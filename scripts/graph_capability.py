"""
MxAgile Provider-Neutral Knowledge Graph Capability (Phase 1d)

Implements the graph operations contract defined in docs/spikes/SPIKE-KG-BUSINESSFLOW.md.
This module wraps the existing build_artifact_index.py / resolve_impact.py infrastructure
for the default 'artifact-index' provider.

Operations:
  build()       — rebuild the artifact index from canonical YAML sources
  refresh()     — rebuild only if source fingerprint indicates staleness
  status()      — return current graph state from .mxagile/state/graph-state.yaml
  query()       — find nodes by type, id pattern, or arbitrary predicate
  neighbors()   — direct neighbors (one hop) of a node, optionally filtered by edge type
  paths()       — all paths between two nodes up to max_depth hops
  affected()    — BFS from a set of changed nodes; returns downstream affected node IDs
  explain()     — return provenance chain for a specific edge or node

Graph availability is OPTIONAL — all operations degrade gracefully when the index is
absent or stale.  Graph unavailability NEVER blocks lifecycle operations.

Provider selection is read from .mxagile/config.yaml:
  knowledge_graph:
    provider: artifact-index   # default
    # provider: none           # disables the graph entirely
    # provider: graphify       # Phase 3 only — not implemented here

Usage:
  from scripts.graph_capability import KnowledgeGraph
  kg = KnowledgeGraph(project_root='/path/to/project')
  print(kg.status())
  result = kg.neighbors('REQ-001')
  affected = kg.affected(['PAGE-CALENDAR'])
"""

import json
import os
import sys
import subprocess
import yaml
import hashlib
import datetime
from pathlib import Path
from collections import deque


# ---------------------------------------------------------------------------
# Graph state constants (must match .mxagile/state/graph-state.yaml)
# ---------------------------------------------------------------------------
STATE_DISABLED  = 'DISABLED'
STATE_MISSING   = 'MISSING'
STATE_BUILDING  = 'BUILDING'
STATE_READY     = 'READY'
STATE_STALE     = 'STALE'
STATE_FAILED    = 'FAILED'


class GraphUnavailableError(Exception):
    """Raised when an operation requires the graph but it is not available."""


