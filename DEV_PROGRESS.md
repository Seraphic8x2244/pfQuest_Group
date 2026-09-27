# Development Progress

## Current
- Branch: `dev`
- Version: `0.1.0-dev` from `pfQuest_Group.toc`.
- Latest addon-affecting development commit: `746265a4561fedcb924bba729aef22458984d994` — Phase 1 foundation/protocol.
- Stable baseline: None; `main` is repository bootstrap only, not a runtime release.
- Goal: Implement the agreed v1 addon across staged development chats, then perform the first broad in-game test on the integrated build.
- Current scope boundary: Phase 1 is complete. Phase 2 has not started. No intermediate in-game testing is planned before the Phase 6 integrated test build.

## Current Design / Development Contract

### Workflow / Branch Rules
- Active addon development occurs on `dev`.
- `dev_rulebook.md` is authoritative and read-only during ordinary addon work.
- `dev_rulebook.md` and `DEV_PROGRESS.md` are development-only and must never be promoted to or committed on `main`.
- `main` is reserved for stable repository/release content.
- `pfQuest_Group.toc` is the addon version source of truth.

### Architecture / Ownership
- Target: World of Warcraft 1.12.1 / Interface 11200 / Lua 5.0.3.
- Project is a separate companion addon named `pfQuest_Group`.
- `pfQuest` is the authoritative local quest/tracker source; do not modify pfQuest source files directly for normal implementation.
- `pfQuest_Group.toc` hard-depends on `pfQuest`.
- Saved state is per-character in `pfQuest_GroupDB`.
- Group Progress and Guide/Tourist are separate systems; Group Progress must work without Guide/Tourist mode.
- Keep the implementation small and in one main Lua file unless later implementation pressure justifies a deliberate split.

### Phase 1 Foundation / Protocol
- Protocol prefix: `PFQGROUP`; protocol version: `1`; SavedVariables schema: `1`.
- Only actual current party members participate; discovery scans `party1` through `party4`. Remote peer state is ephemeral and removed when that player leaves the party.
- Transport uses Vanilla `SendAddonMessage` / `CHAT_MSG_ADDON` over PARTY and targeted WHISPER only.
- Wire message types: HELLO (`H`), full-state request (`R`), full snapshot (`F`) and component delta (`D`).
- Payloads use escaped key/value maps. Large payloads are chunked at 180 bytes with a 64-chunk cap and reassembled with duplicate/stale-fragment handling.
- A peer is compatible when its protocol version matches. HELLO carries addon version and a per-load boot id; a changed boot id invalidates stale remote session state.
- Party refresh broadcasts HELLO plus the local full snapshot. Receiving a compatible HELLO sends a targeted full snapshot back. State mutations should use deltas after synchronization.
- State synchronization is component-based. Phase 1 provides `RegisterStateComponent`, `SendDelta` and `RequestFullSync`; the built-in `session` component is the first consumer. Phase 2 quest/objective state should plug into this owner rather than create a parallel protocol.
- The protocol/sync layer is independent of Guide/Tourist mode so Group Progress can operate when Guide/Tourist is Off.

### Group Quest Progress
- Only current party members with compatible `pfQuest_Group` participate; maximum four remote players.
- Use actual class icons for remote players and class-coloured player names where names are shown.
- Binary objectives (`0/1`, `1/1`) remain on the existing objective line and append compact remote status as class icon + `✓` or `✗`.
- Multi-count objectives expand vertically with one additional row per compatible remote player.
- Vertical expansion is preferred over horizontally compressing up to five numeric progress values.

### Guide / Tourist
- Modes: Off, Guide, Tourist. A Tourist follows one specific Guide.
- Guide/Tourist uses a compact movable minimal window.
- Guide actions are one-line entries using Blizzard yellow `!` for accept and yellow `?` for hand-in.
- Accept presentation: `! NPC Name — Quest Name`.
- Hand-in presentation: `? NPC Name — Quest Name`.
- Tourist matching is automatic; no acknowledgement buttons.
- On matching Tourist action, strike through the instruction, fade for about 10 seconds, then remove it.

### Missing Quest / Disparity Handling
- Guide mode compares the Guide's current quest state against active Tourists.
- Show one disparity row per quest, followed by all Tourists missing it.
- Tourist names are class-coloured and preceded by actual class icons.
- Clicking a disparity row hides it; a `Show Hidden` control restores/views hidden rows.
- Hidden disparity state belongs to the active Guide session.

### Session State
- Session state persists across reload, relog and reconnect in `pfQuest_GroupDB.session`.
- Session fields currently owned by Phase 1: mode, revision, Guide name, Guide session id, Tourist join baseline and hidden-disparity state.
- Entering Guide mode creates a Guide session id; remaining in the same Guide session preserves it. Turning Guide mode Off clears Guide session state; re-entering Guide starts a new session.
- Tourist mode requires a specific Guide. The Guide session id and join baseline persist across reload/relog/reconnect and are not cleared merely because the remote Guide temporarily disappears from the party.
- Turning Tourist mode Off resets Tourist session state.
- When a Tourist joins a Guide session, the later Guide/Tourist phase must record that join as the instruction baseline and must not replay earlier Guide quest actions as instructions.
- Current quest disparity is separate from the instruction baseline and may show quests accepted by the Guide before the Tourist joined.

### Quest / NPC Data Model
- Quest identity: `questID` authoritative when available, quest title fallback.
- NPC identity: `mobID` authoritative when available, NPC name fallback.
- Guide messages should carry IDs plus display/fallback names when available.
- Quest/objective normalization and quest-action detection are Phase 2 work and are not implemented yet.

