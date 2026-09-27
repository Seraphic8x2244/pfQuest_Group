# Development Progress

## Current
- Branch: dev.
- Version: 0.1.11-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: 2affbf36a4435fec245c58a04a21740686a7d3f8 — replace pfQuest binary objective `0/1` / `1/1` suffixes with the active Group Progress status presentation, on top of the communications and peer-quest filtering fixes.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None. main remains exactly bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: reconcile the first broad in-game validation of the integrated Phase 1–6 test build, diagnose and fix only demonstrated defects, then decide release/promotion readiness.
- Scope boundary: Phase 6 code hardening is complete. Broad runtime testing found the Vanilla addon-WHISPER transport defect plus two Group Progress presentation defects: status for peers without the tracked quest, and binary rows retaining pfQuest's native `0/1` / `1/1` suffix beside the tick/cross overlay. All three are fixed on dev and await focused retest; no unrelated feature work or architecture changes are authorized.

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
- Transport remains native Vanilla SendAddonMessage over PARTY. WoW 1.12 SendAddonMessage does not support WHISPER; logical directed recovery validates the requested party peer but uses the PARTY addon channel.
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
- Binary objectives append class icon plus check/cross status for compatible peers who currently have the tracked quest; the overlay is independent of Guide/Tourist mode. While this overlay is active, only the terminal numeric `0/1` or `1/1`-style progress token is removed from pfQuest's objective fontstring; the original text/color is retained for restoration.
- A compatible PFQG peer who does not have the tracked quest contributes no class icon/status for that quest.
- Count objectives add one class-icon/name/progress row per compatible peer who has the tracked quest; a missing matching objective within an otherwise matched quest displays --.
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
- 5a9de26b4978bb943cef371cc27b5886e74a2884 — replace invalid Vanilla addon-message WHISPER transport with PARTY transport; version 0.1.9-dev.
- a736701f8bb26af2309a415b6885aa7cce52e313 — hide Group Progress status for compatible peers without the tracked quest; version 0.1.10-dev.
- 2affbf36a4435fec245c58a04a21740686a7d3f8 — strip pfQuest's terminal binary `0/1` / `1/1` token while the Group Progress binary overlay is active; version 0.1.11-dev.

## Validation State

### Completed / User-Verified
- Repository, product direction, and staged development plan were confirmed by the user.
- Broad in-game testing began on 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825.
- Basic Guide/Tourist behavior appears to work in that run; this is a partial runtime result, not exhaustive validation of every session/instruction/recovery path.
- The reported Lua error is localized to aux-addon's ChatThrottleLib rejecting pfQuest_Group's SendAddonMessage(..., "WHISPER", target) path as an unknown addon chat type. WoW 1.12 addon messages support PARTY/RAID/GUILD/BATTLEGROUND; addon WHISPER was added later.
- Group Progress also showed/was specified to show PFQG peer status only when that peer has the tracked quest; peers without the quest must be omitted.
- Follow-up runtime feedback on 0.1.10-dev: the binary tick/cross overlay was present but pfQuest's native `0/1` or `1/1` count text remained visible on the same objective row.

### Implemented / Awaiting Runtime Test
- 0.1.9+ delta: all addon transport uses the Vanilla-supported PARTY addon channel; no four-argument addon-WHISPER send remains.
- 0.1.10+ delta: Group Progress filters compatible peers per tracked quest before creating binary/count status regions, so peers without that quest are omitted while the overlay remains mode-independent.
- 0.1.11-dev delta: in the binary branch only, Group Progress strips a terminal numeric fraction from the saved pfQuest objective text before rendering peer status. Multi-count objectives remain on the existing count-row path and the untouched base text is restored whenever the overlay is not applicable.
- Integrated Phase 1 foundation/protocol.
- Phase 2 local/remote quest-state engine.
- Phase 3 Group Progress tracker integration.
- Phase 4a Guide/Tourist session lifecycle and pairing.
- Phase 4b instruction creation/synchronization/baseline/consumption/recovery.
- Phase 5 Guide/Tourist window, completion presentation, current quest disparities, Hide/Unhide, and Show Hidden.
- Phase 6 boot/full-state/quest-readiness/numeric-identity/instruction-recovery hardening.

