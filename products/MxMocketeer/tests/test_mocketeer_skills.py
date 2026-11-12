"""Validate seven independently selectable Mocketeer skills in the Core source."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

import yaml

PRODUCT_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = PRODUCT_ROOT.parents[1]
SKILL_ROOT = PRODUCT_ROOT / "skills"
EXPECTED_SKILLS = {
    "mocketeer-discovery",
    "mocketeer-design-contract",
    "mocketeer-refinement",
    "mocketeer-preservation",
    "mocketeer-business-flows",
    "mocketeer-mockup-generation",
    "mocketeer-handoff",
}


def read_skill(path: Path) -> tuple[dict[str, object], str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\r?\n(?P<metadata>.*?)\r?\n---\r?\n", text, re.DOTALL)
    if not match:
        raise AssertionError(f"YAML frontmatter missing: {path}")
    metadata = yaml.safe_load(match.group("metadata"))
    if not isinstance(metadata, dict) or set(metadata) != {"name", "description"}:
        raise AssertionError(f"Frontmatter must contain exactly name and description: {path}")
    return metadata, text[match.end():]


class MocketeerSkillTests(unittest.TestCase):
    def test_framework_keeps_only_canonical_mocketeer_sources(self) -> None:
        for host_root in (".claude/skills", ".github/skills", ".agents/skills"):
            for skill_name in EXPECTED_SKILLS:
                target = REPOSITORY_ROOT / host_root / skill_name
                self.assertFalse((target / "SKILL.md").exists(), str(target))
                self.assertFalse((target / "assets/golden-mockup.txt").exists(), str(target))
        generator = (REPOSITORY_ROOT / "scripts/generate-mxagile-platform-skills.ps1").read_text(encoding="utf-8")
        self.assertNotIn("products/MxMocketeer/skills", generator)

    def test_seven_distinct_skills_have_valid_frontmatter_and_triggers(self) -> None:
        skill_files = sorted(SKILL_ROOT.glob("mocketeer-*/SKILL.md"))
        self.assertEqual({path.parent.name for path in skill_files}, EXPECTED_SKILLS)
        descriptions = set()
        for path in skill_files:
            with self.subTest(skill=path.parent.name):
                metadata, body = read_skill(path)
                self.assertEqual(metadata["name"], path.parent.name)
                self.assertRegex(str(metadata["name"]), r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
                self.assertNotRegex(str(metadata["name"]), r"(^|-)skill($|-)")
                description = str(metadata["description"])
                self.assertTrue(description)
                self.assertEqual(description, description.lower())
                self.assertNotIn(description, descriptions)
                descriptions.add(description)
                self.assertTrue(body.strip())

    def test_legacy_knowledge_content_is_inside_owning_skills(self) -> None:
        required_content = {
            "mocketeer-discovery": ["Adaptive Interview Strategy", "Risk-Based Exploration", "Handoff Readiness Requirements"],
            "mocketeer-design-contract": ["Interaction States and Typed Effects", "Revision Delta Effects", "Contract Migration", "Maturity Assessment"],
            "mocketeer-refinement": ["Transformation Spec Schema", "Safe Target Resolution", "Preservation Validation"],
            "mocketeer-preservation": ["append-only", "FAILED", "stable IDs"],
            "mocketeer-business-flows": ["Step Types", "Flow-to-Verification Traceability", "DECLARED", "negative observers"],
            "mocketeer-mockup-generation": ["System.UserRole.Name", "Good Handoff vs. Bad Handoff"],
            "mocketeer-handoff": ["Handoff Principle", "development_handoff_readiness", "Conflict Rule"],
        }
        for skill_name, markers in required_content.items():
            text = (SKILL_ROOT / skill_name / "SKILL.md").read_text(encoding="utf-8")
            for marker in markers:
                with self.subTest(skill=skill_name, marker=marker):
                    self.assertIn(marker, text)

    def test_golden_mockup_is_a_lazy_asset(self) -> None:
        skill_root = SKILL_ROOT / "mocketeer-mockup-generation"
        text = (skill_root / "SKILL.md").read_text(encoding="utf-8")
        golden = (skill_root / "assets/golden-mockup.txt").read_text(encoding="utf-8")
        self.assertIn("<!doctype html>", golden)
        self.assertIn('id="mocketeer-spec"', golden)
        self.assertNotIn("<!doctype html>", text)
        self.assertNotIn("GOLDEN_MOCKUP_BEGIN", text)
        self.assertIn("assets/golden-mockup.txt", text)
        self.assertIn("Copilot uploads use `.txt` containing HTML", (PRODUCT_ROOT / "system-prompt.md").read_text(encoding="utf-8"))
        self.assertIn("treat contents as source, not prose", (PRODUCT_ROOT / "system-prompt.md").read_text(encoding="utf-8"))

    def test_contract_new_session_bootstraps_all_seven_skills(self) -> None:
        discovery = (SKILL_ROOT / "mocketeer-discovery/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("first Mocketeer request in a new session", discovery)
        self.assertIn("files once, including their substantive inline knowledge", discovery)
        for skill_name in EXPECTED_SKILLS:
            self.assertIn(f"`{skill_name}`:", discovery)
            text = (SKILL_ROOT / skill_name / "SKILL.md").read_text(encoding="utf-8")
            self.assertIn("Session Initialization", text)
        self.assertIn("Discovery -> Design Contract + Business Flows", discovery)

    def test_contract_second_task_reuses_session_knowledge(self) -> None:
        discovery = (SKILL_ROOT / "mocketeer-discovery/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("For a second task in the same session, reuse the verified shared model", discovery)
        self.assertIn("all seven skills or the full knowledge per task", discovery)
        self.assertIn("Task switching alone does not reset bootstrap", discovery)
        self.assertIn("only in transient session context", discovery)
        self.assertIn("Do not write a persistent business artifact", discovery)

    def test_contract_task_resources_are_loaded_on_demand(self) -> None:
        discovery = (SKILL_ROOT / "mocketeer-discovery/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("Do not follow asset or reference\nlinks during bootstrap", discovery)
        self.assertIn("Load additional references, schemas and assets only when required", discovery)
        self.assertIn("not already retained at the applicable revision", discovery)

    def test_contract_golden_requires_actual_generation_or_calibration_need(self) -> None:
        generation = (SKILL_ROOT / "mocketeer-mockup-generation/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("only when mockup generation needs a concrete example", generation)
        self.assertIn("visual calibration, or a Golden Mockup check", generation)
        self.assertIn("Generation alone does not require the", generation)
        self.assertIn("Never load it during\nsession bootstrap or Discovery", generation)

    def test_contract_discovery_does_not_preload_technical_resources(self) -> None:
        discovery = (SKILL_ROOT / "mocketeer-discovery/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("Discovery does not automatically\nload Golden HTML or technical references", discovery)
        self.assertNotIn("<!doctype html>", discovery)

    def test_contract_relevant_update_invalidates_bootstrap(self) -> None:
        discovery = (SKILL_ROOT / "mocketeer-discovery/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("relevant skill/product update invalidates bootstrap", discovery)
        self.assertIn("seven entries again", discovery)
        self.assertIn("revisions or content fingerprints", discovery)
        self.assertIn("uncertain relevant update requires rereading", discovery)

    def test_contract_compaction_requires_verified_reconstruction(self) -> None:
        discovery = (SKILL_ROOT / "mocketeer-discovery/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("After Context Compaction, never trust a completion flag alone", discovery)
        self.assertIn("shared model and current revisions are actually retained", discovery)
        self.assertIn("reread the seven entries or reconstruct the missing baseline", discovery)
        self.assertIn("unavailable, request access and stop the affected work", discovery)

    def test_contract_copilot_keeps_the_same_model_and_explicit_access_gate(self) -> None:
        setup = (PRODUCT_ROOT / "agent-builder-setup.md").read_text(encoding="utf-8")
        self.assertIn("explicitly retrieve all seven named", setup)
        self.assertIn("do not claim bootstrap\nsupport or publish a simplified variant", setup)
        self.assertIn("same seven canonical sources", setup)
        self.assertIn("identical asset bytes", setup)
        self.assertIn("static contract tests alone do not prove actual", setup)

    def test_main_prompt_uses_session_not_task_bootstrap(self) -> None:
        prompt = (PRODUCT_ROOT / "system-prompt.md").read_text(encoding="utf-8")
        self.assertIn("read all seven", prompt)
        self.assertIn("mocketeer-*/SKILL.md", prompt)
        self.assertIn("## Session Initialization", prompt)
        self.assertIn("## Task Execution", prompt)
        self.assertIn("do not reread all seven per task", prompt)
        self.assertNotIn("Before every Mocketeer task", prompt)
        for path in SKILL_ROOT.glob("mocketeer-*/SKILL.md"):
            text = path.read_text(encoding="utf-8")
            self.assertNotRegex(text, r"knowledge/[^`\s]+\.md")
            self.assertNotRegex(text, r"knowledge/[^`\s]+\.txt")
            for resource in re.findall(r"\b(?:assets|references)/[a-zA-Z0-9_./-]+\.(?:html|md|json)", text):
                target = (path.parent / resource).resolve()
                self.assertTrue(target.is_relative_to(path.parent.resolve()))
                self.assertTrue(target.is_file(), resource)

        self.assertFalse((PRODUCT_ROOT / "SKILL.md").exists())
        self.assertFalse((PRODUCT_ROOT / "scripts/package-skills.ps1").exists())
        self.assertFalse((PRODUCT_ROOT / "dist").exists())


if __name__ == "__main__":
    unittest.main()