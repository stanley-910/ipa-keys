#!/bin/sh
# Get the latest ipa-keys and install it:
#   scripts/update.sh
# Your settings file (~/.config/ipa-keys/config.txt) is never changed.
# IPA_KEYS_NO_INSTALL=1 stops after the download (for testing this script).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
APP="$HOME/Applications/ipa-keys.app"
LOG="$HOME/.local/state/ipa-keys/ipa-keys.log"

fail() {
  echo
  echo "Update stopped: $1"
  shift
  for line in "$@"; do echo "  $line"; done
  echo "Nothing was changed; the version you had is still installed."
  exit 1
}

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1 || ! xcrun --find git >/dev/null 2>&1; then
  fail "Apple's command line tools are missing. Run this, finish the window it opens, then run the update again:" \
    "xcode-select --install"
fi
git rev-parse --git-dir >/dev/null 2>&1 || fail "$ROOT is not a git copy of ipa-keys, so it cannot update itself."
[ -n "$(git remote)" ] || fail "this copy has nowhere to update from (no git remote)." \
  "Ask for the ipa-keys address, then run: git -C \"$ROOT\" remote add origin <address>"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
  || fail "this copy is not linked to a branch on the remote." \
    "Run: git -C \"$ROOT\" branch --set-upstream-to=origin/main"
CHANGED="$(git status --porcelain --untracked-files=no)"
[ -z "$CHANGED" ] || fail "files in the ipa-keys folder were changed by hand, and the update would overwrite them:" \
  $(echo "$CHANGED" | awk '{print $2}') \
  "(Your settings file is not one of them; it lives in ~/.config/ipa-keys.)" \
  "To undo those changes, run: git -C \"$ROOT\" checkout -- ."

echo "Checking for updates..."
git fetch --quiet || fail "could not reach $(git remote get-url "$(git remote | head -1)")." \
  "Check the internet connection and try again."
if ! git merge-base --is-ancestor HEAD "$UPSTREAM"; then
  if git merge-base --is-ancestor "$UPSTREAM" HEAD; then
    echo "This copy is newer than $UPSTREAM; nothing to download."
  else
    fail "this copy has its own commits that are not on $UPSTREAM, so it cannot simply move forward." \
      "Ask for help merging them."
  fi
fi
BEFORE="$(git rev-parse --short HEAD)"
git pull --ff-only --quiet || fail "git could not move forward to the latest version (see the message above)."
AFTER="$(git rev-parse --short HEAD)"
if [ "$BEFORE" = "$AFTER" ]; then echo "Already have the latest code ($AFTER)."
else echo "Downloaded $BEFORE -> $AFTER:"; git log --format='  %s' "$BEFORE..$AFTER"; fi

[ "${IPA_KEYS_NO_INSTALL:-}" = 1 ] && { echo "(not installing: IPA_KEYS_NO_INSTALL=1)"; exit 0; }

echo "Building and installing..."
STARTED="$(date '+%Y-%m-%d %H:%M:%S')"
"$ROOT/scripts/install.sh" || fail "the build or install failed (see the messages above)."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :IPAKeysCommit' "$APP/Contents/Info.plist" 2>/dev/null)"
STATUS=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  STATUS="$(awk -v t="$STARTED" '$1" "substr($2,1,8) >= t' "$LOG" 2>/dev/null | grep -E 'ready|waiting for Accessibility|could not' | tail -1)"
  [ -n "$STATUS" ] && break
  sleep 0.5
done
echo
echo "ipa-keys $VERSION ($COMMIT, $(git log -1 --format=%cd --date=format:'%d %b %Y')) is installed."
case "$STATUS" in
  *ready*) echo "It is running." ;;
  *waiting*) echo "It is running but needs Accessibility: System Settings > Privacy & Security > Accessibility, turn on ipa-keys." ;;
  *) echo "It did not report in yet; check the menu bar for ə, or the log: $LOG" ;;
esac
echo "Your settings file was not changed."
# New default symbols never reach an existing settings file; list them.
"$APP/Contents/MacOS/ipa-keys" --missing-defaults 2>/dev/null || true
