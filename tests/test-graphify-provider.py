"""
tests/test-graphify-provider.py
Pytest test suite for GraphifyProvider (scripts/graphify_provider.py).

Covers:
  T1 — DISABLED (default config)
  T2 — MISSING  (enabled but no graph.json)
  T3 — READY    (enabled + graph.json present)
  T4 — OVERLAY authority (enrichment never overrides canonical)
  T5 — FIND_UNLINKED (artifact ID discovery)
  T6 — CONFLICT CHECK
  T7 — SECURITY (local_only API key stripping)
  T8 — PILOT FIXTURE INTEGRATION

Run:  pytest tests/test-graphify-provider.py -v
"""
import json
import os
import re
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ─── Ensure scripts/ is importable ────────────────────────────────────────────

TESTS_DIR = Path(__file__).resolve().parent
ROOT      = TESTS_DIR.parent
SCRIPTS   = ROOT / 'scripts'
sys.path.insert(0, str(SCRIPTS))

from graphify_provider import GraphifyProvider  # noqa: E402

# Path to the pre-built pilot fixture (used by T8)
PILOT_GRAPH_PATH = TESTS_DIR / 'fixtures' / 'graphify-pilot' / 'graphify-out' / 'graph.json'


# ─── Helpers ──────────────────────────────────────────────────────────────────

def make_config(enabled=False, output_dir='graphify-out', local_only=True,
                version_constraint='0.9.28'):
    """Return a config dict for GraphifyProvider."""
    return {
        'enrichment_provider': 'graphify' if enabled else 'none',
        'graphify': {
            'enabled': enabled,
            'output_dir': output_dir,
            'local_only': local_only,
            'version_constraint': version_constraint,
        },
    }


def make_provider(tmp_dir, enabled=False, graph_json=None,
                  output_dir='graphify-out', local_only=True):
    """
    Create an isolated GraphifyProvider rooted at tmp_dir.

    1. Writes .mxagile/config.yaml with appropriate settings.
    2. If graph_json is provided, writes it to <output_dir>/graph.json.
    3. Returns GraphifyProvider(project_root=tmp_dir, config=<dict>).
    """
    tmp_path   = Path(tmp_dir)
    mxagile_dir = tmp_path / '.mxagile'
    mxagile_dir.mkdir(parents=True, exist_ok=True)

    config = make_config(enabled=enabled, output_dir=output_dir, local_only=local_only)

    # Write a minimal config.yaml (plain YAML, no external library needed)
    cfg_yaml = '\n'.join([
        f"enrichment_provider: {'graphify' if enabled else 'none'}",
        'graphify:',
        f"  enabled: {'true' if enabled else 'false'}",
        f"  output_dir: {output_dir}",
        f"  local_only: {'true' if local_only else 'false'}",
        "  version_constraint: '0.9.28'",
    ])
    (mxagile_dir / 'config.yaml').write_text(cfg_yaml, encoding='utf-8')

    if graph_json is not None:
        out_dir = tmp_path / output_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / 'graph.json').write_text(
            json.dumps(graph_json), encoding='utf-8'
        )

    return GraphifyProvider(project_root=str(tmp_path), config=config)


# ─── Reusable inline graph fixtures ───────────────────────────────────────────

#  Three nodes, two code edges (calls + imports).
#  Uses "type" field so _is_code_edge() classifies them as EXTRACTED.
MINI_GRAPH = {
    'directed': False, 'multigraph': False, 'graph': {},
    'nodes': [
        {'id': 'mod_a',  'label': 'module_a.py', 'type': 'module',   'file_type': 'code', '_origin': 'ast'},
        {'id': 'mod_b',  'label': 'module_b.py', 'type': 'module',   'file_type': 'code', '_origin': 'ast'},
        {'id': 'func_x', 'label': 'func_x()',    'type': 'function', 'file_type': 'code', '_origin': 'ast'},
    ],
    'links': [
        {'source': 'mod_a', 'target': 'func_x', 'type': 'calls',   'confidence': 'EXTRACTED', '_origin': 'ast', 'weight': 1.0},
        {'source': 'mod_a', 'target': 'mod_b',  'type': 'imports', 'confidence': 'EXTRACTED', '_origin': 'ast', 'weight': 1.0},
    ],
    'hyperedges': [],
}

