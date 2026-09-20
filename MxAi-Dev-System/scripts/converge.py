import json
import os
import argparse

def check_convergence(project_root):
    """Checks if all requirements have corresponding validation evidence and links to Mendix artifacts."""
    index_path = os.path.join(project_root, '.mxagile', 'state', 'artifact-trace-index.json')
    report_path = os.path.join(project_root, 'convergence-report.md')
    validation_dir = os.path.join(project_root, 'validation')

    # Load Trace Index
    all_reqs = {}
    stale_nodes = []
    req_implementation = {}

    if os.path.exists(index_path):
        with open(index_path, 'r') as f:
            trace_data = json.load(f)
            nodes = trace_data.get('nodes', [])
            edges = trace_data.get('edges', [])

            all_reqs = {node['id']: node for node in nodes if node.get('type') == 'Requirement'}
            
            # Identify stale nodes
            stale_nodes = [node['id'] for node in nodes if node.get('status') == 'Stale']

            # Track implementation status for each requirement
            for req_id in all_reqs.keys():
                req_implementation[req_id] = []
                # Find edges from this requirement to other artifacts
                for edge in edges:
                    if edge['from'] == req_id:
                        target_id = edge['to']
                        # Add the target artifact to the implementation list
                        if target_id not in all_reqs:  # Assuming target is an artifact if not a requirement
                            req_implementation[req_id].append(target_id)
    
    missing_validation = []
    for req_id in all_reqs.keys():
        evidence_file = f"TC-{req_id}.md"
        if not os.path.exists(os.path.join(validation_dir, evidence_file)):
            missing_validation.append(req_id)

    # --- Generate Report ---
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write("# MxAgile Convergence Report\n\n")

        # 1. Validation Evidence
        if not missing_validation:
            f.write("✅ All requirements have corresponding validation evidence.\n\n")
        else:
            f.write("## ❗ Missing Validation Evidence\n\n")
            for req_id in missing_validation:
                f.write(f"- `{req_id}`\n")
            f.write("\n")

        # 2. Stale Nodes
        if stale_nodes:
            f.write("## ⚠️ Stale Nodes\n\n")
            for node_id in stale_nodes:
                f.write(f"- `{node_id}`\n")
            f.write("\n")
        else:
            f.write("✅ No stale nodes identified.\n\n")

        # 3. Requirement Implementation Summary
        f.write("## 📊 Requirement Implementation Summary\n\n")
        f.write("| Requirement | Implemented Artifacts |\n")
        f.write("|-------------|-----------------------|\n")
        for req_id, artifacts in req_implementation.items():
            artifact_list = ", ".join([f"`{a}`" for a in artifacts]) if artifacts else "None"
            f.write(f"| `{req_id}` | {artifact_list} |\n")
        f.write("\n")

    print(f"Convergence check complete. Report generated at {report_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MxAgile Convergence Check Engine.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    check_convergence(args.path)
