"""Exercise preservation, preflight, imports and idempotency on either OS."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).with_name("bootstrap-agent-guidance.py"))
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def test_preserves_and_installs(self):
        with tempfile.TemporaryDirectory(prefix="guidance-") as tmp:
            root = Path(tmp)
            source = root / "source.md"
            source.write_text("shared preferences\n")
            codex, claude = root / "codex", root / "claude"
            claude.mkdir()
            old = claude / "CLAUDE.md"
            old.write_text("existing preferences\n")
            with self.assertRaises(ValueError):
                bootstrap.install(source, codex, claude)
            self.assertFalse((codex / "AGENTS.md").exists())
            bootstrap.install(source, codex, claude, replace=True, dry_run=True)
            self.assertEqual(old.read_text(), "existing preferences\n")
            bootstrap.install(source, codex, claude, replace=True)
            self.assertEqual(old.read_text(), f"@{source.resolve().as_posix()}\n")
            backups = list(claude.glob("guidance-backups/*/CLAUDE.md"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), "existing preferences\n")
            bootstrap.install(source, codex, claude)
            self.assertEqual(len(list(claude.glob("guidance-backups/*/CLAUDE.md"))), 1)
            opencode = root / "opencode"
            opencode.mkdir()
            config = opencode / "opencode.json"
            config.write_text(json.dumps({"theme": "existing", "instructions": ["other.md"]}))
            bootstrap.install(source, codex, claude, replace=True, opencode_home=opencode)
            data = json.loads(config.read_text())
            self.assertEqual(data["theme"], "existing")
            self.assertEqual(data["instructions"], ["other.md", source.resolve().as_posix()])
            bootstrap.install(source, codex, claude, opencode_home=opencode)
            (codex / "AGENTS.override.md").write_text("override")
            with self.assertRaises(ValueError):
                bootstrap.install(source, codex, claude)

    def test_paths_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix="guidance space ") as tmp:
            root = Path(tmp)
            source = root / "private context" / "AGENTS.md"
            source.parent.mkdir()
            source.write_text("shared preferences\n")
            codex = root / "codex home"
            claude = root / "claude home"
            opencode = root / "opencode home"
            bootstrap.install(source, codex, claude, opencode_home=opencode)
            self.assertEqual((claude / "CLAUDE.md").read_text(), f"@{source.resolve().as_posix()}\n")
            self.assertEqual((codex / "AGENTS.md").resolve(), source.resolve())
            self.assertIn(source.resolve().as_posix(), json.loads((opencode / "opencode.json").read_text())["instructions"])

    def test_layered_guidance_is_atomic_preserving_and_platform_specific(self):
        with tempfile.TemporaryDirectory(prefix="layered guidance ") as tmp:
            root = Path(tmp)
            common = root / "private context" / "common.md"
            overlay = root / "private context" / "macos.md"
            common.parent.mkdir()
            common.write_text("# Common\n\nshared rule\n")
            overlay.write_text("# macOS\n\nmac-only rule\n")
            registry = root / "private context" / "repositories.json"
            registry.write_text(json.dumps({
                "version": 1,
                "repositories": [{
                    "name": "SkillPort", "source": "owner/SkillPort", "role": "Distribution.",
                    "checkout": {"kind": "skillport-root"}, "refresh": True, "skills": True,
                }],
            }))
            codex, claude, opencode = root / "codex", root / "claude", root / "opencode"
            codex.mkdir()
            old = codex / "AGENTS.md"
            old.write_text("useful local rule\n")
            with self.assertRaises(ValueError):
                bootstrap.install_layered(common, overlay, "macos", codex, claude)
            bootstrap.install_layered(common, overlay, "macos", codex, claude,
                                      replace=True, opencode_home=opencode, registry=registry)
            rendered = old.read_text()
            self.assertTrue(rendered.startswith(bootstrap.GENERATED_MARKER))
            self.assertIn("shared rule", rendered)
            self.assertIn("mac-only rule", rendered)
            self.assertIn("**SkillPort**: Distribution.", rendered)
            self.assertEqual(len(list(codex.glob("guidance-backups/*/AGENTS.md"))), 1)
            self.assertEqual(list(codex.glob("guidance-backups/*/AGENTS.md"))[0].read_text(), "useful local rule\n")
            self.assertEqual((claude / "CLAUDE.md").read_text(), f"@{common.resolve().as_posix()}\n@{overlay.resolve().as_posix()}\n")
            self.assertEqual(json.loads((opencode / "opencode.json").read_text())["instructions"],
                             [common.resolve().as_posix(), overlay.resolve().as_posix()])
            common.write_text("# Common\n\nupdated shared rule\n")
            bootstrap.install_layered(common, overlay, "macos", codex, claude,
                                      opencode_home=opencode, registry=registry)
            self.assertIn("updated shared rule", old.read_text())
            self.assertEqual(len(list(codex.glob("guidance-backups/*/AGENTS.md"))), 1)


if __name__ == "__main__":
    unittest.main()
