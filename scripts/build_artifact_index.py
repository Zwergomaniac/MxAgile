import json
import os
import re
import hashlib
import yaml
import sys
import collections
import datetime
from pathlib import Path

# =============================================================================
# MxAgile Artifact Index Builder
#
# Produces: .mxagile/state/artifact-index.json
# Schema:   docs/ARTIFACT_GRAPH_SCHEMA.json
# Format:   {"nodes": [...], "edges": [...], "source_fingerprint": "sha256:...", "generated_at": "..."}
#
# Edge provenance vocabulary (stored in edge.provenance.type):
#   DECLARED — derived deterministically from an explicit canonical YAML ref field.
#              These are the only edges with authority to drive lifecycle decisions.
#              (Equivalent to CANONICAL in policy documents.)
#   DERIVED  — observed in artifact content outside dedicated ref fields.
#              (Equivalent to EXTRACTED in policy documents.)
#   INFERRED — semantic/provider suggestion (not emitted by this builder; reserved for providers).
#
# Precedence: DECLARED > DERIVED > INFERRED
#
# NODE TYPES indexed:
#   requirement      requirements/*.yml              ID field
#   spec             specs/*.yml                     ID field
#   task             planning/tasks/*.yml             ID field
#   page             planning/ui-inventory/*.yaml     page_id field
#   scenario         planning/scenarios/*.yaml        scenario_id field
#   test_contract    planning/test-contracts/*.yaml   ID field
#   verification_plan planning/verification-plans/*.yaml ID field
#   decision         planning/decisions/*.yml         ID field
#   revision         planning/target-mockups/*/_history/REV-*/revision.yaml  revision_id field
#   business_flow    extracted from Design Contract HTML files (input-resources/ui-ux/*.html
#                    and planning/target-mockups/*/REV-*/index.html)
#
# EDGE TYPES emitted (all DECLARED unless noted):
#   DERIVED_FROM          Page    -> Requirement   (REQ.derivedFrom)
#   APPLIES_TO            Req     -> Page          (REQ.screens[])
#   IMPLEMENTED_BY        Req     -> Spec          (SPEC.requirements[])
#   IMPLEMENTED_BY        Spec    -> Task          (TASK.spec)
#   DEPENDS_ON            Task    -> Task          (TASK.depends_on[])
#   TRACES_TO             Task    -> Requirement   (TASK.req[])
#   VERIFIED_BY           Page    -> Scenario      (SCN.screen_id)
#   COVERS                Scenario-> Requirement   (SCN.traceability.requirements[])
#   COVERS_SPEC           Scenario-> Spec          (SCN.traceability.specs[])
#   DEPENDS_ON_SCN        Scenario-> Scenario      (SCN.prerequisites.depends_on_scenarios[])
#   COVERS                TC      -> Requirement   (TC.requirement_ids[])
#   DERIVED_FROM_DC       TC      -> design-contract-ref string (TC.design_contract_ref) [DERIVED]
#   PLANS                 VPL     -> TC            (VPL.test_contract_id)
#   GOVERNS               Decision-> Requirement   (DEC.affected_requirements[])
#   GOVERNS_SCREEN        Decision-> Page          (DEC.affected_screens[])
#   SUPERSEDED_BY         Decision-> Decision      (DEC.superseded_by)
#   AUTHORIZED_BY         Revision-> Decision      (REV.acceptance_decisions[])
#   IMPACTS               Revision-> Requirement   (REV.requirements[])
#   AFFECTS_SCREEN        Revision-> Page          (REV.affected_screens[])
#   CONTAINS_STEP         Flow    -> FlowStep      (extracted from mocketeer-spec flows[].steps[])
#   STEP_PARTICIPATES_IN  FlowStep-> Requirement   (step.req_refs[])
#   STEP_SHOWN_ON         FlowStep-> Page          (step.screen_ref)
#   STEP_GOVERNED_BY      FlowStep-> Decision      (step.decision_refs[])
#
# NOTE: artifact-trace-index.json was a legacy hand-written stub and is no longer active.
#       artifact-graph.json was referenced by a stale propagate_stale.py and does not exist.
#       trace-index.json was an old deprecated format used by refine.py.
#       All consumers must use artifact-index.json as the single authoritative index.
# =============================================================================

# ---------------------------------------------------------------------------
# Edge provenance constants
# ---------------------------------------------------------------------------
DECLARED = 'DECLARED'
DERIVED  = 'DERIVED'
INFERRED = 'INFERRED'


def _prov(ptype, source):
    return {'type': ptype, 'source': source}


