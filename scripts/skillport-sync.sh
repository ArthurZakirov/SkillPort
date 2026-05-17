#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_REPOS_FILE="${REPO_ROOT}/config/skill-repos.txt"

REPOS_FILE="${SKILLPORT_REPOS_FILE:-${DEFAULT_REPOS_FILE}}"
AGENT="codex"
GLOBAL=1
RUN_UPDATE=1
DRY_RUN=0
YES=1
SKILLS_BIN="${SKILLPORT_SKILLS_BIN:-npx skills}"

usage() {
  cat <<'EOF'
Usage:
  skillport-sync.sh [options]

Install or refresh all skills from the repos listed in config/skill-repos.txt.

Options:
  --repos-file <path>   Read repos from a custom file.
  --agent <name>        Install for one agent. Default: codex.
  --all-agents          Install for all supported agents.
  --project             Install project-local instead of global.
  --skip-update         Do not run "skills update" after add.
  --update-only         Only run "skills update"; do not run add.
  --dry-run             Print commands without executing them.
  --no-yes              Do not pass -y to skills commands.
  -h, --help            Show this help.

Environment:
  SKILLPORT_REPOS_FILE  Default repo manifest path override.
  SKILLPORT_SKILLS_BIN  Command prefix. Default: "npx skills".

Examples:
  ./scripts/skillport-sync.sh
  ./scripts/skillport-sync.sh --all-agents
  ./scripts/skillport-sync.sh --repos-file ./config/work-repos.txt
EOF
}

log() {
  printf '[skillport-sync] %s\n' "$*"
}

die() {
  printf '[skillport-sync] ERROR: %s\n' "$*" >&2
  exit 1
}

quote_cmd() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '+ '
    quote_cmd "$@"
    return 0
  fi

  "$@"
}

read_repos() {
  local line

  [[ -f "${REPOS_FILE}" ]] || die "Repo manifest not found: ${REPOS_FILE}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "${line}" ]] || continue
    printf '%s\n' "${line}"
  done < "${REPOS_FILE}"
}

split_skills_bin() {
  # Intentionally simple: SKILLPORT_SKILLS_BIN is for command + fixed args,
  # not arbitrary shell syntax.
  # shellcheck disable=SC2206
  SKILLS_CMD=( ${SKILLS_BIN} )
}

INSTALL_ONLY=0
UPDATE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos-file)
      REPOS_FILE="$2"
      shift 2
      ;;
    --agent)
      AGENT="$2"
      shift 2
      ;;
    --all-agents)
      AGENT="*"
      shift
      ;;
    --project)
      GLOBAL=0
      shift
      ;;
    --skip-update)
      RUN_UPDATE=0
      shift
      ;;
    --update-only)
      UPDATE_ONLY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-yes)
      YES=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

split_skills_bin

SCOPE_FLAG=()
if [[ "${GLOBAL}" -eq 1 ]]; then
  SCOPE_FLAG=(-g)
fi

YES_FLAG=()
if [[ "${YES}" -eq 1 ]]; then
  YES_FLAG=(-y)
fi

if [[ "${UPDATE_ONLY}" -ne 1 ]]; then
  REPOS=()
  while IFS= read -r repo; do
    REPOS+=("${repo}")
  done < <(read_repos)
  [[ "${#REPOS[@]}" -gt 0 ]] || die "No repos found in ${REPOS_FILE}"

  log "Installing all skills from ${#REPOS[@]} repo(s) for agent=${AGENT}"
  for repo in "${REPOS[@]}"; do
    log "Adding ${repo}"
    run_cmd "${SKILLS_CMD[@]}" add "${repo}" --skill "*" -a "${AGENT}" "${SCOPE_FLAG[@]}" "${YES_FLAG[@]}"
  done
fi

if [[ "${RUN_UPDATE}" -eq 1 ]]; then
  log "Updating tracked installed skills"
  run_cmd "${SKILLS_CMD[@]}" update "${SCOPE_FLAG[@]}" "${YES_FLAG[@]}"
fi

log "Done."
