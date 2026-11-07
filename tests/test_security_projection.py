"""Tests for scripts/security_projection.py.

All fixtures below are SYNTHETIC test fixtures (a fake mxcli runner returning canned JSON shaped like the
output observed from mxcli v0.20.0). They verify normalization, determinism, drift and provenance logic.
They do NOT verify mxcli behaviour; that is covered only by the opt-in reality test at the bottom
(set MXAGILE_SECURITY_REALITY_MPR to a Mendix .mpr and MXAGILE_MXCLI to mxcli; otherwise it is SKIPPED).
"""

from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import security_projection as sp  # noqa: E402

NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)


def make_runner(overrides: dict | None = None, fail: set[str] | None = None):
    """Synthetic fixture runner. `overrides` replaces canned responses by statement."""
    data = {
        "SHOW PROJECT SECURITY": [
            {"Property": "SecurityLevel", "Value": "Production"}, {"Property": "CheckSecurity", "Value": "true"},
            {"Property": "StrictMode", "Value": "false"}, {"Property": "DemoUsersEnabled", "Value": "false"},
            {"Property": "GuestAccess", "Value": "true"}, {"Property": "GuestUserRole", "Value": "Guest"},
            {"Property": "AdminUser", "Value": "MxAdmin"}],
        "SHOW USER ROLES": [
            {"Name": "CEKO", "Check Security": "Yes"}, {"Name": "E3_Aendern", "Check Security": "Yes"},
            {"Name": "Guest", "Check Security": "Yes"}],
        "DESCRIBE USER ROLE CEKO": {"mdl": "create user role CEKO (Core.CEKO, System.User);\n/"},
        "DESCRIBE USER ROLE E3_Aendern": {"mdl": "create user role E3_Aendern (Core.E3_Aendern, System.User) manage all roles;\n/"},
        "DESCRIBE USER ROLE Guest": {"mdl": "create user role Guest (Core.Guest);\n/"},
        "SHOW MODULE ROLES": [{"Qualified Name": q} for q in ("Core.E3_Aendern", "Core.CEKO", "Core.Guest", "System.User")],
        "SHOW SECURITY MATRIX": [
            {"ObjectType": "Page", "QualifiedName": "Core.Regions_Overview", "Rights": "X", "Roles": "Core.CEKO, Core.E3_Aendern"},
            {"ObjectType": "Page", "QualifiedName": "Core.Region_Edit", "Rights": "X", "Roles": "Core.E3_Aendern"},
            {"ObjectType": "Microflow", "QualifiedName": "Core.ACT_Region_Save", "Rights": "X", "Roles": "Core.E3_Aendern"},
            {"ObjectType": "Entity", "QualifiedName": "Core.Region", "Rights": "CRWD", "Roles": "ignored"}],
        "SHOW PAGES": [{"Qualified Name": q} for q in ("Core.Region_Edit", "Core.Regions_Overview", "Core.Orphan_Page")],
        "SHOW MICROFLOWS": [{"Qualified Name": q} for q in ("Core.ACT_Region_Save", "Core.ACT_Hidden")],
        "SHOW NANOFLOWS": [{"Qualified Name": "Core.NAN_Region_Validate"}],
        "SHOW ENTITIES": [{"Entity": "Core.Region", "AccessRules": 2}, {"Entity": "Core.NoRules", "AccessRules": 0}],
        "SHOW ACCESS ON Core.Region": [
            {"Roles": "Core.E3_Aendern", "Rights": "create, read, write", "DefaultMemberAccess": "ReadOnly",
             "MemberAccess": "Core.Region.Name:ReadWrite, Core.Region.Status:ReadWrite, Core.Region.Country:ReadOnly", "XPath": ""},
            {"Roles": "Core.CEKO", "Rights": "read", "DefaultMemberAccess": "None",
             "MemberAccess": "Core.Region.Name:ReadOnly, Core.Region.Status:ReadOnly, System.FileDocument.Name:ReadOnly, Core.Region.Country:None",
             "XPath": "[Organization = '[%CurrentUser%]/Organization']"}],
    }
    data.update(overrides or {})

    def run(args: list[str]) -> str:
        if args[0] == "bson":
            name = args[args.index("--object") + 1]
            if "bson" in (fail or set()):
                raise sp.ExtractionError("bson failed")
            roles = {"Core.NAN_Region_Validate": ["Core.E3_Aendern", "Core.CEKO"]}[name]
            return "WARNING: banner\n" + json.dumps([{"Key": "$Type", "Value": "Microflows$Nanoflow"},
                                                     {"Key": "AllowedModuleRoles", "Value": [1, *roles]}])
        statement = args[1]
        if statement in (fail or set()):
            raise sp.ExtractionError(f"{statement} failed")
        return "WARNING: banner\n" + json.dumps(data[statement])
    return run


