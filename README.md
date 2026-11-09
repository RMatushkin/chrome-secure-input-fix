# chrome-secure-input-fix

A small macOS LaunchAgent that keeps Google Chrome running with

```
--disable-features=RWHVMacHasFocusReturnsFalseForNonKeyWindow
```

to work around a Chrome 156+ bug where Chrome **keeps macOS Secure Input enabled** after you focus a password field and switch to another app.

## The problem

While an app holds Secure Input, other apps can't observe or synthesize keystrokes. Symptoms:

- Logi Options+ keystroke / shortcut actions on mouse buttons and keyboards stop working
  ([Logitech article](https://support.logi.com/hc/en-us/articles/360023189334-Logitech-Options-and-Options-issues-when-Secure-Input-is-enabled))
- Global hotkeys, text expanders (TextExpander, Typinator, Alfred snippets), Keyboard Maestro, etc. stop working

Check who holds it:

```sh
ioreg -l -d 1 -w 0 | grep -o '"kCGSSessionSecureInputPID"=[0-9]*'
```

If the PID is Google Chrome, the usual "fix" is to quit Chrome.

### Root cause

Since Chrome 156, `RenderWidgetHostViewMac::HasFocus()` returns false for a non-key window
(feature `RWHVMacHasFocusReturnsFalseForNonKeyWindow`, enabled by default). As a result,
deactivating Chrome no longer releases the password-input Secure Input enabler.
Tracked as Chromium issue [567613584](https://issues.chromium.org/issues/567613584).
Analysis: [miyaoka/tugime#79](https://github.com/miyaoka/tugime/pull/79).

Disabling that feature restores the pre-156 behavior. Chrome on macOS has no persistent
way to set command-line switches, so this watcher enforces it.

## How it works

`watcher` listens for application launches. When Chrome starts as a plain user launch,
i.e. **with no command-line arguments** (Dock, Spotlight, a link from another app, login item…),
it quits Chrome gracefully and relaunches it with the flag plus `--restore-last-session`,
so the same windows and tabs come back. This takes ~2–3 seconds and only happens at launch.
If Chrome refuses to quit within ~15 s (e.g. a "Leave site?" dialog), the watcher gives up for that launch.

Chrome instances started **with their own arguments** are never touched — this covers
[Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp), Puppeteer,
Playwright, Selenium and `open -a "Google Chrome" --args …`. Restarting them would drop their
`--user-data-dir` / `--remote-debugging-*` setup and break the automation. Such launches are logged.

## Install

Requires the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/RMatushkin/chrome-secure-input-fix.git
cd chrome-secure-input-fix
./install.sh
```

Installs:

| Path | Purpose |
|---|---|
| `~/Library/Application Support/ChromeSecureInputFix/watcher` | compiled watcher |
| `~/Library/LaunchAgents/local.chrome-secure-input-fix.plist` | starts it at login, restarts it if it dies |
| `~/Library/Logs/ChromeSecureInputFix.log` | log |

Verify: open `chrome://version` — the **Command Line** row should contain the flag.

## Uninstall

Once Google ships a fix:

```sh
./uninstall.sh
```

## Limitations

- A second trigger reported on Chromium 154 (submitting a login form with Enter) is not
  covered by this flag. If Secure Input still gets stuck, quit Chrome with ⌘Q.
- Google may remove the feature flag in a future version; the flag then simply does nothing.
- Chromium-based browsers other than Chrome (Edge, Brave, Arc…) are not handled.
