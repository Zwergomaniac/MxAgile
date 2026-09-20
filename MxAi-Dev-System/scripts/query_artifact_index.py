import json
import os
import argparse
import sys
from pathlib import Path

def find_parents(nodes, edges, item_id):
    parents = []
    for edge in edges:
        if edge['to'] == item_id:
            parent_id = edge['from']
            for node in nodes:
                if node['id'] == parent_id:
                    parents.append(node)
                    break
    return parents

def find_children(nodes, edges, item_id):
    children = []
    for edge in edges:
        if edge['from'] == item_id:
            child_id = edge['to']
            for node in nodes:
                if node['id'] == child_id:
                    children.append(node)
                    break
    return children

def get_all_parents(nodes, edges, item_id, visited):
    """Recursively find all parents."""
    if item_id in visited:
        return []
    visited.add(item_id)

    all_parents = []
    direct_parents = find_parents(nodes, edges, item_id)
    for parent_node in direct_parents:
        all_parents.append(parent_node)
        all_parents.extend(get_all_parents(nodes, edges, parent_node['id'], visited))
            
    return all_parents

def get_all_children(nodes, edges, item_id, visited):
    """Recursively find all children."""
    if item_id in visited:
        return []
    visited.add(item_id)
    
    all_children = []
    direct_children = find_children(nodes, edges, item_id)
    for child_node in direct_children:
        all_children.append(child_node)
        all_children.extend(get_all_children(nodes, edges, child_node['id'], visited))

    return all_children

def trace_id(project_root, start_id):
    """Traces the relationships for a given ID through the index."""
    project_root_path = Path(project_root).resolve()
    index_path = project_root_path / ".mxagile" / "state" / "artifact-index.json"
    report_path = project_root_path / 'trace-report.md'

    if not index_path.exists():
        print(f"[ERROR] Artifact index not found. Please run the indexer first.")
        print(f"        Looked for: {index_path}")
        sys.exit(1)

    with open(index_path, 'r', encoding='utf-8') as f:
        trace_data = json.load(f)
    
    nodes = trace_data.get('nodes', [])
    edges = trace_data.get('edges', [])

    print(f"[INFO] Tracing relationships for ID: {start_id}\n")

    # Find the starting item
    start_item = None
    for node in nodes:
        if node['id'] == start_id:
            start_item = node
            break
    
    if not start_item:
        print(f"[ERROR] ID '{start_id}' not found in the artifact index.")
        sys.exit(1)

    visited_parents = set()
    all_parents = get_all_parents(nodes, edges, start_id, visited_parents)
    
    visited_children = set()
    all_children = get_all_children(nodes, edges, start_id, visited_children)
    
    # Collect all unique nodes to be detailed in the report
    found_nodes = {start_item['id']: start_item}
    for node in all_parents:
        found_nodes[node['id']] = node
    for node in all_children:
        found_nodes[node['id']] = node
    
    # --- Generate Report -- -
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(f"# MxAgile Traceability Report for: {start_id}\n\n")
        
        f.write("## Trace Hierarchy\n\n")

        # Display parents
        if all_parents:
            f.write("### Upstream (Parents)\n")
            parent_ids_seen = set()
            for node in reversed(all_parents):
                if node['id'] not in parent_ids_seen:
                    f.write(f"- **{node.get('type', 'N/A').upper()}**: `{node['id']}`\n")
                    parent_ids_seen.add(node['id'])

        # Display the starting item
        f.write(f"### Start Item\n")
        f.write(f"- **{start_item.get('type', 'N/A').upper()}**: `{start_item['id']}`\n")

        # Display children
        if all_children:
            f.write("### Downstream (Children)\n")
            child_ids_seen = set()
            for node in all_children:
                 if node['id'] not in child_ids_seen:
                    f.write(f"- **{node.get('type', 'N/A').upper()}**: `{node['id']}`\n")
                    child_ids_seen.add(node['id'])

        f.write("\n---\n\n## Artifact Details\n\n")
        # Sort nodes for consistent report output
        sorted_nodes = sorted(found_nodes.values(), key=lambda x: (x['type'], x['id']))

        for item_data in sorted_nodes:
            item_id = item_data['id']
            f.write(f"### `{item_id}`\n")
            f.write(f"- **Type:** {item_data.get('type', 'N/A')}\n")
            f.write(f"- **Path:** `{item_data.get('path')}`\n")
            f.write(f"- **Hash:** `{item_data.get('hash')}`\n")

            # Show direct relationships from the edge list
            direct_children = find_children(nodes, edges, item_id)
            if direct_children:
                f.write(f"- **Connects To:**\n")
                for child in direct_children:
                    edge_type = next((edge['type'] for edge in edges if edge['from'] == item_id and edge['to'] == child['id']), "ASSOCIATED_WITH")
                    f.write(f"  - `{child['id']}` (*{edge_type}*)\n")
            f.write("\n")

    print(f"[INFO] Trace complete. Report generated at {report_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Query the MxAgile artifact index.')
    parser.add_argument('id', type=str, help='The ID of the artifact to trace.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    trace_id(args.path, args.id)
