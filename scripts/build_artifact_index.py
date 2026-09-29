import json
import os
import hashlib
import yaml
import sys
import collections
import datetime
from pathlib import Path

# Canonical artifact schemas:
#   .mxagile/schemas/requirement.schema.json
#   .mxagile/schemas/spec.schema.json
#   .mxagile/schemas/task.schema.json
#   .mxagile/schemas/verification-scenario.schema.json
#
# Field contract (what this indexer reads from each artifact type):
#
#   requirement (requirements/*.yml):
#     ID          -> primary key (falls back to filename stem if absent)
#     derivedFrom -> optional PAGE-id: DERIVED_FROM edge: Page -> Requirement (provenance)
#     screens     -> optional [PAGE-ids]: APPLIES_TO edges: Requirement -> Page (applicability)
#
#   spec (specs/*.yml):
#     ID           -> primary key
#     requirements -> list of REQ-ids, creates IMPLEMENTED_BY edges: Requirement -> Spec
#
#   task (planning/tasks/*.yml):
#     ID     -> primary key
#     spec   -> SPEC-id, creates IMPLEMENTED_BY edge: Spec -> Task
#     action -> display name (falls back to description, then filename stem)
#
#   page (planning/ui-inventory/*.yaml):
#     page_id     -> primary key (REQUIRED field per schema)
#     mockup_name -> optional: bundle this screen belongs to
#
#   scenario (planning/scenarios/*.yaml):
#     scenario_id    -> primary key
#     screen_id      -> PAGE-id: VERIFIED_BY edge: Page -> Scenario
#     traceability.requirements -> list of REQ-ids: COVERS edges: Scenario -> Requirement
#
# Output: .mxagile/state/artifact-index.json
# Format: {"nodes": [...], "edges": [...], "source_fingerprint": "sha256:...", "generated_at": "..."}
#
# NOTE: artifact-trace-index.json was a legacy hand-written stub and is no longer active.
#       artifact-graph.json was referenced by a stale propagate_stale.py and does not exist.
#       trace-index.json was an old deprecated format used by refine.py.
#       All consumers must use artifact-index.json as the single authoritative index.


def calculate_sha256(filepath):
    sha256_hash = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            for byte_block in iter(lambda: f.read(4096), b''):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        print(f'[ERROR] Could not read file for hash: {filepath} - {e}')
        return None


def get_display_name(content, artifact_type, fallback):
    if artifact_type == 'task':
        return content.get('action') or content.get('description') or fallback
    if artifact_type == 'page':
        return content.get('purpose') or content.get('page_id') or fallback
    if artifact_type == 'scenario':
        return content.get('description') or content.get('scenario_id') or fallback
    return content.get('description') or fallback


