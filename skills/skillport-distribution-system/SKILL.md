---
name: skillport-distribution-system
description: Use when packaging, publishing, or updating a public agent-skill repository so it can be installed across machines, repos and harnesses including Codex, Claude Code and OpenCode, using shared local skill storage.
---

# SkillPort Distribution System

## Purpose

Package reusable agent skills once so they can be installed and shared across machines, people, repos and harnesses including Codex, Claude Code and OpenCode, using shared local skill storage.

## Use This Workflow

For a new skill-pack repo:

1. Pick the repo product name, slug, and promise before packaging files.
2. Run `scripts/create-agent-skill-repo.sh` from the SkillPort repo when starting a new skill pack.
3. Inspect generated placeholders, plugin manifests, README, examples, schemas, and setup script.
4. Add or update the real skills.
5. Add the GitHub repo shorthand to a SkillPort manifest, usually `config/skill-repos.local.yaml`.
6. Validate locally with:

```bash
npx skills add /path/to/generated/repo --list
```

7. Push to GitHub.
8. Validate from GitHub:

```bash
npx skills add https://github.com/OWNER/REPO --list
```

For normal cross-machine syncing, use:

```bash
./scripts/skillport-sync.sh
```

This reruns `npx skills add <repo> --skill '*' -a codex -g -y` for every repo listed in the selected manifest, then runs `npx skills update -g -y`.

Keep personal repo lists in ignored local files such as `config/skill-repos.local.yaml`, or pass a separate manifest with `--repos-file`. The public SkillPort repo should only ship a neutral example manifest.

Use the sync script for normal machine setup. Use local symlink scripts only for active local development where live edits should be visible before pushing.

## GitHub Template Rule

GitHub template repositories copy an entire repo. They do not directly template a subdirectory.

Use the generator for normal SkillPort workflows. Create a separate minimal GitHub template repo only if you need the GitHub UI or `gh repo create --template` flow.

## Harness-neutral installation and global rules

Use `npx skills add <repo> --skill '*' -a codex claude-code opencode -g -y` for the configured baseline. Inspect the CLI output and `npx skills ls -g -a codex claude-code opencode`: Codex and OpenCode use `~/.agents/skills` directly; Claude's paths are aliases to that per-OS tree. Never add an editable content copy per harness.

Keep one canonical repository checkout shared by Windows and WSL through Windows paths and `/mnt/c`. Generated installs may remain per OS so each installer can maintain its own paths without disturbing unrelated skills. Other physical devices use separate Git-synced checkouts.

Global rules are separate from skills. Use `scripts/bootstrap-agent-guidance.py` with an already reconciled private AGENTS.md source. It configures Codex guidance, a one-line Claude import and OpenCode's global JSON `instructions` reference without copying the rules. See `docs/cross-device-maintenance.md` in the SkillPort repository for preservation and verification steps. Do not assume arbitrary harnesses support the same global file path or import syntax.
