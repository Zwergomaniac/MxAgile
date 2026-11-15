"""Focused D/E/H contract regressions; fixtures remain inside the repository."""

import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from jsonschema import Draft7Validator
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import resolve_impact
import project_compatibility
import create_revision
import build_artifact_index
import graph_capability


def validator(name):
    schema = json.loads((ROOT / ".mxagile/schemas" / name).read_text(encoding="utf-8-sig"))
    Draft7Validator.check_schema(schema)
    return Draft7Validator(schema)


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix="lifecycle-reality-", dir=ROOT / "tests")
        self.root = Path(self.fixture.name)
        self.addCleanup(self.fixture.cleanup)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(content), encoding="utf-8")


class OwnedSchemaTests(unittest.TestCase):
    def test_requirement_retirement_and_traceability(self):
        check = validator("requirement.schema.json")
        base = {"ID": "REQ-001", "title": "Historical intent", "description": "Preserved history"}
        for status, fields in (
            ("obsolete", {}), ("retired", {}), ("invalid", {}),
            ("split", {"replacement_ids": ["REQ-002", "REQ-003"]}),
            ("merged", {"merged_into": "REQ-002"}),
            ("duplicate", {"superseded_by": "REQ-002"}),
            ("superseded", {}),
            ("ambiguous", {"open_items": ["Historical conflict"]}),
        ):
            with self.subTest(valid=status):
                self.assertTrue(check.is_valid({**base, "status": status, **fields}))
        for fields in (
            {"status": "split"}, {"status": "split", "replacement_ids": ["REQ-002"]},
            {"status": "merged"}, {"status": "duplicate"},
            {"status": "obsolete", "superseded_by": "REQ-002"},
            {"status": "retired", "replacement_ids": ["REQ-002", "REQ-003"]},
            {"status": "invalid", "merged_into": "REQ-002"},
            {"status": "accepted", "open_items": ["Unconfirmed assumption"]},
        ):
            with self.subTest(invalid=fields):
                self.assertFalse(check.is_valid({**base, **fields}))

    def test_revision_readiness_does_not_authorize_active_target(self):
        check = validator("revision.schema.json")
        base = {
            "revision_id": "REV-002", "mockup_name": "demo", "created_at": "2026-11-15",
            "entry_point": "index.html", "bundle_hash": "sha256:" + "a" * 64,
            "lifecycle_trigger": "refinement_accepted", "change_classification": "material",
            "impact_scope": "targeted", "affected_screens": ["PAGE-EDIT"],
            "lifecycle_status": "REFINED_TARGET", "refinement_status": "ACCEPTED",
            "active_target": True, "acceptance_decisions": ["DEC-001"],
        }
        self.assertTrue(check.is_valid(base))
        for fields in (
            {"refinement_status": "PROPOSED"}, {"refinement_status": "REJECTED"},
            {"lifecycle_status": "SUPERSEDED_TARGET"}, {"acceptance_decisions": []},
            {"affected_screens": []},
        ):
            with self.subTest(fields=fields):
                self.assertFalse(check.is_valid({**base, **fields}))
        for missing in ("acceptance_decisions", "affected_screens"):
            doc = copy.deepcopy(base)
            del doc[missing]
            self.assertFalse(check.is_valid(doc))
        self.assertTrue(check.is_valid({**base, "active_target": False, "lifecycle_status": "SUPERSEDED_TARGET"}))

    def test_calculation_requires_semantic_baseline_and_build_evidence(self):
        check = validator("test-contract.schema.json")
        pp = {"id": "PP-001", "claim": "Expected signed balance", "role": "ANY_AUTHENTICATED",
              "data_state": "populated", "semantic_kind": "CALCULATION", "required_layers": ["MODEL", "BUILD"]}
        doc = {"schema_version": 2, "ID": "TC-001", "title": "Calculation", "status": "draft",
               "requirement_ids": ["REQ-001"], "proof_points": [pp]}
        self.assertFalse(check.is_valid(doc))
        pp["calculation_baseline"] = {
            key: "Declared basis" for key in ("metric_definition", "canonical_source", "time_basis",
                                             "opening_balance", "movement_logic", "sign_convention", "aggregation", "scope")
        }
        pp["calculation_baseline"]["example"] = {
            "opening_balance": "10", "movements": ["-2"], "expected_balance": "8",
            "expected_delta": "-2", "expected_sign": "negative", "role_scope": "Declared scope",
        }
        self.assertTrue(check.is_valid(doc))
        pp["required_layers"] = ["MODEL"]
        self.assertFalse(check.is_valid(doc))


