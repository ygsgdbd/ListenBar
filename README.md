<p align="center">
  <img src="Design/AppIcon/Previews/listenbar-icon-default.png" width="160" alt="ListenBar app icon">
</p>

<h1 align="center">ListenBar</h1>

<p align="center">A native macOS menu bar utility for seeing what is listening on your Mac.</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-0D96F6">
  <img alt="TCA" src="https://img.shields.io/badge/Architecture-TCA-7C3AED">
  <img alt="Xcode 26" src="https://img.shields.io/badge/Xcode-26-147EFB?logo=xcode&logoColor=white">
  <img alt="Universal Binary" src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-555555">
  <a href="https://github.com/ygsgdbd/ListenBar/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/ygsgdbd/ListenBar?display_name=tag&sort=semver&label=Latest%20Release"></a>
</p>

<p align="center">🇨🇳 <a href="README.zh-CN.md">简体中文</a> · 🇺🇸 <strong>English</strong></p>

## 🖼️ Screenshots

![ListenBar light appearance showing the main menu and process actions](Documentation/Screenshots/en-light.png#gh-light-mode-only)

![ListenBar dark appearance showing the main menu and process actions](Documentation/Screenshots/en-dark.png#gh-dark-mode-only)

## ✨ Highlights

- 🔎 **Find listeners at a glance.** Scan TCP `LISTEN` endpoints and UDP sockets with a concrete local port, then see their exposure, protocol, port, PID, process or app name, executable path, command line, inferred source, and resident memory when available.
- 🧩 **Understand which process owns each port.** Related helper processes are grouped under their owning macOS app, while command-line listeners remain separated by PID. Current-user processes are also distinguished from system or other-user processes.
- 🔗 **Open services and copy what you need.** Open eligible loopback TCP services at `http://localhost:<port>`, or copy URLs, ports, PIDs, paths, `lsof` commands, process details, and complete listener reports.
- 🔒 **Share diagnostics more safely.** Choose between full and redacted command-line copy actions to omit sensitive arguments when needed.
- 🛠️ **Inspect and manage processes.** Reveal executables in Finder, view native app or executable icons, quit or force-quit apps, and send `SIGTERM` or `SIGKILL` to individual processes, with confirmation for destructive or higher-risk actions.
- 🔄 **Keep the list current.** Refresh whenever the menu opens, use an optional 1-, 2-, or 5-second interval, disable automatic refresh, or check for updates manually through Sparkle.

## 🪶 Native and lightweight

- 🍎 **Truly native.** ListenBar's app business code is 100% Swift, built with SwiftUI and The Composable Architecture (TCA). It uses `MenuBarExtra` and `LSUIElement` instead of an Electron runtime or embedded WebView.
- 🪶 **Lightweight by design.** A focused menu bar utility does not need to ship an entire browser engine. ListenBar keeps its runtime and interface centered on the task of inspecting local listeners.
- 🎨 **At home on macOS.** The interface automatically follows Light and Dark Mode. Native SwiftUI menu controls adopt the system-provided Liquid Glass appearance where appropriate on macOS 26, while macOS 14 and macOS 15 retain their own native styling. ListenBar does not simulate Liquid Glass with custom visual effects. Releases are built with Xcode 26.2.

## 📦 Installation

### Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac (Universal Binary)

### Homebrew

```bash
brew install --cask ygsgdbd/tap/listenbar
```

Homebrew requires explicit trust for packages from third-party taps. Using the fully qualified cask name above trusts only `listenbar`, rather than every current and future package in `ygsgdbd/tap`.

### GitHub Releases

1. Download `ListenBar-macOS-universal.zip` from the [latest GitHub Release](https://github.com/ygsgdbd/ListenBar/releases/latest).
2. Unzip it and move `ListenBar.app` to `/Applications`.

### First launch and Gatekeeper

Current release builds are **unsigned and not notarized**. macOS may therefore block the first launch even when the app was downloaded from the official release page.

1. In Finder, Control-click or right-click `ListenBar.app`, choose **Open**, then choose **Open** again.
2. If macOS still blocks it, open **System Settings → Privacy & Security**, find the ListenBar warning, click **Open Anyway**, and confirm **Open**.

Only bypass Gatekeeper when you obtained the app from this repository's official GitHub Releases and trust the download.

## 🧪 Development and tests

The project currently contains **121 XCTest test methods** covering reducer behavior, settings persistence, port parsing and grouping, process metadata, menu presentation, screenshot fixtures, and Sparkle configuration.

Requirements: Xcode 26 and [Tuist](https://tuist.dev/).

```bash
tuist generate
xcodebuild test \
  -project ListenBar.xcodeproj \
  -scheme ListenBar \
  -destination 'platform=macOS' \
  -testLanguage zh-Hans \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```
