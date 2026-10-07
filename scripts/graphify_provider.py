"""
Graphify Optional Enrichment Provider for MxAgile Knowledge Graph (Phase 3)

Loads and adapts the Graphify code graph (graphify-out/graph.json) as an
optional OVERLAY on top of the native artifact index.

Authority hierarchy:
  CANONICAL (artifact-index) > EXTRACTED (Graphify AST) > INFERRED (Graphify LLM)

Graphify MUST NOT:
  - Replace the native artifact index
  - Become canonical project truth
  - Become a mandatory dependency
  - Block any lifecycle operation

When Graphify is DISABLED or unavailable, all operations return empty overlay results.

Configuration (.mxagile/config.yaml):
  enrichment_provider: graphify
  graphify:
    enabled: true
    output_dir: graphify-out
    local_only: true
    incremental: true
    version_constraint: ">=0.9.28"
"""

import json
import os
import re
import subprocess
import sys
import hashlib
import datetime
from collections import deque
from pathlib import Path


# Provenance tiers for enrichment overlay edges
PROVENANCE_EXTRACTED = 'EXTRACTED'   # AST / structural code analysis (local, deterministic)
PROVENANCE_INFERRED  = 'INFERRED'    # LLM semantic analysis (may require opt-in)
PROVENANCE_DUPLICATE = 'DUPLICATE'   # already present in canonical artifact-index

# State constants (mirrors native graph states relevant to enrichment)
STATE_DISABLED = 'DISABLED'
STATE_MISSING  = 'MISSING'
STATE_READY    = 'READY'
STATE_STALE    = 'STALE'
STATE_FAILED   = 'FAILED'

# MxAgile canonical artifact ID pattern
_ARTIFACT_ID_PATTERN = re.compile(
    r'\b(REQ|SPEC|TASK|DEC|PAGE|SCN|TC|VPP|FLOW|FLOWSTEP|GAP|PP|VPL|EVIDENCE)-\d{3,}\b'
)

# Graphify code-structural edge types (AST-derived → EXTRACTED provenance)
_CODE_EDGE_TYPES = frozenset([
    'calls', 'imports', 'defines', 'inherits', 'uses', 'references',
    'instantiates', 'decorates', 'returns', 'raises', 'implements',
    'overrides', 'extends', 'depends_on',
])


