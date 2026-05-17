#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/templates/agent-skill-repo"

AUTHOR_NAME="Arthur Zakirov"
GITHUB_OWNER="ArthurZakirov"
BRAND_COLOR="#2563EB"
INIT_GIT=0

usage() {
  cat <<'EOF'
Usage:
  create-agent-skill-repo.sh <repo-name> <destination-dir> [options]

Options:
  --display-name <text>        Human display name. Defaults to title-cased repo name.
  --description <text>         Plugin/repo description.
  --value-prop <text>          README opening value proposition.
  --skill-name <name>          First skill name. Defaults to repo-name.
  --skill-description <text>   First skill trigger description.
  --skill-purpose <text>       First skill purpose body text.
  --skill-use-example <text>   README usage example text.
  --keyword <text>             Plugin keyword. Defaults to repo-name.
  --brand-color <hex>          Plugin brand color. Defaults to #2563EB.
  --github-owner <owner>       GitHub owner. Defaults to ArthurZakirov.
  --author-name <name>         Author name. Defaults to Arthur Zakirov.
  --init-git                   Run git init -b main after scaffolding.

Example:
  create-agent-skill-repo.sh career-positioning-os ../career-positioning-os \
    --display-name "Career Positioning OS" \
    --description "Public-safe skills and schemas for turning private work evidence into career signal." \
    --skill-name article-leverage-story \
    --skill-description "Use when drafting confidentiality-safe long-form project stories." \
    --skill-purpose "Draft persuasive long-form project stories from structured achievement evidence."
EOF
}

normalize_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

title_case_slug() {
  local slug="$1"
  python3 - "$slug" <<'PY'
import sys
print(" ".join(part.capitalize() for part in sys.argv[1].replace("_", "-").split("-") if part))
PY
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

REPO_NAME="$(normalize_slug "$1")"
DESTINATION="$2"
shift 2

if [[ -z "${REPO_NAME}" ]]; then
  echo "Repo name must contain at least one letter or digit." >&2
  exit 1
fi

DISPLAY_NAME="$(title_case_slug "${REPO_NAME}")"
PLUGIN_DESCRIPTION="${DISPLAY_NAME} packages public-safe reusable agent skills."
VALUE_PROPOSITION="Public-safe skills, schemas, and examples for reusable agent workflows."
SKILL_NAME="${REPO_NAME}"
SKILL_DISPLAY_NAME="$(title_case_slug "${SKILL_NAME}")"
SKILL_DESCRIPTION="Use when applying the ${DISPLAY_NAME} workflow."
SKILL_PURPOSE="Apply the reusable ${DISPLAY_NAME} workflow."
SKILL_USE_EXAMPLE="apply this workflow to my current task"
KEYWORD="${REPO_NAME}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --display-name)
      DISPLAY_NAME="$2"
      shift 2
      ;;
    --description)
      PLUGIN_DESCRIPTION="$2"
      shift 2
      ;;
    --value-prop)
      VALUE_PROPOSITION="$2"
      shift 2
      ;;
    --skill-name)
      SKILL_NAME="$(normalize_slug "$2")"
      SKILL_DISPLAY_NAME="$(title_case_slug "${SKILL_NAME}")"
      shift 2
      ;;
    --skill-description)
      SKILL_DESCRIPTION="$2"
      shift 2
      ;;
    --skill-purpose)
      SKILL_PURPOSE="$2"
      shift 2
      ;;
    --skill-use-example)
      SKILL_USE_EXAMPLE="$2"
      shift 2
      ;;
    --keyword)
      KEYWORD="$2"
      shift 2
      ;;
    --brand-color)
      BRAND_COLOR="$2"
      shift 2
      ;;
    --github-owner)
      GITHUB_OWNER="$2"
      shift 2
      ;;
    --author-name)
      AUTHOR_NAME="$2"
      shift 2
      ;;
    --init-git)
      INIT_GIT=1
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

if [[ -z "${SKILL_NAME}" ]]; then
  echo "Skill name must contain at least one letter or digit." >&2
  exit 1
fi

if [[ -e "${DESTINATION}" ]]; then
  if [[ -n "$(find "${DESTINATION}" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    echo "Destination exists and is not empty: ${DESTINATION}" >&2
    exit 1
  fi
fi

mkdir -p "${DESTINATION}"
cp -R "${TEMPLATE_DIR}/." "${DESTINATION}/"

if [[ "${SKILL_NAME}" != "__SKILL_NAME__" ]]; then
  mkdir -p "${DESTINATION}/skills"
  mv "${DESTINATION}/skills/__SKILL_NAME__" "${DESTINATION}/skills/${SKILL_NAME}"
fi

GITHUB_OWNER_SLUG="$(normalize_slug "${GITHUB_OWNER}")"
SHORT_DESCRIPTION="${PLUGIN_DESCRIPTION}"

PLACEHOLDERS=(
  "__REPO_NAME__=${REPO_NAME}"
  "__DISPLAY_NAME__=${DISPLAY_NAME}"
  "__VALUE_PROPOSITION__=${VALUE_PROPOSITION}"
  "__PLUGIN_DESCRIPTION__=${PLUGIN_DESCRIPTION}"
  "__SHORT_DESCRIPTION__=${SHORT_DESCRIPTION}"
  "__GITHUB_OWNER__=${GITHUB_OWNER}"
  "__GITHUB_OWNER_SLUG__=${GITHUB_OWNER_SLUG}"
  "__AUTHOR_NAME__=${AUTHOR_NAME}"
  "__BRAND_COLOR__=${BRAND_COLOR}"
  "__KEYWORD__=${KEYWORD}"
  "__SKILL_NAME__=${SKILL_NAME}"
  "__SKILL_DISPLAY_NAME__=${SKILL_DISPLAY_NAME}"
  "__SKILL_DESCRIPTION__=${SKILL_DESCRIPTION}"
  "__SKILL_PURPOSE__=${SKILL_PURPOSE}"
  "__SKILL_USE_EXAMPLE__=${SKILL_USE_EXAMPLE}"
  "__AGENTS_PURPOSE__=Help users apply ${DISPLAY_NAME} through reusable public-safe methodology, examples, and skills."
)

PLACEHOLDER_PAYLOAD="$(printf '%s\n' "${PLACEHOLDERS[@]}")"
export PLACEHOLDER_PAYLOAD

python3 - "${DESTINATION}" <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
mapping = {}

for line in os.environ["PLACEHOLDER_PAYLOAD"].splitlines():
    key, value = line.split("=", 1)
    if "\x00" in value:
        raise SystemExit(f"Placeholder value for {key} contains a NUL byte")
    mapping[key] = value

def replace_text(value):
    for key, replacement in mapping.items():
        value = value.replace(key, replacement)
    return value

def replace_json(value):
    if isinstance(value, str):
        return replace_text(value)
    if isinstance(value, list):
        return [replace_json(item) for item in value]
    if isinstance(value, dict):
        return {replace_json(key): replace_json(item) for key, item in value.items()}
    return value

for path in root.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix == ".json":
        data = json.loads(path.read_text())
        path.write_text(json.dumps(replace_json(data), indent=2) + "\n")
    else:
        path.write_text(replace_text(path.read_text()))
PY

chmod +x "${DESTINATION}/scripts/setup-local-links.sh"

if [[ "${INIT_GIT}" -eq 1 ]]; then
  git -C "${DESTINATION}" init -b main
fi

printf 'Created agent skill repo scaffold at %s\n' "${DESTINATION}"
