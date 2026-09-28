import hashlib
import os
import yaml
from bs4 import BeautifulSoup
import bs4

# OS metadata files excluded from bundle hash (not mockup-owned content)
_EXCLUDED_FILENAMES = frozenset([
    '.DS_Store', 'Thumbs.db', 'desktop.ini', '.gitkeep', '.gitignore',
])

# Editor/system file patterns excluded from bundle hash
_EXCLUDED_SUFFIXES = ('.swp', '.swo', '.tmp', '.bak', '~')

# Directories excluded from bundle hash traversal
_EXCLUDED_DIRS = frozenset(['_history', 'node_modules', '.git'])


def hash_mockup(filepath):
    """
    Normalizes an HTML file by removing comments, normalizing whitespace,
    removing 'id' attributes, and hashing the DOM structure.

    NOTE: This function applies semantic HTML normalization and is suitable
    for comparing two HTML files for content-equivalence. It is NOT used
    for bundle identity — use hash_spa_bundle() for bundle identity instead.
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        soup = BeautifulSoup(f, 'html.parser')

    # Remove comments
    for comment in soup.find_all(text=lambda text: isinstance(text, bs4.Comment)):
        comment.extract()

    # Remove IDs
    for tag in soup.find_all(attrs={'id': True}):
        del tag['id']

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
    content = yaml.dump(normalized_data, sort_keys=True)
    return hashlib.sha256(content.encode('utf-8')).hexdigest()


def _file_sha256(filepath):
    """SHA-256 of raw file bytes. Binary mode, no normalization."""
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            sha256.update(chunk)
    return sha256.hexdigest()


def _is_excluded_file(filename):
    """Returns True if this file should be excluded from bundle hash."""
    if filename in _EXCLUDED_FILENAMES:
        return True
    if filename.endswith(_EXCLUDED_SUFFIXES):
        return True
    return False


def hash_spa_bundle(bundle_dir, exclude_revision_yaml=True):
    """
    Compute a deterministic SHA-256 identity hash for a SPA mockup bundle directory.

    Algorithm (canonical per policies/spa-mockup-bundle.md):
    1. Enumerate all files recursively, excluding _history/, node_modules/, OS metadata.
    2. Optionally exclude revision.yaml (to avoid circular hashing of the manifest itself).
    3. For each included file:
       a. Compute rel_path = canonical path from bundle_dir, forward slashes, no leading ./
       b. Compute file_hash = SHA-256 of raw file bytes (binary, no normalization)
    4. Sort (rel_path, file_hash) pairs by rel_path lexicographically ascending.
    5. Build manifest: join "<rel_path>:<file_hash>" lines with newline.
    6. Return sha256:<SHA-256 of UTF-8 manifest string>

    Platform portable: uses raw bytes, forward-slash paths, no line-ending normalization.

    Args:
        bundle_dir: Path-like, root of the bundle directory.
        exclude_revision_yaml: If True, excludes revision.yaml from hash (default True).

    Returns:
        str: "sha256:<hex_digest>" or None if bundle_dir does not exist.
    """
    from pathlib import Path
    bundle_path = Path(bundle_dir).resolve()

    if not bundle_path.is_dir():
        return None

    manifest_entries = []

    for dirpath, dirnames, filenames in os.walk(bundle_path):
        # Prune excluded directories in-place so os.walk skips them
        dirnames[:] = [d for d in dirnames if d not in _EXCLUDED_DIRS]

        for filename in filenames:
            if _is_excluded_file(filename):
                continue
            if exclude_revision_yaml and filename == 'revision.yaml':
                continue

            abs_path = os.path.join(dirpath, filename)

            # Canonical relative path: forward slashes, no leading ./
            rel = os.path.relpath(abs_path, bundle_path)
            canonical_rel = rel.replace('\\', '/')

            file_hash = _file_sha256(abs_path)
            manifest_entries.append((canonical_rel, file_hash))

    # Sort by canonical relative path (lexicographic ascending)
    manifest_entries.sort(key=lambda x: x[0])

    # Build manifest string
    manifest_str = '\n'.join(f'{rel}:{fh}' for rel, fh in manifest_entries)

    # SHA-256 of UTF-8 encoded manifest
    bundle_hash = hashlib.sha256(manifest_str.encode('utf-8')).hexdigest()
    return f'sha256:{bundle_hash}'


def compute_source_fingerprint(indexed_files):
    """
    Compute a deterministic source fingerprint from a list of (canonical_path, sha256) tuples.

    Used by build_artifact_index.py to detect whether the index is stale relative to
    the canonical artifact files it was built from.

    Args:
        indexed_files: Iterable of (str canonical_path, str sha256_hex) tuples.

    Returns:
        str: "sha256:<hex_digest>"
    """
    sorted_entries = sorted(indexed_files, key=lambda x: x[0])
    manifest_str = '\n'.join(f'{path}:{sha}' for path, sha in sorted_entries)
    fp = hashlib.sha256(manifest_str.encode('utf-8')).hexdigest()
    return f'sha256:{fp}'