def build(overrides=None, fail=None, previous=None, reason=None):
    extracted = sp.extract(make_runner(overrides, fail))
    return sp.assemble(extracted, mxcli_version="v0.0.0-test", provenance={"project_revision": "abc", "model_dirty": False, "last_model_commit": "abc"},
                       reason=reason or sp.build_reason(None, None, None), previous=previous, now=NOW)


class SchemaAndStructure(unittest.TestCase):
    def test_schema_valid_and_complete(self):
        doc = build()
        self.assertEqual(sp.validate(doc), [])
        self.assertTrue(doc["generated"]["complete"])

    def test_user_vs_module_roles_not_collapsed(self):
        roles = build()["roles"]
        self.assertEqual(roles["user_roles"]["CEKO"]["module_roles"], ["Core.CEKO", "System.User"])
        self.assertTrue(roles["user_roles"]["E3_Aendern"]["manage_all_roles"])
        self.assertIn("Core.CEKO", roles["module_roles"])

    def test_page_microflow_nanoflow_grants_and_ungranted_resources(self):
        doc = build()
        self.assertEqual(doc["pages"]["Core.Region_Edit"]["grants"], ["Core.E3_Aendern"])
        self.assertEqual(doc["pages"]["Core.Regions_Overview"]["grants"], ["Core.CEKO", "Core.E3_Aendern"])
        self.assertEqual(doc["pages"]["Core.Orphan_Page"]["grants"], [])
        self.assertEqual(doc["microflows"]["Core.ACT_Hidden"]["grants"], [])
        self.assertEqual(doc["nanoflows"]["Core.NAN_Region_Validate"]["grants"], ["Core.CEKO", "Core.E3_Aendern"])

    def test_entity_member_level_and_xpath_preserved_verbatim(self):
        rules = {tuple(r["roles"]): r for r in build()["entities"]["Core.Region"]["access_rules"]}
        ceko = rules[("Core.CEKO",)]
        self.assertEqual(ceko["read"]["members"], ["Name", "Status", "System.FileDocument.Name"])
        self.assertEqual(ceko["write"]["members"], [])
        self.assertEqual(ceko["xpath"], "[Organization = '[%CurrentUser%]/Organization']")
        self.assertFalse(ceko["create"])
        e3 = rules[("Core.E3_Aendern",)]
        self.assertEqual(e3["write"]["members"], ["Name", "Status"])
        self.assertEqual(e3["read"]["members"], "*")  # every listed member readable AND default ReadOnly
        self.assertTrue(e3["create"])
        self.assertFalse(e3["delete"])
        self.assertIsNone(e3["xpath"])
        self.assertEqual(build()["entities"]["Core.NoRules"]["access_rules"], [])

    def test_matrix_entity_rows_are_ignored_not_trusted(self):
        # CRUD letters in the matrix are lossy; entity rights come only from SHOW ACCESS.
        self.assertFalse(any("ignored" in str(r) for r in build()["entities"]["Core.Region"]["access_rules"]))


