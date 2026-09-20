import json
import os
import hashlib
import argparse

def calculate_file_hash(filepath):
    hasher = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    return hasher.hexdigest()

def build_artifact_graph(project_root):
    graph = {
        "nodes": [],
        "edges": []
    }
    
    # Define directories to scan and their potential types
    scan_configs = [
        {"path": "input-resources", "type": "Mockup"},
        {"path": "requirements", "type": "Requirement"},
        # Add more mappings as needed based on the supportedChain
    ]
    
    found_nodes = {}
    
    # 1. Scan and populate nodes
    for config in scan_configs:
        dir_path = os.path.join(project_root, config["path"])
        artifact_type = config["type"]
        
        if not os.path.exists(dir_path):
            continue
            
        for root, _, files in os.walk(dir_path):
            for file in files:
                filepath = os.path.join(root, file)
                rel_path = os.path.relpath(filepath, project_root)
                
                node = {
                    "id": rel_path,
                    "type": artifact_type,
                    "hash": calculate_file_hash(filepath),
                    "status": "Active"
                }
                found_nodes[rel_path] = node
                graph["nodes"].append(node)
                
    # 2. Simple pattern matching for edges
    # E.g., if 'X.yaml' exists and 'X.md' exists in requirements, assume a link
    # This is a naive implementation based on filename without extension
    
    node_ids = list(found_nodes.keys())
    for id1 in node_ids:
        name1 = os.path.splitext(os.path.basename(id1))[0]
        
        for id2 in node_ids:
            if id1 == id2:
                continue
                
            name2 = os.path.splitext(os.path.basename(id2))[0]
            
            if name1 == name2:
                # Potential link
                graph["edges"].append({
                    "from": id1,
                    "to": id2,
                    "relationship": "related"
                })
                
    # 3. Save the graph
    output_dir = os.path.join(project_root, ".mxagile", "state")
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, "artifact-graph.json")
    
    with open(output_file, 'w') as f:
        json.dump(graph, f, indent=2)
        
    print(f"Artifact graph saved to {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build artifact graph.")
    parser.add_argument("--project-root", default=".", help="Project root directory (default: .)")
    args = parser.parse_args()
    build_artifact_graph(args.project_root)
