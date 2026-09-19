import json
import os
import argparse

def check_convergence(project_root):
    """Checks if all requirements have corresponding validation evidence."""
    index_path = os.path.join(project_root, '.mxagile', 'state', 'trace-index.json')
    report_path = os.path.join(project_root, 'convergence-report.md')
    validation_dir = os.path.join(project_root, 'validation')

    if not os.path.exists(index_path):
        print(f"Error: Trace index not found at {index_path}")
        return

    with open(index_path, 'r') as f:
        index = json.load(f)

    all_reqs = index.get('requirements', {}).keys()
    missing_validation = []

    print(f"Checking convergence for {len(all_reqs)} requirement(s)...")

    for req_id in all_reqs:
        # Convention: Validation evidence is a file named TC-<req_id>.md in the validation folder
        evidence_file = f"TC-{req_id}.md"
        evidence_path = os.path.join(validation_dir, evidence_file)
        if not os.path.exists(evidence_path):
            missing_validation.append(req_id)

    # --- Generate Report ---
    with open(report_path, 'w') as f:
        f.write("# MxAgile Convergence Report\n\n")
        if not missing_validation:
            f.write("✅ All requirements have corresponding validation evidence.\n")
            print("✅ All requirements have corresponding validation evidence.")
        else:
            f.write("## ❗ Missing Validation Evidence\n\n")
            f.write("The following requirements are missing a validation evidence file (e.g., `validation/TC-REQ-XYZ.md`):\n\n")
            for req_id in missing_validation:
                f.write(f"- `{req_id}`\n")
            print(f"❗ Found {len(missing_validation)} requirements with missing validation.")

    print(f"Convergence check complete. Report generated at {report_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MxAgile Convergence Check Engine.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    check_convergence(args.path)
