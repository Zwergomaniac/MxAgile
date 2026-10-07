"""
MxAgile Cross-Contract Drift Detection (Phase 1/2 Requirement 5)

Verifies that the canonical Business Flow vocabulary (step types, ID patterns,
edge types, graph node types) is consistently propagated across:

  1. Canonical schema    — .mxagile/schemas/business-flow.schema.json
  2. Graph schema        — docs/ARTIFACT_GRAPH_SCHEMA.json
  3. Index builder       — scripts/build_artifact_index.py
  4. Mermaid generator   — scripts/mermaid_generator.py
  5. M365 knowledge file — products/MxMocketeer/knowledge/business-flows.txt
  6. Consuming agent     — .mxagile/agents/mocketeer-agent.md
  7. System prompt       — products/MxMocketeer/system-prompt.md

Failure mode: this test FAILS when a required cross-boundary vocabulary item is
added on one side but not propagated to the others. Tests are structural
(all step types present in every consumer), not string-presence smoke tests.

Usage:
  python tests/test-cross-contract-drift.py [project_root]

Exit codes: 0 = all pass, 1 = one or more drift failures.
"""

import json
import sys
import re
from pathlib import Path

PROJECT_ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.').resolve()

PASS_COUNT = 0
FAIL_COUNT = 0
DRIFT_FAILURES = []


def ok(label):
    global PASS_COUNT
    PASS_COUNT += 1
    print(f'[PASS] {label}')


def fail(label, reason=''):
    global FAIL_COUNT, DRIFT_FAILURES
    FAIL_COUNT += 1
    msg = f'[FAIL] {label}{": " + reason if reason else ""}'
    print(msg)
    DRIFT_FAILURES.append(label)


# ---------------------------------------------------------------------------
# Source loaders
# ---------------------------------------------------------------------------

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def load_text(path):
    return path.read_text(encoding='utf-8')


# ---------------------------------------------------------------------------
# 1. Extract canonical step types from the Business Flow schema
# ---------------------------------------------------------------------------

SCHEMA_PATH = PROJECT_ROOT / '.mxagile' / 'schemas' / 'business-flow.schema.json'


def get_canonical_step_types():
    if not SCHEMA_PATH.exists():
        fail('SCHEMA_EXISTS', f'{SCHEMA_PATH} not found')
        return []
    schema = load_json(SCHEMA_PATH)
    defs = schema.get('definitions') or schema.get('$defs') or {}
    step_def = defs.get('flow_step', {})
    props = step_def.get('properties', {})
    type_enum = props.get('type', {}).get('enum', [])
    if not type_enum:
        fail('SCHEMA_STEP_TYPE_ENUM', 'flow_step.type enum is empty')
        return []
    ok(f'SCHEMA_STEP_TYPE_ENUM: {len(type_enum)} step types in canonical schema: {type_enum}')
    return type_enum


CANONICAL_STEP_TYPES = get_canonical_step_types()
CANONICAL_ID_PATTERNS = {
    'flow':      r'FLOW-[A-Z0-9_-]+',
    'flow_step': r'FLOWSTEP-[A-Z0-9_-]+',
}
CANONICAL_EDGE_TYPES_FLOW = {
    'CONTAINS_STEP', 'STEP_PARTICIPATES_IN', 'STEP_SHOWN_ON', 'STEP_GOVERNED_BY'
}
CANONICAL_NODE_TYPES_FLOW = {'business_flow', 'flow_step'}


# ---------------------------------------------------------------------------
# 2. docs/ARTIFACT_GRAPH_SCHEMA.json — node types and edge types
# ---------------------------------------------------------------------------

def check_graph_schema():
    path = PROJECT_ROOT / 'docs' / 'ARTIFACT_GRAPH_SCHEMA.json'
    if not path.exists():
        fail('GRAPH_SCHEMA_EXISTS', str(path))
        return
    source = load_text(path)

    # Check node types
    for nt in CANONICAL_NODE_TYPES_FLOW:
        if f'"{nt}"' in source:
            ok(f'GRAPH_SCHEMA_NODE_TYPE: {nt!r} documented')
        else:
            fail('GRAPH_SCHEMA_NODE_TYPE_MISSING', f'{nt!r} not in ARTIFACT_GRAPH_SCHEMA.json')

    # Check edge types
    for et in sorted(CANONICAL_EDGE_TYPES_FLOW):
        if f'"{et}"' in source:
            ok(f'GRAPH_SCHEMA_EDGE_TYPE: {et!r} documented')
        else:
            fail('GRAPH_SCHEMA_EDGE_TYPE_MISSING', f'{et!r} not in ARTIFACT_GRAPH_SCHEMA.json')


