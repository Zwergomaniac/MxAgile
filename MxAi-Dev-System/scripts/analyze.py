import json
import os
import argparse
import sys

def load_index(project_root):
    index_path = os.path.join(project_root, '.mxagile', 'state', 'artifact-trace-index.json')
    if not os.path.exists(index_path):
        return None
    with open(index_path, 'r') as f:
        return json.load(f)

def run_diagnostics(project_root):
    """Analyzes the project artifacts for diagnostics."""
    data = load_index(project_root)
    if not data:
        print("Error: Could not load trace index.")
        return

    errors = []
    warnings = []
    
    # 1. Broken References (Check paths for all entities in index)
    for category in ['specs', 'requirements']:
        if category in data:
            for rid, info in data[category].items():
                if 'path' in info:
                    path = os.path.join(project_root, info['path'])
                    if not os.path.exists(path):
                        errors.append(f"Broken Reference: {category.capitalize()} '{rid}' points to missing path: {info['path']}")

    # 2. Orphan detection
    # Example: If requirements exist but are not referenced in specs
    if 'specs' in data and 'requirements' in data:
        pass
    
    # 3. Duplicate ID check placeholder
    
    # 4. Stale State placeholder

    print("--- Analysis Report ---")
    if errors:
        print("\nERRORS:")
        for e in errors: print(f" - {e}")
    else:
        print("\nNo critical reference errors found.")
    
    if warnings:
        print("\nWARNINGS:")
        for w in warnings: print(f" - {w}")
    else:
        print("\nNo warnings found.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MxAgile Analysis Engine.')
    parser.add_argument('--path', type=str, default='.', help='The root directory of the MxAgile project.')
    args = parser.parse_args()
    run_diagnostics(args.path)
