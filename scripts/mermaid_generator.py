"""
MxAgile Mermaid Generator (Phase 2c)

Generates Mermaid flowchart diagrams deterministically from structured Business Flow
steps[] in a MxMocketeer Design Contract.

IMPORTANT — Canonicity Rule:
  Mermaid diagrams are DERIVED views of the structured steps[].
  They are NEVER stored in the Design Contract (neither as canonical data nor
  as rendered HTML embedded in the contract).
  If a Mermaid diagram contradicts steps[], steps[] is authoritative.

Usage:
  python scripts/mermaid_generator.py <html_path> [flow_id]
  python scripts/mermaid_generator.py --json <flow_json>

Output:
  Mermaid flowchart text written to stdout.
  With --all: all structured flows in the HTML file are printed.

Examples:
  python scripts/mermaid_generator.py input-resources/ui-ux/mockup.html FLOW-ORDER-SUBMIT
  python scripts/mermaid_generator.py input-resources/ui-ux/mockup.html --all
"""

import json
import re
import sys
import argparse
from pathlib import Path


# Mermaid node shapes by step type (flowchart TD syntax)
SHAPE_OPEN  = {
    'user_action':      ('([', '])'),     # stadium
    'system_action':    ('[', ']'),        # rectangle
    'decision_node':    ('{', '}'),        # diamond
    'integration_call': ('[/', '/]'),      # parallelogram
    'ui_state':         ('(', ')'),        # rounded rectangle
    'end_node':         ('((', '))'),      # circle
    'error_node':       ('((', '))'),      # circle (marked red via class)
}
DEFAULT_SHAPE = ('[', ']')

# Maximum label length before truncation in Mermaid output
MAX_LABEL_LEN = 60


def _mermaid_label(text, max_len=MAX_LABEL_LEN):
    """Escape and truncate text for use inside a Mermaid node label."""
    if not text:
        return ''
    text = text.replace('"', "'")
    if len(text) > max_len:
        text = text[:max_len - 1] + '…'
    return text


def _step_node_id(flow_id, step_id):
    """Generate a Mermaid-safe node identifier from composite IDs."""
    return re.sub(r'[^A-Za-z0-9_]', '_', f'{flow_id}__{step_id}')


def generate_mermaid(flow, indent='    '):
    """
    Generate a Mermaid flowchart string from a structured flow dict.

    Args:
      flow:   a flow entry dict matching business-flow.schema.json
      indent: indentation string for Mermaid lines

    Returns:
      Mermaid flowchart text (str), or None if the flow has no structured steps.
    """
    flow_id = flow.get('id', 'FLOW')
    steps   = [s for s in (flow.get('steps') or []) if s.get('step_id')]

    if not steps:
        return None

    lines = [f'flowchart TD']
    class_lines = []

    for step in steps:
        step_id  = step['step_id']
        stype    = step.get('type', 'system_action')
        desc     = step.get('description') or step_id
        node_id  = _step_node_id(flow_id, step_id)
        label    = _mermaid_label(desc)

        open_br, close_br = SHAPE_OPEN.get(stype, DEFAULT_SHAPE)
        lines.append(f'{indent}{node_id}{open_br}"{label}"{close_br}')

        # Annotations: screen_ref + req_refs in tooltip (not rendered, stored as comment)
        meta_parts = []
        if step.get('screen_ref'):
            meta_parts.append(f'screen:{step["screen_ref"]}')
        if step.get('req_refs'):
            meta_parts.append('reqs:' + ','.join(step['req_refs']))
        if meta_parts:
            lines.append(f'{indent}%% {step_id}: {" | ".join(meta_parts)}')

        # Error nodes get a special style class
        if stype == 'error_node':
            class_lines.append(f'{indent}class {node_id} errorNode')

    lines.append('')

    # Transitions
    step_id_to_node = {
        s['step_id']: _step_node_id(flow_id, s['step_id'])
        for s in steps
    }

    for step in steps:
        step_id  = step['step_id']
        node_id  = step_id_to_node[step_id]
        for transition in (step.get('transitions') or []):
            target_step_id = transition.get('to')
            if not target_step_id or target_step_id not in step_id_to_node:
                continue
            target_node_id = step_id_to_node[target_step_id]
            label = transition.get('label', '')
            if label:
                lines.append(f'{indent}{node_id} -->|"{_mermaid_label(label, 40)}"| {target_node_id}')
            else:
                lines.append(f'{indent}{node_id} --> {target_node_id}')

    # Style classes
    if class_lines:
        lines.append('')
        lines.append(f'{indent}classDef errorNode fill:#f88,stroke:#c00,color:#000')
        lines.extend(class_lines)

    return '\n'.join(lines)


def generate_all_flows(html_path):
    """
    Extract all structured flows from a Design Contract HTML file and
    return a list of (flow_id, mermaid_text) tuples.

    Only flows with at least one step_id are included (STRUCTURED or OPEN flows
    that have been partially structured).
    """
    try:
        content = Path(html_path).read_text(encoding='utf-8', errors='ignore')
    except Exception as e:
        print(f'[ERROR] Cannot read {html_path}: {e}', file=sys.stderr)
        return []

    pattern = re.compile(
        r'<script[^>]+type=["\']application/json["\'][^>]+id=["\']mocketeer-spec["\'][^>]*>(.*?)</script>',
        re.DOTALL | re.IGNORECASE
    )
    match = pattern.search(content)
    if not match:
        return []

    try:
        spec = json.loads(match.group(1))
    except json.JSONDecodeError as e:
        print(f'[ERROR] Cannot parse mocketeer-spec JSON: {e}', file=sys.stderr)
        return []

    results = []
    for flow in (spec.get('flows') or []):
        mermaid = generate_mermaid(flow)
        if mermaid:
            results.append((flow.get('id', 'FLOW'), mermaid))
    return results


def main():
    parser = argparse.ArgumentParser(
        description='Generate Mermaid flowcharts from MxMocketeer structured Business Flows'
    )
    parser.add_argument('html_path', nargs='?', help='Path to Design Contract HTML file')
    parser.add_argument('flow_id',  nargs='?', help='Specific FLOW-NNN ID to generate (default: all)')
    parser.add_argument('--all',    action='store_true', help='Generate all flows in the file')
    parser.add_argument('--json',   help='Inline flow JSON string (overrides html_path)')
    args = parser.parse_args()

    if args.json:
        try:
            flow = json.loads(args.json)
        except json.JSONDecodeError as e:
            print(f'[ERROR] Invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
        mermaid = generate_mermaid(flow)
        if mermaid:
            print(mermaid)
        else:
            print('[INFO] No structured steps found in flow.', file=sys.stderr)
        return

    if not args.html_path:
        parser.print_help()
        sys.exit(1)

    all_flows = generate_all_flows(args.html_path)
    if not all_flows:
        print('[INFO] No structured flows found in this Design Contract.', file=sys.stderr)
        sys.exit(0)

    if args.all or not args.flow_id:
        for flow_id, mermaid in all_flows:
            print(f'\n%% --- {flow_id} ---')
            print(mermaid)
    else:
        found = [(fid, m) for fid, m in all_flows if fid == args.flow_id]
        if not found:
            print(f'[ERROR] Flow {args.flow_id!r} not found or has no structured steps.', file=sys.stderr)
            sys.exit(1)
        for _, mermaid in found:
            print(mermaid)


if __name__ == '__main__':
    main()