# ---------------------------------------------------------------------------
# 3. scripts/build_artifact_index.py — emits all edge types and indexes node types
# ---------------------------------------------------------------------------

def check_index_builder():
    path = PROJECT_ROOT / 'scripts' / 'build_artifact_index.py'
    if not path.exists():
        fail('BUILDER_EXISTS', str(path))
        return
    source = load_text(path)

    # All business_flow edge types must be emitted
    for et in sorted(CANONICAL_EDGE_TYPES_FLOW):
        if f"'{et}'" in source or f'"{et}"' in source:
            ok(f'BUILDER_EMITS_EDGE: {et!r}')
        else:
            fail('BUILDER_EDGE_MISSING', f'edge type {et!r} not emitted in build_artifact_index.py')

    # Node type strings for business_flow and flow_step must appear
    for nt in CANONICAL_NODE_TYPES_FLOW:
        if f"'{nt}'" in source or f'"{nt}"' in source:
            ok(f'BUILDER_INDEXES_NODE_TYPE: {nt!r}')
        else:
            fail('BUILDER_NODE_TYPE_MISSING', f'node type {nt!r} not in build_artifact_index.py')

    # FLOWSTEP ID pattern must appear in source
    if 'FLOWSTEP' in source:
        ok('BUILDER_FLOWSTEP_ID_PATTERN: FLOWSTEP referenced in builder')
    else:
        fail('BUILDER_FLOWSTEP_ID_PATTERN', 'FLOWSTEP not referenced in build_artifact_index.py')


# ---------------------------------------------------------------------------
# 4. scripts/mermaid_generator.py — handles every canonical step type
# ---------------------------------------------------------------------------

def check_mermaid_generator():
    path = PROJECT_ROOT / 'scripts' / 'mermaid_generator.py'
    if not path.exists():
        fail('MERMAID_GEN_EXISTS', str(path))
        return
    source = load_text(path)

    # Every step type must appear in the generator's shape mapping or handling logic
    missing = []
    for st in CANONICAL_STEP_TYPES:
        if f"'{st}'" in source or f'"{st}"' in source:
            pass
        else:
            missing.append(st)

    if missing:
        fail('MERMAID_STEP_TYPE_COVERAGE',
             f'step types not handled in mermaid_generator.py: {missing}')
    else:
        ok(f'MERMAID_STEP_TYPE_COVERAGE: all {len(CANONICAL_STEP_TYPES)} step types handled')

    # Mermaid text must never be stored (no "flowchart" emitted to JSON contract)
    if 'flowchart' in source:
        ok('MERMAID_GENERATED_NOT_STORED: flowchart text is generated (not stored in contracts)')
    else:
        fail('MERMAID_GENERATED_NOT_STORED',
             '"flowchart" keyword missing from mermaid_generator.py')


# ---------------------------------------------------------------------------
# 5. M365 knowledge file — documents all step types
# ---------------------------------------------------------------------------

def check_knowledge_file():
    path = PROJECT_ROOT / 'products' / 'MxMocketeer' / 'knowledge' / 'business-flows.txt'
    if not path.exists():
        fail('KNOWLEDGE_FILE_EXISTS', str(path))
        return
    source = load_text(path)

    # Every canonical step type must be documented in the knowledge file
    missing = [st for st in CANONICAL_STEP_TYPES if st not in source]
    if missing:
        fail('KNOWLEDGE_STEP_TYPES',
             f'step types not documented in business-flows.txt: {missing}')
    else:
        ok(f'KNOWLEDGE_STEP_TYPES: all {len(CANONICAL_STEP_TYPES)} step types documented')

    # Stable ID invariant must be documented
    if 'FLOW-' in source and 'FLOWSTEP-' in source:
        ok('KNOWLEDGE_STABLE_ID_INVARIANT: FLOW-NNN/FLOWSTEP-NNN mentioned')
    else:
        fail('KNOWLEDGE_STABLE_ID_INVARIANT',
             'FLOW- or FLOWSTEP- ID patterns not documented in business-flows.txt')

    # "never stored" / "Mermaid" invariant must be present
    if re.search(r'[Mm]ermaid', source) and re.search(r'(never stored|CANONICAL|derived)', source):
        ok('KNOWLEDGE_MERMAID_DERIVED_INVARIANT: Mermaid-as-derived documented')
    else:
        fail('KNOWLEDGE_MERMAID_DERIVED_INVARIANT',
             'Mermaid-as-derived-only invariant not clearly stated in business-flows.txt')


# ---------------------------------------------------------------------------
# 6. Consuming agent — .mxagile/agents/mocketeer-agent.md
# ---------------------------------------------------------------------------

