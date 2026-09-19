import sys
import json
import os
import hashlib
import subprocess
from pathlib import Path
from bs4 import BeautifulSoup

def calculate_sha256(filepath):
    """Calculates the SHA256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def compare_html_files(old_html, new_html):
    """
    Performs a semantic diff on two HTML files.
    """
    old_soup = BeautifulSoup(old_html, 'html.parser')
    new_soup = BeautifulSoup(new_html, 'html.parser')

    old_style = old_soup.find('style')
    new_style = new_soup.find('style')

    old_style_content = old_style.string if old_style else ""
    new_style_content = new_style.string if new_style else ""

    if old_style_content != new_style_content:
        return [{'type': 'VISUAL', 'detail': 'Changes detected in <style> block.'}]

    return []

def main():
    """Main function for the mockup analysis engine."""
    project_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.').resolve()
    index_path = project_root / ".mxagile" / "state" / "trace-index.json"
    mockups_dir = project_root / "input-resources" / "ui-ux"
    report_path = project_root / "mockup-report.md"

    print("Running Python-based Mockup Analysis Engine...")

    # 1. Load the trace index
    if not index_path.exists():
        print(f"Error: Trace index not found at {index_path}")
        return
    with open(index_path, 'r') as f:
        index = json.load(f)
        baseline_index = index.get('mockups', {})

    # 2. Scan the current mockups directory
    current_files = {}
    if mockups_dir.exists():
        for filepath in mockups_dir.glob("*.html"):
            file_id = filepath.stem
            file_hash = calculate_sha256(filepath)
            current_files[file_id] = {
                'path': str(filepath.relative_to(project_root)),
                'hash': file_hash
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
    report_content = ["# MxAgile Mockup Report", "", f"This report summarizes changes in the `{mockups_dir.relative_to(project_root)}` directory.", "", "## Summary", "", "| Status    | Count |", "| --------- | ----- |", f"| New       | {len(new_files)}     |", f"| Changed   | {len(changed_files)}   |", f"| Unchanged | {len(unchanged_files)} |", f"| Deleted   | {len(deleted_files)}   |", ""]

    # 5. Add details for changed files
    if changed_files:
        report_content.append("## Details for Changed Files")
        for file_id in changed_files:
            file_path_str = current_files[file_id]['path']
            filepath = project_root / file_path_str
            report_content.append(f'\n### File: `{file_path_str}`')
            
            try:
                # Get old version from git
                old_content = subprocess.check_output(['git', 'show', f'HEAD:{file_path_str}'], cwd=project_root).decode('utf-8')
                
                # Get new version from filesystem
                with open(filepath, 'r', encoding='utf-8') as f:
                    new_content = f.read()
                
                # Compare the two versions
                diffs = compare_html_files(old_content, new_content)
                
                if diffs:
                    for diff in diffs:
                        report_content.append(f"- **{diff['type']}**: {diff['detail']}")
                else:
                    report_content.append("- No semantic changes detected.")

            except (subprocess.CalledProcessError, FileNotFoundError) as e:
                report_content.append(f"- Could not retrieve previous version of file. Error: {e}")
            except Exception as e:
                report_content.append(f"- An error occurred during analysis: {e}")


    # 6. Write the report
    with open(report_path, 'w') as f:
        f.write("\n".join(report_content))

    print(f"Report generated at: {report_path}")

if __name__ == "__main__":
    main()
