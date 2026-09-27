# Development Progress

## Current
- Branch: `dev`.
- Version: `0.1.2-dev` from `pfQuest_Group.toc`.
- Latest addon-affecting development commit: `e3b988309054eb86a3ad39953bf5a39332168e83` — Phase 3 Group Progress UI.
- Handoff checkpoint: the current `dev` head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None; `main` is repository bootstrap only, not a runtime release.
- Goal: Implement the agreed v1 addon across staged development chats, then perform the first broad in-game test on the integrated build.
- Current scope boundary: Phase 3 is complete. Phase 4 has not started. No intermediate in-game testing is planned before the Phase 6 integrated test build.

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
- A peer is compatible when its protocol version matches. HELLO carries addon version and a per-load boot id; a changed boot id invalidates stale remote component state.
- Party refresh broadcasts HELLO plus the local full snapshot. Receiving a compatible HELLO sends a targeted full snapshot back. State mutations use deltas after synchronization.
- State synchronization is component-based through `RegisterStateComponent`, `SendDelta` and `RequestFullSync`. The built-in `session` and `quests` components use this same owner.
- The protocol/sync layer is independent of Guide/Tourist mode so Group Progress can operate when Guide/Tourist is Off.

### Phase 2 Quest-State Engine
- Local quest state is normalized from the Vanilla quest log while reusing pfQuest compatibility/data ownership.
- Quest identity uses numeric `questID` when pfQuest/pfDatabase resolves one; title is the fallback key. A later title-to-ID resolution migrates identity without generating a false accept/remove pair.
- Each normalized quest contains title, completion state and normalized objectives. Count objectives carry current/required values; binary/non-count objectives normalize to 0/1 or 1/1 plus done/type/text.
- Quest scans are dirty/event-driven from `QUEST_LOG_UPDATE`, `QUEST_WATCH_UPDATE`, `QUEST_FINISHED` and explicit accept/turn-in/abandon hooks. The initial world-entry baseline is delayed and does not emit false action history.
- Local transitions emit `LOCAL_QUEST_ACTION` with `ACCEPT`, `PROGRESS`, `TURNIN` or `REMOVE`. Removal reason is `ABANDON` when captured, otherwise `UNKNOWN`.
- Accept and turn-in hooks capture nearby NPC display context before the underlying Vanilla/pfQuest wrapper runs.
- NPC identity resolves `mobID` from pfQuest quest start/end unit data when a captured localized NPC name uniquely matches, or when the quest has exactly one relevant unit. NPC name remains the fallback when an authoritative ID cannot be resolved.
- Quest state is the `quests` state component. Full snapshots and revisioned deltas use the Phase 1 transport; revision gaps request a full resync.
- Remote per-peer quest state is exposed through `GetRemoteQuestState(name)`; local normalized state is exposed through `GetLocalQuestState()`.
- Peer restart, protocol incompatibility and party departure invalidate stale remote quest state through the existing peer lifecycle.
- No Group Progress tracker/UI code or Guide/Tourist UI/behaviour was added in Phase 2.

### Group Quest Progress
- Phase 3 is implemented by post-processing pfQuest's existing tracker; pfQuest source is not modified.
- Only current party members with compatible `pfQuest_Group` participate; maximum four remote players, displayed in party-slot order.
- Quest matching consumes the Phase 2 quest-state owner: numeric `questID` first, title fallback.
- Remote players use the Blizzard class-icon atlas. Player names shown on count rows are class-coloured.
- Binary objectives (`0/1`, `1/1`) remain on the existing objective line and append one compact class icon + `✓`/`✗` pair per compatible remote player.
- Multi-count objectives expand vertically with one additional class-icon/name/progress row per compatible remote player.
- A compatible peer without the matching count quest/objective displays `--` rather than a false numeric value; a missing binary objective displays `✗`.
- Group UI regions are reused/hidden as peers change. Tracker button height and overall tracker layout are recalculated after local/remote quest-state or party/peer churn.
- Integration wraps `pfQuest.tracker.ButtonEvent`, rewires already-created tracker buttons and leaves future buttons on the wrapped handler. Group Progress remains independent of Guide/Tourist mode.

