"""MxAgile Security Projection: deterministic, read-only projection of a Mendix model's security.

Authority is the Mendix model. This module only *projects* what ``mxcli`` reports into a normalized
``security-matrix.yaml`` (evidence artifact, never hand-edited) and compares two such snapshots.
Nothing is synthesized: anything mxcli cannot report is recorded as a limitation/warning and marks
the projection ``complete: false``.

CLI:
    python security_projection.py generate --project <App.mpr> [--out <file>] [--mxcli <exe>] [--force]
                                           [--reason-type T --reason-ref R --reason-text X]
    python security_projection.py diff <before.yaml> <after.yaml> [--json]
    python security_projection.py validate <file.yaml>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import yaml

SCHEMA_VERSION = 1
GENERATOR = "security_projection.py"
GENERATOR_VERSION = "1.0.0"
DEFAULT_OUT = ".mxagile/state/security/security-matrix.yaml"
REASON_TYPES = ("requirement", "task", "decision", "finding", "unknown")
SEVERITIES = ("info", "security_relevant", "high_impact", "critical")
# Sections of the semantic body (fingerprinted). Everything else (generated, change_context, drift) is provenance.
BODY_KEYS = ("security", "roles", "pages", "microflows", "nanoflows", "entities", "effective_access", "findings")

Runner = Callable[[list[str]], str]


class ExtractionError(RuntimeError):
    pass


# --------------------------------------------------------------------------- mxcli access

def make_mxcli_runner(mxcli: str, project: str) -> Runner:
    def run(args: list[str]) -> str:
        cmd = [mxcli, "bson", "dump", "-p", project, *args[2:]] if args[0] == "bson" else [mxcli, "-p", project, *args]
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        if proc.returncode != 0:
            raise ExtractionError(f"mxcli exit {proc.returncode}: {' '.join(args)}: {(proc.stderr or proc.stdout).strip()[:300]}")
        if re.search(r"^(Error|Parse error):", proc.stdout, re.M):
            raise ExtractionError(f"mxcli reported an error for {' '.join(args)}: {proc.stdout.strip()[:300]}")
        return proc.stdout
    return run


def parse_json_output(text: str) -> Any:
    """mxcli may print banners; take the first JSON document in the stream."""
    decoder = json.JSONDecoder()
    for match in re.finditer(r"^[\[{]", text, re.M):
        try:
            return decoder.raw_decode(text[match.start():])[0]
        except ValueError:
            continue
    raise ExtractionError("no JSON document in mxcli output")


def _query(run: Runner, statement: str) -> Any:
    return parse_json_output(run(["-c", statement, "--json"]))


def _split_roles(value: str) -> list[str]:
    return sorted({part.strip() for part in value.split(",") if part.strip()})


# --------------------------------------------------------------------------- normalization

def _truthy(value: Any) -> bool | None:
    text = str(value).strip().lower()
    if text in ("true", "yes"):
        return True
    if text in ("false", "no"):
        return False
    return None


def normalize_security(rows: list[dict]) -> dict:
    props = {row["Property"]: row["Value"] for row in rows}
    out: dict[str, Any] = {
        "level": str(props["SecurityLevel"]).upper() if "SecurityLevel" in props else None,
        "check_security": _truthy(props["CheckSecurity"]) if "CheckSecurity" in props else None,
        "strict_mode": _truthy(props["StrictMode"]) if "StrictMode" in props else None,
        "demo_users_enabled": _truthy(props["DemoUsersEnabled"]) if "DemoUsersEnabled" in props else None,
        "guest_access": _truthy(props["GuestAccess"]) if "GuestAccess" in props else None,
        "guest_user_role": props.get("GuestUserRole") or None,
        "admin_user": props.get("AdminUser") or None,
    }
    return out


_USER_ROLE_RE = re.compile(r"create\s+user\s+role\s+(?P<name>\"[^\"]+\"|\S+)\s*\((?P<roles>[^)]*)\)\s*(?P<manage>manage\s+all\s+roles)?", re.I)


def parse_user_role_mdl(mdl: str) -> dict:
    match = _USER_ROLE_RE.search(mdl)
    if not match:
        raise ExtractionError(f"unparseable DESCRIBE USER ROLE output: {mdl[:120]!r}")
    roles = sorted({r.strip().strip('"') for r in match.group("roles").split(",") if r.strip()})
    return {"module_roles": roles, "manage_all_roles": bool(match.group("manage"))}


def _short_member(entity: str, member: str) -> str:
    prefix = entity + "."
    return member[len(prefix):] if member.startswith(prefix) else member


_RIGHTS = ("create", "read", "write", "delete")


def normalize_entity_rule(entity: str, row: dict) -> dict:
    rights = {part.strip().lower() for part in str(row.get("Rights", "")).split(",") if part.strip()}
    default = str(row.get("DefaultMemberAccess") or "None")
    member_access: dict[str, str] = {}
    for part in filter(None, (p.strip() for p in str(row.get("MemberAccess") or "").split(","))):
        name, _, mode = part.rpartition(":")
        member_access[_short_member(entity, name)] = mode
    readable = sorted(m for m, mode in member_access.items() if mode in ("ReadOnly", "ReadWrite"))
    writable = sorted(m for m, mode in member_access.items() if mode == "ReadWrite")

    def members(selected: list[str], allowed_modes: tuple[str, ...]) -> Any:
        # "*" only when every listed member AND the default for unlisted (future) members qualify.
        if default in allowed_modes and len(selected) == len(member_access):
            return "*"
        return selected

    xpath = row.get("XPath")
    return {
        "roles": _split_roles(str(row.get("Roles", ""))),
        "create": "create" in rights,
        "delete": "delete" in rights,
        "read": {"granted": "read" in rights, "members": members(readable, ("ReadOnly", "ReadWrite"))},
        "write": {"granted": "write" in rights, "members": members(writable, ("ReadWrite",))},
        "default_member_access": default,
        "xpath": xpath if xpath else None,
    }


def _rule_sort_key(rule: dict) -> str:
    return json.dumps(rule, sort_keys=True, ensure_ascii=False)


def _resource_grants(universe: list[str], rows: list[dict], object_type: str) -> dict:
    grants: dict[str, set[str]] = {name: set() for name in universe}
    for row in rows:
        if row.get("ObjectType") == object_type:
            grants.setdefault(row["QualifiedName"], set()).update(_split_roles(row.get("Roles", "")))
    return {name: {"grants": sorted(roles)} for name, roles in sorted(grants.items())}


# --------------------------------------------------------------------------- extraction

def extract(run: Runner, *, workers: int = 4, mxcli_version: str | None = None) -> dict:
    """Run the mxcli queries and return a normalized body plus extraction warnings.

    Returns {"body": {...}, "warnings": [...], "sections": {section: "complete"|"failed"}}.
    """
    warnings: list[str] = []
    sections: dict[str, str] = {}
    body: dict[str, Any] = {key: None for key in BODY_KEYS}

    def guarded(section: str, fn: Callable[[], Any]) -> Any:
        try:
            value = fn()
            sections[section] = "complete"
            return value
        except (ExtractionError, KeyError, ValueError, subprocess.SubprocessError) as exc:
            sections[section] = "failed"
            warnings.append(f"{section}: extraction failed: {exc}")
            return None

    body["security"] = guarded("security", lambda: normalize_security(_query(run, "SHOW PROJECT SECURITY")))

    def roles() -> dict:
        user_rows = _query(run, "SHOW USER ROLES")
        module_rows = _query(run, "SHOW MODULE ROLES")
        user_roles = {}
        for row in user_rows:
            described = parse_json_output(run(["-c", f"DESCRIBE USER ROLE {row['Name']}", "--json"]))
            parsed = parse_user_role_mdl(described["mdl"])
            user_roles[row["Name"]] = {
                **parsed,
                "check_security": _truthy(row.get("Check Security")),
            }
        return {
            "user_roles": dict(sorted(user_roles.items())),
            "module_roles": sorted(r["Qualified Name"] for r in module_rows),
        }
    body["roles"] = guarded("roles", roles)

    matrix = guarded("matrix", lambda: _query(run, "SHOW SECURITY MATRIX"))
    pages = guarded("pages", lambda: sorted(r["Qualified Name"] for r in _query(run, "SHOW PAGES")))
    mfs = guarded("microflows", lambda: sorted(r["Qualified Name"] for r in _query(run, "SHOW MICROFLOWS")))
    nfs = guarded("nanoflows", lambda: sorted(r["Qualified Name"] for r in _query(run, "SHOW NANOFLOWS")))
    # mxcli lists only resources that have grants in the matrix; absence from a complete resource
    # listing is therefore recorded as an empty grant list (basis stated in the schema notes).
    body["pages"] = _resource_grants(pages, matrix, "Page") if matrix is not None and pages is not None else None
    body["microflows"] = _resource_grants(mfs, matrix, "Microflow") if matrix is not None and mfs is not None else None
    if body["pages"] is None:
        sections["pages"] = "failed"
    if body["microflows"] is None:
        sections["microflows"] = "failed"
    sections.pop("matrix", None)

    def nanoflow_roles(name: str) -> tuple[str, list[str]]:
        dump = parse_json_output(run(["bson", "dump", "--type", "nanoflow", "--object", name, "--format", "json"]))
        for item in dump:
            if item.get("Key") == "AllowedModuleRoles":
                return name, sorted(v for v in item["Value"] if isinstance(v, str))
        raise ExtractionError(f"AllowedModuleRoles missing in nanoflow {name}")

    def nanoflows() -> dict:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            return {name: {"grants": roles_} for name, roles_ in sorted(pool.map(nanoflow_roles, nfs))}
    body["nanoflows"] = guarded("nanoflows", nanoflows) if nfs is not None else None
    if nfs is None:
        sections["nanoflows"] = "failed"

    def entity_rules(entity: dict) -> tuple[str, list[dict]]:
        name = entity["Entity"]
        rows = _query(run, f"SHOW ACCESS ON {name}") if entity.get("AccessRules", 0) else []
        return name, sorted((normalize_entity_rule(name, row) for row in rows), key=_rule_sort_key)

    def entities() -> dict:
        listing = _query(run, "SHOW ENTITIES")
        with ThreadPoolExecutor(max_workers=workers) as pool:
            return {name: {"access_rules": rules} for name, rules in sorted(pool.map(entity_rules, listing))}
    body["entities"] = guarded("entities", entities)

    if all(body.get(k) is not None for k in ("roles", "pages", "microflows", "nanoflows")):
        body["effective_access"] = compute_effective_access(body)
        sections["effective_access"] = "complete"
    else:
        sections["effective_access"] = "failed"
        warnings.append("effective_access: not computed because a prerequisite section is incomplete")
    body["findings"] = derive_findings(body, sections)
    return {"body": body, "warnings": sorted(warnings), "sections": dict(sorted(sections.items()))}


# --------------------------------------------------------------------------- effective access

def _mode(rules: list[dict], granted: Callable[[dict], bool]) -> str:
    granting = [r for r in rules if granted(r)]
    if not granting:
        return "none"
    return "unconditional" if any(r["xpath"] is None for r in granting) else "conditional"


def compute_effective_access(body: dict) -> dict:
    """Application User Role -> union of its Module Roles' grants (additive in Mendix).

    Entities are NOT flattened: the contributing rules (with XPath and member lists) are kept and the
    summary only says none | unconditional | conditional per right.
    """
    out: dict[str, Any] = {}
    for user_role, info in body["roles"]["user_roles"].items():
        mroles = set(info["module_roles"])
        entry: dict[str, Any] = {"module_roles": sorted(mroles)}
        for key in ("pages", "microflows", "nanoflows"):
            entry[key] = sorted(n for n, v in (body[key] or {}).items() if mroles & set(v["grants"]))
        ents: dict[str, Any] = {}
        for name, data in (body["entities"] or {}).items():
            rules = []
            for rule in data["access_rules"]:
                via = sorted(mroles & set(rule["roles"]))
                if via:
                    rules.append({**{k: rule[k] for k in ("create", "delete", "read", "write", "xpath", "default_member_access")}, "via_module_roles": via})
            if rules:
                ents[name] = {
                    "summary": {
                        "create": _mode(rules, lambda r: r["create"]),
                        "delete": _mode(rules, lambda r: r["delete"]),
                        "read": _mode(rules, lambda r: r["read"]["granted"]),
                        "write": _mode(rules, lambda r: r["write"]["granted"]),
                    },
                    "rules": sorted(rules, key=_rule_sort_key),
                }
        entry["entities"] = dict(sorted(ents.items()))
        out[user_role] = entry
    return dict(sorted(out.items()))


# --------------------------------------------------------------------------- findings (snapshot-only, conservative)

def derive_findings(body: dict, sections: dict[str, str]) -> list[dict]:
    findings: list[dict] = []

    def add(fid: str, severity: str, subject: str, message: str) -> None:
        findings.append({"id": fid, "severity": severity, "subject": subject, "message": message})

    if any(state != "complete" for state in sections.values()):
        failed = sorted(k for k, v in sections.items() if v != "complete")
        add("SEC-EXTRACTION-INCOMPLETE", "high_impact", "projection", f"Sections not extracted: {', '.join(failed)}")
    sec = body.get("security") or {}
    if sec.get("level") and sec["level"] != "PRODUCTION":
        add("SEC-LEVEL-NOT-PRODUCTION", "critical" if sec["level"] == "OFF" else "high_impact", "security.level",
            f"Project security level is {sec['level']}")
    if sec.get("level") == "PRODUCTION" and sec.get("demo_users_enabled"):
        add("SEC-DEMO-USERS-IN-PRODUCTION", "security_relevant", "security.demo_users_enabled",
            "Demo users are enabled while security level is PRODUCTION")
    guest_role = sec.get("guest_user_role")
    if sec.get("guest_access") and guest_role:
        add("SEC-GUEST-ACCESS-ENABLED", "info", "security.guest_access", f"Anonymous access enabled; guest user role is {guest_role}")
        eff = (body.get("effective_access") or {}).get(guest_role, {})
        for entity, data in sorted(eff.get("entities", {}).items()):
            risky = sorted(r for r in ("create", "delete", "write") if data["summary"][r] == "unconditional")
            if risky:
                add("SEC-GUEST-ENTITY-WRITE", "security_relevant", entity,
                    f"Guest user role {guest_role} has unconditional {', '.join(risky)} on {entity}")
    return sorted(findings, key=lambda f: (f["id"], f["subject"]))


# --------------------------------------------------------------------------- fingerprint / assembly

def semantic_body(doc: dict) -> dict:
    return {key: doc.get(key) for key in BODY_KEYS}


def fingerprint(doc: dict) -> str:
    canonical = json.dumps(semantic_body(doc), sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def git_provenance(project_dir: Path) -> dict:
    def git(*args: str) -> str | None:
        try:
            proc = subprocess.run(["git", "-C", str(project_dir), *args], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            return None
        return proc.stdout.strip() if proc.returncode == 0 else None
    head = git("rev-parse", "HEAD")
    if not head:
        return {"project_revision": None, "model_dirty": None, "last_model_commit": None}
    status = git("status", "--porcelain", "--", ".")
    last = git("log", "-1", "--format=%H", "--", ".")
    return {"project_revision": head, "model_dirty": bool(status) if status is not None else None, "last_model_commit": last}


def build_reason(reason_type: str | None, reference: str | None, text: str | None) -> dict:
    """Reasons are never inferred. They exist only when explicitly supplied by a human/agent with a reference."""
    if not reason_type or reason_type == "unknown":
        return {"type": "unknown", "reference": None, "text": None}
    if reason_type not in REASON_TYPES or not reference:
        raise ValueError("a reason requires --reason-type in requirement|task|decision|finding and a --reason-ref")
    return {"type": reason_type, "reference": reference, "text": text or None}


def assemble(extracted: dict, *, mxcli_version: str | None, provenance: dict, reason: dict,
             previous: dict | None, now: datetime | None = None) -> dict:
    warnings = list(extracted["warnings"])
    if provenance.get("project_revision") is None:
        warnings.append("project_revision: project is not inside a git repository; revision unknown")
    if mxcli_version is None:
        warnings.append("mxcli_version: could not be determined")
    complete = all(state == "complete" for state in extracted["sections"].values())
    doc: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "generated": {
            "generated_at": (now or datetime.now(timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "generator": f"{GENERATOR} {GENERATOR_VERSION}",
            "source": "mendix-model",
            "mxcli_version": mxcli_version,
            "project_revision": provenance.get("project_revision"),
            "complete": complete,
            "sections": extracted["sections"],
            "warnings": sorted(set(warnings)),
        },
        **extracted["body"],
    }
    doc["generated"]["fingerprint"] = fingerprint(doc)
    drift = diff_snapshots(previous, doc) if previous else None
    doc["change_context"] = {
        "last_generated": doc["generated"]["generated_at"],
        "source_revision": provenance.get("project_revision"),
        "model_dirty": provenance.get("model_dirty"),
        "last_model_commit": provenance.get("last_model_commit"),
        "previous_fingerprint": (previous or {}).get("generated", {}).get("fingerprint"),
        "reason": reason,
    }
    doc["drift"] = drift
    return doc


# --------------------------------------------------------------------------- drift

def _grant_facets(doc: dict) -> dict:
    """Flatten a snapshot into comparable facts: {(kind, subject, detail): value}."""
    facts: dict[tuple, Any] = {}
    sec = doc.get("security") or {}
    for key, value in sec.items():
        facts[("security", key, "")] = value
    for name, info in ((doc.get("roles") or {}).get("user_roles") or {}).items():
        facts[("user_role", name, "")] = True
        for mr in info["module_roles"]:
            facts[("role_mapping", name, mr)] = True
    for mr in (doc.get("roles") or {}).get("module_roles") or []:
        facts[("module_role", mr, "")] = True
    for kind, section in (("page", "pages"), ("microflow", "microflows"), ("nanoflow", "nanoflows")):
        for name, info in (doc.get(section) or {}).items():
            for role in info["grants"]:
                facts[(f"{kind}_grant", name, role)] = True
    for entity, data in (doc.get("entities") or {}).items():
        per_role: dict[str, dict] = {}
        for rule in data["access_rules"]:
            for role in rule["roles"]:
                facet = per_role.setdefault(role, {"create": False, "delete": False, "read": set(), "write": set(), "xpath": set()})
                facet["create"] |= rule["create"]
                facet["delete"] |= rule["delete"]
                for right in ("read", "write"):
                    members = rule[right]["members"]
                    facet[right] |= {"*"} if members == "*" else set(members)
                facet["xpath"].add(rule["xpath"])
        for role, facet in per_role.items():
            if facet["create"]:
                facts[("entity_create", entity, role)] = True
            if facet["delete"]:
                facts[("entity_delete", entity, role)] = True
            for right in ("read", "write"):
                for member in facet[right]:
                    facts[(f"entity_{right}_member", entity, f"{role}|{member}")] = True
            facts[("entity_xpath", entity, role)] = tuple(sorted(("" if x is None else x) for x in facet["xpath"]))
    return facts


def _classify(kind: str, subject: str, detail: str, before: Any, after: Any, added: bool, removed: bool) -> tuple[str, str] | None:
    """Return (type, severity). Severity is the impact class consumed by existing impact/verification tooling."""
    if kind == "security":
        if subject == "level":
            lowered = str(after) in ("OFF", "PROTOTYPE") and str(before) == "PRODUCTION"
            return "security_level_changed", "critical" if lowered else "security_relevant"
        if subject in ("guest_access", "guest_user_role"):
            return "guest_security_changed", "high_impact" if (after or subject == "guest_user_role") else "security_relevant"
        return f"security_{subject}_changed", "security_relevant"
    simple = {
        "user_role": "user_role", "module_role": "module_role", "role_mapping": "role_mapping",
        "page_grant": "page_view", "microflow_grant": "microflow_execute", "nanoflow_grant": "nanoflow_execute",
        "entity_create": "entity_create", "entity_delete": "entity_delete",
        "entity_read_member": "entity_read_member", "entity_write_member": "entity_write_member",
    }
    if kind in simple:
        verb = "added" if added else "removed"
        sev = "info" if removed else "security_relevant"
        if added and kind in ("entity_delete",):
            sev = "high_impact"
        if added and kind == "entity_write_member" and detail.endswith("|*"):
            sev = "high_impact"
        if added and kind == "role_mapping":
            sev = "security_relevant"
        return f"{simple[kind]}_{verb}", sev
    return None


def diff_snapshots(before: dict | None, after: dict) -> dict:
    """Deterministic structural drift between two snapshots. Timestamps/provenance are ignored."""
    result: dict[str, Any] = {"comparable": True, "changes": [], "notes": []}
    if before is None:
        return {"comparable": False, "changes": [], "notes": ["no previous snapshot"]}
    if before.get("schema_version") != after.get("schema_version"):
        return {"comparable": False, "changes": [], "notes": ["schema_version differs; no drift computed"]}
    for label, doc in (("before", before), ("after", after)):
        if not doc.get("generated", {}).get("complete", False):
            result["comparable"] = False
            result["notes"].append(f"{label} snapshot is incomplete; additions/removals in failed sections are not drift")
    failed = {s for d in (before, after) for s, st in d.get("generated", {}).get("sections", {}).items() if st != "complete"}
    a, b = _grant_facets(before), _grant_facets(after)
    skip_kinds: set[str] = set()
    sect_kinds = {"roles": ("user_role", "role_mapping", "module_role"), "pages": ("page_grant",),
                  "microflows": ("microflow_grant",), "nanoflows": ("nanoflow_grant",), "security": ("security",),
                  "entities": ("entity_create", "entity_delete", "entity_read_member", "entity_write_member", "entity_xpath")}
    for section in failed:
        skip_kinds.update(sect_kinds.get(section, ()))
    changes = []
    for key in sorted(set(a) | set(b), key=lambda k: tuple(str(x) for x in k)):
        kind, subject, detail = key
        if kind in skip_kinds:
            continue
        in_a, in_b = key in a, key in b
        if kind == "entity_xpath":
            if in_a and in_b and a[key] != b[key]:
                old, new = a[key], b[key]
                if "" in new and "" not in old:
                    changes.append({"type": "entity_xpath_removed", "severity": "high_impact", "kind": kind, "subject": subject, "detail": detail, "before": list(old), "after": list(new)})
                else:
                    changes.append({"type": "entity_xpath_changed", "severity": "security_relevant", "kind": kind, "subject": subject, "detail": detail, "before": list(old), "after": list(new)})
            continue
        if kind == "security":
            if in_a and in_b and a[key] != b[key]:
                t, sev = _classify(kind, subject, detail, a[key], b[key], False, False)
                changes.append({"type": t, "severity": sev, "kind": kind, "subject": subject, "detail": detail, "before": a[key], "after": b[key]})
            continue
        if in_a != in_b:
            t, sev = _classify(kind, subject, detail, None, None, in_b, in_a)
            changes.append({"type": t, "severity": sev, "kind": kind, "subject": subject, "detail": detail})
    result["changes"] = changes
    result["summary"] = {sev: sum(1 for c in changes if c["severity"] == sev) for sev in SEVERITIES}
    result["max_severity"] = next((s for s in reversed(SEVERITIES) if result["summary"][s]), None)
    return result


# --------------------------------------------------------------------------- IO

def dump_yaml(doc: dict) -> str:
    header = "# GENERATED by MxAgile security_projection.py from the Mendix model. Do not edit; regenerate instead.\n"
    return header + yaml.safe_dump(doc, sort_keys=True, default_flow_style=False, allow_unicode=True, width=10_000)


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def schema_path() -> Path | None:
    here = Path(__file__).resolve().parent
    for candidate in (here.parent / ".mxagile/schemas/security-matrix.schema.json", here.parent / "schemas/security-matrix.schema.json"):
        if candidate.is_file():
            return candidate
    return None


def validate(doc: dict) -> list[str]:
    path = schema_path()
    if path is None:
        return ["security-matrix.schema.json not found"]
    from jsonschema import Draft202012Validator
    schema = json.loads(path.read_text(encoding="utf-8"))
    return [f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}" for e in Draft202012Validator(schema).iter_errors(doc)]


def mxcli_version_of(mxcli: str) -> str | None:
    try:
        proc = subprocess.run([mxcli, "--version"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(r"v?\d+\.\d+\.\d+\S*", proc.stdout)
    return match.group(0) if match else None


def generate(project: Path, out: Path, mxcli: str, *, run: Runner | None = None, force: bool = False,
             reason: dict | None = None, now: datetime | None = None) -> tuple[dict, bool]:
    """Returns (document, written). An unchanged semantic fingerprint leaves the existing file untouched."""
    runner = run or make_mxcli_runner(mxcli, str(project))
    previous = load_yaml(out) if out.is_file() else None
    doc = assemble(extract(runner), mxcli_version=mxcli_version_of(mxcli) if run is None else None,
                   provenance=git_provenance(project.parent), reason=reason or build_reason(None, None, None),
                   previous=previous, now=now)
    if previous and not force and previous.get("generated", {}).get("fingerprint") == doc["generated"]["fingerprint"] \
            and previous.get("generated", {}).get("complete") == doc["generated"]["complete"]:
        return previous, False
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(dump_yaml(doc), encoding="utf-8", newline="\n")
    return doc, True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate")
    g.add_argument("--project", required=True, help="path to the .mpr")
    g.add_argument("--out", default=None)
    g.add_argument("--mxcli", default="mxcli")
    g.add_argument("--force", action="store_true")
    g.add_argument("--reason-type", choices=REASON_TYPES)
    g.add_argument("--reason-ref")
    g.add_argument("--reason-text")
    d = sub.add_parser("diff")
    d.add_argument("before")
    d.add_argument("after")
    d.add_argument("--json", action="store_true")
    v = sub.add_parser("validate")
    v.add_argument("file")
    args = parser.parse_args(argv)

    if args.cmd == "generate":
        project = Path(args.project).resolve()
        if not project.is_file():
            print(f"project not found: {project}", file=sys.stderr)
            return 2
        out = Path(args.out) if args.out else project.parent / DEFAULT_OUT
        try:
            reason = build_reason(args.reason_type, args.reason_ref, args.reason_text)
            doc, written = generate(project, out, args.mxcli, force=args.force, reason=reason)
        except (ExtractionError, ValueError, OSError) as exc:
            print(f"security projection failed: {exc}", file=sys.stderr)
            return 2
        errors = validate(doc)
        gen = doc["generated"]
        print(f"{'written' if written else 'unchanged (not rewritten)'}: {out}")
        print(f"complete={gen['complete']} fingerprint={gen['fingerprint']}")
        for warning in gen["warnings"]:
            print(f"WARNING: {warning}")
        for error in errors:
            print(f"SCHEMA: {error}")
        return 1 if errors else (0 if gen["complete"] else 3)
    if args.cmd == "diff":
        result = diff_snapshots(load_yaml(Path(args.before)), load_yaml(Path(args.after)))
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False))
        else:
            print(f"comparable={result['comparable']} max_severity={result.get('max_severity')}")
            for note in result["notes"]:
                print(f"NOTE: {note}")
            for change in result["changes"]:
                print(f"[{change['severity']}] {change['type']}: {change['subject']} {change['detail']}".rstrip())
        return 0
    errors = validate(load_yaml(Path(args.file)))
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