### Refresh / Event Behaviour
- Prefer event/state-driven updates over unnecessary continuous full rescans.
- Reuse pfQuest's existing state/refresh ownership where practical rather than creating parallel quest-state machinery.
- Quest disparity will refresh when relevant Guide or Tourist quest state changes and when session/sync state changes.

## Recent Relevant Commits
- `4c5c63f074923266566c36c51ce2718d0060166f` — initialize `main` with repository README only.
- `107ab19b47996cb0081735c6d1f94c35392d95eb` — add canonical unchanged `dev_rulebook.md` on `dev`.
- `407af9f3bf347bc51d1e493b823ff0f335c41c63` — plan staged implementation and authorize phased coding.
- `746265a4561fedcb924bba729aef22458984d994` — implement Phase 1 foundation/protocol.

## Completed / User-Verified
- Repository and initial feature/design direction were confirmed by the user.
- User explicitly required `dev_rulebook.md` and `DEV_PROGRESS.md` to remain off `main`.
- No runtime addon behaviour has been user-tested yet.

## Implemented / Awaiting Runtime Test
- Phase 1 addon skeleton and development metadata.
- Hard pfQuest dependency and per-character SavedVariables.
- Party discovery and peer lifecycle for up to four remote party members.
- Versioned protocol v1, presence handshake, chunked transport, full-state requests/snapshots and component deltas.
- Persistent local Guide/Tourist session state and synchronized remote session state.
- Extensible state-component and listener hooks for later phases.
- Phase 2+ quest normalization, tracker integration, Guide/Tourist commands/behaviour/UI and disparity computation are not implemented.

## Static / Automated Checks
Performed against the exact Phase 1 runtime contents committed as `746265a4561fedcb924bba729aef22458984d994`:
- Committed Git blob SHAs matched the locally checked files.
- `texluac -p` parser smoke check: passed for `pfQuest_Group.lua`. This is not claimed as the canonical Lua 5.0.3 compiler check.
- Mocked Vanilla event/message harness: passed database initialization, Guide/Tourist persistence/reset semantics, party startup sync, compatible HELLO/targeted full-state response, multi-chunk transport/reassembly, remote session reconstruction and peer pruning without clearing persistent local Tourist state.
- TOC/static metadata checks: passed Interface 11200, development title/version, pfQuest dependency, per-character SavedVariables and loader order.
- Static later-Lua/API scan: no `#` length syntax, varargs `...`, `string.match`, `string.gmatch`, `table.unpack`, `select`, `C_` APIs or `RegisterAddonMessagePrefix`; top-level local declarations counted 46.
- Canonical Lua 5.0.3 compiler check: **not run / unavailable in the executable environment**. The shell had a C compiler but did not have the VanillaTemplate checker files, and its network/DNS could not fetch GitHub. A Lua 5.0.3 checker exists in VanillaTemplate commit `9e32d8481e11bd31f1e0f91f3d25056a7382aaa8`, but repository access through the GitHub connector did not make those sources executable in the shell. Do not treat the parser smoke check as a 5.0.3 compiler pass.

## Current Issues
- Validation debt: Phase 1 still needs a real Lua 5.0.3 compiler pass when the canonical checker is available in the executable environment.
- No known implementation defect is recorded at this checkpoint.

## Testing

### Last Runtime Test
- Version/commit: None.
- Passed: None.
- Failed: None.
- Not tested: All Phase 1 in-game behaviour.

### Next Runtime Test
- Per the agreed staged plan, no intermediate in-game test is scheduled. The first broad in-game test remains the integrated Phase 6 build.

## Planned / Next Work
1. **Phase 1 — Foundation / protocol:** complete at `746265a4561fedcb924bba729aef22458984d994`.
2. **Phase 2 — Quest-state engine:** normalize local pfQuest quest/objective state, detect accept/remove/turn-in/progress changes, synchronize remote quest state, handle reload/group resync, and implement quest/NPC ID fallback handling.
3. **Phase 3 — Group Progress UI:** pfQuest tracker integration, binary class-icon + ✓/✗ statuses, expanded multi-count rows, class colours/icons, layout and group churn handling.
4. **Phase 4 — Guide/Tourist behaviour:** commands/modes, pairing, join baseline, accept/hand-in instructions, automatic Tourist completion, persistence/reset rules.
5. **Phase 5 — Guide/Tourist UI + disparity:** compact window, Blizzard !/?, strike-through/fade, missing-quest rows, hide/Show Hidden, layout/persistence.
6. **Phase 6 — Integration hardening / test build:** whole-system audit, stale/duplicate/order handling, SavedVariables/protocol robustness, final static/compiler checks, then one broad in-game test plan.

Each coding phase ends with available static/compiler checks, a clean commit checkpoint and an updated handoff. Runtime behaviour remains untested until Phase 6 unless the user changes that plan explicitly.

## Deferred / Out of Scope
- All Phase 2–6 implementation is deferred beyond this handoff.
- No tracker UI or Guide/Tourist UI was started in Phase 1.
- No in-game testing was performed in Phase 1.

## Release / Promotion Notes
- `dev_rulebook.md` and `DEV_PROGRESS.md` must never be present on `main`.
- Main-only/release-only content to preserve: current repository README until a later stable release changes it deliberately.
- Known validation debt accepted for release: None; current Lua 5.0.3 compiler-check debt is development validation debt, not a release acceptance.
- External/runtime prerequisite: pfQuest (`## Dependencies: pfQuest`).

## Exact Next Step
Begin **Phase 2 — Quest-state engine** from the Phase 1 implementation at `746265a4561fedcb924bba729aef22458984d994`. First verify the current `dev` handoff against the actual branch head, then add normalized local/remote quest and objective state through the existing component sync owner, including accept/remove/turn-in/progress detection and quest/NPC ID fallbacks. Stop before Phase 3 Group Progress UI. No in-game testing yet.
