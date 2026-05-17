# Templates

Reusable repository templates for agent-skill projects.

## `agent-skill-repo`

Use this template when creating a new public repository that packages skills for Codex, Claude Code, `.agents`, and `skills.sh`.

The template includes:

- README focused on value, setup, and usage
- public/private boundary instructions
- Codex plugin manifest
- Codex marketplace metadata
- Claude Code plugin metadata
- local symlink setup script
- starter skill
- dummy example and schema placeholders

Create a repo from it with:

```bash
./scripts/create-agent-skill-repo.sh <repo-name> <destination-dir> \
  --display-name "Display Name" \
  --description "What this repo helps users do." \
  --skill-name first-skill \
  --skill-description "Use when ..." \
  --skill-purpose "..."
```

Then validate:

```bash
! rg "__[A-Z0-9_]+__" .

ruby -rjson -e 'ARGV.each { |f| JSON.parse(File.read(f)); puts "json ok #{f}" }' \
  .codex-plugin/plugin.json \
  .agents/plugins/marketplace.json \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json

./scripts/setup-local-links.sh --help

npm exec --yes skills -- add . --list
```

Expected result:

- `rg` finds no unreplaced template placeholders.
- Each JSON manifest parses.
- `setup-local-links.sh --help` prints usage.
- `skills.sh` lists the generated skill.

After the repo is pushed to GitHub, verify the published install path:

```bash
npm exec --yes skills -- add https://github.com/<owner>/<repo> --list
```
