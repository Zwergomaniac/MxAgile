import json
import os
import argparse

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
    index_path = os.path.join(project_root, '.mxagile', 'state', 'artifact-trace-index.json')
    report_path = os.path.join(project_root, 'trace-report.md')

    if not os.path.exists(index_path):
        print(f"Error: Trace index not found at {index_path}")
        return

    with open(index_path, 'r') as f:
        trace_data = json.load(f)
    
    nodes = trace_data.get('nodes', [])
    edges = trace_data.get('edges', [])

    print(f"Tracing relationships for ID: {start_id}\n")

    # Find the starting item
    start_item = None
    for node in nodes:
        if node['id'] == start_id:
            start_item = node
            break
    
    if not start_item:
        print(f"ID '{start_id}' not found in any artifact type.")
        return

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
    with open(report_path, 'w') as f:
        f.write(f"# MxAgile Traceability Report for: {start_id}\n\n")
        
        f.write("## Trace Hierarchy\n\n")

        # Display parents
        if all_parents:
            f.write("### Parents (Upstream)\n")
            # Reverse for top-down display, and ensure no duplicates
            parent_ids_seen = set()
            for node in reversed(all_parents):
                if node['id'] not in parent_ids_seen:
                    f.write(f"- **ID:** `{node['id']}` ({node.get('type', 'N/A')})\n")
                    parent_ids_seen.add(node['id'])

        # Display the starting item
        f.write(f"### Start Item\n")
        f.write(f"- **ID:** `{start_item['id']}` ({start_item.get('type', 'N/A')})\n")

        # Display children
        if all_children:
            f.write("### Children (Downstream)\n")
            child_ids_seen = set()
            for node in all_children:
                 if node['id'] not in child_ids_seen:
                    f.write(f"- **ID:** `{node['id']}` ({node.get('type', 'N/A')})\n")
                    child_ids_seen.add(node['id'])

        f.write("\n## Item Details\n\n")
        for item_id, item_data in sorted(found_nodes.items(), key=lambda x: x[0]):
            f.write(f"### `{item_id}` ({item_data.get('type', 'N/A')})\n")
            f.write(f"- **Path:** `{item_data.get('path')}`\n")
            desc = item_data.get('description', 'N/A')
            f.write(f"- **Description:** {desc}\n")

            # Show direct relationships from the edge list
            direct_children = find_children(nodes, edges, item_id)
            if direct_children:
                f.write(f"- **Connects to:**\n")
                for child in direct_children:
                    f.write(f"  - `{child['id']}` ({child.get('type', 'N/A')})\n")
            f.write("\n")


    print(f"Trace complete. Report generated at {report_path}")
    print("--- Report Content ---")
    with open(report_path, 'r') as f:
        print(f.read())

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MxAgile Traceability Engine.')
    parser.add_argument('id', type=str, help='The ID of the artifact to trace.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    trace_id(args.path, args.id)
