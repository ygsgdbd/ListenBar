# ListenBar Roadmap

This file tracks feature ideas that are intentionally deferred from the current P1 hardening pass.

## Menu Bar Status Count

- Candidate: show port count or abnormal watch count beside the menu bar icon.
- Deferred because the current pass keeps the menu bar label icon-only.
- Revisit after auto refresh and watched ports produce stable signals.

## Hidden Process Configuration

- Candidate: hide system processes, hide specific app/process groups, or keep an ignore list.
- Deferred because it needs persistent preferences and clear hide identity semantics.
- Prefer bundle identifier or process group ID over PID-only hiding.

## Search

- Candidate: filter by port, app/process name, PID, source, command line, or path.
- Deferred to avoid changing the current `MenuBarExtra` menu interaction model.
- Revisit with either lightweight in-memory filtering or a richer popover-style UI.

## Watched Ports

- Candidate: watch `protocol + port`, pin watched ports, and show `free` or owner status.
- Deferred because it needs persistent configuration and clear conflict semantics.
- This should be the foundation for future notifications.

## Homebrew And LaunchAgent Attribution

- Candidate: parse LaunchAgent/LaunchDaemon plists, `launchctl`, and optional `brew services` output.
- Deferred because current source inference is heuristic and this needs evidence-based confidence labels.
- Avoid making strong claims unless a label, PID, or plist match is available.

## HTTP Title Probe

- Candidate: fetch localhost HTTP title for TCP ports.
- Deferred because automatic GET requests may create logs, redirects, or side effects.
- Revisit with short timeouts, caching, failure silence, and an off switch.

## History

- Candidate: keep snapshot history and show which process previously occupied a port.
- Deferred because it needs retention, persistence, and privacy policy.

## Notifications

- Candidate: notify when watched ports change owner or become occupied/free.
- Deferred until watched ports and auto refresh are stable enough to avoid noisy notifications.

## Diagnostic Report

- Candidate: copy a diagnostic report containing grouped ports, commands, errors, and environment hints.
- Deferred because exported data needs redaction rules and explicit user intent.
- A text-only report should avoid raw command lines unless the user chooses raw export.

## Dev Ports Mode

- Candidate: show Common Dev Ports or Localhost Only.
- Deferred because a reliable Dev Ports Only mode needs project/runtime context.
- Prefer an explainable Common Dev Ports filter over opaque heuristics.
