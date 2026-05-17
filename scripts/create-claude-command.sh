#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMANDS_DIR="${REPO_ROOT}/commands"

usage() {
  cat <<'EOF'
Usage:
  create-claude-command.sh <command-name>

Creates a new canonical Claude command file under commands/ and then runs
setup-local-links.sh so ~/.claude/commands/ can point at it.
EOF
}

normalize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

RAW_NAME="$1"
COMMAND_NAME="$(normalize_name "${RAW_NAME}")"

if [[ -z "${COMMAND_NAME}" ]]; then
  echo "Command name must contain at least one letter or digit." >&2
  exit 1
fi

mkdir -p "${COMMANDS_DIR}"
COMMAND_FILE="${COMMANDS_DIR}/${COMMAND_NAME}.md"

if [[ -e "${COMMAND_FILE}" ]]; then
  echo "Command already exists: ${COMMAND_FILE}" >&2
  exit 1
fi

cat > "${COMMAND_FILE}" <<EOF
# ${COMMAND_NAME}

[TODO: Add the Claude command body here.]
EOF

"${SCRIPT_DIR}/setup-local-links.sh"

printf 'Created %s\n' "${COMMAND_FILE}"
