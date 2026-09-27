# Development Progress

## Current
- Branch: dev.
- Version: 0.1.16-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: c74a0da565d412ad118466faaff1640e21d8096c — reverse Tourist instruction completion acknowledgement hardening on top of the Guide-side completion feedback feature.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None. main remains exactly bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: validate the new reverse Tourist-completion feedback on top of the partially user-verified 0.1.14 baseline, then continue the remaining broad matrix and decide release/promotion readiness.
- Scope boundary: the user explicitly requested one post-Phase-6 feature addition: when every Tourist eligible for a Guide instruction has completed it, the Guide should receive the same strike/fade/removal feedback. That feature is implemented in 0.1.16-dev through the existing Phase 4b instructions owner and Phase 5 window; remote-member tracker visual fine-tuning remains deferred.

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
- Protocol prefix: PFQGROUP; protocol version: 2; SavedVariables schema: 1. Protocol v2 is deliberate because Tourist -> Guide instruction-completion acknowledgements extend the instructions-component wire semantics; v1 peers are rejected rather than silently behaving as non-acknowledging Tourists.
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
- Tourist consumed sequence state remains persisted in the Phase 4b instruction store. Under protocol v2 a Tourist sends an idempotent completion delta when consuming a step and includes the consumed set in its instructions full snapshot, so missed acknowledgements can recover through the existing full-state path without a new scheduler or component.
- Guide completion is derived only for Tourists paired to the same Guide session whose fixed joinBaseline is below that instruction sequence; Tourists who joined after the step do not block it. When all currently eligible paired Tourists have acknowledged the step, the Guide row uses the existing strike/fade/removal presentation. Acknowledgements seen by unrelated PARTY peers are ignored.

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
- 07f509361926fa05dcdab748a40c08b5e77d5933 — add protocol-v2 Tourist completion acknowledgements and Guide-side all-Tourists strike/fade/removal; version 0.1.15-dev.
- c74a0da565d412ad118466faaff1640e21d8096c — make unrelated PARTY recipients ignore Tourist completion acknowledgements instead of requesting unnecessary full sync; version 0.1.16-dev.

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
- Partial broad matrix on 0.1.14-dev confirms startup, solo reload, 2-player discovery, one-sided and sequential grouped reloads, relog recovery, local binary conversion, normal count preservation, tracker collapse/expand, peer binary status/no-quest filtering, Group Progress in Off mode, basic Off/Guide/Tourist lifecycle, Guide instruction ordering/turn-in creation, same-quest accept+turn-in sequencing, completion presentation, and window move/reload persistence in the limited sample tested.
- No ChatThrottleLib `unknown addon chat type` recurrence was noticed during this sample. This is positive runtime evidence but not an exhaustive transport stress result.
- Guide ACCEPT/TURNIN instruction creation passed, but NPC-name presentation remains unverified. The current instruction row renderer shows only quest title; `npcName` is still carried in instruction state when resolvable.

