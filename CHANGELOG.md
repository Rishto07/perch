# Changelog

## Unreleased (Perch)

- New logo and icon set: the coral-bird artwork is now canonical SVG
  (`design/perch.svg`, `design/perch-menubar.svg`); every app icon, tray icon,
  menubar template, favicon and the GitHub social card are rendered from it.
- One-click setup for every agent: Settings → Other coding agents detects
  installed CLIs and installs agent hooks with backup/diff/confirm guarantees,
  plus a Connect-all button.
- Rebrand: new identity — Perch with Pip (`com.perch.*` identifiers,
  `perch-hook` relay, `perch.sock` / `perch-<sid>` transports). Legacy installs
  are detected, upgraded and cleaned up, never orphaned.
- Every coding agent gets a pill: Codex, OpenCode, Zcode and anything else.
  Blocking approvals stay Claude-only; other agents are observability-only.
