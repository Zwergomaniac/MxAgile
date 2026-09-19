import sys
import json
import os
import hashlib
import subprocess
import yaml
from pathlib import Path

def calculate_sha256(filepath):
    """Calculates the SHA256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def compare_yaml_files(old_data, new_data, path=''):
    """Recursively compares two yaml data structures and returns a human-readable diff."""
    diff = []
    all_keys = set(old_data.keys()) | set(new_data.keys())

    for key in sorted(list(all_keys)):
        new_path = f"{path}.{key}" if path else key
        if key not in old_data:
            diff.append(f"- Added: `{new_path}`")
        elif key not in new_data:
            diff.append(f"- Removed: `{new_path}`")
        elif isinstance(old_data[key], dict) and isinstance(new_data[key], dict):
            diff.extend(compare_yaml_files(old_data[key], new_data[key], path=new_path))
        elif old_data[key] != new_data[key]:
            diff.append(f"- Changed: `{new_path}` from `{old_data[key]}` to `{new_data[key]}`")
    return diff

def main():
    """Main function for the refinement engine."""
    project_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.').resolve()
    index_path = project_root / ".mxagile" / "state" / "trace-index.json"
    refinements_dir = project_root / "refinements"
    report_path = project_root / "refinement-report.md"
    impact_analysis = {}

    print("🚀 Running Python-based Refinement Engine...")

    # 1. Load the trace index
    if not index_path.exists():
        print(f"Error: Trace index not found at {index_path}")
        return
    with open(index_path, 'r') as f:
        index = json.load(f)
        baseline_index = index.get('refinements', {})

    # 2. Scan the current refinements directory
    current_files = {}
    if refinements_dir.exists():
        for filepath in refinements_dir.glob("*.yml"):
            file_id = filepath.stem
            current_files[file_id] = {
                'path': str(filepath.relative_to(project_root)),
                'hash': calculate_sha256(filepath)
            }
    
    # 3. Compare baseline with current state
    new_files = []
    changed_files = []
    unchanged_files = []
    deleted_files = list(set(baseline_index.keys()) - set(current_files.keys()))

    for file_id, file_info in current_files.items():
        if file_id not in baseline_index:
            new_files.append(file_id)
        elif baseline_index[file_id]['hash'] != file_info['hash']:
            changed_files.append(file_id)
        else:
            unchanged_files.append(file_id)

    # 4. Generate the report
    report_content = ["# MxAgile Refinement Report", "", "This report summarizes changes in the 'refinements' directory.", "", "## Summary", "", "| Status    | Count |", "| --------- | ----- |", f"| New       | {len(new_files)}     |", f"| Changed   | {len(changed_files)}   |", f"| Unchanged | {len(unchanged_files)} |", f"| Deleted   | {len(deleted_files)}   |", ""]

    # 5. Add details for changed files (semantic diff)
    if changed_files:
        report_content.append("## Semantic Diffs for Changed Files")
        for file_id in changed_files:
            filepath = project_root / current_files[file_id]['path']
            report_content.append(f"\n### File: `{current_files[file_id]['path']}`")

            # --- Semantic Diff ---
            try:
                # Get old file content from git HEAD
                git_path = current_files[file_id]['path'].replace('\\', '/') # Use forward slashes for git
                old_content_raw = subprocess.check_output(["git", "show", f"HEAD:{git_path}"], cwd=project_root, text=True)
                old_data = yaml.safe_load(old_content_raw)

                # Get new file content
                with open(filepath, 'r') as f:
                    new_data = yaml.safe_load(f)

                # Compare the two
                diffs = compare_yaml_files(old_data, new_data)
                if diffs:
                    report_content.extend(diffs)
                else:
                    report_content.append("- No semantic changes detected despite different file hash (e.g., whitespace or comments).")
            except Exception as e:
                report_content.append(f"- Could not generate semantic diff: {e}")

            # --- Impact Analysis ---
            impacted_items = {'specs': [], 'tasks': []}
            # If the changed file is a requirement, find specs that relate to it
            if file_id.startswith('REQ'):
                for spec_id, spec_data in index.get('specs', {}).items():
                    if spec_data.get('Relates') == file_id:
                        impacted_items['specs'].append(spec_id)
            
            # You can add more complex traversal here (e.g., find tasks related to affected specs)
            if impacted_items['specs'] or impacted_items['tasks']:
                impact_analysis[file_id] = impacted_items

    # 6. Write the report
    if impact_analysis:
        report_content.append("\n## Impact Analysis")
        report_content.append("The following artifacts may be affected by the changes:")
        for changed_id, impacts in impact_analysis.items():
            report_content.append(f"\n### Change to `{changed_id}` may impact:")
            if impacts['specs']:
                report_content.append("- **Specs:** " + ", ".join([f"`{s}`" for s in impacts['specs']]))
            if impacts['tasks']:
                report_content.append("- **Tasks:** " + ", ".join([f"`{t}`" for t in impacts['tasks']]))

    with open(report_path, 'w') as f:
        f.write("
".join(report_content))

    print(f"✅ Report generated at: {report_path}")

if __name__ == "__main__":
    main()