class Determinism(unittest.TestCase):
    def test_same_state_same_fingerprint_independent_of_order_and_time(self):
        a = build()
        shuffled = {"SHOW USER ROLES": list(reversed(make_runner()(["-c", "SHOW USER ROLES", "--json"]) and json.loads(make_runner()(["-c", "SHOW USER ROLES", "--json"]).split("\n", 1)[1])))}
        b = sp.assemble(sp.extract(make_runner(shuffled)), mxcli_version="x", provenance={"project_revision": "zzz", "model_dirty": True, "last_model_commit": None},
                        reason=sp.build_reason("task", "TASK-1", "t"), previous=None, now=datetime(2030, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(a["generated"]["fingerprint"], b["generated"]["fingerprint"])
        self.assertEqual(sp.semantic_body(a), sp.semantic_body(b))

    def test_yaml_output_is_byte_stable(self):
        self.assertEqual(sp.dump_yaml(build()), sp.dump_yaml(build()))

    def test_unchanged_regeneration_does_not_rewrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "m.yaml"
            project = Path(tmp) / "App.mpr"
            _, written1 = sp.generate(project, out, "mxcli", run=make_runner(), now=NOW)
            first = out.read_bytes()
            _, written2 = sp.generate(project, out, "mxcli", run=make_runner(), now=datetime(2031, 1, 1, tzinfo=timezone.utc))
            self.assertTrue(written1)
            self.assertFalse(written2)
            self.assertEqual(first, out.read_bytes())
            _, written3 = sp.generate(project, out, "mxcli", run=make_runner(), force=True, now=datetime(2031, 1, 1, tzinfo=timezone.utc))
            self.assertTrue(written3)


class IncompleteExtraction(unittest.TestCase):
    def test_failed_section_marks_incomplete_and_is_not_synthesized(self):
        doc = build(fail={"SHOW NANOFLOWS"})
        self.assertFalse(doc["generated"]["complete"])
        self.assertIsNone(doc["nanoflows"])
        self.assertIsNone(doc["effective_access"])
        self.assertEqual(doc["generated"]["sections"]["nanoflows"], "failed")
        self.assertTrue(any("nanoflows" in w for w in doc["generated"]["warnings"]))
        self.assertIn("SEC-EXTRACTION-INCOMPLETE", [f["id"] for f in doc["findings"]])
        self.assertEqual(sp.validate(doc), [])

    def test_nanoflow_bson_failure_is_incomplete(self):
        doc = build(fail={"bson"})
        self.assertIsNone(doc["nanoflows"])
        self.assertFalse(doc["generated"]["complete"])

    def test_missing_git_revision_is_null_with_warning(self):
        doc = sp.assemble(sp.extract(make_runner()), mxcli_version=None, provenance={}, reason=sp.build_reason(None, None, None), previous=None, now=NOW)
        self.assertIsNone(doc["generated"]["project_revision"])
        self.assertTrue(any("project_revision" in w for w in doc["generated"]["warnings"]))
        self.assertTrue(any("mxcli_version" in w for w in doc["generated"]["warnings"]))

    def test_incomplete_snapshots_do_not_report_failed_section_as_drift(self):
        before = build()
        after = build(fail={"SHOW NANOFLOWS"})
        drift = sp.diff_snapshots(before, after)
        self.assertFalse(drift["comparable"])
        self.assertFalse([c for c in drift["changes"] if c["kind"] == "nanoflow_grant"])


class EffectiveAccess(unittest.TestCase):
    def test_user_role_resolves_through_module_roles(self):
        eff = build()["effective_access"]
        self.assertEqual(eff["CEKO"]["pages"], ["Core.Regions_Overview"])
        self.assertEqual(eff["CEKO"]["nanoflows"], ["Core.NAN_Region_Validate"])
        self.assertEqual(eff["E3_Aendern"]["microflows"], ["Core.ACT_Region_Save"])
        self.assertEqual(eff["Guest"]["pages"], [])

    def test_entity_with_xpath_is_conditional_and_rules_are_kept(self):
        ceko = build()["effective_access"]["CEKO"]["entities"]["Core.Region"]
        self.assertEqual(ceko["summary"], {"create": "none", "delete": "none", "read": "conditional", "write": "none"})
        self.assertEqual(ceko["rules"][0]["xpath"], "[Organization = '[%CurrentUser%]/Organization']")
        self.assertEqual(ceko["rules"][0]["via_module_roles"], ["Core.CEKO"])

    def test_unconstrained_rule_beats_constrained_in_summary(self):
        doc = build()
        e3 = doc["effective_access"]["E3_Aendern"]["entities"]["Core.Region"]["summary"]
        self.assertEqual(e3, {"create": "unconditional", "delete": "none", "read": "unconditional", "write": "unconditional"})


def mutate(doc: dict, fn) -> dict:
    out = copy.deepcopy(doc)
    fn(out)
    out["generated"]["fingerprint"] = sp.fingerprint(out)
    return out


def kinds(drift: dict) -> set[str]:
    return {c["type"] for c in drift["changes"]}


class Drift(unittest.TestCase):
    def setUp(self):
        self.base = build()

    def test_no_drift_ignores_timestamps_and_provenance(self):
        later = copy.deepcopy(self.base)
        later["generated"]["generated_at"] = "2099-01-01T00:00:00Z"
        later["change_context"]["source_revision"] = "other"
        drift = sp.diff_snapshots(self.base, later)
        self.assertEqual(drift["changes"], [])
        self.assertIsNone(drift["max_severity"])

    def test_grants_and_roles(self):
        def f(d):
            d["pages"]["Core.Region_Edit"]["grants"].append("Core.CEKO")
            d["microflows"]["Core.ACT_Region_Save"]["grants"].remove("Core.E3_Aendern")
            d["nanoflows"]["Core.NAN_Region_Validate"]["grants"].append("Core.Guest")
            d["roles"]["user_roles"]["CEKO"]["module_roles"].append("Core.Guest")
            d["roles"]["user_roles"]["New"] = {"module_roles": [], "manage_all_roles": False, "check_security": True}
            d["roles"]["module_roles"].append("Core.New")
        t = kinds(sp.diff_snapshots(self.base, mutate(self.base, f)))
        self.assertEqual(t, {"page_view_added", "microflow_execute_removed", "nanoflow_execute_added",
                             "role_mapping_added", "user_role_added", "module_role_added"})

    def test_entity_changes_and_severity(self):
        def f(d):
            for rule in d["entities"]["Core.Region"]["access_rules"]:
                if rule["roles"] == ["Core.CEKO"]:
                    rule["delete"] = True
                    rule["write"]["members"] = ["Name"]
                    rule["read"]["members"].append("Extra")
                    rule["xpath"] = None
        drift = sp.diff_snapshots(self.base, mutate(self.base, f))
        t = kinds(drift)
        self.assertIn("entity_delete_added", t)
        self.assertIn("entity_write_member_added", t)
        self.assertIn("entity_read_member_added", t)
        self.assertIn("entity_xpath_removed", t)
        by_type = {c["type"]: c["severity"] for c in drift["changes"]}
        self.assertEqual(by_type["entity_delete_added"], "high_impact")
        self.assertEqual(by_type["entity_xpath_removed"], "high_impact")
        self.assertEqual(drift["max_severity"], "high_impact")

    def test_xpath_text_change_is_changed_not_broadened(self):
        def f(d):
            for rule in d["entities"]["Core.Region"]["access_rules"]:
                if rule["xpath"]:
                    rule["xpath"] = "[Organization != empty]"
        drift = sp.diff_snapshots(self.base, mutate(self.base, f))
        self.assertEqual(kinds(drift), {"entity_xpath_changed"})
        self.assertEqual(drift["changes"][0]["severity"], "security_relevant")

    def test_production_to_prototype_is_critical_and_guest_change_detected(self):
        def f(d):
            d["security"]["level"] = "PROTOTYPE"
            d["security"]["guest_access"] = False
        drift = sp.diff_snapshots(self.base, mutate(self.base, f))
        by_type = {c["type"]: c["severity"] for c in drift["changes"]}
        self.assertEqual(by_type["security_level_changed"], "critical")
        self.assertIn("guest_security_changed", by_type)
        self.assertEqual(drift["max_severity"], "critical")

    def test_diff_is_deterministic(self):
        def f(d):
            d["pages"]["Core.Region_Edit"]["grants"].append("Core.CEKO")
        after = mutate(self.base, f)
        self.assertEqual(json.dumps(sp.diff_snapshots(self.base, after), sort_keys=True), json.dumps(sp.diff_snapshots(self.base, after), sort_keys=True))

    def test_embedded_drift_in_regeneration(self):
        changed = build(overrides={"SHOW PROJECT SECURITY": [{"Property": "SecurityLevel", "Value": "Off"}]}, previous=self.base)
        self.assertEqual(changed["drift"]["max_severity"], "critical")
        self.assertEqual(changed["change_context"]["previous_fingerprint"], self.base["generated"]["fingerprint"])


class FindingsAndReason(unittest.TestCase):
    def test_conservative_findings(self):
        ids = [f["id"] for f in build()["findings"]]
        self.assertIn("SEC-GUEST-ACCESS-ENABLED", ids)
        self.assertNotIn("SEC-LEVEL-NOT-PRODUCTION", ids)
        off = build(overrides={"SHOW PROJECT SECURITY": [{"Property": "SecurityLevel", "Value": "Off"}]})
        self.assertIn("SEC-LEVEL-NOT-PRODUCTION", [f["id"] for f in off["findings"]])

    def test_reason_defaults_to_unknown_and_is_never_inferred(self):
        reason = build()["change_context"]["reason"]
        self.assertEqual(reason, {"type": "unknown", "reference": None, "text": None})

    def test_explicit_reason_requires_reference(self):
        self.assertEqual(sp.build_reason("requirement", "REQ-014", "why")["reference"], "REQ-014")
        with self.assertRaises(ValueError):
            sp.build_reason("requirement", None, "no ref")
        with self.assertRaises(ValueError):
            sp.build_reason("hardening", "X", None)

    def test_schema_rejects_unknown_reason_with_text(self):
        doc = build()
        doc["change_context"]["reason"] = {"type": "unknown", "reference": None, "text": "security hardening"}
        self.assertTrue(sp.validate(doc))


@unittest.skipUnless(os.environ.get("MXAGILE_SECURITY_REALITY_MPR") and os.environ.get("MXAGILE_MXCLI"),
                     "SKIPPED (not PASS): set MXAGILE_SECURITY_REALITY_MPR and MXAGILE_MXCLI for the real-mxcli check")
class RealMxcli(unittest.TestCase):
    def test_real_extraction_is_complete_schema_valid_and_deterministic(self):
        mpr, mxcli = os.environ["MXAGILE_SECURITY_REALITY_MPR"], os.environ["MXAGILE_MXCLI"]
        run = sp.make_mxcli_runner(mxcli, mpr)
        first = sp.assemble(sp.extract(run), mxcli_version=sp.mxcli_version_of(mxcli), provenance={}, reason=sp.build_reason(None, None, None), previous=None)
        second = sp.assemble(sp.extract(run), mxcli_version=None, provenance={}, reason=sp.build_reason(None, None, None), previous=None)
        self.assertEqual(sp.validate(first), [])
        self.assertTrue(first["generated"]["complete"], first["generated"]["warnings"])
        self.assertEqual(first["generated"]["fingerprint"], second["generated"]["fingerprint"])


if __name__ == "__main__":
    unittest.main()