class OwnedResolverTests(FixtureTests):
    def test_builder_and_consumers_share_exclusions_and_detect_real_source_edits(self):
        self.write("planning/ui-inventory/PAGE-EDIT.yaml", {"page_id": "PAGE-EDIT"})
        self.write("planning/ui-inventory/interaction-states-demo.yaml", {"states": ["expanded"]})
        self.write("planning/test-contracts/impact-REV-001.yaml", {"analysis": "not a test contract"})
        built = build_artifact_index.compute_source_fingerprint(build_artifact_index.find_artifacts(self.root))
        self.assertEqual(resolve_impact._compute_current_fingerprint(self.root), built)
        self.assertEqual(graph_capability.KnowledgeGraph(self.root)._compute_current_fingerprint(), built)
        self.write("planning/ui-inventory/PAGE-EDIT.yaml", {"page_id": "PAGE-EDIT", "title": "Changed"})
        changed = build_artifact_index.compute_source_fingerprint(build_artifact_index.find_artifacts(self.root))
        self.assertNotEqual(changed, built)
        self.assertEqual(resolve_impact._compute_current_fingerprint(self.root), changed)

    def test_stale_index_rebuild_failure_uses_current_canonical_candidates(self):
        self.write("requirements/REQ-002.yml", {"ID": "REQ-002", "screens": ["PAGE-EDIT"]})
        index = {"source_fingerprint": "sha256:" + "0" * 64,
                 "nodes": [{"id": "REQ-001", "type": "requirement"}],
                 "edges": [{"from": "REQ-001", "to": "PAGE-EDIT", "type": "APPLIES_TO"}]}
        path = self.root / ".mxagile/state/artifact-index.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(index), encoding="utf-8")
        before = path.read_bytes()
        with patch.object(resolve_impact, "_try_rebuild", return_value=False):
            result = resolve_impact.resolve(self.root, "PAGE-EDIT")
        self.assertEqual(result["source"], "direct_canonical_traversal")
        self.assertEqual(result["all_requirements"], ["REQ-002"])
        self.assertEqual(path.read_bytes(), before)

    def test_successful_rebuild_must_prove_freshness_before_index_reuse(self):
        path = self.root / ".mxagile/state/artifact-index.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"source_fingerprint": "sha256:" + "0" * 64, "nodes": [], "edges": []}), encoding="utf-8")
        self.write("requirements/REQ-002.yml", {"ID": "REQ-002", "screens": ["PAGE-EDIT"]})
        with patch.object(resolve_impact, "_try_rebuild", return_value=True):
            result = resolve_impact.resolve(self.root, "PAGE-EDIT")
        self.assertEqual(result["source"], "direct_canonical_traversal")
        self.assertEqual(result["all_requirements"], ["REQ-002"])

    def test_unfingerprinted_index_is_not_verified_authority(self):
        path = self.root / ".mxagile/state/artifact-index.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"nodes": [], "edges": []}), encoding="utf-8")
        self.write("requirements/REQ-002.yml", {"ID": "REQ-002", "screens": ["PAGE-EDIT"]})
        with patch.object(resolve_impact, "_try_rebuild", return_value=False):
            result = resolve_impact.resolve(self.root, "PAGE-EDIT")
        self.assertEqual(result["all_requirements"], ["REQ-002"])


