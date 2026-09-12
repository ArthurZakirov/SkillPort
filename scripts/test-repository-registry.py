import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("registry", Path(__file__).with_name("repository_registry.py"))
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


class RepositoryRegistryTests(unittest.TestCase):
    def test_valid_registry_drives_skills_checkouts_and_overview(self):
        data = {
            "version": 1,
            "repositories": [
                {
                    "name": "SkillPort",
                    "source": "owner/SkillPort",
                    "role": "Skill distribution infrastructure.",
                    "checkout": {"kind": "skillport-root"},
                    "refresh": True,
                    "skills": True,
                },
                {
                    "name": "Product",
                    "source": "owner/Product",
                    "role": "Application source.",
                    "checkout": {"kind": "skillport-sibling", "directory": "Product"},
                    "refresh": True,
                    "skills": False,
                },
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "repositories.json"
            path.write_text(json.dumps(data))
            loaded = registry.load_registry(path)
        self.assertEqual([entry["source"] for entry in loaded if entry["skills"]], ["owner/SkillPort"])
        self.assertIn("**Product**: Application source.", registry.render_overview(loaded))

    def test_duplicate_and_unsafe_entries_fail(self):
        entry = {
            "name": "unsafe/name",
            "source": "owner/repo",
            "role": "Role",
            "checkout": {"kind": "none"},
            "refresh": False,
            "skills": False,
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "repositories.json"
            path.write_text(json.dumps({"version": 1, "repositories": [entry]}))
            with self.assertRaises(ValueError):
                registry.load_registry(path)


if __name__ == "__main__":
    unittest.main()
