import json
import os
import argparse

def analyze_orphans(project_root):
    """Analyzes the trace index to find orphan specs and unused requirements."""
    index_path = os.path.join(project_root, '.mxagile', 'state', 'artifact-trace-index.json')
    report_path = os.path.join(project_root, 'analysis-report.md')

    if not os.path.exists(index_path):
        print(f"Error: Trace index not found at {index_path}")
        return

    with open(index_path, 'r') as f:
        trace_data = json.load(f)

    nodes = trace_data.get('nodes', [])
    edges = trace_data.get('edges', [])

    specs = {node['id']: node for node in nodes if node.get('type') == 'Spec'}
    reqs = {node['id']: node for node in nodes if node.get('type') == 'Requirement'}

    spec_ids = set(specs.keys())
    req_ids = set(reqs.keys())

    # Find which requirements are referenced by specs
    referenced_reqs = set()
    for edge in edges:
        if edge['from'] in spec_ids and edge['to'] in req_ids:
            referenced_reqs.add(edge['to'])

    # Find which specs reference requirements
    specs_with_refs = set()
    for edge in edges:
        if edge['from'] in spec_ids and edge['to'] in req_ids:
            specs_with_refs.add(edge['from'])
            
    orphan_specs = list(spec_ids - specs_with_refs)
    unused_reqs = list(req_ids - referenced_reqs)

    # Generate Report
    with open(report_path, 'w') as f:
        f.write("# MxAgile Analysis Report\n\n")
        f.write("This report highlights potential inconsistencies and quality issues in the project artifacts.\n\n")
        f.write("## Orphan Analysis\n\n")

        if not orphan_specs and not unused_reqs:
            f.write("✅ No orphan specs or unused requirements found.\n")
        else:
            if orphan_specs:
                f.write("###  Orphan Specs\n")
                f.write("The following specs are not related to any existing requirement:\n")
                for spec_id in orphan_specs:
                    f.write(f"- `{spec_id}`\n")
                f.write("\n")

            if unused_reqs:
                f.write("### Unused Requirements\n")
                f.write("The following requirements are not realized by any spec:\n")
                for req_id in unused_reqs:
                    f.write(f"- `{req_id}`\n")

    print(f"Analysis complete. Report generated at {report_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MxAgile Analysis Engine.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    analyze_orphans(args.path)