class MainOwnedReconciliationTests(FixtureTests):
    """Read-only source reconciliation and scoped accepted-target binding."""

    def decision(self, status="CONFIRMED"):
        self.write("planning/decisions/DEC-001.yml", {
            "ID": "DEC-001", "title": "Accept target", "status": status,
            "decision_type": "mockup_refinement", "topic": "Demo target",
            "decision_text": "Accept the specified target", "owner": "ProductOwner",
        })

    def revision(self, **extra):
        self.decision()
        doc = {"revision_id": "REV-002", "revision": 2, "mockup_name": "demo",
               "active_target": True, "refinement_status": "ACCEPTED", "lifecycle_status": "REFINED_TARGET",
               "acceptance_decisions": ["DEC-001"], "impact_scope": "targeted",
               "affected_screens": ["PAGE-EDIT"], "artifact_path": "input-resources/ui-ux/demo.html"}
        self.write("planning/revisions/REV-002.yaml", {**doc, **extra})

    def source(self, revision=2, mockup="demo", previous=None, **extra):
        path = self.root / "input-resources/ui-ux/demo/index.html"
        path.parent.mkdir(parents=True, exist_ok=True)
        spec = {"schema_version": 1, "mockup": {"id": mockup, "revision": revision},
                "roles": [], "requirements": [],
                "assessment": {"development_handoff_readiness": "HANDOFF_READY"}, **extra}
        if previous is not None:
            spec["mockup"]["previous_revision"] = previous
        path.write_text('<script type="application/json" id="mocketeer-spec">' +
                        json.dumps(spec) + '</script>', encoding="utf-8")
        return path

    def page(self, name, **extra):
        self.write(f"planning/ui-inventory/{name}.yaml", {
            "page_id": name, "mockup_name": "demo", "target_revision": "REV-001", **extra})

    def test_source_identity_is_not_the_bundle_namespace(self):
        source = self.source(mockup="source-demo")
        self.revision(mockup_id="source-demo", artifact_path=source.relative_to(self.root).as_posix(),
                      artifact_hash=project_compatibility.digest(source.read_bytes()))
        self.page("PAGE-EDIT", mockup_id="source-demo", target_revision="REV-002")
        observed = project_compatibility.evaluate_mocketeer_reconciliation(self.root)
        self.assertEqual(len(observed["reconciled"]), 1)
        self.assertEqual(project_compatibility.reconcile_page_revision_bindings(self.root)["state"], "BOUND")

    def test_archived_source_revision_is_independent_of_snapshot_counter(self):
        self.decision()
        source = self.source(revision=38, mockup="upstream-design", previous=37)
        entry = self.root / "planning/target-mockups/demo/index.html"
        entry.parent.mkdir(parents=True)
        entry.write_bytes(source.read_bytes())
        create_revision.create_revision(self.root, "demo", "DEC-001")
        observed = project_compatibility.evaluate_mocketeer_reconciliation(self.root)
        self.assertEqual(len(observed["reconciled"]), 1)
        self.assertEqual(observed["reconciled"][0]["revision"], 38)
        self.assertEqual(observed["reconciled"][0]["revision_path"].split("/")[-2], "REV-001")

    def test_same_source_path_new_revision_requires_reconciliation(self):
        self.revision()
        path = self.root / "input-resources/ui-ux/demo.html"
        path.parent.mkdir(parents=True)
        path.write_text('<script type="application/json" id="mocketeer-spec">' + json.dumps({
            "schema_version": 1, "mockup": {"id": "demo", "revision": 3, "previous_revision": 2},
            "roles": [], "requirements": [],
            "assessment": {"development_handoff_readiness": "HANDOFF_READY"},
        }) + '</script>', encoding="utf-8")
        result = project_compatibility.evaluate_mocketeer_reconciliation(self.root)
        self.assertTrue(result["reconciliation_required"])

    def test_active_candidate_requires_unique_target_and_confirmed_acceptance(self):
        self.revision()
        self.page("PAGE-EDIT")
        candidate = yaml.safe_load((self.root / "planning/revisions/REV-002.yaml").read_text(encoding="utf-8"))
        candidate.update(revision_id="REV-003", revision=3, previous_revision=2)
        path = "planning/revisions/REV-003.yaml"
        check = lambda doc: project_compatibility.prevalidate_canonical_write(self.root, path, yaml.safe_dump(doc).encode())
        self.assertFalse(check(candidate)["valid"], "A second active target was authorized")
        self.assertTrue(check({**candidate, "mockup_name": "unrelated"})["valid"])
        self.assertFalse(check({**candidate, "active_target": False, "acceptance_decisions": []})["valid"])
        self.assertFalse(check({**candidate, "mockup_name": " "})["valid"])
        if os.name == "nt":
            self.assertFalse(check({**candidate, "mockup_name": "DEMO"})["valid"], "A namespace case alias bypassed uniqueness")
        self.decision("PROPOSED")
        self.assertFalse(check({**candidate, "active_target": False})["valid"], "A proposal became accepted authority")
        self.assertTrue(check({**candidate, "active_target": False, "refinement_status": "PROPOSED"})["valid"])

    def test_delivery_preflight_projects_bindings_per_namespace_without_mutation(self):
        self.revision()
        self.page("PAGE-EDIT", target_revision="REV-002")
        other = yaml.safe_load((self.root / "planning/revisions/REV-002.yaml").read_text())
        other.update(revision_id="REV-003", revision=3, mockup_name="other", affected_screens=["PAGE-OTHER"])
        self.write("planning/revisions/REV-003.yaml", other)
        self.page("PAGE-OTHER", mockup_name="other", target_revision="REV-002")
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        result = project_compatibility.delivery_preflight(self.root)
        bindings = result["mocketeer_reconciliation"]["page_bindings"]
        self.assertEqual({binding["mockup_id"]: binding["state"] for binding in bindings},
                         {"demo": "BOUND", "other": "ACTIVE_REVISION_UNBOUND"})
        self.assertIn("ACTIVE_REVISION_PAGE_BINDING_UNRECONCILED", result["warning_codes"])
        self.assertTrue(all(binding["retention_requires_existing_valid_evidence"] for binding in bindings))
        self.assertEqual(before, {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()})

    def test_doctor_does_not_treat_old_revision_shared_source_path_as_current_binding(self):
        self.revision()
        self.page("PAGE-EDIT", source_mockup="input-resources/ui-ux/demo.html")
        parsed = {"planning/ui-inventory/PAGE-EDIT.yaml": {"state": "available", "value": yaml.safe_load(
            (self.root / "planning/ui-inventory/PAGE-EDIT.yaml").read_text(encoding="utf-8"))}}
        found = []
        project_compatibility._active_revision_diagnostics(self.root, parsed, lambda *args, **kwargs: found.append(args[0]))
        self.assertIn("ACTIVE_REVISION_UNBOUND", found)

    def test_source_path_alone_does_not_bind_impacted_page_to_new_revision(self):
        self.revision()
        self.page("PAGE-EDIT", source_mockup="input-resources/ui-ux/demo.html")
        result = project_compatibility.reconcile_page_revision_bindings(self.root)
        self.assertFalse(result["impacted_pages"][0]["bound_to_active"])

    def test_unknown_impact_does_not_prove_unchanged_evidence(self):
        self.revision(impact_scope="unknown", affected_screens=[])
        self.page("PAGE-EDIT")
        result = project_compatibility.reconcile_page_revision_bindings(self.root)
        self.assertFalse(any(page["evidence_disposition"] == "RETAIN_VALID_EVIDENCE"
                             for page in result["unchanged_pages"]))

    def test_partial_binding_does_not_report_bound_affected_scope(self):
        self.revision(affected_screens=["PAGE-EDIT", "PAGE-LIST"])
        self.page("PAGE-EDIT", target_revision="REV-002")
        self.page("PAGE-LIST")
        result = project_compatibility.reconcile_page_revision_bindings(self.root)
        self.assertNotEqual(result["state"], "BOUND")

    def test_nested_source_exact_identity_and_fingerprint_are_reconciled(self):
        source = self.source(consumer_readiness={"runtime_verified": True})
        self.revision(artifact_path=source.relative_to(self.root).as_posix(),
                      artifact_hash=project_compatibility.digest(source.read_bytes()))
        result = project_compatibility.evaluate_mocketeer_reconciliation(self.root)
        self.assertFalse(result["reconciliation_required"])
        dimensions = result["reconciled"][0]["dimensions"]
        self.assertTrue(dimensions["project_active_target"])
        self.assertEqual(dimensions["runtime_verification"], "NOT_VERIFIED")
        self.assertEqual(dimensions["source_runtime_verification_claim"], "VERIFIED")
        self.source(mockup="other")
        self.assertTrue(project_compatibility.evaluate_mocketeer_reconciliation(self.root)["reconciliation_required"])
        self.source(requirements=[{"id": "SOURCE-NEW"}])
        self.assertTrue(project_compatibility.evaluate_mocketeer_reconciliation(self.root)["reconciliation_required"])

    def test_archive_revision_is_read_without_latest_active_inference(self):
        source = self.source()
        self.decision()
        archive = "planning/target-mockups/demo/_history/REV-002"
        self.write(f"{archive}/revision.yaml", {
            "revision_id": "REV-002", "mockup_name": "demo", "entry_point": "index.html",
            "refinement_status": "ACCEPTED", "lifecycle_status": "REFINED_TARGET",
            "active_target": True, "acceptance_decisions": ["DEC-001"],
            "impact_scope": "targeted", "affected_screens": ["PAGE-EDIT"],
        })
        (self.root / archive / "index.html").write_bytes(source.read_bytes())
        self.page("PAGE-EDIT", target_revision="REV-002")
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        self.assertFalse(project_compatibility.evaluate_mocketeer_reconciliation(self.root)["reconciliation_required"])
        self.assertEqual(project_compatibility.reconcile_page_revision_bindings(self.root)["state"], "BOUND")
        self.assertEqual(before, {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()})
        self.write("planning/revisions/REV-003.yaml", {
            "revision_id": "REV-003", "revision": 3, "mockup_name": "demo",
            "active_target": False, "refinement_status": "PROPOSED",
        })
        self.assertEqual(project_compatibility.reconcile_page_revision_bindings(self.root)["revision_id"], "REV-002")

    def test_duplicate_revision_identity_and_missing_affected_page_are_not_bound(self):
        self.revision(affected_screens=["PAGE-EDIT", "PAGE-MISSING"])
        self.page("PAGE-EDIT", target_revision="REV-002")
        result = project_compatibility.reconcile_page_revision_bindings(self.root)
        self.assertNotEqual(result["state"], "BOUND")
        self.assertIn("PAGE-MISSING", result["missing_pages"])
        original = yaml.safe_load((self.root / "planning/revisions/REV-002.yaml").read_text())
        self.write("planning/target-mockups/demo/_history/REV-002/revision.yaml", original)
        self.assertEqual(project_compatibility.reconcile_page_revision_bindings(self.root)["state"], "AMBIGUOUS_REVISION")

    def test_declared_target_needs_real_confirmed_decision(self):
        self.revision()
        doc = yaml.safe_load((self.root / "planning/revisions/REV-002.yaml").read_text())
        for status in ("PROPOSED", "REJECTED", "SUPERSEDED"):
            with self.subTest(status=status):
                self.decision(status)
                dimensions = project_compatibility.classify_revision_dimensions(self.root, doc)
                self.assertFalse(dimensions["project_accepted_revision"])
                self.assertFalse(dimensions["project_active_target"])
        (self.root / "planning/decisions/DEC-001.yml").unlink()
        self.assertFalse(project_compatibility.classify_revision_dimensions(self.root, doc)["project_accepted_revision"])
        self.decision()
        dimensions = project_compatibility.classify_revision_dimensions(self.root, doc)
        self.assertTrue(dimensions["project_accepted_revision"])
        self.assertFalse(dimensions["mocketeer_contract_ready"])
        self.assertFalse(dimensions["mocketeer_handoff_ready"])

    def test_targeted_explicit_unchanged_scope_retains_only_valid_evidence(self):
        self.revision(screens=[{"page_id": "PAGE-LIST", "delta_visual": "UNCHANGED",
                                "delta_interaction": "UNCHANGED"}])
        self.page("PAGE-EDIT", target_revision="REV-002")
        self.page("PAGE-LIST")
        self.page("PAGE-OTHER", mockup_name="other")
        result = project_compatibility.reconcile_page_revision_bindings(self.root)
        self.assertEqual(result["state"], "BOUND")
        self.assertEqual(result["unchanged_pages"], [{
            "page_id": "PAGE-LIST", "bound_to_active": False, "evidence_disposition": "RETAIN_VALID_EVIDENCE"}])
        self.assertNotIn("PAGE-OTHER", result["bound_pages"])
        for scope in ("full", "cross_cutting", "unknown"):
            with self.subTest(scope=scope):
                self.revision(impact_scope=scope, affected_screens=[])
                result = project_compatibility.reconcile_page_revision_bindings(self.root)
                self.assertFalse(result["unchanged_pages"])
                self.assertEqual({page["page_id"] for page in result["impacted_pages"]}, {"PAGE-EDIT", "PAGE-LIST"})
                self.assertNotEqual(result["state"], "BOUND")

    def test_namespace_collision_and_noncanonical_screen_mapping_are_explicit(self):
        self.revision()
        self.page("PAGE-EDIT", target_revision="REV-002")
        self.write("planning/target-mockups/other/_history/REV-002/revision.yaml", {
            "revision_id": "REV-002", "mockup_name": "other", "refinement_status": "ACCEPTED",
            "active_target": True, "lifecycle_status": "REFINED_TARGET", "acceptance_decisions": ["DEC-001"],
        })
        self.assertEqual(project_compatibility.reconcile_page_revision_bindings(self.root, "REV-002")["state"], "AMBIGUOUS_REVISION")
        (self.root / "planning/target-mockups/other/_history/REV-002/revision.yaml").unlink()
        self.revision(affected_screens=["SCR-EDIT"])
        self.assertNotEqual(project_compatibility.reconcile_page_revision_bindings(self.root)["state"], "BOUND")


