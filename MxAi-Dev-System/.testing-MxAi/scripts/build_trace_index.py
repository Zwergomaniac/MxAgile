import sys
import json
import os
import hashlib
import yaml
from pathlib import Path

def calculate_sha256(filepath):
    """Calculates the SHA256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def main():
    """Main function for the trace indexer."""
    project_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.').resolve()
    print(f"Building MxAgile traceability index in: {project_root}")

    index = {
        "requirements": {},
        "specs": {},
        "waves": {},
        "tasks": {},
        "refinements": {}
    }

    # For now, we only focus on the refinements part for the test
    artifact_locations = [
        {"name": "refinements", "path": "refinements", "filter": "*.yml"}
        # In the full YAML conversion, we'll add the other types here
    ]

    for loc in artifact_locations:
        dir_path = project_root / loc['path']
        if not dir_path.exists():
            continue

        for filepath in dir_path.glob(loc['filter']):
            file_id = filepath.stem
            
            entry = {}
            try:
                with open(filepath, 'r') as f:
                    data = yaml.safe_load(f)
                    if data:
                        entry.update(data)
            except Exception as e:
                print(f"Warning: Could not parse YAML for {filepath}: {e}")

            entry['path'] = str(filepath.relative_to(project_root))
            entry['hash'] = calculate_sha256(filepath)
            
            # Use file stem as ID if not present in content
            final_id = entry.get('ID', file_id)

            index[loc['name']][final_id] = entry

    # Save the index
    state_dir = project_root / ".mxagile" / "state"
    state_dir.mkdir(exist_ok=True)
    output_file = state_dir / "trace-index.json"

    with open(output_file, 'w') as f:
        json.dump(index, f, indent=2)

    print(f"Traceability index created successfully at: {output_file}")

if __name__ == "__main__":
    main()
