"""Exercise preservation, preflight, imports and idempotency on either OS."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

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


if __name__ == "__main__":
    unittest.main()