#  Rationale node whose label embeds MxAgile artifact IDs.
RATIONALE_GRAPH = {
    'directed': False, 'multigraph': False, 'graph': {},
    'nodes': [
        {'id': 'func_y',      'label': 'func_y()',
         'file_type': 'code',      '_origin': 'ast'},
        {'id': 'rationale_1', 'label': 'Implements: REQ-001 (User Auth). See SPEC-002.',
         'file_type': 'rationale', '_origin': 'ast'},
    ],
    'links': [
        {'source': 'rationale_1', 'target': 'func_y',
         'type': 'rationale_for', 'confidence': 'EXTRACTED', '_origin': 'ast', 'weight': 1.0},
    ],
    'hyperedges': [],
}

_ARTIFACT_PATTERN = re.compile(
    r'^(REQ|SPEC|TASK|DEC|PAGE|SCN|TC|VPP|FLOW|FLOWSTEP|GAP|PP|VPL|EVIDENCE)-\d{3,}$'
)


# ══════════════════════════════════════════════════════════════════════════════
# T1 — DISABLED (default config)
# ══════════════════════════════════════════════════════════════════════════════

class TestDisabled:
    """Provider with enrichment_provider=none must be fully inert."""

    def test_load_returns_not_enabled(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=False)
        result = p.load()
        assert result['success'] is False
        assert 'not enabled' in (result.get('error') or '').lower()

    def test_status_disabled(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=False)
        s = p.status()
        assert s['status'] == 'DISABLED'
        assert s['enabled'] is False

    def test_neighbors_overlay_returns_empty(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=False)
        assert p.neighbors_overlay('x') == []

    def test_affected_candidates_returns_empty(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=False)
        assert p.affected_candidates(['x']) == []

    def test_find_unlinked_artifacts_returns_empty(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=False)
        assert p.find_unlinked_artifacts([]) == []


# ══════════════════════════════════════════════════════════════════════════════
# T2 — MISSING (enabled but no graph.json)
# ══════════════════════════════════════════════════════════════════════════════

class TestMissing:
    """Enabled provider with no graph.json on disk."""

    def test_status_missing(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=None)
        s = p.status()
        assert s['status'] == 'MISSING'

    def test_load_error_contains_not_found(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=None)
        result = p.load()
        assert result['success'] is False
        assert 'not found' in (result.get('error') or '').lower()

    def test_classify_edges_zero_total(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=None)
        r = p.classify_edges()
        assert r['total'] == 0

    def test_verify_no_conflict_safe_without_graph(self, tmp_path):
        # _ensure_loaded returns False → early-return path with safe=True
        p = make_provider(str(tmp_path), enabled=True, graph_json=None)
        r = p.verify_no_canonical_conflict([], [])
        assert r['safe'] is True


# ══════════════════════════════════════════════════════════════════════════════
# T3 — READY (enabled + graph.json present)
# ══════════════════════════════════════════════════════════════════════════════