### Guide / Tourist
- Modes: Off, Guide, Tourist. A Tourist follows one specific Guide.
- Guide/Tourist uses a compact movable minimal window.
- Guide actions are one-line entries using Blizzard yellow `!` for accept and yellow `?` for hand-in.
- Accept presentation: `! NPC Name — Quest Name`.
- Hand-in presentation: `? NPC Name — Quest Name`.
- Tourist matching is automatic; no acknowledgement buttons.
- On matching Tourist action, strike through the instruction, fade for about 10 seconds, then remove it.
- Behaviour/UI remains deferred to Phases 4–5.

### Missing Quest / Disparity Handling
- Guide mode compares the Guide's current quest state against active Tourists.
- Show one disparity row per quest, followed by all Tourists missing it.
- Tourist names are class-coloured and preceded by actual class icons.
- Clicking a disparity row hides it; a `Show Hidden` control restores/views hidden rows.
- Hidden disparity state belongs to the active Guide session.
- Implementation remains Phase 5 work.

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
- Phase 2 now implements those fallbacks and supplies normalized quest/action context.
- Later Guide messages should carry IDs plus display/fallback names when available.

### Refresh / Event Behaviour
- Quest-state updates are event/state-driven; the frame's `OnUpdate` only services a pending short-debounce scan.
- pfQuest quest-log ID resolution and quest/NPC database ownership are reused rather than duplicated.
- Later quest disparity should refresh when relevant Guide or Tourist quest state changes and when session/sync state changes.

## Recent Relevant Commits
- `4c5c63f074923266566c36c51ce2718d0060166f` — initialize `main` with repository README only.
- `107ab19b47996cb0081735c6d1f94c35392d95eb` — add canonical unchanged `dev_rulebook.md` on `dev`.
- `407af9f3bf347bc51d1e493b823ff0f335c41c63` — plan staged implementation and authorize phased coding.
- `746265a4561fedcb924bba729aef22458984d994` — implement Phase 1 foundation/protocol.
- `c2bed9de66d40f2c2bc24cb1922d50b4839a73c7` — checkpoint Phase 1 handoff.
- `d83669c6a476a5a7521a3308102a267c2e79a668` — implement Phase 2 quest-state engine.
- `a0a53ca04f844ef28258684f9e96ff53cb71ba76` — checkpoint Phase 2 handoff.
- `e3b988309054eb86a3ad39953bf5a39332168e83` — implement Phase 3 Group Progress UI.

## Completed / User-Verified
- Repository and initial feature/design direction were confirmed by the user.
- User explicitly required `dev_rulebook.md` and `DEV_PROGRESS.md` to remain off `main`.
- No runtime addon behaviour has been user-tested yet.

## Implemented / Awaiting Runtime Test
- Phase 1 addon skeleton, party peer lifecycle, protocol v1, chunked full/delta component synchronization and persistent local session state.
- Phase 2 local quest/objective normalization with quest-ID fallback/migration.
- Phase 2 event-driven accept/remove/turn-in/progress detection with NPC ID/name context fallback.
- Phase 2 `quests` component full snapshot, deltas, peer revision tracking, gap recovery/full resync and public local/remote state accessors.
- Phase 3 pfQuest tracker integration for compatible party peers, including binary class-icon + ✓/✗ status, vertically expanded count rows with class-coloured names/progress, tracker relayout and group-churn cleanup.
- All Guide/Tourist behaviour/UI remains unimplemented.

