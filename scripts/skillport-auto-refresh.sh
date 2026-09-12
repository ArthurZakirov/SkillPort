#!/bin/bash

umask 077

CONFIG_FILE="${HOME}/.config/SkillPort/auto-refresh.conf"
MAX_LOG_BYTES=131072

usage() {
  cat <<'EOF'
Usage: skillport-auto-refresh.sh [--config <absolute-path>]

Safely refresh configured Git-backed guidance, private workstation context,
and remote-installed global skills. Optional pushes never create commits.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      [ "$#" -ge 2 ] || { printf 'skillport-auto-refresh: missing config path\n' >&2; exit 2; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'skillport-auto-refresh: unsupported argument\n' >&2
      exit 2
      ;;
  esac
done

case "$CONFIG_FILE" in
  /*) ;;
  *) printf 'skillport-auto-refresh: config path must be absolute\n' >&2; exit 2;;
esac
[ -f "$CONFIG_FILE" ] || { printf 'skillport-auto-refresh: config is missing\n' >&2; exit 2; }

SKILLPORT_REPO=
SKILL_REPOS_FILE=
GUIDANCE_REPO=
GUIDANCE_SOURCE=
STATE_DIR=
NPX_BIN=
PYTHON_BIN=
GH_BIN=
PUSH_PRIVATE_REPOS=()
PUSH_PUBLIC_REPOS=()
REQUIRED_GLOBAL_SKILLS=()

trim() {
  TRIMMED="$1"
  TRIMMED="${TRIMMED#"${TRIMMED%%[![:space:]]*}"}"
  TRIMMED="${TRIMMED%"${TRIMMED##*[![:space:]]}"}"
}

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  raw_line="${raw_line%$'\r'}"
  trim "$raw_line"
  line="$TRIMMED"
  case "$line" in
    ''|'#'*) continue;;
  esac
  case "$line" in
    *=*) ;;
    *) printf 'skillport-auto-refresh: malformed config line\n' >&2; exit 2;;
  esac
  key="${line%%=*}"
  value="${line#*=}"
  trim "$key"
  key="$TRIMMED"
  trim "$value"
  value="$TRIMMED"
  [ -n "$value" ] || { printf 'skillport-auto-refresh: empty config value\n' >&2; exit 2; }
  case "$key" in
    SKILLPORT_REPO) [ -z "$SKILLPORT_REPO" ] || exit 2; SKILLPORT_REPO="$value";;
    SKILL_REPOS_FILE) [ -z "$SKILL_REPOS_FILE" ] || exit 2; SKILL_REPOS_FILE="$value";;
    GUIDANCE_REPO) [ -z "$GUIDANCE_REPO" ] || exit 2; GUIDANCE_REPO="$value";;
    GUIDANCE_SOURCE) [ -z "$GUIDANCE_SOURCE" ] || exit 2; GUIDANCE_SOURCE="$value";;
    STATE_DIR) [ -z "$STATE_DIR" ] || exit 2; STATE_DIR="$value";;
    NPX_BIN) [ -z "$NPX_BIN" ] || exit 2; NPX_BIN="$value";;
    PYTHON_BIN) [ -z "$PYTHON_BIN" ] || exit 2; PYTHON_BIN="$value";;
    GH_BIN) [ -z "$GH_BIN" ] || exit 2; GH_BIN="$value";;
    PUSH_PRIVATE_REPO)
      PUSH_PRIVATE_REPOS+=("$value")
      ;;
    PUSH_PUBLIC_REPO)
      PUSH_PUBLIC_REPOS+=("$value")
      ;;
    REQUIRED_GLOBAL_SKILL)
      case "$value" in *[!A-Za-z0-9._-]*) printf 'skillport-auto-refresh: invalid required skill name\n' >&2; exit 2;; esac
      REQUIRED_GLOBAL_SKILLS+=("$value")
      ;;
    *)
      printf 'skillport-auto-refresh: unsupported config key\n' >&2
      exit 2
      ;;
  esac
done < "$CONFIG_FILE"

for required_value in "$SKILLPORT_REPO" "$SKILL_REPOS_FILE" "$GUIDANCE_REPO" "$GUIDANCE_SOURCE" "$STATE_DIR" "$NPX_BIN" "$PYTHON_BIN" "$GH_BIN"; do
  [ -n "$required_value" ] || { printf 'skillport-auto-refresh: required config key is missing\n' >&2; exit 2; }
  case "$required_value" in
    /*) ;;
    *) printf 'skillport-auto-refresh: configured paths must be absolute\n' >&2; exit 2;;
  esac
done

[ -x "$NPX_BIN" ] || { printf 'skillport-auto-refresh: npx executable is unavailable\n' >&2; exit 2; }
[ -x "$PYTHON_BIN" ] || { printf 'skillport-auto-refresh: python executable is unavailable\n' >&2; exit 2; }
[ -x "$GH_BIN" ] || { printf 'skillport-auto-refresh: GitHub metadata executable is unavailable\n' >&2; exit 2; }
PATH="$(/usr/bin/dirname "$NPX_BIN"):$(/usr/bin/dirname "$GH_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

/bin/mkdir -p "$STATE_DIR"
/bin/chmod 700 "$STATE_DIR"
LOCK_DIR="$STATE_DIR/refresh.lock"
LOG_FILE="$STATE_DIR/refresh.log"

acquire_lock() {
  if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    return 0
  fi
  lock_pid=
  if [ -f "$LOCK_DIR/pid" ]; then
    IFS= read -r lock_pid < "$LOCK_DIR/pid" || lock_pid=
  fi
  case "$lock_pid" in
    ''|*[!0-9]*) ;;
    *)
      if /bin/kill -0 "$lock_pid" 2>/dev/null; then
        printf 'skillport-auto-refresh: another refresh is active\n'
        exit 0
      fi
      ;;
  esac
  /bin/rm -f "$LOCK_DIR/pid"
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || {
    printf 'skillport-auto-refresh: stale lock could not be reconciled\n' >&2
    exit 1
  }
  /bin/mkdir "$LOCK_DIR" 2>/dev/null || {
    printf 'skillport-auto-refresh: refresh lock is unavailable\n' >&2
    exit 1
  }
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

cleanup() {
  if [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ]; then
    /bin/rm -f "$RUN_DIR/command.out"
    /bin/rmdir "$RUN_DIR" 2>/dev/null || true
  fi
  /bin/rm -f "$LOCK_DIR/pid"
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
RUN_DIR="$(/usr/bin/mktemp -d "$STATE_DIR/run.XXXXXX")" || exit 1
COMMAND_OUTPUT="$RUN_DIR/command.out"

rotate_log() {
  [ -f "$LOG_FILE" ] || return 0
  log_size=$(/usr/bin/stat -f %z "$LOG_FILE" 2>/dev/null || printf '0')
  case "$log_size" in ''|*[!0-9]*) log_size=0;; esac
  if [ "$log_size" -ge "$MAX_LOG_BYTES" ]; then
    /usr/bin/tail -n 400 "$LOG_FILE" > "$RUN_DIR/trimmed.log"
    /bin/mv "$RUN_DIR/trimmed.log" "$LOG_FILE"
  fi
}

log() {
  rotate_log
  timestamp=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
  printf '%s %s\n' "$timestamp" "$1" | /usr/bin/tee -a "$LOG_FILE"
  /bin/chmod 600 "$LOG_FILE"
}

run_quiet() {
  label="$1"
  shift
  : > "$COMMAND_OUTPUT"
  if "$@" > "$COMMAND_OUTPUT" 2>&1; then
    : > "$COMMAND_OUTPUT"
    log "$label ok"
    return 0
  else
    command_status=$?
  fi
  : > "$COMMAND_OUTPUT"
  log "ERROR $label failed status=$command_status"
  return "$command_status"
}

repo_label() {
  /usr/bin/basename "$1" | /usr/bin/tr -cd 'A-Za-z0-9._-'
}

git_capture() {
  capture_label="$1"
  shift
  : > "$COMMAND_OUTPUT"
  if CAPTURED_VALUE=$("$@" 2> "$COMMAND_OUTPUT"); then
    : > "$COMMAND_OUTPUT"
    return 0
  else
    capture_status=$?
  fi
  : > "$COMMAND_OUTPUT"
  log "ERROR $capture_label failed status=$capture_status"
  return "$capture_status"
}

require_git_repo() {
  repo_dir="$1"
  repo_name=$(repo_label "$repo_dir")
  [ -d "$repo_dir/.git" ] || { log "ERROR repo=$repo_name checkout_missing"; return 1; }
  return 0
}

safe_git_refresh() {
  repo_dir="$1"
  require_git_repo "$repo_dir" || return 1
  repo_name=$(repo_label "$repo_dir")
  git_capture "repo=$repo_name branch_check" /usr/bin/git -C "$repo_dir" symbolic-ref --quiet --short HEAD || return 1
  git_capture "repo=$repo_name upstream_check" /usr/bin/git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' || return 1
  upstream="$CAPTURED_VALUE"
  run_quiet "repo=$repo_name fetch" /usr/bin/git -C "$repo_dir" fetch --quiet || return 1
  git_capture "repo=$repo_name relation_check" /usr/bin/git -C "$repo_dir" rev-list --left-right --count "HEAD...$upstream" || return 1
  set -- $CAPTURED_VALUE
  ahead="${1:-x}"
  behind="${2:-x}"
  case "$ahead:$behind" in *[!0-9:]*|'') log "ERROR repo=$repo_name invalid_relation"; return 1;; esac
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    log "ERROR repo=$repo_name divergent_checkout"
    return 1
  fi
  if [ "$behind" -gt 0 ]; then
    run_quiet "repo=$repo_name fast_forward" /usr/bin/git -C "$repo_dir" merge --ff-only --quiet "$upstream" || {
      log "ERROR repo=$repo_name fast_forward_blocked"
      return 1
    }
  elif [ "$ahead" -gt 0 ]; then
    log "repo=$repo_name local_commits_pending"
  else
    log "repo=$repo_name current"
  fi
}

visibility_for_repo() {
  repo_dir="$1"
  repo_name=$(repo_label "$repo_dir")
  : > "$COMMAND_OUTPUT"
  if CAPTURED_VALUE=$(cd "$repo_dir" && GH_PROMPT_DISABLED=1 NO_COLOR=1 "$GH_BIN" repo view --json visibility --jq .visibility 2> "$COMMAND_OUTPUT"); then
    : > "$COMMAND_OUTPUT"
  else
    visibility_status=$?
    : > "$COMMAND_OUTPUT"
    log "repo=$repo_name push_skipped visibility_unverified status=$visibility_status"
    return 1
  fi
  case "$CAPTURED_VALUE" in
    PUBLIC|PRIVATE) return 0;;
    *) log "repo=$repo_name push_skipped visibility_unverified"; return 1;;
  esac
}

scan_secret_material() {
  repo_dir="$1"
  upstream="$2"
  repo_name=$(repo_label "$repo_dir")
  secret_path_pattern='(^|/)(\.env($|\.)|\.npmrc$|\.yarnrc(\.yml)?$|\.netrc$|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$|.*(secret|credential|token).*)'
  secret_content_pattern="(-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|(^|[^A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{16,}|(api[_-]?key|client[_-]?secret|password|passwd|access[_-]?token|refresh[_-]?token)[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_./+=-]{12,})"
  /usr/bin/git -C "$repo_dir" log --format= --name-only "$upstream..HEAD" -- . | /usr/bin/grep -Ei "$secret_path_pattern" >/dev/null
  scan_status=("${PIPESTATUS[@]}")
  if [ "${scan_status[0]}" -ne 0 ] || [ "${scan_status[1]}" -gt 1 ]; then
    log "repo=$repo_name push_skipped credential_scan_error"
    return 1
  fi
  if [ "${scan_status[1]}" -eq 0 ]; then
    log "repo=$repo_name push_skipped credential_scan_failed"
    return 1
  fi
  /usr/bin/git -C "$repo_dir" log --format= --no-ext-diff -p "$upstream..HEAD" -- . | /usr/bin/grep -E '^\+' | /usr/bin/grep -Ei "$secret_content_pattern" >/dev/null
  scan_status=("${PIPESTATUS[@]}")
  if [ "${scan_status[0]}" -ne 0 ] || [ "${scan_status[2]}" -gt 1 ]; then
    log "repo=$repo_name push_skipped credential_scan_error"
    return 1
  fi
  if [ "${scan_status[2]}" -eq 0 ]; then
    log "repo=$repo_name push_skipped credential_scan_failed"
    return 1
  fi
  log "repo=$repo_name credential_scan_passed"
}

scan_public_personal_data() {
  repo_dir="$1"
  upstream="$2"
  repo_name=$(repo_label "$repo_dir")
  personal_pattern='([[:alnum:]._%+-]+@[[:alnum:].-]+\.[A-Za-z]{2,}|\+?[0-9][0-9 ()/.-]{8,}[0-9]|(straße|strasse|street|road|avenue|weg|platz)[[:space:]]+[0-9]+|DE[0-9]{20})'
  /usr/bin/git -C "$repo_dir" log --format= --no-ext-diff -p "$upstream..HEAD" -- . | /usr/bin/grep -E '^\+' | /usr/bin/grep -Ei "$personal_pattern" >/dev/null
  scan_status=("${PIPESTATUS[@]}")
  if [ "${scan_status[0]}" -ne 0 ] || [ "${scan_status[2]}" -gt 1 ]; then
    log "repo=$repo_name push_skipped personal_data_scan_error"
    return 1
  fi
  if [ "${scan_status[2]}" -eq 0 ]; then
    log "repo=$repo_name push_skipped personal_data_review_required"
    return 1
  fi
  log "repo=$repo_name personal_data_scan_passed"
}

safe_git_push() {
  repo_dir="$1"
  declared_visibility="$2"
  approved_head="${3:-}"
  require_git_repo "$repo_dir" || return 0
  repo_name=$(repo_label "$repo_dir")
  visibility_for_repo "$repo_dir" || return 0
  [ "$CAPTURED_VALUE" = "$declared_visibility" ] || {
    log "repo=$repo_name push_skipped visibility_mismatch"
    return 0
  }
  git_capture "repo=$repo_name worktree_check" /usr/bin/git -C "$repo_dir" status --porcelain --untracked-files=normal || return 0
  [ -z "$CAPTURED_VALUE" ] || { log "repo=$repo_name push_skipped dirty_worktree"; return 0; }
  git_capture "repo=$repo_name branch_check" /usr/bin/git -C "$repo_dir" symbolic-ref --quiet --short HEAD || return 0
  git_capture "repo=$repo_name upstream_check" /usr/bin/git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' || return 0
  upstream="$CAPTURED_VALUE"
  run_quiet "repo=$repo_name push_fetch" /usr/bin/git -C "$repo_dir" fetch --quiet || return 0
  git_capture "repo=$repo_name push_relation_check" /usr/bin/git -C "$repo_dir" rev-list --left-right --count "HEAD...$upstream" || return 0
  set -- $CAPTURED_VALUE
  ahead="${1:-x}"
  behind="${2:-x}"
  case "$ahead:$behind" in *[!0-9:]*|'') log "repo=$repo_name push_skipped invalid_relation"; return 0;; esac
  if [ "$ahead" -eq 0 ]; then
    log "repo=$repo_name push_skipped nothing_ahead"
    return 0
  fi
  if [ "$behind" -gt 0 ]; then
    log "repo=$repo_name push_skipped behind_or_diverged"
    return 0
  fi
  if [ "$declared_visibility" = PUBLIC ]; then
    git_capture "repo=$repo_name head_check" /usr/bin/git -C "$repo_dir" rev-parse HEAD || return 0
    current_head="$CAPTURED_VALUE"
    case "$approved_head" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
      *) log "repo=$repo_name push_skipped public_release_review_required"; return 0;;
    esac
    [ "$current_head" = "$approved_head" ] || { log "repo=$repo_name push_skipped public_release_review_required"; return 0; }
  fi
  scan_secret_material "$repo_dir" "$upstream" || return 0
  if [ "$declared_visibility" = PUBLIC ]; then
    scan_public_personal_data "$repo_dir" "$upstream" || return 0
  fi
  run_quiet "repo=$repo_name ordinary_push" /usr/bin/git -C "$repo_dir" push --quiet || return 0
}

log 'refresh_start'
safe_git_refresh "$SKILLPORT_REPO" || exit 1
if [ "$GUIDANCE_REPO" != "$SKILLPORT_REPO" ]; then
  safe_git_refresh "$GUIDANCE_REPO" || exit 1
fi

for repo_dir in "${PUSH_PRIVATE_REPOS[@]}"; do
  case "$repo_dir" in /*) safe_git_push "$repo_dir" PRIVATE;; *) log 'push_skipped invalid_private_repo_path';; esac
done
for public_spec in "${PUSH_PUBLIC_REPOS[@]}"; do
  case "$public_spec" in
    *'|'*)
      repo_dir="${public_spec%%|*}"
      approved_head="${public_spec#*|}"
      case "$repo_dir" in /*) safe_git_push "$repo_dir" PUBLIC "$approved_head";; *) log 'push_skipped invalid_public_repo_path';; esac
      ;;
    *) log 'push_skipped invalid_public_repo_spec';;
  esac
done

run_quiet 'global_guidance refresh' "$PYTHON_BIN" "$SKILLPORT_REPO/scripts/bootstrap-agent-guidance.py" --source "$GUIDANCE_SOURCE" || exit 1
run_quiet 'global_skills synchronize' /usr/bin/env SKILLPORT_SKILLS_BIN="$NPX_BIN -y skills" "$SKILLPORT_REPO/scripts/skillport-sync.sh" --repos-file "$SKILL_REPOS_FILE" --skip-update || exit 1
run_quiet 'global_skills discovery_check' "$NPX_BIN" -y skills ls -g -a codex || exit 1
for skill_name in "${REQUIRED_GLOBAL_SKILLS[@]}"; do
  if [ ! -f "$HOME/.agents/skills/$skill_name/SKILL.md" ]; then
    log "ERROR global_skills required_skill_missing name=$skill_name"
    exit 1
  fi
done
log 'refresh_complete'
