#!/bin/sh
# Build, install as ~/Applications/ipa-keys.app, and (re)load the launchd
# agent that starts it at login. --no-build installs dist/ipa-keys.app as is.
#
# The running version is replaced only once the new one is copied and
# checked, and kept until the new one has started; if it doesn't start, the
# old one is put back. Exit status: 1 tools missing, 2 build failed,
# 3 copy failed, 4 new version didn't start (old one put back), 5 putting
# the old one back failed too. In 1-4 the version you had is still installed.
# (IPA_KEYS_APP_DIR, IPA_KEYS_AGENT_DIR and IPA_KEYS_LABEL are for testing.)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/dist/ipa-keys.app"
APPS="${IPA_KEYS_APP_DIR:-$HOME/Applications}"
DEST="$APPS/ipa-keys.app"
NEW="$APPS/.ipa-keys.app.new"
OLD="$APPS/.ipa-keys.app.old"
LABEL="${IPA_KEYS_LABEL:-cc.stanleywang.ipa-keys}"
AGENTS="${IPA_KEYS_AGENT_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$AGENTS/$LABEL.plist"
STATE="$HOME/.local/state/ipa-keys"
EXE="Contents/MacOS/ipa-keys"
DOMAIN="gui/$(id -u)"
if [ "${1:-}" != "--no-build" ]; then
  if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
    echo "Apple's command line tools are missing. Run this, finish the window it opens, then try again:" >&2
    echo "  xcode-select --install" >&2
    exit 1
  fi
  # A signing certificate keeps the Accessibility grant across updates.
  # Making one may show a macOS password prompt for the keychain.
  if [ -z "${IPA_KEYS_SIGN_IDENTITY:-}" ] \
     && ! security find-identity -v -p codesigning 2>/dev/null | grep -qE '"(ipa-keys-dev|dictate-dev)"'; then
    echo "making a signing certificate (macOS may ask for your login password)"
    "$ROOT/scripts/make-cert.sh" || {
      echo "could not make the certificate; installing without it. To fix, run:" >&2
      echo "  $ROOT/scripts/make-cert.sh" >&2
    }
  fi
  "$ROOT/scripts/build-app.sh" || { echo "install: the build failed; the installed version was not touched" >&2; exit 2; }
fi
[ -d "$SRC" ] || { echo "install: missing $SRC; the installed version was not touched" >&2; exit 2; }
mkdir -p "$APPS" "$AGENTS" "$STATE"

# 1. Stage the new version next to the old one and check it.
rm -rf "$NEW"
if ! cp -R "$SRC" "$NEW" 2>/dev/null || ! codesign --verify "$NEW" 2>/dev/null; then
  rm -rf "$NEW" 2>/dev/null || true
  echo "install: copying the new version into $APPS failed (disk full or no permission); the installed version was not touched" >&2
  exit 3
fi
# Restart after a crash, not after Quit (which exits cleanly).
cat > "$PLIST.new" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/$EXE</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$STATE/launchd.log</string>
  <key>StandardErrorPath</key><string>$STATE/launchd.log</string>
</dict>
</plist>
PLIST

stop() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  pkill -fx "$DEST/$EXE" 2>/dev/null || true
  i=0
  while pgrep -fx "$DEST/$EXE" >/dev/null 2>&1 && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
}

# bootout returns before the old job is gone; bootstrap fails with EIO
# until it is, so retry for a few seconds.
load() {
  i=0
  until launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; do
    i=$((i + 1))
    [ $i -lt 10 ] || return 1
    sleep 0.5
  done
}

# Started, and still the same process two seconds later (not crashing).
started() {
  sleep 3
  pid="$(pgrep -fx "$DEST/$EXE" | head -1)"
  [ -n "$pid" ] || return 1
  sleep 2
  kill -0 "$pid" 2>/dev/null
}

# 2. Stop the old version and swap the bundles; the old one is kept.
stop
rm -rf "$OLD"
[ -f "$PLIST" ] && cp "$PLIST" "$PLIST.old"
if [ -d "$DEST" ]; then mv "$DEST" "$OLD"; fi
mv "$NEW" "$DEST"
mv "$PLIST.new" "$PLIST"

# 3. Start it. If it doesn't run, put the old version back.
if load && started; then
  rm -rf "$OLD"
  rm -f "$PLIST.old"
  echo "installed $DEST and loaded $LABEL; log: $STATE/ipa-keys.log"
  exit 0
fi
echo "install: the new version did not start; putting the previous one back" >&2
stop
if [ -d "$OLD" ]; then
  rm -rf "$DEST" && mv "$OLD" "$DEST" || { echo "install: could not put the previous version back; run scripts/install.sh again" >&2; exit 5; }
  [ -f "$PLIST.old" ] && mv "$PLIST.old" "$PLIST"
  if load && started; then
    echo "install: the previous version is back and running" >&2
  else
    echo "install: the previous version is back but did not start; see $STATE/ipa-keys.log" >&2
  fi
  exit 4
fi
echo "install: there was no previous version to put back; see $STATE/ipa-keys.log" >&2
exit 5
