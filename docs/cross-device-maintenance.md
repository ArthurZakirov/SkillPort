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

Prefer one authoritative skill package when instructions and the facts they operate on form one coherent workflow. Choose the repository visibility through a harm-and-benefit review, not a mechanical personal-versus-generic rule. A public workstation skill may include reviewed hardware models, topology, adapters, cabling, workflows, and lessons when disclosure is useful and low-risk; exclude exact location linkage, serial numbers, account or network identifiers, security-device locations, secrets, confidential details, and uncleared drafts. Keep supporting references inside the same skill directory so installation has no cross-repository runtime dependency, and retire the migration source after the reviewed content moves rather than maintaining two authoritative copies.

A successful Windows or WSL installation is not proof of macOS installation. Verify each machine separately; when access is unavailable, provide the commands and clearly mark that machine pending.

## One checkout shared by Windows and WSL

Place canonical source repositories on the Windows filesystem when both environments need direct access. Windows uses `C:/...` and WSL uses `/mnt/c/...` for the same files. Legacy WSL paths may be compatibility symlinks after a verified migration. Do not create a second editable WSL clone or use Git push/pull to transfer changes between these filesystem views. Separate physical devices still need their own checkout and Git synchronization.

Generated skill installs remain per operating system. Include the configured agent targets when installing for Codex, Claude Code and OpenCode:

```powershell
npx.cmd -y skills add owner/repository --skill '*' -a codex claude-code opencode -g -y
```

Use `npx` instead of `npx.cmd` on Linux/macOS. Verify Claude's `~/.claude/skills` links resolve to the generated install and inspect both agents with `skills ls -g -a codex claude-code opencode`.

## Shared global rules

Keep private personal rules in a private repository, for example `agent-guidance/AGENTS.md`. Reconcile the existing global Codex and Claude preferences before running:

```bash
python3 scripts/bootstrap-agent-guidance.py --source /absolute/private-repo/agent-guidance/AGENTS.md --dry-run
python3 scripts/bootstrap-agent-guidance.py --source /absolute/private-repo/agent-guidance/AGENTS.md --replace-existing
```

On Windows use `python` and the native absolute source path. The bootstrap uses a WSL/Linux/macOS file symlink for Codex, or a concise load-reference wrapper on Windows without requesting elevated privileges. Claude's global `~/.claude/CLAUDE.md` contains only one absolute `@` import of the source. Source paths must have no whitespace. Existing differing files require the explicit replacement flag and are preserved under `guidance-backups/`; nonempty `AGENTS.override.md` must be reconciled first.

This bootstrap handles arbitrary global guidance files; `npx skills` does not distribute them. Verify a fresh Codex session actually reads the wrapper target, rather than assuming bare `@` imports work in Codex. Check Claude import behavior in a fresh session where access allows it. Inspect another physical device's existing rules before bootstrapping it.

References: [Codex global instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [Claude memory and imports](https://code.claude.com/docs/en/memory).

## Automatic macOS refresh

Use `scripts/install-macos-auto-refresh.sh` to create a private local config and a user LaunchAgent. The job runs when loaded at login and at quarter-hour calendar intervals. macOS coalesces missed calendar events and runs one after wake. The refresh command uses a lock, bounds its log, fetches only explicitly configured canonical checkouts, permits only fast-forward updates, refreshes global guidance with `bootstrap-agent-guidance.py`, and reruns the selected remote-backed skill manifest with `skillport-sync.sh --skip-update`.

Keep the real config outside the public repository. A synchronized private repository is a suitable place for the personal skill manifest and global guidance source. The generated `~/.agents/skills` tree remains machine-local and must never become an editable source.

The updater never stages, commits, stashes, rebases, resets, cleans, force-pushes, or merges divergent history. A dirty canonical checkout may receive a fast-forward only when Git can preserve its local changes; otherwise the run stops with a concise error.

Automatic push is separate from automatic refresh and is disabled unless a repository is explicitly listed in the private config:

- `PUSH_PRIVATE_REPO` requires remotely verified private visibility, a clean working tree, a configured upstream, strictly ahead-only history, and a silent credential scan.
- `PUSH_PUBLIC_REPO` requires remotely verified public visibility and all private-repository checks. It also requires an exact reviewed `HEAD` SHA in the config plus a silent personal-data scan. `REVIEW_REQUIRED` is the fail-closed default. A new commit invalidates the previous approval.
- Visibility mismatch or unavailable metadata blocks the push. Dirty, behind, divergent, detached, or ambiguous repositories are not changed. Push automation publishes only commits a human already created; it never creates or selects content for publication.

Logs contain repository labels and status codes only. Raw Git, GitHub, scanner, installer, and package-manager output is discarded so errors cannot leak credentials or private content.

Codex guidance and skills have different reload behavior. Codex constructs its `AGENTS.md` instruction chain once per run/session, so an already-running task is not guaranteed to adopt changed global guidance on its next turn; restart that task/session when current guidance matters. Codex automatically detects skill changes, but restart Codex if an installed update does not appear. Neither mechanism promises mid-response hot reload.

## OpenCode and additional harnesses

OpenCode can discover `~/.agents/skills` directly, so no additional skill-content copy is needed. The current skills CLI reports Codex and OpenCode as universal consumers of that tree, with Claude linked to it. Verify these reported targets and the actual paths after installing; do not force every harness into a path it does not support.

The bootstrap merges the shared absolute instruction-file path into `~/.config/opencode/opencode.json` while preserving other JSON settings and instruction entries. Existing JSONC is left untouched for explicit reconciliation. This native `instructions` mechanism loads the common source; it does not rely on Claude's `@` syntax being an OpenCode import. OpenCode also supports `~/.config/opencode/AGENTS.md`, but it is unnecessary when the source is configured through `instructions`.

Verify existing OpenCode installations with `opencode debug config` and `opencode debug skill` when available. Configuration for a not-yet-installed harness is not proof of a live model session. Do not install full applications just to create aliases. Other harnesses, such as OpenClaw or Pi, need their own documented discovery/entrypoint check before claiming support.

References: [OpenCode skills](https://opencode.ai/docs/skills/), [OpenCode rules](https://opencode.ai/docs/rules/).
