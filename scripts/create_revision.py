"""
MxAgile SPA Bundle Revision Creator

Creates an accepted revision of a SPA mockup bundle. This is the ONLY authorized
way to create a revision — agents and gates do not create revisions directly.

Preconditions (enforced):
  1. The target working bundle must exist.
  2. A planning/decisions/DEC-NNN.md file must be provided as acceptance provenance.
  3. The working bundle must actually differ from the last accepted revision (if any).

Usage:
  python scripts/create_revision.py [--path <project_root>] --mockup <mockup_name>
                                    --decision <DEC-NNN>
                                    [--reason <"reason text">]
                                    [--impact-scope targeted|cross_cutting|full|unknown]
                                    [--affected-screens PAGE-A PAGE-B ...]
                                    [--change-classification material|non_material|unknown]
                                    [--dry-run]

Examples:
  python scripts/create_revision.py --mockup kidscompass-web --decision DEC-061
  python scripts/create_revision.py --mockup admin-portal --decision DEC-042 --impact-scope targeted --affected-screens PAGE-CALENDAR
  python scripts/create_revision.py --mockup kidscompass-web --decision DEC-099 --dry-run

What this script does:
  1. Computes the current working bundle hash.
  2. Determines the next revision ID (REV-NNN sequential).
  3. Verifies the DEC-NNN file exists in planning/decisions/.
  4. Copies the working bundle to _history/REV-NNN/.
  5. Creates _history/REV-NNN/revision.yaml with:
     - revision_id, mockup_name, created_at, bundle_hash
     - lifecycle_trigger: refinement_accepted
     - acceptance_decisions: [DEC-NNN]
     - impact fields from arguments
  6. Reports the new revision ID.

The caller (developer or CI) is responsible for:
  - Updating the UI inventory YAML files (target_revision, bundle_hash fields)
  - Committing the new revision directory
"""

import argparse
import datetime
import json
import os
import re
import shutil
import sys
import yaml
from pathlib import Path

# Ensure artifact_hashing is importable from same scripts/ directory
sys.path.insert(0, str(Path(__file__).parent))
from artifact_hashing import hash_spa_bundle


def _find_existing_revisions(history_dir):
    """Return sorted list of existing revision IDs (e.g. ['REV-001', 'REV-002'])."""
    if not history_dir.exists():
        return []
    revisions = []
    for entry in history_dir.iterdir():
        if entry.is_dir() and re.match(r'^REV-\d+$', entry.name):
            revisions.append(entry.name)
    revisions.sort()
    return revisions


def _next_revision_id(existing):
    """Compute the next sequential revision ID."""
    if not existing:
        return 'REV-001'
    last = existing[-1]
    num = int(last.replace('REV-', ''))
    return f'REV-{num + 1:03d}'


