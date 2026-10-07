"""
MxAgile Impact Resolver

Resolves a structured identifier (PAGE-NNN, REQ-NNN, SPEC-NNN, or mockup bundle name)
to its related canonical artifacts using the artifact index.

Usage:
  python scripts/resolve_impact.py [--path <project_root>] <identifier>
  python scripts/resolve_impact.py [--path <project_root>] --mockup <mockup_name>
  python scripts/resolve_impact.py [--path <project_root>] --json <identifier>

Examples:
  python scripts/resolve_impact.py PAGE-CALENDAR
  python scripts/resolve_impact.py REQ-034
  python scripts/resolve_impact.py SPEC-012
  python scripts/resolve_impact.py --mockup demo-application
  python scripts/resolve_impact.py --json PAGE-CALENDAR  (structured JSON output)

Output: structured resolution result with requirements, specs, scenarios, pages, warnings.

This resolver returns FACTS AND CANDIDATES. It does NOT decide:
  - Which Requirement to mutate
  - Whether something is a new Requirement
  - Whether product intent changed

Those remain agent/refinement reasoning decisions per policies/impact-resolution.md.

Index validity: the resolver checks the source_fingerprint of the index against the
current canonical artifact files. If stale, it rebuilds the index before querying.
If rebuild is unavailable, it falls back to direct canonical file traversal.
"""

import json
import os
import sys
import argparse
import subprocess
import hashlib
import yaml
from pathlib import Path
from collections import defaultdict


# ---------------------------------------------------------------------------
# Index loading + validity
# ---------------------------------------------------------------------------

def _index_path(project_root):
    return Path(project_root) / '.mxagile' / 'state' / 'artifact-index.json'


def _compute_current_fingerprint(project_root):
    """
    Compute the source fingerprint of the current canonical artifact files.
    Used to detect whether the stored index is stale.

    Must stay in sync with the same algorithm in:
      scripts/build_artifact_index.py  compute_source_fingerprint()
      scripts/graph_capability.py      _compute_current_fingerprint()
    """
    artifact_locations = [
        ('requirements',                '*.yml'),
        ('specs',                       '*.yml'),
        ('planning/tasks',              '*.yml'),
        ('planning/ui-inventory',       '*.yaml'),
        ('planning/scenarios',          '*.yaml'),
        ('planning/test-contracts',     '*.yaml'),
        ('planning/verification-plans', '*.yaml'),
        ('planning/decisions',          '*.yml'),
    ]
    entries = []
    root = Path(project_root)
    for rel_dir, pattern in artifact_locations:
        d = root / rel_dir
        if d.exists():
            for f in sorted(d.glob(pattern)):
                rel = str(f.relative_to(root)).replace('\\', '/')
                sha = hashlib.sha256(f.read_bytes()).hexdigest()
                entries.append((rel, sha))

    # Revision artifacts
    target_dir = root / 'planning' / 'target-mockups'
    if target_dir.exists():
        for mockup_dir in sorted(target_dir.iterdir()):
            history_dir = mockup_dir / '_history'
            if history_dir.exists():
                for rev_dir in sorted(history_dir.iterdir()):
                    rev_file = rev_dir / 'revision.yaml'
                    if rev_file.exists():
                        rel = str(rev_file.relative_to(root)).replace('\\', '/')
                        sha = hashlib.sha256(rev_file.read_bytes()).hexdigest()
                        entries.append((rel, sha))

    entries.sort(key=lambda x: x[0])
    manifest = '\n'.join(f'{p}:{h}' for p, h in entries)
    fp = hashlib.sha256(manifest.encode('utf-8')).hexdigest()
    return f'sha256:{fp}'


def _try_rebuild(project_root):
    """Attempt to rebuild the index via build_artifact_index.py."""
    script = Path(__file__).parent / 'build_artifact_index.py'
    if not script.exists():
        return False
    try:
        result = subprocess.run(
            [sys.executable, str(script), str(project_root)],
            capture_output=True, text=True, timeout=60
        )
        return result.returncode == 0
    except Exception:
        return False


