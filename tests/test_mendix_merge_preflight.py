"""Mendix merge preflight / strategy resolver / post-merge gate.

Fixtures A-H are synthetic and minimal. Fixture R reproduces the structure of a real criss-cross integration
(two merge bases, one historically damaged base, ten artifacts as two UUID lines, competing guard semantics,
a shared domain-model conflict, one-sided navigation change, serialization noise on both sides).
All repositories are temporary; the tool under test must stay read-only."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from temp_cleanup import cleanup_temporary_directory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import mendix_merge_preflight as mp  # noqa: E402
from mendix_fixture import MODULE, I64, Model, Repo, bson, domain_model, guid, microflow, navigation  # noqa: E402

TOOL = ROOT / "scripts/mendix_merge_preflight.py"


def base_model() -> Model:
    model = Model()
    for index in range(8):
        model.put_microflow(f"MF_{index}", expression="1 > 0")
    model.add(guid("dm"), MODULE, domain_model({"Order": ["Number"]}))
    model.add(guid("nav"), None, navigation({"Home": "App.Home", "Overview2": "App.Overview"}))
    return model


def mf(index: int) -> str:
    return guid("mf", f"MF_{index}", "base")


class ClassifierTests(unittest.TestCase):
    def test_serialization_noise_is_not_semantic(self):
        original = microflow("X", "1 > 0")
        cases = {
            "key order / int width / dropped defaults / order-free graph arrays / regenerated ids": microflow("X", "1 > 0", noise=True),
        }
        for label, other in cases.items():
            with self.subTest(label):
                verdict = mp.compare_units(original, other)
                self.assertIn(verdict["kind"], ("SERIALIZATION_ONLY", "DEFAULTS_ONLY"))
                self.assertTrue(verdict["id_churn"])
                self.assertFalse(mp.is_semantic(verdict["kind"]))

    def test_each_serialization_dimension_individually(self):
        base = {"$ID": b"a" * 16, "$Type": "T$X", "Name": "n", "Count": 5, "List": [3, {"$ID": b"b" * 16, "V": "1"}]}
        reordered = dict(reversed(list(base.items())))
        wide = dict(base, Count=I64(5))
        marker = dict(base, List=[2, {"$ID": b"b" * 16, "V": "1"}])
        regenerated = dict(base, List=[3, {"$ID": b"z" * 16, "V": "1"}])
        for label, changed in (("key order", reordered), ("int32 to int64", wide), ("list marker", marker), ("regenerated $ID", regenerated)):
            with self.subTest(label):
                self.assertEqual(mp.compare_units(bson(base), bson(changed))["kind"], "SERIALIZATION_ONLY")

    def test_real_changes_are_never_hidden(self):
        base = {"$ID": b"a" * 16, "$Type": "T$X", "Name": "n", "Flag": False, "Count": 5, "Items": [3, {"V": "1"}, {"V": "2"}]}
        for label, changed in (("flag flipped", dict(base, Flag=True)), ("value changed", dict(base, Count=6)),
                               ("ordered array reordered", dict(base, Items=[3, {"V": "2"}, {"V": "1"}])),
                               ("new non-default key", dict(base, Extra="x")), ("renamed", dict(base, Name="m"))):
            with self.subTest(label):
                self.assertEqual(mp.compare_units(bson(base), bson(changed))["kind"], "SEMANTIC")
        self.assertEqual(mp.compare_units(b"\x01\x02", b"\x03\x04")["kind"], "UNPARSEABLE")
        self.assertTrue(mp.is_semantic("UNPARSEABLE"))

    def test_weaker_classes_are_separate(self):
        base = {"$ID": b"a" * 16, "$Type": "T$X", "Name": "n", "Doc": "", "Objects": [3, {"$ID": b"b" * 16, "$Type": "E", "Size": "20;20"}]}
        self.assertEqual(mp.compare_units(bson(base), bson({k: v for k, v in base.items() if k != "Doc"}))["kind"], "DEFAULTS_ONLY")
        moved = dict(base, Objects=[3, {"$ID": b"b" * 16, "$Type": "E", "Size": "30;30"}])
        self.assertEqual(mp.compare_units(bson(base), bson(moved))["kind"], "PRESENTATION_ONLY")

    def test_guard_findings(self):
        guarded, collapsed, other = microflow("G", "$KC/CanEditRegions"), microflow("G", "true"), microflow("G", "1 > 0")
        found = mp.guard_findings(guarded, collapsed, ("CanEditRegions",))
        self.assertIn("GUARD_COLLAPSE", found["findings"])
        self.assertIn("PROTECTED_MARKER:CanEditRegions", found["findings"])
        self.assertEqual(found["guard_expressions"], ["$KC/CanEditRegions"])
        self.assertEqual(mp.guard_findings(other, microflow("G", "2 > 0"), ("CanEditRegions",))["findings"], [])


class FixtureBase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-merge-")
        self.repo = Repo(Path(self.temp.name) / "repo")

    def tearDown(self):
        cleanup_temporary_directory(self.temp, expected_prefix="mxagile-merge-")

    def pre(self, target, source, markers=(), root=None, **kwargs):
        return mp.preflight(root or self.repo.root, target, source, None, markers, **kwargs)

    def branches(self, base: Model, a: Model, b: Model):
        base_sha = self.repo.commit(base, "base", ref="base")
        return base_sha, self.repo.commit(a, "A", (base_sha,), "A"), self.repo.commit(b, "B", (base_sha,), "B")

    def cli(self, *arguments, root=None):
        return subprocess.run([sys.executable, "-I", str(TOOL), "--project-root", str(root or self.repo.root), *arguments], capture_output=True, text=True)


class SyntheticFixtureTests(FixtureBase):
    def test_a_independent_microflows_merge_natively_even_though_mpr_changed_on_both_sides(self):
        base = base_model()
        a, b = base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), base.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        self.branches(base, a, b)
        report = self.pre("A", "B")
        self.assertTrue(report["read_only"])
        self.assertTrue(report["mpr_changed_on_both_sides"], "precondition: the .mpr differs on both sides")
        self.assertEqual((report["strategy"], report["strategy_alias"]), (mp.STUDIO_PRO_MERGE, "MERGE_NATIVE"))
        self.assertFalse(report["criss_cross"])
        self.assertEqual((report["shared_semantic_count"], report["identity_divergence_count"], report["security_critical"]), (0, 0, []))
        self.assertNotEqual(report["strategy"], mp.REPLAY_REQUIRED)
        self.assertEqual(report["model_versions"]["target"], "10.24.11.1")
        self.assertTrue(report["registry"]["target"]["consistent"] and report["registry"]["source"]["consistent"])

    def test_b_same_microflow_changed_on_both_sides_needs_targeted_review(self):
        base = base_model()
        a, b = base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), base.copy().set_microflow(mf(0), "MF_0", expression="3 > 0")
        self.branches(base, a, b)
        report = self.pre("A", "B")
        self.assertEqual((report["strategy"], report["strategy_alias"]), (mp.STUDIO_PRO_MERGE_REVIEW, "MERGE_NATIVE_WITH_CONFLICT_REVIEW"))
        self.assertEqual([item["identity"] for item in report["shared_semantic_units"]], ["App.MF_0"])
        self.assertEqual(report["security_critical"], [])

    def test_c_mxcli_serialization_on_one_side_is_not_overlap(self):
        base = base_model()
        a = base.copy()
        for index in range(1, 8):
            a.set_microflow(mf(index), f"MF_{index}", expression="1 > 0", noise=True)
        b = base.copy().set_microflow(mf(1), "MF_1", expression="9 > 0")
        self.branches(base, a, b)
        report = self.pre("A", "B")
        change = report["changes"][0]
        self.assertEqual(change["target"]["semantic"], 0)
        self.assertEqual(change["target"]["serialization_only"] + change["target"]["defaults_only"], 7)
        self.assertEqual(change["source"]["semantic"], 1)
        self.assertEqual(report["shared_semantic_count"], 0)
        self.assertEqual(report["strategy"], mp.STUDIO_PRO_MERGE)

    def test_d_rebuilt_artifact_with_new_uuid_needs_semantic_reconciliation(self):
        base = base_model()
        a = base.copy().remove(mf(3))
        rebuilt = a.put_microflow("MF_3", line="rebuilt", expression="7 > 0")
        b = base.copy().set_microflow(mf(3), "MF_3", expression="8 > 0")
        self.branches(base, a, b)
        report = self.pre("A", "B")
        self.assertEqual(report["strategy"], mp.SEMANTIC_RECONCILIATION)
        divergence = report["identity_divergences"][0]
        self.assertEqual((divergence["identity"], divergence["merge_effect"]), ("App.MF_3", "REBUILD_CONFLICT"))
        self.assertEqual((divergence["target_unit"], divergence["source_unit"]), (rebuilt, mf(3)))

    def test_d2_rebuild_without_other_side_change_is_deterministic_and_not_a_conflict(self):
        base = base_model()
        a = base.copy().remove(mf(3))
        a.put_microflow("MF_3", line="rebuilt", expression="7 > 0")
        self.branches(base, a, base.copy())
        report = self.pre("A", "B")
        self.assertEqual(report["identity_divergences"][0]["merge_effect"], "TARGET_LINE_WINS")
        self.assertEqual(report["identity_divergence_real_count"], 0)
        self.assertEqual(report["strategy"], mp.STUDIO_PRO_MERGE)

    def test_e_inconsistent_registry_blocks(self):
        base = base_model()
        orphaned = base.copy()
        orphaned.orphans = {guid("orphan", str(i)): b"junk" for i in range(2)}
        self.branches(base, orphaned, base.copy())
        report = self.pre("A", "B")
        self.assertEqual(report["strategy"], mp.BLOCKED)
        self.assertIn("REGISTRY_INCONSISTENT_TARGET", report["blocking_reasons"])
        registry = report["registry"]["target"]
        self.assertEqual((registry["orphan_count"], registry["mxunit_files"] - registry["registry_entries"]), (2, 2))

    def test_e2_missing_unit_and_hash_mismatch_block(self):
        base = base_model()
        missing = base.copy()
        missing.missing_files = {mf(5)}
        mismatch = base.copy()
        mismatch.hash_overrides[mf(6)] = "bm90LXRoZS1oYXNo"
        self.branches(base, missing, mismatch)
        report = self.pre("A", "base")
        self.assertEqual(report["strategy"], mp.BLOCKED)
        self.assertEqual(report["registry"]["target"]["missing_units"], [mf(5)])
        report = self.pre("B", "base")
        self.assertEqual(report["strategy"], mp.BLOCKED)
        self.assertEqual(report["registry"]["target"]["hash_mismatches"], [mf(6)])

    def test_f_format_or_version_change_requires_replay(self):
        base = base_model()
        legacy = base.copy()
        legacy.fmt = "v1"
        self.branches(base, base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), legacy)
        report = self.pre("A", "B")
        self.assertEqual(report["strategy"], mp.REPLAY_REQUIRED)
        self.assertTrue(any(reason.startswith("MPR_FORMAT_CHANGE") for reason in report["reasons"]))

    def test_f2_minor_version_change_requires_replay_but_patch_difference_only_warns(self):
        base = base_model()
        newer = base.copy()
        newer.product = "10.25.0.1"
        self.branches(base, base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), newer)
        self.assertEqual(self.pre("A", "B")["strategy"], mp.REPLAY_REQUIRED)
        patched = base.copy()
        patched.product = "10.24.12.1"
        self.repo.commit(patched, "patch", (self.repo.git("rev-parse", "base"),), "C")
        report = self.pre("A", "C")
        self.assertEqual(report["strategy"], mp.STUDIO_PRO_MERGE)
        self.assertTrue(any("PATCH_VERSION_DIFFERS" in warning for warning in report["warnings"]))

    def test_f3_native_reconciliation_failure_is_the_only_evidence_based_replay_trigger(self):
        base = base_model()
        self.branches(base, base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), base.copy().set_microflow(mf(1), "MF_1", expression="3 > 0"))
        report = self.pre("A", "B", native_reconciliation_failed=True)
        self.assertEqual(report["strategy"], mp.REPLAY_REQUIRED)
        self.assertIn("NATIVE_RECONCILIATION_EVIDENCED_INSUFFICIENT", report["reasons"])

    def test_g_postcheck_detects_lost_units_and_is_not_a_pass_without_expectations(self):
        base = base_model()
        a = base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0")
        new_a = a.put_microflow("NEW_A", line="a")
        b = base.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        new_b = b.put_microflow("NEW_B", line="b")
        _, _, b_sha = self.branches(base, a, b)
        report = self.pre("A", "B")
        self.assertEqual(report["strategy"], mp.STUDIO_PRO_MERGE)
        merged = a.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        merged.add(new_b, MODULE, b.units[new_b]["data"])
        merged.write(self.repo.root)
        good = mp.postcheck(self.repo.root, None, report)
        self.assertEqual(good["state"], "PASS", good["checks"])
        self.assertEqual(good["expected_features"], {"target_added": 1, "source_added": 1, "target_missing": 0, "source_missing": 0})
        merged.remove(new_b).write(self.repo.root)
        lost = mp.postcheck(self.repo.root, None, report)
        self.assertEqual(lost["state"], "FAIL")
        self.assertEqual({c["check"]: c["status"] for c in lost["checks"]}["no_lost_units"], "FAIL")
        self.assertEqual((lost["lost_units"][0]["unit"], lost["lost_units"][0]["restore_from"]), (new_b, b_sha))
        self.assertEqual(lost["lost_units"][0]["restore_path"], f"mprcontents/{new_b[:2]}/{new_b[2:4]}/{new_b}.mxunit")
        self.assertNotEqual(new_a, new_b)
        bare = mp.postcheck(self.repo.root, None, None)
        self.assertEqual(bare["state"], "INCOMPLETE", "missing verification must never read as PASS")

    def test_g2_postcheck_blocks_unresolved_git_conflict_and_inconsistent_registry(self):
        base = base_model()
        a, b = base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), base.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        self.branches(base, a, b)
        report = self.pre("A", "B")
        self.repo.git("checkout", "--quiet", "-f", "A")
        self.repo.git("merge", "--no-edit", "B", check=False)
        conflicted = mp.postcheck(self.repo.root, None, report)
        self.assertEqual({c["check"]: c["status"] for c in conflicted["checks"]}["merge_conflicts_resolved"], "FAIL")
        self.assertEqual(conflicted["state"], "FAIL")
        self.repo.git("merge", "--abort")
        orphaned = a.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        orphaned.orphans = {guid("orphan", str(i)): b"junk" for i in range(111)}
        orphaned.write(self.repo.root)
        result = mp.postcheck(self.repo.root, None, report)
        self.assertEqual(result["state"], "FAIL")
        self.assertEqual((result["registry"]["orphan_count"], result["registry"]["mxunit_files"] - result["registry"]["registry_entries"]), (111, 111))

    def test_h_linked_worktrees_use_their_own_head_index_and_files(self):
        base = base_model()
        a, b = base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), base.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        base_sha, a_sha, b_sha = self.branches(base, a, b)
        wt_a, wt_b = Path(self.temp.name) / "wtA", Path(self.temp.name) / "wtB"
        self.repo.git("worktree", "add", "--quiet", str(wt_a), "A")
        self.repo.git("worktree", "add", "--quiet", str(wt_b), "B")
        main_report = self.pre("A", "B")
        report_a, report_b = mp.preflight(wt_a, "HEAD", "B"), mp.preflight(wt_b, "HEAD", "A")
        self.assertEqual((report_a["target"]["sha"], report_b["target"]["sha"]), (a_sha, b_sha))
        self.assertEqual([item["sha"] for item in report_a["merge_bases"]], [base_sha])
        self.assertEqual([item["sha"] for item in report_b["merge_bases"]], [base_sha])
        indexes = {report_a["git_index_guard"]["index_path"], report_b["git_index_guard"]["index_path"], main_report["git_index_guard"]["index_path"]}
        self.assertEqual(len(indexes), 3, "each checkout must report its own index")
        self.assertEqual({report_a["strategy"], report_b["strategy"], main_report["strategy"]}, {mp.STUDIO_PRO_MERGE})
        broken = b.copy()
        broken.orphans = {guid("orphan", "x"): b"junk"}
        broken.write(wt_b)
        self.assertEqual(mp.postcheck(wt_b, None, report_b)["state"], "FAIL")
        self.assertEqual({c["check"]: c["status"] for c in mp.postcheck(wt_a, None, report_a)["checks"]}["mpr_mxunit_consistent"], "PASS")

    def test_cli_is_read_only_works_from_subdirectories_and_uses_stable_exit_codes(self):
        base = base_model()
        a, b = base.copy().set_microflow(mf(0), "MF_0", expression="2 > 0"), base.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        self.branches(base, a, b)
        index = self.repo.root / ".git" / "index"
        state = (index.read_bytes(), self.repo.git("rev-parse", "A"), self.repo.git("status", "--porcelain"))
        deep = self.repo.root / "mprcontents"
        output = Path(self.temp.name) / "report.json"
        result = self.cli("--output", str(output), "preflight", "--target", "A", "--source", "B", root=deep)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["strategy"], mp.STUDIO_PRO_MERGE)
        self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["schema"], mp.SCHEMA_PREFLIGHT)
        text = self.cli("--format", "text", "preflight", "--target", "A", "--source", "B")
        self.assertIn("STRATEGY: STUDIO_PRO_MERGE (MERGE_NATIVE)", text.stdout)
        merged = a.copy().set_microflow(mf(1), "MF_1", expression="3 > 0")
        merged.write(self.repo.root)
        post = self.cli("postcheck", "--preflight", str(output))
        self.assertEqual((post.returncode, json.loads(post.stdout)["state"]), (0, "PASS"), post.stdout)
        self.assertEqual(self.cli("postcheck").returncode, 4, "INCOMPLETE is not PASS")
        self.assertEqual(self.cli("preflight", "--target", "A", "--source", "does-not-exist").returncode, 3)
        self.repo.git("checkout", "--quiet", "--", ".")
        self.repo.git("reset", "--quiet", "--mixed", "A")
        self.assertEqual(self.repo.git("rev-parse", "A"), state[1])
        noisy = base.copy().set_microflow(mf(2), "MF_2", expression="1 > 0", noise=True).set_microflow(mf(3), "MF_3", expression="4 > 0")
        noisy.write(self.repo.root)
        classified = json.loads(self.cli("classify-changes", "--base", "base").stdout)
        self.assertEqual((classified["counts"]["DEFAULTS_ONLY"], classified["counts"]["SEMANTIC"]), (1, 1))
        self.assertTrue(state[0])
        blocked = base.copy()
        blocked.orphans = {guid("orphan", "x"): b"junk"}
        self.repo.commit(blocked, "blocked", (self.repo.git("rev-parse", "base"),), "C")
        self.assertEqual(self.cli("preflight", "--target", "C", "--source", "B").returncode, 4)


class RealityFixtureTests(FixtureBase):
    """Fixture R: criss-cross history with the properties of a real integration state."""

    DIVERGENT = [f"DIV_{index}" for index in range(10)]

    def build(self):
        l0m = base_model()
        for index in range(20):
            l0m.add(guid("nz", str(index)), MODULE, microflow(f"NZ_{index}", "1 > 0"))
        self.auth = l0m.put_microflow("SUB_Region_Authorize", expression="$KC/CanEdit")
        self.undo = l0m.put_microflow("SUB_Region_UndoAvailable", expression="$KC/CanEdit")
        self.kc = l0m.put_microflow("SUB_KnowledgeContext_GetOrCreate", expression="1 > 0")
        l0 = self.repo.commit(l0m, "L0", ref="L0")
        dm_x = domain_model({"Order": ["Number"], "KnowledgeContext": ["CanEditRegions"]})
        x1m = l0m.copy()
        x1m.add(guid("dm"), MODULE, dm_x)
        x1m.orphans = {guid("historic-orphan", str(i)): b"junk" for i in range(3)}  # historically damaged merge base
        x1 = self.repo.commit(x1m, "X1", (l0,), "X1")
        y1m = l0m.copy()
        y1m.set_microflow(self.auth, "SUB_Region_Authorize", expression="true").set_microflow(self.undo, "SUB_Region_UndoAvailable", expression="true")
        y1 = self.repo.commit(y1m, "Y1", (l0,), "Y1")
        x2m = x1m.copy()
        x2m.orphans = {}
        for index in range(12):
            x2m.set_microflow(guid("nz", str(index)), f"NZ_{index}", expression="1 > 0", noise=True)
        x2 = self.repo.commit(x2m, "X2", (x1,), "X2")
        y2m = y1m.copy()
        for index in range(12, 20):
            y2m.set_microflow(guid("nz", str(index)), f"NZ_{index}", expression="1 > 0", noise=True)
        y2m.add(guid("nav"), None, navigation({"Home": "App.Home", "Overview2": "App.Overview_V2"}))
        y2 = self.repo.commit(y2m, "Y2", (y1,), "Y2")
        m1m = x2m.copy()
        m1m.set_microflow(self.auth, "SUB_Region_Authorize", expression="true").set_microflow(self.undo, "SUB_Region_UndoAvailable", expression="true")
        m1 = self.repo.commit(m1m, "M1 merge(X2,Y1)", (x2, y1), "M1")
        m2m = y2m.copy()
        m2 = self.repo.commit(m2m, "M2 merge(Y2,X1)", (y2, x1), "M2")
        tm = m1m.copy()
        tm.set_microflow(self.auth, "SUB_Region_Authorize", expression="$KC/CanEditRegions").set_microflow(self.undo, "SUB_Region_UndoAvailable", expression="$KC/CanEditRegions")
        tm.set_microflow(self.kc, "SUB_KnowledgeContext_GetOrCreate", expression="2 > 0")
        tm.add(guid("dm"), MODULE, domain_model({"Order": ["Number"], "KnowledgeContext": ["CanEditRegions"], "TEdit": ["X"]}))
        sm = m2m.copy()
        sm.set_microflow(self.kc, "SUB_KnowledgeContext_GetOrCreate", expression="3 > 0")
        sm.add(guid("dm"), MODULE, domain_model({"Order": ["Number", "SEdit"]}))
        for index, name in enumerate(self.DIVERGENT):
            tm.put_microflow(name, line="t", expression="1 > 0" if index >= 4 else f"{index} > 0")
            sm.put_microflow(name, line="s", expression="1 > 0" if index >= 4 else f"{index + 10} > 0")
        self.feat_t, self.feat_s = tm.put_microflow("FEAT_T", line="t"), sm.put_microflow("FEAT_S", line="s")
        self.tm, self.sm = tm, sm
        self.x1, self.y1 = x1, y1
        self.repo.commit(tm, "T", (m1,), "target")
        self.repo.commit(sm, "S", (m2,), "source")

    def merged(self) -> Model:
        z = self.tm.copy()
        z.put_microflow("FEAT_S", line="s")
        z.set_microflow(self.kc, "SUB_KnowledgeContext_GetOrCreate", expression="2 > 0 and 3 > 0")
        z.add(guid("dm"), MODULE, domain_model({"Order": ["Number", "SEdit"], "KnowledgeContext": ["CanEditRegions"], "TEdit": ["X"]}))
        z.add(guid("nav"), None, navigation({"Home": "App.Home", "Overview2": "App.Overview_V2"}))
        return z

    def test_reality_preflight_classification(self):
        self.build()
        self.assertEqual(sorted(self.repo.git("merge-base", "--all", "target", "source").split()), sorted([self.x1, self.y1]))
        before = (self.repo.git("rev-parse", "target"), self.repo.git("status", "--porcelain"), (self.repo.root / ".git/index").read_bytes())
        report = self.pre("target", "source", ("CanEditRegions",))
        self.assertEqual((self.repo.git("rev-parse", "target"), self.repo.git("status", "--porcelain"), (self.repo.root / ".git/index").read_bytes()), before)
        # 1. .mpr changed on both sides must not trigger replay
        self.assertTrue(report["mpr_changed_on_both_sides"])
        self.assertEqual((report["strategy"], report["strategy_alias"]), (mp.STUDIO_PRO_MERGE_REVIEW, "MERGE_NATIVE_WITH_CONFLICT_REVIEW"))
        self.assertNotEqual(report["strategy"], mp.REPLAY_REQUIRED)
        # 2. criss-cross is explicit
        self.assertTrue(report["criss_cross"])
        self.assertEqual(len(report["merge_bases"]), 2)
        self.assertTrue(any(w.startswith("CRISS_CROSS_HISTORY") for w in report["warnings"]))
        # both heads consistent; the historical damage lives in exactly one base only and does not block
        self.assertTrue(report["registry"]["target"]["consistent"] and report["registry"]["source"]["consistent"])
        damaged = [base for base in report["merge_bases"] if not base["registry_consistent"]]
        self.assertEqual([base["sha"] for base in damaged], [self.x1])
        self.assertEqual(damaged[0]["orphan_count"], 3)
        self.assertEqual(report["blocking_reasons"], [])
        self.assertTrue(any(w.startswith("HISTORICAL_MERGE_BASE_INCONSISTENT") for w in report["warnings"]))
        # 3. identity divergence is visible: ten artifacts, two UUID lines each
        self.assertEqual(report["identity_divergence_count"], 10)
        self.assertEqual(report["identity_divergence_real_count"], 10)
        self.assertEqual({item["identity"] for item in report["identity_divergences"]}, {f"App.{name}" for name in self.DIVERGENT})
        self.assertEqual({item["merge_effect"] for item in report["identity_divergences"]}, {"DUPLICATE_AFTER_MERGE"})
        self.assertEqual(sum(item["content"] == "DIFFERENT" for item in report["identity_divergences"]), 4)
        for item in report["identity_divergences"]:
            self.assertNotEqual(item["target_unit"], item["source_unit"])
        # real shared semantic conflict: domain model, knowledge context, and the two guards
        shared = {item["identity"]: item for item in report["shared_semantic_units"]}
        self.assertEqual(set(shared), {"App.<DomainModel>", "App.SUB_KnowledgeContext_GetOrCreate", "App.SUB_Region_Authorize", "App.SUB_Region_UndoAvailable"})
        # 4. competing guard semantics may not be decided by an arbitrary merge base
        self.assertTrue(shared["App.SUB_Region_Authorize"]["base_dependent_outcome"])
        self.assertTrue(shared["App.SUB_Region_UndoAvailable"]["base_dependent_outcome"])
        self.assertFalse(shared["App.SUB_KnowledgeContext_GetOrCreate"]["base_dependent_outcome"])
        security = {item["identity"]: item for item in report["security_critical"]}
        self.assertEqual({k for k, v in security.items() if "GUARD_COLLAPSE" in v["findings"]}, {"App.SUB_Region_Authorize", "App.SUB_Region_UndoAvailable"})
        self.assertIn("PROTECTED_MARKER:CanEditRegions", security["App.<DomainModel>"]["findings"])
        self.assertEqual(security["App.SUB_Region_Authorize"]["guard_expressions"], ["$KC/CanEditRegions"])
        actions = {action["action"]: action for action in report["required_actions"]}
        self.assertIn("EXPLICIT_DECISION", actions["SECURITY_DECISION_REQUIRED"]["policy"])
        # 5. explicit identity reconciliation for the ten divergences
        self.assertEqual((actions["IDENTITY_RECONCILIATION"]["count"], actions["IDENTITY_RECONCILIATION"]["real_after_merge"]), (10, 10))
        # serialization noise exists but is not a semantic overlap
        target_vs_base = report["changes"][0]["target"]
        self.assertEqual(target_vs_base["serialization_only"] + target_vs_base["defaults_only"], 12)
        self.assertEqual(report["serialization_only_between_heads"], 20)
        for item in report["shared_semantic_units"]:
            self.assertFalse(item["identity"].startswith("App.NZ_"), "noise units must never appear as semantic overlap")
        # the one-sided navigation change is not a conflict
        self.assertNotIn(".<NavigationDocument>", shared)

    def check_states(self, report, **kwargs):
        result = mp.postcheck(self.repo.root, None, report, ("CanEditRegions",), **kwargs)
        return result, {check["check"]: check["status"] for check in result["checks"]}

    def test_reality_postcheck_gate(self):
        self.build()
        report = self.pre("target", "source", ("CanEditRegions",))
        good = self.merged()
        good.write(self.repo.root)
        result, states = self.check_states(report)
        self.assertEqual(result["state"], "PASS", result["checks"])
        self.assertEqual(set(states.values()), {"PASS"})
        self.assertEqual(result["expected_features"]["source_missing"] + result["expected_features"]["target_missing"], 0)

        duplicates = good.copy()
        for name in self.DIVERGENT:
            duplicates.put_microflow(name, line="s", expression="1 > 0")
        duplicates.write(self.repo.root)
        result, states = self.check_states(report)
        self.assertEqual((result["state"], states["no_duplicate_artifact_names"]), ("FAIL", "FAIL"))
        self.assertEqual(len(result["duplicate_identities"]), 10)

        collapsed = good.copy().set_microflow(self.auth, "SUB_Region_Authorize", expression="true")
        collapsed.write(self.repo.root)
        result, states = self.check_states(report)
        self.assertEqual(result["state"], "FAIL")
        self.assertEqual((states["security_decisions_resolved"], states["protected_markers_preserved"]), ("FAIL", "FAIL"))
        accepted, states = self.check_states(report, accepted=("App.SUB_Region_Authorize",))
        self.assertEqual(accepted["state"], "PASS", "an explicit, recorded acceptance is the only way to give up a protected guard")
        self.assertEqual(accepted["accepted_security_decisions"], ["App.SUB_Region_Authorize"])

        lost = good.copy().remove(self.feat_t)
        lost.write(self.repo.root)
        result, states = self.check_states(report)
        self.assertEqual((result["state"], states["no_lost_units"], states["expected_features_of_both_branches_present"]), ("FAIL", "FAIL", "FAIL"))
        self.assertEqual(result["lost_units"][0]["unit"], self.feat_t)

        broken = good.copy()
        broken.orphans = {guid("orphan", str(i)): b"junk" for i in range(111)}
        broken.write(self.repo.root)
        result, states = self.check_states(report)
        self.assertEqual((result["state"], states["mpr_mxunit_consistent"]), ("FAIL", "FAIL"))

        wrong_hash = good.copy()
        wrong_hash.hash_overrides[self.kc] = "bm90LXRoZS1oYXNo"
        wrong_hash.write(self.repo.root)
        self.assertEqual(self.check_states(report)[1]["mpr_mxunit_consistent"], "FAIL")

    def test_reality_postcheck_on_a_committed_merge_revision(self):
        self.build()
        report = self.pre("target", "source", ("CanEditRegions",))
        sha = self.repo.commit(self.merged(), "merge result", (self.repo.git("rev-parse", "target"), self.repo.git("rev-parse", "source")), "result")
        result = mp.postcheck(self.repo.root, sha, report, ("CanEditRegions",))
        self.assertEqual(result["state"], "PASS", result["checks"])

    def test_reality_concord_scope_is_targeted(self):
        self.build()
        scope = self.pre("target", "source", ("CanEditRegions",))["concord_scope"]
        kinds = {}
        for item in scope["in_scope"]:
            kinds.setdefault(item["kind"], []).append(item["identity"])
        self.assertEqual({kind: len(identities) for kind, identities in kinds.items()}, {"IDENTITY_DIVERGENCE": 10, "SHARED_SEMANTIC": 4})
        decisions = {item["identity"] for item in scope["in_scope"] if item["decision_required"]}
        self.assertEqual(decisions, {"App.SUB_Region_Authorize", "App.SUB_Region_UndoAvailable", "App.<DomainModel>"})
        self.assertEqual(scope["decisions_required"], 3)
        self.assertEqual(scope["out_of_scope"]["serialization_noise_units_between_heads"], 20)
        everything = {item["identity"] for item in scope["in_scope"]}
        self.assertFalse(any(identity.startswith("App.NZ_") for identity in everything), "noise is never Concord scope")
        self.assertNotIn(".<NavigationDocument>", everything, "a one-sided change is not a conflict")

    def test_reality_staged_postchecks_studio_pro_then_concord_then_final(self):
        self.build()
        report_file = Path(self.temp.name) / "preflight.json"
        cli = self.cli("--output", str(report_file), "preflight", "--target", "target", "--source", "source", "--protected-marker", "CanEditRegions")
        self.assertEqual(cli.returncode, 0, cli.stderr)
        report = json.loads(report_file.read_text(encoding="utf-8"))
        markers = ("CanEditRegions",)
        # state right after the Studio Pro merge: both UUID lines exist, one guard collapsed, Concord scope still open
        studio = self.merged()
        for name in self.DIVERGENT:
            studio.put_microflow(name, line="s", expression="1 > 0")
        studio.set_microflow(self.auth, "SUB_Region_Authorize", expression="true")
        studio.write(self.repo.root)
        first = mp.postcheck(self.repo.root, None, report, markers, stage="studio-pro-merge")
        states = {check["check"]: check["status"] for check in first["checks"]}
        self.assertEqual(first["state"], "OPEN_ITEMS", first["checks"])
        self.assertEqual((states["no_duplicate_artifact_names"], states["security_decisions_resolved"], states["protected_markers_preserved"]), ("OPEN", "OPEN", "OPEN"))
        self.assertEqual((states["mpr_mxunit_consistent"], states["no_lost_units"]), ("PASS", "PASS"))
        self.assertEqual(first["scope"]["identity_divergences_open"], 10)
        self.assertEqual({item["kind"] for item in first["remaining_scope"]}, {"IDENTITY_DIVERGENCE", "SECURITY_DECISION", "PROTECTED_MARKER"})
        self.assertEqual((first["ready_for_final"], first["final_integrity_gate"]), (False, "NOT_PASSED"))
        # the same state is not acceptable after Concord resolution or as the final gate
        for stage in ("concord-resolution", "final"):
            with self.subTest(stage=stage):
                strict = mp.postcheck(self.repo.root, None, report, markers, stage=stage)
                self.assertEqual((strict["state"], strict["final_integrity_gate"]), ("FAIL", "NOT_PASSED"))
        self.assertEqual(self.cli("postcheck", "--stage", "studio-pro-merge", "--preflight", str(report_file), "--protected-marker", "CanEditRegions").returncode, 5)
        self.assertEqual(self.cli("postcheck", "--stage", "final", "--preflight", str(report_file), "--protected-marker", "CanEditRegions").returncode, 4)
        # structural damage stays a hard failure even at the tolerant stage
        broken = studio.copy().remove(self.feat_t)
        broken.orphans = {guid("orphan", str(i)): b"junk" for i in range(3)}
        broken.write(self.repo.root)
        damaged = mp.postcheck(self.repo.root, None, report, markers, stage="studio-pro-merge")
        damaged_states = {check["check"]: check["status"] for check in damaged["checks"]}
        self.assertEqual((damaged["state"], damaged_states["no_lost_units"], damaged_states["mpr_mxunit_consistent"]), ("FAIL", "FAIL", "FAIL"))
        # after Concord resolution: scope closed; only the final stage can pass the integrity gate
        self.merged().write(self.repo.root)
        resolved = mp.postcheck(self.repo.root, None, report, markers, stage="concord-resolution")
        self.assertEqual((resolved["state"], resolved["ready_for_final"], resolved["final_integrity_gate"]), ("PASS", True, "NOT_PASSED"))
        self.assertEqual(resolved["remaining_scope"], [])
        self.assertEqual((resolved["scope"]["identity_divergences_open"], resolved["scope"]["shared_semantic_content_machine_verified"]), (0, False))
        final = mp.postcheck(self.repo.root, None, report, markers, stage="final")
        self.assertEqual((final["state"], final["final_integrity_gate"]), ("PASS", "PASS"))
        self.assertEqual(self.cli("postcheck", "--stage", "final", "--preflight", str(report_file), "--protected-marker", "CanEditRegions").returncode, 0)


class ContractTests(unittest.TestCase):
    def test_policy_routing_and_distribution(self):
        policy = (ROOT / ".mxagile/policies/mendix-integration.md").read_text(encoding="utf-8")
        for marker in ("STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW", "SEMANTIC_RECONCILIATION", "REPLAY_REQUIRED", "BLOCKED", "Studio Pro",
                       "Concord", "CLOSED-AUTONOM", "WORKAROUND", "IDENTITY_DIVERGENCE", "BASE_DEPENDENT", "mendix_merge_preflight.py", "postcheck",
                       "ALTER", "Conflict Resolution"):
            self.assertIn(marker, policy)
        self.assertNotIn("mxagile merge-preflight", policy, "no invented CLI entry point")
        agent = (ROOT / ".mxagile/agents/implementation-agent.md").read_text(encoding="utf-8")
        self.assertIn("policies/mendix-integration.md", agent)
        safety = (ROOT / ".mxagile/policies/safety-rules.md").read_text(encoding="utf-8")
        self.assertIn("mendix-integration.md", safety)
        installer = (ROOT / "scripts/install-core.ps1").read_text(encoding="utf-8")
        self.assertIn(".mxagile/tools/mendix_merge_preflight.py", installer)
        self.assertIn("'mendix_merge_preflight.py'", installer)
        self.assertIn(".mxagile/tools/mendix_merge_preflight.py", (ROOT / "docs/injection-contract.md").read_text(encoding="utf-8"))
        generated = (ROOT / ".claude/agents/mxagile-implementation-agent.md").read_text(encoding="utf-8")
        self.assertIn("policies/mendix-integration.md", generated, "generated projection must follow the canonical agent")


if __name__ == "__main__":
    unittest.main()
