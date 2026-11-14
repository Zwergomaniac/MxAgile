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


def is_wave_id(value):
    return isinstance(value, str) and re.fullmatch(WAVE_ID_PATTERN, value) is not None


def planned_wave_ids(text):
    identifiers = (match.group(1).removesuffix(':') for match in _HEADING.finditer(text))
    return {identifier for identifier in identifiers if is_wave_id(identifier)}


def checklist_wave_id(name):
    match = CHECKLIST_NAME_PATTERN.fullmatch(name)
    return match.group(1) if match else None


def wave_sort_key(value):
    identifier = str(value)
    parts = tuple((1, int(part)) if part.isascii() and part.isdigit() else (0, part.casefold())
                  for part in re.split(r'([0-9]+)', identifier) if part)
    return (0 if is_wave_id(identifier) else 1, parts, identifier)
