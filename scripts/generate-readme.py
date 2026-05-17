#!/usr/bin/env python3
from __future__ import annotations

import argparse
import difflib
import os
import re
import subprocess
import sys
from pathlib import Path

from rich.console import Console
from rich.tree import Tree


ROOT = Path(__file__).resolve().parents[1]
README_PATH = ROOT / "README.md"

SECTION_MARKERS = {
    "skills": ("<!-- BEGIN GENERATED SECTION: skills -->", "<!-- END GENERATED SECTION: skills -->"),
    "commands": ("<!-- BEGIN GENERATED SECTION: commands -->", "<!-- END GENERATED SECTION: commands -->"),
    "repo_inventory": (
        "<!-- BEGIN GENERATED SECTION: repo_inventory -->",
        "<!-- END GENERATED SECTION: repo_inventory -->",
    ),
}


def run_git(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def tracked_paths() -> list[Path]:
    output = run_git("ls-files", "-z")
    return [Path(item) for item in output.split("\0") if item]


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    metadata: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        metadata[key.strip()] = value.strip().strip('"').strip("'")
    return metadata


def escape_cell(value: str) -> str:
    return value.replace("|", r"\|").replace("\n", " ").strip()


def tracked_skill_dirs(paths: list[Path]) -> list[Path]:
    skill_dirs = sorted({path.parent for path in paths if path.parts[:1] == ("skills",) and path.name == "SKILL.md"})
    return skill_dirs


def tracked_command_files(paths: list[Path]) -> list[Path]:
    command_files = []
    for path in paths:
        if path.parts[:1] != ("commands",):
            continue
        if path.name == ".gitkeep":
            continue
        if path.suffix != ".md":
            continue
        command_files.append(path)
    return sorted(command_files)


def summarize_command(path: Path) -> str:
    lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
    in_code_block = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block or not stripped or stripped.startswith("#"):
            continue
        return stripped
    return "No summary available."


def build_skills_section(paths: list[Path]) -> str:
    skill_dirs = tracked_skill_dirs(paths)
    rows = [
        "| Skill | Description |",
        "| --- | --- |",
    ]

    for skill_dir in skill_dirs:
        metadata = parse_frontmatter(ROOT / skill_dir / "SKILL.md")
        rows.append(
            "| `{skill}` | {description} |".format(
                skill=escape_cell(metadata.get("name", skill_dir.name)),
                description=escape_cell(metadata.get("description", "")),
            )
        )

    return "\n".join(
        [
            "> Generated from tracked `skills/*/SKILL.md` metadata.",
            "",
            *rows,
        ]
    )


def build_commands_section(paths: list[Path]) -> str:
    command_files = tracked_command_files(paths)
    if not command_files:
        return "> Generated from tracked `commands/*.md` files.\n\n_No tracked commands._"

    rows = [
        "| Command | Summary |",
        "| --- | --- |",
    ]
    for command_file in command_files:
        rows.append(
            "| `/{name}` | {summary} |".format(
                name=escape_cell(command_file.stem),
                summary=escape_cell(summarize_command(command_file)),
            )
        )

    return "\n".join(
        [
            "> Generated from tracked `commands/*.md` files.",
            "",
            *rows,
        ]
    )


def render_tree(lines: list[tuple[int, str]]) -> str:
    root = Tree(".")
    stack: list[tuple[int, Tree]] = [(-1, root)]

    for depth, label in lines:
        while stack and stack[-1][0] >= depth:
            stack.pop()
        branch = stack[-1][1].add(label)
        stack.append((depth, branch))

    width = max(88, max((len(label) + (depth * 4) for depth, label in lines), default=0) + 8)
    console = Console(width=width, color_system=None)
    with console.capture() as capture:
        console.print(root)
    return "\n".join(
        [
            "```text",
            capture.get().rstrip(),
            "```",
        ]
    )


def build_repo_inventory_section(paths: list[Path]) -> str:
    inventory: list[tuple[int, str]] = []
    for top_level in (".agents", ".claude-plugin", ".claude", ".codex-plugin"):
        entries = sorted(path for path in paths if path.parts[:1] == (top_level,))
        if not entries:
            continue
        inventory.append((0, f"{top_level}/"))
        for entry in entries:
            label = "/".join(entry.parts[1:])
            resolved = ROOT / entry
            if resolved.is_symlink():
                label = f"{label} -> {os.readlink(resolved)}"
            inventory.append((1, label))

    if (ROOT / ".githooks" / "pre-commit").exists():
        inventory.extend([(0, ".githooks/"), (1, "pre-commit")])

    workflow_files = sorted(path for path in paths if path.parts[:2] == (".github", "workflows"))
    if workflow_files:
        inventory.append((0, ".github/"))
        inventory.append((1, "workflows/"))
        for workflow in workflow_files:
            inventory.append((2, workflow.name))

    command_files = tracked_command_files(paths)
    inventory.append((0, "commands/"))
    for command_file in command_files:
        inventory.append((1, command_file.name))

    script_files = sorted(path for path in paths if path.parts[:1] == ("scripts",))
    inventory.append((0, "scripts/"))
    for script_file in script_files:
        inventory.append((1, script_file.name))

    skill_dirs = tracked_skill_dirs(paths)
    inventory.append((0, "skills/"))
    for skill_dir in skill_dirs:
        inventory.append((1, f"{skill_dir.name}/"))

    for root_file in ("pyproject.toml", "uv.lock"):
        if any(path == Path(root_file) for path in paths):
            inventory.append((0, root_file))

    return "\n".join(
        [
            "> Generated from tracked manifests, scripts, commands, and skills.",
            "",
            render_tree(inventory),
        ]
    )


def replace_section(readme: str, section_name: str, replacement: str) -> str:
    begin, end = SECTION_MARKERS[section_name]
    pattern = re.compile(
        rf"({re.escape(begin)}\n)(.*?)({re.escape(end)})",
        re.DOTALL,
    )
    if not pattern.search(readme):
        raise RuntimeError(f"Missing README markers for section: {section_name}")
    return pattern.sub(lambda match: f"{match.group(1)}{replacement}\n{match.group(3)}", readme, count=1)


def build_readme() -> str:
    readme = README_PATH.read_text(encoding="utf-8")
    paths = tracked_paths()

    replacements = {
        "skills": build_skills_section(paths),
        "commands": build_commands_section(paths),
        "repo_inventory": build_repo_inventory_section(paths),
    }

    for section_name, replacement in replacements.items():
        readme = replace_section(readme, section_name, replacement)
    return readme


def main() -> int:
    parser = argparse.ArgumentParser(description="Regenerate marker-based README sections.")
    parser.add_argument("--check", action="store_true", help="Fail if README.md is not up to date.")
    args = parser.parse_args()

    generated = build_readme()
    current = README_PATH.read_text(encoding="utf-8")

    if args.check:
        if generated != current:
            diff = difflib.unified_diff(
                current.splitlines(),
                generated.splitlines(),
                fromfile="README.md",
                tofile="README.md (generated)",
                lineterm="",
            )
            sys.stdout.write("\n".join(diff) + "\n")
            return 1
        return 0

    if generated != current:
        README_PATH.write_text(generated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
