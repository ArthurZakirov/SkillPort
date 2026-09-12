#!/bin/bash
set -e

SKILLPORT_REPO=
SKILL_REPOS_FILE=
GUIDANCE_REPO=
GUIDANCE_SOURCE=
NPX_BIN=
PYTHON_BIN=
GH_BIN=
PRIVATE_REPOS=()
PUBLIC_REPOS=()
REQUIRED_SKILLS=()
CONFIG_FILE="${HOME}/.config/SkillPort/auto-refresh.conf"
PLIST_FILE="${HOME}/Library/LaunchAgents/com.skillport.auto-refresh.plist"
STATE_DIR="${HOME}/Library/Application Support/SkillPort"
DRY_RUN=0
REPLACE=0

usage() {
  cat <<'EOF'
Usage: install-macos-auto-refresh.sh [options]

Required:
  --skillport-repo <path>
  --repos-file <path>
  --guidance-repo <path>
  --guidance-source <path>

Optional:
  --push-private-repo <path>  Repeatable private-repository push opt-in.
  --push-public-repo <path>   Repeatable public opt-in; starts review-blocked.
  --required-global-skill <name>  Repeatable post-sync discovery check.
  --npx-bin <path>
  --python-bin <path>
  --gh-bin <path>
  --replace-existing
  --dry-run

The LaunchAgent runs at login/load and every 15 minutes. Missed calendar runs
are coalesced by launchd and run after wake. Public push approval is per exact
HEAD and must be added manually to the private config after review.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skillport-repo) SKILLPORT_REPO="$2"; shift 2;;
    --repos-file) SKILL_REPOS_FILE="$2"; shift 2;;
    --guidance-repo) GUIDANCE_REPO="$2"; shift 2;;
    --guidance-source) GUIDANCE_SOURCE="$2"; shift 2;;
    --npx-bin) NPX_BIN="$2"; shift 2;;
    --python-bin) PYTHON_BIN="$2"; shift 2;;
    --gh-bin) GH_BIN="$2"; shift 2;;
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
NPX_BIN="${NPX_BIN:-$(command -v npx || true)}"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || true)}"
GH_BIN="${GH_BIN:-$(command -v gh || true)}"

for required_path in "$SKILLPORT_REPO" "$SKILL_REPOS_FILE" "$GUIDANCE_REPO" "$GUIDANCE_SOURCE" "$NPX_BIN" "$PYTHON_BIN" "$GH_BIN"; do
  case "$required_path" in /*) ;; *) printf 'install-macos-auto-refresh: every path must be absolute\n' >&2; exit 2;; esac
done
[ -x "$SKILLPORT_REPO/scripts/skillport-auto-refresh.sh" ] || { printf 'install-macos-auto-refresh: refresh script is not executable\n' >&2; exit 2; }
[ -f "$SKILL_REPOS_FILE" ] || { printf 'install-macos-auto-refresh: repo manifest is missing\n' >&2; exit 2; }
[ -d "$GUIDANCE_REPO/.git" ] || { printf 'install-macos-auto-refresh: guidance repository is invalid\n' >&2; exit 2; }
[ -f "$GUIDANCE_SOURCE" ] || { printf 'install-macos-auto-refresh: guidance source is missing\n' >&2; exit 2; }
[ -x "$NPX_BIN" ] && [ -x "$PYTHON_BIN" ] && [ -x "$GH_BIN" ] || { printf 'install-macos-auto-refresh: required executable is missing\n' >&2; exit 2; }

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
  printf 'SKILLPORT_REPO=%s\n' "$SKILLPORT_REPO"
  printf 'SKILL_REPOS_FILE=%s\n' "$SKILL_REPOS_FILE"
  printf 'GUIDANCE_REPO=%s\n' "$GUIDANCE_REPO"
  printf 'GUIDANCE_SOURCE=%s\n' "$GUIDANCE_SOURCE"
  printf 'STATE_DIR=%s\n' "$STATE_DIR"
  printf 'NPX_BIN=%s\n' "$NPX_BIN"
  printf 'PYTHON_BIN=%s\n' "$PYTHON_BIN"
  printf 'GH_BIN=%s\n' "$GH_BIN"
  for repo_dir in "${PRIVATE_REPOS[@]}"; do printf 'PUSH_PRIVATE_REPO=%s\n' "$repo_dir"; done
  for repo_dir in "${PUBLIC_REPOS[@]}"; do printf 'PUSH_PUBLIC_REPO=%s|REVIEW_REQUIRED\n' "$repo_dir"; done
  for skill_name in "${REQUIRED_SKILLS[@]}"; do printf 'REQUIRED_GLOBAL_SKILL=%s\n' "$skill_name"; done
} > "$TEMP_CONFIG"

refresh_script_xml=$(escape_xml "$SKILLPORT_REPO/scripts/skillport-auto-refresh.sh")
config_file_xml=$(escape_xml "$CONFIG_FILE")
state_dir_xml=$(escape_xml "$STATE_DIR")
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
    <string>--config</string>
    <string>${config_file_xml}</string>
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
  <string>$(escape_xml "$SKILLPORT_REPO")</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SKILLPORT_STATE_DIR</key>
    <string>${state_dir_xml}</string>
  </dict>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$TEMP_PLIST" >/dev/null

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

/bin/mkdir -p "$(/usr/bin/dirname "$CONFIG_FILE")" "$(/usr/bin/dirname "$PLIST_FILE")" "$STATE_DIR"
/usr/bin/install -m 600 "$TEMP_CONFIG" "$CONFIG_FILE"
/usr/bin/install -m 644 "$TEMP_PLIST" "$PLIST_FILE"
/bin/chmod 700 "$STATE_DIR"

domain="gui/$(/usr/bin/id -u)"
if /bin/launchctl print "$domain/com.skillport.auto-refresh" >/dev/null 2>&1; then
  /bin/launchctl kickstart "$domain/com.skillport.auto-refresh"
else
  /bin/launchctl bootstrap "$domain" "$PLIST_FILE"
fi
printf 'Installed and loaded com.skillport.auto-refresh\n'