### Static / Automated Checks — Exact Phase 6 Addon State
Exact original Phase 6 test commit: bfe9b578802bf87ed418cb3c329684acfe787825.
Current addon-affecting retest commit: 2affbf36a4435fec245c58a04a21740686a7d3f8.
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
- Token-level local scan of the original 0.1.8 source found 144 actual top-level locals. The 0.1.9 transport change renames one top-level local function without changing that count, and the 0.1.10 tracker change adds only one inner-function local; current top-level pressure therefore remains 144, leaving 56 below Lua 5.0.3's 200-local top-level chunk limit. The affected tracker function remains far below 200 locals.
- Focused Phase 6 mocked integration harness passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. Coverage: session-first full snapshots; first-known/restarted boot invalidation and recovery; quest readiness/revision handling; numeric-ID-authoritative matching; cross-session instruction-full rejection; missed-instruction cursor resync; instruction validation before cursor mutation; instruction-delta-before-session-delta ordering.

### Checks Not Actually Runnable
- Exact full-file Lua 5.3.6 parser smoke: not run against the committed pfQuest_Group.lua blob because GitHub connector-backed repository bytes are not materialized into the executable container.
- Canonical Lua 5.0.3 compiler check: not run / unavailable against the exact Phase 6 blob. Seraphic8x2244/VanillaTemplate main at 6980e95476a72c47a461f7c78ce9e4f649c829f contains the canonical tools/lua50 checker and vendored Lua 5.0.3 source, and the executable environment has a working C compiler, but the private connector-backed checker/source and addon blob are not mounted into that executable environment.
- No in-game testing has been performed.

### Current Issues / Validation Debt
- The 0.1.8 runtime transport defect is fixed in 0.1.9+: there is now exactly one SendAddonMessage call and it uses the three-argument PARTY form. Focused in-game retest is still required.
- The Group Progress no-quest status defect/requirement is fixed in 0.1.10+ by filtering peers through the matched remote quest before rendering status. Focused in-game retest is still required.
- The binary objective text collision is fixed in 0.1.11-dev by removing only the terminal numeric fraction in the binary overlay branch; the underlying captured pfQuest text is not destroyed. Focused in-game retest is still required.
- Static triage excludes the Lua 5.0.3 200-local cap as the reported error source; current top-level pressure remains 144.
- No obvious later-Lua syntax/API blacklist hit is present in the current source.
- Canonical Lua 5.0.3 compiler check remains not run against 0.1.10-dev: the connected GitHub source is not mounted in the executable environment, and direct network cloning from the executable environment is unavailable.
- No release/promotion decision should be made until the 0.1.10-dev runtime retest confirms these fixes and the remaining broad-test points are reconciled.

## Testing

### Last Runtime Test
- Version/commit: 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825.
- Passed/appears good: basic Guide/Tourist behavior appeared to work during the run.
- Failed: addon communications hit `Interface\\AddOns\\aux-addon\\libs\\ChatThrottleLib.lua:261: unknown addon chat type`, localized to pfQuest_Group using addon-message WHISPER, which is unsupported in WoW 1.12.
- Failed/behavior correction: Group Progress must not render a PFQG peer's class icon/status when that peer does not have the tracked quest.
- Not yet reconciled: exhaustive instruction/recovery paths, disparities, reload/restart recovery, party churn, window persistence, Off cleanup, and the remainder of Group Progress.

### Next Runtime Test
Run 0.1.11-dev / 2affbf36a4435fec245c58a04a21740686a7d3f8. Verify: (1) party discovery/sync and reload/recovery produce no ChatThrottleLib `unknown addon chat type` error; (2) Guide/Tourist basic behavior still works; (3) binary pfQuest objectives no longer show the native `0/1` or `1/1` suffix while peer tick/cross status is active; (4) multi-count objectives such as `3/10` remain unchanged; (5) a compatible PFQG peer without the tracked quest shows no class icon/status for that quest.

## Planned / Next Work
1. User performs the focused 0.1.11-dev retest for communications, basic Guide/Tourist behavior, binary objective text replacement, and Group Progress peer filtering.
2. Fix only defects demonstrated by that retest, with normal version discipline.
3. Reconcile the remaining broad-test results point by point.
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
Test 0.1.11-dev / 2affbf36a4435fec245c58a04a21740686a7d3f8 in game, starting with communications/reload, Guide/Tourist, binary objective `0/1` / `1/1` replacement, and pfQuest tracker peer-status filtering. Do not begin unrelated feature work or promote to main before this retest is reconciled.