class TestReady:
    """Provider with MINI_GRAPH (3 nodes, 2 code edges) loaded."""

    def test_load_success_with_counts(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        result = p.load()
        assert result['success'] is True
        assert result['node_count'] == 3
        assert result['link_count'] == 2

    def test_status_ready_or_stale(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        s = p.status()
        assert s['status'] in ('READY', 'STALE')

    def test_neighbors_overlay_returns_all_when_no_canonical(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        results = p.neighbors_overlay('mod_a', canonical_neighbors=set())
        assert len(results) == 2

    def test_neighbors_overlay_empty_when_all_canonical(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        results = p.neighbors_overlay('mod_a', canonical_neighbors={'func_x', 'mod_b'})
        assert len(results) == 0

    def test_classify_edges_extracted_code_types(self, tmp_path):
        # calls + imports are in _CODE_EDGE_TYPES → both classified as extracted
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        r = p.classify_edges()
        assert r['total'] == 2
        assert len(r['extracted']) == 2

    def test_verify_no_conflict_empty_canonical(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        r = p.verify_no_canonical_conflict([], [])
        assert r['safe'] is True


# ══════════════════════════════════════════════════════════════════════════════
# T4 — OVERLAY authority (enrichment never overrides canonical)
# ══════════════════════════════════════════════════════════════════════════════

class TestOverlayAuthority:
    """Canonical neighbors are always filtered from enrichment results."""

    def test_neighbors_overlay_filters_canonical_neighbor(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        results = p.neighbors_overlay('mod_a', canonical_neighbors={'mod_b'})
        ids = [r['node_id'] for r in results]
        assert 'func_x' in ids
        assert 'mod_b' not in ids

    def test_neighbors_overlay_enrichment_only_flag(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        results = p.neighbors_overlay('mod_a', canonical_neighbors=set())
        assert len(results) > 0
        assert all(r['enrichment_only'] is True for r in results)

    def test_neighbors_overlay_provenance_field_present(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        results = p.neighbors_overlay('mod_a', canonical_neighbors=set())
        for r in results:
            assert 'provenance' in r
            assert r['provenance'] in ('EXTRACTED', 'INFERRED')

    def test_affected_candidates_excludes_canonical_affected(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        # func_x is already known canonical-affected; only mod_b is enrichment-only
        results = p.affected_candidates(['mod_a'], canonical_affected={'func_x'})
        ids = [r['id'] for r in results]
        assert 'mod_b' in ids
        assert 'func_x' not in ids

    def test_affected_candidates_empty_when_all_canonical(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        results = p.affected_candidates(['mod_a'], canonical_affected={'mod_b', 'func_x'})
        assert results == []


# ══════════════════════════════════════════════════════════════════════════════
# T5 — FIND_UNLINKED (artifact ID discovery)
# ══════════════════════════════════════════════════════════════════════════════

class TestFindUnlinked:
    """Artifact IDs embedded in graph content are surfaced as dark-matter links."""

    def test_finds_both_artifact_ids(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=RATIONALE_GRAPH)
        results = p.find_unlinked_artifacts([])
        ids = [r['id'] for r in results]
        assert 'REQ-001' in ids
        assert 'SPEC-002' in ids

    def test_excludes_already_canonical_id(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=RATIONALE_GRAPH)
        results = p.find_unlinked_artifacts(['REQ-001'])
        ids = [r['id'] for r in results]
        assert 'REQ-001' not in ids
        assert 'SPEC-002' in ids

    def test_items_have_provenance_field(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=RATIONALE_GRAPH)
        results = p.find_unlinked_artifacts([])
        assert len(results) > 0
        for r in results:
            assert 'provenance' in r

    def test_items_id_matches_artifact_pattern(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=RATIONALE_GRAPH)
        results = p.find_unlinked_artifacts([])
        assert len(results) > 0
        for r in results:
            assert _ARTIFACT_PATTERN.match(r['id']), (
                f"id {r['id']!r} does not match MxAgile artifact ID pattern"
            )


# ══════════════════════════════════════════════════════════════════════════════
# T6 — CONFLICT CHECK
# ══════════════════════════════════════════════════════════════════════════════

class TestConflictCheck:
    """verify_no_canonical_conflict detects type mismatches and bad output paths."""

    def test_safe_when_canonical_types_match(self, tmp_path):
        # MINI_GRAPH mod_a has type='module'; canonical also says 'module' → no conflict
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        r = p.verify_no_canonical_conflict([{'id': 'mod_a', 'type': 'module'}], [])
        assert r['safe'] is True

    def test_conflict_output_dir_inside_requirements(self, tmp_path):
        # output_dir nested under requirements/ is a canonical-dir violation
        p = make_provider(
            str(tmp_path), enabled=True, graph_json=MINI_GRAPH,
            output_dir='requirements/graphify-out',
        )
        r = p.verify_no_canonical_conflict([], [])
        assert r['safe'] is False
        assert len(r['conflicts']) > 0

    def test_conflict_type_mismatch(self, tmp_path):
        # MINI_GRAPH mod_a has type='module'; canonical claims 'requirement' → conflict
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        r = p.verify_no_canonical_conflict([{'id': 'mod_a', 'type': 'requirement'}], [])
        assert r['safe'] is False
        assert any(c.get('type') == 'type_mismatch' for c in r['conflicts'])


# ══════════════════════════════════════════════════════════════════════════════
# T7 — SECURITY (local_only API key stripping)
# ══════════════════════════════════════════════════════════════════════════════

class TestSecurity:
    """build() must strip external API keys when local_only=True."""

    def _fake_run(self, captured_env):
        """Factory for a subprocess.run replacement that records env."""
        def _inner(cmd, **kwargs):
            captured_env.clear()
            captured_env.update(kwargs.get('env', {}))
            m = MagicMock()
            m.returncode = 0
            m.stdout = ''
            m.stderr = ''
            return m
        return _inner

    def test_local_only_strips_api_keys(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH, local_only=True)
        captured: dict = {}

        secret_env = {
            'GEMINI_API_KEY':    'gemini-secret',
            'OPENAI_API_KEY':    'openai-secret',
            'ANTHROPIC_API_KEY': 'anthropic-secret',
            'GOOGLE_API_KEY':    'google-secret',
            'COHERE_API_KEY':    'cohere-secret',
        }
        with patch.dict(os.environ, secret_env):
            with patch('subprocess.run', side_effect=self._fake_run(captured)):
                p.build()

        assert 'GEMINI_API_KEY'    not in captured
        assert 'OPENAI_API_KEY'    not in captured
        assert 'ANTHROPIC_API_KEY' not in captured

    def test_local_only_false_preserves_env(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH, local_only=False)
        captured: dict = {}

        with patch.dict(os.environ, {'SOME_CUSTOM_VAR': 'should-survive'}):
            with patch('subprocess.run', side_effect=self._fake_run(captured)):
                p.build()

        assert 'SOME_CUSTOM_VAR' in captured

    def test_build_file_not_found_returns_failure_dict(self, tmp_path):
        p = make_provider(str(tmp_path), enabled=True, graph_json=MINI_GRAPH)
        with patch('subprocess.run', side_effect=FileNotFoundError('graphify not found')):
            result = p.build()

        assert isinstance(result, dict)
        assert result['success'] is False
        assert 'graphify' in (result.get('stderr') or '').lower()


# ══════════════════════════════════════════════════════════════════════════════
# T8 — PILOT FIXTURE INTEGRATION
# ══════════════════════════════════════════════════════════════════════════════

_pilot_skip = pytest.mark.skipif(
    not PILOT_GRAPH_PATH.exists(),
    reason='Pilot graph fixture not found — run graphify update in tests/fixtures/graphify-pilot first',
)


@_pilot_skip
class TestPilotFixture:
    """
    Integration tests against the real pre-built graphify-pilot graph.

    Asserts structural properties of the 31-node / 36-edge pilot graph
    without mutating any project files.
    """

    def _provider(self):
        """Return a provider pointed at the actual pilot graph output dir."""
        pilot_root    = PILOT_GRAPH_PATH.parent.parent          # tests/fixtures/graphify-pilot
        pilot_out_dir = str(PILOT_GRAPH_PATH.parent)            # …/graphify-out
        cfg = make_config(enabled=True, output_dir=pilot_out_dir)
        return GraphifyProvider(project_root=str(pilot_root), config=cfg)

    def test_load_pilot_counts(self, tmp_path):
        p = self._provider()
        result = p.load()
        assert result['success'] is True
        assert result['node_count'] >= 31
        assert result['link_count'] >= 36

    def test_classify_edges_enrichment_count(self, tmp_path):
        p = self._provider()
        p.load()
        r = p.classify_edges()
        # All edges are enrichment (none are in canonical artifact pairs)
        assert r['enrichment_count'] > 0
        assert r['total'] >= 36

    def test_find_unlinked_finds_artifact_references(self, tmp_path):
        p = self._provider()
        p.load()
        results = p.find_unlinked_artifacts([])
        ids = [r['id'] for r in results]
        # Rationale nodes in the pilot contain REQ-001 and/or REQ-002
        assert any(aid in ids for aid in ('REQ-001', 'REQ-002'))

    def test_neighbors_overlay_src_auth_has_neighbors(self, tmp_path):
        p = self._provider()
        p.load()
        results = p.neighbors_overlay('src_auth', canonical_neighbors=set())
        assert len(results) > 0

    def test_verify_no_conflict_pilot_is_clean(self, tmp_path):
        p = self._provider()
        p.load()
        r = p.verify_no_canonical_conflict([], [])
        assert r['safe'] is True
