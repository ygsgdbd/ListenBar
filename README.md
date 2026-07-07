# ListenBar

ListenBar is a macOS menu bar utility for viewing local listening ports.

## MVP

- Pure menu bar app (`LSUIElement`)
- SwiftUI `MenuBarExtra`
- TCA reducer and testable port scanner dependency
- Lists TCP `LISTEN` ports and UDP sockets with concrete ports
- Groups ports by macOS app when available, otherwise by process PID
- Sends `SIGTERM` to the process that owns a selected listening port

## Development

```bash
rtk tuist generate
rtk xcodebuild test -skipMacroValidation -workspace ListenBar.xcworkspace -scheme ListenBar -destination 'platform=macOS'
```
