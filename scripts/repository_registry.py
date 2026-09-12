#!/usr/bin/env python3
"""Validate and query the private cross-device repository registry."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


NAME = re.compile(r"^[A-Za-z0-9._-]+$")
SOURCE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
CHECKOUT_KINDS = {"skillport-root", "private-context-root", "skillport-sibling", "none"}


def load_registry(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("version") != 1:
        raise ValueError("Repository registry version must be 1")
    repositories = data.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise ValueError("Repository registry must contain repositories")
    seen_names: set[str] = set()
    seen_sources: set[str] = set()
    for entry in repositories:
        if not isinstance(entry, dict):
            raise ValueError("Each repository entry must be an object")
        name, source, role = entry.get("name"), entry.get("source"), entry.get("role")
        if not isinstance(name, str) or not NAME.fullmatch(name) or name in seen_names:
            raise ValueError("Repository names must be unique safe identifiers")
        if not isinstance(source, str) or not SOURCE.fullmatch(source) or source in seen_sources:
            raise ValueError("Repository sources must be unique owner/name shorthands")
        if not isinstance(role, str) or not role.strip() or any(character in role for character in "\r\n"):
            raise ValueError("Repository roles must be nonempty single-line text")
        checkout = entry.get("checkout")
        if not isinstance(checkout, dict) or checkout.get("kind") not in CHECKOUT_KINDS:
            raise ValueError("Each repository needs a supported checkout kind")
        directory = checkout.get("directory", "")
        if checkout["kind"] == "skillport-sibling":
            if not isinstance(directory, str) or not NAME.fullmatch(directory):
                raise ValueError("Sibling checkouts need a safe directory name")
        elif directory not in (None, ""):
            raise ValueError("Only sibling checkouts may define a directory")
        if not isinstance(entry.get("refresh"), bool) or not isinstance(entry.get("skills"), bool):
            raise ValueError("refresh and skills must be booleans")
        seen_names.add(name)
        seen_sources.add(source)
    return repositories


def render_overview(repositories: list[dict]) -> str:
    lines = ["## Repository roles", ""]
    lines.extend(f"- **{entry['name']}**: {entry['role']}" for entry in repositories)
    lines.extend([
        "",
        "This overview is generated from the canonical private repository registry. "
        "Operational install commands remain in SkillPort.",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("registry", type=Path)
    parser.add_argument("command", choices=("skills", "checkouts", "overview", "validate"))
    args = parser.parse_args()
    repositories = load_registry(args.registry)
    if args.command == "skills":
        for entry in repositories:
            if entry["skills"]:
                print(entry["source"])
    elif args.command == "checkouts":
        for entry in repositories:
            checkout = entry["checkout"]
            if entry["refresh"] and checkout["kind"] != "none":
                print("\t".join((entry["name"], checkout["kind"], checkout.get("directory", ""))))
    elif args.command == "overview":
        print(render_overview(repositories))


if __name__ == "__main__":
    main()
