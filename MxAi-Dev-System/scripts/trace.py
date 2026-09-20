import json
import os
import argparse

def find_parents(index, item_id, visited):

    parents = []
    for item_type, items in index.items():
        for i_id, i_data in items.items():
            if i_id in visited:
                continue

            related_ids = []
            if 'Relates' in i_data:
                relates_val = i_data['Relates']
                if isinstance(relates_val, list):
                    related_ids.extend(relates_val)
                else:
                    related_ids.append(relates_val)

            if 'requirements' in i_data:
                reqs_val = i_data['requirements']
                if isinstance(reqs_val, list):
                    for req in reqs_val:
                        if isinstance(req, dict) and 'id' in req:
                            related_ids.append(req['id'])
                        else:
                            related_ids.append(req)
                elif isinstance(reqs_val, dict) and 'id' in reqs_val:
                    related_ids.append(reqs_val['id'])
                else:
                    related_ids.append(reqs_val)

            if item_id in related_ids:
                parents.append((i_id, item_type, i_data))
    return parents

def find_children(index, item, visited):
    children = []
    related_ids = []

    if 'Relates' in item:
        relates_val = item['Relates']
        if isinstance(relates_val, list):
            related_ids.extend(relates_val)
        else:
            related_ids.append(relates_val)

    if 'requirements' in item:
        reqs_val = item['requirements']
        if isinstance(reqs_val, list):
            for req in reqs_val:
                if isinstance(req, dict) and 'id' in req:
                    related_ids.append(req['id'])
                else:
                    related_ids.append(req)
        elif isinstance(reqs_val, dict) and 'id' in reqs_val:
            related_ids.append(reqs_val['id'])
        else:
            related_ids.append(reqs_val)

    for r_id in related_ids:
        if r_id in visited:
            continue
        for item_type, items in index.items():
            if r_id in items:
                children.append((r_id, item_type, items[r_id]))
                break
    return children

def get_all_parents(index, item_id, visited):
    """Recursively find all parents."""
    all_parents = []
    visited.add(item_id)
    
    direct_parents = find_parents(index, item_id, visited)
    for p_id, p_type, p_data in direct_parents:
        if p_id not in visited:
            all_parents.append((p_id, p_type, p_data))
            all_parents.extend(get_all_parents(index, p_id, visited))
            
    return all_parents

def get_all_children(index, item_id, item_data, visited):
    """Recursively find all children."""
    all_children = []
    visited.add(item_id)
    
    direct_children = find_children(index, item_data, visited)
    for c_id, c_type, c_data in direct_children:
        if c_id not in visited:
            all_children.append((c_id, c_type, c_data))
            all_children.extend(get_all_children(index, c_id, c_data, visited))

    return all_children

def trace_id(project_root, start_id):
    """Traces the relationships for a given ID through the index."""
    index_path = os.path.join(project_root, '.mxagile', 'state', 'trace-index.json')
    report_path = os.path.join(project_root, 'trace-report.md')

    if not os.path.exists(index_path):
        print(f"Error: Trace index not found at {index_path}")
        return

    with open(index_path, 'r') as f:
        index = json.load(f)

    print(f"Tracing relationships for ID: {start_id}\n")

    # Find the starting item
    start_item = None
    start_type = None
    for item_type, items in index.items():
        if start_id in items:
            start_item = items[start_id]
            start_type = item_type
            break
    
    if not start_item:
        print(f"ID '{start_id}' not found in any artifact type.")
        return

    visited = set()
    all_parents = get_all_parents(index, start_id, visited)
    
    # Reset visited for children traversal to ensure full graph from start_id down
    visited = set()
    all_children = get_all_children(index, start_id, start_item, visited)
    
    found_items = [(start_id, start_type, start_item)] + all_parents + all_children
    
    # --- Generate Report -- -
    with open(report_path, 'w') as f:
        f.write(f"# MxAgile Traceability Report for: {start_id}\n\n")
        
        f.write("## Trace Hierarchy\n\n")

        # Display parents
        if all_parents:
            f.write("### Parents (Upstream)\n")
            for item_id, item_type, item_data in reversed(all_parents): # Show top-down
                f.write(f"- **ID:** `{item_id}` ({item_type})\n")

        # Display the starting item
        f.write(f"### Start Item\n")
        f.write(f"- **ID:** `{start_id}` ({start_type})\n")

        # Display children
        if all_children:
            f.write("### Children (Downstream)\n")
            for item_id, item_type, item_data in all_children:
                f.write(f"- **ID:** `{item_id}` ({item_type})\n")

        f.write("\n## Item Details\n\n")
        for item_id, item_type, item_data in sorted(found_items, key=lambda x: x[0]):
            f.write(f"### `{item_id}` ({item_type})\n")
            f.write(f"- **Path:** `{item_data.get('path')}`\n")
            desc = item_data.get('Description', 'N/A')
            f.write(f"- **Description:** {desc}\n")
            if 'Relates' in item_data:
                f.write(f"- **Relates to:** `{item_data['Relates']}`\n")
            if 'requirements' in item_data:
                f.write(f"- **Requirements:** `{item_data['requirements']}`\n")
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
