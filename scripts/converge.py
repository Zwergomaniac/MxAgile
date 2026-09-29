import json
import os
import argparse
import sys
from pathlib import Path
from collections import defaultdict


def load_index(project_root):
    """Load artifact-index.json (canonical derived graph, built by build_artifact_index.py)."""
    index_path = os.path.join(project_root, '.mxagile', 'state', 'artifact-index.json')
    if not os.path.exists(index_path):
        return None, index_path
    with open(index_path, 'r', encoding='utf-8') as f:
        return json.load(f), index_path


def check_convergence(project_root):
    """
    Convergence diagnostic consumer.
    Reads artifact-index.json and lifecycle artifacts to report convergence state.
    Zero file-writing (read-only).
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

    # Build type maps
    requirements = {nid: n for nid, n in nodes.items() if n.get('type') == 'requirement'}
    specs = {nid: n for nid, n in nodes.items() if n.get('type') == 'spec'}
    tasks = {nid: n for nid, n in nodes.items() if n.get('type') == 'task'}
    pages = {nid: n for nid, n in nodes.items() if n.get('type') == 'page'}
    scenarios = {nid: n for nid, n in nodes.items() if n.get('type') == 'scenario'}

    # Build edge lookup maps
    req_to_specs = defaultdict(list)
    spec_to_tasks = defaultdict(list)
    page_to_reqs = defaultdict(list)    # via DERIVED_FROM (reverse) + APPLIES_TO (reverse)
    page_to_scenarios = defaultdict(list)  # via VERIFIED_BY (reverse)
    scenario_to_reqs = defaultdict(list)   # via COVERS

    for edge in edges:
        etype = edge.get('type')
        frm = edge.get('from', '')
        to = edge.get('to', '')
        if etype == 'IMPLEMENTED_BY' and frm in requirements:
            req_to_specs[frm].append(to)
        elif etype == 'IMPLEMENTED_BY' and frm in specs:
            spec_to_tasks[frm].append(to)
        elif etype == 'DERIVED_FROM':
            page_to_reqs[frm].append(to)
        elif etype == 'APPLIES_TO':
            page_to_reqs[to].append(frm)
        elif etype == 'VERIFIED_BY':
            page_to_scenarios[frm].append(to)
        elif etype == 'COVERS':
            scenario_to_reqs[frm].append(to)

    # Compute coverage stats
    reqs_with_specs = sum(1 for r in requirements if req_to_specs.get(r))
    specs_with_tasks = sum(1 for s in specs if spec_to_tasks.get(s))
    pages_with_reqs = sum(1 for p in pages if page_to_reqs.get(p))
    pages_with_scenarios = sum(1 for p in pages if page_to_scenarios.get(p))

    reqs_without_specs = len(requirements) - reqs_with_specs
    specs_without_tasks = len(specs) - specs_with_tasks
    pages_without_reqs = len(pages) - pages_with_reqs
    pages_without_scenarios = len(pages) - pages_with_scenarios

    # Determine overall convergence verdict
    blockers = []
    if reqs_without_specs > 0:
        blockers.append(f'{reqs_without_specs} Requirement(s) have no implementing Spec')
    if specs_without_tasks > 0:
        blockers.append(f'{specs_without_tasks} Spec(s) have no Task')
    if pages_without_reqs > 0:
        blockers.append(f'{pages_without_reqs} Page(s) have no Requirement traceability (coverage gap)')
    if pages_without_scenarios > 0:
        blockers.append(f'{pages_without_scenarios} Page(s) have no verification scenario')

    status = 'CONVERGED' if not blockers else 'GAPS_DETECTED'

    print('--- MxAgile Convergence Audit Report ---')
    print(f'Index generated:    {generated_at}')
    print(f'Source fingerprint: {source_fingerprint}')
    print()
    print(f'1. Requirements:       {len(requirements)} total, {reqs_with_specs} with Specs, {reqs_without_specs} without')
    print(f'2. Specs:              {len(specs)} total, {specs_with_tasks} with Tasks, {specs_without_tasks} without')
    print(f'3. Tasks:              {len(tasks)}')
    print(f'4. Pages (screens):    {len(pages)} total, {pages_with_reqs} with Req traceability, {pages_without_reqs} without')
    print(f'5. Scenarios:          {len(scenarios)} total, {pages_with_scenarios} pages covered')
    print()
    print(f'Status: {status}')

    if blockers:
        print('\nGaps requiring attention:')
        for b in blockers:
            print(f'  - {b}')
        return 1

    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='MxAgile Convergence Check.')
    parser.add_argument('--path', type=str, default='.', help='Root directory of the MxAgile project.')
    args = parser.parse_args()
    sys.exit(check_convergence(args.path))
