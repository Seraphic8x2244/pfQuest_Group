# Development Progress

## Current
- Branch: dev.
- Version: 0.1.14-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: fb3f8f3bcf46b0372303db590d4f68694aba97af — align local and remote binary Group Progress status inline with the objective label.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None. main remains exactly bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: reconcile the first broad in-game validation of the integrated Phase 1–6 test build, diagnose and fix only demonstrated defects, then decide release/promotion readiness.
- Scope boundary: Phase 6 code hardening is complete. Broad runtime testing found the Vanilla addon-WHISPER transport defect plus Group Progress presentation defects around peer filtering and binary status rendering. 0.1.13-dev runtime confirms local binary replacement and remote class/status rendering now work; the remaining demonstrated defect was awkward right-edge justification. 0.1.14-dev changes only binary status positioning to inline flow and awaits focused retest; no unrelated feature work or architecture changes are authorized.

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
- Binary objective conversion is always active for the local player: pfQuest's terminal numeric `0/1` / `1/1`-style token is removed and replaced by a local complete/incomplete texture even if no compatible peer has that quest. Binary rows flow inline as objective label -> local status -> remote class/status pairs. Compatible peers who have the tracked quest append class icon plus complete/incomplete status; peers without the quest append nothing. The overlay is independent of Guide/Tourist mode, and the original pfQuest text/color is retained for restoration. Status marks use Vanilla-safe Blizzard textures rather than Unicode font glyphs.
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
- 6419463902225f4672eb1a398bd34a79ae8406a3 — replace Unicode `✓` / `✗` font glyphs with Blizzard `UI-CheckBox-Check` / `UI-GroupLoot-Pass-Up` textures; version 0.1.12-dev.
- a840dfa7b45918e202ed10038ca5a9cc77d56ab9 — always render local binary complete/incomplete status, independent of whether any peer has the quest; version 0.1.13-dev.
- fb3f8f3bcf46b0372303db590d4f68694aba97af — move binary local/remote status from right-edge justification to inline placement after the objective label; version 0.1.14-dev.

## Validation State

### Completed / User-Verified
- Repository, product direction, and staged development plan were confirmed by the user.
- Broad in-game testing began on 0.1.8-dev / bfe9b578802bf87ed418cb3c329684acfe787825.
- Basic Guide/Tourist behavior appears to work in that run; this is a partial runtime result, not exhaustive validation of every session/instruction/recovery path.
- The reported Lua error is localized to aux-addon's ChatThrottleLib rejecting pfQuest_Group's SendAddonMessage(..., "WHISPER", target) path as an unknown addon chat type. WoW 1.12 addon messages support PARTY/RAID/GUILD/BATTLEGROUND; addon WHISPER was added later.
- Group Progress also showed/was specified to show PFQG peer status only when that peer has the tracked quest; peers without the quest must be omitted.
- Follow-up runtime feedback on 0.1.10-dev: the binary tick/cross overlay was present but pfQuest's native `0/1` or `1/1` count text remained visible on the same objective row.
- Follow-up runtime feedback after the text fix: the expected binary tick/cross mark itself was not visible. Inspection showed the mark was a literal Unicode `✓` / `✗` in `GameFontNormal`, which is not reliable on the Vanilla client font set.
- 0.1.12-dev screenshot result: remote PFQG class icon plus red incomplete/cross texture is visibly rendering on quests the peer has. Local `1/1` and `0/1` text remained unchanged on other binary objectives, demonstrating that local conversion was wrongly gated on `questPeers` being non-empty.
- 0.1.13-dev screenshot result: local binary replacement works and remote class/status renders correctly; the remaining visible defect was right-edge justification.
- Follow-up after the 0.1.14-dev inline-layout handoff: the user reports their own local binary symbols are now in the correct place. Remote-member presentation still needs subjective fine-tuning, but that polish is explicitly deferred until after broad functional validation.

