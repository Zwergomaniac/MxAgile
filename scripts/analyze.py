import json
import os
import argparse
import sys
from pathlib import Path


def load_index(project_root):
    """Load artifact-index.json (the canonical derived graph, built by build_artifact_index.py)."""
    index_path = os.path.join(project_root, '.mxagile', 'state', 'artifact-index.json')
    if not os.path.exists(index_path):
        return None, index_path
    with open(index_path, 'r', encoding='utf-8') as f:
        return json.load(f), index_path


def run_diagnostics(project_root):
    """
    Analyzes the project artifact index for structural issues.

    Reads artifact-index.json (produced by build_artifact_index.py).
    Reports: broken path references, orphan nodes, missing edge targets.
    """
    data, index_path = load_index(project_root)
    if not data:
        print(f'Error: artifact-index.json not found at {index_path}')
        print('Run: python scripts/build_artifact_index.py <project_root>')
        return 1

    nodes = {n['id']: n for n in data.get('nodes', [])}
    edges = data.get('edges', [])
    source_fingerprint = data.get('source_fingerprint', '(not recorded)')
    generated_at = data.get('generated_at', '(not recorded)')

    errors = []
    warnings = []

    print(f'--- Artifact Index Diagnostics ---')
    print(f'Index generated: {generated_at}')
    print(f'Source fingerprint: {source_fingerprint}')
    print(f'Nodes: {len(nodes)}  Edges: {len(edges)}')
    print()

    # 1. Broken path references
    for node_id, node in nodes.items():
        node_path = node.get('path')
        if node_path:
            abs_path = os.path.join(project_root, node_path)
            if not os.path.exists(abs_path):
                errors.append(
                    f'Broken path reference: {node["type"]} \'{node_id}\' '
                    f'points to missing file: {node_path}'
                )

    # 2. Broken edge references (edge points to node not in index)
    node_ids = set(nodes.keys())
    for edge in edges:
        frm = edge.get('from', '')
        to = edge.get('to', '')
        etype = edge.get('type', '?')
        if frm not in node_ids:
            errors.append(f'Broken edge source: {etype} edge from \'{frm}\' -> \'{to}\' — source not in index')
        if to not in node_ids:
            errors.append(f'Broken edge target: {etype} edge from \'{frm}\' -> \'{to}\' — target not in index')

    # 3. Orphan detection — Requirements with no Spec relationship and no screen relationship
    spec_linked_reqs = set()
    for edge in edges:
        if edge.get('type') == 'IMPLEMENTED_BY':
            spec_node = nodes.get(edge.get('to', ''))
            if spec_node and spec_node.get('type') == 'spec':
                spec_linked_reqs.add(edge.get('from', ''))

    screen_linked_reqs = set()
    for edge in edges:
        if edge.get('type') in ('DERIVED_FROM', 'APPLIES_TO', 'COVERS'):
            if edge.get('type') == 'DERIVED_FROM':
                screen_linked_reqs.add(edge.get('to', ''))  # Req is the target
            elif edge.get('type') == 'APPLIES_TO':
                screen_linked_reqs.add(edge.get('from', ''))  # Req is the source
            elif edge.get('type') == 'COVERS':
                screen_linked_reqs.add(edge.get('to', ''))  # Req is the target

    for node_id, node in nodes.items():
        if node.get('type') == 'requirement':
            if node_id not in spec_linked_reqs:
                warnings.append(f'Orphan requirement (no Spec): {node_id} — {node.get("display_name", "")}')
            if node_id not in screen_linked_reqs:
                warnings.append(f'Coverage gap (no Screen link): {node_id} — no derivedFrom, screens[], or scenario traceability')

    # 4. Specs with no Task (implementation pending)
    task_linked_specs = set()
    for edge in edges:
        if edge.get('type') == 'IMPLEMENTED_BY':
            task_node = nodes.get(edge.get('to', ''))
            if task_node and task_node.get('type') == 'task':
                task_linked_specs.add(edge.get('from', ''))

    for node_id, node in nodes.items():
        if node.get('type') == 'spec':
            if node_id not in task_linked_specs:
                warnings.append(f'Spec with no Task: {node_id} — {node.get("display_name", "")}')

    # 5. Pages with no scenario (verification gap)
    scenario_linked_pages = set()
    for edge in edges:
        if edge.get('type') == 'VERIFIED_BY':
            scenario_linked_pages.add(edge.get('from', ''))

    for node_id, node in nodes.items():
        if node.get('type') == 'page':
            if node_id not in scenario_linked_pages:
                warnings.append(f'Page with no verification scenario: {node_id} — {node.get("display_name", "")}')

    # Report
    print('--- Analysis Report ---')
    if errors:
        print(f'\nERRORS ({len(errors)}):')
        for e in errors:
            print(f'  [ERROR] {e}')
    else:
        print('\nNo critical errors found.')

    if warnings:
        print(f'\nWARNINGS ({len(warnings)}):')
        for w in warnings:
            print(f'  [WARN]  {w}')
    else:
        print('\nNo warnings found.')

    return 1 if errors else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='MxAgile Artifact Index Diagnostics.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    sys.exit(run_diagnostics(args.path))
