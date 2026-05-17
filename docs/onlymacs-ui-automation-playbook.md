# OnlyMacs UI Automation Playbook

This file captures the latest reliable selectors and state-prep rules for autonomous OnlyMacs QA.

## Current desktop-control reality

1. Computer Use is currently blocked from `OnlyMacs`, `Codex`, and `Terminal` in this environment.
2. The practical fallback is `osascript` / `System Events` against the native app process.
3. The preferred path is now the app-owned automation command channel for popup/control-center surfacing; use raw window clicks only when a flow still genuinely requires them.
4. Treat this file as the source of truth for those selectors until direct Computer Use control is available.

## App and window identity

1. App process name: `OnlyMacsApp`
2. Approval window name: `OnlyMacs File Approval`
3. Automation popup window name: `OnlyMacs Popup`
4. Automation Control Center window name: `OnlyMacs Automation Control Center`

Current product note:

- the normal user-facing product is now popup-first
- setup and control-center windows are no longer part of the standard UX
- the automation control center remains a QA-only mirror surface

## Preferred automation hook

Use the state-directory command channel first:

1. Write a JSON file to `~/.local/state/onlymacs/automation/command-<id>.json`
2. Wait for `~/.local/state/onlymacs/automation/receipt-<id>.json`
3. Supported surfaces:
   - `popup`
   - `control_center`
4. Supported actions:
   - `open`
   - `close`
5. Optional section values:
   - `swarms`
   - `activity`
   - `sharing`
   - `models`
   - `setup`
   - `runtime`

For autonomous QA launches, start the app with:

- `open -na ./dist/OnlyMacs.app --args --onlymacs-automation-mode`

That mode keeps automation deterministic while the normal product stays popup-first.

Example payload:

```json
{
  "id": "example-123",
  "createdAt": "2026-04-18T14:00:00Z",
  "surface": "popup",
  "action": "open",
  "section": "models"
}
```

## Health-check rule

After every automation step that should surface or dismiss a window:

1. verify the `OnlyMacsApp` process is still alive
2. if it is not, capture the newest `~/Library/Logs/DiagnosticReports/OnlyMacsApp-*.ips`
3. stop the run immediately instead of waiting on a missing receipt or missing window

## Approval window structure

Current reliable accessibility structure for `OnlyMacs File Approval`:

1. Main content container identifier: `onlymacs.fileApproval.windowContent`
2. Preferred action button selectors:
   - label: `Share Selected Files`
   - identifier: `onlymacs.fileApproval.shareSelectedFiles`
   - keyboard: `Return` triggers the default action when the approval window is frontmost
3. Other approval controls:
   - `Choose Files` / `onlymacs.fileApproval.chooseFiles`
   - `Cancel` / `onlymacs.fileApproval.cancel`
4. Helpful container identifiers:
   - files column: `onlymacs.fileApproval.filesColumn`
   - suggestions list: `onlymacs.fileApproval.suggestionsList`
   - request details: `onlymacs.fileApproval.requestDetails`
   - selection summary: `onlymacs.fileApproval.selectionSummary`
   - warning summary: `onlymacs.fileApproval.warningSummary`
5. File rows expose stable identifiers with the prefix:
   - `onlymacs.fileApproval.fileRow.`

## Other stable automation selectors

1. Apply swarm: `onlymacs.swarm.apply`
2. Create private swarm:
   - name field: `onlymacs.swarm.create.nameField`
   - create button: `onlymacs.swarm.create`
   - create invite: `onlymacs.swarm.createInvite`
3. Join private swarm:
   - token field: `onlymacs.swarm.join.tokenField`
   - join button: `onlymacs.swarm.join`
4. Run on startup toggle: `onlymacs.settings.runOnStartup`
5. Launcher actions:
   - install/refresh: `onlymacs.launchers.install`
   - copy starter command: `onlymacs.launchers.copyStarterCommand`
   - repair PATH: `onlymacs.launchers.repairPath`
   - reopen tools: `onlymacs.launchers.reopenTools`
   - copy PATH fix: `onlymacs.launchers.copyPathFix`
6. Popup settings button: `onlymacs.popup.openSettings`
7. Menu bar status item: `onlymacs.menuBar.statusItem`
8. Popup root: `onlymacs.popup.windowContent`
9. Popup section buttons:
   - `onlymacs.popup.section.swarms`
   - `onlymacs.popup.section.activity`
   - `onlymacs.popup.section.sharing`
   - `onlymacs.popup.section.models`
   - `onlymacs.popup.section.setup`
   - `onlymacs.popup.section.runtime`
10. Automation Control Center root: `onlymacs.controlCenter.windowContent`
11. Automation Control Center section buttons:
   - `onlymacs.controlCenter.section.swarms`
   - `onlymacs.controlCenter.section.activity`
   - `onlymacs.controlCenter.section.sharing`
   - `onlymacs.controlCenter.section.models`
   - `onlymacs.controlCenter.section.setup`
   - `onlymacs.controlCenter.section.runtime`

## Current QA state prep

Before testing the trusted file-aware flow:

1. Ensure `dist/OnlyMacs.app` is running.
2. Ensure the runtime is on a private swarm, not `OnlyMacs Public`.
3. Ensure local share is published with at least one real model.
4. Current proven publish target:
   - `qwen2.5-coder:32b`

## Current bridge endpoints used by the harness

1. `GET /admin/v1/runtime`
2. `POST /admin/v1/runtime`
3. `GET /admin/v1/swarms`
4. `POST /admin/v1/swarms/create`
5. `GET /admin/v1/share/local`
6. `POST /admin/v1/share/publish`

## If selectors drift

Re-probe with AppleScript before changing the harness:

1. List windows:
   - ask `System Events` for `name of every window` of process `OnlyMacsApp`
2. Dump the approval tree recursively
3. Update this file with:
   - window name
   - button labels
   - identifiers
   - any remaining positional fallback

## Process rule

Every time a new automation selector or state-prep trick is discovered during QA, fold it back into:

1. this playbook
2. the autonomous QA script under `scripts/qa/`
3. the checkpoint notes when it changes the recursive loop
