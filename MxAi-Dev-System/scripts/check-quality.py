import json
import os
import argparse

def find_checklist_path(start_path):
    """Searches upward from start_path for quality-checklist.json."""
    path = os.path.abspath(start_path)
    while True:
        checklist_path = os.path.join(path, 'quality-checklist.json')
        if os.path.exists(checklist_path):
            return checklist_path
        parent_path = os.path.dirname(path)
        if parent_path == path:  # Reached the root of the filesystem
            return None
        path = parent_path

def parse_artifact(file_path):
    """Parses a simple key: value artifact file."""
    data = {}
    with open(file_path, 'r') as f:
        for line in f:
            if ':' in line:
                key, value = line.split(':', 1)
                data[key.strip()] = value.strip()
    return data

def check_quality(file_path, project_root):
    """Checks a single artifact file against the quality checklist."""
    checklist_path = find_checklist_path(project_root)
    violations = []

    if not os.path.exists(checklist_path):
        print(f"Error: quality-checklist.json not found at {checklist_path}")
        return 1

    if not os.path.exists(file_path):
        print(f"Error: File to check not found at {file_path}")
        return 1

    with open(checklist_path, 'r') as f:
        checklist = json.load(f)
    
    artifact_data = parse_artifact(file_path)
    rules = checklist.get('spec', {})

    # Check for required fields
    for field in rules.get('required_fields', []):
        if field not in artifact_data or not artifact_data[field]:
            violations.append(f"Missing required field: '{field}'")

    # Check for description length
    min_len = rules.get('min_description_length', 0)
    if min_len > 0 and ('Description' not in artifact_data or len(artifact_data['Description']) < min_len):
        violations.append(f"Description must be at least {min_len} characters long.")

    if violations:
        print(f"--- Quality Violations in {os.path.basename(file_path)} ---")
        for v in violations:
            print(f"- {v}")
        return 1 # Return non-zero exit code for failure
    else:
        print(f"✅ Quality check passed for {os.path.basename(file_path)}.")
        return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MxAgile Quality Gate Engine.')
    parser.add_argument('file', type=str, help='The path to the artifact file to check.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    exit_code = check_quality(args.file, args.path)
    exit(exit_code)
