# Development Progress

## Current
- Branch: dev.
- Version: 0.1.8-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: bfe9b578802bf87ed418cb3c329684acfe787825 — Phase 6 integration/state-recovery hardening.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None. main remains exactly bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: reconcile the first broad in-game validation of the integrated Phase 1–6 test build, diagnose and fix only demonstrated defects, then decide release/promotion readiness.
- Scope boundary: Phase 6 code hardening is complete. The broad runtime test has begun and exposed at least one Lua error on the exact 0.1.8-dev test build; no unrelated feature work or architecture changes are authorized.

## Current Design / Development Contract

### Workflow / Branch Rules
- Active development occurs on dev.
- dev_rulebook.md is authoritative and read-only during ordinary addon work.
- DEV_PROGRESS.md is the sole live development/handoff source.
- dev_rulebook.md and DEV_PROGRESS.md are development-only and must never be promoted to or committed on main.
- pfQuest_Group.toc is the addon version source of truth.
- Every addon-affecting development revision must bump the dev version.

### Target / Architecture / Ownership
- Target: World of Warcraft 1.12.1 / Interface 11200 / Lua 5.0.3.
- pfQuest_Group is a separate companion addon and hard-depends on pfQuest; do not modify pfQuest source for normal implementation.
- Saved state is per-character in pfQuest_GroupDB.
- Keep the established one-main-Lua-file architecture unless concrete pressure justifies a deliberate split.
- Phase 4a remains the sole Guide/Tourist session owner.
- Phase 4b remains the sole Guide/Tourist instruction owner.
- Phase 2 remains the sole quest-state owner.
- Phase 5 remains the sole Guide/Tourist window/disparity presentation architecture.
- Group Progress is independent of Guide/Tourist mode.

### Protocol / Peer State
- Protocol prefix: PFQGROUP; protocol version: 1; SavedVariables schema: 1.
- Only actual current party members participate; discovery scans party1 through party4.
- Transport remains native Vanilla SendAddonMessage over PARTY and targeted WHISPER.
- Wire types remain HELLO (H), full-state request (R), full snapshot (F), and component delta (D).
- State synchronization remains component-based through RegisterStateComponent, SendDelta, and RequestFullSync.
- Registered synchronized components remain exactly session, quests, and instructions.
- Remote peer state is ephemeral and is removed when the player leaves the party.
- A newly established or changed peer boot id invalidates previously cached remote session/quest/instruction state. Compatible peers answer a newly established boot with HELLO plus full state and request the peer's full state, so both sides establish the boot boundary and current state.
- Full snapshots apply the session component before dependent components. Unknown components continue to be ignored.

### Quest-State Engine
- Local quest state is normalized from the Vanilla quest log while reusing pfQuest compatibility/data ownership.
- Numeric questID is authoritative when both sides have one; title fallback is used only when at least one side lacks a numeric ID.
- Later title-to-ID resolution migrates identity without a false accept/remove pair.
- Normalized quests carry title, completion state, and normalized objectives.
- Event-driven scans emit LOCAL_QUEST_ACTION with ACCEPT, PROGRESS, TURNIN, or REMOVE.
- Accept/turn-in actions carry NPC ID/name context when resolvable.
- Quest state remains the revisioned quests component with full/delta synchronization and gap recovery.
- Local quest state is not snapshotted before its first baseline scan. Remote revision 0 is treated as unready, not as an established empty quest log.
- Remote quest state is invalidated on peer restart, incompatibility, and party departure.

### Group Quest Progress
- The addon post-processes pfQuest's existing tracker; pfQuest source remains untouched.
- Only compatible current party peers are displayed, in party-slot order.
- Numeric questID is matched first and remains authoritative; title fallback is unresolved-ID compatibility only.
- Binary objectives append class icon plus check/cross status per compatible peer.
- Count objectives add one class-icon/name/progress row per compatible peer; a missing matching count objective displays --.
- Reusable tracker regions are hidden/restored as peers change and tracker dimensions are recalculated.

### Guide / Tourist Session and Instructions
- Modes remain Off, Guide, and Tourist. Commands remain /pfqgroup off, /pfqgroup guide, /pfqgroup tourist <player>, /pfqgroup status; /pfqg is an alias.
- Entering Guide from another mode creates a new Guide session id and guideActionSeq=0. Staying in the same Guide mode preserves both. Reload/relog preserves the active Guide session and sequence.
- Tourist follows one specific player and preserves that target through temporary absence.
- Tourist binds only when that compatible peer advertises Guide mode with a Guide session id. joinBaseline is the Guide's current guideActionSeq and remains fixed for that Guide session.
- A different Guide session id causes a fresh binding/baseline. Explicit non-Guide advertisement clears active binding/baseline but preserves Tourist mode and target. Turning Tourist Off clears target/binding/baseline.
- Guide ACCEPT/TURNIN actions create ordered instruction records using guideActionSeq. Records persist in pfQuest_GroupDB.instructions and synchronize through the existing instructions component.
- A Guide instruction record is validated before guideActionSeq advances.
- Guide sends the instruction delta before the corresponding session cursor delta. A bound Tourist uses the existing Guide session cursor to detect a missing instruction delta and requests the existing full-state resync path; no new scheduler, owner, component, or wire type exists.
- Remote instruction full snapshots are accepted only when coherent with the currently known remote Guide session. Same-session stale cursors cannot roll backward.
- Tourist pending instructions are selected-Guide/session scoped and include only seq > joinBaseline. Consumed instruction sequence numbers persist so reload/full resync does not replay completed work.
- Matching local Tourist ACCEPT/TURNIN consumes the earliest matching pending instruction; numeric questID is authoritative when both sides have one and title is fallback.

