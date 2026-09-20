import json
import sys
import os

GRAPH_PATH = ".mxagile/state/artifact-graph.json"

def load_graph():
    if not os.path.exists(GRAPH_PATH):
        print(f"Error: Graph file not found at {GRAPH_PATH}")
        sys.exit(1)
    with open(GRAPH_PATH, 'r') as f:
        return json.load(f)

def save_graph(graph):
    with open(GRAPH_PATH, 'w') as f:
        json.dump(graph, f, indent=2)

def propagate_stale(graph, stale_ids):
    # Build adjacency list
    adj = {}
    for edge in graph.get('edges', []):
        src = edge['from']
        dst = edge['to']
        if src not in adj:
            adj[src] = []
        adj[src].append(dst)

    stale_nodes = set(stale_ids)
    to_visit = list(stale_ids)
    
    # Traverse downstream
    while to_visit:
        current = to_visit.pop(0)
        if current in adj:
            for neighbor in adj[current]:
                if neighbor not in stale_nodes:
                    stale_nodes.add(neighbor)
                    to_visit.append(neighbor)
    
    # Update statuses
    updated_count = 0
    for node in graph.get('nodes', []):
        if node['id'] in stale_nodes:
            if node.get('status') != 'Stale':
                node['status'] = 'Stale'
                updated_count += 1
                
    return stale_nodes, updated_count

def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/propagate_stale.py <node_id1> [<node_id2> ...]")
        sys.exit(1)
        
    stale_input = sys.argv[1:]
    graph = load_graph()
    
    stale_nodes, updated_count = propagate_stale(graph, stale_input)
    
    save_graph(graph)
    
    print(f"Summary: {len(stale_nodes)} nodes marked as 'Stale' ({updated_count} updated).")
    print("Stale nodes:", ", ".join(sorted(stale_nodes)))

if __name__ == "__main__":
    main()
