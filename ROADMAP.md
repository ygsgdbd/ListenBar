# ListenBar Roadmap

This file tracks current product priorities, deferred ideas, and features that are not planned for the current direction.

## Menu Bar Status Count

- Candidate: show port count or abnormal watch count beside the menu bar icon.
- Deferred because the current pass keeps the menu bar label icon-only.
- Revisit after auto refresh and watched ports produce stable signals.

## Hidden Process Configuration

- Implemented: persistently ignore individual app or executable groups using bundle identifiers or absolute executable paths.
- The menu supports restoring individual ignored items or clearing the full ignore list.
- Deferred extension: optional category filters such as hiding system processes; define category and precedence semantics before implementation.

## Search

- Not planned for the current menu-based product direction.
- `MenuBarExtra` cannot provide the intended inline search-field experience without moving to a richer popover or window.
- Watched ports and port change history should reduce the need to search the full listener list.

## Watched Ports

- Current priority: watch and persist `protocol + port` entries.
- Show whether each watched port is free or occupied and identify its current owner when available.
- Define stable identity and conflict semantics before adding notifications or menu bar status counts.

## Homebrew And LaunchAgent Attribution

- Recorded for a later pass: parse LaunchAgent/LaunchDaemon plists, `launchctl`, and optional `brew services` output.
- The goal is more reliable service-source attribution than the current heuristic inference.
- Deferred because it needs evidence-based confidence labels.
- Avoid making strong claims unless a label, PID, or plist match is available.

## LaunchAtLogin Rollback Hardening

- Deferred: the current failed-install rollback removes the committed fallback plist to avoid reporting login launch as enabled when no service is loaded.
- Preserve any valid fallback plist that existed before installation and restore it if the replacement attempt fails.
- Re-bootstrap the previous service when needed so one failed enable attempt does not permanently discard a working login configuration.

## HTTP Title Probe

- Candidate: fetch localhost HTTP title for TCP ports.
- Deferred because automatic GET requests may create logs, redirects, or side effects.
- Revisit with short timeouts, caching, failure silence, and an off switch.

## History

- Current priority: record changes for watched ports.
- Track transitions such as `free -> occupied`, `occupied -> free`, and owner changes.
- Keep the first version focused on watched ports instead of retaining every listener snapshot.
- Retention duration, persistence, and privacy rules still need to be defined.

## Notifications

- Candidate: notify when watched ports change owner or become occupied/free.
- Deferred until watched ports and auto refresh are stable enough to avoid noisy notifications.

## Diagnostic Report

- Low priority enhancement: extend the existing Copy Full Information action into a fuller diagnostic report.
- The current export already includes grouped listener details, sources, URLs, and executable paths.
- Future additions may include scan errors, app/version details, and environment hints.
- Command lines require redaction rules, and raw export must remain an explicit user choice.

## Manual Refresh

- Low priority: allow a one-time refresh without changing the saved automatic refresh mode.
- The existing menu-open and interval-based refresh modes cover the primary workflow.

## Automation Integrations

- Low priority: expose selected ListenBar actions through App Intents.
- A future Raycast plugin may consume those actions or provide a dedicated ListenBar integration.
- Define the safe read-only action surface before exposing process termination or other destructive operations.

## Dev Ports Mode

- Candidate: show Common Dev Ports or Localhost Only.
- Deferred because a reliable Dev Ports Only mode needs project/runtime context.
- Prefer an explainable Common Dev Ports filter over opaque heuristics.