def _read_yaml(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print(f'[ERROR] Could not read or parse YAML for {filepath}: {e}')
        return None


def find_artifacts(project_root):
    print('[INFO] Stage 1: Indexing artifacts from filesystem...')
    artifacts = collections.defaultdict(dict)

    # Canonical locations per policies/project-knowledge.md
    artifact_locations = [
        {'type': 'requirement', 'path': 'requirements',          'filter': '*.yml',  'id_field': 'ID'},
        {'type': 'spec',        'path': 'specs',                 'filter': '*.yml',  'id_field': 'ID'},
        {'type': 'task',        'path': 'planning/tasks',        'filter': '*.yml',  'id_field': 'ID'},
        # FIXED: UI inventories live in planning/ui-inventory/*.yaml (not pages/*.yml)
        {'type': 'page',        'path': 'planning/ui-inventory', 'filter': '*.yaml', 'id_field': 'page_id'},
        # Scenarios: planning/scenarios/*.yaml
        {'type': 'scenario',    'path': 'planning/scenarios',    'filter': '*.yaml', 'id_field': 'scenario_id'},
    ]

    for loc in artifact_locations:
        dir_path = project_root / loc['path']
        if not dir_path.exists():
            print(f'[DEBUG] Directory does not exist, skipping: {dir_path}')
            continue

        for filepath in sorted(dir_path.glob(loc['filter'])):
            content = _read_yaml(filepath)
            if content is None:
                continue

            file_id_from_name = filepath.stem
            artifact_id = content.get(loc['id_field'], file_id_from_name)

            if artifact_id != file_id_from_name:
                print(f'[WARN] ID mismatch: file={file_id_from_name}, {loc["id_field"]}={artifact_id} in {filepath}')

            entry = {
                'id':           artifact_id,
                'type':         loc['type'],
                'path':         str(filepath.relative_to(project_root)).replace('\\', '/'),
                'hash':         calculate_sha256(filepath),
                'display_name': get_display_name(content, loc['type'], file_id_from_name),
                'content':      content,
            }

            if loc['type'] == 'page' and content.get('mockup_name'):
                entry['mockup_name'] = content['mockup_name']

            artifacts[loc['type']][artifact_id] = entry
            print(f'[DEBUG] Indexed {loc["type"]}: {artifact_id}')

    print(
        f'[INFO] Indexing complete. Found:'
        f' {len(artifacts["requirement"])} requirements,'
        f' {len(artifacts["spec"])} specs,'
        f' {len(artifacts["task"])} tasks,'
        f' {len(artifacts["page"])} pages,'
        f' {len(artifacts["scenario"])} scenarios.'
    )
    return artifacts


def build_graph(artifacts):
    print('\n[INFO] Stage 2: Building artifact graph...')
    nodes = []
    edges = []
    all_artifact_ids = set()

    for type_key in artifacts:
        for id_key in artifacts[type_key]:
            node = {k: v for k, v in artifacts[type_key][id_key].items() if k != 'content'}
            node['content'] = artifacts[type_key][id_key].get('content', {})
            nodes.append(node)
            all_artifact_ids.add(id_key)

    for node in nodes:
        node_id = node['id']
        content = node.get('content', {})

        # --- DERIVED_FROM: Page -> Requirement (provenance) ---
        # requirement.derivedFrom is the page this requirement ORIGINATED FROM.
        if node['type'] == 'requirement':
            derived_from_id = content.get('derivedFrom')
            if derived_from_id:
                if derived_from_id in all_artifact_ids:
                    edges.append({'from': derived_from_id, 'to': node_id, 'type': 'DERIVED_FROM'})
                    print(f'[DEBUG] Edge: {derived_from_id} --DERIVED_FROM--> {node_id}')
                else:
                    print(f'[WARN] Broken derivedFrom reference in {node_id}: {derived_from_id} not found')

        # --- APPLIES_TO: Requirement -> Page (applicability) ---
        # requirement.screens[] lists pages where this requirement is applicable.
        # This is a separate concept from derivedFrom (provenance).
        if node['type'] == 'requirement':
            screen_refs = content.get('screens', [])
            if isinstance(screen_refs, list):
                for screen_id in screen_refs:
                    if screen_id in all_artifact_ids:
                        edges.append({'from': node_id, 'to': screen_id, 'type': 'APPLIES_TO'})
                        print(f'[DEBUG] Edge: {node_id} --APPLIES_TO--> {screen_id}')
                    else:
                        print(f'[WARN] Broken screens reference in {node_id}: {screen_id} not found')

        # --- IMPLEMENTED_BY: Requirement -> Spec ---
        if node['type'] == 'spec':
            req_refs = content.get('requirements', [])
            if isinstance(req_refs, list):
                for req_id in req_refs:
                    if req_id in all_artifact_ids:
                        edges.append({'from': req_id, 'to': node_id, 'type': 'IMPLEMENTED_BY'})
                        print(f'[DEBUG] Edge: {req_id} --IMPLEMENTED_BY--> {node_id}')
                    else:
                        print(f'[WARN] Broken requirements reference in {node_id}: {req_id} not found')

        # --- IMPLEMENTED_BY: Spec -> Task ---
        if node['type'] == 'task':
            spec_ref_id = content.get('spec')
            if spec_ref_id:
                if spec_ref_id in all_artifact_ids:
                    edges.append({'from': spec_ref_id, 'to': node_id, 'type': 'IMPLEMENTED_BY'})
                    print(f'[DEBUG] Edge: {spec_ref_id} --IMPLEMENTED_BY--> {node_id}')
                else:
                    print(f'[WARN] Broken spec reference in {node_id}: {spec_ref_id} not found')

        # --- VERIFIED_BY: Page -> Scenario ---
        # scenario.screen_id links a scenario to the page it verifies.
        if node['type'] == 'scenario':
            screen_id = content.get('screen_id')
            if screen_id:
                if screen_id in all_artifact_ids:
                    edges.append({'from': screen_id, 'to': node_id, 'type': 'VERIFIED_BY'})
                    print(f'[DEBUG] Edge: {screen_id} --VERIFIED_BY--> {node_id}')
                else:
                    print(f'[WARN] Broken screen_id reference in {node_id}: {screen_id} not found')

        # --- COVERS: Scenario -> Requirement ---
        # scenario.traceability.requirements[] links a scenario to requirements it validates.
        if node['type'] == 'scenario':
            traceability = content.get('traceability', {}) or {}
            req_refs = traceability.get('requirements', [])
            if isinstance(req_refs, list):
                for req_id in req_refs:
                    if req_id in all_artifact_ids:
                        edges.append({'from': node_id, 'to': req_id, 'type': 'COVERS'})
                        print(f'[DEBUG] Edge: {node_id} --COVERS--> {req_id}')
                    else:
                        print(f'[WARN] Broken scenario.traceability.requirements ref in {node_id}: {req_id} not found')

    print(f'[INFO] Graph building complete. Found {len(nodes)} nodes and {len(edges)} edges.')
    return {'nodes': nodes, 'edges': edges}


def compute_source_fingerprint(artifacts):
    """
    Compute a deterministic fingerprint of all indexed source files.
    This fingerprint allows consumers to detect whether the index is stale
    relative to the canonical artifact files it was built from.

    Algorithm: sort (canonical_path, sha256) pairs by path, join as "<path>:<hash>",
    SHA-256 the resulting manifest.
    """
    entries = []
    for type_key in artifacts:
        for id_key in artifacts[type_key]:
            entry = artifacts[type_key][id_key]
            canonical_path = entry.get('path', '')
            file_hash = entry.get('hash', '')
            if canonical_path and file_hash:
                entries.append((canonical_path, file_hash))

    entries.sort(key=lambda x: x[0])
    manifest_str = '\n'.join(f'{p}:{h}' for p, h in entries)
    fp = hashlib.sha256(manifest_str.encode('utf-8')).hexdigest()
    return f'sha256:{fp}'


def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--path':
        project_root_path = sys.argv[2]
    elif len(sys.argv) > 1 and not sys.argv[1].startswith('--'):
        project_root_path = sys.argv[1]
    else:
        project_root_path = '.'

    project_root = Path(project_root_path).resolve()
    print(f'[INFO] Building artifact index for project: {project_root}')

    artifacts = find_artifacts(project_root)
    graph = build_graph(artifacts)

    # Attach index metadata
    source_fingerprint = compute_source_fingerprint(artifacts)
    graph['source_fingerprint'] = source_fingerprint
    graph['generated_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    state_dir = project_root / '.mxagile' / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)
    output_file = state_dir / 'artifact-index.json'

    print(f'\n[INFO] Writing artifact index to: {output_file}')
    print(f'[INFO] Source fingerprint: {source_fingerprint}')
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(graph, f, indent=2)
        print('\nArtifact index created successfully.')
    except Exception as e:
        print(f'[ERROR] Failed to write JSON output: {e}')


if __name__ == '__main__':
    main()
