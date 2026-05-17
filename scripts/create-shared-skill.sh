#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"

usage() {
  cat <<'EOF'
Usage:
  create-shared-skill.sh <skill-name> [-- init_skill.py args...]

Creates a new shared skill under the repo's canonical skills/ directory and
then links it into the local Claude, .agents, and Codex skill directories by
calling setup-local-links.sh.

Any arguments after -- are passed to Codex's skill-creator init_skill.py when
that helper is available, for example:

  create-shared-skill.sh my-skill -- --resources scripts,references
EOF
}

normalize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

RAW_NAME="$1"
shift

INIT_ARGS=()
if [[ $# -gt 0 ]]; then
  if [[ "$1" != "--" ]]; then
    usage >&2
    exit 1
  fi
  shift
  INIT_ARGS=("$@")
fi

SKILL_NAME="$(normalize_name "${RAW_NAME}")"

if [[ -z "${SKILL_NAME}" ]]; then
  echo "Skill name must contain at least one letter or digit." >&2
  exit 1
fi

SKILL_DIR="${SKILLS_DIR}/${SKILL_NAME}"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
CODEX_HOME_ROOT="${CODEX_HOME:-${HOME}/.codex}"
INIT_SKILL="${CODEX_HOME_ROOT}/skills/.system/skill-creator/scripts/init_skill.py"

if [[ -e "${SKILL_DIR}" ]]; then
  echo "Skill already exists: ${SKILL_DIR}" >&2
  exit 1
fi

if [[ -x "${INIT_SKILL}" ]]; then
  if [[ "${#INIT_ARGS[@]}" -gt 0 ]]; then
    python3 "${INIT_SKILL}" "${SKILL_NAME}" --path "${SKILLS_DIR}" "${INIT_ARGS[@]}"
  else
    python3 "${INIT_SKILL}" "${SKILL_NAME}" --path "${SKILLS_DIR}"
  fi
else
  mkdir -p "${SKILL_DIR}"

  cat > "${SKILL_FILE}" <<EOF
---
name: ${SKILL_NAME}
description: "[TODO: Describe when to use this skill.]"
---

# ${SKILL_NAME}

[TODO: Add the workflow and any references, scripts, or assets.]
EOF
fi

"${SCRIPT_DIR}/setup-local-links.sh"

printf 'Created %s\n' "${SKILL_DIR}"