# ---------------------------------------------------------------------------
# Edge coverage registry — prevents future drift between canonical ref fields
# and graph edge emitters. Validated by validate_edge_coverage.py.
# Format: (artifact_type, yaml_field_path, edge_type, target_type, provenance_type)
# ---------------------------------------------------------------------------
CANONICAL_EDGE_REGISTRY = [
    # requirement
    ('requirement', 'derivedFrom',                  'DERIVED_FROM',   'page',              DECLARED),
    ('requirement', 'screens[]',                    'APPLIES_TO',     'page',              DECLARED),
    # spec
    ('spec',        'requirements[]',               'IMPLEMENTED_BY', 'requirement',       DECLARED),
    # task
    ('task',        'spec',                         'IMPLEMENTED_BY', 'spec',              DECLARED),
    ('task',        'depends_on[]',                 'DEPENDS_ON',     'task',              DECLARED),
    ('task',        'req[]',                        'TRACES_TO',      'requirement',       DECLARED),
    # scenario
    ('scenario',    'screen_id',                    'VERIFIED_BY',    'page',              DECLARED),
    ('scenario',    'traceability.requirements[]',  'COVERS',         'requirement',       DECLARED),
    ('scenario',    'traceability.specs[]',         'COVERS_SPEC',    'spec',              DECLARED),
    ('scenario',    'prerequisites.depends_on_scenarios[]', 'DEPENDS_ON_SCN', 'scenario', DECLARED),
    # test_contract
    ('test_contract', 'requirement_ids[]',          'COVERS',         'requirement',       DECLARED),
    ('test_contract', 'design_contract_ref',        'DERIVED_FROM_DC','external',          DERIVED),
    # verification_plan
    ('verification_plan', 'test_contract_id',       'PLANS',          'test_contract',     DECLARED),
    # decision
    ('decision',    'affected_requirements[]',      'GOVERNS',        'requirement',       DECLARED),
    ('decision',    'affected_screens[]',           'GOVERNS_SCREEN', 'page',              DECLARED),
    ('decision',    'superseded_by',                'SUPERSEDED_BY',  'decision',          DECLARED),
    # revision
    ('revision',    'acceptance_decisions[]',       'AUTHORIZED_BY',  'decision',          DECLARED),
    ('revision',    'requirements[]',               'IMPACTS',        'requirement',       DECLARED),
    ('revision',    'affected_screens[]',           'AFFECTS_SCREEN', 'page',              DECLARED),
    # business_flow (extracted from Design Contract)
    ('business_flow', 'steps[] (contains)',         'CONTAINS_STEP',  'flow_step',         DECLARED),
    ('flow_step',   'req_refs[]',                   'STEP_PARTICIPATES_IN', 'requirement', DECLARED),
    ('flow_step',   'screen_ref',                   'STEP_SHOWN_ON',  'page',              DECLARED),
    ('flow_step',   'decision_refs[]',              'STEP_GOVERNED_BY','decision',         DECLARED),
]


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def calculate_sha256(filepath):
    sha256_hash = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            for byte_block in iter(lambda: f.read(4096), b''):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        print(f'[ERROR] Could not read file for hash: {filepath} - {e}')
        return None


def get_display_name(content, artifact_type, fallback):
    if artifact_type == 'task':
        return content.get('action') or content.get('description') or fallback
    if artifact_type == 'page':
        return content.get('purpose') or content.get('page_id') or fallback
    if artifact_type == 'scenario':
        return content.get('description') or content.get('scenario_id') or fallback
    if artifact_type == 'test_contract':
        return content.get('title') or fallback
    if artifact_type == 'verification_plan':
        return content.get('title') or content.get('ID') or fallback
    if artifact_type == 'decision':
        return content.get('title') or content.get('topic') or fallback
    if artifact_type == 'revision':
        return content.get('change_scope') or content.get('revision_id') or fallback
    if artifact_type == 'business_flow':
        return content.get('name') or content.get('id') or fallback
    return content.get('description') or fallback


