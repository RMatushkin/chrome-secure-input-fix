#!/bin/zsh
# Builds the watcher and installs it as a per-user LaunchAgent.
set -euo pipefail

LABEL="local.chrome-secure-input-fix"
REPO_DIR="${0:A:h}"
INSTALL_DIR="$HOME/Library/Application Support/ChromeSecureInputFix"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ChromeSecureInputFix.log"

command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install" >&2; exit 1; }

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"
echo "Building watcher..."
swiftc -O -swift-version 5 -o "$INSTALL_DIR/watcher" "$REPO_DIR/watcher.swift"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$INSTALL_DIR/watcher</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>StandardErrorPath</key><string>$LOG</string>
    <key>StandardOutPath</key><string>$LOG</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null

# Reload if already installed
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed. Log: $LOG"
