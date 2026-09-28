import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("skillport_cli", Path(__file__).with_name("skillport.py"))
skillport_cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skillport_cli)


class SkillPortCatalogTests(unittest.TestCase):
    def test_catalog_enriches_skills_with_frontmatter_description(self):
        with tempfile.TemporaryDirectory() as tmp:
            skill_dir = Path(tmp) / "demo-skill"
            skill_dir.mkdir()
            (skill_dir / "SKILL.md").write_text(
                '---\nname: demo-skill\ndescription: "Use when testing catalog discovery."\n---\n\n# Demo\n',
                encoding="utf-8",
            )
            catalog = skillport_cli.build_catalog([
                {"name": "demo-skill", "path": str(skill_dir), "scope": "global"}
            ])

        self.assertEqual(catalog[0]["description"], "Use when testing catalog discovery.")
        self.assertEqual(catalog[0]["frontmatterName"], "demo-skill")
        self.assertTrue(catalog[0]["skillFile"].endswith("demo-skill/SKILL.md"))

    def test_missing_description_is_reported_without_dropping_skill(self):
        with tempfile.TemporaryDirectory() as tmp:
            skill_dir = Path(tmp) / "demo-skill"
            skill_dir.mkdir()
            (skill_dir / "SKILL.md").write_text("---\nname: demo-skill\n---\n", encoding="utf-8")
            catalog = skillport_cli.build_catalog([{"name": "demo-skill", "path": str(skill_dir)}])

        self.assertEqual(catalog[0]["description"], "")
        self.assertIn("metadataError", catalog[0])
