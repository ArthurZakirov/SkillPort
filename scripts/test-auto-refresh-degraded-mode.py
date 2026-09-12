from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
REFRESH_SCRIPT = ROOT / "scripts" / "skillport-auto-refresh.sh"


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, check=True)


def initialize_checkout(root: Path, name: str) -> Path:
    remote = root / f"{name}.git"
    checkout = root / name
    run("git", "init", "--bare", str(remote))
    run("git", "init", "-b", "main", str(checkout))
    run("git", "config", "user.name", "SkillPort Test", cwd=checkout)
    run("git", "config", "user.email", "skillport-test" + "@" + "invalid.example", cwd=checkout)
    (checkout / ".keep").write_text("baseline\n", encoding="utf-8")
    run("git", "add", ".keep", cwd=checkout)
    run("git", "commit", "-m", "Baseline", cwd=checkout)
    run("git", "remote", "add", "origin", str(remote), cwd=checkout)
    run("git", "push", "-u", "origin", "main", cwd=checkout)
    return checkout


class AutoRefreshDegradedModeTests(unittest.TestCase):
    def exercise(self, gh_mode: str) -> str:
        with tempfile.TemporaryDirectory(prefix="skillport-degraded-") as temporary:
            root = Path(temporary)
            skillport = initialize_checkout(root, "SkillPort")
            private = initialize_checkout(root, "PrivateContext")
            scripts = skillport / "scripts"
            scripts.mkdir()
            shutil.copy2(REFRESH_SCRIPT, scripts / REFRESH_SCRIPT.name)
            (scripts / "bootstrap-agent-guidance.py").write_text("raise SystemExit(0)\n", encoding="utf-8")
            (scripts / "repository_registry.py").write_text(textwrap.dedent("""
                import sys
                if sys.argv[2] == "skills":
                    print("owner/example")
            """), encoding="utf-8")
            sync = scripts / "skillport-sync.sh"
            sync.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            sync.chmod(0o755)
            guidance = private / "agent-guidance"
            registry = private / "skillport"
            guidance.mkdir()
            registry.mkdir()
            (guidance / "common.md").write_text("common\n", encoding="utf-8")
            (guidance / "macos.md").write_text("macos\n", encoding="utf-8")
            (registry / "repositories.json").write_text('{"version":1,"repositories":[]}\n', encoding="utf-8")
            run("git", "add", "scripts", cwd=skillport)
            run("git", "commit", "-m", "Add updater fixtures", cwd=skillport)
            run("git", "push", cwd=skillport)
            run("git", "add", "agent-guidance", "skillport", cwd=private)
            run("git", "commit", "-m", "Add private fixtures", cwd=private)
            run("git", "push", cwd=private)
            (skillport / "payload.txt").write_text("reviewed generic change\n", encoding="utf-8")
            run("git", "add", "payload.txt", cwd=skillport)
            run("git", "commit", "-m", "Ahead change", cwd=skillport)
            approved_head = run("git", "rev-parse", "HEAD", cwd=skillport).stdout.strip()

            config = root / "auto-refresh.conf"
            config.write_text(f"SKILLPORT_PUSH_PUBLIC_REPO={skillport}|{approved_head}\n", encoding="utf-8")
            state = root / "state"
            fake_node = root / "node"
            fake_node.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            fake_node.chmod(0o755)
            fake_gh = root / "gh"
            if gh_mode != "missing":
                if gh_mode == "verified":
                    fake_gh.write_text("#!/bin/bash\nprintf 'PUBLIC\\n'\n", encoding="utf-8")
                else:
                    status = "4" if gh_mode == "unauthenticated" else "75"
                    fake_gh.write_text(f"#!/bin/bash\nexit {status}\n", encoding="utf-8")
                fake_gh.chmod(0o755)

            environment = {
                "HOME": str(root / "home"),
                "SKILLPORT_ROOT": str(skillport),
                "PRIVATE_CONTEXT_ROOT": str(private),
                "SKILLPORT_AUTO_REFRESH_CONFIG": str(config),
                "SKILLPORT_STATE_DIR": str(state),
                "SKILLPORT_NODE_BIN": str(fake_node),
                "SKILLPORT_NPX_BIN": str(fake_node),
                "SKILLPORT_PYTHON_BIN": sys.executable,
            }
            if gh_mode != "missing":
                environment["SKILLPORT_GH_BIN"] = str(fake_gh)
            completed = subprocess.run(
                ["/bin/bash", str(scripts / REFRESH_SCRIPT.name)],
                env=environment,
                text=True,
                capture_output=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            log = (state / "refresh.log").read_text(encoding="utf-8")
            self.assertIn("refresh_complete", log)
            self.assertIn("global_guidance refresh ok", log)
            self.assertIn("global_skills synchronize ok", log)
            if gh_mode == "verified":
                self.assertIn("credential_scan_passed", log)
                self.assertIn("personal_data_scan_passed", log)
                self.assertIn("ordinary_push ok", log)
                self.assertEqual(run("git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}", cwd=skillport).stdout.strip(), "0\t0")
            else:
                self.assertIn("push_skipped visibility_unverified", log)
                self.assertEqual(run("git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}", cwd=skillport).stdout.strip(), "1\t0")
            return log

    def test_missing_gh_keeps_core_refresh_operational(self):
        self.exercise("missing")

    def test_unauthenticated_gh_keeps_core_refresh_operational(self):
        self.exercise("unauthenticated")

    def test_transient_gh_failure_keeps_core_refresh_operational(self):
        self.exercise("transient")

    def test_verified_visibility_preserves_push_gates(self):
        self.exercise("verified")


if __name__ == "__main__":
    unittest.main()
