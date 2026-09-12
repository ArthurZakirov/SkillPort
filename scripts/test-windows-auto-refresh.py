from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
REFRESH = (ROOT / "scripts" / "skillport-auto-refresh.ps1").read_text(encoding="utf-8")
INSTALLER = (ROOT / "scripts" / "install-windows-auto-refresh.ps1").read_text(encoding="utf-8")
PUBLIC_FILES = REFRESH + "\n" + INSTALLER + "\n" + (ROOT / "config" / "auto-refresh.windows.example.json").read_text(encoding="utf-8")


class WindowsAutoRefreshContractTests(unittest.TestCase):
    def test_portable_environment_contract(self):
        self.assertIn("SKILLPORT_ROOT", PUBLIC_FILES)
        self.assertIn("PRIVATE_CONTEXT_ROOT", PUBLIC_FILES)
        rejected_alias = "SKILLPORT_PRIVATE_" + "CONTEXT_ROOT"
        self.assertNotIn(rejected_alias, PUBLIC_FILES)
        self.assertIn("skillport\\repositories.json", REFRESH)
        self.assertIn("agent-guidance\\common.md", REFRESH)
        self.assertIn("agent-guidance\\windows-wsl.md", REFRESH)
        self.assertIn("Read-RepositoryRegistry", REFRESH)

    def test_task_scheduler_catch_up_contract(self):
        for fragment in (
            "<LogonTrigger>",
            "<Interval>PT15M</Interval>",
            "<Duration>P1D</Duration>",
            "<DaysInterval>1</DaysInterval>",
            "<StartWhenAvailable>true</StartWhenAvailable>",
            "<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>",
            "<RunLevel>LeastPrivilege</RunLevel>",
        ):
            self.assertIn(fragment, INSTALLER)

    def test_destructive_git_operations_are_absent(self):
        forbidden = (
            r"\badd\b",
            r"\bcommit\b",
            r"\bstash\b",
            r"\brebase\b",
            r"\breset\b",
            r"\bclean\b",
            r"force-with-lease",
            r"force-push",
        )
        git_argument_text = "\n".join(
            line for line in REFRESH.splitlines() if "GitBin" in line or "Get-GitValue" in line
        )
        for pattern in forbidden:
            self.assertIsNone(re.search(pattern, git_argument_text, flags=re.IGNORECASE), pattern)
        self.assertIn("'merge', '--ff-only'", REFRESH)
        self.assertIn("'push', '--quiet'", REFRESH)

    def test_lock_logging_and_public_gate_contract(self):
        self.assertIn("FileShare]::None", REFRESH)
        self.assertRegex(REFRESH, r"if \(\$null -ne \$LockStream\) \{\s*\$LockStream\.Dispose\(\)\s*if \(Test-Path")
        self.assertIn("$MaximumLogBytes = 131072", REFRESH)
        self.assertIn("public_release_review_required", REFRESH)
        self.assertIn("personal_data_scan_passed", REFRESH)
        self.assertIn("credential_scan_passed", REFRESH)
        self.assertIn("@('diff', '--name-only', \"$Upstream..HEAD\"", REFRESH)
        self.assertNotIn("@('log', '--format='", REFRESH)
        self.assertNotRegex(REFRESH, r"Write-Status[^\n]*(Output|ErrorPath)")


if __name__ == "__main__":
    unittest.main()