## Static / Automated Checks
Performed against the exact Phase 3 runtime blob `707a0f40266c7c1d2902f01149cfccdef7336e20` and TOC version `0.1.2-dev` in implementation commit `e3b988309054eb86a3ad39953bf5a39332168e83`:
- Pre-write handoff verification: `dev` was exactly `a0a53ca04f844ef28258684f9e96ff53cb71ba76`; that checkpoint is one documentation-only commit after the Phase 2 implementation and changes only `DEV_PROGRESS.md`.
- Exact-byte verification: the locally checked `pfQuest_Group.lua` hashes with `git hash-object` to Git blob `707a0f40266c7c1d2902f01149cfccdef7336e20`.
- `texluac -p` parser smoke check: passed. The available `texluac` is Lua 5.3.6 and is not treated as the canonical Lua 5.0.3 compiler check.
- Static later-Lua/API scan: passed; no `string.match`, `string.gmatch`, `table.unpack`, `select(`, `RegisterAddonMessagePrefix` or modern `C_` APIs; top-level local declarations counted 110, below Lua 5.0.3's 200-local chunk limit.
- Phase 3 structural/scope scan: passed class-atlas, binary-status, count-row and all five refresh-listener expectations. The candidate changes only `pfQuest_Group.lua` plus the required TOC version bump relative to the Phase 2 checkpoint; existing Guide/Tourist token count, `SetMode` definition count and protocol-prefix count are unchanged.
- Mocked tracker/runtime harness: passed two-compatible-peer rendering, binary ✓/✗ state, class atlas use, class-coloured count rows, missing-count `--`, expanded layout sizing, compatible-peer churn cleanup and restoration of native two-objective height. Harness result: `mocked_phase3_runtime: PASS`.
- Canonical Lua 5.0.3 compiler check: **not run / unavailable in the executable environment**. The canonical VanillaTemplate checker and vendored Lua 5.0.3 sources are readable through repository access and a C compiler is available, but connector repository files are not materialized into the execution shell and the shell has no direct GitHub network access. Do not treat this as a compiler pass.
- No in-game testing was performed, by plan.

## Current Issues
- Validation debt: the exact Phase 3 runtime still needs the canonical Lua 5.0.3 compiler pass when the VanillaTemplate checker is executable in the shell.
- No known implementation defect is recorded at this checkpoint.

## Testing

### Last Runtime Test
- Version/commit: None.
- Passed: None.
- Failed: None.
- Not tested: All Phase 1–3 in-game behaviour.

### Next Runtime Test
- Per the agreed staged plan, no intermediate in-game test is scheduled. The first broad in-game test remains the integrated Phase 6 build.

## Planned / Next Work
1. **Phase 1 — Foundation / protocol:** complete at `746265a4561fedcb924bba729aef22458984d994`.
2. **Phase 2 — Quest-state engine:** complete at `d83669c6a476a5a7521a3308102a267c2e79a668`.
3. **Phase 3 — Group Progress UI:** complete at `e3b988309054eb86a3ad39953bf5a39332168e83`.
4. **Phase 4 — Guide/Tourist behaviour:** commands/modes, pairing, join baseline, accept/hand-in instructions, automatic Tourist completion, persistence/reset rules.
5. **Phase 5 — Guide/Tourist UI + disparity:** compact window, Blizzard !/?, strike-through/fade, missing-quest rows, hide/Show Hidden, layout/persistence.
6. **Phase 6 — Integration hardening / test build:** whole-system audit, stale/duplicate/order handling, SavedVariables/protocol robustness, final static/compiler checks, then one broad in-game test plan.

Each coding phase ends with available static/compiler checks, a clean commit checkpoint and an updated handoff. Runtime behaviour remains untested until Phase 6 unless the user changes that plan explicitly.

## Deferred / Out of Scope
- All Phase 4 Guide/Tourist behaviour remains deferred and has not started.
- All Phase 5 Guide/Tourist UI/disparity work remains deferred.
- Phase 6 integration hardening and broad in-game testing remain deferred.
- No in-game testing was performed in Phase 3.

## Release / Promotion Notes
- `dev_rulebook.md` and `DEV_PROGRESS.md` must never be present on `main`.
- Main-only/release-only content to preserve: current repository README until a later stable release changes it deliberately.
- Known validation debt accepted for release: None; current Lua 5.0.3 compiler-check debt is development validation debt, not a release acceptance.
- External/runtime prerequisite: pfQuest (`## Dependencies: pfQuest`).

## Exact Next Step
Begin **Phase 4 — Guide/Tourist behaviour** from the Phase 3 implementation at `e3b988309054eb86a3ad39953bf5a39332168e83`. First verify the current `dev` handoff against the actual branch head, then implement only the documented Phase 4 commands/modes, Guide/Tourist pairing, join baseline, accept/hand-in instruction state, automatic Tourist completion and persistence/reset rules. Stop before Phase 5 Guide/Tourist UI/disparity work. No in-game testing yet.