class RevisionCreatorRealityTests(FixtureTests):
    def setup_bundle(self, status="CONFIRMED"):
        bundle = self.root / "planning/target-mockups/demo"
        bundle.mkdir(parents=True)
        (bundle / "index.html").write_text("<p>Accepted target</p>", encoding="utf-8")
        self.write("planning/decisions/DEC-001.yml", {"ID": "DEC-001", "title": "Target acceptance", "status": status,
                   "decision_type": "ux_interaction", "topic": "Target", "decision_text": "Accept this target.", "owner": "developer"})
        return bundle

    def test_canonical_confirmation_produces_valid_inactive_revision(self):
        bundle = self.setup_bundle()
        self.write("planning/ui-inventory/PAGE-OTHER.yaml", {"page_id": "PAGE-OTHER", "target_revision": "REV-099"})
        page = self.root / "planning/ui-inventory/PAGE-OTHER.yaml"
        before = page.read_bytes()
        self.assertTrue(create_revision.create_revision(self.root, "demo", "DEC-001"))
        manifest = yaml.safe_load((bundle / "_history/REV-001/revision.yaml").read_text(encoding="utf-8"))
        self.assertEqual(list(validator("revision.schema.json").iter_errors(manifest)), [])
        self.assertEqual(manifest["refinement_status"], "ACCEPTED")
        self.assertFalse(manifest["active_target"])
        self.assertEqual(page.read_bytes(), before)

    def test_proposed_or_filename_only_decision_does_not_create_accepted_history(self):
        bundle = self.setup_bundle(status="PROPOSED")
        self.assertFalse(create_revision.create_revision(self.root, "demo", "DEC-001"))
        (self.root / "planning/decisions/DEC-001.yml").unlink()
        (self.root / "planning/decisions/DEC-001.md").write_text("# Acceptance idea\n", encoding="utf-8")
        self.assertFalse(create_revision.create_revision(self.root, "demo", "DEC-001"))
        self.assertFalse((bundle / "_history").exists())


if __name__ == "__main__":
    unittest.main()
