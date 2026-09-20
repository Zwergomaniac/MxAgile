import hashlib
import yaml
from bs4 import BeautifulSoup
import bs4

def hash_mockup(filepath):
    """
    Normalizes an HTML file by removing comments, normalizing whitespace,
    removing 'id' attributes, and hashing the DOM structure.
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        soup = BeautifulSoup(f, 'html.parser')
    
    # Remove comments
    for comment in soup.find_all(text=lambda text: isinstance(text, bs4.Comment)):
        comment.extract()
    
    # Remove IDs
    for tag in soup.find_all(attrs={'id': True}):
        del tag['id']
    
    # Canonicalize structure by prettifying (also handles whitespace)
    # and hashing the result
    return hashlib.sha256(soup.prettify().encode('utf-8')).hexdigest()

def sort_dict(d):
    """Recursively sorts dictionary keys."""
    if isinstance(d, dict):
        return {k: sort_dict(v) for k, v in sorted(d.items())}
    if isinstance(d, list):
        return [sort_dict(i) for i in d]
    return d

def hash_page_yaml(filepath):
    """
    Loads a YAML file, sorts keys to ensure consistency, 
    and returns a hash of the normalized content.
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    
    normalized_data = sort_dict(data)
    # Dump with sort_keys=True just in case, though sort_dict handles it
    content = yaml.dump(normalized_data, sort_keys=True)
    return hashlib.sha256(content.encode('utf-8')).hexdigest()
