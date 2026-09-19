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
    diffs = []
    old_soup = BeautifulSoup(old_html, 'html.parser')
    new_soup = BeautifulSoup(new_html, 'html.parser')

    # 1. Style changes
    old_style = old_soup.find('style')
    new_style = new_soup.find('style')
    old_style_content = old_style.string if old_style else ""
    new_style_content = new_style.string if new_style else ""

    if old_style_content != new_style_content:
        diffs.append({'type': 'VISUAL', 'detail': 'Changes detected in <style> block.'})

    # 2. Data input changes
    input_tags = ['input', 'select', 'textarea']
    old_inputs = {tag.get('id') for tag in old_soup.find_all(input_tags) if tag.get('id')}
    new_inputs = {tag.get('id') for tag in new_soup.find_all(input_tags) if tag.get('id')}

    added_inputs = new_inputs - old_inputs
    removed_inputs = old_inputs - new_inputs

    for input_id in added_inputs:
        diffs.append({'type': 'DATA', 'detail': f'New input field added: #{input_id}'})
    
    for input_id in removed_inputs:
        diffs.append({'type': 'DATA', 'detail': f'Input field removed: #{input_id}'})

    # 3. Interaction changes (buttons and links)
    interaction_tags = ['button', 'a']
    old_interactions = {tag.get('id') for tag in old_soup.find_all(interaction_tags) if tag.get('id')}
    new_interactions = {tag.get('id') for tag in new_soup.find_all(interaction_tags) if tag.get('id')}

    added_interactions = new_interactions - old_interactions
    removed_interactions = old_interactions - new_interactions

    for interaction_id in added_interactions:
        diffs.append({'type': 'INTERACTION', 'detail': f'New button or link added: #{interaction_id}'})

    for interaction_id in removed_interactions:
        diffs.append({'type': 'INTERACTION', 'detail': f'Button or link removed: #{interaction_id}'})

    return diffs

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
                git_path = file_path_str.replace('\\', '/')
                old_content = subprocess.check_output(['git', 'show', f'HEAD:./{git_path}'], cwd=project_root).decode('utf-8')
                
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
