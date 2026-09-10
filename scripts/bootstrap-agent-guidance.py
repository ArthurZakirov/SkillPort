#!/usr/bin/env python3
"""Install global entrypoints to a reconciled, repo-backed AGENTS.md."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil


def install(source: Path, codex_home: Path, claude_home: Path,
            replace: bool = False, dry_run: bool = False) -> None:
    source = source.resolve(strict=True)
    if not source.is_file() or not source.read_text(encoding="utf-8").strip():
        raise ValueError("Source must be a nonempty UTF-8 guidance file")
    # A plain one-line Claude import is unambiguous for these paths.
    if any(c.isspace() for c in str(source)):
        raise ValueError("Use a guidance source path without whitespace")
    codex = codex_home / "AGENTS.md"
    claude = claude_home / "CLAUDE.md"
    override = codex_home / "AGENTS.override.md"
    if override.exists() and override.read_text(encoding="utf-8").strip():
        raise ValueError(f"Reconcile the overriding global guidance first: {override}")
    wrapper = ("Before responding or taking action, read the complete shared personal "
               f"instructions at `{source.as_posix()}` and follow them for this task. "
               "If the file cannot be read, report the missing source. "
               "Edit that repository source when updating these rules, not this wrapper.\n")
    imports = f"@{source.as_posix()}\n"
    plans = [(codex, wrapper, os.name != "nt"), (claude, imports, False)]
    pending = []
    for destination, content, link in plans:
        if destination.resolve() == source:
            if link and destination.is_symlink():
                continue
            raise ValueError(f"Destination must not overwrite source: {destination}")
        exists = destination.exists() or destination.is_symlink()
        if destination.is_dir():
            raise ValueError(f"Expected a file, found a directory: {destination}")
        if exists and not link and not destination.is_symlink():
            if destination.read_text(encoding="utf-8") == content:
                continue
        if exists and not replace:
            raise ValueError(f"Reconcile existing preferences before --replace-existing: {destination}")
        pending.append((destination, content, link, exists))
    # Preflight every destination before mutating either file.
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    for destination, content, link, exists in pending:
        print(f"{'Would install' if dry_run else 'Install'} {'symlink' if link else 'reference'}: {destination}")
        if dry_run:
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if exists:
            backup = destination.parent / "guidance-backups" / stamp / destination.name
            backup.parent.mkdir(parents=True, exist_ok=False)
            if destination.is_dir():
                raise ValueError(f"Expected a file, found a directory: {destination}")
            if destination.is_symlink():
                # Retain the previous link itself, including a dangling link.
                backup.symlink_to(destination.resolve())
            else:
                shutil.copy2(destination, backup)
            destination.unlink()
        if link:
            destination.symlink_to(source)
        else:
            destination.write_text(content, encoding="utf-8", newline="\n")
        assert destination.read_text(encoding="utf-8") == (source.read_text(encoding="utf-8") if link else content)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--codex-home", type=Path, default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")))
    parser.add_argument("--claude-home", type=Path, default=Path.home() / ".claude")
    parser.add_argument("--replace-existing", action="store_true", help="Only after merging old preferences; originals are backed up")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    install(args.source, args.codex_home, args.claude_home, args.replace_existing, args.dry_run)


if __name__ == "__main__":
    main()
