"""
MxAgile Brownfield Artifact Canonicalization Engine

Converts legacy planning/stories/*.md requirements and planning/checklists/*.yaml
tasks into canonical requirements/*.yml and planning/tasks/*.yml conformant with
the MxAgile artifact schemas in .mxagile/schemas/.

This script is called by migrate-stories.ps1 (the orchestrator).

Usage:
    python canonicalize_artifacts.py --project-root <path> [--dry-run] [--phase <phase>]
    python canonicalize_artifacts.py --project-root <path> --validate-output

Phases:
    requirements  - convert planning/stories/*.md -> requirements/*.yml
    tasks         - convert planning/checklists/*.yaml -> planning/tasks/*.yml
    all           - run both phases in sequence (default)

Safety contract:
    - Source files are NEVER deleted or modified
    - Output files are written only after per-file validation passes
    - Canonicalization state is persisted to .mxagile/migration/canonicalization-state.yaml
    - Re-running is safe: already-converted files with matching IDs are skipped
    - --dry-run prints what would be done without writing any files
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

try:
    import yaml
except ImportError:
    print("[ERROR] PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)

TODAY = date.today().isoformat()


# ---------------------------------------------------------------------------
# Markdown frontmatter and section parser
# ---------------------------------------------------------------------------

def parse_md_frontmatter(text):
    """Extract YAML frontmatter from a markdown file.

    Returns (frontmatter_dict, body_text).
    """
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm_text = text[3:end].strip()
    body = text[end + 4:].strip()
    try:
        fm = yaml.safe_load(fm_text) or {}
    except Exception:
        fm = {}
    return fm, body


def extract_h1(body):
    """Return the first H1 heading text."""
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("# ") and not line.startswith("## "):
            return line[2:].strip()
    return ""


def extract_sections(body):
    """Return a dict mapping heading text (lowercase) -> section body text."""
    sections = {}
    current_heading = None
    current_lines = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            if current_heading is not None:
                sections[current_heading] = "\n".join(current_lines).strip()
            heading_text = re.sub(r'^#+\s+', '', stripped)
            heading_text = re.sub(r'^\d+\.\s+', '', heading_text)
            current_heading = heading_text.lower()
            current_lines = []
        else:
            if current_heading is not None:
                current_lines.append(line)
    if current_heading is not None:
        sections[current_heading] = "\n".join(current_lines).strip()
    return sections


# ---------------------------------------------------------------------------
# Acceptance criteria parser (Given/When/Then from markdown)
# ---------------------------------------------------------------------------

def parse_acceptance_criteria(body):
    """Extract all Given/When/Then blocks from the body."""
    criteria = []
    ac_id_counter = [1]

    lines = body.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        # Look for AC headers: **AC-N:** or ### Funktion X then AC blocks
        given = when = then = None
        ac_id = None

        if re.match(r'\*\*AC-\d+', line):
            ac_match = re.search(r'AC-(\d+)', line)
            if ac_match:
                ac_id = f"AC-{ac_match.group(1).zfill(3)}"
            # Read following Given/When/Then lines
            j = i + 1
            while j < len(lines) and j < i + 10:
                l = lines[j].strip()
                if re.match(r'[-*]\s*\*\*Given', l, re.I):
                    given = re.sub(r'^[-*]\s*\*\*Given[:\*\s]+', '', l, flags=re.I).strip()
                elif re.match(r'[-*]\s*\*\*When', l, re.I):
                    when = re.sub(r'^[-*]\s*\*\*When[:\*\s]+', '', l, flags=re.I).strip()
                elif re.match(r'[-*]\s*\*\*Then', l, re.I):
                    then = re.sub(r'^[-*]\s*\*\*Then[:\*\s]+', '', l, flags=re.I).strip()
                j += 1

            if given or when or then:
                criteria.append({
                    "id": ac_id or f"AC-{str(ac_id_counter[0]).zfill(3)}",
                    "given": given or "[to be defined]",
                    "when": when or "[to be defined]",
                    "then": then or "[to be defined]",
                })
                ac_id_counter[0] += 1
        i += 1

    return criteria


# ---------------------------------------------------------------------------
# Business rules parser
# ---------------------------------------------------------------------------

def parse_business_rules(section_text):
    """Extract business rules from a markdown table or list."""
    rules = []
    br_counter = 1
    lines = section_text.splitlines()

    for line in lines:
        line = line.strip()
        if not line or line.startswith("|---|") or line.startswith("| Regel |") or line.startswith("| Rege"):
            continue
        # Table row: | Regel N | Description | Entity |
        if line.startswith("|") and "|" in line[1:]:
            parts = [p.strip() for p in line.strip("|").split("|")]
            if len(parts) >= 2 and parts[0] and parts[1] and parts[1] != "Beschreibung":
                rules.append({
                    "id": f"BR-{str(br_counter).zfill(3)}",
                    "rule": parts[1],
                    "entity": parts[2] if len(parts) > 2 else "",
                })
                br_counter += 1
        # List item
        elif line.startswith("-") or line.startswith("*"):
            text = line.lstrip("-* ").strip()
            if text and text != "...":
                rules.append({
                    "id": f"BR-{str(br_counter).zfill(3)}",
                    "rule": text,
                })
                br_counter += 1

    return rules


# ---------------------------------------------------------------------------
# Target user parser
# ---------------------------------------------------------------------------

def parse_target_users(section_text):
    """Extract user roles from a markdown section."""
    users = []
    seen = set()
    for line in section_text.splitlines():
        line = line.strip()
        # List item: - Rolle 1 — Description
        if line.startswith("-") or line.startswith("*"):
            text = line.lstrip("-* ").strip()
            if " — " in text:
                parts = text.split(" — ", 1)
                role = parts[0].strip()
                desc = parts[1].strip()
            elif text and text != "..." and not text.startswith("["):
                role = text
                desc = ""
            else:
                continue
            if role and role not in seen:
                seen.add(role)
                entry = {"role": role}
                if desc:
                    entry["description"] = desc
                users.append(entry)
    return users


# ---------------------------------------------------------------------------
# Open items parser
# ---------------------------------------------------------------------------

def parse_open_items(section_text):
    """Extract DECISION REQUIRED and open items."""
    items = []
    for line in section_text.splitlines():
        line = line.strip()
        if line.startswith("-") or line.startswith("*"):
            text = line.lstrip("-* ").strip()
            if text and text != "..." and not text.startswith("["):
                items.append(text)
    return items


# ---------------------------------------------------------------------------
# Main requirement converter
# ---------------------------------------------------------------------------

def convert_requirement_md_to_yml(source_path, project_root):
    """Convert a planning/stories/*.md file to a canonical requirement dict.

    Returns (req_id, canonical_dict) or (None, None) if conversion fails.
    """
    text = source_path.read_text(encoding="utf-8")
    fm, body = parse_md_frontmatter(text)
    sections = extract_sections(body)

    # Determine ID: prefer frontmatter req_id, then ID, then filename stem
    req_id = (fm.get("req_id") or fm.get("ID") or source_path.stem).upper()
    if not re.match(r'^REQ-\d{3,}$', req_id):
        # Try to coerce: REQ-1 -> REQ-001
        m = re.match(r'^REQ-(\d+)$', req_id, re.I)
        if m:
            req_id = f"REQ-{m.group(1).zfill(3)}"
        else:
            print(f"[WARN] Cannot determine valid REQ-NNN id for {source_path.name}, skipping")
            return None, None

    title = extract_h1(body) or fm.get("title") or req_id

    # Extract description from section 1 (Ziel und Nutzen) or section 2 (MVP)
    description = ""
    for key in ["ziel und nutzen", "fachliches problem", "ziel der anwendung", "description"]:
        if key in sections and sections[key].strip():
            lines = [l.strip() for l in sections[key].splitlines() if l.strip() and not l.strip().startswith("<!--")]
            if lines:
                description = " ".join(lines[:3])
                break
    if not description:
        description = title

    # target_users
    target_users = []
    for key in ["zielnutzer", "benutzerrollen und berechtigungen", "target users"]:
        if key in sections:
            target_users = parse_target_users(sections[key])
            if target_users:
                break

    # acceptance_criteria
    ac_section = sections.get("akzeptanzkriterien", sections.get("acceptance criteria", body))
    acceptance_criteria = parse_acceptance_criteria(ac_section)

    # business_rules
    br_section = sections.get("geschäftsregeln und validierungen",
                 sections.get("geschaeftsregeln und validierungen",
                 sections.get("business rules", "")))
    business_rules = parse_business_rules(br_section) if br_section else []

    # open_items
    oi_section = sections.get("offene punkte", sections.get("open items", ""))
    open_items = parse_open_items(oi_section) if oi_section else []

    source_rel = str(source_path.relative_to(project_root))

    canonical = {
        "ID": req_id,
        "title": title,
        "description": description,
        "status": "draft",
        "source": "migrated",
        "migrated_from": source_rel,
        "migration_date": TODAY,
    }

    if target_users:
        canonical["target_users"] = target_users
    if acceptance_criteria:
        canonical["acceptance_criteria"] = acceptance_criteria
    if business_rules:
        canonical["business_rules"] = business_rules
    if open_items:
        canonical["open_items"] = open_items

    return req_id, canonical


# ---------------------------------------------------------------------------
# Task converter (from checklist YAML)
# ---------------------------------------------------------------------------

def convert_checklist_yaml_to_tasks(source_path, project_root, start_task_num):
    """Convert a planning/checklists/*.yaml file to a list of canonical task dicts."""
    text = source_path.read_text(encoding="utf-8")
    try:
        data = yaml.safe_load(text) or {}
    except Exception as e:
        print(f"[ERROR] Could not parse {source_path}: {e}")
        return []

    source_rel = str(source_path.relative_to(project_root))
    tasks = []
    task_num = start_task_num

    # Common checklist formats:
    # 1. List of strings: [- "Do X", ...]
    # 2. Dict with 'tasks' or 'items' key
    # 3. Dict with wave/script structure
    items = []
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        for key in ["tasks", "items", "steps", "checklist"]:
            if key in data and isinstance(data[key], list):
                items = data[key]
                break
        if not items:
            # Try to flatten all list values
            for v in data.values():
                if isinstance(v, list):
                    items.extend(v)

    for item in items:
        if isinstance(item, str):
            text_val = item.strip()
            if not text_val or text_val.startswith("#"):
                continue
            task_id = f"TASK-{str(task_num).zfill(3)}"
            tasks.append({
                "ID": task_id,
                "spec": "[SPEC-REQUIRED]",
                "action": text_val,
                "status": "pending",
                "source": "migrated",
                "migrated_from": source_rel,
                "migration_date": TODAY,
                "open_items": ["DECISION REQUIRED: assign to spec"],
            })
            task_num += 1
        elif isinstance(item, dict):
            action = (item.get("action") or item.get("description") or
                      item.get("title") or item.get("name") or "")
            if not action:
                continue
            task_id = (item.get("task_id") or item.get("ID") or
                       f"TASK-{str(task_num).zfill(3)}")
            if not re.match(r'^TASK-\d{3,}$', task_id):
                m = re.match(r'^TASK-(\d+)$', task_id, re.I)
                task_id = f"TASK-{m.group(1).zfill(3)}" if m else f"TASK-{str(task_num).zfill(3)}"
            spec = item.get("spec") or item.get("spec_id") or "[SPEC-REQUIRED]"
            task = {
                "ID": task_id,
                "spec": spec,
                "action": action,
                "status": item.get("status", "pending"),
                "source": "migrated",
                "migrated_from": source_rel,
                "migration_date": TODAY,
            }
            if item.get("detail") or item.get("description"):
                task["detail"] = item.get("detail") or item.get("description")
            if spec == "[SPEC-REQUIRED]":
                task["open_items"] = ["DECISION REQUIRED: assign to spec"]
            tasks.append(task)
            task_num += 1

    return tasks


# ---------------------------------------------------------------------------
# Canonicalization state management
# ---------------------------------------------------------------------------

def load_canon_state(state_path):
    if state_path.exists():
        try:
            return yaml.safe_load(state_path.read_text(encoding="utf-8")) or {}
        except Exception:
            return {}
    return {}


def save_canon_state(state_path, state):
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(
        yaml.dump(state, default_flow_style=False, allow_unicode=True),
        encoding="utf-8"
    )


# ---------------------------------------------------------------------------
# YAML writer that produces clean output
# ---------------------------------------------------------------------------

def write_canonical_yaml(output_path, data, dry_run=False):
    """Write a canonical YAML file with a schema header comment."""
    if dry_run:
        print(f"[DRY-RUN] Would write: {output_path}")
        return True

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Determine schema comment based on artifact type
    artifact_id = data.get("ID", "")
    if artifact_id.startswith("REQ-"):
        schema_ref = "# Schema: .mxagile/schemas/requirement.schema.json"
    elif artifact_id.startswith("SPEC-"):
        schema_ref = "# Schema: .mxagile/schemas/spec.schema.json"
    elif artifact_id.startswith("TASK-"):
        schema_ref = "# Schema: .mxagile/schemas/task.schema.json"
    else:
        schema_ref = ""

    content = yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False)
    if schema_ref:
        content = schema_ref + "\n" + content

    output_path.write_text(content, encoding="utf-8")
    return True


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_canonical_requirement(data, path):
    """Basic validation: required fields present, ID matches filename."""
    errors = []
    for field in ["ID", "title", "description"]:
        if not data.get(field):
            errors.append(f"Missing required field: {field}")
    req_id = data.get("ID", "")
    if not re.match(r'^REQ-\d{3,}$', req_id):
        errors.append(f"ID does not match REQ-NNN pattern: {req_id}")
    if path and path.stem != req_id:
        errors.append(f"ID {req_id} does not match filename stem {path.stem}")
    return errors


def validate_canonical_task(data, path):
    errors = []
    for field in ["ID", "spec", "action"]:
        if not data.get(field):
            errors.append(f"Missing required field: {field}")
    task_id = data.get("ID", "")
    if not re.match(r'^TASK-\d{3,}$', task_id):
        errors.append(f"ID does not match TASK-NNN pattern: {task_id}")
    if path and path.stem != task_id:
        errors.append(f"ID {task_id} does not match filename stem {path.stem}")
    return errors


# ---------------------------------------------------------------------------
# Phase: canonicalize requirements
# ---------------------------------------------------------------------------

def phase_requirements(project_root, dry_run, state):
    stories_dir = project_root / "planning" / "stories"
    req_dir = project_root / "requirements"

    if not stories_dir.exists():
        print(f"[INFO] No planning/stories/ directory found, skipping requirements phase.")
        return 0, 0

    md_files = sorted(stories_dir.glob("REQ-*.md"))
    if not md_files:
        md_files = sorted(stories_dir.glob("*.md"))
    print(f"[INFO] Found {len(md_files)} story files in {stories_dir}")

    converted = 0
    skipped = 0

    items = state.setdefault("items", {})

    for md_path in md_files:
        source_rel = str(md_path.relative_to(project_root))
        item_state = items.get(source_rel, {})

        req_id, canonical = convert_requirement_md_to_yml(md_path, project_root)
        if req_id is None:
            print(f"[SKIP] Could not convert: {md_path.name}")
            skipped += 1
            continue

        output_path = req_dir / f"{req_id}.yml"

        # Skip if already converted and output exists
        if item_state.get("status") == "validated" and output_path.exists():
            print(f"[SKIP] Already converted: {req_id}")
            skipped += 1
            continue

        errors = validate_canonical_requirement(canonical, output_path)
        if errors:
            print(f"[ERROR] Validation failed for {req_id}: {errors}")
            items[source_rel] = {"status": "failed", "errors": errors}
            skipped += 1
            continue

        write_canonical_yaml(output_path, canonical, dry_run=dry_run)
        if not dry_run:
            items[source_rel] = {
                "status": "validated",
                "target": str(output_path.relative_to(project_root)),
                "converted_at": TODAY,
            }
        print(f"[OK] {'Would convert' if dry_run else 'Converted'}: {md_path.name} -> {output_path.name}")
        converted += 1

    return converted, skipped


# ---------------------------------------------------------------------------
# Phase: canonicalize tasks from checklists
# ---------------------------------------------------------------------------

def phase_tasks(project_root, dry_run, state):
    checklists_dir = project_root / "planning" / "checklists"
    tasks_dir = project_root / "planning" / "tasks"

    if not checklists_dir.exists():
        print(f"[INFO] No planning/checklists/ directory found, skipping tasks phase.")
        return 0, 0

    checklist_files = sorted(checklists_dir.glob("*.yaml")) + sorted(checklists_dir.glob("*.yml"))
    # Exclude template files
    checklist_files = [f for f in checklist_files if "template" not in f.name.lower()]
    print(f"[INFO] Found {len(checklist_files)} checklist files in {checklists_dir}")

    # Find highest existing task number
    existing_tasks = sorted(tasks_dir.glob("TASK-*.yml")) if tasks_dir.exists() else []
    start_num = 1
    for t in existing_tasks:
        m = re.match(r'^TASK-(\d+)', t.stem)
        if m:
            start_num = max(start_num, int(m.group(1)) + 1)

    converted = 0
    skipped = 0
    items = state.setdefault("items", {})

    for cl_path in checklist_files:
        source_rel = str(cl_path.relative_to(project_root))
        item_state = items.get(source_rel, {})

        if item_state.get("status") == "validated":
            print(f"[SKIP] Already converted: {cl_path.name}")
            skipped += 1
            continue

        tasks = convert_checklist_yaml_to_tasks(cl_path, project_root, start_num)
        if not tasks:
            print(f"[SKIP] No extractable tasks from: {cl_path.name}")
            skipped += 1
            continue

        file_converted = 0
        for task_data in tasks:
            task_id = task_data["ID"]
            output_path = tasks_dir / f"{task_id}.yml"
            if output_path.exists():
                print(f"[SKIP] Task already exists: {task_id}")
                continue
            errors = validate_canonical_task(task_data, output_path)
            if errors:
                print(f"[ERROR] Validation failed for {task_id}: {errors}")
                continue
            write_canonical_yaml(output_path, task_data, dry_run=dry_run)
            print(f"[OK] {'Would create' if dry_run else 'Created'}: {output_path.name}")
            file_converted += 1
            start_num += 1

        if not dry_run and file_converted > 0:
            items[source_rel] = {
                "status": "validated",
                "tasks_created": file_converted,
                "converted_at": TODAY,
            }
        converted += file_converted

    return converted, skipped


# ---------------------------------------------------------------------------
# Validate output (post-conversion check)
# ---------------------------------------------------------------------------

def phase_validate_output(project_root):
    req_dir = project_root / "requirements"
    tasks_dir = project_root / "planning" / "tasks"
    errors_found = 0

    for yml_path in sorted(req_dir.glob("*.yml")) if req_dir.exists() else []:
        if yml_path.stem == "template":
            continue
        try:
            data = yaml.safe_load(yml_path.read_text(encoding="utf-8")) or {}
        except Exception as e:
            print(f"[ERROR] Parse error in {yml_path.name}: {e}")
            errors_found += 1
            continue
        errs = validate_canonical_requirement(data, yml_path)
        if errs:
            print(f"[ERROR] {yml_path.name}: {errs}")
            errors_found += 1
        else:
            print(f"[VALID] {yml_path.name}")

    for yml_path in sorted(tasks_dir.glob("TASK-*.yml")) if tasks_dir.exists() else []:
        try:
            data = yaml.safe_load(yml_path.read_text(encoding="utf-8")) or {}
        except Exception as e:
            print(f"[ERROR] Parse error in {yml_path.name}: {e}")
            errors_found += 1
            continue
        errs = validate_canonical_task(data, yml_path)
        if errs:
            print(f"[ERROR] {yml_path.name}: {errs}")
            errors_found += 1
        else:
            print(f"[VALID] {yml_path.name}")

    if errors_found:
        print(f"\n[FAIL] {errors_found} validation error(s) found.")
        return False
    print("\n[PASS] All canonical artifacts validate.")
    return True


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="MxAgile Brownfield Artifact Canonicalization")
    parser.add_argument("--project-root", required=True, help="Absolute path to project root")
    parser.add_argument("--phase", choices=["requirements", "tasks", "all"], default="all")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without writing files")
    parser.add_argument("--validate-output", action="store_true", help="Validate existing canonical artifacts")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    if not project_root.exists():
        print(f"[ERROR] Project root not found: {project_root}")
        sys.exit(1)

    state_path = project_root / ".mxagile" / "migration" / "canonicalization-state.yaml"
    state = load_canon_state(state_path)

    if args.validate_output:
        ok = phase_validate_output(project_root)
        sys.exit(0 if ok else 1)

    if state.get("status") == "complete" and not args.dry_run:
        print("[INFO] Canonicalization already complete. Use --dry-run to inspect or --validate-output to revalidate.")
        sys.exit(0)

    if not args.dry_run:
        state["status"] = "in_progress"
        state["started_at"] = state.get("started_at", TODAY)
        save_canon_state(state_path, state)

    total_converted = 0
    total_skipped = 0

    if args.phase in ("requirements", "all"):
        print("\n[PHASE] Requirements")
        req_state = state.setdefault("requirements", {})
        c, s = phase_requirements(project_root, args.dry_run, req_state)
        total_converted += c
        total_skipped += s

    if args.phase in ("tasks", "all"):
        print("\n[PHASE] Tasks")
        task_state = state.setdefault("tasks", {})
        c, s = phase_tasks(project_root, args.dry_run, task_state)
        total_converted += c
        total_skipped += s

    if not args.dry_run:
        save_canon_state(state_path, state)

    print(f"\n[SUMMARY] Converted: {total_converted}, Skipped/failed: {total_skipped}")

    if not args.dry_run and total_skipped == 0:
        # Final validation pass
        print("\n[PHASE] Validation")
        ok = phase_validate_output(project_root)
        if ok:
            state["status"] = "complete"
            state["completed_at"] = TODAY
            save_canon_state(state_path, state)
            print("\n[DONE] Canonicalization complete. Update artifact_canonicalization in state.yaml.")
        else:
            print("\n[WARN] Canonicalization finished with validation errors. Status remains in_progress.")


if __name__ == "__main__":
    main()
