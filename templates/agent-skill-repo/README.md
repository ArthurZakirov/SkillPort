# __DISPLAY_NAME__

__VALUE_PROPOSITION__

## Install

Install all skills for Codex with `skills.sh`:

```bash
npx skills add https://github.com/__GITHUB_OWNER__/__REPO_NAME__ --skill '*' -a codex -g -y
```

List available skills first:

```bash
npx skills add https://github.com/__GITHUB_OWNER__/__REPO_NAME__ --list
```

For local development from a cloned repo, link skills into Claude Code, `.agents`, and Codex skill directories:

```bash
./scripts/setup-local-links.sh
```

Existing non-symlink paths are left untouched unless `--force` is used.

## Use

After installation, ask your agent to use the relevant skill by describing the task:

```text
Use __SKILL_NAME__ to __SKILL_USE_EXAMPLE__.
```

## Keep Private Data Out

Do not put real raw notes, secrets, credentials, private strategy, customer data, or employer-internal material in this repo.

Use fictional examples here. Keep real evidence in a private repo, then publish only reviewed and sanitized outputs.