def create_revision(project_root, mockup_name, decision_id, reason=None,
                    impact_scope='unknown', affected_screens=None,
                    change_classification='unknown', dry_run=False):
    root = Path(project_root).resolve()

    working_bundle = root / 'planning' / 'target-mockups' / mockup_name
    if not working_bundle.exists():
        print(f'[ERROR] Working bundle not found: {working_bundle}')
        return False

    history_dir = working_bundle / '_history'
    existing_revisions = _find_existing_revisions(history_dir)
    new_revision_id = _next_revision_id(existing_revisions)
    predecessor = existing_revisions[-1] if existing_revisions else None

    # Verify the decision file exists
    dec_md = root / 'planning' / 'decisions' / f'{decision_id}.md'
    dec_yaml = root / 'planning' / 'decisions' / f'{decision_id}.yaml'
    if not dec_md.exists() and not dec_yaml.exists():
        print(f'[ERROR] Decision file not found: {dec_md} or {dec_yaml}')
        print(f'  The decision must be recorded in planning/decisions/{decision_id}.md')
        print(f'  before a revision can be created. This is the acceptance provenance.')
        return False

    # Compute working bundle hash (excludes _history/ and revision.yaml)
    print(f'[INFO] Computing bundle hash for: {working_bundle}')
    bundle_hash = hash_spa_bundle(working_bundle, exclude_revision_yaml=True)
    if not bundle_hash:
        print(f'[ERROR] Failed to compute bundle hash for: {working_bundle}')
        return False

    print(f'[INFO] Bundle hash: {bundle_hash}')

    # Check: does the working bundle differ from the last revision?
    if existing_revisions:
        last_revision_dir = history_dir / existing_revisions[-1]
        last_revision_yaml = last_revision_dir / 'revision.yaml'
        if last_revision_yaml.exists():
            try:
                with open(last_revision_yaml, 'r', encoding='utf-8') as f:
                    last_manifest = yaml.safe_load(f) or {}
                last_hash = last_manifest.get('bundle_hash')
                if last_hash == bundle_hash:
                    print(f'[WARN] Working bundle hash matches last revision ({existing_revisions[-1]}).')
                    print(f'  No content changes detected. Revision would be identical.')
                    print(f'  Aborting to prevent empty revision creation.')
                    return False
            except Exception as e:
                print(f'[WARN] Could not read last revision manifest: {e}')

    new_revision_dir = history_dir / new_revision_id

    print(f'[INFO] New revision: {new_revision_id}')
    print(f'[INFO] Revision directory: {new_revision_dir}')

    if dry_run:
        print()
        print('--- DRY RUN (no changes written) ---')
        print(f'Would create: {new_revision_dir}/')
        print(f'revision.yaml:')
        _print_revision_yaml(new_revision_id, mockup_name, bundle_hash, decision_id,
                             predecessor, reason, impact_scope, affected_screens, change_classification)
        return True

    # Create revision directory and copy working bundle
    new_revision_dir.mkdir(parents=True, exist_ok=True)

    copied = 0
    for src_path in working_bundle.rglob('*'):
        # Skip _history/ directory (don't copy revision history into new revision)
        if '_history' in src_path.parts:
            continue
        rel = src_path.relative_to(working_bundle)
        dst_path = new_revision_dir / rel
        if src_path.is_dir():
            dst_path.mkdir(parents=True, exist_ok=True)
        else:
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, dst_path)
            copied += 1

    print(f'[INFO] Copied {copied} files to {new_revision_dir}')

    # Write revision.yaml
    revision_manifest = {
        'revision_id': new_revision_id,
        'mockup_name': mockup_name,
        'created_at': datetime.date.today().isoformat(),
        'entry_point': 'index.html',
        'bundle_hash': bundle_hash,
        'lifecycle_trigger': 'refinement_accepted',
        'change_classification': change_classification,
        'impact_scope': impact_scope,
        'acceptance_decisions': [decision_id],
    }

    if predecessor:
        revision_manifest['predecessor_revision_id'] = predecessor
    if reason:
        revision_manifest['reason'] = reason
    if affected_screens:
        revision_manifest['affected_screens'] = affected_screens

    revision_yaml_path = new_revision_dir / 'revision.yaml'
    with open(revision_yaml_path, 'w', encoding='utf-8') as f:
        yaml.dump(revision_manifest, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f'[INFO] Wrote revision.yaml: {revision_yaml_path}')
    print()
    print(f'[OK] Revision {new_revision_id} created successfully.')
    print()
    print(f'Next steps:')
    print(f'  1. Update UI inventory YAMLs for affected screens:')
    print(f'     target_revision: {new_revision_id}')
    print(f'     bundle_hash: {bundle_hash}')
    print(f'  2. Run: python scripts/build_artifact_index.py <project_root>')
    print(f'  3. Commit: git add planning/target-mockups/{mockup_name}/_history/{new_revision_id}/')

    return True


def _print_revision_yaml(revision_id, mockup_name, bundle_hash, decision_id,
                         predecessor, reason, impact_scope, affected_screens, change_classification):
    lines = [
        f'revision_id: {revision_id}',
        f'mockup_name: {mockup_name}',
        f'created_at: {datetime.date.today().isoformat()}',
        f'entry_point: index.html',
        f'bundle_hash: {bundle_hash}',
        f'lifecycle_trigger: refinement_accepted',
        f'change_classification: {change_classification}',
        f'impact_scope: {impact_scope}',
        f'acceptance_decisions: [{decision_id}]',
    ]
    if predecessor:
        lines.insert(4, f'predecessor_revision_id: {predecessor}')
    if reason:
        lines.append(f'reason: "{reason}"')
    if affected_screens:
        lines.append(f'affected_screens: {affected_screens}')
    for line in lines:
        print(f'  {line}')


def main():
    parser = argparse.ArgumentParser(
        description='Create an accepted SPA mockup bundle revision.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--path', type=str, default='.', help='Project root directory.')
    parser.add_argument('--mockup', required=True, help='Mockup bundle name (e.g. kidscompass-web).')
    parser.add_argument('--decision', required=True, help='DEC-NNN identifier of the acceptance decision.')
    parser.add_argument('--reason', type=str, default=None, help='Human-readable reason for this revision.')
    parser.add_argument('--impact-scope', default='unknown',
                        choices=['targeted', 'cross_cutting', 'full', 'unknown'],
                        help='Impact scope for evidence staleness (default: unknown = conservative full).')
    parser.add_argument('--affected-screens', nargs='*', default=None,
                        help='PAGE-NNN identifiers affected (use with --impact-scope targeted).')
    parser.add_argument('--change-classification', default='unknown',
                        choices=['material', 'non_material', 'unknown'],
                        help='Whether existing evidence must be re-verified (default: unknown = material).')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would happen without writing files.')

    args = parser.parse_args()

    success = create_revision(
        project_root=args.path,
        mockup_name=args.mockup,
        decision_id=args.decision,
        reason=args.reason,
        impact_scope=args.impact_scope,
        affected_screens=args.affected_screens,
        change_classification=args.change_classification,
        dry_run=args.dry_run,
    )

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
