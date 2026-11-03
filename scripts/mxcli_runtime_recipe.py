"""Compose a complete mxcli runtime recipe from current binary-help evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

import yaml


KNOWN_BACKENDS = ("hsqldb", "postgresql", "sqlserver")
OPTION_PATTERN = re.compile(r"(?<![\w-])(--[a-z][a-z0-9-]*|-[a-z])(?=\s|=|<|>|,|\[|\]|$)", re.IGNORECASE)


def _base_result(request: dict[str, Any]) -> dict[str, Any]:
    operating_mode = request.get("operating_mode_resolution") or {}
    mode_result = operating_mode.get("operating_mode", operating_mode)
    authority = mode_result.get("tool_authority", {}) if isinstance(mode_result, dict) else {}
    raw_binary = request.get("binary", {})
    binary = raw_binary if isinstance(raw_binary, dict) else {}
    raw_help = request.get("help_output", "")
    help_text = raw_help if isinstance(raw_help, str) else ""
    return {
        "schema_version": 1,
        "status": "BLOCKED",
        "blockers": [],
        "route": {
            "operating_mode": mode_result.get("mode") if isinstance(mode_result, dict) else None,
            "operating_mode_source": (mode_result.get("detection") or {}).get("source") if isinstance(mode_result, dict) else None,
            "permitted_tool": "mxcli" if authority.get("mxcli_permitted") is True else None,
            "authority_status": authority.get("status"),
        },
        "capability_evidence": {
            "executable_path": binary.get("path"),
            "resolution_source": binary.get("source"),
            "version": request.get("version_output") if isinstance(request.get("version_output"), str) else None,
            "help_command": request.get("help_command", ["help", "run"]),
            "help_sha256": "sha256:" + hashlib.sha256(help_text.encode("utf-8")).hexdigest(),
            "advertised_options": sorted(set(OPTION_PATTERN.findall(help_text))),
        },
        "recipe": None,
    }


def _block(result: dict[str, Any], code: str, reason: str, status: str = "BLOCKED") -> dict[str, Any]:
    result["status"] = status
    result["blockers"].append({"code": code, "reason": reason})
    return result


def _get_c2(request: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    resolution = request.get("operating_mode_resolution")
    if not isinstance(resolution, dict):
        return {}, {}
    mode_result = resolution.get("operating_mode", resolution)
    if not isinstance(mode_result, dict):
        return {}, {}
    authority = mode_result.get("tool_authority")
    return mode_result, authority if isinstance(authority, dict) else {}


def _local_backends(help_text: str, options: set[str]) -> set[str]:
    if "--db-type" not in options:
        return set()
    candidates = {name for name in KNOWN_BACKENDS if re.search(rf"\b{re.escape(name)}\b", help_text, re.IGNORECASE)}
    local = set()
    for backend in candidates:
        backend_lines = []
        for line in help_text.splitlines():
            if not re.search(rf"\b{re.escape(backend)}\b", line, re.IGNORECASE):
                continue
            names_on_line = {name for name in KNOWN_BACKENDS if re.search(rf"\b{re.escape(name)}\b", line, re.IGNORECASE)}
            if names_on_line == {backend}:
                backend_lines.append(line)
        if any(re.search(r"\b(local|embedded|isolated)\b", line, re.IGNORECASE) for line in backend_lines):
            local.add(backend)
    return local


def _one_flag(options: set[str], choices: tuple[str, ...], label: str) -> tuple[str | None, str | None]:
    present = [choice for choice in choices if choice in options]
    if len(present) == 1:
        return present[0], None
    if len(present) > 1:
        return None, f"Multiple advertised spellings for {label}: {', '.join(present)}."
    return None, f"The selected binary help does not advertise an option for {label}."


def _project_path(project_root: Path, value: str) -> Path:
    candidate = Path(value)
    resolved = candidate.resolve() if candidate.is_absolute() else (project_root / candidate).resolve()
    resolved.relative_to(project_root.resolve())
    return resolved


def resolve_runtime_recipe(request: dict[str, Any], project_config: dict[str, Any]) -> dict[str, Any]:
    """Return a fail-closed recipe decision. This function never launches mxcli."""
    if not isinstance(request, dict) or not isinstance(project_config, dict):
        safe_request = request if isinstance(request, dict) else {}
        return _block(_base_result(safe_request), "RECIPE_INPUT_INVALID", "Runtime request and project configuration must be objects.")
    result = _base_result(request)
    mode_result, authority = _get_c2(request)
    mode = mode_result.get("mode")
    if not mode:
        return _block(result, "OPERATING_MODE_UNOBSERVED", "A current C2 operating-mode result is required.", "AMBIGUOUS")
    if authority.get("mxcli_permitted") is not True:
        return _block(result, "MXCLI_ROUTE_NOT_PERMITTED", "The current C2 tool-authority result does not permit mxcli.", "BLOCKED")
    if mode not in {"CLOSED-AUTONOM", "LIVE-SP-OTHER"}:
        return _block(result, "OPERATING_MODE_CONFLICT", f"Mode {mode} does not permit an mxcli runtime recipe.", "AMBIGUOUS")

    binary = request.get("binary")
    if not isinstance(binary, dict) or not isinstance(binary.get("path"), str) or not isinstance(binary.get("source"), str) or not binary.get("path") or not binary.get("source"):
        return _block(result, "MXCLI_BINARY_UNRESOLVED", "The canonical binary resolver did not provide an absolute path and source.")
    version = request.get("version_output")
    if not isinstance(version, str) or not version.strip():
        return _block(result, "MXCLI_VERSION_UNOBSERVED", "The selected binary did not provide a version.")
    help_text = request.get("help_output")
    if not isinstance(help_text, str) or not help_text.strip():
        return _block(result, "MXCLI_RUN_HELP_UNAVAILABLE", "The selected binary did not provide command-specific run help.")

    runtime_value = project_config.get("runtime", {})
    if not isinstance(runtime_value, dict):
        return _block(result, "PROJECT_RUNTIME_CONFIG_INVALID", "Project runtime configuration must be an object.")
    runtime = runtime_value
    verification_route = runtime.get("verification", "local_first")
    if verification_route not in {"local_first", "docker"}:
        return _block(result, "PROJECT_VERIFICATION_ROUTE_INVALID", "Project runtime.verification must be local_first or docker.")
    if verification_route == "docker":
        result["route"]["permitted_tool"] = "docker"
        return _block(result, "PROJECT_REQUIRES_DOCKER_ROUTE", "Project runtime.verification selects Docker; no mxcli local recipe was composed.", "ALTERNATE_ROUTE_REQUIRED")
    project_mpr_value = request.get("project_mpr")
    if not isinstance(project_mpr_value, str) or not project_mpr_value.strip():
        return _block(result, "PROJECT_MPR_UNRESOLVED", "A concrete project .mpr path is required.")
    project_root = Path(request.get("project_root", ".")).resolve()
    try:
        project_mpr = _project_path(project_root, project_mpr_value)
    except (OSError, ValueError):
        return _block(result, "PROJECT_MPR_OUTSIDE_ROOT", "The selected .mpr path must remain inside the project root.")

    options = set(OPTION_PATTERN.findall(help_text))
    for required in ("run", "--local"):
        if required == "run":
            if not re.search(r"(?i)\b(run)\b", help_text):
                return _block(result, "RUN_COMMAND_UNAVAILABLE", "The selected binary help does not advertise the run command.")
        elif required not in options:
            return _block(result, "LOCAL_RUN_UNAVAILABLE", "The selected binary help does not advertise --local.")

    requested_backend = request.get("requested_backend")
    if requested_backend is not None and (not isinstance(requested_backend, str) or not requested_backend.strip()):
        return _block(result, "REQUESTED_BACKEND_INVALID", "The requested verification backend must be a non-empty string.")
    local_runtime_value = project_config.get("local_runtime", {})
    if not isinstance(local_runtime_value, dict):
        return _block(result, "PROJECT_LOCAL_RUNTIME_CONFIG_INVALID", "Project local_runtime configuration must be an object.")
    local_runtime = local_runtime_value
    profile_backend = local_runtime.get("db_type")
    backend_options = _local_backends(help_text, options)
    if requested_backend:
        if requested_backend not in backend_options:
            return _block(result, "REQUESTED_BACKEND_UNAVAILABLE", f"Requested backend {requested_backend} is not advertised as a local backend by this binary.")
        selected_backend = requested_backend
        backend_source = "VERIFICATION_REQUIREMENT"
    elif len(backend_options) == 1:
        selected_backend = next(iter(backend_options))
        backend_source = "ONLY_ADVERTISED_LOCAL_BACKEND"
    elif not backend_options:
        return _block(result, "LOCAL_RUNTIME_CAPABILITY_UNAVAILABLE", "No isolated/local backend was established from the selected binary help.")
    else:
        return _block(result, "BACKEND_SELECTION_AMBIGUOUS", "Multiple local backends are advertised and the verification contract did not select one.", "AMBIGUOUS")

    project_flag, project_error = _one_flag(options, ("-p", "--project"), "project path")
    if project_error:
        return _block(result, "PROJECT_ARGUMENT_UNAVAILABLE", project_error)
    db_name_flag, db_name_error = _one_flag(options, ("--db-name", "--dbname"), "database identity")
    if db_name_error:
        return _block(result, "DB_IDENTITY_CONTROL_UNAVAILABLE", db_name_error)
    backend_flag, backend_error = _one_flag(options, ("--db-type", "--dbtype"), "database backend")
    if backend_error:
        return _block(result, "BACKEND_ARGUMENT_UNAVAILABLE", backend_error)

    purpose = request.get("purpose", "verification")
    if purpose not in {"verification", "implementation", "development"}:
        return _block(result, "RUNTIME_PURPOSE_INVALID", "The requested runtime purpose is not recognized.")
    runtime_mode = "interactive" if purpose in {"implementation", "development"} else "autonomous"
    arguments = ["run", "--local"]
    if runtime_mode == "autonomous":
        if request.get("detach") is True:
            if "--detach" not in options:
                return _block(result, "DETACH_CONTROL_UNAVAILABLE", "The requested detached runtime is not advertised by the selected binary.")
            arguments.append("--detach")
    else:
        if "--watch" not in options:
            return _block(result, "INTERACTIVE_WATCH_CONTROL_UNAVAILABLE", "The selected binary help does not advertise --watch for the requested interactive runtime.")
        arguments.append("--watch")
    arguments.extend([backend_flag, selected_backend, project_flag, str(project_mpr)])

    db_name_override = request.get("db_name_override")
    if db_name_override:
        db_name, db_name_source = db_name_override, "SESSION_OVERRIDE"
    elif local_runtime.get("db_name"):
        db_name, db_name_source = local_runtime["db_name"], "PROJECT_DECLARED"
    else:
        db_name, db_name_source = "default", "MXAGILE_CORE_DEFAULT"
    arguments.extend([db_name_flag, str(db_name)])

    session_overrides = request.get("runtime_overrides") if isinstance(request.get("runtime_overrides"), dict) else {}
    app_port = session_overrides.get("app_port", local_runtime.get("app_port", 8080))
    if "app_port" in session_overrides or "app_port" in local_runtime:
        port_flag, port_error = _one_flag(options, ("--app-port", "--port"), "application port")
        if port_error:
            return _block(result, "APP_PORT_CONTROL_UNAVAILABLE", port_error)
        arguments.extend([port_flag, str(app_port)])

    for config_key, option_names, label in (
        ("db_host", ("--db-host", "--dbhost"), "database host"),
        ("db_port", ("--db-port", "--dbport"), "database port"),
    ):
        if config_key in session_overrides or config_key in local_runtime:
            flag, flag_error = _one_flag(options, option_names, label)
            if flag_error:
                return _block(result, f"{config_key.upper()}_CONTROL_UNAVAILABLE", flag_error)
            arguments.extend([flag, str(session_overrides.get(config_key, local_runtime.get(config_key)))])

    constant_overrides = session_overrides.get("constant_overrides", local_runtime.get("constant_overrides", []))
    secret_bindings: list[dict[str, Any]] = []
    if constant_overrides:
        if "--constant" not in options:
            return _block(result, "CONSTANT_CONTROL_UNAVAILABLE", "Project runtime constants exist but the selected binary help does not advertise --constant.")
        for override in constant_overrides:
            if not isinstance(override, dict) or not isinstance(override.get("name"), str):
                return _block(result, "RUNTIME_CONSTANT_INVALID", "A runtime constant override is missing its name.")
            if isinstance(override.get("env_key"), str):
                value = "${ENV:" + override["env_key"] + "}"
                secret_bindings.append({"constant": override["name"], "env_key": override["env_key"], "argument_value": value})
            elif isinstance(override.get("value"), str):
                value = override["value"]
            else:
                return _block(result, "RUNTIME_CONSTANT_VALUE_UNRESOLVED", f"Constant {override['name']} has no value or secret reference.")
            arguments.extend(["--constant", f"{override['name']}={value}"])

    app_url = session_overrides.get("app_url", local_runtime.get("app_url", f"http://localhost:{app_port}"))
    recipe = {
        "purpose": purpose,
        "runtime_mode": runtime_mode,
        "operating_mode": mode,
        "tool_authority": authority,
        "executable": str(Path(binary["path"]).resolve()),
        "executable_source": binary["source"],
        "binary_version": version.strip(),
        "capability_evidence": result["capability_evidence"],
        "project_root": str(project_root),
        "project_mpr": str(project_mpr),
        "route": "mxcli_local",
        "backend": {"class": "LOCAL_ISOLATED", "type": selected_backend, "source": backend_source},
        "project_runtime_metadata": {"declared_db_type": profile_backend},
        "database": {"name": str(db_name), "source": db_name_source},
        "arguments": arguments,
        "expected": {"backend": selected_backend, "database_name": str(db_name), "app_url": app_url, "app_port": app_port},
        "credential_references": {
            key: local_runtime[key] for key in ("db_user_env_key", "db_password_env_key", "admin_username_env_key", "admin_password_env_key")
            if isinstance(local_runtime.get(key), str)
        },
        "secret_bindings": secret_bindings,
        "required_checks": request.get("required_checks", {"readiness": ["APPLICATION_REACHABLE"]}),
    }
    result["status"] = "RESOLVED"
    result["recipe"] = recipe
    return result


def resolve_request(request: dict[str, Any]) -> dict[str, Any]:
    project_root = Path(request.get("project_root", ".")).resolve()
    config_path = project_root / "mxagile-project.yaml"
    if config_path.is_file():
        try:
            project_config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as exc:
            result = _base_result(request)
            return _block(result, "PROJECT_RUNTIME_CONFIG_INVALID", f"Project runtime profile could not be parsed: {type(exc).__name__}.")
    else:
        project_config = {}
    if not isinstance(project_config, dict):
        result = _base_result(request)
        return _block(result, "PROJECT_RUNTIME_CONFIG_INVALID", "Project configuration root must be a mapping.")
    return resolve_runtime_recipe(request, project_config)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request-file", type=Path, required=True, help="Ephemeral JSON request from Resolve-MxAgileMxcli.ps1.")
    args = parser.parse_args()
    try:
        request = json.loads(args.request_file.read_text(encoding="utf-8-sig"))
        if not isinstance(request, dict):
            raise ValueError("request root must be an object")
        print(json.dumps(resolve_request(request), ensure_ascii=False))
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(json.dumps({"schema_version": 1, "status": "BLOCKED", "blockers": [{"code": "REQUEST_INVALID", "reason": type(exc).__name__}], "recipe": None}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())