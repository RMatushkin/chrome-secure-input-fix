#!/bin/zsh
# Stops and removes the LaunchAgent and installed files.
set -uo pipefail

LABEL="local.chrome-secure-input-fix"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/ChromeSecureInputFix"
rm -f "$HOME/Library/Logs/ChromeSecureInputFix.log"

echo "Uninstalled. Chrome launches normally again (without the flag) from its next start."
