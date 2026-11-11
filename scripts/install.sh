#!/bin/sh
# Build, copy to ~/Applications/ipa-keys.app, and (re)load the launchd agent
# that starts it at login. --no-build installs dist/ipa-keys.app as it is.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/dist/ipa-keys.app"
DEST="$HOME/Applications/ipa-keys.app"
LABEL="cc.stanleywang.ipa-keys"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE="$HOME/.local/state/ipa-keys"
[ "${1:-}" = "--no-build" ] || "$ROOT/scripts/build-app.sh"
[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$STATE"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -fx "$DEST/Contents/MacOS/ipa-keys" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
# Restart after a crash, not after Quit (which exits cleanly).
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/Contents/MacOS/ipa-keys</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$STATE/launchd.log</string>
  <key>StandardErrorPath</key><string>$STATE/launchd.log</string>
</dict>
</plist>
PLIST
# bootout returns before the old job is gone; bootstrap fails with EIO
# until it is, so retry for a few seconds.
tries=0
until launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -lt 10 ] || { launchctl bootstrap "gui/$(id -u)" "$PLIST"; exit 1; }
  sleep 0.5
done
echo "installed $DEST and loaded $LABEL; log: $STATE/ipa-keys.log"
