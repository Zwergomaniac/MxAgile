"""Behavioral C1 fixtures for the opt-in mxcli runtime recipe composer."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from mxcli_runtime_recipe import resolve_runtime_recipe


def request(help_text: str, **updates):
    value = {
        "project_root": str(ROOT),
        "project_mpr": str(ROOT / "Project.mpr"),
        "binary": {"path": str(ROOT / "mxcli.exe"), "source": "PROJECT_LOCAL"},
        "version_output": "mxcli 10.24.0",
        "help_command": ["help", "run"],
        "help_output": help_text,
        "detach": True,
        "purpose": "verification",
        "operating_mode_resolution": {
            "operating_mode": {
                "mode": "CLOSED-AUTONOM",
                "detection": {"source": "fixture"},
                "tool_authority": {"status": "AUTONOMOUS_ROUTE_ELIGIBLE", "mxcli_permitted": True},
            }
        },
        "required_checks": {"readiness": ["APPLICATION_REACHABLE"], "fixture": ["seed-data-ready"], "identity": ["requested-role"], "authentication": ["demo-user-switch"]},
    }
    value.update(updates)
    return value


def project_config(**local_runtime):
    return {"runtime": {"verification": "local_first"}, "local_runtime": local_runtime}


BASE_HELP = """Usage: mxcli run --local --detach --db-type <backend> -p <project.mpr> --dbname <name>
Options:
  --local
  --detach
    --db-type <backend> Select the database backend
    hsqldb Local embedded database backend
    postgresql External database server
  -p <project.mpr>
  --dbname <name>
  --constant <name=value>
"""


class RuntimeRecipeTests(unittest.TestCase):
    def test_composes_default_db_recipe_from_c2_profile_and_help(self) -> None:
        result = resolve_runtime_recipe(request(BASE_HELP), project_config(db_type="hsqldb"))

        self.assertEqual(result["status"], "RESOLVED")
        self.assertEqual(result["recipe"]["database"], {"name": "default", "source": "MXAGILE_CORE_DEFAULT"})
        self.assertEqual(
            result["recipe"]["arguments"],
            ["run", "--local", "--detach", "--db-type", "hsqldb", "-p", str(ROOT / "Project.mpr"), "--dbname", "default"],
        )
        self.assertEqual(result["recipe"]["required_checks"]["authentication"], ["demo-user-switch"])

    def test_uses_only_db_name_spelling_advertised_by_this_help(self) -> None:
        alternate_help = BASE_HELP.replace("--dbname <name>", "--db-name <name>").replace("--dbname <name>\n", "--db-name <name>\n")

        result = resolve_runtime_recipe(request(alternate_help), project_config(db_type="hsqldb"))

        self.assertEqual(result["status"], "RESOLVED")
        self.assertIn("--db-name", result["recipe"]["arguments"])
        self.assertNotIn("--dbname", result["recipe"]["arguments"])

    def test_missing_db_identity_option_fails_closed(self) -> None:
        help_without_db_name = BASE_HELP.replace("--dbname <name>", "").replace("  --dbname <name>\n", "")

        result = resolve_runtime_recipe(request(help_without_db_name), project_config(db_type="hsqldb"))

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blockers"][0]["code"], "DB_IDENTITY_CONTROL_UNAVAILABLE")
        self.assertIsNone(result["recipe"])

    def test_conflicting_mcp_identity_blocks_mxcli_route(self) -> None:
        c2 = request(BASE_HELP)["operating_mode_resolution"]
        c2["operating_mode"]["mode"] = "AMBIGUOUS-SP-STATE"
        c2["operating_mode"]["tool_authority"]["mxcli_permitted"] = False

        result = resolve_runtime_recipe(request(BASE_HELP, operating_mode_resolution=c2), project_config(db_type="hsqldb"))

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blockers"][0]["code"], "MXCLI_ROUTE_NOT_PERMITTED")

    def test_profile_db_override_and_secret_references_are_non_secret(self) -> None:
        config = project_config(
            db_type="hsqldb",
            db_name="project_db",
            constant_overrides=[{"name": "Module.Secret", "env_key": "SECRET_KEY", "purpose": "fixture"}],
        )

        result = resolve_runtime_recipe(request(BASE_HELP), config)

        self.assertEqual(result["status"], "RESOLVED")
        self.assertEqual(result["recipe"]["database"], {"name": "project_db", "source": "PROJECT_DECLARED"})
        self.assertIn("Module.Secret=${ENV:SECRET_KEY}", result["recipe"]["arguments"])
        self.assertNotIn("secret-value", str(result))
        self.assertEqual(result["recipe"]["secret_bindings"][0]["env_key"], "SECRET_KEY")

    def test_db_type_metadata_does_not_override_a_single_supported_local_backend(self) -> None:
        result = resolve_runtime_recipe(request(BASE_HELP), project_config(db_type="postgresql"))

        self.assertEqual(result["status"], "RESOLVED")
        self.assertEqual(result["recipe"]["backend"]["type"], "hsqldb")
        self.assertEqual(result["recipe"]["project_runtime_metadata"]["declared_db_type"], "postgresql")

    def test_docker_verification_is_an_explicit_alternate_route(self) -> None:
        config = project_config(db_type="hsqldb")
        config["runtime"]["verification"] = "docker"

        result = resolve_runtime_recipe(request(BASE_HELP), config)

        self.assertEqual(result["status"], "ALTERNATE_ROUTE_REQUIRED")
        self.assertIsNone(result["recipe"])

    def test_unknown_project_verification_route_blocks_instead_of_defaulting_local(self) -> None:
        config = project_config(db_type="hsqldb")
        config["runtime"]["verification"] = "guess"

        result = resolve_runtime_recipe(request(BASE_HELP), config)

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blockers"][0]["code"], "PROJECT_VERIFICATION_ROUTE_INVALID")

    def test_malformed_local_runtime_config_blocks_instead_of_using_core_defaults(self) -> None:
        result = resolve_runtime_recipe(request(BASE_HELP), {"runtime": {"verification": "local_first"}, "local_runtime": []})

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blockers"][0]["code"], "PROJECT_LOCAL_RUNTIME_CONFIG_INVALID")

    def test_interactive_purpose_blocks_without_help_advertised_watch(self) -> None:
        result = resolve_runtime_recipe(
            request(BASE_HELP, purpose="implementation"),
            project_config(db_type="hsqldb"),
        )

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blockers"][0]["code"], "INTERACTIVE_WATCH_CONTROL_UNAVAILABLE")
        self.assertIsNone(result["recipe"])

    def test_unknown_purpose_blocks_instead_of_defaulting_to_autonomous(self) -> None:
        result = resolve_runtime_recipe(
            request(BASE_HELP, purpose="unattended_build"),
            project_config(db_type="hsqldb"),
        )

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blockers"][0]["code"], "RUNTIME_PURPOSE_INVALID")
        self.assertIsNone(result["recipe"])

    def test_multiple_local_backends_without_a_requirement_are_ambiguous(self) -> None:
        help_with_two_local = BASE_HELP + "postgresql Isolated local database backend\n"

        result = resolve_runtime_recipe(request(help_with_two_local), project_config())

        self.assertEqual(result["status"], "AMBIGUOUS")
        self.assertEqual(result["blockers"][0]["code"], "BACKEND_SELECTION_AMBIGUOUS")


if __name__ == "__main__":
    unittest.main()