def load_index(project_root):
    """
    Load and validate the artifact index.

    Validity check: compare stored source_fingerprint against current canonical files.
    If stale: attempt rebuild. If rebuild fails: fall back to None (caller uses direct traversal).

    Returns (data, warnings) where data is None if index unavailable.
    """
    idx_path = _index_path(project_root)
    warnings = []

    if not idx_path.exists():
        warnings.append('artifact-index.json not found — attempting rebuild')
        if _try_rebuild(project_root):
            warnings.append('Index rebuilt successfully')
        else:
            warnings.append('Index rebuild failed — using direct canonical traversal')
            return None, warnings

    try:
        with open(idx_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        warnings.append(f'Failed to read artifact-index.json: {e}')
        return None, warnings

    stored_fp = data.get('source_fingerprint')
    if stored_fp:
        current_fp = _compute_current_fingerprint(project_root)
        if stored_fp != current_fp:
            warnings.append(f'Index is stale (fingerprint mismatch) — rebuilding')
            if _try_rebuild(project_root):
                warnings.append('Index rebuilt successfully')
                try:
                    with open(idx_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                except Exception as e:
                    warnings.append(f'Failed to read rebuilt index: {e}')
                    return None, warnings
            else:
                warnings.append('Rebuild failed — using stale index (results may be incomplete)')

    return data, warnings


# ---------------------------------------------------------------------------
# Direct canonical traversal (fallback when index is unavailable)
# ---------------------------------------------------------------------------

def _read_yaml(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def direct_resolve_page(project_root, page_id):
    """Direct canonical traversal for Page -> Requirements (no index needed)."""
    root = Path(project_root)
    requirements = []
    scenario_reqs = []

    # Scan requirements/*.yml for derivedFrom + screens
    req_dir = root / 'requirements'
    if req_dir.exists():
        for f in sorted(req_dir.glob('*.yml')):
            content = _read_yaml(f)
            rid = content.get('ID', f.stem)
            if content.get('derivedFrom') == page_id:
                if rid not in requirements:
                    requirements.append(rid)
            screens = content.get('screens', [])
            if isinstance(screens, list) and page_id in screens:
                if rid not in requirements:
                    requirements.append(rid)

    # Scan planning/scenarios/*.yaml for screen_id
    scen_dir = root / 'planning' / 'scenarios'
    if scen_dir.exists():
        for f in sorted(scen_dir.glob('*.yaml')):
            content = _read_yaml(f)
            if content.get('screen_id') == page_id:
                traceability = content.get('traceability', {}) or {}
                for rid in traceability.get('requirements', []):
                    if rid not in scenario_reqs:
                        scenario_reqs.append(rid)

    all_reqs = list(dict.fromkeys(requirements + [r for r in scenario_reqs if r not in requirements]))
    return {
        'requirements': requirements,
        'scenario_requirements': scenario_reqs,
        'all_requirements': all_reqs,
        'source': 'direct_canonical_traversal',
    }


# ---------------------------------------------------------------------------
# Index-based resolution
# ---------------------------------------------------------------------------

def build_lookup_maps(data):
    """Build efficient lookup maps from the index graph."""
    nodes = {n['id']: n for n in data.get('nodes', [])}
    edges = data.get('edges', [])

    page_to_reqs = defaultdict(set)      # derivedFrom (DERIVED_FROM, reverse) + screens (APPLIES_TO, reverse)
    req_to_specs = defaultdict(set)      # IMPLEMENTED_BY Req->Spec
    spec_to_tasks = defaultdict(set)     # IMPLEMENTED_BY Spec->Task
    page_to_scenarios = defaultdict(set) # VERIFIED_BY (reverse)
    scenario_to_reqs = defaultdict(set)  # COVERS
    req_to_pages = defaultdict(set)      # reverse of APPLIES_TO + DERIVED_FROM
    bundle_to_pages = defaultdict(set)   # mockup_name -> page IDs

    for edge in edges:
        etype = edge.get('type')
        frm = edge.get('from', '')
        to = edge.get('to', '')
        if etype == 'DERIVED_FROM':
            page_to_reqs[frm].add(to)
            req_to_pages[to].add(frm)
        elif etype == 'APPLIES_TO':
            page_to_reqs[to].add(frm)
            req_to_pages[frm].add(to)
        elif etype == 'IMPLEMENTED_BY':
            frm_node = nodes.get(frm, {})
            to_node = nodes.get(to, {})
            if frm_node.get('type') == 'requirement' and to_node.get('type') == 'spec':
                req_to_specs[frm].add(to)
            elif frm_node.get('type') == 'spec' and to_node.get('type') == 'task':
                spec_to_tasks[frm].add(to)
        elif etype == 'VERIFIED_BY':
            page_to_scenarios[frm].add(to)
        elif etype == 'COVERS':
            scenario_to_reqs[frm].add(to)

    # Build bundle->pages from page node mockup_name attribute
    for nid, node in nodes.items():
        if node.get('type') == 'page':
            mn = node.get('content', {}).get('mockup_name') or node.get('mockup_name')
            if mn:
                bundle_to_pages[mn].add(nid)

    return {
        'nodes': nodes,
        'page_to_reqs': page_to_reqs,
        'req_to_specs': req_to_specs,
        'spec_to_tasks': spec_to_tasks,
        'page_to_scenarios': page_to_scenarios,
        'scenario_to_reqs': scenario_to_reqs,
        'req_to_pages': req_to_pages,
        'bundle_to_pages': bundle_to_pages,
    }


def resolve_page(maps, page_id):
    nodes = maps['nodes']
    page_node = nodes.get(page_id)

    direct_reqs = sorted(maps['page_to_reqs'].get(page_id, set()))
    scenario_ids = sorted(maps['page_to_scenarios'].get(page_id, set()))
    scenario_reqs = []
    for scn_id in scenario_ids:
        for rq in sorted(maps['scenario_to_reqs'].get(scn_id, set())):
            if rq not in scenario_reqs:
                scenario_reqs.append(rq)

    all_reqs = list(dict.fromkeys(direct_reqs + [r for r in scenario_reqs if r not in direct_reqs]))
    specs = sorted(set(s for r in all_reqs for s in maps['req_to_specs'].get(r, set())))

    result = {
        'query_id': page_id,
        'query_type': 'page',
        'direct_requirements': direct_reqs,
        'scenario_requirements': scenario_reqs,
        'all_requirements': all_reqs,
        'specs': specs,
        'scenarios': scenario_ids,
        'source': 'artifact_index',
    }

    if page_node:
        content = page_node.get('content', {})
        if content.get('mockup_name'):
            result['mockup_name'] = content['mockup_name']
        if content.get('target_revision'):
            result['active_revision'] = content['target_revision']

    return result


def resolve_requirement(maps, req_id):
    specs = sorted(maps['req_to_specs'].get(req_id, set()))
    pages = sorted(maps['req_to_pages'].get(req_id, set()))
    tasks = sorted(set(t for s in specs for t in maps['spec_to_tasks'].get(s, set())))

    # Find scenarios that cover this requirement
    scenarios = []
    for scn_id, scn_reqs in maps['scenario_to_reqs'].items():
        if req_id in scn_reqs:
            scenarios.append(scn_id)

    return {
        'query_id': req_id,
        'query_type': 'requirement',
        'pages': pages,
        'specs': specs,
        'tasks': tasks,
        'scenarios': sorted(scenarios),
        'source': 'artifact_index',
    }


def resolve_spec(maps, spec_id):
    tasks = sorted(maps['spec_to_tasks'].get(spec_id, set()))
    # Find requirements that implement this spec
    reqs = []
    for req_id, spec_set in maps['req_to_specs'].items():
        if spec_id in spec_set:
            reqs.append(req_id)
    pages = sorted(set(p for r in reqs for p in maps['req_to_pages'].get(r, set())))

    return {
        'query_id': spec_id,
        'query_type': 'spec',
        'requirements': sorted(reqs),
        'pages': pages,
        'tasks': tasks,
        'source': 'artifact_index',
    }


def resolve_bundle(maps, mockup_name):
    pages = sorted(maps['bundle_to_pages'].get(mockup_name, set()))
    all_reqs = sorted(set(r for p in pages for r in maps['page_to_reqs'].get(p, set())))
    specs = sorted(set(s for r in all_reqs for s in maps['req_to_specs'].get(r, set())))

    return {
        'query_id': mockup_name,
        'query_type': 'bundle',
        'pages': pages,
        'requirements': all_reqs,
        'specs': specs,
        'source': 'artifact_index',
    }


# ---------------------------------------------------------------------------
# Main resolution entry point
# ---------------------------------------------------------------------------

def resolve(project_root, identifier, query_type=None):
    """
    Resolve an identifier to its related artifacts.

    Args:
        project_root: Path to project root.
        identifier: PAGE-NNN, REQ-NNN, SPEC-NNN, or bundle name.
        query_type: Optional explicit type ('page', 'req', 'spec', 'bundle').

    Returns: dict with resolution result + warnings.
    """
    warnings = []
    data, index_warnings = load_index(project_root)
    warnings.extend(index_warnings)

    # Detect type from identifier if not explicit
    if query_type is None:
        if identifier.startswith('PAGE-'):
            query_type = 'page'
        elif identifier.startswith('REQ-'):
            query_type = 'req'
        elif identifier.startswith('SPEC-'):
            query_type = 'spec'
        else:
            query_type = 'bundle'

    if data is None:
        # Fallback: direct canonical traversal (page only for now)
        if query_type == 'page':
            result = direct_resolve_page(project_root, identifier)
            result['warnings'] = warnings + ['Used direct canonical traversal (index unavailable)']
            return result
        else:
            return {
                'query_id': identifier,
                'query_type': query_type,
                'error': 'Index unavailable and direct traversal not implemented for this type',
                'warnings': warnings,
            }

    maps = build_lookup_maps(data)

    if query_type == 'page':
        result = resolve_page(maps, identifier)
    elif query_type == 'req':
        result = resolve_requirement(maps, identifier)
    elif query_type == 'spec':
        result = resolve_spec(maps, identifier)
    elif query_type == 'bundle':
        result = resolve_bundle(maps, identifier)
    else:
        result = {'query_id': identifier, 'error': f'Unknown query type: {query_type}'}

    if identifier not in maps['nodes'] and query_type != 'bundle':
        warnings.append(f'Identifier \'{identifier}\' not found in index — may need index rebuild or derivedFrom/screens backfill')

    result['warnings'] = warnings
    return result


def print_result(result, as_json=False):
    if as_json:
        print(json.dumps(result, indent=2))
        return

    qtype = result.get('query_type', '?')
    qid = result.get('query_id', '?')
    src = result.get('source', '?')
    print(f'\n--- Impact Resolution: {qid} ({qtype}) ---')
    print(f'Source: {src}')

    if qtype == 'page':
        print(f'Direct requirements:   {result.get("direct_requirements", [])}')
        print(f'Scenario requirements: {result.get("scenario_requirements", [])}')
        print(f'All requirements:      {result.get("all_requirements", [])}')
        print(f'Specs:                 {result.get("specs", [])}')
        print(f'Scenarios:             {result.get("scenarios", [])}')
        if result.get('mockup_name'):
            print(f'Mockup bundle:         {result["mockup_name"]}')
        if result.get('active_revision'):
            print(f'Active revision:       {result["active_revision"]}')

    elif qtype == 'requirement':
        print(f'Pages (applicability): {result.get("pages", [])}')
        print(f'Specs:                 {result.get("specs", [])}')
        print(f'Tasks:                 {result.get("tasks", [])}')
        print(f'Scenarios:             {result.get("scenarios", [])}')

    elif qtype == 'spec':
        print(f'Requirements:          {result.get("requirements", [])}')
        print(f'Pages:                 {result.get("pages", [])}')
        print(f'Tasks:                 {result.get("tasks", [])}')

    elif qtype == 'bundle':
        print(f'Screens (pages):       {result.get("pages", [])}')
        print(f'Requirements:          {result.get("requirements", [])}')
        print(f'Specs:                 {result.get("specs", [])}')

    warnings = result.get('warnings', [])
    if warnings:
        print(f'\nWarnings:')
        for w in warnings:
            print(f'  [WARN] {w}')


def main():
    parser = argparse.ArgumentParser(
        description='MxAgile Impact Resolver — resolves artifact identifiers to related canonical artifacts.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--path', type=str, default='.', help='Project root directory.')
    parser.add_argument('--mockup', type=str, help='Mockup bundle name (alternative to positional ID).')
    parser.add_argument('--json', action='store_true', help='Output as JSON.')
    parser.add_argument('identifier', nargs='?', help='PAGE-NNN, REQ-NNN, or SPEC-NNN identifier.')

    args = parser.parse_args()

    if args.mockup:
        identifier = args.mockup
        query_type = 'bundle'
    elif args.identifier:
        identifier = args.identifier
        query_type = None
    else:
        parser.print_help()
        sys.exit(1)

    result = resolve(args.path, identifier, query_type)
    print_result(result, as_json=args.json)

    if result.get('error'):
        sys.exit(1)


if __name__ == '__main__':
    main()
