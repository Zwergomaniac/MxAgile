import json
import os
import hashlib
import yaml
import sys
from pathlib import Path

def calculate_sha256(filepath):
    sha256_hash = hashlib.sha256()
    try:
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        print(f"[DEBUG] Error reading file for hash: {filepath} - {e}")
        return None

def main():
    project_root_path = sys.argv[1] if len(sys.argv) > 1 else '.'
    project_root = Path(project_root_path).resolve()
    print(f"[DEBUG] Starting index build in root: {project_root}")

    index = {
        "requirements": {},
        "specs": {},
        "waves": {},
        "tasks": {},
        "refinements": {}
    }

    artifact_locations = [
        {"name": "requirements", "path": "requirements", "filter": "*.req"},
        {"name": "specs", "path": "specs", "filter": "*.spec"},
        {"name": "waves", "path": "waves", "filter": "*.wave"},
        {"name": "refinements", "path": "refinements", "filter": "*.yml"}
    ]

    for loc in artifact_locations:
        dir_path = project_root / loc['path']
        print(f"[DEBUG] Scanning directory: {dir_path}")
        if not dir_path.exists():
            print(f"[DEBUG] Directory does not exist. Skipping.")
            continue

        files_found = list(dir_path.glob(loc['filter']))
        print(f"[DEBUG] Found {len(files_found)} files matching '{loc['filter']}'.")

        for filepath in files_found:
            print(f"[DEBUG] Processing file: {filepath}")
            entry = {}
            file_id_from_name = filepath.stem

            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    # Simple Key: Value parsing
                    for line in f:
                        if ":" in line:
                            key, value = line.split(':', 1)
                            key = key.strip()
                            value = value.strip()
                            if key == 'SPECS':
                                value = [v.strip() for v in value.split(',')]
                            entry[key] = value

            except Exception as e:
                print(f"[DEBUG] Could not parse text for {filepath}: {e}")

            file_hash = calculate_sha256(filepath)
            if file_hash:
                entry['hash'] = file_hash
            
            entry['path'] = str(filepath.relative_to(project_root))
            final_id = entry.get('ID', file_id_from_name)
            print(f"[DEBUG]   -> Parsed ID: {final_id}")
            index[loc['name']][final_id] = entry

    # Save the index
    state_dir = project_root / ".mxagile" / "state"
    state_dir.mkdir(exist_ok=True)
    output_file = state_dir / "trace-index.json"

    print(f"[DEBUG] Writing index with {len(index['requirements'])} reqs, {len(index['specs'])} specs, {len(index['waves'])} waves...")
    try:
        with open(output_file, 'w') as f:
            json.dump(index, f, indent=2)
        print(f"Traceability index created successfully at: {output_file}")
    except Exception as e:
        print(f"[DEBUG] Error writing JSON file: {e}")

if __name__ == "__main__":
    main()