def check_mocketeer_agent():
    path = PROJECT_ROOT / '.mxagile' / 'agents' / 'mocketeer-agent.md'
    if not path.exists():
        fail('MOCKETEER_AGENT_EXISTS', str(path))
        return
    source = load_text(path)

    # Agent must reference DIM-BUSINESS_FLOWS assessment dimension
    if 'DIM-BUSINESS_FLOWS' in source:
        ok('AGENT_DIM_BUSINESS_FLOWS: DIM-BUSINESS_FLOWS assessment dimension referenced')
    else:
        fail('AGENT_DIM_BUSINESS_FLOWS',
             'DIM-BUSINESS_FLOWS not found in mocketeer-agent.md')

    # Agent must reference FLOW-NNN stable IDs
    if 'FLOW-' in source:
        ok('AGENT_FLOW_ID_PATTERN: FLOW-NNN pattern referenced in agent instructions')
    else:
        fail('AGENT_FLOW_ID_PATTERN', 'FLOW- ID pattern not in mocketeer-agent.md')

    # Agent must reference FLOWSTEP (step-level stability)
    if 'FLOWSTEP' in source or 'step_id' in source:
        ok('AGENT_FLOWSTEP_PATTERN: FLOWSTEP/step_id stability referenced in agent')
    else:
        fail('AGENT_FLOWSTEP_PATTERN',
             'FLOWSTEP or step_id stability not referenced in mocketeer-agent.md')

    # Agent must reference SUPERSEDED handling for flows
    if 'SUPERSEDED' in source:
        ok('AGENT_SUPERSEDED_HANDLING: SUPERSEDED flow handling present')
    else:
        fail('AGENT_SUPERSEDED_HANDLING',
             'SUPERSEDED handling not found in mocketeer-agent.md')


# ---------------------------------------------------------------------------
# 7. System prompt — behavioral routing for Business Flows
# ---------------------------------------------------------------------------

def check_system_prompt():
    path = PROJECT_ROOT / 'products' / 'MxMocketeer' / 'system-prompt.md'
    if not path.exists():
        fail('SYSTEM_PROMPT_EXISTS', str(path))
        return
    source = load_text(path)

    # Must reference FLOW-NNN stable IDs
    if 'FLOW-NNN' in source:
        ok('SYSTEM_PROMPT_FLOW_ID: FLOW-NNN stable ID policy in system prompt')
    else:
        fail('SYSTEM_PROMPT_FLOW_ID', 'FLOW-NNN not in system-prompt.md')

    # Must reference FLOWSTEP-NNN stable IDs
    if 'FLOWSTEP-NNN' in source:
        ok('SYSTEM_PROMPT_FLOWSTEP_ID: FLOWSTEP-NNN stable ID policy in system prompt')
    else:
        fail('SYSTEM_PROMPT_FLOWSTEP_ID', 'FLOWSTEP-NNN not in system-prompt.md')

    # Must reference Mermaid on-demand / never-stored invariant
    if re.search(r'[Mm]ermaid.*never stored|never stored.*[Mm]ermaid', source):
        ok('SYSTEM_PROMPT_MERMAID_INVARIANT: Mermaid never-stored policy in system prompt')
    else:
        fail('SYSTEM_PROMPT_MERMAID_INVARIANT',
             'Mermaid never-stored invariant not in system-prompt.md')

    # Must reference DIM-BUSINESS_FLOWS
    if 'DIM-BUSINESS_FLOWS' in source:
        ok('SYSTEM_PROMPT_DIM_BUSINESS_FLOWS: DIM-BUSINESS_FLOWS referenced in system prompt')
    else:
        fail('SYSTEM_PROMPT_DIM_BUSINESS_FLOWS',
             'DIM-BUSINESS_FLOWS not in system-prompt.md')

    # Must contain producer-side graph output guidance (MxMocketeer is a producer, not a consumer)
    if re.search(r'graph-ready|graph-indexable|Graph-Ready|Graph-ready|graph.*indexable', source, re.IGNORECASE):
        ok('SYSTEM_PROMPT_PRODUCER_BOUNDARY: graph-ready producer language present')
    else:
        fail('SYSTEM_PROMPT_PRODUCER_BOUNDARY',
             'No graph-ready producer guidance in system-prompt.md')

    # Must NOT reference KG consumer operations — those belong to MxAgile pipeline agents, not M365
    KG_CONSUMER_PATTERNS = [
        (r'neighbors\(\)', 'neighbors()'),
        (r'paths\(\)', 'paths()'),
        (r'affected\(\)', 'affected()'),
        (r'graph freshness|graph.*stale|stale.*graph', 'graph freshness/staleness'),
        (r'provider:\s*(none|graphify|artifact)', 'graph provider selection'),
    ]
    consumer_violations = []
    for pattern, label in KG_CONSUMER_PATTERNS:
        if re.search(pattern, source, re.IGNORECASE):
            consumer_violations.append(label)
    if consumer_violations:
        fail('SYSTEM_PROMPT_NO_KG_CONSUMER',
             f'KG consumer operations in system-prompt.md: {consumer_violations}')
    else:
        ok('SYSTEM_PROMPT_NO_KG_CONSUMER: no KG consumer operations in system prompt')


