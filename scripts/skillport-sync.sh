#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_REPOS_FILE="${REPO_ROOT}/config/skill-repos.local.yaml"
EXAMPLE_REPOS_FILE="${REPO_ROOT}/config/skill-repos.example.yaml"

REPOS_FILE="${SKILLPORT_REPOS_FILE:-}"
REPOS_FILE_EXPLICIT=0
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

Install or refresh all skills from a SkillPort repo manifest.

Options:
  --repos-file <path>   Read repos from a custom YAML or text manifest.
  --agent <name>        Install for one agent. Default: codex.
  --all-agents          Install for all supported agents.
  --project             Install project-local instead of global.
  --skip-update         Do not run "skills update" after add.
  --update-only         Only run "skills update"; do not run add.
  --dry-run             Print commands without executing them.
  --no-yes              Do not pass -y to skills commands.
  -h, --help            Show this help.

Environment:
  SKILLPORT_REPOS_FILE  Repo manifest path override.
  SKILLPORT_SKILLS_BIN  Command prefix. Default: "npx skills".

Examples:
  ./scripts/skillport-sync.sh
  ./scripts/skillport-sync.sh --all-agents
  ./scripts/skillport-sync.sh --repos-file ./config/work-repos.yaml
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
  local in_repos=0

  [[ -f "${REPOS_FILE}" ]] || die "Repo manifest not found: ${REPOS_FILE}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "${line}" ]] || continue

    if [[ "${line}" == "repos:" ]]; then
      in_repos=1
      continue
    fi

    if [[ "${in_repos}" -eq 1 ]]; then
      if [[ "${line}" =~ ^-[[:space:]]+(.+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        continue
      fi

      if [[ "${line}" != -* ]]; then
        in_repos=0
      fi
    fi

    # Backward-compatible plain text format: one repo shorthand per line.
    if [[ "${line}" != *":"* && "${line}" != -* ]]; then
      printf '%s\n' "${line}"
    fi
  done < "${REPOS_FILE}"
}

resolve_repos_file() {
  if [[ -n "${REPOS_FILE}" ]]; then
    return 0
  fi

  if [[ -f "${LOCAL_REPOS_FILE}" ]]; then
    REPOS_FILE="${LOCAL_REPOS_FILE}"
    return 0
  fi

  REPOS_FILE="${EXAMPLE_REPOS_FILE}"
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
      REPOS_FILE_EXPLICIT=1
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

resolve_repos_file
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

  if [[ "${REPOS_FILE}" == "${EXAMPLE_REPOS_FILE}" && "${REPOS_FILE_EXPLICIT}" -ne 1 ]]; then
    die "Only the example manifest exists. Copy config/skill-repos.example.yaml to config/skill-repos.local.yaml and add your repos, or pass --repos-file."
  fi

  log "Using repo manifest: ${REPOS_FILE}"
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