### Guide / Tourist Window and Disparities
- The existing compact movable Phase 5 window is the only Guide/Tourist presentation window and is shown only in Guide/Tourist mode.
- Guide/Tourist instruction rows use Blizzard-style yellow !/? markers. Tourist completion uses the existing completion event for ephemeral strike/fade/removal only.
- Guide disparities are derived presentation state only and compare current local Guide quests against ready remote quest state for compatible Tourists paired to the same Guide session.
- Unknown/unready remote quest state is never treated as missing.
- Current quest disparity is independent of Tourist joinBaseline.
- Disparity rows follow instruction rows and are ordered by party slot then quest title.
- Hidden disparity state remains pfQuest_GroupDB.session.hiddenDisparities, scoped to the current Guide session. Hide/Unhide and Show Hidden are presentation-only and do not revise/broadcast session state.
- Window position remains persisted under pfQuest_GroupDB.ui.guideWindow.

## Phase 6 Integration Hardening — Implemented
- Handoff verification passed before writing: dev exactly matched expected Phase 5b checkpoint 7df623aa3f77f216f60b2909c96f49785b96c6d3.
- Hardened peer boot establishment/restart recovery without changing protocol version or ownership.
- Made full-state application deterministic for session-dependent instruction state.
- Removed the pre-baseline false-empty quest window and made revision-0 remote quest state explicitly unready.
- Enforced numeric quest identity as authoritative when both local/remote sides have IDs.
- Hardened instruction/session ordering and added existing-full-sync recovery when the Guide session cursor proves a bound Tourist missed an instruction delta.
- Rejected instruction full snapshots that conflict with the currently established remote session.
- No Phase 4a/4b/2/5 owner was replaced or duplicated.

## Recent Relevant Commits
- 4c5c63f074923266566c36c51ce2718d0060166f — repository bootstrap on main.
- 746265a4561fedcb924bba729aef22458984d994 — Phase 1 foundation/protocol.
- d83669c6a476a5a7521a3308102a267c2e79a668 — Phase 2 quest-state engine.
- e3b988309054eb86a3ad39953bf5a39332168e83 — Phase 3 Group Progress.
- b7655c8bd7d7108b38ad19f271a456f9bcad78d4 — Phase 4a Guide/Tourist session foundation.
- 84fa3c77e327407a066fa1d9c3a5e7d41f7e89d5 — Phase 4b Guide/Tourist instruction behaviour.
- 5c142f5174d8d0d30ea544e09958bd43466e83fe — final Phase 5a instruction-window state.
- 6193dc5be9aaaefb85aebe5c711bb946560416b4 — Phase 5b disparity presentation/controls.
- bfe9b578802bf87ed418cb3c329684acfe787825 — Phase 6 integration/state-recovery hardening.

## Validation State

### Completed / User-Verified
- Repository, product direction, and staged development plan were confirmed by the user.
- Broad in-game testing has begun on 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825.
- The user reports a Lua error during that test. The exact error text/line/stack has not yet been supplied, so the defect is not yet localized and no runtime path is being marked passed on the basis of this report alone.

### Implemented / Awaiting Runtime Test
- Integrated Phase 1 foundation/protocol.
- Phase 2 local/remote quest-state engine.
- Phase 3 Group Progress tracker integration.
- Phase 4a Guide/Tourist session lifecycle and pairing.
- Phase 4b instruction creation/synchronization/baseline/consumption/recovery.
- Phase 5 Guide/Tourist window, completion presentation, current quest disparities, Hide/Unhide, and Show Hidden.
- Phase 6 boot/full-state/quest-readiness/numeric-identity/instruction-recovery hardening.

