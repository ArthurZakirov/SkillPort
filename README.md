# SkillPort

Package agent skills once. Install them anywhere.

SkillPort is the packaging and distribution layer for public skill-pack repos. It packages the repeatable repo scaffolding: README shape, plugin manifests, marketplace metadata, local symlink setup, dummy examples, schema placeholders, and a starter skill.

Use it when you want a new repo that already knows how to install through `npx skills add`, Codex plugins, Claude Code plugins, and local symlinks.

## What It Helps With

- Package new agent-skill repositories in a tested installable structure.
- Avoid re-explaining README, plugin, marketplace, and setup-script conventions.
- Generate public-safe starter repos with examples, schemas, docs, and a starter skill when packaging a new skill pack.
- Keep one manifest of skill-pack repos and sync all of them onto a machine with one command.
- Keep distribution infrastructure separate from individual skill packs such as ProofStack, AgentDesk, SystemSmith, and OpportunityOS.

## Install With skills.sh

List the skills in this repo:

```bash
npx skills add https://github.com/ArthurZakirov/SkillPort --list
```

Install all skills for Codex:

```bash
npx skills add https://github.com/ArthurZakirov/SkillPort --skill '*' -a codex -g -y
```

## Generate A New Skill Repo

```bash
./scripts/create-agent-skill-repo.sh my-skill-pack ../MySkillPack \
  --display-name "MySkillPack" \
  --description "Reusable skills for a specific workflow." \
  --value-prop "Reusable agent skills for a specific workflow." \
  --skill-name first-workflow \
  --skill-description "Use when applying the first workflow." \
  --skill-purpose "Apply the first workflow."
```

The generated repo includes:

- `README.md`
- `AGENTS.example.md`
- `.codex-plugin/plugin.json`
- `.agents/plugins/marketplace.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `scripts/setup-local-links.sh`
- starter `skills/<skill>/SKILL.md`
- dummy examples, schemas, and public/private docs

## GitHub Templates

GitHub template repositories copy an entire repository with `gh repo create --template owner/repo`. They cannot directly use only a subdirectory such as `templates/agent-skill-repo`.

SkillPort is therefore a packaging toolbox repo. If a one-click GitHub template becomes useful later, create a separate minimal repo from `templates/agent-skill-repo` and mark that repo as a template with:

```bash
gh repo edit ArthurZakirov/<template-repo> --template
```

See `docs/github-template-strategy.md`.

## Sync Skills Across Machines

SkillPort keeps the source repo list in [`config/skill-repos.txt`](./config/skill-repos.txt).

Run:

```bash
./scripts/skillport-sync.sh
```

That loops over every repo in the manifest and runs:

```bash
npx skills add <repo> --skill '*' -a codex -g -y
```

Then it runs:

```bash
npx skills update -g -y
```

This is intentionally different from local per-repo symlinking. Use `skillport-sync.sh` for normal cross-machine setup and updates. Use `scripts/setup-local-links.sh` only when actively developing a repo locally and wanting live edits before pushing.

Useful variants:

```bash
./scripts/skillport-sync.sh --all-agents
./scripts/skillport-sync.sh --agent claude-code
./scripts/skillport-sync.sh --skip-update
./scripts/skillport-sync.sh --update-only
./scripts/skillport-sync.sh --dry-run
```

## Included Skills

<!-- BEGIN GENERATED SECTION: skills -->
> Generated from tracked `skills/*/SKILL.md` metadata.

| Skill | Description |
| --- | --- |
| `skillport-distribution-system` | Use when packaging, publishing, or updating a public agent-skill repository so it can be installed across machines, repos, Codex, Claude Code, and local skill directories. |
<!-- END GENERATED SECTION: skills -->

## Available Commands

<!-- BEGIN GENERATED SECTION: commands -->
> Generated from tracked `commands/*.md` files.

| Command | Summary |
| --- | --- |
| `/list-skills` | Please list all your available skills with a 1 sentence description for each one. Do not return any additional fluff text before or after. |
<!-- END GENERATED SECTION: commands -->

## Repo Inventory

<!-- BEGIN GENERATED SECTION: repo_inventory -->
> Generated from tracked manifests, scripts, commands, and skills.

```text
.
├── .agents/
│   ├── plugins/marketplace.json
│   └── skills -> ../skills
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── .claude/
│   ├── commands -> ../commands
│   └── skills -> ../skills
├── .codex-plugin/
│   └── plugin.json
├── .githooks/
│   └── pre-commit
├── .github/
│   └── workflows/
│       └── readme-generated.yml
├── commands/
│   └── list-skills.md
├── scripts/
│   ├── create-agent-skill-repo.sh
│   ├── create-claude-command.sh
│   ├── create-shared-skill.sh
│   ├── generate-readme.py
│   ├── install-git-hooks.sh
│   ├── setup-local-links.sh
│   ├── skillport-sync.sh
│   └── update-readme.sh
├── skills/
│   └── skillport-distribution-system/
├── pyproject.toml
└── uv.lock
```
<!-- END GENERATED SECTION: repo_inventory -->

## Development

Use `./scripts/update-readme.sh` after changing tracked skills, scripts, templates, or plugin metadata.
