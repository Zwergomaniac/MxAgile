"""Wave identity recognition from the canonical Task schema; never lifecycle authority."""
from __future__ import annotations

import json
import re
from pathlib import Path

_PARENT = Path(__file__).resolve().parent.parent
_SCHEMA = next(path for path in (_PARENT / 'schemas/task.schema.json', _PARENT / '.mxagile/schemas/task.schema.json') if path.is_file())
WAVE_ID_PATTERN = json.loads(_SCHEMA.read_text(encoding='utf-8-sig'))['properties']['wave_id']['pattern']
_BODY = WAVE_ID_PATTERN.removeprefix('^').removesuffix('$')
WAVE_MENTION_PATTERN = re.compile(rf'(?<![\w-])({_BODY})(?![\w-])')
CHECKLIST_PATH_PATTERN = re.compile(rf'^planning/checklists/({_BODY})-implementation-checklist\.ya?ml$')
CHECKLIST_NAME_PATTERN = re.compile(rf'^({_BODY})-implementation-checklist\.ya?ml$')
_HEADING = re.compile(r'(?m)^[ \t]{0,3}#{1,6}[ \t]+(?:(?i:Wave)[ \t]+)?([^\s]+)')
_COMMIT_REF = re.compile(r'\b([0-9a-f]{7,40})\b')


def is_wave_id(value):
    return isinstance(value, str) and re.fullmatch(WAVE_ID_PATTERN, value) is not None


def planned_wave_ids(text):
    identifiers = (match.group(1).removesuffix(':') for match in _HEADING.finditer(text))
    return {identifier for identifier in identifiers if is_wave_id(identifier)}


def extract_plan_wave_claims(text):
    """Extract non-authoritative wave status and commit claims from execution-waves.md tables.

    Plan text and commit mentions are evidence only and never establish canonical DONE.
    """
    claims = {}
    if not isinstance(text, str) or not text:
        return claims
    status_column = None
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped.startswith('|') or not stripped.endswith('|'):
            continue
        cells = [cell.strip().strip('`*') for cell in stripped.strip('|').split('|')]
        if len(cells) < 2:
            continue
        candidate = cells[0].removesuffix(':').strip()
        if candidate.lower() in ('wave', 'wave_id', 'id') and any(cell.lower() in ('status', 'state', 'phase') for cell in cells):
            status_column = next(index for index, cell in enumerate(cells) if cell.lower() in ('status', 'state', 'phase'))
            continue
        if not is_wave_id(candidate):
            continue
        status_cell = cells[status_column if status_column is not None and status_column < len(cells) else -1].lower()
        normalized_status = None
        if re.search(r'\b(done|completed|abgeschlossen)\b', status_cell):
            normalized_status = 'done'
        elif re.search(r'\b(active|implementing|in_progress|in arbeit)\b', status_cell):
            normalized_status = 'implementing'
        elif re.search(r'\b(planned|geplant|open|not_started|ready)\b', status_cell):
            normalized_status = 'planned'
        commits = _COMMIT_REF.findall(raw_line)
        entry = claims.setdefault(candidate, {'statuses': [], 'commits': [], 'lines': []})
        if normalized_status:
            entry['statuses'].append((normalized_status, line_no, status_cell))
        for commit in commits:
            entry['commits'].append((commit, line_no))
        entry['lines'].append(line_no)
    return claims


def checklist_wave_id(name):
    match = CHECKLIST_NAME_PATTERN.fullmatch(name)
    return match.group(1) if match else None


def wave_sort_key(value):
    identifier = str(value)
    parts = tuple((1, int(part)) if part.isascii() and part.isdigit() else (0, part.casefold())
                  for part in re.split(r'([0-9]+)', identifier) if part)
    return (0 if is_wave_id(identifier) else 1, parts, identifier)