### Static / Automated Checks — Exact Phase 6 Addon State
Exact addon-affecting commit: bfe9b578802bf87ed418cb3c329684acfe787825.
- pfQuest_Group.lua blob: 2aeb9ed756936f27d3c69f341fa8acf437782182.
- locales/enUS.lua blob: 0122994a3bd10ef5d0202dc6794d0c7bd32c7655 (unchanged from Phase 5b).
- pfQuest_Group.toc blob: 0a19ef766fb6453a2967bb8ed91a7ec574f563e7.
- dev_rulebook.md blob: 1e054bc02930ece70445abd9ef910750193a9461 (unchanged).
- Version discipline: passed; 0.1.7-dev -> 0.1.8-dev.
- Scope check: passed. Relative to the Phase 5b handoff, the addon-affecting commit changes only pfQuest_Group.lua and pfQuest_Group.toc.
- main remains exactly 4c5c63f074923266566c36c51ce2718d0060166f.
- Protocol check: PFQGROUP protocol version remains 1.
- Ownership check: exactly one session component registration, one quests component registration, one instructions component registration, one Addon.SetMode definition, and one Guide/Tourist window initializer.
- UI structural count is unchanged from Phase 5b: 5 CreateFrame, 5 CreateFontString, and 3 CreateTexture call sites.
- Static later-Lua/API scan passed for the exact committed source: no string.match, string.gmatch, table.unpack, select(, RegisterAddonMessagePrefix, C_QuestLog, C_ChatInfo, or C_Timer tokens.
- Token-level local scan of the exact committed source: 144 actual top-level locals, all uniquely named, leaving 56 below Lua 5.0.3's 200-local top-level chunk limit. The highest scanned inner-function local/parameter/loop-variable pressure is about 25. This excludes the 200-local cap as the likely cause of the reported runtime error, but remains a static scan rather than a canonical Lua 5.0.3 compiler proof.
- Focused Phase 6 mocked integration harness passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. Coverage: session-first full snapshots; first-known/restarted boot invalidation and recovery; quest readiness/revision handling; numeric-ID-authoritative matching; cross-session instruction-full rejection; missed-instruction cursor resync; instruction validation before cursor mutation; instruction-delta-before-session-delta ordering.

### Checks Not Actually Runnable
- Exact full-file Lua 5.3.6 parser smoke: not run against the committed pfQuest_Group.lua blob because GitHub connector-backed repository bytes are not materialized into the executable container.
- Canonical Lua 5.0.3 compiler check: not run / unavailable against the exact Phase 6 blob. Seraphic8x2244/VanillaTemplate main at 6980e95476a72c47a461f7c78ce9e4f649c829f contains the canonical tools/lua50 checker and vendored Lua 5.0.3 source, and the executable environment has a working C compiler, but the private connector-backed checker/source and addon blob are not mounted into that executable environment.
- No in-game testing has been performed.

### Current Issues / Validation Debt
- Runtime failure observed: the user reports a Lua error on 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825 during the broad test. Exact error text/line/stack is still needed before changing addon code.
- Static triage does not indicate the Lua 5.0.3 200-local cap: the exact source has 144 top-level locals; the largest scanned inner-function local pressure is about 25.
- No obvious later-Lua syntax/API blacklist hit was found in the exact source, and the registered QUEST_WATCH_UPDATE / QUEST_FINISHED events are valid Vanilla-era events.
- The exact current runtime still lacks the canonical Lua 5.0.3 compiler pass because of connector/executable-environment separation.
- The exact current full file also lacks an executable-environment Lua 5.3.6 parser smoke for the same reason.
- No addon-affecting fix has been made yet because the demonstrated runtime failure has not been localized.

## Testing

### Last Runtime Test
- Version/commit: 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825.
- Passed: no point is being marked passed yet from the available report.
- Failed: at least one Lua error occurred during the broad in-game test; exact error text/line/stack not yet supplied.
- Not yet reconciled: the remaining broad-test points (startup/discovery, Group Progress, Guide/Tourist pairing, instructions, disparities, reload/recovery, party churn, window persistence, Off cleanup) until the user's point-by-point results are available.

### Next Runtime Test
First capture the exact Lua error text, file/line and stack from the 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825 run. Localize and fix only that demonstrated defect with normal version discipline, then resume/repeat the affected broad-test point before continuing release-readiness evaluation.

## Planned / Next Work
1. Obtain the exact Lua error text/file/line/stack from the user's 0.1.8-dev broad test.
2. Localize and fix only the demonstrated defect, with a required dev version bump for any addon-affecting revision.
3. Re-test the affected runtime path, then reconcile the rest of the broad-test results point by point.
4. After a known-good runtime state exists, review release/promotion readiness separately; do not treat development checks as a runtime test.

## Deferred / Out of Scope
- New feature work beyond the agreed v1 Phase 1–6 scope.
- Release/promotion to main before broad runtime validation is complete or any validation debt is explicitly accepted.
- dev_rulebook.md changes.

## Release / Promotion Notes
- dev_rulebook.md and DEV_PROGRESS.md must never be present on main.
- main remains the bootstrap baseline only.
- No validation debt has been accepted for release.
- External/runtime prerequisite: pfQuest.

## Exact Next Step
Capture the exact Lua error text, file/line and stack from the broad test of 0.1.8-dev (addon-affecting commit bfe9b578802bf87ed418cb3c329684acfe787825). Do not change addon code until that demonstrated failure is localized; do not begin unrelated feature work or promote to main.