class KnowledgeGraph:
    """
    Provider-neutral Knowledge Graph capability for a single MxAgile project.

    All operations return plain dicts/lists — no custom types that would force
    callers to import this module just to inspect results.

    Fallback contract:
    - If the provider is 'none' or graph is DISABLED, status() returns DISABLED
      and all data operations return empty results with a 'fallback_reason' key.
    - If the index file is missing or FAILED, operations fall back to direct
      canonical YAML traversal where possible.
    - Graph unavailability never raises exceptions in query/neighbors/affected —
      only build()/refresh() surface errors.
    """

    def __init__(self, project_root='.'):
        self._root    = Path(project_root).resolve()
        self._index   = None          # lazily loaded
        self._state   = None          # cached state

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def build(self, force=False):
        """
        Rebuild the artifact index from canonical sources.

        Args:
          force: if True, rebuild even if the index appears current.

        Returns:
          dict with keys: success, node_count, edge_count, duration_s, warnings
        """
        if not force:
            st = self.status()
            if st.get('status') == STATE_READY and not self._is_stale():
                return {
                    'success':    True,
                    'node_count': st.get('node_count', 0),
                    'edge_count': st.get('edge_count', 0),
                    'duration_s': 0.0,
                    'warnings':   ['Index is current — skipped rebuild (use force=True to override)'],
                }

        import time
        start = time.time()
        ok = self._run_builder()
        duration = time.time() - start

        self._index = None   # invalidate cache
        self._state = None

        if ok:
            st = self.status()
            return {
                'success':    True,
                'node_count': st.get('node_count', 0),
                'edge_count': st.get('edge_count', 0),
                'duration_s': round(duration, 2),
                'warnings':   [],
            }
        return {
            'success':    False,
            'node_count': 0,
            'edge_count': 0,
            'duration_s': round(duration, 2),
            'warnings':   ['Build failed — see stderr output from build_artifact_index.py'],
        }

    def refresh(self):
        """
        Rebuild the index if and only if the source fingerprint indicates staleness.
        No-op if the index is current.
        """
        if self._is_stale():
            return self.build(force=True)
        return {
            'success':  True,
            'refreshed': False,
            'message':  'Index is current — no refresh needed',
        }

    def status(self):
        """
        Return the current graph state as a plain dict.
        Keys: status, provider, last_built, node_count, edge_count,
              source_fingerprint, build_duration_s.
        Falls back to MISSING if state file does not exist.
        """
        cfg = self._read_config()
        provider = cfg.get('knowledge_graph', {}).get('provider', 'artifact-index')
        if provider == 'none':
            return {'status': STATE_DISABLED, 'provider': 'none'}

        state_file = self._root / '.mxagile' / 'state' / 'graph-state.yaml'
        if not state_file.exists():
            return {'status': STATE_MISSING, 'provider': provider}

        try:
            with open(state_file, 'r', encoding='utf-8') as f:
                state = yaml.safe_load(f) or {}
        except Exception as e:
            return {'status': STATE_FAILED, 'provider': provider, 'error': str(e)}

        # Check for staleness if READY
        if state.get('status') == STATE_READY and self._is_stale(state.get('source_fingerprint')):
            state['status'] = STATE_STALE

        self._state = state
        return state

    def query(self, node_type=None, id_pattern=None, predicate=None):
        """
        Find nodes in the index.

        Args:
          node_type:  filter by type string (e.g. 'requirement', 'task')
          id_pattern: substring or prefix to match against node ID
          predicate:  callable(node) -> bool for arbitrary filtering

        Returns:
          list of node dicts; empty list if graph is unavailable
        """
        data, _warn = self._load_index_safe()
        if data is None:
            return []

        results = []
        for node in data.get('nodes', []):
            if node_type and node.get('type') != node_type:
                continue
            if id_pattern and id_pattern.lower() not in node.get('id', '').lower():
                continue
            if predicate and not predicate(node):
                continue
            results.append(node)
        return results

    def neighbors(self, node_id, edge_types=None, direction='both'):
        """
        Return direct neighbors (one hop) of node_id.

        Args:
          node_id:    ID of the starting node
          edge_types: list of edge type strings to include (None = all)
          direction:  'out' (from node_id), 'in' (to node_id), 'both'

        Returns:
          dict with keys: node_id, outgoing, incoming — each a list of
          {'node': <node_dict>, 'edge_type': str, 'provenance': dict}
        """
        data, _warn = self._load_index_safe()
        if data is None:
            return {'node_id': node_id, 'outgoing': [], 'incoming': [],
                    'fallback_reason': 'index_unavailable'}

        nodes_by_id = {n['id']: n for n in data.get('nodes', [])}
        outgoing = []
        incoming = []

        for edge in data.get('edges', []):
            etype = edge.get('type')
            if edge_types and etype not in edge_types:
                continue
            if direction in ('out', 'both') and edge.get('from') == node_id:
                target = nodes_by_id.get(edge.get('to'))
                if target:
                    outgoing.append({
                        'node':       target,
                        'edge_type':  etype,
                        'provenance': edge.get('provenance', {}),
                    })
            if direction in ('in', 'both') and edge.get('to') == node_id:
                source = nodes_by_id.get(edge.get('from'))
                if source:
                    incoming.append({
                        'node':       source,
                        'edge_type':  etype,
                        'provenance': edge.get('provenance', {}),
                    })

        return {'node_id': node_id, 'outgoing': outgoing, 'incoming': incoming}

    def paths(self, from_id, to_id, max_depth=5):
        """
        Find all directed paths from from_id to to_id up to max_depth hops.

        Returns:
          list of paths; each path is a list of {'node_id', 'edge_type'} dicts.
          Empty list if no path or graph unavailable.
        """
        data, _warn = self._load_index_safe()
        if data is None:
            return []

        # Build adjacency: from_id -> [(to_id, edge_type)]
        adj = {}
        for edge in data.get('edges', []):
            frm = edge.get('from')
            to  = edge.get('to')
            et  = edge.get('type')
            if frm not in adj:
                adj[frm] = []
            adj[frm].append((to, et))

        found_paths = []
        # BFS with path tracking
        queue = deque()
        queue.append([(from_id, None)])  # (node_id, arriving_edge_type)

        while queue:
            path = queue.popleft()
            current_id = path[-1][0]
            if len(path) - 1 > max_depth:
                continue
            if current_id == to_id and len(path) > 1:
                found_paths.append([
                    {'node_id': nid, 'edge_type': et} for nid, et in path
                ])
                continue
            for (next_id, et) in adj.get(current_id, []):
                # Avoid cycles
                visited = {p[0] for p in path}
                if next_id not in visited:
                    queue.append(path + [(next_id, et)])

        return found_paths

    def affected(self, changed_ids, max_depth=10):
        """
        BFS from changed_ids following all outgoing edges to find downstream
        artifacts that are potentially affected.

        This is the graph-assisted complement to propagate_stale.py.
        The graph is ADVISORY — lifecycle gates remain authoritative.

        Args:
          changed_ids: list of node IDs that changed
          max_depth:   maximum BFS depth

        Returns:
          dict with keys:
            changed:    the input set (normalized)
            affected:   list of {'id', 'type', 'distance', 'path'} dicts, distance-sorted
            warnings:   list of warning strings
            fallback:   True if direct YAML traversal was used instead of index
        """
        data, warnings = self._load_index_safe()
        if data is None:
            # Fall back to direct resolve_impact.py traversal for PAGE/REQ
            return self._direct_affected_fallback(changed_ids, warnings)

        nodes_by_id = {n['id']: n for n in data.get('nodes', [])}
        # Build adjacency from the full edge set (all types)
        adj = {}
        for edge in data.get('edges', []):
            frm = edge.get('from')
            to  = edge.get('to')
            if frm not in adj:
                adj[frm] = []
            adj[frm].append(to)

        visited = {}  # id -> distance
        queue = deque()
        for cid in changed_ids:
            queue.append((cid, 0, [cid]))

        while queue:
            node_id, dist, path = queue.popleft()
            if node_id in visited:
                continue
            if dist > 0:
                visited[node_id] = {'id': node_id, 'distance': dist, 'path': path,
                                    'type': nodes_by_id.get(node_id, {}).get('type')}
            if dist >= max_depth:
                continue
            for next_id in adj.get(node_id, []):
                if next_id not in visited:
                    queue.append((next_id, dist + 1, path + [next_id]))

        affected_sorted = sorted(visited.values(), key=lambda x: x['distance'])
        return {
            'changed':  list(changed_ids),
            'affected': affected_sorted,
            'warnings': warnings,
            'fallback': False,
        }

    def explain(self, from_id, to_id):
        """
        Return the provenance chain for the edge(s) between from_id and to_id.

        Returns:
          list of edge dicts (may be empty); each includes 'provenance' key.
        """
        data, _warn = self._load_index_safe()
        if data is None:
            return []
        return [
            e for e in data.get('edges', [])
            if e.get('from') == from_id and e.get('to') == to_id
        ]

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _read_config(self):
        config_path = self._root / '.mxagile' / 'config.yaml'
        if config_path.exists():
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    return yaml.safe_load(f) or {}
            except Exception:
                pass
        return {}

    def _index_path(self):
        return self._root / '.mxagile' / 'state' / 'artifact-index.json'

    def _load_index_safe(self):
        """Load the artifact index; return (data, warnings) with data=None on failure."""
        cfg = self._read_config()
        provider = cfg.get('knowledge_graph', {}).get('provider', 'artifact-index')
        if provider == 'none':
            return None, ['Graph is DISABLED (provider: none)']

        if self._index is not None:
            return self._index, []

        idx_path = self._index_path()
        warnings = []
        if not idx_path.exists():
            warnings.append('artifact-index.json not found — graph unavailable')
            return None, warnings
        try:
            with open(idx_path, 'r', encoding='utf-8') as f:
                self._index = json.load(f)
            return self._index, warnings
        except Exception as e:
            warnings.append(f'Failed to read artifact-index.json: {e}')
            return None, warnings

    def _is_stale(self, stored_fp=None):
        """
        Returns True if the stored source fingerprint does not match the current files.
        If stored_fp is not provided, reads it from the index file.
        """
        if stored_fp is None:
            data, _ = self._load_index_safe()
            if data is None:
                return True
            stored_fp = data.get('source_fingerprint')

        if not stored_fp:
            return True

        current_fp = self._compute_current_fingerprint()
        return stored_fp != current_fp

    def _compute_current_fingerprint(self):
        """
        Compute the source fingerprint of all canonical artifact files.
        Must stay in sync with the fingerprint algorithm in build_artifact_index.py.
        """
        artifact_locations = [
            ('requirements',                    '*.yml'),
            ('specs',                           '*.yml'),
            ('planning/tasks',                  '*.yml'),
            ('planning/ui-inventory',           '*.yaml'),
            ('planning/scenarios',              '*.yaml'),
            ('planning/test-contracts',         '*.yaml'),
            ('planning/verification-plans',     '*.yaml'),
            ('planning/decisions',              '*.yml'),
        ]
        entries = []
        for rel_dir, pattern in artifact_locations:
            d = self._root / rel_dir
            if d.exists():
                for f in sorted(d.glob(pattern)):
                    rel = str(f.relative_to(self._root)).replace('\\', '/')
                    sha = hashlib.sha256(f.read_bytes()).hexdigest()
                    entries.append((rel, sha))

        # Revision files
        target_dir = self._root / 'planning' / 'target-mockups'
        if target_dir.exists():
            for mockup_dir in sorted(target_dir.iterdir()):
                history_dir = mockup_dir / '_history'
                if history_dir.exists():
                    for rev_dir in sorted(history_dir.iterdir()):
                        rev_file = rev_dir / 'revision.yaml'
                        if rev_file.exists():
                            rel = str(rev_file.relative_to(self._root)).replace('\\', '/')
                            sha = hashlib.sha256(rev_file.read_bytes()).hexdigest()
                            entries.append((rel, sha))

        entries.sort(key=lambda x: x[0])
        manifest = '\n'.join(f'{p}:{h}' for p, h in entries)
        fp = hashlib.sha256(manifest.encode('utf-8')).hexdigest()
        return f'sha256:{fp}'

    def _run_builder(self):
        """Invoke build_artifact_index.py as a subprocess."""
        builder = Path(__file__).parent / 'build_artifact_index.py'
        if not builder.exists():
            return False
        try:
            result = subprocess.run(
                [sys.executable, str(builder), str(self._root)],
                capture_output=True, text=True, timeout=120
            )
            if result.returncode != 0:
                print(result.stderr, file=sys.stderr)
            return result.returncode == 0
        except Exception as e:
            print(f'[ERROR] build_artifact_index.py failed: {e}', file=sys.stderr)
            return False

    def _direct_affected_fallback(self, changed_ids, base_warnings):
        """
        Fallback: use resolve_impact.py direct traversal for PAGE/REQ nodes.
        Only partial coverage — just the relationships resolve_impact.py knows about.
        """
        warnings = list(base_warnings) + ['Using direct canonical traversal (graph index unavailable)']
        affected = []

        try:
            resolve_module = Path(__file__).parent / 'resolve_impact.py'
            if not resolve_module.exists():
                warnings.append('resolve_impact.py not found — fallback unavailable')
                return {'changed': list(changed_ids), 'affected': [], 'warnings': warnings, 'fallback': True}

            import importlib.util
            spec = importlib.util.spec_from_file_location('resolve_impact', str(resolve_module))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            seen = set()
            for node_id in changed_ids:
                if node_id.startswith('PAGE-') or node_id.startswith('SCREEN-'):
                    result = module.direct_resolve_page(str(self._root), node_id)
                    for req_id in result.get('all_requirements', []):
                        if req_id not in seen:
                            affected.append({'id': req_id, 'distance': 1, 'type': 'requirement',
                                             'path': [node_id, req_id]})
                            seen.add(req_id)
        except Exception as e:
            warnings.append(f'Direct traversal fallback error: {e}')

        return {
            'changed':  list(changed_ids),
            'affected': affected,
            'warnings': warnings,
            'fallback': True,
        }


