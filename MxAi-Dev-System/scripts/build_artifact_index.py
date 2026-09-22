import json
import os
import hashlib
import yaml
import sys
import collections
from pathlib import Path

# Canonical artifact schemas: .mxagile/schemas/requirement.schema.json
#                              .mxagile/schemas/spec.schema.json
#                              .mxagile/schemas/task.schema.json
#
# Field contract (what this indexer reads from each artifact type):
#
#   requirement (requirements/*.yml):
#     ID          -> primary key (falls back to filename stem if absent)
#     derivedFrom -> creates DERIVED_FROM edge: Page -> Requirement
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
#   page (pages/*.yml):
#     ID -> primary key


def calculate_sha256(filepath):
    sha256_hash = hashlib.sha256()
    try:
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        print(f"[ERROR] Could not read file for hash: {filepath} - {e}")
        return None


def get_display_name(content, artifact_type, fallback):
    """Return a human-readable display name for the artifact.

    Tasks use 'action' (canonical) with fallback to 'description' for
    compatibility with older files written before the canonical schema.
    All other types use 'description'.
    """
    if artifact_type == "task":
        return content.get("action") or content.get("description") or fallback
    return content.get("description") or fallback


def find_artifacts(project_root):
    print("[INFO] Stage 1: Indexing artifacts from filesystem...")
    artifacts = collections.defaultdict(dict)
    artifact_locations = [
        {"type": "requirement", "path": "requirements", "filter": "*.yml"},
        {"type": "spec",        "path": "specs",         "filter": "*.yml"},
        {"type": "task",        "path": "planning/tasks","filter": "*.yml"},
        {"type": "page",        "path": "pages",         "filter": "*.yml"},
    ]

    for loc in artifact_locations:
        dir_path = project_root / loc['path']
        if not dir_path.exists():
            print(f"[DEBUG] Directory does not exist, skipping: {dir_path}")
            continue

        for filepath in dir_path.glob(loc['filter']):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    entry_content = yaml.safe_load(f) or {}
            except Exception as e:
                print(f"[ERROR] Could not read or parse YAML for {filepath}: {e}")
                continue

            file_id_from_name = filepath.stem
            artifact_id = entry_content.get('ID', file_id_from_name)

            if artifact_id != file_id_from_name:
                print(f"[WARN] ID mismatch: file={file_id_from_name}, ID field={artifact_id} in {filepath}")

            entry = {}
            entry['id'] = artifact_id
            entry['type'] = loc['type']
            entry['path'] = str(filepath.relative_to(project_root))
            entry['hash'] = calculate_sha256(filepath)
            entry['display_name'] = get_display_name(entry_content, loc['type'], file_id_from_name)
            entry['content'] = entry_content

            artifacts[loc['type']][artifact_id] = entry
            print(f"[DEBUG] Indexed {loc['type']}: {artifact_id}")

    print(f"[INFO] Indexing complete. Found:"
          f" {len(artifacts['requirement'])} requirements,"
          f" {len(artifacts['spec'])} specs,"
          f" {len(artifacts['task'])} tasks,"
          f" {len(artifacts['page'])} pages.")
    return artifacts


def build_graph(artifacts):
    print("\n[INFO] Stage 2: Building artifact graph...")
    nodes = []
    edges = []
    all_artifact_ids = set()

    for type_key in artifacts:
        for id_key in artifacts[type_key]:
            node = artifacts[type_key][id_key].copy()
            nodes.append(node)
            all_artifact_ids.add(id_key)

    for node in nodes:
        node_id = node['id']
        content = node.get('content', {})

        # Page -> Requirement: DERIVED_FROM
        if node['type'] == 'requirement':
            derived_from_id = content.get('derivedFrom')
            if derived_from_id and derived_from_id in all_artifact_ids:
                edges.append({"from": derived_from_id, "to": node_id, "type": "DERIVED_FROM"})
                print(f"[DEBUG] Edge: {derived_from_id} --DERIVED_FROM--> {node_id}")
            elif derived_from_id:
                print(f"[WARN] Broken derivedFrom reference in {node_id}: {derived_from_id} not found")

        # Requirement -> Spec: IMPLEMENTED_BY
        if node['type'] == 'spec':
            req_refs = content.get('requirements', [])
            if isinstance(req_refs, list):
                for req_id in req_refs:
                    if req_id in all_artifact_ids:
                        edges.append({"from": req_id, "to": node_id, "type": "IMPLEMENTED_BY"})
                        print(f"[DEBUG] Edge: {req_id} --IMPLEMENTED_BY--> {node_id}")
                    else:
                        print(f"[WARN] Broken requirements reference in {node_id}: {req_id} not found")

        # Spec -> Task: IMPLEMENTED_BY
        if node['type'] == 'task':
            spec_ref_id = content.get('spec')
            if spec_ref_id and spec_ref_id in all_artifact_ids:
                edges.append({"from": spec_ref_id, "to": node_id, "type": "IMPLEMENTED_BY"})
                print(f"[DEBUG] Edge: {spec_ref_id} --IMPLEMENTED_BY--> {node_id}")
            elif spec_ref_id:
                print(f"[WARN] Broken spec reference in {node_id}: {spec_ref_id} not found")

    print(f"[INFO] Graph building complete. Found {len(nodes)} nodes and {len(edges)} edges.")
    return {"nodes": nodes, "edges": edges}


def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--path':
        project_root_path = sys.argv[2]
    elif len(sys.argv) > 1:
        project_root_path = sys.argv[1]
    else:
        project_root_path = '.'

    project_root = Path(project_root_path).resolve()
    print(f"[INFO] Building artifact index for project: {project_root}")

    artifacts = find_artifacts(project_root)
    graph = build_graph(artifacts)

    state_dir = project_root / ".mxagile" / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    output_file = state_dir / "artifact-index.json"

    print(f"\n[INFO] Writing final artifact index to: {output_file}")
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(graph, f, indent=2)
        print("\nArtifact index created successfully.")
    except Exception as e:
        print(f"[ERROR] Failed to write JSON output: {e}")


if __name__ == "__main__":
    main()