class GraphifyProvider:
    """
    Optional Graphify enrichment overlay adapter.

    Every public method is fail-safe: returns empty / disabled result
    rather than raising when Graphify is unavailable or misconfigured.

    This class is intentionally read-only with respect to canonical artifacts.
    It may only write to the graphify output directory.
    """

    def __init__(self, project_root='.', config=None):
        self._root  = Path(project_root).resolve()
        self._cfg   = config or self._read_config()
        self._graph = None   # lazily loaded from graph.json

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def load(self):
        """
        Load graph.json into memory.

        Returns:
          dict: success, node_count, link_count, error
        """
        if not self._is_enabled():
            return {'success': False, 'node_count': 0, 'link_count': 0,
                    'error': 'Graphify enrichment provider is not enabled'}

        graph_path = self._graph_path()
        if not graph_path.exists():
            return {'success': False, 'node_count': 0, 'link_count': 0,
                    'error': f'graph.json not found at {graph_path} — run build() first'}

        try:
            with open(graph_path, 'r', encoding='utf-8') as f:
                self._graph = json.load(f)
            nodes = self._graph.get('nodes', [])
            links = self._graph.get('links', [])
            return {'success': True, 'node_count': len(nodes), 'link_count': len(links), 'error': None}
        except Exception as e:
            self._graph = None
            return {'success': False, 'node_count': 0, 'link_count': 0, 'error': str(e)}

    def status(self):
        """
        Return current Graphify provider status.

        Returns:
          dict: status, enabled, graph_path, node_count, link_count,
                last_built, is_stale
        """
        if not self._is_enabled():
            return {
                'status':  STATE_DISABLED,
                'enabled': False,
                'reason':  'enrichment_provider is not graphify or graphify.enabled is false',
            }

        graph_path = self._graph_path()
        if not graph_path.exists():
            return {'status': STATE_MISSING, 'enabled': True,
                    'graph_path': str(graph_path), 'reason': 'graph.json not found'}

        try:
            with open(graph_path, 'r', encoding='utf-8') as f:
                graph_data = json.load(f)
        except Exception as e:
            return {'status': STATE_FAILED, 'enabled': True,
                    'graph_path': str(graph_path), 'error': str(e)}

        nodes      = graph_data.get('nodes', [])
        links      = graph_data.get('links', [])
        is_stale   = self._is_stale()
        mtime      = os.path.getmtime(graph_path)
        last_built = datetime.datetime.fromtimestamp(mtime).isoformat()

        return {
            'status':     STATE_STALE if is_stale else STATE_READY,
            'enabled':    True,
            'graph_path': str(graph_path),
            'node_count': len(nodes),
            'link_count': len(links),
            'last_built': last_built,
            'is_stale':   is_stale,
        }

    def neighbors_overlay(self, node_id, canonical_neighbors=None):
        """
        Return enrichment-only neighbors not already in the canonical artifact index.

        Args:
          node_id:             node ID to look up
          canonical_neighbors: set of node IDs already known to native graph

        Returns:
          list of {node_id, label, edge_type, provenance, enrichment_only}
        """
        if not self._ensure_loaded():
            return []

        canonical = set(canonical_neighbors or [])
        results   = []
        seen      = set()

        for link in self._graph.get('links', []):
            src = link.get('source') or link.get('from', '')
            tgt = link.get('target') or link.get('to', '')
            if src != node_id and tgt != node_id:
                continue

            neighbor_id = tgt if src == node_id else src
            if neighbor_id in canonical or neighbor_id in seen:
                continue
            seen.add(neighbor_id)

            edge_type  = link.get('key') or link.get('type') or link.get('label') or 'related_to'
            provenance = self._classify_link_provenance(link)

            results.append({
                'node_id':         neighbor_id,
                'label':           self._node_label(neighbor_id),
                'edge_type':       edge_type,
                'provenance':      provenance,
                'enrichment_only': True,
            })

        return results

    def affected_candidates(self, changed_ids, canonical_affected=None):
        """
        Return enrichment-based affected candidates via BFS on code graph.

        Args:
          changed_ids:        list of canonical artifact IDs that changed
          canonical_affected: set of IDs already known to native affected()

        Returns:
          list of {id, label, distance, provenance, enrichment_only}, sorted by distance
        """
        if not self._ensure_loaded():
            return []

        canonical   = set(canonical_affected or [])
        changed_set = set(changed_ids)
        results     = []
        seen        = set()

        # Build forward adjacency from Graphify graph
        adj = {}
        for link in self._graph.get('links', []):
            src = link.get('source') or link.get('from', '')
            tgt = link.get('target') or link.get('to', '')
            if src not in adj:
                adj[src] = []
            adj[src].append((tgt, link))

        queue = deque()
        for cid in changed_ids:
            queue.append((cid, 0))

        while queue:
            node_id, dist = queue.popleft()
            if node_id in seen:
                continue
            seen.add(node_id)

            if dist > 0 and node_id not in changed_set and node_id not in canonical:
                results.append({
                    'id':              node_id,
                    'label':           self._node_label(node_id),
                    'distance':        dist,
                    'provenance':      PROVENANCE_EXTRACTED,
                    'enrichment_only': True,
                })

            if dist < 5:
                for (next_id, _link) in adj.get(node_id, []):
                    if next_id not in seen:
                        queue.append((next_id, dist + 1))

        return sorted(results, key=lambda x: x['distance'])

    def find_unlinked_artifacts(self, canonical_node_ids):
        """
        Find artifact IDs referenced in Graphify's code graph that are NOT
        in the canonical index — the "dark matter" relationships.

        Scans all Graphify node and link attributes for MxAgile ID patterns.

        Args:
          canonical_node_ids: set/list of IDs known to the native artifact index

        Returns:
          list of {id, label, discovered_in, provenance}
        """
        if not self._ensure_loaded():
            return []

        canonical = set(canonical_node_ids)
        results   = []
        seen      = set()

        def _add_if_new(ref_id, discovered_in, prov):
            if ref_id not in seen and ref_id not in canonical:
                seen.add(ref_id)
                results.append({
                    'id':           ref_id,
                    'label':        self._node_label(ref_id),
                    'discovered_in': discovered_in,
                    'provenance':   prov,
                })

        # Scan node IDs and all node attributes
        for node in self._graph.get('nodes', []):
            node_id  = node.get('id', '')
            node_str = json.dumps(node)
            for match in _ARTIFACT_ID_PATTERN.finditer(node_str):
                _add_if_new(match.group(0), f'node_property:{node_id}', PROVENANCE_INFERRED)

        # Scan link endpoints and attributes
        for link in self._graph.get('links', []):
            link_str = json.dumps(link)
            for match in _ARTIFACT_ID_PATTERN.finditer(link_str):
                _add_if_new(match.group(0), 'link_attribute', PROVENANCE_EXTRACTED)

        return results

    def classify_edges(self, canonical_edge_pairs=None):
        """
        Classify all Graphify edges by provenance tier and canonical overlap.

        Args:
          canonical_edge_pairs: set of (from_id, to_id) tuples in canonical graph

        Returns:
          dict: extracted[], inferred[], duplicate[], total, enrichment_count
        """
        if not self._ensure_loaded():
            return {'extracted': [], 'inferred': [], 'duplicate': [],
                    'total': 0, 'enrichment_count': 0}

        canonical_pairs = set(canonical_edge_pairs or [])
        extracted = []
        inferred  = []
        duplicate = []

        for link in self._graph.get('links', []):
            src       = link.get('source') or link.get('from', '')
            tgt       = link.get('target') or link.get('to', '')
            edge_type = link.get('key') or link.get('type') or link.get('label') or 'related_to'

            record = {'from': src, 'to': tgt, 'edge_type': edge_type, 'raw': link}

            if (src, tgt) in canonical_pairs:
                duplicate.append(record)
            elif self._is_code_edge(link):
                extracted.append(record)
            else:
                inferred.append(record)

        total = len(extracted) + len(inferred) + len(duplicate)
        return {
            'extracted':        extracted,
            'inferred':         inferred,
            'duplicate':        duplicate,
            'total':            total,
            'enrichment_count': len(extracted) + len(inferred),
        }

    def verify_no_canonical_conflict(self, canonical_nodes, canonical_edges):
        """
        Safety invariant check: Graphify overlay must not contradict canonical facts.

        Checks:
          1. No Graphify node claims same ID as canonical node but different type
          2. Graphify output_dir is not inside any canonical source directory

        Returns:
          dict: safe, conflicts[], warnings[]
        """
        if not self._ensure_loaded():
            return {'safe': True, 'conflicts': [],
                    'warnings': ['Graphify not loaded — conflict check skipped']}

        conflicts = []
        warnings  = []

        canonical_node_map = {n.get('id'): n for n in canonical_nodes if n.get('id')}

        for g_node in self._graph.get('nodes', []):
            g_id   = g_node.get('id', '')
            g_type = (g_node.get('type') or g_node.get('label') or '').lower()
            if g_id in canonical_node_map:
                c_type = canonical_node_map[g_id].get('type', '').lower()
                if c_type and g_type and c_type != g_type:
                    conflicts.append({
                        'type':           'type_mismatch',
                        'node_id':         g_id,
                        'canonical_type': c_type,
                        'graphify_type':  g_type,
                        'message': f'Node {g_id}: canonical={c_type}, graphify={g_type}',
                    })

        output_dir = self._output_dir()
        for cdir_name in ('requirements', 'specs', 'planning', '.mxagile', 'input-resources'):
            cdir = self._root / cdir_name
            try:
                output_dir.relative_to(cdir)
                conflicts.append({
                    'type':    'output_dir_in_canonical',
                    'message': f'graphify output_dir {output_dir} is inside canonical dir {cdir}',
                })
            except ValueError:
                pass

        return {'safe': len(conflicts) == 0, 'conflicts': conflicts, 'warnings': warnings}

    def build(self, incremental=True):
        """
        Run Graphify to build/update the code graph.

        Uses 'graphify update <path>' for incremental (AST only, no LLM),
        or 'graphify <path>' for full initial build.

        local_only=true strips external API keys from the environment.

        Scope fingerprint safety: if .graphifyignore has changed since the last
        build, graphify-out/ is wiped before rebuilding. This prevents stale
        broad-scope nodes (retained by Graphify's fail-closed mechanism) from
        silently masquerading as a targeted graph.

        Returns:
          dict: success, returncode, stdout, stderr, duration_s
        """
        if not self._is_enabled():
            return {'success': False, 'returncode': -1,
                    'stdout': '', 'stderr': 'Graphify not enabled', 'duration_s': 0.0}

        import time
        import shutil
        start = time.time()

        # ── Scope fingerprint check ──────────────────────────────────────────
        # If .graphifyignore changed, wipe graphify-out/ so fail-closed retention
        # does not carry over nodes that should now be excluded.
        current_scope_fp = self._compute_scope_fingerprint()
        stored_scope_fp  = self._read_stored_scope_fingerprint()
        output_dir       = self._output_dir()

        if stored_scope_fp is not None and current_scope_fp != stored_scope_fp:
            if output_dir.exists():
                shutil.rmtree(output_dir)
            incremental = False   # scope changed → full rebuild

        output_dir.mkdir(parents=True, exist_ok=True)

        local_only = self._cfg.get('graphify', {}).get('local_only', True)

        env = dict(os.environ)
        if local_only:
            for key in ('GEMINI_API_KEY', 'OPENAI_API_KEY', 'ANTHROPIC_API_KEY',
                        'GOOGLE_API_KEY', 'COHERE_API_KEY', 'GEMINI_KEY'):
                env.pop(key, None)

        if incremental:
            cmd = ['graphify', 'update', str(self._root)]
        else:
            cmd = ['graphify', str(self._root)]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300,
                env=env,
                cwd=str(self._root),
            )
            duration  = time.time() - start
            self._graph = None   # invalidate cache

            # A non-zero exit for "nothing to process" is not a failure
            success = result.returncode == 0
            if not success and result.stderr:
                stderr_lower = result.stderr.lower()
                if any(x in stderr_lower for x in ('no files', 'nothing to process', 'no python')):
                    success = True

            if success:
                self._write_scope_fingerprint(current_scope_fp)

            return {
                'success':    success,
                'returncode': result.returncode,
                'stdout':     result.stdout,
                'stderr':     result.stderr,
                'duration_s': round(duration, 2),
            }
        except FileNotFoundError:
            return {
                'success': False, 'returncode': -1, 'stdout': '',
                'stderr': 'graphify not found — install with: uv tool install graphifyy',
                'duration_s': round(time.time() - start, 2),
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False, 'returncode': -1, 'stdout': '',
                'stderr': 'graphify timed out after 300s',
                'duration_s': round(time.time() - start, 2),
            }
        except Exception as e:
            return {
                'success': False, 'returncode': -1, 'stdout': '',
                'stderr': str(e),
                'duration_s': round(time.time() - start, 2),
            }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _read_config(self):
        config_path = self._root / '.mxagile' / 'config.yaml'
        if config_path.exists():
            try:
                import yaml
                with open(config_path, 'r', encoding='utf-8') as f:
                    return yaml.safe_load(f) or {}
            except Exception:
                pass
        return {}

    def _is_enabled(self):
        enrichment = self._cfg.get('enrichment_provider', 'none')
        if enrichment != 'graphify':
            return False
        return bool(self._cfg.get('graphify', {}).get('enabled', False))

    def _output_dir(self):
        out = self._cfg.get('graphify', {}).get('output_dir', 'graphify-out')
        p   = Path(out)
        return p if p.is_absolute() else self._root / p

    def _graph_path(self):
        return self._output_dir() / 'graph.json'

    def _ensure_loaded(self):
        if not self._is_enabled():
            return False
        if self._graph is not None:
            return True
        return self.load().get('success', False)

    def _node_label(self, node_id):
        if self._graph is None:
            return node_id
        for node in self._graph.get('nodes', []):
            if node.get('id') == node_id:
                return node.get('label') or node.get('name') or node_id
        return node_id

    def _is_code_edge(self, link):
        edge_type = (link.get('key') or link.get('type') or link.get('label') or '').lower()
        return edge_type in _CODE_EDGE_TYPES

    def _classify_link_provenance(self, link):
        return PROVENANCE_EXTRACTED if self._is_code_edge(link) else PROVENANCE_INFERRED

    def _compute_scope_fingerprint(self):
        ignore_path = self._root / '.graphifyignore'
        content = ignore_path.read_text(encoding='utf-8') if ignore_path.exists() else ''
        return hashlib.sha256(content.encode('utf-8')).hexdigest()

    def _state_path(self):
        return self._root / '.mxagile' / 'state' / 'graphify-state.yaml'

    def _read_stored_scope_fingerprint(self):
        state_path = self._state_path()
        if not state_path.exists():
            return None
        try:
            import yaml
            with open(state_path, 'r', encoding='utf-8') as f:
                state = yaml.safe_load(f) or {}
            return state.get('scope_fingerprint')
        except Exception:
            return None

    def _write_scope_fingerprint(self, fingerprint):
        state_path = self._state_path()
        if not state_path.exists():
            return
        try:
            import yaml
            with open(state_path, 'r', encoding='utf-8') as f:
                state = yaml.safe_load(f) or {}
            state['scope_fingerprint'] = fingerprint
            with open(state_path, 'w', encoding='utf-8') as f:
                yaml.dump(state, f, default_flow_style=False, allow_unicode=True)
        except Exception:
            pass   # non-fatal: fingerprint persistence failure does not block build

    def _is_stale(self):
        graph_path = self._graph_path()
        if not graph_path.exists():
            return True
        graph_mtime = os.path.getmtime(graph_path)
        check_dirs  = [self._root / d for d in ('src', 'scripts', 'docs')]
        exts        = {'.py', '.ts', '.js', '.go', '.java'}
        for d in check_dirs:
            if not d.exists():
                continue
            for f in d.rglob('*'):
                if f.suffix in exts and '.mxagile' not in str(f) and 'graphify-out' not in str(f):
                    try:
                        if os.path.getmtime(f) > graph_mtime:
                            return True
                    except OSError:
                        pass
        return False
