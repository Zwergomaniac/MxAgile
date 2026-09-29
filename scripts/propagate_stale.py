import json
import sys
import os
from pathlib import Path

INDEX_FILENAME = 'artifact-index.json'


def get_index_path(project_root):
    return os.path.join(project_root, '.mxagile', 'state', INDEX_FILENAME)


def load_graph(project_root):
    index_path = get_index_path(project_root)
    if not os.path.exists(index_path):
        print(f'Error: artifact-index.json not found at {index_path}')
        print('Run: python scripts/build_artifact_index.py <project_root>')
        sys.exit(1)
    with open(index_path, 'r', encoding='utf-8') as f:
        return json.load(f)


def save_graph(graph, project_root):
    index_path = get_index_path(project_root)
    with open(index_path, 'w', encoding='utf-8') as f:
        json.dump(graph, f, indent=2)


def propagate_stale(graph, stale_ids):
    """
    Propagate STALE status downstream through the artifact graph.
    A node becomes STALE when its upstream dependency is STALE.
    Traversal follows IMPLEMENTED_BY and COVERS edges downstream.
    """
    adj = {}
    for edge in graph.get('edges', []):
        src = edge['from']
        dst = edge['to']
        if src not in adj:
            adj[src] = []
        adj[src].append(dst)

    stale_nodes = set(stale_ids)
    to_visit = list(stale_ids)

    while to_visit:
        current = to_visit.pop(0)
        if current in adj:
            for neighbor in adj[current]:
                if neighbor not in stale_nodes:
                    stale_nodes.add(neighbor)
                    to_visit.append(neighbor)

    updated_count = 0
    for node in graph.get('nodes', []):
        if node['id'] in stale_nodes:
            if node.get('status') != 'STALE':
                node['status'] = 'STALE'
                updated_count += 1

    return stale_nodes, updated_count


def main():
    args = sys.argv[1:]

    project_root = '.'
    stale_input = []

    i = 0
    while i < len(args):
        if args[i] == '--path' and i + 1 < len(args):
            project_root = args[i + 1]
            i += 2
        else:
            stale_input.append(args[i])
            i += 1

    if not stale_input:
        print('Usage: python scripts/propagate_stale.py [--path <project_root>] <node_id1> [<node_id2> ...]')
        print()
        print('Marks listed nodes STALE in artifact-index.json and propagates downstream.')
        print('Reads and writes: .mxagile/state/artifact-index.json')
        sys.exit(1)

    graph = load_graph(project_root)
    stale_nodes, updated_count = propagate_stale(graph, stale_input)
    save_graph(graph, project_root)

    print(f'Summary: {len(stale_nodes)} nodes marked STALE ({updated_count} newly updated).')
    print('Stale nodes:', ', '.join(sorted(stale_nodes)))


if __name__ == '__main__':
    main()