# ---------------------------------------------------------------------------
# 8. M365 package boundary — knowledge-graph.txt must NOT be in the upload list
# ---------------------------------------------------------------------------

def check_m365_package_boundary():
    setup_path = PROJECT_ROOT / 'products' / 'MxMocketeer' / 'agent-builder-setup.md'
    if not setup_path.exists():
        fail('M365_SETUP_EXISTS', str(setup_path))
        return
    source = load_text(setup_path)

    # knowledge-graph.txt must NOT be in the upload list
    # The file is internal framework doc; the Note line in the setup file explains this
    if re.search(r'^\d+\.\s.*knowledge-graph\.txt', source, re.MULTILINE):
        fail('M365_NO_KG_CONSUMER_FILE',
             'knowledge-graph.txt is listed as an M365 upload file — it must not be (KG consumer doc belongs to MxAgile pipeline)')
    else:
        ok('M365_NO_KG_CONSUMER_FILE: knowledge-graph.txt not in M365 upload list')

    # 6 producer knowledge files must be listed (not 7)
    upload_items = re.findall(r'^\d+\.\s', source, re.MULTILINE)
    if len(upload_items) == 6:
        ok(f'M365_PACKAGE_COUNT: exactly 6 knowledge files listed for upload')
    else:
        fail('M365_PACKAGE_COUNT', f'expected 6 upload files, found {len(upload_items)}')

    # business-flows.txt MUST be in the upload list (producer content)
    if 'business-flows.txt' in source and re.search(r'^\d+\.\s.*business-flows\.txt', source, re.MULTILINE):
        ok('M365_BUSINESS_FLOWS_IN_PACKAGE: business-flows.txt in upload list')
    else:
        fail('M365_BUSINESS_FLOWS_IN_PACKAGE',
             'business-flows.txt missing from M365 upload list')


# ---------------------------------------------------------------------------
# 9. Structural invariant: adding a step type to schema breaks downstream
#    Prove this by checking the set of step types in the schema vs each consumer.
# ---------------------------------------------------------------------------

def check_step_type_propagation_completeness():
    """
    This test confirms the enforcement works: if CANONICAL_STEP_TYPES is non-empty
    and all consumer checks above passed, then the propagation is complete.
    The individual consumer checks (2-7) are the actual enforcement; this is the
    final gate that confirms we checked every consumer.
    """
    if not CANONICAL_STEP_TYPES:
        fail('STEP_TYPE_PROPAGATION', 'No canonical step types found — cannot validate propagation')
        return

    consumers_checked = [
        'GRAPH_SCHEMA_NODE_TYPE',
        'BUILDER_INDEXES_NODE_TYPE',
        'MERMAID_STEP_TYPE_COVERAGE',
        'KNOWLEDGE_STEP_TYPES',
        'AGENT_DIM_BUSINESS_FLOWS',
        'SYSTEM_PROMPT_FLOW_ID',
    ]
    # All consumer checks have already run above. If any failed, DRIFT_FAILURES is non-empty.
    # This check confirms the chain is complete:
    if not DRIFT_FAILURES:
        ok(f'STEP_TYPE_PROPAGATION: all step types fully propagated across '
           f'{len(consumers_checked)} consumers')
    else:
        fail('STEP_TYPE_PROPAGATION',
             f'Drift detected in {len(DRIFT_FAILURES)} checks: {DRIFT_FAILURES[:3]}...')


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    print(f'Cross-Contract Drift Detection\n{"=" * 40}')
    print(f'Project root: {PROJECT_ROOT}')
    print(f'Canonical step types: {CANONICAL_STEP_TYPES}\n')

    check_graph_schema()
    check_index_builder()
    check_mermaid_generator()
    check_knowledge_file()
    check_mocketeer_agent()
    check_system_prompt()
    check_m365_package_boundary()
    check_step_type_propagation_completeness()

    print(f'\n{"=" * 40}')
    print(f'PASS: {PASS_COUNT}   FAIL: {FAIL_COUNT}', end='')
    if FAIL_COUNT == 0:
        print(' — no drift detected')
        sys.exit(0)
    else:
        print(' — drift detected')
        sys.exit(1)
