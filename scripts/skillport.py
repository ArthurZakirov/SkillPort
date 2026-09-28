#!/usr/bin/env python3
"""Small stable CLI for SkillPort-local skill discovery helpers."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


def parse_frontmatter(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
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


def list_installed_skills(scope: str, agents: list[str] | None = None) -> list[dict]:
    command = ["npx", "skills", "ls"]
    if scope == "global":
        command.append("--global")
    if agents:
        command.extend(["--agent", *agents])
    command.append("--json")
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    payload = json.loads(result.stdout)
    if not isinstance(payload, list):
        raise RuntimeError("skills ls --json returned a non-list payload")
    return payload


def build_catalog(skills: list[dict]) -> list[dict]:
    catalog: list[dict] = []
    for skill in skills:
        item = dict(skill)
        skill_dir = Path(str(skill.get("path", "")))
        skill_file = skill_dir / "SKILL.md"
        item["skillFile"] = str(skill_file)
        try:
            metadata = parse_frontmatter(skill_file)
            item["description"] = metadata.get("description", "")
            if metadata.get("name"):
                item["frontmatterName"] = metadata["name"]
            if not item["description"]:
                item["metadataError"] = "missing description in SKILL.md frontmatter"
        except (OSError, UnicodeError) as exc:
            item["description"] = ""
            item["metadataError"] = str(exc)
        catalog.append(item)
    return catalog


def render_text(catalog: list[dict]) -> str:
    lines = []
    for item in catalog:
        description = item.get("description") or "(no description)"
        lines.append(f"{item.get('name', '(unnamed)')}: {description}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    catalog_parser = subparsers.add_parser("catalog", help="List installed skills with frontmatter descriptions.")
    catalog_parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    catalog_parser.add_argument(
        "--scope",
        choices=("global", "project"),
        default="global",
        help="Read globally installed skills by default; use project for the current project scope.",
    )
    catalog_parser.add_argument("--agent", action="append", default=[], help="Optional skills CLI agent filter.")
    args = parser.parse_args()

    if args.command == "catalog":
        try:
            catalog = build_catalog(list_installed_skills(args.scope, args.agent))
        except (subprocess.CalledProcessError, json.JSONDecodeError, RuntimeError) as exc:
            print(f"skillport catalog failed: {exc}", file=sys.stderr)
            return 1
        if args.json:
            json.dump(catalog, sys.stdout, indent=2, ensure_ascii=False)
            sys.stdout.write("\n")
        else:
            print(render_text(catalog))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