def _read_yaml(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print(f'[ERROR] Could not read or parse YAML for {filepath}: {e}')
        return None


def _emit_edge(edges, from_id, to_id, edge_type, provenance_type, source_field,
               all_artifact_ids, warn_prefix):
    """Helper: emit an edge if both endpoints exist in the index, or warn."""
    if to_id in all_artifact_ids:
        edges.append({
            'from': from_id,
            'to': to_id,
            'type': edge_type,
            'provenance': _prov(provenance_type, source_field),
        })
        print(f'[DEBUG] Edge: {from_id} --{edge_type}--> {to_id}')
        return True
    else:
        print(f'[WARN] Broken {source_field} reference in {warn_prefix}: '
              f'{to_id} not found in index')
        return False


# ---------------------------------------------------------------------------
# Stage 1: Find canonical artifacts
# ---------------------------------------------------------------------------

def find_artifacts(project_root):
    print('[INFO] Stage 1: Indexing artifacts from filesystem...')
    artifacts = collections.defaultdict(dict)

    # Standard YAML-based artifact locations.
    artifact_locations = [
        {'type': 'requirement',       'path': 'requirements',                  'filter': '*.yml',  'id_field': 'ID'},
        {'type': 'spec',              'path': 'specs',                         'filter': '*.yml',  'id_field': 'ID'},
        {'type': 'task',              'path': 'planning/tasks',                'filter': '*.yml',  'id_field': 'ID'},
        {'type': 'page',              'path': 'planning/ui-inventory',         'filter': '*.yaml', 'id_field': 'page_id'},
        {'type': 'scenario',          'path': 'planning/scenarios',            'filter': '*.yaml', 'id_field': 'scenario_id'},
        {'type': 'test_contract',     'path': 'planning/test-contracts',       'filter': '*.yaml', 'id_field': 'ID'},
        {'type': 'verification_plan', 'path': 'planning/verification-plans',   'filter': '*.yaml', 'id_field': 'ID'},
        {'type': 'decision',          'path': 'planning/decisions',            'filter': '*.yml',  'id_field': 'ID'},
    ]

    for loc in artifact_locations:
        dir_path = project_root / loc['path']
        if not dir_path.exists():
            print(f'[DEBUG] Directory does not exist, skipping: {dir_path}')
            continue

        for filepath in sorted(dir_path.glob(loc['filter'])):
            content = _read_yaml(filepath)
            if content is None:
                continue

            file_id_from_name = filepath.stem
            artifact_id = content.get(loc['id_field'], file_id_from_name)

            if artifact_id != file_id_from_name:
                print(f'[WARN] ID mismatch: file={file_id_from_name}, '
                      f'{loc["id_field"]}={artifact_id} in {filepath}')

            entry = {
                'id':           artifact_id,
                'type':         loc['type'],
                'path':         str(filepath.relative_to(project_root)).replace('\\', '/'),
                'hash':         calculate_sha256(filepath),
                'status':       'Active',
                'display_name': get_display_name(content, loc['type'], file_id_from_name),
                'content':      content,
            }

            if loc['type'] == 'page' and content.get('mockup_name'):
                entry['mockup_name'] = content['mockup_name']

            artifacts[loc['type']][artifact_id] = entry
            print(f'[DEBUG] Indexed {loc["type"]}: {artifact_id}')

    # Revision artifacts live in planning/target-mockups/*/_history/REV-*/revision.yaml
    _find_revisions(project_root, artifacts)

    type_counts = ', '.join(
        f'{len(artifacts[t])} {t}s' for t in [
            'requirement', 'spec', 'task', 'page', 'scenario',
            'test_contract', 'verification_plan', 'decision', 'revision'
        ] if artifacts[t]
    )
    print(f'[INFO] YAML indexing complete. Found: {type_counts}.')
    return artifacts


def _find_revisions(project_root, artifacts):
    """Index revision.yaml files from planning/target-mockups/*/_history/REV-*/."""
    target_dir = project_root / 'planning' / 'target-mockups'
    if not target_dir.exists():
        return

    for mockup_dir in sorted(target_dir.iterdir()):
        if not mockup_dir.is_dir():
            continue
        history_dir = mockup_dir / '_history'
        if not history_dir.exists():
            continue
        for rev_dir in sorted(history_dir.iterdir()):
            if not rev_dir.is_dir():
                continue
            rev_file = rev_dir / 'revision.yaml'
            if not rev_file.exists():
                continue
            content = _read_yaml(rev_file)
            if content is None:
                continue
            rev_id = content.get('revision_id', rev_dir.name)
            entry = {
                'id':           rev_id,
                'type':         'revision',
                'path':         str(rev_file.relative_to(project_root)).replace('\\', '/'),
                'hash':         calculate_sha256(rev_file),
                'status':       'Active',
                'display_name': content.get('change_scope') or rev_id,
                'content':      content,
                'mockup_name':  mockup_dir.name,
            }
            artifacts['revision'][rev_id] = entry
            print(f'[DEBUG] Indexed revision: {rev_id} (mockup: {mockup_dir.name})')


# ---------------------------------------------------------------------------
# Stage 2: Extract Business Flows from Design Contract HTML files
# ---------------------------------------------------------------------------

def find_design_contract_flows(project_root, artifacts):
    """
    Parse Design Contract HTML files for structured flows[] and emit business_flow
    and flow_step nodes. Reads from:
      - input-resources/ui-ux/*.html  (active input for current wave)
      - planning/target-mockups/*/_history/REV-*/index.html  (accepted revision bundles)

    Structured flows have steps[] with step_id (FLOWSTEP-NNN) fields.
    Narrative-only flows (no step_id or no steps[]) are skipped — they produce no nodes.
    """
    print('\n[INFO] Stage 1b: Extracting Business Flows from Design Contract HTML files...')
    flow_count = 0
    step_count = 0

    sources = []

    # Input resources
    input_dir = project_root / 'input-resources' / 'ui-ux'
    if input_dir.exists():
        sources.extend(sorted(input_dir.glob('*.html')))

    # Accepted revision bundles
    target_dir = project_root / 'planning' / 'target-mockups'
    if target_dir.exists():
        for mockup_dir in sorted(target_dir.iterdir()):
            if not mockup_dir.is_dir():
                continue
            # Scan _history for accepted revision HTML files
            history_dir = mockup_dir / '_history'
            if history_dir.exists():
                for rev_dir in sorted(history_dir.iterdir()):
                    for html_file in ['index.html', 'mockup.html']:
                        candidate = rev_dir / html_file
                        if candidate.exists():
                            sources.append(candidate)
                            break

    for html_path in sources:
        flows = _extract_flows_from_html(html_path)
        if not flows:
            continue
        mockup_id = _extract_mockup_id_from_html(html_path)
        rel_path = str(html_path.relative_to(project_root)).replace('\\', '/')

        for flow in flows:
            flow_id = flow.get('id')
            if not flow_id:
                continue
            steps = flow.get('steps', [])
            # Only index flows with at least one structured step (has step_id)
            structured_steps = [s for s in steps if s.get('step_id')]
            if not structured_steps:
                print(f'[DEBUG] Skipping narrative-only flow {flow_id} in {rel_path}')
                continue

            # Emit business_flow node
            flow_entry = {
                'id':           flow_id,
                'type':         'business_flow',
                'path':         rel_path,
                'hash':         None,  # extracted synthetic node, no single file hash
                'status':       'Active',
                'display_name': flow.get('name') or flow_id,
                'content':      flow,
                'mockup_id':    mockup_id,
            }
            artifacts['business_flow'][flow_id] = flow_entry
            flow_count += 1
            print(f'[DEBUG] Indexed business_flow: {flow_id} from {rel_path}')

            # Emit flow_step nodes for each structured step
            for step in structured_steps:
                step_id = step['step_id']
                composite_id = f'{flow_id}:{step_id}'
                step_entry = {
                    'id':           composite_id,
                    'type':         'flow_step',
                    'path':         rel_path,
                    'hash':         None,
                    'status':       'Active',
                    'display_name': step.get('description') or composite_id,
                    'content':      step,
                    'flow_id':      flow_id,
                    'step_id':      step_id,
                }
                artifacts['flow_step'][composite_id] = step_entry
                step_count += 1
                print(f'[DEBUG] Indexed flow_step: {composite_id}')

    if flow_count:
        print(f'[INFO] Design Contract extraction complete. '
              f'Found {flow_count} structured flows, {step_count} steps.')
    else:
        print('[INFO] No structured Business Flow data found in Design Contract HTML files.')


def _extract_flows_from_html(html_path):
    """Extract flows[] array from the mocketeer-spec JSON embedded in an HTML file."""
    try:
        content = html_path.read_text(encoding='utf-8', errors='ignore')
    except Exception as e:
        print(f'[WARN] Could not read HTML file {html_path}: {e}')
        return []

    # Find <script type="application/json" id="mocketeer-spec">...</script>
    pattern = re.compile(
        r'<script[^>]+type=["\']application/json["\'][^>]+id=["\']mocketeer-spec["\'][^>]*>(.*?)</script>',
        re.DOTALL | re.IGNORECASE
    )
    match = pattern.search(content)
    if not match:
        return []

    try:
        spec = json.loads(match.group(1))
        flows = spec.get('flows', [])
        if not isinstance(flows, list):
            return []
        return flows
    except (json.JSONDecodeError, KeyError) as e:
        print(f'[WARN] Could not parse mocketeer-spec JSON in {html_path}: {e}')
        return []


def _extract_mockup_id_from_html(html_path):
    """Extract mockup.id from the mocketeer-spec JSON."""
    try:
        content = html_path.read_text(encoding='utf-8', errors='ignore')
        pattern = re.compile(
            r'<script[^>]+type=["\']application/json["\'][^>]+id=["\']mocketeer-spec["\'][^>]*>(.*?)</script>',
            re.DOTALL | re.IGNORECASE
        )
        match = pattern.search(content)
        if match:
            spec = json.loads(match.group(1))
            return spec.get('mockup', {}).get('id')
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Stage 3: Build graph (nodes + edges)
# ---------------------------------------------------------------------------

def build_graph(artifacts):
    print('\n[INFO] Stage 2: Building artifact graph...')
    nodes = []
    edges = []
    all_artifact_ids = set()

    for type_key in artifacts:
        for id_key in artifacts[type_key]:
            node = {k: v for k, v in artifacts[type_key][id_key].items() if k != 'content'}
            node['content'] = artifacts[type_key][id_key].get('content', {})
            nodes.append(node)
            all_artifact_ids.add(id_key)

    for node in nodes:
        node_id = node['id']
        ntype   = node['type']
        content = node.get('content', {}) or {}

        # ----------------------------------------------------------------
        # requirement edges
        # ----------------------------------------------------------------
        if ntype == 'requirement':
            # DERIVED_FROM: Page -> Requirement  (REQ.derivedFrom)
            derived_from_id = content.get('derivedFrom')
            if derived_from_id:
                _emit_edge(edges, derived_from_id, node_id, 'DERIVED_FROM', DECLARED,
                           'requirement.derivedFrom', all_artifact_ids, node_id)

            # APPLIES_TO: Requirement -> Page  (REQ.screens[])
            for screen_id in _as_list(content.get('screens')):
                _emit_edge(edges, node_id, screen_id, 'APPLIES_TO', DECLARED,
                           'requirement.screens[]', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # spec edges
        # ----------------------------------------------------------------
        elif ntype == 'spec':
            # IMPLEMENTED_BY: Requirement -> Spec  (SPEC.requirements[])
            for req_id in _as_list(content.get('requirements')):
                _emit_edge(edges, req_id, node_id, 'IMPLEMENTED_BY', DECLARED,
                           'spec.requirements[]', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # task edges
        # ----------------------------------------------------------------
        elif ntype == 'task':
            # IMPLEMENTED_BY: Spec -> Task  (TASK.spec)
            spec_id = content.get('spec')
            if spec_id:
                _emit_edge(edges, spec_id, node_id, 'IMPLEMENTED_BY', DECLARED,
                           'task.spec', all_artifact_ids, node_id)

            # DEPENDS_ON: Task -> Task  (TASK.depends_on[])
            for dep_id in _as_list(content.get('depends_on')):
                _emit_edge(edges, node_id, dep_id, 'DEPENDS_ON', DECLARED,
                           'task.depends_on[]', all_artifact_ids, node_id)

            # TRACES_TO: Task -> Requirement  (TASK.req[])
            for req_id in _as_list(content.get('req')):
                _emit_edge(edges, node_id, req_id, 'TRACES_TO', DECLARED,
                           'task.req[]', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # scenario edges
        # ----------------------------------------------------------------
        elif ntype == 'scenario':
            # VERIFIED_BY: Page -> Scenario  (SCN.screen_id)
            screen_id = content.get('screen_id')
            if screen_id:
                _emit_edge(edges, screen_id, node_id, 'VERIFIED_BY', DECLARED,
                           'scenario.screen_id', all_artifact_ids, node_id)

            traceability = content.get('traceability') or {}

            # COVERS: Scenario -> Requirement  (SCN.traceability.requirements[])
            for req_id in _as_list(traceability.get('requirements')):
                _emit_edge(edges, node_id, req_id, 'COVERS', DECLARED,
                           'scenario.traceability.requirements[]', all_artifact_ids, node_id)

            # COVERS_SPEC: Scenario -> Spec  (SCN.traceability.specs[])
            for spec_id in _as_list(traceability.get('specs')):
                _emit_edge(edges, node_id, spec_id, 'COVERS_SPEC', DECLARED,
                           'scenario.traceability.specs[]', all_artifact_ids, node_id)

            # DEPENDS_ON_SCN: Scenario -> Scenario  (SCN.prerequisites.depends_on_scenarios[])
            prerequisites = content.get('prerequisites') or {}
            for dep_scn_id in _as_list(prerequisites.get('depends_on_scenarios')):
                _emit_edge(edges, node_id, dep_scn_id, 'DEPENDS_ON_SCN', DECLARED,
                           'scenario.prerequisites.depends_on_scenarios[]', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # test_contract edges
        # ----------------------------------------------------------------
        elif ntype == 'test_contract':
            # COVERS: TC -> Requirement  (TC.requirement_ids[])
            for req_id in _as_list(content.get('requirement_ids')):
                _emit_edge(edges, node_id, req_id, 'COVERS', DECLARED,
                           'test_contract.requirement_ids[]', all_artifact_ids, node_id)

            # DERIVED_FROM_DC: TC -> design-contract-ref (DERIVED — not a canonical artifact node)
            dc_ref = content.get('design_contract_ref')
            if dc_ref:
                # This is a string reference to a Design Contract, not a node in the index.
                # Emit as a DERIVED edge with the ref as the target ID string.
                # Consumers must handle that the target may not exist as a node.
                edges.append({
                    'from': node_id,
                    'to': dc_ref,
                    'type': 'DERIVED_FROM_DC',
                    'provenance': _prov(DERIVED, 'test_contract.design_contract_ref'),
                })
                print(f'[DEBUG] Edge (DERIVED): {node_id} --DERIVED_FROM_DC--> {dc_ref}')

        # ----------------------------------------------------------------
        # verification_plan edges
        # ----------------------------------------------------------------
        elif ntype == 'verification_plan':
            # PLANS: VPL -> TC  (VPL.test_contract_id)
            tc_id = content.get('test_contract_id')
            if tc_id:
                _emit_edge(edges, node_id, tc_id, 'PLANS', DECLARED,
                           'verification_plan.test_contract_id', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # decision edges
        # ----------------------------------------------------------------
        elif ntype == 'decision':
            # GOVERNS: Decision -> Requirement  (DEC.affected_requirements[])
            for req_id in _as_list(content.get('affected_requirements')):
                _emit_edge(edges, node_id, req_id, 'GOVERNS', DECLARED,
                           'decision.affected_requirements[]', all_artifact_ids, node_id)

            # GOVERNS_SCREEN: Decision -> Page  (DEC.affected_screens[])
            for page_id in _as_list(content.get('affected_screens')):
                _emit_edge(edges, node_id, page_id, 'GOVERNS_SCREEN', DECLARED,
                           'decision.affected_screens[]', all_artifact_ids, node_id)

            # SUPERSEDED_BY: Decision -> Decision  (DEC.superseded_by)
            superseded_by = content.get('superseded_by')
            if superseded_by:
                _emit_edge(edges, node_id, superseded_by, 'SUPERSEDED_BY', DECLARED,
                           'decision.superseded_by', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # revision edges
        # ----------------------------------------------------------------
        elif ntype == 'revision':
            # AUTHORIZED_BY: Revision -> Decision  (REV.acceptance_decisions[])
            for dec_id in _as_list(content.get('acceptance_decisions')):
                _emit_edge(edges, node_id, dec_id, 'AUTHORIZED_BY', DECLARED,
                           'revision.acceptance_decisions[]', all_artifact_ids, node_id)

            # IMPACTS: Revision -> Requirement  (REV.requirements[])
            for req_id in _as_list(content.get('requirements')):
                _emit_edge(edges, node_id, req_id, 'IMPACTS', DECLARED,
                           'revision.requirements[]', all_artifact_ids, node_id)

            # AFFECTS_SCREEN: Revision -> Page  (REV.affected_screens[])
            for page_id in _as_list(content.get('affected_screens')):
                _emit_edge(edges, node_id, page_id, 'AFFECTS_SCREEN', DECLARED,
                           'revision.affected_screens[]', all_artifact_ids, node_id)

        # ----------------------------------------------------------------
        # business_flow edges
        # ----------------------------------------------------------------
        elif ntype == 'business_flow':
            steps = _as_list(content.get('steps'))
            for step in steps:
                step_id = step.get('step_id')
                if not step_id:
                    continue
                composite_id = f'{node_id}:{step_id}'
                if composite_id not in all_artifact_ids:
                    continue

                # CONTAINS_STEP: Flow -> FlowStep
                edges.append({
                    'from': node_id,
                    'to': composite_id,
                    'type': 'CONTAINS_STEP',
                    'provenance': _prov(DECLARED, 'business_flow.steps[].step_id'),
                })
                print(f'[DEBUG] Edge: {node_id} --CONTAINS_STEP--> {composite_id}')

        # ----------------------------------------------------------------
        # flow_step edges
        # ----------------------------------------------------------------
        elif ntype == 'flow_step':
            # STEP_PARTICIPATES_IN: FlowStep -> Requirement  (step.req_refs[])
            for req_id in _as_list(content.get('req_refs')):
                _emit_edge(edges, node_id, req_id, 'STEP_PARTICIPATES_IN', DECLARED,
                           'flow_step.req_refs[]', all_artifact_ids, node_id)

            # STEP_SHOWN_ON: FlowStep -> Page  (step.screen_ref)
            screen_ref = content.get('screen_ref')
            if screen_ref:
                _emit_edge(edges, node_id, screen_ref, 'STEP_SHOWN_ON', DECLARED,
                           'flow_step.screen_ref', all_artifact_ids, node_id)

            # STEP_GOVERNED_BY: FlowStep -> Decision  (step.decision_refs[])
            for dec_id in _as_list(content.get('decision_refs')):
                _emit_edge(edges, node_id, dec_id, 'STEP_GOVERNED_BY', DECLARED,
                           'flow_step.decision_refs[]', all_artifact_ids, node_id)

    print(f'[INFO] Graph building complete. Found {len(nodes)} nodes and {len(edges)} edges.')
    return {'nodes': nodes, 'edges': edges}


def _as_list(value):
    """Coerce None / scalar / list to list safely."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


# ---------------------------------------------------------------------------
# Stage 4: Source fingerprint
# ---------------------------------------------------------------------------

def compute_source_fingerprint(artifacts):
    """
    Deterministic fingerprint of all indexed source files.
    Consumers compare against current files to detect staleness.
    Algorithm: sort (canonical_path, sha256) pairs by path, SHA-256 the manifest.
    """
    entries = []
    for type_key in artifacts:
        for id_key in artifacts[type_key]:
            entry = artifacts[type_key][id_key]
            canonical_path = entry.get('path', '')
            file_hash = entry.get('hash', '')
            if canonical_path and file_hash:
                entries.append((canonical_path, file_hash))

    entries.sort(key=lambda x: x[0])
    manifest_str = '\n'.join(f'{p}:{h}' for p, h in entries)
    fp = hashlib.sha256(manifest_str.encode('utf-8')).hexdigest()
    return f'sha256:{fp}'


# ---------------------------------------------------------------------------
# Stage 5: Graph state file
# ---------------------------------------------------------------------------

def write_graph_state(project_root, graph, source_fingerprint, duration_s, status='READY'):
    """
    Write .mxagile/state/graph-state.yaml for graph freshness tracking.
    Status values: DISABLED | MISSING | BUILDING | READY | STALE | FAILED
    """
    state_dir = project_root / '.mxagile' / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)
    state_file = state_dir / 'graph-state.yaml'

    state = {
        'schema_version':    1,
        'provider':          'artifact-index',
        'status':            status,
        'last_built':        datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'node_count':        len(graph.get('nodes', [])),
        'edge_count':        len(graph.get('edges', [])),
        'source_fingerprint': source_fingerprint,
        'build_duration_s':  round(duration_s, 2),
    }

    try:
        with open(state_file, 'w', encoding='utf-8') as f:
            yaml.dump(state, f, default_flow_style=False, sort_keys=False)
        print(f'[INFO] Graph state written: {state_file} (status={status})')
    except Exception as e:
        print(f'[WARN] Could not write graph-state.yaml: {e}')


# ---------------------------------------------------------------------------
# Validate flow reference integrity
# ---------------------------------------------------------------------------

def validate_flow_references(artifacts):
    """
    Validate that structured Business Flow references point to known artifact IDs.
    Reports warnings for: unknown roles, unknown requirements, unknown screens,
    unknown decisions, unknown FLOWSTEP transition targets, orphaned steps.
    Does NOT fail the build — violations are warnings only.
    """
    all_ids = set()
    for type_key in artifacts:
        for id_key in artifacts[type_key]:
            all_ids.add(id_key)

    req_ids  = set(artifacts.get('requirement', {}).keys())
    page_ids = set(artifacts.get('page', {}).keys())
    dec_ids  = set(artifacts.get('decision', {}).keys())

    violations = []

    for flow_id, flow_entry in artifacts.get('business_flow', {}).items():
        content = flow_entry.get('content', {}) or {}
        steps   = _as_list(content.get('steps'))
        step_id_set = {s.get('step_id') for s in steps if s.get('step_id')}

        for step in steps:
            step_id = step.get('step_id')
            if not step_id:
                continue
            label = f'{flow_id}/{step_id}'

            # Check req_refs
            for req_ref in _as_list(step.get('req_refs')):
                if req_ref not in req_ids:
                    violations.append(f'[FLOW-REF-WARN] {label}: unknown req_ref {req_ref}')

            # Check screen_ref
            screen_ref = step.get('screen_ref')
            if screen_ref and screen_ref not in page_ids:
                violations.append(f'[FLOW-REF-WARN] {label}: unknown screen_ref {screen_ref}')

            # Check decision_refs
            for dec_ref in _as_list(step.get('decision_refs')):
                if dec_ref not in dec_ids:
                    violations.append(f'[FLOW-REF-WARN] {label}: unknown decision_ref {dec_ref}')

            # Check transition targets
            for transition in _as_list(step.get('transitions')):
                target = transition.get('to')
                if target and target not in step_id_set:
                    violations.append(
                        f'[FLOW-REF-WARN] {label}: transition target {target} '
                        f'not found in steps[] of {flow_id}'
                    )

        # Check for orphaned steps (no incoming transitions from any other step)
        result_id = content.get('result')
        error_paths = set(_as_list(content.get('error_paths')))
        all_transition_targets = set()
        for step in steps:
            for t in _as_list(step.get('transitions')):
                tgt = t.get('to')
                if tgt:
                    all_transition_targets.add(tgt)

        for step in steps:
            step_id = step.get('step_id')
            stype = step.get('type', '')
            # First step is always reachable via trigger; terminal steps need no incoming
            if stype in ('end_node', 'error_node'):
                continue
            # Step 0 (trigger entry) has no incoming by design — skip the first step
            if step is steps[0]:
                continue
            if step_id and step_id not in all_transition_targets:
                violations.append(
                    f'[FLOW-REF-WARN] {flow_id}/{step_id}: orphaned step '
                    f'(no incoming transitions)'
                )

    for v in violations:
        print(v)

    if violations:
        print(f'[WARN] Flow reference validation: {len(violations)} issue(s) found (non-fatal).')
    return violations


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import time
    start_time = time.time()

    if len(sys.argv) > 2 and sys.argv[1] == '--path':
        project_root_path = sys.argv[2]
    elif len(sys.argv) > 1 and not sys.argv[1].startswith('--'):
        project_root_path = sys.argv[1]
    else:
        project_root_path = '.'

    project_root = Path(project_root_path).resolve()
    print(f'[INFO] Building artifact index for project: {project_root}')

    # Read graph config (provider selection / enabled flag)
    config = _read_graph_config(project_root)
    provider = config.get('knowledge_graph', {}).get('provider', 'artifact-index')
    if provider == 'none':
        print('[INFO] Knowledge graph is disabled (provider: none in .mxagile/config.yaml). '
              'Writing DISABLED state.')
        write_graph_state(project_root, {'nodes': [], 'edges': []}, 'sha256:' + '0' * 64,
                          0.0, status='DISABLED')
        return

    # Stage 1: Index YAML artifacts
    artifacts = find_artifacts(project_root)

    # Stage 1b: Extract Design Contract flows (Phase 2)
    find_design_contract_flows(project_root, artifacts)

    # Stage 2: Build graph
    graph = build_graph(artifacts)

    # Stage 2b: Validate flow references (non-fatal)
    validate_flow_references(artifacts)

    # Stage 3: Fingerprint + metadata
    source_fingerprint = compute_source_fingerprint(artifacts)
    graph['source_fingerprint'] = source_fingerprint
    graph['generated_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    # Stage 4: Write index
    state_dir = project_root / '.mxagile' / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)
    output_file = state_dir / 'artifact-index.json'

    print(f'\n[INFO] Writing artifact index to: {output_file}')
    print(f'[INFO] Source fingerprint: {source_fingerprint}')
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(graph, f, indent=2)
        print('\nArtifact index created successfully.')
    except Exception as e:
        print(f'[ERROR] Failed to write JSON output: {e}')
        duration = time.time() - start_time
        write_graph_state(project_root, graph, source_fingerprint, duration, status='FAILED')
        return

    # Stage 5: Write graph state
    duration = time.time() - start_time
    write_graph_state(project_root, graph, source_fingerprint, duration, status='READY')


def _read_graph_config(project_root):
    """Read .mxagile/config.yaml if present. Returns empty dict if absent."""
    config_path = project_root / '.mxagile' / 'config.yaml'
    if config_path.exists():
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f) or {}
        except Exception as e:
            print(f'[WARN] Could not read .mxagile/config.yaml: {e}')
    return {}


if __name__ == '__main__':
    main()