### Implemented / Awaiting Runtime Test
- 0.1.16-dev reverse-completion delta: protocol v2 extends only the existing instructions component. Tourist completion deltas/full snapshots carry consumed instruction sequences; Guide completion waits for all currently eligible same-session Tourists, then uses the existing strike/fade/removal UI.
- 0.1.16-dev recovery/transport hardening: consumed state is recoverable through full snapshots; acknowledgements are idempotent; unrelated PARTY recipients ignore them; no new component, session owner, scheduler, or Guide/Tourist window was introduced.
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
Current addon-affecting retest commit: c74a0da565d412ad118466faaff1640e21d8096c.
- pfQuest_Group.lua blob: 5e03d3a1d3b7c7a15d7ef2e643f4ec82f385e747.
- locales/enUS.lua blob: 0122994a3bd10ef5d0202dc6794d0c7bd32c7655 (unchanged from the tested 0.1.14 baseline).
- pfQuest_Group.toc blob: 70433a2bcdae8d69a991fbc7b5529012425a8dba.
- dev_rulebook.md blob: 1e054bc02930ece70445abd9ef910750193a9461 (unchanged).
- Version discipline: passed for the new delta; 0.1.14-dev -> 0.1.15-dev for the feature, then -> 0.1.16-dev for the PARTY-recipient robustness correction.
- Protocol check: PFQGROUP is deliberately protocol version 2; prefix remains PFQGROUP and SavedVariables schema remains 1.
- Ownership check: exactly one session component registration, one quests component registration, one instructions component registration, one Addon.SetMode definition, and one Guide/Tourist window initializer. Reverse completion remains inside the existing instructions component/window.
- Transport check: exactly one SendAddonMessage call remains and it uses the Vanilla three-argument PARTY form.
- UI structural call-site count remains 5 CreateFrame, 4 CreateFontString, and 5 CreateTexture; the reverse feedback reuses the existing strike/fade row presentation.
- Static later-Lua/API scan passed for the exact 0.1.16 source: no string.match, string.gmatch, table.unpack, select(, RegisterAddonMessagePrefix, C_QuestLog, C_ChatInfo, C_Timer, goto, or label syntax.
- Token-level local scan of the exact 0.1.16 source found 151 top-level locals, leaving 49 below Lua 5.0.3's 200-local top-level chunk limit. The largest scanned inner function remains far below 200 locals.
- Focused Phase 6 mocked integration harness passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. Coverage: session-first full snapshots; first-known/restarted boot invalidation and recovery; quest readiness/revision handling; numeric-ID-authoritative matching; cross-session instruction-full rejection; missed-instruction cursor resync; instruction validation before cursor mutation; instruction-delta-before-session-delta ordering.

### Checks Not Actually Runnable
- Exact full-file Lua 5.3.6 parser smoke: not run against the committed pfQuest_Group.lua blob because GitHub connector-backed repository bytes are not materialized into the executable container.
- Canonical Lua 5.0.3 compiler check: not run / unavailable against the exact Phase 6 blob. Seraphic8x2244/VanillaTemplate main at 6980e95476a72c47a461f7c78ce9e4f649c829f contains the canonical tools/lua50 checker and vendored Lua 5.0.3 source, and the executable environment has a working C compiler, but the private connector-backed checker/source and addon blob are not mounted into that executable environment.
- Broad in-game testing is in progress on the exact current addon build; automated/compiler limitations above remain separate from the user runtime results.

### Current Issues / Validation Debt
- The 0.1.8 runtime transport defect is fixed in 0.1.9+: there is now exactly one SendAddonMessage call and it uses the three-argument PARTY form. Focused in-game retest is still required.
- The Group Progress no-quest status defect/requirement is fixed in 0.1.10+ by filtering peers through the matched remote quest before rendering status. Focused in-game retest is still required.
- The binary objective text collision is fixed in 0.1.11+ by removing only the terminal numeric fraction in the binary overlay branch; the underlying captured pfQuest text is not destroyed. Focused in-game retest is still required.
- The invisible binary mark defect is fixed in 0.1.12+ by replacing literal Unicode marks with Vanilla-era Blizzard textures; the screenshot confirms the remote red incomplete/cross texture is visible.
- The 0.1.12 local binary replacement gating defect is fixed and user-verified in 0.1.13-dev: local binary status no longer depends on any peer having the quest.
- The 0.1.13 binary-row justification defect is fixed and locally user-verified in 0.1.14-dev by placing the local status inline after the objective label. Remote-member presentation polish is deferred.
- Static triage excludes the Lua 5.0.3 200-local cap as the reported error source; current top-level pressure is 151.
- No obvious later-Lua syntax/API blacklist hit is present in the current source.
- Canonical Lua 5.0.3 compiler check remains not run against 0.1.16-dev: the connected GitHub source is not mounted in the executable environment, and direct network cloning from the executable environment is unavailable.
- The 0.1.16 reverse-completion delta is not yet user-tested. The 0.1.14 partial broad-matrix results remain the last runtime baseline and must not be rewritten as tests of protocol v2.
- New performance report during testing: with the client otherwise around 120 FPS, moving the mouse anywhere on screen can drop below 100 FPS with severe frametime disturbance; stationary mouse returns to the cap. Direct source inspection found no PFQG global mouse-movement hook, only the Guide/Tourist window as mouse-enabled plus two lightweight OnUpdate handlers. This symptom is therefore not yet localized to PFQG. Before changing addon code, compare mouse polling/report rate at 125/250 Hz and perform an A/B run with PFQG disabled but pfQuest still enabled.
- Separate from the mouse-specific symptom, the current Vanilla PARTY transport still has a known fan-out inefficiency: logically targeted recovery packets are PARTY broadcasts without an encoded recipient, so non-target PFQG peers can process them. This is a concrete optimization candidate, but it has not yet been changed because it does not explain a stutter that occurs only while the mouse moves.

## Testing

### Last Runtime Test
- Version/commit: 0.1.14-dev / fb3f8f3bcf46b0372303db590d4f68694aba97af.
- Sample size: limited 2-player/solo pass; many matrix cases remain untested.
- PASS: 1, 2, 3, 5, 6, 7, 8, 11, 12, 13, 15, 17, 20, 22, 30, 32, 33, 34, 39, 43, 44, 45, 52, 75, 76.
- PASS with qualification: 4 — no ChatThrottleLib recurrence noticed, but not deliberately stress-triggered; 31 — remote Group Progress presentation is functional but visual polish is deferred; 43/44 — instruction behavior passed, but NPC-name presentation was not observed and remains a focused presentation check rather than a confirmed state-sync defect.
- UNTESTED/SKIP: 9, 10, 14, 16, 18, 19, 21, 23-29, 35-38, 40-42, 46-51, 53-74, 77-91.
- 76 was reported as "res" and is recorded as PASS under the likely intended "yes"; correct this if that was not intended.
- No new confirmed functional defect was demonstrated by this partial matrix.
- Deferred polish: exact remote-member binary presentation/spacing will be fine-tuned later and is not a current functional blocker.

### Next Runtime Test
First run a focused protocol-v2/reverse-completion test on 0.1.16-dev / c74a0da565d412ad118466faaff1640e21d8096c with every participating PFQG client updated to 0.1.16: (1) 2-player discovery and basic Guide/Tourist pairing still work with no Lua/ChatThrottleLib errors; (2) Guide creates a step, one Tourist consumes it, Tourist still gets its local strike/fade and Guide now gets strike/fade/removal; (3) with two Tourists, one completion leaves the Guide row visible and the second completion triggers Guide removal; (4) a Tourist joining after an existing step does not block that old step; (5) reload/rejoin/full-sync recovery preserves completion acknowledgement where practical; (6) unrelated Tourist PARTY recipients do not cause sync churn/errors. After that passes, continue the remaining 0.1.14 broad-matrix gaps on the 0.1.16 build. Keep remote-member tracker visual fine-tuning deferred.

## Planned / Next Work
1. User runs the focused 0.1.16 protocol-v2/reverse-completion test on all-updated clients.
2. Fix only defects demonstrated by that runtime test, with normal version discipline.
3. Continue the remaining broad-matrix gaps on the resulting known-good build; keep remote-member tracker presentation polish deferred.
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
Update every PFQG test client to 0.1.16-dev / c74a0da565d412ad118466faaff1640e21d8096c and test the reverse completion path first: one Tourist completion, then the two-Tourist all-complete gate, plus a reload/recovery pass. Protocol v1 builds are intentionally incompatible with this test. Report PASS / FAIL / SKIP with notes before continuing the remaining broad matrix or considering promotion.