### Implemented / Awaiting Runtime Test
- 0.1.9+ delta: all addon transport uses the Vanilla-supported PARTY addon channel; no four-argument addon-WHISPER send remains.
- 0.1.10+ delta: Group Progress filters compatible peers per tracked quest before creating binary/count status regions, so peers without that quest are omitted while the overlay remains mode-independent.
- 0.1.11+ delta: in the binary branch only, Group Progress strips a terminal numeric fraction from the saved pfQuest objective text before rendering peer status. Multi-count objectives remain on the existing count-row path and the untouched base text is restored whenever the overlay is not applicable.
- 0.1.12+ delta: binary status marks are textures, not font glyphs. Complete uses `Interface\\Buttons\\UI-CheckBox-Check` tinted green; incomplete uses `Interface\\Buttons\\UI-GroupLoot-Pass-Up` tinted red.
- 0.1.13+ delta: local binary rendering no longer returns early when there are zero compatible peers or zero peers with the quest. A local status texture is always reserved/rendered for binary objectives; remote class-icon/status loops remain filtered through matched remote quest ownership.
- 0.1.14-dev delta: binary status anchors are inline. The local status is positioned immediately after the rendered objective text width; remote class/status pairs follow the local status in party order. Count-objective layout is unchanged.
- Integrated Phase 1 foundation/protocol.
- Phase 2 local/remote quest-state engine.
- Phase 3 Group Progress tracker integration.
- Phase 4a Guide/Tourist session lifecycle and pairing.
- Phase 4b instruction creation/synchronization/baseline/consumption/recovery.
- Phase 5 Guide/Tourist window, completion presentation, current quest disparities, Hide/Unhide, and Show Hidden.
- Phase 6 boot/full-state/quest-readiness/numeric-identity/instruction-recovery hardening.

