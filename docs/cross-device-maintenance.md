# Maintain skills across machines

The Git repository is the editable source. Treat `npx skills` output as generated installations. Installing from a local path does not imply a live link to that checkout: verify the installed paths before editing them. In skills 1.5.25, a Codex installation uses `~/.agents/skills/<name>` and copies source files there.

## Update cycle

1. Inspect `git status`, fetch the source repository and fast-forward only when safe. Preserve uncommitted changes and reconcile divergent edits before installation.
2. Edit and validate the repository source, then commit and push.
3. Refresh each machine from the private canonical repository registry. Its `skills: true` entries are the only remote packs passed to `skills add`, so unrelated installed packs are untouched.
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

Use the actual repository names selected by the private registry. A refresh is not a merge: reconcile any manual edits to an installed skill into its repository before refreshing it.

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

## Layered global rules and one repository registry

Keep synchronized private global rules in exactly two layers per machine: `agent-guidance/common.md` plus either `agent-guidance/macos.md` or `agent-guidance/windows-wsl.md`. `scripts/bootstrap-agent-guidance.py` renders a concrete global Codex `AGENTS.md` atomically from Common + one overlay. The output has a generated marker and source digest; later refreshes may replace only that managed output. A first replacement of any regular file, wrapper, or symlink requires `--replace-existing`, after human comparison, and preserves its effective content under `guidance-backups/`. A nonempty `AGENTS.override.md` remains a hard stop.

Do not rely on a bare `@` line as a Codex import. Claude receives two native imports and OpenCode receives the two paths in its `instructions` array while unrelated settings are preserved. Paths containing spaces are supported. `npx skills` does not distribute arbitrary global instruction files, and running Codex sessions still need a restart to adopt a changed `AGENTS.md` chain.

Store one structured private registry at `$PRIVATE_CONTEXT_ROOT/skillport/repositories.json`; see `config/repositories.example.json`. Every entry has one logical role, portable checkout kind, refresh flag, and skill-install flag. The updater derives `skillport-root`, `private-context-root`, and sibling checkout paths from the two machine roots. The same registry drives safe Git refresh, the exact remote skill subset, and the generated human-readable repository-role overview. Do not maintain separate checkout and skill-repository inventories.

