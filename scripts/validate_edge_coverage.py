"""
MxAgile Edge Coverage Validator (Phase 1c)

Validates that every canonical cross-artifact reference field defined in the
CANONICAL_EDGE_REGISTRY has a corresponding emitter in build_artifact_index.py.

Purpose: prevent future drift between what the schema documents and what the
         builder actually emits.  Run as Tier 0 test before any build.

Usage:
  python scripts/validate_edge_coverage.py [--path <project_root>]

Exit codes:
  0 — all registry entries have a confirmed emitter
  1 — one or more registry entries are missing an emitter (drift detected)
"""

import sys
import ast
import re
import argparse
from pathlib import Path

# ---------------------------------------------------------------------------
# Edge coverage registry (single source of truth).
# Each tuple: (artifact_type, field_path, edge_type, target_type, provenance_type)
# This MUST stay in sync with CANONICAL_EDGE_REGISTRY in build_artifact_index.py.
# ---------------------------------------------------------------------------
REGISTRY = [
    # requirement
    ('requirement',       'derivedFrom',                        'DERIVED_FROM',       'page',              'DECLARED'),
    ('requirement',       'screens[]',                          'APPLIES_TO',         'page',              'DECLARED'),
    # spec
    ('spec',              'requirements[]',                     'IMPLEMENTED_BY',     'requirement',       'DECLARED'),
    # task
    ('task',              'spec',                               'IMPLEMENTED_BY',     'spec',              'DECLARED'),
    ('task',              'depends_on[]',                       'DEPENDS_ON',         'task',              'DECLARED'),
    ('task',              'req[]',                              'TRACES_TO',          'requirement',       'DECLARED'),
    # scenario
    ('scenario',          'screen_id',                          'VERIFIED_BY',        'page',              'DECLARED'),
    ('scenario',          'traceability.requirements[]',        'COVERS',             'requirement',       'DECLARED'),
    ('scenario',          'traceability.specs[]',               'COVERS_SPEC',        'spec',              'DECLARED'),
    ('scenario',          'prerequisites.depends_on_scenarios[]', 'DEPENDS_ON_SCN',  'scenario',          'DECLARED'),
    # test_contract
    ('test_contract',     'requirement_ids[]',                  'COVERS',             'requirement',       'DECLARED'),
    ('test_contract',     'design_contract_ref',                'DERIVED_FROM_DC',    'external',          'DERIVED'),
    # verification_plan
    ('verification_plan', 'test_contract_id',                   'PLANS',              'test_contract',     'DECLARED'),
    # decision
    ('decision',          'affected_requirements[]',            'GOVERNS',            'requirement',       'DECLARED'),
    ('decision',          'affected_screens[]',                 'GOVERNS_SCREEN',     'page',              'DECLARED'),
    ('decision',          'superseded_by',                      'SUPERSEDED_BY',      'decision',          'DECLARED'),
    # revision
    ('revision',          'acceptance_decisions[]',             'AUTHORIZED_BY',      'decision',          'DECLARED'),
    ('revision',          'requirements[]',                     'IMPACTS',            'requirement',       'DECLARED'),
    ('revision',          'affected_screens[]',                 'AFFECTS_SCREEN',     'page',              'DECLARED'),
    # business_flow
    ('business_flow',     'steps[] (contains)',                 'CONTAINS_STEP',      'flow_step',         'DECLARED'),
    ('flow_step',         'req_refs[]',                         'STEP_PARTICIPATES_IN','requirement',      'DECLARED'),
    ('flow_step',         'screen_ref',                         'STEP_SHOWN_ON',      'page',              'DECLARED'),
    ('flow_step',         'decision_refs[]',                    'STEP_GOVERNED_BY',   'decision',          'DECLARED'),
]


def _load_builder_source(project_root):
    builder = project_root / 'scripts' / 'build_artifact_index.py'
    if not builder.exists():
        print(f'[ERROR] build_artifact_index.py not found at {builder}')
        return None
    return builder.read_text(encoding='utf-8')


def _check_edge_type_in_source(source, edge_type):
    """Return True if edge_type string literal appears in the builder source."""
    return f"'{edge_type}'" in source or f'"{edge_type}"' in source


def _check_field_in_source(source, artifact_type, field_path):
    """
    Heuristic: check that the field name (stripped of [] and path prefix)
    appears near the artifact_type in the builder source.
    This is a best-effort lint, not a full AST parse.
    """
    # Extract the leaf field name
    leaf = field_path.split('.')[-1].rstrip('[]').replace('[]', '')
    if leaf == '(contains)':
        leaf = 'steps'

    # Check field name literal appears in source
    return f"'{leaf}'" in source or f'"{leaf}"' in source or f'.get({repr(leaf)})' in source


def main():
    parser = argparse.ArgumentParser(description='Validate edge coverage in build_artifact_index.py')
    parser.add_argument('--path', default='.', help='Project root path')
    args = parser.parse_args()
    project_root = Path(args.path).resolve()

    source = _load_builder_source(project_root)
    if source is None:
        sys.exit(1)

    failures = []
    warnings = []

    for artifact_type, field_path, edge_type, target_type, provenance in REGISTRY:
        edge_found  = _check_edge_type_in_source(source, edge_type)
        field_found = _check_field_in_source(source, artifact_type, field_path)

        if not edge_found:
            failures.append(
                f'MISSING EMITTER: edge_type={edge_type!r} for '
                f'{artifact_type}.{field_path} → {target_type}'
            )
        elif not field_found:
            warnings.append(
                f'FIELD NOT FOUND IN SOURCE: {artifact_type}.{field_path} '
                f'(edge_type={edge_type!r}) — verify emitter logic manually'
            )

    # Also check that the ARTIFACT_GRAPH_SCHEMA.json edge type enum is current
    schema_path = project_root / 'docs' / 'ARTIFACT_GRAPH_SCHEMA.json'
    if schema_path.exists():
        schema_source = schema_path.read_text(encoding='utf-8')
        schema_edge_types = set(re.findall(r'"([A-Z_]{4,})"', schema_source))
        registry_edge_types = {r[2] for r in REGISTRY}
        undocumented = registry_edge_types - schema_edge_types
        if undocumented:
            failures.append(
                f'SCHEMA MISSING EDGE TYPES: {sorted(undocumented)} — '
                f'add to ARTIFACT_GRAPH_SCHEMA.json edge type enum'
            )
    else:
        warnings.append('docs/ARTIFACT_GRAPH_SCHEMA.json not found — schema coverage check skipped')

    # Report
    print(f'\nEdge Coverage Validator — {len(REGISTRY)} registry entries')
    print(f'  Failures: {len(failures)}')
    print(f'  Warnings: {len(warnings)}')

    if warnings:
        print('\nWARNINGS:')
        for w in warnings:
            print(f'  [WARN]  {w}')

    if failures:
        print('\nFAILURES:')
        for f in failures:
            print(f'  [FAIL]  {f}')
        print('\nEdge coverage validation FAILED.')
        sys.exit(1)
    else:
        print('\nEdge coverage validation PASSED.')
        sys.exit(0)


if __name__ == '__main__':
    main()
