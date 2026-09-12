#!/bin/bash
set -e

SKILLPORT_ROOT="${SKILLPORT_ROOT:-}"
PRIVATE_CONTEXT_ROOT="${PRIVATE_CONTEXT_ROOT:-}"
SKILLPORT_NODE_BIN="${SKILLPORT_NODE_BIN:-}"
SKILLPORT_NPX_BIN="${SKILLPORT_NPX_BIN:-}"
SKILLPORT_PYTHON_BIN="${SKILLPORT_PYTHON_BIN:-}"
SKILLPORT_GH_BIN="${SKILLPORT_GH_BIN:-}"
PRIVATE_REPOS=()
PUBLIC_REPOS=()
REQUIRED_SKILLS=()
CONFIG_FILE="${SKILLPORT_AUTO_REFRESH_CONFIG:-${HOME}/.config/SkillPort/auto-refresh.conf}"
PLIST_FILE="${HOME}/Library/LaunchAgents/com.skillport.auto-refresh.plist"
SKILLPORT_STATE_DIR="${SKILLPORT_STATE_DIR:-${HOME}/Library/Application Support/SkillPort}"
DRY_RUN=0
REPLACE=0

usage() {
  cat <<'EOF'
Usage: SKILLPORT_ROOT=<path> PRIVATE_CONTEXT_ROOT=<path> install-macos-auto-refresh.sh [options]

Required environment:
  SKILLPORT_ROOT                 SkillPort checkout on this machine.
  PRIVATE_CONTEXT_ROOT           Cross-tool private context checkout.

Optional:
  --push-private-repo <path>  Repeatable private-repository push opt-in.
  --push-public-repo <path>   Repeatable public opt-in; starts review-blocked.
  --required-global-skill <name>  Repeatable post-sync discovery check.
  --replace-existing
  --dry-run

The LaunchAgent runs at login/load and every 15 minutes. Missed calendar runs
are coalesced by launchd and run after wake. Public push approval is per exact
HEAD and must be added manually to the private config after review.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --push-private-repo) PRIVATE_REPOS+=("$2"); shift 2;;
    --push-public-repo) PUBLIC_REPOS+=("$2"); shift 2;;
    --required-global-skill) REQUIRED_SKILLS+=("$2"); shift 2;;
    --replace-existing) REPLACE=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) printf 'install-macos-auto-refresh: unsupported argument\n' >&2; exit 2;;
  esac
done

[ "$(/usr/bin/uname -s)" = Darwin ] || { printf 'install-macos-auto-refresh: macOS is required\n' >&2; exit 2; }
SKILLPORT_NODE_BIN="${SKILLPORT_NODE_BIN:-$(command -v node || true)}"
SKILLPORT_NPX_BIN="${SKILLPORT_NPX_BIN:-$(command -v npx || true)}"
SKILLPORT_PYTHON_BIN="${SKILLPORT_PYTHON_BIN:-$(command -v python3 || true)}"
SKILLPORT_GH_BIN="${SKILLPORT_GH_BIN:-$(command -v gh || true)}"
SKILLPORT_REGISTRY_FILE="$PRIVATE_CONTEXT_ROOT/skillport/repositories.json"
SKILLPORT_GUIDANCE_COMMON="$PRIVATE_CONTEXT_ROOT/agent-guidance/common.md"
SKILLPORT_GUIDANCE_OVERLAY="$PRIVATE_CONTEXT_ROOT/agent-guidance/macos.md"

