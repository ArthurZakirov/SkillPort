---
name: skillport-distribution-system
description: Use when packaging, publishing, or updating a public agent-skill repository so it can be installed across machines, repos, Codex, Claude Code, and local skill directories.
---

# SkillPort Distribution System

## Purpose

Package reusable agent skills once so they can be installed and shared across machines, people, repos, Codex, Claude Code, and local skill directories.

## Use This Workflow

For a new skill-pack repo:

1. Pick the repo product name, slug, and promise before packaging files.
2. Run `scripts/create-agent-skill-repo.sh` from the SkillPort repo when starting a new skill pack.
3. Inspect generated placeholders, plugin manifests, README, examples, schemas, and setup script.
4. Add or update the real skills.
5. Add the GitHub repo shorthand to `config/skill-repos.txt`.
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

This reruns `npx skills add <repo> --skill '*' -a codex -g -y` for every repo listed in `config/skill-repos.txt`, then runs `npx skills update -g -y`.

Use the sync script for normal machine setup. Use local symlink scripts only for active local development where live edits should be visible before pushing.

## GitHub Template Rule

GitHub template repositories copy an entire repo. They do not directly template a subdirectory.

Use the generator for normal SkillPort workflows. Create a separate minimal GitHub template repo only if you need the GitHub UI or `gh repo create --template` flow.