References: [Codex global instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [Claude memory and imports](https://code.claude.com/docs/en/memory).

## Automatic macOS refresh

Use `scripts/install-macos-auto-refresh.sh` to create a private local config and a user LaunchAgent. The job runs when loaded at login and at quarter-hour calendar intervals. macOS coalesces missed calendar events and runs one after wake. The refresh command uses a lock, bounds its log, fetches only registry-selected canonical checkouts, permits only fast-forward updates, renders Common + macOS global guidance, and reinstalls the registry's selected remote-backed skills.

Keep the real config outside the public repository. A synchronized private repository is a suitable place for the personal skill manifest and global guidance source. The generated `~/.agents/skills` tree remains machine-local and must never become an editable source.

Set machine-local paths through task-specific environment variables. Do not put a device's concrete checkout paths in public files or rely on interactive shell startup files:

- `SKILLPORT_ROOT`: the SkillPort checkout on the current machine.
- `PRIVATE_CONTEXT_ROOT`: the cross-tool private context checkout on the current machine. The updater derives the repository registry and both private guidance layers from this root.
- `SKILLPORT_AUTO_REFRESH_CONFIG`, `SKILLPORT_STATE_DIR`, `SKILLPORT_NODE_BIN`, `SKILLPORT_NPX_BIN`, `SKILLPORT_PYTHON_BIN`, and `SKILLPORT_GH_BIN`: the machine-local policy file, state directory, and exact executable entrypoints supplied to the LaunchAgent.

The installer writes these values explicitly into the generated LaunchAgent environment. The permission-restricted local config contains only prefixed push and verification policy entries. The same logical root names apply on Windows, but their values are independent native Windows paths; the macOS LaunchAgent and POSIX refresh script intentionally reject Windows path syntax. Paths containing spaces are supported because values remain separate quoted arguments. Node invokes the npx entrypoint directly; because npm-generated command shims use `/usr/bin/env node`, only that child process receives a minimal lookup path derived from `SKILLPORT_NODE_BIN`. The updater never changes or exports the parent process's `PATH`.

The updater never stages, commits, stashes, rebases, resets, cleans, force-pushes, or merges divergent history. A dirty canonical checkout may receive a fast-forward only when Git can preserve its local changes; otherwise the run stops with a concise error.

Automatic push is separate from automatic refresh and is disabled unless a repository is explicitly listed in the private config:

- `SKILLPORT_PUSH_PRIVATE_REPO` requires remotely verified private visibility, a clean working tree, a configured upstream, strictly ahead-only history, and a silent credential scan.
- `SKILLPORT_PUSH_PUBLIC_REPO` requires remotely verified public visibility and all private-repository checks. It also requires an exact reviewed `HEAD` SHA in the config plus a silent personal-data scan. `REVIEW_REQUIRED` is the fail-closed default. A new commit invalidates the previous approval.
- Visibility mismatch or unavailable metadata blocks the push. Dirty, behind, divergent, detached, or ambiguous repositories are not changed. Push automation publishes only commits a human already created; it never creates or selects content for publication.

Logs contain repository labels and status codes only. Raw Git, GitHub, scanner, installer, and package-manager output is discarded so errors cannot leak credentials or private content.

Codex guidance and skills have different reload behavior. Codex constructs its `AGENTS.md` instruction chain once per run/session, so an already-running task is not guaranteed to adopt changed global guidance on its next turn; restart that task/session when current guidance matters. Codex automatically detects skill changes, but restart Codex if an installed update does not appear. Neither mechanism promises mid-response hot reload.

## Automatic Windows refresh

`scripts/install-windows-auto-refresh.ps1` creates a permission-restricted JSON machine config and registers a current-user Task Scheduler task. Run the installer from native Windows PowerShell with `SKILLPORT_ROOT` and `PRIVATE_CONTEXT_ROOT` set to that machine's native checkout paths. It discovers or accepts explicit `SKILLPORT_GIT_BIN`, `SKILLPORT_NODE_BIN`, `SKILLPORT_NPX_BIN`, `SKILLPORT_PYTHON_BIN`, `SKILLPORT_GH_BIN`, and `SKILLPORT_POWERSHELL_BIN` paths, then records the required runtime values in the local config. Concrete device paths never belong in the public repository or synchronized guidance.

```powershell
$env:SKILLPORT_ROOT = '<absolute-windows-skillport-checkout>'
$env:PRIVATE_CONTEXT_ROOT = '<absolute-windows-private-context-checkout>'
& "$env:SKILLPORT_ROOT\scripts\install-windows-auto-refresh.ps1" -ReplaceExisting
```

Add repeatable `-PushPrivateRepository`, `-PushPublicRepository`, or `-RequiredGlobalSkill` values only when explicitly intended. Public push entries are written as `REVIEW_REQUIRED`; replace that token with the exact reviewed 40-character `HEAD` only in the protected local config.

The task starts immediately after installation, at current-user logon, and through a daily trigger repeated every 15 minutes for the full day. `StartWhenAvailable` catches a missed scheduled run after sleep, while `IgnoreNew` plus the updater's exclusive file lock prevents overlap. A standalone workstation-unlock trigger is intentionally omitted: Security event 4801 depends on audit policy and event-log access and is not reliably portable. Logon plus at-most-15-minute repetition provides deterministic coverage after unlock without requiring elevated event subscriptions.

The Windows updater uses the same registry and safety model as macOS. It fetches first, refuses divergent history, skips dirty checkouts when a fast-forward would be required, and never stages, commits, stashes, rebases, resets, cleans, or force-pushes. Optional ordinary pushes use verified remote visibility, clean ahead-only history, silent credential scans, and the same exact-SHA plus personal-data gate for public repositories. Logs are bounded and contain only sanitized repository labels, operation names, and status codes; raw command output, remote URLs, configuration, and environment contents are never logged.

Static cross-platform tests validate the PowerShell safety and Task Scheduler contract on non-Windows development machines. The installer dry run, task XML registration, ACLs, task execution, sleep/wake catch-up, and installed Codex/skills discovery must still be verified on a real Windows host before declaring that host complete.

## OpenCode and additional harnesses

OpenCode can discover `~/.agents/skills` directly, so no additional skill-content copy is needed. The current skills CLI reports Codex and OpenCode as universal consumers of that tree, with Claude linked to it. Verify these reported targets and the actual paths after installing; do not force every harness into a path it does not support.

The bootstrap merges the shared absolute instruction-file path into `~/.config/opencode/opencode.json` while preserving other JSON settings and instruction entries. Existing JSONC is left untouched for explicit reconciliation. This native `instructions` mechanism loads the common source; it does not rely on Claude's `@` syntax being an OpenCode import. OpenCode also supports `~/.config/opencode/AGENTS.md`, but it is unnecessary when the source is configured through `instructions`.

Verify existing OpenCode installations with `opencode debug config` and `opencode debug skill` when available. Configuration for a not-yet-installed harness is not proof of a live model session. Do not install full applications just to create aliases. Other harnesses, such as OpenClaw or Pi, need their own documented discovery/entrypoint check before claiming support.

References: [OpenCode skills](https://opencode.ai/docs/skills/), [OpenCode rules](https://opencode.ai/docs/rules/).
