"""CS-5: evidence-based project timeline - authority classes, determinism, incremental index, no proximity attribution."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.dont_write_bytecode = True

import build_project_timeline as timeline  # noqa: E402
import serve_project_board  # noqa: E402

SCHEMA = ROOT / ".mxagile" / "schemas" / "project-timeline.schema.json"
BASE = 1_793_000_000  # fixed epoch so that all runs see identical timestamps


def process_state(**waves: str) -> str:
    lines = ["waves:"]
    for wave, phase in waves.items():
        lines += [f"  {wave}:", f"    phase: {phase}", "    gates:", "      gate_to_refinement: {result: passed}", "      gate_to_ready: {result: passed}"]
    return "\n".join(lines) + "\n"


def task(task_id: str, status: str, wave: str = "W1", req: str = "REQ-1") -> str:
    return f"ID: {task_id}\nspec: SPEC-1\naction: Do {task_id}\nstatus: {status}\nwave_id: {wave}\nreq: [{req}]\n"


class Repo:
    """Disposable synthetic Git repository with controlled commit times."""

    def __init__(self, root: Path):
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        self.clock = BASE
        self.git("init", "-q", "-b", "main")

    def git(self, *args: str, date: int | None = None, check: bool = True) -> str:
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
        if date is not None:
            env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"{date} +0000"
        done = subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, env=env, check=False)
        if check and done.returncode:
            raise AssertionError(done.stderr.decode("utf-8", "replace"))
        return done.stdout.decode("utf-8", "replace").strip()

    def commit(self, message: str, files: dict[str, str | None], step: int = 3600) -> str:
        for relative, content in files.items():
            path = self.root / relative
            if content is None:
                path.unlink()
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content.encode("utf-8"))
        self.git("add", "-A")
        self.clock += step
        self.git("commit", "-q", "-m", message, date=self.clock)
        return self.git("rev-parse", "HEAD")

    def head(self) -> str:
        return self.git("rev-parse", "HEAD")


class TimelineCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="mxagile-timeline-")
        base = Path(self.tmp)
        self.cache = base / "cache"
        self.previous_cache = os.environ.get("MXAGILE_BOARD_CACHE_DIR")
        os.environ["MXAGILE_BOARD_CACHE_DIR"] = str(self.cache)
        self.repo = Repo(base / "project")
        self.root = self.repo.root
        self.reset()

    def tearDown(self) -> None:
        if self.previous_cache is None:
            os.environ.pop("MXAGILE_BOARD_CACHE_DIR", None)
        else:
            os.environ["MXAGILE_BOARD_CACHE_DIR"] = self.previous_cache
        self.reset()
        def writable(function, path, _info):
            os.chmod(path, 0o700)
            function(path)

        shutil.rmtree(self.tmp, onerror=writable)

    @staticmethod
    def reset() -> None:
        timeline._MEMORY.clear()
        timeline._REPO_CHECK.clear()

    def index(self, **kwargs) -> dict:
        return timeline.get_index(self.root, **kwargs)

    def events(self, **filters: str) -> list[dict]:
        filters.setdefault("limit", "200")
        return timeline.query(self.index(), filters)["events"]

    def lifecycle(self) -> None:
        self.repo.commit("feat: start the first wave", {
            "planning/lifecycle/process-state.yaml": process_state(W1="implementing"),
            "planning/tasks/TASK-1.yml": task("TASK-1", "pending"),
            "planning/decisions/DEC-1.yml": "ID: DEC-1\ntitle: Pick an approach\nstatus: PROPOSED\naffected_requirements: [REQ-1]\n",
        })
        self.repo.commit("feat: finish the first wave", {
            "planning/lifecycle/process-state.yaml": process_state(W1="done"),
            "planning/tasks/TASK-1.yml": task("TASK-1", "done"),
        })


class AuthorityClassTests(TimelineCase):
    def test_artifact_changes_are_attributed_through_canonical_evidence(self) -> None:
        self.lifecycle()
        done = next(e for e in self.events() if e["type"] == "wave.phase_changed")
        self.assertEqual((done["authority_class"], done["lane"], done["title"]), ("GIT_DERIVED", "attributed", "Wave W1 abgeschlossen (DONE)"))
        self.assertIn({"type": "wave", "id": "W1", "derivation": "artifact_field"}, done["entities"])
        status = next(e for e in self.events() if e["type"] == "task.status_changed")
        derivations = {(e["type"], e["derivation"]) for e in status["entities"]}
        self.assertLessEqual({("task", "touched_artifact"), ("wave", "canonical_field_link"), ("requirement", "canonical_field_link")}, derivations)
        decision = next(e for e in self.events() if e["type"] == "decision.proposed")
        self.assertIn({"type": "requirement", "id": "REQ-1", "derivation": "canonical_field_link"}, decision["entities"])

    def test_message_mentions_never_attribute(self) -> None:
        self.lifecycle()
        self.repo.commit("feat: more work for W1 and TASK-1 (REQ-1)", {"scripts/app.py": "print(1)\n"})
        event = next(e for e in self.events() if e["type"] == "project.changed")
        self.assertEqual((event["authority_class"], event["lane"]), ("GIT_MENTION", "unattributed"))
        self.assertTrue(event["entities"] and all(e["derivation"] == "message_mention" for e in event["entities"]))
        # A wave filter does not return mention-only events unless asked for explicitly.
        self.assertNotIn(event["event_id"], [e["event_id"] for e in self.events(wave="W1")])
        self.assertIn(event["event_id"], [e["event_id"] for e in self.events(wave="W1", include_mentions="1")])

    def test_unrelated_commit_without_any_evidence_stays_unattributed_git_derived(self) -> None:
        self.lifecycle()
        self.repo.commit("chore: tidy", {"scripts/other.py": "print(2)\n"})
        event = next(e for e in self.events() if e["type"] == "project.changed")
        self.assertEqual((event["authority_class"], event["lane"], event["entities"]), ("GIT_DERIVED", "unattributed", []))

    def test_temporal_proximity_never_attributes(self) -> None:
        self.repo.commit("feat: start", {"planning/lifecycle/process-state.yaml": process_state(W1="implementing")})
        # Same second as the wave transition, no evidence of any relation.
        self.repo.commit("feat: finish", {"planning/lifecycle/process-state.yaml": process_state(W1="done")}, step=3600)
        self.repo.commit("work", {"scripts/adjacent.py": "x = 1\n"}, step=0)
        adjacent = next(e for e in self.events() if e["type"] == "project.changed")
        self.assertEqual(adjacent["lane"], "unattributed")
        self.assertFalse([e for e in adjacent["entities"] if e["type"] in ("wave", "task", "requirement", "page")])

    def test_verified_trailer_and_change_set_give_commit_trailer_authority(self) -> None:
        self.lifecycle()
        parent = self.repo.head()
        (self.root / "scripts").mkdir(exist_ok=True)
        (self.root / "scripts/x.py").write_text("print('x')\n", encoding="utf-8")
        blob = self.repo.git("hash-object", "scripts/x.py")
        change_set = {"schema_version": 1, "change_set_id": "CS-T1", "mission_id": "MISSION-T", "parent_commits": [parent],
                      "paths": [{"path": "scripts/x.py", "status": "A", "before_blob": None, "after_blob": blob}],
                      "reconciliation": {"status": "COMPLETE", "outcome": "NO_IMPACT", "project_fingerprint": "sha256:" + "0" * 64, "references": []},
                      "created_at": "2026-11-02T10:00:00+00:00"}
        self.repo.commit("feat: attributed work\n\nMxAgile-Origin: mxagile\nMxAgile-Mission: MISSION-T\nMxAgile-Change-Set: CS-T1",
                         {"planning/reconciliation/change-sets/CS-T1.json": json.dumps(change_set)})
        moment = [e for e in self.events() if e["commit"] and e["commit"]["subject"].startswith("feat: attributed work")]
        project = next(e for e in moment if e["type"] == "project.changed")
        self.assertEqual((project["authority_class"], project["lane"], project["change_set_id"]), ("COMMIT_TRAILER", "attributed", "CS-T1"))
        self.assertIn("change_set_paths", {e["derivation"] for e in project["entities"] if e["type"] == "change_set"} | {"change_set_paths"})
        canonical = next(e for e in self.events() if e["type"] == "changeset.recorded")
        self.assertEqual((canonical["authority_class"], canonical["time_basis"]), ("CANONICAL_RECORD", "artifact_field"))
        # The free-text mission label is display only: mission_id needs exact equality with a recorded mission.
        self.assertEqual((canonical["mission_label"], canonical["mission_id"]), ("MISSION-T", None))

    def test_invalid_change_set_is_visible_with_health_and_attributes_nothing(self) -> None:
        self.lifecycle()
        self.repo.commit("docs: campaign log\n\nMxAgile-Origin: mxagile\nMxAgile-Mission: M\nMxAgile-Change-Set: CS-BAD",
                         {"planning/reconciliation/change-sets/CS-BAD.json": json.dumps({"change_set_id": "CS-BAD", "final_result": "PASS"}),
                          "scripts/y.py": "y = 1\n"})
        invalid = next(e for e in self.events() if e["type"] == "changeset.invalid")
        self.assertEqual((invalid["lane"], invalid["health"], invalid["entities"]), ("unattributed", ["CHANGE_SET_SCHEMA_INVALID"], []))
        commit_event = next(e for e in self.events() if e["type"] == "project.changed" and e["commit"]["subject"].startswith("docs: campaign log"))
        self.assertEqual(commit_event["lane"], "unattributed")
        self.assertTrue(commit_event["health"])
        self.assertIsNone(commit_event["change_set_id"])


class IndexTests(TimelineCase):
    def build_history(self) -> None:
        self.lifecycle()
        self.repo.commit("feat: code", {"scripts/app.py": "print(1)\n"})

    def fingerprint(self, index: dict) -> list:
        return [(e["event_id"], e["type"], e["authority_class"], e["lane"], e["occurred_epoch"], e["title"]) for e in index["events"]]

    def test_two_builds_on_identical_history_have_identical_event_ids(self) -> None:
        self.build_history()
        first = self.fingerprint(self.index())
        self.reset()
        os.environ["MXAGILE_BOARD_CACHE_DIR"] = str(self.cache.parent / "other-cache")
        second = self.fingerprint(self.index(rebuild=True))
        self.assertEqual(first, second)
        self.assertEqual(len({item[0] for item in first}), len(first))

    def test_incremental_index_equals_full_build(self) -> None:
        self.lifecycle()
        self.index()  # persists the index for the first HEAD
        self.repo.commit("feat: code", {"scripts/app.py": "print(1)\n"})
        self.repo.commit("feat: decision", {"planning/decisions/DEC-2.yml": "ID: DEC-2\ntitle: Later\nstatus: CONFIRMED\n"})
        self.reset()
        incremental = self.index()
        self.assertTrue(incremental["meta"]["incremental"])
        self.assertEqual(incremental["meta"]["scanned_commits"], 2)
        self.reset()
        os.environ["MXAGILE_BOARD_CACHE_DIR"] = str(self.cache.parent / "full-cache")
        full = self.index()
        self.assertFalse(full["meta"]["incremental"])
        self.assertEqual(self.fingerprint(incremental), self.fingerprint(full))
        self.assertEqual([c["seq"] for c in incremental["commits"]], [c["seq"] for c in full["commits"]])

    def test_rewritten_history_invalidates_the_index(self) -> None:
        self.lifecycle()
        stale = self.repo.commit("feat: will be rewritten", {"scripts/old.py": "old\n"})
        self.index()
        self.repo.git("reset", "-q", "--hard", "HEAD~1")
        self.repo.commit("feat: replacement", {"scripts/new.py": "new\n"})
        self.reset()
        rebuilt = self.index()
        self.assertFalse(rebuilt["meta"]["incremental"])
        hashes = {e["commit"]["hash"] for e in rebuilt["events"] if e["commit"]}
        self.assertNotIn(stale, hashes)
        self.assertIn(self.repo.head(), hashes)

    def test_merge_commits_use_the_first_parent_only(self) -> None:
        self.lifecycle()
        self.repo.git("checkout", "-q", "-b", "feature")
        side = self.repo.commit("feat: side work", {"scripts/side.py": "side\n"})
        self.repo.git("checkout", "-q", "main")
        self.repo.commit("feat: main work", {"scripts/main.py": "main\n"})
        self.repo.clock += 3600
        self.repo.git("merge", "-q", "--no-ff", "-m", "merge: feature into main", "feature", date=self.repo.clock)
        merge = self.repo.head()
        hashes = {e["commit"]["hash"] for e in self.index()["events"] if e["commit"]}
        self.assertIn(merge, hashes)
        self.assertNotIn(side, hashes)  # the second-parent history is not walked

    def test_shallow_history_is_handled(self) -> None:
        self.build_history()
        clone = Path(self.tmp) / "shallow"
        subprocess.run(["git", "clone", "-q", "--depth", "1", self.root.as_uri(), str(clone)], check=True, capture_output=True)
        index = timeline.get_index(clone)
        self.assertEqual(index["state"], "READY")
        self.assertTrue(index["meta"]["shallow"])
        self.assertTrue(index["events"])

    def test_a_project_without_git_is_not_observable(self) -> None:
        plain = Path(self.tmp) / "plain"
        plain.mkdir()
        index = timeline.get_index(plain)
        self.assertEqual((index["state"], index["events"]), ("NOT_OBSERVABLE", []))

    def test_building_the_timeline_never_writes_into_the_project(self) -> None:
        self.build_history()
        before = self.repo.git("status", "--porcelain", "--ignored")
        listing = sorted(str(p.relative_to(self.root)) for p in self.root.rglob("*") if ".git" not in p.parts)
        self.index()
        self.index(rebuild=True)
        self.assertEqual(self.repo.git("status", "--porcelain", "--ignored"), before)
        self.assertEqual(listing, sorted(str(p.relative_to(self.root)) for p in self.root.rglob("*") if ".git" not in p.parts))
        self.assertTrue(self.cache.exists())


class WaveHistoryAndQueryTests(TimelineCase):
    def test_per_wave_done_reconstruction_never_reopens_the_wave(self) -> None:
        self.lifecycle()
        done_commit = self.repo.head()
        self.repo.commit("feat: later project work", {"scripts/app.py": "print(1)\n"})
        self.repo.commit("fix: later artifact change", {"planning/tasks/TASK-1.yml": task("TASK-1", "done") + "detail: tweaked\n"})
        history = timeline.wave_history(self.root)
        self.assertEqual(history["observation_state"], "AVAILABLE")
        wave = history["waves"]["W1"]
        self.assertEqual(wave["commit"], done_commit[:12])
        self.assertEqual(wave["linked_artifact_commits"], 1)
        self.assertEqual(wave["project_activity_commits"], 1)
        # The transition itself is still an unchanged DONE event.
        self.assertTrue([e for e in self.events(wave="W1") if e["type"] == "wave.phase_changed" and e["title"].startswith("Wave W1 abgeschlossen")])

    def test_waves_without_a_recorded_transition_are_absent_not_inferred(self) -> None:
        self.repo.commit("chore: import", {"planning/lifecycle/process-state.yaml": process_state(W1="done")})
        # Registered already done (e.g. an import): the transition into DONE was never observed, so it is not invented.
        self.assertNotIn("W1", timeline.wave_history(self.root)["waves"])
        self.repo.commit("chore: later", {"planning/lifecycle/process-state.yaml": process_state(W1="done", W2="implementing")})
        self.repo.commit("feat: close W2", {"planning/lifecycle/process-state.yaml": process_state(W1="done", W2="done")})
        waves = timeline.wave_history(self.root)["waves"]
        self.assertIn("W2", waves)
        self.assertNotIn("W1", waves)

    def test_filters_paging_and_stability(self) -> None:
        self.lifecycle()
        self.repo.commit("feat: code", {"scripts/app.py": "print(1)\n"})
        everything = timeline.query(self.index(), {"limit": "200"})
        self.assertEqual(everything["total"], len(self.index()["events"]))
        self.assertEqual([e["event_id"] for e in timeline.query(self.index(), {"group": "decision", "limit": "50"})["events"]], [e["event_id"] for e in self.index()["events"] if e["type"].startswith("decision.")])
        self.assertTrue(all(e["lane"] == "unattributed" for e in self.events(lane="unattributed")))
        self.assertTrue(all(e["authority_class"] == "GIT_DERIVED" for e in self.events(authority="GIT_DERIVED")))
        first = timeline.query(self.index(), {"limit": "2"})
        second = timeline.query(self.index(), {"limit": "2", "cursor": first["next_cursor"]})
        self.assertTrue(set(e["event_id"] for e in first["events"]).isdisjoint(e["event_id"] for e in second["events"]))
        self.assertEqual([e["event_id"] for e in first["events"] + second["events"]], [e["event_id"] for e in self.index()["events"][:4]])
        newest_first = [e["occurred_epoch"] for e in self.index()["events"]]
        self.assertEqual(newest_first, sorted(newest_first, reverse=True))

    def test_response_validates_against_the_timeline_schema(self) -> None:
        self.lifecycle()
        self.repo.commit("feat: code (W1)", {"scripts/app.py": "print(1)\n"})
        schema = json.loads(SCHEMA.read_text(encoding="utf-8-sig"))
        response = timeline.query(self.index(), {"limit": "200"})
        self.assertEqual([error.message for error in Draft7Validator(schema).iter_errors(response)], [])
        for event in response["events"]:
            self.assertIn(event["authority_class"], timeline.AUTHORITY_CLASSES)
            if event["lane"] == "unattributed":
                self.assertTrue(all(e["derivation"] == "message_mention" for e in event["entities"]))


class ServiceTests(TimelineCase):
    def test_filter_validation_rejects_unknown_and_malformed_parameters(self) -> None:
        self.lifecycle()
        service = serve_project_board.TimelineService(self.root)
        self.assertEqual(service.valid_filters({"wave": ["W1"], "limit": ["20"]}), {"wave": "W1", "limit": "20"})
        for bad in ({"bogus": ["1"]}, {"limit": ["abc"]}, {"from": ["yesterday"]}, {"authority": ["X"]}, {"wave": ["W1", "W2"]}, {"entity": ["no-colon"]}, {"group": ["nonsense"]}):
            self.assertIsNone(service.valid_filters(bad), bad)
        service._thread.join(timeout=60)
        code, body = service.response({"limit": "5"})
        self.assertEqual((code, body["index"]["state"]), (200, "READY"))
        self.assertLessEqual(len(body["events"]), 5)


if __name__ == "__main__":
    unittest.main()