### Static / Automated Checks — Exact Phase 6 Addon State
Exact original Phase 6 test commit: bfe9b578802bf87ed418cb3c329684acfe787825.
Current addon-affecting retest commit: fb3f8f3bcf46b0372303db590d4f68694aba97af.
- pfQuest_Group.lua blob: 2aeb9ed756936f27d3c69f341fa8acf437782182.
- locales/enUS.lua blob: 0122994a3bd10ef5d0202dc6794d0c7bd32c7655 (unchanged from Phase 5b).
- pfQuest_Group.toc blob: 0a19ef766fb6453a2967bb8ed91a7ec574f563e7.
- dev_rulebook.md blob: 1e054bc02930ece70445abd9ef910750193a9461 (unchanged).
- Version discipline: passed; 0.1.7-dev -> 0.1.8-dev.
- Scope check: passed. Relative to the Phase 5b handoff, the addon-affecting commit changes only pfQuest_Group.lua and pfQuest_Group.toc.
- main remains exactly 4c5c63f074923266566c36c51ce2718d0060166f.
- Protocol check: PFQGROUP protocol version remains 1.
- Ownership check: exactly one session component registration, one quests component registration, one instructions component registration, one Addon.SetMode definition, and one Guide/Tourist window initializer.
- Current UI structural count after the local binary marker addition: 5 CreateFrame, 4 CreateFontString, and 5 CreateTexture call sites. The added texture is a reusable per-objective local binary status marker; no new window architecture is introduced.
- Static later-Lua/API scan passed for the exact committed source: no string.match, string.gmatch, table.unpack, select(, RegisterAddonMessagePrefix, C_QuestLog, C_ChatInfo, or C_Timer tokens.
- Token-level local scan of the original 0.1.8 source found 144 actual top-level locals. Changes through 0.1.12 did not alter that top-level count. 0.1.13 adds one top-level helper (`EnsureLocalBinaryStatus`), bringing current top-level pressure to 145, leaving 55 below Lua 5.0.3's 200-local top-level chunk limit. The affected tracker function remains far below 200 locals.
- Focused Phase 6 mocked integration harness passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. Coverage: session-first full snapshots; first-known/restarted boot invalidation and recovery; quest readiness/revision handling; numeric-ID-authoritative matching; cross-session instruction-full rejection; missed-instruction cursor resync; instruction validation before cursor mutation; instruction-delta-before-session-delta ordering.

### Checks Not Actually Runnable
- Exact full-file Lua 5.3.6 parser smoke: not run against the committed pfQuest_Group.lua blob because GitHub connector-backed repository bytes are not materialized into the executable container.
- Canonical Lua 5.0.3 compiler check: not run / unavailable against the exact Phase 6 blob. Seraphic8x2244/VanillaTemplate main at 6980e95476a72c47a461f7c78ce9e4f649c829f contains the canonical tools/lua50 checker and vendored Lua 5.0.3 source, and the executable environment has a working C compiler, but the private connector-backed checker/source and addon blob are not mounted into that executable environment.
- No in-game testing has been performed.

### Current Issues / Validation Debt
- The 0.1.8 runtime transport defect is fixed in 0.1.9+: there is now exactly one SendAddonMessage call and it uses the three-argument PARTY form. Focused in-game retest is still required.
- The Group Progress no-quest status defect/requirement is fixed in 0.1.10+ by filtering peers through the matched remote quest before rendering status. Focused in-game retest is still required.
- The binary objective text collision is fixed in 0.1.11+ by removing only the terminal numeric fraction in the binary overlay branch; the underlying captured pfQuest text is not destroyed. Focused in-game retest is still required.
- The invisible binary mark defect is fixed in 0.1.12+ by replacing literal Unicode marks with Vanilla-era Blizzard textures; the screenshot confirms the remote red incomplete/cross texture is visible.
- The 0.1.12 local binary replacement gating defect is fixed and user-verified in 0.1.13-dev: local binary status no longer depends on any peer having the quest.
- The 0.1.13 binary-row justification defect is fixed and locally user-verified in 0.1.14-dev by placing the local status inline after the objective label. Remote-member presentation polish is deferred.
- Static triage excludes the Lua 5.0.3 200-local cap as the reported error source; current top-level pressure is 145.
- No obvious later-Lua syntax/API blacklist hit is present in the current source.
- Canonical Lua 5.0.3 compiler check remains not run against 0.1.14-dev: the connected GitHub source is not mounted in the executable environment, and direct network cloning from the executable environment is unavailable.
- No release/promotion decision should be made until the 0.1.14-dev broad runtime matrix is reconciled.

## Testing

### Last Runtime Test
- Version/commit: 0.1.14-dev / fb3f8f3bcf46b0372303db590d4f68694aba97af (follow-up report against the current addon build context).
- Passed/appears good: local binary `0/1` / `1/1` replacement works and the user's own complete/incomplete symbols are now positioned correctly; earlier testing also showed basic Guide/Tourist behavior working and remote class/status rendering functioning.
- Deferred polish: exact remote-member binary presentation/spacing will be fine-tuned later and is not a current functional blocker.
- Not yet reconciled: full communications/reload recovery, exhaustive quest-state synchronization, count objectives, multi-peer behavior, instruction baseline/consumption/recovery, disparities, party churn, persistence, Off cleanup, and the remaining broad-test matrix.

### Next Runtime Test
Run the full broad runtime matrix on 0.1.14-dev / fb3f8f3bcf46b0372303db590d4f68694aba97af. Cover startup/error monitoring, party discovery and PARTY transport, local/remote quest-state synchronization, binary and count Group Progress behavior, Guide/Tourist pairing and instruction lifecycle, disparity controls, reload/restart and leave/rejoin recovery, UI persistence, Off cleanup, and multi-peer behavior where available. Record PASS / FAIL / SKIP plus concise notes for every numbered case.

## Planned / Next Work
1. User performs the full numbered 0.1.14-dev broad runtime matrix.
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
Run the supplied numbered broad runtime matrix on 0.1.14-dev / fb3f8f3bcf46b0372303db590d4f68694aba97af and report PASS / FAIL / SKIP with notes per case. Keep remote-member presentation fine-tuning deferred. Do not begin unrelated feature work or promote to main before the matrix is reconciled.
