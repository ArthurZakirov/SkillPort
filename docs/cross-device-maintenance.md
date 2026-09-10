# Maintain skills across machines

The Git repository is the editable source. Treat `npx skills` output as generated installations. Installing from a local path does not imply a live link to that checkout: verify the installed paths before editing them. In skills 1.5.25, a Codex installation uses `~/.agents/skills/<name>` and copies source files there.

## Update cycle

1. Inspect `git status`, fetch the source repository and fast-forward only when safe. Preserve uncommitted changes and reconcile divergent edits before installation.
2. Edit and validate the repository source, then commit and push.
3. Refresh each machine using the local SkillPort manifest with `./scripts/skillport-sync.sh --skip-update`. This reruns `skills add` for only the selected repositories and avoids updating unrelated installed packs.
4. Check `npx skills ls -g -a codex`, installed file contents, and `~/.agents/.skill-lock.json` to verify discovery and the recorded source.

On native Windows, run the equivalent commands in PowerShell:

```powershell
npx.cmd -y skills add owner/repository --skill '*' -a codex -g -y
npx.cmd -y skills ls -g -a codex
```

On macOS or Linux:

```bash
npx -y skills add owner/repository --skill '*' -a codex -g -y
npx -y skills ls -g -a codex
```

Use the actual repository names from the machine's local manifest. A refresh is not a merge: reconcile any manual edits to an installed skill into its repository before refreshing it.

## Existing installations

Before replacing a standalone skill directory, compare its complete file tree against the selected source. Move preserved originals to a dated backup outside all skill discovery directories. A backup is a recovery snapshot, not another editable install.

Legacy `~/.codex/skills/<name>` paths can point to the corresponding generated `~/.agents/skills/<name>` path. Use symlinks on Linux/macOS or directory junctions between local Windows paths. Verify that the link resolves and the skill entrypoint can be read. Do not assume Windows can create a symlink to a WSL network path without additional privileges.

For active local development, the repository's `setup-local-links.sh` is the supported live-link workflow. Inspect its destinations and reconcile conflicts before using it; do not use `--force` to discard differing copies. Do not refresh a development link with `skills add` until edits are committed and the link has been safely detached. Generated installs and development links are different modes.

## Private context

Public skill installation does not distribute private inventory. Keep private facts in a separate private source, install or link only the relevant domain, and verify the public skill's configured lookup path on every machine. Avoid copying an entire private profile into a public skill or into an unrelated workflow.

A successful Windows or WSL installation is not proof of macOS installation. Verify each machine separately; when access is unavailable, provide the commands and clearly mark that machine pending.