for required_name in SKILLPORT_ROOT PRIVATE_CONTEXT_ROOT SKILLPORT_AUTO_REFRESH_CONFIG SKILLPORT_STATE_DIR SKILLPORT_NODE_BIN SKILLPORT_NPX_BIN SKILLPORT_PYTHON_BIN SKILLPORT_GH_BIN; do
  case "$required_name" in
    SKILLPORT_ROOT) required_path="$SKILLPORT_ROOT";;
    PRIVATE_CONTEXT_ROOT) required_path="$PRIVATE_CONTEXT_ROOT";;
    SKILLPORT_AUTO_REFRESH_CONFIG) required_path="$CONFIG_FILE";;
    SKILLPORT_STATE_DIR) required_path="$SKILLPORT_STATE_DIR";;
    SKILLPORT_NODE_BIN) required_path="$SKILLPORT_NODE_BIN";;
    SKILLPORT_NPX_BIN) required_path="$SKILLPORT_NPX_BIN";;
    SKILLPORT_PYTHON_BIN) required_path="$SKILLPORT_PYTHON_BIN";;
    SKILLPORT_GH_BIN) required_path="$SKILLPORT_GH_BIN";;
  esac
  [ -n "$required_path" ] || { printf 'install-macos-auto-refresh: required environment variable %s is unset\n' "$required_name" >&2; exit 2; }
  case "$required_path" in /*) ;; *) printf 'install-macos-auto-refresh: %s must be an absolute POSIX path\n' "$required_name" >&2; exit 2;; esac
done
[ -x "$SKILLPORT_ROOT/scripts/skillport-auto-refresh.sh" ] || { printf 'install-macos-auto-refresh: refresh script is not executable\n' >&2; exit 2; }
[ -d "$PRIVATE_CONTEXT_ROOT/.git" ] || { printf 'install-macos-auto-refresh: private context repository is invalid\n' >&2; exit 2; }
for private_input in "$SKILLPORT_REGISTRY_FILE" "$SKILLPORT_GUIDANCE_COMMON" "$SKILLPORT_GUIDANCE_OVERLAY"; do
  [ -f "$private_input" ] || { printf 'install-macos-auto-refresh: a derived private input is missing\n' >&2; exit 2; }
done
[ -x "$SKILLPORT_NODE_BIN" ] && [ -f "$SKILLPORT_NPX_BIN" ] && [ -x "$SKILLPORT_PYTHON_BIN" ] && [ -x "$SKILLPORT_GH_BIN" ] || { printf 'install-macos-auto-refresh: required executable is missing\n' >&2; exit 2; }

for repo_dir in "${PRIVATE_REPOS[@]}" "${PUBLIC_REPOS[@]}"; do
  [ -z "$repo_dir" ] && continue
  case "$repo_dir" in /*) ;; *) printf 'install-macos-auto-refresh: push repository paths must be absolute\n' >&2; exit 2;; esac
  [ -d "$repo_dir/.git" ] || { printf 'install-macos-auto-refresh: push repository is invalid\n' >&2; exit 2; }
done

for skill_name in "${REQUIRED_SKILLS[@]}"; do
  case "$skill_name" in ''|*[!A-Za-z0-9._-]*) printf 'install-macos-auto-refresh: invalid required skill name\n' >&2; exit 2;; esac
done

escape_xml() {
  printf '%s' "$1" | /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

TEMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/skillport-install.XXXXXX")
trap '/bin/rm -f "$TEMP_DIR/auto-refresh.conf" "$TEMP_DIR/job.plist"; /bin/rmdir "$TEMP_DIR" 2>/dev/null || true' EXIT HUP INT TERM
TEMP_CONFIG="$TEMP_DIR/auto-refresh.conf"
TEMP_PLIST="$TEMP_DIR/job.plist"

{
  printf '# Machine-local push policy. Canonical paths are provided by the LaunchAgent environment.\n'
  for repo_dir in "${PRIVATE_REPOS[@]}"; do printf 'SKILLPORT_PUSH_PRIVATE_REPO=%s\n' "$repo_dir"; done
  for repo_dir in "${PUBLIC_REPOS[@]}"; do printf 'SKILLPORT_PUSH_PUBLIC_REPO=%s|REVIEW_REQUIRED\n' "$repo_dir"; done
  for skill_name in "${REQUIRED_SKILLS[@]}"; do printf 'SKILLPORT_REQUIRED_GLOBAL_SKILL=%s\n' "$skill_name"; done
} > "$TEMP_CONFIG"

refresh_script_xml=$(escape_xml "$SKILLPORT_ROOT/scripts/skillport-auto-refresh.sh")
config_file_xml=$(escape_xml "$CONFIG_FILE")
skillport_root_xml=$(escape_xml "$SKILLPORT_ROOT")
private_context_root_xml=$(escape_xml "$PRIVATE_CONTEXT_ROOT")
state_dir_xml=$(escape_xml "$SKILLPORT_STATE_DIR")
node_bin_xml=$(escape_xml "$SKILLPORT_NODE_BIN")
npx_bin_xml=$(escape_xml "$SKILLPORT_NPX_BIN")
python_bin_xml=$(escape_xml "$SKILLPORT_PYTHON_BIN")
gh_bin_xml=$(escape_xml "$SKILLPORT_GH_BIN")
cat > "$TEMP_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.skillport.auto-refresh</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${refresh_script_xml}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Minute</key><integer>0</integer></dict>
    <dict><key>Minute</key><integer>15</integer></dict>
    <dict><key>Minute</key><integer>30</integer></dict>
    <dict><key>Minute</key><integer>45</integer></dict>
  </array>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>/dev/null</string>
  <key>StandardErrorPath</key>
  <string>/dev/null</string>
  <key>WorkingDirectory</key>
  <string>${skillport_root_xml}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SKILLPORT_ROOT</key>
    <string>${skillport_root_xml}</string>
    <key>PRIVATE_CONTEXT_ROOT</key>
    <string>${private_context_root_xml}</string>
    <key>SKILLPORT_AUTO_REFRESH_CONFIG</key>
    <string>${config_file_xml}</string>
    <key>SKILLPORT_STATE_DIR</key>
    <string>${state_dir_xml}</string>
    <key>SKILLPORT_NODE_BIN</key>
    <string>${node_bin_xml}</string>
    <key>SKILLPORT_NPX_BIN</key>
    <string>${npx_bin_xml}</string>
    <key>SKILLPORT_PYTHON_BIN</key>
    <string>${python_bin_xml}</string>
    <key>SKILLPORT_GH_BIN</key>
    <string>${gh_bin_xml}</string>
  </dict>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$TEMP_PLIST" >/dev/null

guidance_args=(--common "$SKILLPORT_GUIDANCE_COMMON" --overlay "$SKILLPORT_GUIDANCE_OVERLAY" --platform macos --registry "$SKILLPORT_REGISTRY_FILE" --dry-run)
[ "$REPLACE" -eq 0 ] || guidance_args+=(--replace-existing)
"$SKILLPORT_PYTHON_BIN" "$SKILLPORT_ROOT/scripts/bootstrap-agent-guidance.py" "${guidance_args[@]}" >/dev/null

for destination in "$CONFIG_FILE" "$PLIST_FILE"; do
  source_file="$TEMP_CONFIG"
  [ "$destination" = "$PLIST_FILE" ] && source_file="$TEMP_PLIST"
  if [ -e "$destination" ] && ! /usr/bin/cmp -s "$source_file" "$destination" && [ "$REPLACE" -ne 1 ]; then
    printf 'install-macos-auto-refresh: existing artifact differs; reconcile or use --replace-existing\n' >&2
    exit 1
  fi
done

printf 'Config target: %s\n' "$CONFIG_FILE"
printf 'LaunchAgent target: %s\n' "$PLIST_FILE"
printf 'Schedule: login/load and quarter-hour calendar intervals (wake-coalesced)\n'
[ "$DRY_RUN" -eq 0 ] || exit 0

/bin/mkdir -p "$(/usr/bin/dirname "$CONFIG_FILE")" "$(/usr/bin/dirname "$PLIST_FILE")" "$SKILLPORT_STATE_DIR"
/usr/bin/install -m 600 "$TEMP_CONFIG" "$CONFIG_FILE"
/usr/bin/install -m 644 "$TEMP_PLIST" "$PLIST_FILE"
/bin/chmod 700 "$SKILLPORT_STATE_DIR"
guidance_args=(--common "$SKILLPORT_GUIDANCE_COMMON" --overlay "$SKILLPORT_GUIDANCE_OVERLAY" --platform macos --registry "$SKILLPORT_REGISTRY_FILE")
[ "$REPLACE" -eq 0 ] || guidance_args+=(--replace-existing)
"$SKILLPORT_PYTHON_BIN" "$SKILLPORT_ROOT/scripts/bootstrap-agent-guidance.py" "${guidance_args[@]}" >/dev/null

domain="gui/$(/usr/bin/id -u)"
if /bin/launchctl print "$domain/com.skillport.auto-refresh" >/dev/null 2>&1; then
  if [ "$REPLACE" -eq 1 ]; then
    /bin/launchctl bootout "$domain" "$PLIST_FILE"
    /bin/launchctl bootstrap "$domain" "$PLIST_FILE"
  else
    /bin/launchctl kickstart "$domain/com.skillport.auto-refresh"
  fi
else
  /bin/launchctl bootstrap "$domain" "$PLIST_FILE"
fi
printf 'Installed and loaded com.skillport.auto-refresh\n'
