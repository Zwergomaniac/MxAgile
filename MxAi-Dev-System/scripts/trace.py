import json
import os
import argparse

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

    # --- This is a simplified trace. A real implementation would be a full graph traversal. ---
    found_items = []

    # Find the starting item
    start_item = None
    start_type = None
    for item_type, items in index.items():
        if start_id in items:
            start_item = items[start_id]
            start_type = item_type
            found_items.append((start_id, start_type, start_item))
            break
    
    if not start_item:
        print(f"ID '{start_id}' not found in any artifact type.")
        return

    # Find children (e.g., specs related to a req)
    if start_type == 'requirements':
        for spec_id, spec_data in index.get('specs', {}).items():
            if spec_data.get('Relates') == start_id:
                found_items.append((spec_id, 'specs', spec_data))

    # Find parent (e.g., req a spec relates to)
    if start_type == 'specs':
        parent_req_id = start_item.get('Relates')
        if parent_req_id and parent_req_id in index.get('requirements', {}):
            found_items.append((parent_req_id, 'requirements', index['requirements'][parent_req_id]))
    
    # --- Generate Report ---
    with open(report_path, 'w') as f:
        f.write(f"# MxAgile Traceability Report for: {start_id}\n\n")
        for item_id, item_type, item_data in found_items:
            f.write(f"- **ID:** `{item_id}` ({item_type})\n")
            f.write(f"  - **Path:** `{item_data.get('path')}`\n")
            desc = item_data.get('Description', 'N/A')
            f.write(f"  - **Description:** {desc}\n")

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
