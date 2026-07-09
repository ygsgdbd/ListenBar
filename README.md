# ListenBar

ListenBar is a macOS menu bar utility for viewing local listening ports.

## Features

- Pure menu bar app (`LSUIElement`)
- SwiftUI `MenuBarExtra`
- TCA reducer and testable port scanner dependency
- Lists TCP `LISTEN` ports and UDP sockets with concrete ports
- Groups ports by macOS app when available, otherwise by process PID
- Supports `SIGTERM` quit and `SIGKILL` force kill actions with confirmation for risky targets
- Supports Sparkle-powered manual update checks from the menu

## Development

```bash
rtk tuist generate
rtk xcodebuild test \
  -project ListenBar.xcodeproj \
  -scheme ListenBar \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

## Installation

```bash
brew tap ygsgdbd/tap
brew install --cask listenbar
```

You can also download `ListenBar-macOS-universal.zip` from GitHub Releases.

## Releases

Releases are created by pushing a `vX.Y.Z` tag. The GitHub Actions workflow builds a universal macOS app, publishes `ListenBar-macOS-universal.zip`, generates `checksums.txt`, signs and uploads `appcast.xml` for Sparkle, and updates `ygsgdbd/homebrew-tap`.

Before the first release, set these repository secrets on `ygsgdbd/ListenBar`:

```bash
gh secret set SPARKLE_ED_PRIVATE_KEY --repo ygsgdbd/ListenBar < /path/to/listenbar-sparkle-ed-private-key
gh secret set HOMEBREW_TAP_TOKEN --repo ygsgdbd/ListenBar --body "$HOMEBREW_TAP_TOKEN"
```

The Sparkle public key is embedded in `Project.swift`; keep the matching private key out of the repository.
