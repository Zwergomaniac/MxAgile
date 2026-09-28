"""
RETIRED — scripts/refine.py

This script is retired as of the SPA mockup bundle hardening (2026-09-28).

What it did:
  Semantic HTML diff between two single-file mockup versions, using the old
  trace-index.json format for mockup hash baselines.

Why it was retired:
  1. It relied on the old .mxagile/state/trace-index.json format which is
     now empty/deprecated. The canonical index is artifact-index.json.
  2. Single-file HTML mockup comparison is superseded by the SPA bundle
     revision model. Revision identity uses deterministic bundle hashing
     (artifact_hashing.hash_spa_bundle) rather than per-file HTML normalization.
  3. The semantic HTML normalization approach (removing IDs, prettifying) was
     intentionally removed to prevent aggressive normalization from obscuring
     content changes.

Replacement:
  - For bundle identity: artifact_hashing.hash_spa_bundle(bundle_dir)
  - For revision history: planning/target-mockups/<mockup-name>/_history/REV-NNN/
  - For creating revisions: scripts/create_revision.py
  - For impact analysis: scripts/resolve_impact.py
  - For artifact graph: scripts/build_artifact_index.py + artifact-index.json
  - For stale propagation: scripts/propagate_stale.py
  - For diagnostics: scripts/analyze.py

If you need the old HTML diff behavior for legacy single-file mockups, extract
the compare_html_files() function and call it directly. It has no dependency
on the trace index format.
"""

import sys


def main():
    print('ERROR: scripts/refine.py is retired.')
    print()
    print('Use these replacements:')
    print('  Bundle identity:   python scripts/build_artifact_index.py <project_root>')
    print('  Create revision:   python scripts/create_revision.py --help')
    print('  Impact resolution: python scripts/resolve_impact.py --help')
    print('  Diagnostics:       python scripts/analyze.py --path <project_root>')
    sys.exit(1)


if __name__ == '__main__':
    main()
