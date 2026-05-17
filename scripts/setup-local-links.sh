#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
COMMANDS_DIR="${REPO_ROOT}/commands"

CLAUDE_HOME="${CLAUDE_HOME:-${HOME}/.claude}"
AGENTS_HOME="${AGENTS_HOME:-${HOME}/.agents}"
CODEX_HOME_ROOT="${CODEX_HOME:-${HOME}/.codex}"

FORCE=0
LINK_COMMANDS=1
SKIPPED=0

usage() {
  cat <<'EOF'
Usage:
  setup-local-links.sh [--force] [--skip-commands]

What it does:
  - links repo skills into ~/.claude/skills/
  - links repo skills into ~/.agents/skills/
  - links repo skills into ~/.codex/skills/ as per-skill symlinks
  - links repo commands into ~/.claude/commands/ as per-file symlinks

Notes:
  - Codex currently has no verified filesystem-backed slash-command/prompt
    directory analogous to Claude Code's ~/.claude/commands/, so this script
    only links skills for Codex.
  - Existing non-symlink paths are left untouched unless --force is used.
EOF
}

log() {
  printf '[setup-local-links] %s\n' "$*"
}

warn() {
  printf '[setup-local-links] WARN: %s\n' "$*" >&2
}

abs_path() {
  readlink -f "$1"
}

ensure_dir() {
  mkdir -p "$1"
}

ensure_symlink() {
  local source="$1"
  local destination="$2"
  local source_abs current_abs

  source_abs="$(abs_path "${source}")"
  ensure_dir "$(dirname "${destination}")"

  if [[ -L "${destination}" ]]; then
    current_abs="$(readlink -f "${destination}" || true)"
    if [[ "${current_abs}" == "${source_abs}" ]]; then
      return 0
    fi
    if [[ "${FORCE}" -ne 1 ]]; then
      warn "Skipping existing symlink with different target: ${destination}"
      SKIPPED=$((SKIPPED + 1))
      return 1
    fi
    rm -f "${destination}"
  elif [[ -e "${destination}" ]]; then
    if [[ "${FORCE}" -ne 1 ]]; then
      warn "Skipping existing non-symlink path: ${destination}"
      SKIPPED=$((SKIPPED + 1))
      return 1
    fi
    rm -rf "${destination}"
  fi

  if ln -s "${source_abs}" "${destination}"; then
    log "Linked ${destination} -> ${source_abs}"
    return 0
  fi

  warn "Failed to create symlink: ${destination}"
  SKIPPED=$((SKIPPED + 1))
  return 1
}

link_skill_tree() {
  local provider_root="$1"
  local provider_name="$2"
  local destination_root="${provider_root}/skills"
  local skill_path skill_name

  ensure_dir "${destination_root}"

  for skill_path in "${SKILLS_DIR}"/*; do
    if [[ ! -d "${skill_path}" ]]; then
      continue
    fi
    skill_name="$(basename "${skill_path}")"
    ensure_symlink "${skill_path}" "${destination_root}/${skill_name}" || true
  done

  log "Processed ${provider_name} skills in ${destination_root}"
}

link_claude_commands() {
  local destination_root="${CLAUDE_HOME}/commands"
  local command_path command_name

  if [[ "${LINK_COMMANDS}" -ne 1 ]]; then
    return 0
  fi

  ensure_dir "${destination_root}"

  for command_path in "${COMMANDS_DIR}"/*.md; do
    if [[ ! -f "${command_path}" ]]; then
      continue
    fi
    command_name="$(basename "${command_path}")"
    ensure_symlink "${command_path}" "${destination_root}/${command_name}" || true
  done

  log "Processed Claude commands in ${destination_root}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --skip-commands)
      LINK_COMMANDS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ensure_dir "${SKILLS_DIR}"
ensure_dir "${COMMANDS_DIR}"

link_skill_tree "${CLAUDE_HOME}" "Claude Code"
link_skill_tree "${AGENTS_HOME}" ".agents"
link_skill_tree "${CODEX_HOME_ROOT}" "Codex"
link_claude_commands

if [[ "${SKIPPED}" -gt 0 ]]; then
  warn "Completed with ${SKIPPED} skipped path(s). Re-run with --force if you want this script to replace conflicting paths."
fi

log "Done."
