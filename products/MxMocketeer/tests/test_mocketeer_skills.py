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
            "mocketeer-mockup-generation": ["System.UserRole.Name", "Good Handoff vs. Bad Handoff", "<!doctype html>", "id=\"mocketeer-spec\""],
            "mocketeer-handoff": ["Handoff Principle", "development_handoff_readiness", "Conflict Rule"],
        }
        for skill_name, markers in required_content.items():
            text = (SKILL_ROOT / skill_name / "SKILL.md").read_text(encoding="utf-8")
            for marker in markers:
                with self.subTest(skill=skill_name, marker=marker):
                    self.assertIn(marker, text)

    def test_main_prompt_loads_all_skills_without_external_knowledge_files(self) -> None:
        prompt = (PRODUCT_ROOT / "system-prompt.md").read_text(encoding="utf-8")
        self.assertIn("read all seven", prompt)
        self.assertIn("mocketeer-*/SKILL.md", prompt)
        for path in SKILL_ROOT.glob("mocketeer-*/SKILL.md"):
            text = path.read_text(encoding="utf-8")
            self.assertNotRegex(text, r"(?:references|knowledge)/[^`\s]+\.md")
            self.assertNotRegex(text, r"knowledge/[^`\s]+\.txt")

        self.assertFalse((PRODUCT_ROOT / "SKILL.md").exists())
        self.assertFalse((PRODUCT_ROOT / "scripts/package-skills.ps1").exists())
        self.assertFalse((PRODUCT_ROOT / "dist").exists())
        self.assertFalse((PRODUCT_ROOT / "references").exists())


if __name__ == "__main__":
    unittest.main()