# ---------------------------------------------------------------------------
# CLI entry point — useful for quick inspection
# ---------------------------------------------------------------------------

def main():
    import argparse
    parser = argparse.ArgumentParser(description='MxAgile Knowledge Graph capability CLI')
    parser.add_argument('--path', default='.', help='Project root')
    sub = parser.add_subparsers(dest='command')

    sub.add_parser('status',  help='Show graph state')
    sub.add_parser('build',   help='Build/rebuild the artifact index')
    sub.add_parser('refresh', help='Rebuild only if stale')

    query_p = sub.add_parser('query', help='Find nodes')
    query_p.add_argument('--type', help='Node type filter')
    query_p.add_argument('--id',   help='ID substring filter')

    nbrs_p = sub.add_parser('neighbors', help='Show neighbors of a node')
    nbrs_p.add_argument('node_id')
    nbrs_p.add_argument('--edge-types', nargs='*')
    nbrs_p.add_argument('--direction', default='both', choices=['in', 'out', 'both'])

    aff_p = sub.add_parser('affected', help='Find downstream affected nodes')
    aff_p.add_argument('node_ids', nargs='+')

    exp_p = sub.add_parser('explain', help='Explain edge provenance')
    exp_p.add_argument('from_id')
    exp_p.add_argument('to_id')

    paths_p = sub.add_parser('paths', help='Find all directed paths between two nodes')
    paths_p.add_argument('from_id')
    paths_p.add_argument('to_id')
    paths_p.add_argument('--max-depth', type=int, default=5)

    args = parser.parse_args()
    kg = KnowledgeGraph(project_root=args.path)

    if args.command == 'status':
        print(json.dumps(kg.status(), indent=2))
    elif args.command == 'build':
        print(json.dumps(kg.build(force=True), indent=2))
    elif args.command == 'refresh':
        print(json.dumps(kg.refresh(), indent=2))
    elif args.command == 'query':
        results = kg.query(node_type=args.type, id_pattern=args.id)
        print(json.dumps([{'id': n['id'], 'type': n['type'], 'display_name': n.get('display_name')}
                           for n in results], indent=2))
    elif args.command == 'neighbors':
        print(json.dumps(kg.neighbors(args.node_id, args.edge_types, args.direction), indent=2))
    elif args.command == 'affected':
        print(json.dumps(kg.affected(args.node_ids), indent=2))
    elif args.command == 'explain':
        print(json.dumps(kg.explain(args.from_id, args.to_id), indent=2))
    elif args.command == 'paths':
        result = kg.paths(args.from_id, args.to_id, args.max_depth)
        print(json.dumps({'from': args.from_id, 'to': args.to_id, 'paths': result}, indent=2))
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
