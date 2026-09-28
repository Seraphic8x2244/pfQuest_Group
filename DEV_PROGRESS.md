# Development Progress

## Current
- Branch: dev.
- Version: 0.1.23-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: 3674229c012e6a6eab7c93d87542661d08b9b545 — harden the count-objective player-row redesign introduced in 0.1.22-dev, including self-first rows and per-player pfQuest-derived count colours.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None. main remains exactly bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: implement the newly accepted Guide lifecycle/completion semantics and PFQG group-held objective tracking on top of 0.1.23-dev, then runtime-validate those changes together with the still-pending Tourist Done/NPC/count-row work before resuming the broad matrix.
- Scope boundary: the user explicitly requested post-Phase-6 refinements through the existing owners: Guide reverse-completion feedback (0.1.16+), Tourist manual Done for stale already-completed instructions (0.1.18+), instruction NPC presentation (0.1.19-0.1.21), count-objective Group Progress redesign (0.1.22-0.1.23), dormant persisted Guide sessions, durable Guide-side instruction completion, and PFQG-owned group-held objective/map tracking after a local player finishes. Other remote-member/binary tracker polish remains deferred unless explicitly requested.

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
- Count objectives render the objective label as a heading with no inline personal fraction, then add a self row first followed by one row per compatible peer who has the tracked quest in party order. Each row keeps the class icon, renders `PlayerName:` in that player's class colour (including self), and renders `current/required` using the same pfQuest objective colour rule for that player's own progress (`pfMap.tooltip:GetColor(current, required)` brightened by 0.2 and clamped). A missing matching objective within an otherwise matched remote quest displays grey `--`.
- Reusable tracker regions are hidden/restored as peers change and tracker dimensions are recalculated.

### Accepted PFQG Group-Hold Tracking — Not Yet Implemented
- WoW/pfQuest must continue to record the local player's real quest progress normally. Do not falsify a local `15/15`, quest completion flag, quest log state, or turn-in state merely to keep shared guidance visible.
- When the local player completes an objective/quest but at least one relevant Guide/Tourist participant still needs part of it, PFQG should maintain a supplemental `group hold` presentation until the relevant group is actually complete.
- Group hold should preserve/recreate only useful objective guidance: PFQG's shared tracker objective block, world-map objective nodes, minimap objective nodes, and PFQG-owned tooltips for those held objective nodes. Do not resurrect Blizzard quest-log progress, quest-start/giver markers, or personal turn-in/completion state solely because another player is unfinished.
- For multi-objective quests, retain only objectives that at least one relevant participant still needs rather than blindly restoring every objective node for the quest.
- PFQG group-held tooltips should use the same visual language as the redesigned count tracker: objective heading, then self first and relevant Tourist rows in party/session order, class-coloured names, and per-player progress colours. They should not show a misleading personal `?`/complete state merely because the local player is finished.
- Normal pfQuest nodes/tooltips may continue unchanged while they exist. Once pfQuest removes local objective nodes because the local player is complete, PFQG supplemental nodes become the group-aware representation.
- A Tourist temporarily disconnecting must not be treated as group completion. Group-hold release needs durable completion semantics/last-known state sufficient to distinguish `offline but unfinished` from `finished`. While no relevant Tourist is present, the Guide/group-hold presentation may go dormant and resume on rejoin.
- pfQuest source inspection confirms why a supplemental layer is preferable: pfQuest's quest queue deletes/rebuilds `PFQUEST` nodes from the local quest log, `SearchQuestID` skips objective-node generation when the local quest is complete, and map tooltips read local `GetQuestLogLeaderBoard` state. Its database search API accepts an addon metadata namespace, so investigate PFQG-owned supplemental nodes rather than fighting pfQuest's personal-state machinery.

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
- A Tourist may also click Done on a pending instruction when the underlying quest action happened before that instruction could be matched. Done is a semantic completion acknowledgement, not a presentation-only hide: it writes the same persisted consumed sequence state, triggers the existing local strike/fade/removal, and sends the same protocol-v2 completion acknowledgement to the Guide. If PARTY transport is temporarily unavailable, persisted consumed state remains recoverable through the existing instructions full snapshot on later synchronization.
- Tourist consumed sequence state remains persisted in the Phase 4b instruction store. Under protocol v2 a Tourist sends an idempotent completion delta when consuming a step and includes the consumed set in its instructions full snapshot, so missed acknowledgements can recover through the existing full-state path without a new scheduler or component.
- Guide completion is derived only for Tourists paired to the same Guide session whose fixed joinBaseline is below that instruction sequence; Tourists who joined after the step do not block it. When all currently eligible paired Tourists have acknowledged the step, the Guide row uses the existing strike/fade/removal presentation. Acknowledgements seen by unrelated PARTY peers are ignored.

### Accepted Guide Lifecycle / Durable Completion Semantics — Not Yet Implemented
- Persisted Guide mode/session should remain stored across logout/reload so the group can resume, but the Guide presentation should be dormant whenever no Tourist bound to that same Guide session is currently present. In the dormant state the Guide window should not appear and new Guide instructions should not be generated. When a matching Tourist rejoins, the existing persisted session should wake, synchronize, and continue rather than creating a fresh Guide session.
- The current behavior observed by the user is the defect motivating this change: logging in solo restored active Guide mode with a very large old instruction list; when Gaia later joined the party, synchronization caused many rows to cross off. The resume/synchronization behavior is desirable, but the solo-active presentation is not.
- Tourist completion acknowledgements remain durable per Tourist. In addition, once every Tourist who was eligible for a particular instruction has acknowledged it, the Guide must persist that instruction as completed for that Guide session. A completed Guide instruction must never reappear after reload, logout, party breakup, or regrouping within the same Guide session.
- Eligibility for permanent Guide completion must be based on the Tourists who were eligible for that instruction, not merely Tourists currently online/present at the moment completion is evaluated. A temporarily offline eligible Tourist must not disappear from the requirement and cause premature completion. Late joiners whose fixed joinBaseline is at/after the instruction remain ineligible and must not block it.
- Keep Phase 4a as session owner and Phase 4b as instruction/completion owner. The implementation may require persisted Guide-side eligibility/completion metadata and possibly a protocol/schema revision; decide that deliberately after inspecting current wire/store shapes rather than deriving permanent completion from transient current-party membership.

### Guide / Tourist Window and Disparities
- The existing compact movable Phase 5 window is the only Guide/Tourist presentation window and is shown only in Guide/Tourist mode.
- Guide/Tourist instruction rows visually sandwich the action marker between NPC and quest text. ACCEPT renders `NPC Name` + yellow `!` + `Quest Name`; TURNIN uses a yellow `?`. Resolved NPC names longer than 18 characters are shortened by reducing every word except the final surname/last token to initials, e.g. `Commander Ashlam Valorfist` -> `C.A. Valorfist`. Short NPC names remain unchanged. If no NPC is available, the row falls back to yellow `!/?` + quest text. The separate marker column is collapsed for instruction rows to avoid an empty left gutter, but remains available for disparity rows. Tourist completion uses the existing completion event for ephemeral strike/fade/removal only.
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
- 53e901594eacb8d7bb1be3eb15b2b3684b2d30fe — add Tourist-side Done for already-completed pending instructions using the existing consumed-state/acknowledgement pipeline; version 0.1.18-dev.
- 0aa21139e353adbd4fc22bfbcf2adcbcd421a166 — render stored NPC names in the existing Guide/Tourist instruction text formatter; version 0.1.19-dev.
- e5771dd1ab4288dc793e9ec6ba5b361e656c206b — reformat Guide/Tourist instruction text to NPC-first with the action marker in parentheses and suppress the duplicate standalone marker; version 0.1.20-dev.
- a5f78570026be729c5878ec9bb615ed357cde302 — refine instruction presentation to `NPC` + yellow `!/?` + `Quest`, abbreviating resolved NPC names longer than 18 characters to initials-plus-final-token and collapsing the unused marker gutter for instruction rows; version 0.1.21-dev.
- 207f801b0f3b6bb2ceee2126f6890f1a66633065 — redesign numeric/count tracker objectives as objective heading + self/party player rows with class-coloured names and per-player pfQuest-derived progress colours; version 0.1.22-dev.
- 3674229c012e6a6eab7c93d87542661d08b9b545 — harden count-row formatting by avoiding `_` global pollution and guarding invalid zero requirements; version 0.1.23-dev.

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
- 0.1.23-dev count-objective redesign: numeric objectives now show only `- Objective Name` on the objective line. Under it, self appears first and compatible peers follow in party order as `PlayerName: current/required`; names are class-coloured for every player including self, and each numeric progress value uses pfQuest's own `pfMap.tooltip:GetColor(current, required)` rule (with the same +0.2 brightness) based on that player's progress. Existing class icons are retained. Remote matched quests with no equivalent objective still show grey `--`. Binary objective behavior is unchanged.
- 0.1.18-dev stale-instruction fix: pending Tourist instruction rows now expose Done. Clicking it routes through the same completion helper used by automatic ACCEPT/TURNIN matching, persists the consumed sequence, performs the existing Tourist strike/fade/removal, and sends the existing protocol-v2 completion acknowledgement so the Guide can complete the corresponding row. No new component, protocol version, window, scheduler, or state owner was added.
- 0.1.21-dev NPC presentation refinement: resolved instruction rows now render NPC first, then the same yellow action marker visually inline, then quest text. NPC names longer than 18 characters are abbreviated to initials for all tokens except the final token (for example `Commander Ashlam Valorfist` -> `C.A. Valorfist`). The standalone marker column is collapsed for instruction rows and reset for disparity rows. No protocol or state-shape change was required.
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
Current addon-affecting retest commit: 4df6d0b9c1c3682e5077eaaab6b191f445aa3c16.
- pfQuest_Group.lua blob: 57964b863207f3dd70562cef5285197d0bf62a4b.
- locales/enUS.lua blob: 0122994a3bd10ef5d0202dc6794d0c7bd32c7655 (unchanged from the tested 0.1.14 baseline).
- pfQuest_Group.toc blob: 5fb3ad3c36f49b792bf108e632d2939704108e8a.
- dev_rulebook.md blob: 1e054bc02930ece70445abd9ef910750193a9461 (unchanged).
- Version discipline: passed for the new delta; 0.1.14-dev -> 0.1.15-dev for the feature, then -> 0.1.16-dev for the PARTY-recipient robustness correction.
- Protocol check: PFQGROUP is deliberately protocol version 2; prefix remains PFQGROUP and SavedVariables schema remains 1.
- Ownership check: exactly one session component registration, one quests component registration, one instructions component registration, one Addon.SetMode definition, and one Guide/Tourist window initializer. Reverse completion remains inside the existing instructions component/window.
- Transport check: exactly one SendAddonMessage call remains and it uses the Vanilla three-argument PARTY form.
- UI structural call-site count remains 5 CreateFrame, 4 CreateFontString, and 5 CreateTexture; the reverse feedback reuses the existing strike/fade row presentation.
- Static later-Lua/API scan passed for the exact 0.1.16 source: no string.match, string.gmatch, table.unpack, select(, RegisterAddonMessagePrefix, C_QuestLog, C_ChatInfo, C_Timer, goto, or label syntax.
- 0.1.17 adds one top-level worker-frame local, bringing the expected top-level local count to 152, leaving 48 below Lua 5.0.3's 200-local top-level chunk limit. No later-Lua/API blacklist tokens were introduced.
- Focused Phase 6 mocked integration harness passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. Coverage: session-first full snapshots; first-known/restarted boot invalidation and recovery; quest readiness/revision handling; numeric-ID-authoritative matching; cross-session instruction-full rejection; missed-instruction cursor resync; instruction validation before cursor mutation; instruction-delta-before-session-delta ordering.
- Focused protocol-v2 reverse-completion extracted-logic harness passed texluac -p and 12/12 runtime assertions under the available texluac/texlua environment against the current 0.1.17-dev logic. Covered: one eligible Tourist completes; two Tourists wait for both; late joiners do not block an older step; zero eligible Tourists do not auto-remove a row; other-Guide Tourists are ignored; completion filtering drops pre-baseline, beyond-cursor, wrong-session and unrelated-PARTY state while retaining eligible known instruction records. This is a mocked/static logic check, not an in-game test and not a canonical Lua 5.0.3 full-file compiler pass.

### Static / Automated Checks — 0.1.18-dev Manual Completion Delta
Exact addon-affecting commit: 53e901594eacb8d7bb1be3eb15b2b3684b2d30fe.
- Version discipline: passed; 0.1.17-dev -> 0.1.18-dev in the same addon-affecting commit.
- Structural check: exactly one `CompleteTouristInstruction` helper exists; both automatic Tourist ACCEPT/TURNIN matching and the Tourist Done button route through it.
- Completion semantics check: the shared helper writes `store.consumed[seq] = true`, removes the pending entry, sends `EncodeInstructionCompletionWire("A", ...)` through the existing instructions delta path, and emits the existing Tourist completion/change events.
- Ownership/protocol check: protocol remains PFQGROUP v2; exactly one instructions component registration remains; no new synchronized component or Guide/Tourist window was introduced.
- Transport check: exactly one `SendAddonMessage` call remains and continues to use the existing PARTY transport path.
- UI structure: the existing per-row action button is reused for Tourist Done; no additional frame/button creation site was introduced.
- Compatibility scan: no `string.match`, `string.gmatch`, `table.unpack`, `RegisterAddonMessagePrefix`, `C_QuestLog`, `C_ChatInfo`, `C_Timer`, or `goto` token was introduced.
- Expected top-level local count: 153 after adding one top-level helper, leaving 47 below Lua 5.0.3's 200-local top-level chunk limit.
- Canonical Lua 5.0.3 full-file compiler pass remains not run against this exact commit; do not treat these static checks as a compiler or in-game pass.

### Static / Automated Checks — 0.1.19-dev NPC Presentation Delta
Exact addon-affecting commit: 0aa21139e353adbd4fc22bfbcf2adcbcd421a166.
- Version discipline: passed; 0.1.18-dev -> 0.1.19-dev in the same addon-affecting commit.
- Data-path check: Guide instruction creation still captures `npcName`; the shared Guide/Tourist text formatter now reads it and uses the localized `"%s - %s"` form when non-empty.
- Fallback check: instructions without a resolved NPC retain the existing quest-title or numeric quest-ID text.
- Ownership/protocol check: protocol remains PFQGROUP v2; exactly one instructions component registration remains; no synchronized state shape, owner, or Guide/Tourist window was added.
- Transport check: exactly one `SendAddonMessage` call remains.
- Compatibility scan: no `string.match`, `string.gmatch`, `table.unpack`, `RegisterAddonMessagePrefix`, `C_QuestLog`, `C_ChatInfo`, `C_Timer`, or `goto` token is present.
- Canonical Lua 5.0.3 full-file compiler pass remains not run against this exact commit; runtime NPC resolution/presentation remains user-test pending.

### Static / Automated Checks — 0.1.21-dev NPC Presentation Delta
Exact addon-affecting commit: a5f78570026be729c5878ec9bb615ed357cde302.
- Version discipline: passed; 0.1.20-dev -> 0.1.21-dev in the same addon-affecting commit.
- Format check: resolved rows use localized `NPC + yellow !/? + quest` output with no literal parentheses around the action marker.
- Abbreviation check: NPC names longer than 18 characters reduce every token except the final token to initials; `Commander Ashlam Valorfist` becomes `C.A. Valorfist`. Short NPC names remain unchanged.
- Layout check: the instruction marker column is collapsed to width 0 so NPC text starts at the row edge, and reset to width 18 before disparity rendering.
- Fallback check: unresolved NPC rows still show the yellow action marker followed by quest text.
- Ownership/protocol check: protocol remains PFQGROUP v2; exactly one instructions component registration remains; no synchronized state shape, owner, or Guide/Tourist window was added.
- Transport check: exactly one `SendAddonMessage` call remains.
- Compatibility scan: no `string.match`, `string.gmatch`, `table.unpack`, `RegisterAddonMessagePrefix`, `C_QuestLog`, `C_ChatInfo`, `C_Timer`, or `goto` token is present.
- Canonical Lua 5.0.3 full-file compiler pass remains not run against this exact commit; runtime visual validation remains pending.

### Static / Automated Checks — 0.1.23-dev Count Tracker Delta
Exact addon-affecting commit: 3674229c012e6a6eab7c93d87542661d08b9b545 (feature introduced by 207f801b0f3b6bb2ceee2126f6890f1a66633065).
- Version discipline: count redesign bumped 0.1.21-dev -> 0.1.22-dev; follow-up hardening bumped -> 0.1.23-dev.
- Upstream-colour reconciliation: pfQuest's tracker uses `pfMap.tooltip:GetColor(objNum, objNeeded)` then brightens each channel by 0.2 for numeric objectives; PFQG now applies that same rule independently to every self/remote numeric count.
- Layout check: numeric objective text is replaced by white `- Objective Name` with no local fraction left inline.
- Self-row check: self uses reserved count-row slot 0, appears before party rows, retains a class icon, renders the player's name with local class colour and the local count with local progress colour.
- Remote-row check: compatible peers remain in party order; each name is class-coloured and each count colour is calculated from that peer's own current/required values.
- Missing-objective check: an otherwise matched remote quest with no equivalent objective still displays grey `--`.
- Region reuse check: the existing `pfqGroupRows` row pool is reused; CreateFrame/CreateFontString/CreateTexture call-site counts remain 6/4/5 and no new tracker owner/frame was introduced.
- Ownership/protocol check: protocol remains PFQGROUP v2; exactly one instructions component registration and one `SendAddonMessage` call remain; binary tracker behavior is untouched by this delta.
- Compatibility scan: no `string.match`, `string.gmatch`, `table.unpack`, `RegisterAddonMessagePrefix`, `C_QuestLog`, `C_ChatInfo`, `C_Timer`, or `goto` token is present.
- Expected top-level local count: 154 after adding one top-level colour helper, leaving 46 below Lua 5.0.3's 200-local top-level chunk limit.
- Canonical Lua 5.0.3 full-file compiler pass remains not run against this exact commit; runtime tracker layout/colour validation remains pending.

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
- Static triage excludes the Lua 5.0.3 200-local cap as the reported error source; current top-level pressure is 152.
- No obvious later-Lua syntax/API blacklist hit is present in the current source.
- Canonical Lua 5.0.3 compiler check remains not run against 0.1.17-dev: the connected GitHub source is not mounted in the executable environment, and direct network cloning from the executable environment is unavailable.
- Protocol-v2 reverse-completion now has partial user runtime validation on 0.1.17-dev: after both players logged in on characters with persisted Guide/Tourist modes while initially ungrouped, forming the party re-established the Guide/Tourist relationship and the Guide UI retroactively strike/fade/removed two steps the Tourist had completed previously. This demonstrates persisted completion state recovering through regroup/full-state synchronization. Live one-Tourist completion, two-Tourist gating, late-join gating, and the focused recovery variants remain separately untested unless explicitly covered below.
- Demonstrated 0.1.17 stale-instruction defect: when the Guide later ACCEPTs/TURNINs a quest action the Tourist had already performed before the instruction existed, the Tourist has no future matching local quest event to consume that instruction, leaving a permanent Tourist row and therefore a permanent Guide row. 0.1.18-dev addresses this with explicit Tourist Done acknowledgement; runtime validation is pending.
- Demonstrated instruction-presentation defect: Tourist rows were not showing NPC names even though `npcName` is already carried in instruction state when resolvable; the shared formatter discarded that field and returned only the quest title. 0.1.19-dev renders the stored NPC name when available; runtime validation is pending.
- Initial performance A/B on 0.1.16: with PFQG enabled, moving the mouse anywhere on screen dropped from about 120 FPS to below 100 with poor frametime; with PFQG disabled but pfQuest still enabled, mouse movement still dropped FPS (about 120 -> 80) but frametime felt substantially smoother.
- 0.1.17-dev performance fix: the always-installed main quest-scan OnUpdate was replaced by a hidden worker frame that is shown only while a quest scan is actually pending and hides itself immediately when idle. Follow-up user A/B after updating and re-enabling PFQG reports that enabled frametime now feels no worse than disabled. Treat the idle quest-scan OnUpdate as a confirmed PFQG performance contributor and the 0.1.17 delta as user-verified for this symptom.
- Separate from the mouse-specific symptom, the current Vanilla PARTY transport still has a known fan-out inefficiency: logically targeted recovery packets are PARTY broadcasts without an encoded recipient, so non-target PFQG peers can process them. This is a concrete optimization candidate, but it has not yet been changed because it does not explain a stutter that occurs only while the mouse moves.
- Deferred linked-quest anomaly reported by user: the related quests `Mrs Dalson's Diary`, `Outhouse`, and `Locked Cabinet` do not track correctly in pfQuest itself and also do not track correctly through PFQG's quest interface. Treat this as a separate later investigation into upstream/special linked-quest identity/objective behavior; do not fold it into the count-tracker UI change.

## Testing

### Latest Runtime Result
- 0.1.23-dev follow-up observation before formal C/R matrix validation: the Guide logged in solo with persisted Guide mode active and a very large historical instruction list visible. When Gaia rejoined the party, synchronization resumed correctly and many already-completed rows crossed off. Treat `resume where we left off` as desirable, but the solo-visible/active Guide presentation as a demonstrated behavior to change via dormant Guide semantics; do not mark additional canonical matrix items PASS from this observation alone.
- Version/commit: 0.1.17-dev / 4df6d0b9c1c3682e5077eaaab6b191f445aa3c16.
- User A/B result: the mouse-movement frametime regression is resolved for PFQG; enabled frametime now feels no worse than disabled with pfQuest left enabled.
- Additional 0.1.17 runtime result: both players logged in while initially ungrouped with persisted Guide/Tourist modes, then formed a party; the Guide/Tourist relationship resumed and two previously completed Tourist steps were retroactively strike/fade/removed on the Guide UI after synchronization.
- This upgrades broad-matrix item 62 (both players relog/persisted session + fresh peer boot synchronization) to PASS and provides partial runtime validation of protocol-v2 completion recovery. It does not by itself prove the live one-Tourist or multi-Tourist completion cases.
- Same 0.1.17 session exposed a demonstrated stale-instruction case: Guide hand-ins for quests the Tourist had already completed could leave permanent instruction rows on both Tourist and Guide. This is the defect targeted by 0.1.18-dev.

### Last Broad-Matrix Runtime Test
- Version/commit: 0.1.14-dev / fb3f8f3bcf46b0372303db590d4f68694aba97af.
- Sample size: limited 2-player/solo pass; many matrix cases remain untested.
- No new confirmed functional defect was demonstrated by this partial matrix.
- Deferred polish: exact remote-member binary presentation/spacing will be fine-tuned later and is not a current functional blocker.


### Canonical Broad Runtime Matrix (91 points)
Status provenance: reconciled from the user's recorded broad-matrix answers against the canonical 91-point checklist. Do not upgrade an UNTESTED item to PASS from static checks or adjacent runtime evidence. Optional cases remain `UNTESTED / SKIP-eligible` unless the user explicitly reports SKIP.

Legend: `PASS` = user runtime pass; `PASS-Q` = runtime pass with qualification; `UNTESTED` = no recorded result; `UNTESTED / SKIP-eligible` = optional/hard-to-force case with no recorded result.

#### A. Startup, errors, and communications
1. **PASS — Solo login/load.** No Lua errors; pfQuest works normally.
2. **PASS — Solo `/reload`.** No Lua errors.
3. **PASS — Form a 2-player party.** Automatic discovery; no manual command required.
4. **PASS-Q — ChatThrottleLib regression.** No `unknown addon chat type` recurrence was noticed, but this was not deliberately stress-triggered.
5. **PASS — Reload player A while grouped.** No error; synchronization recovers.
6. **PASS — Reload player B while grouped.** Same recovery expectation.
7. **PASS — Both players reload one after another.** State settles without repeated errors or obvious loops.
8. **PASS — Full relog one player.** Peer state recovers.
9. **UNTESTED — Leave party and rejoin.** Old remote state should disappear while absent and current state should return after rejoin.
10. **UNTESTED / SKIP-eligible — Optional 3-player party.** No message storms/errors; all compatible peers synchronize.

#### B. Local pfQuest tracker behavior
11. **PASS — Binary objective at 0/1.** Native binary count is replaced by the local incomplete symbol.
12. **PASS — Binary objective reaches 1/1.** Native binary count is replaced by the local complete symbol.
13. **PASS — Binary quest nobody else has.** Local symbol still appears; no remote class/status appears.
14. **UNTESTED — Binary state changes live.** Incomplete -> complete should update without reload.
15. **UNTESTED — Normal count objective after redesign.** Numeric progress must remain numeric, but the objective line now shows only the objective name and the local `PlayerName: current/required` row appears beneath it. The prior PASS covered the pre-0.1.22 layout and does not validate this redesign.
16. **UNTESTED — Multiple objectives on one quest.** Binary/count objectives should coexist without row collisions.
17. **PASS — Collapse/expand a tracked quest.** PFQG regions hide/show cleanly without duplicated icons.
18. **UNTESTED — Tracker refresh/update.** No duplicated rows, drifting icons, or stale text during repeated progress.
19. **UNTESTED — Switch pfQuest tracker mode away and back.** PFQG overlays should not remain on unrelated tracker content.

#### C. Remote Group Progress
20. **PASS — Peer has same binary quest, incomplete.** Peer class icon plus incomplete status appears.
21. **UNTESTED — Peer completes that binary objective.** Remote status should update without reload.
22. **PASS — Peer does not have the quest.** No class icon/status for that peer.
23. **UNTESTED — Peer accepts the quest while already grouped.** Class/status should begin appearing after synchronization.
24. **UNTESTED — Peer abandons or turns in the quest.** Class/status should disappear.
25. **UNTESTED — Peer has same count quest.** Objective heading should contain no inline count; self row appears first, then the peer row, retaining class icons with class-coloured `PlayerName:` labels and per-player coloured numeric progress.
26. **UNTESTED — Peer count progresses.** Remote count and its pfQuest-derived progress colour should update from that peer's own current/required values without affecting the self row.
27. **UNTESTED / SKIP-eligible — Equivalent objective cannot be found.** Should display `--`, not bogus `0/N`.
28. **UNTESTED / SKIP-eligible — Two remote peers with same quest.** Both should display in party order.
29. **UNTESTED — One remote peer has quest, another does not.** Only the peer with the quest should appear.
30. **PASS — Group Progress while PFQG mode is Off.** Tracker sharing remains independent of Guide/Tourist mode.
31. **UNTESTED — Visual sanity after count-row redesign.** Verify objective headings and self/party rows remain readable with no overlap or unusable objective rows. The prior PASS-Q covered the pre-0.1.22 presentation.

#### D. Basic Guide/Tourist session lifecycle
32. **PASS — Both players Off.** No Guide/Tourist window.
33. **PASS — Player A enters Guide.** Guide window appears.
34. **PASS — Player B enters Tourist following A.** Tourist pairs to A.
35. **UNTESTED — `/pfqgroup status`.** Both sides should report sensible session status.
36. **UNTESTED — Tourist command before Guide enters Guide mode.** Tourist should wait and then pair when the target becomes Guide.
37. **UNTESTED — Guide command repeated while already Guide.** Must not unnecessarily start a fresh Guide session.
38. **UNTESTED — Tourist follows wrong/nonparty/non-Guide target.** Should wait/fail cleanly without Lua error.
39. **PASS — Guide -> Off.** Guide window disappears and Guide-specific behavior stops.
40. **UNTESTED — Tourist -> Off.** Tourist window should disappear and target/binding clear.
41. **UNTESTED — Group Progress after Guide/Tourist -> Off.** Tracker sharing should continue.

#### E. Guide instructions
42. **UNTESTED — Tourist pairs first, then Guide accepts a quest.** New ACCEPT instruction should reach Tourist.
43. **PASS-Q — Guide accepts two quests.** Two ordered instructions passed; NPC-name presentation was not observed and remains separately unverified.
44. **PASS-Q — Guide turns in a quest.** TURNIN instruction creation passed; NPC-name presentation was not observed and remains separately unverified.
45. **PASS — Guide accepts and later turns in same quest.** Distinct ordered ACCEPT then TURNIN behavior.
46. **UNTESTED — Tourist joins after Guide already performed an action.** Pre-join instruction should not become pending.
47. **UNTESTED — Guide performs a new action after Tourist joins.** New instruction should appear.
48. **UNTESTED — Tourist performs matching ACCEPT.** Earliest matching pending ACCEPT should be consumed.
49. **UNTESTED — Tourist performs matching TURNIN.** Matching TURNIN should be consumed.
50. **UNTESTED — Tourist performs unrelated quest action.** Unrelated pending instruction should remain.
51. **UNTESTED / SKIP-eligible — Two similar pending actions.** Earliest matching sequence should be consumed first.
52. **PASS — Completed instruction presentation.** Strike/fade/removal occurs once without replay.

#### F. Guide/Tourist reload and persistence
53. **UNTESTED — Reload Guide while paired.** Guide session should survive and Tourist recover.
54. **UNTESTED — Reload Tourist while paired.** Selected Guide/binding/baseline should survive appropriately.
55. **UNTESTED — Reload with pending Tourist instruction.** Pending instruction should remain.
56. **UNTESTED — Consume an instruction, then reload Tourist.** Consumed instruction should not return.
57. **UNTESTED — Guide reload after several instructions.** Guide action sequence/order should continue.
58. **UNTESTED — Guide Off -> Guide again.** Should create a genuinely new Guide session.
59. **UNTESTED — Tourist observes new Guide session.** Fresh pairing/baseline; old instructions should not replay.
60. **UNTESTED — Guide temporarily leaves party and rejoins.** No stale/corrupt state or old instruction replay.
61. **UNTESTED — Tourist temporarily leaves and rejoins.** No duplicated instructions or Lua errors.
62. **PASS — Both players relog.** On 0.1.17-dev both players logged in while initially ungrouped with persisted Guide/Tourist modes, then formed a party; the relationship resumed and synchronized state settled correctly. The Guide also recovered and retroactively completed two Tourist-finished steps.

#### G. Disparities
63. **UNTESTED — Guide and Tourist have identical quest logs.** No false missing rows.
64. **UNTESTED — Guide has a quest Tourist lacks.** Appropriate disparity row should appear.
65. **UNTESTED — Tourist then accepts that quest.** Disparity should resolve after synchronization.
66. **UNTESTED — Several differing quests.** Multiple disparity rows should display consistently.
67. **UNTESTED — Hide a disparity.** Row should disappear.
68. **UNTESTED — Show Hidden.** Hidden disparity should reappear in hidden-state presentation.
69. **UNTESTED — Unhide.** Row should return to normal disparity list.
70. **UNTESTED — Reload Guide with hidden disparities.** Hidden state should persist within the same Guide session.
71. **UNTESTED — Start a fresh Guide session.** Prior session hidden state must not leak.
72. **UNTESTED — Tourist reloads while Guide disparity view is active.** Temporary unready state must not create false mass-missing disparities.
73. **UNTESTED / SKIP-eligible — Multiple Tourists.** Disparities should order by party slot then quest title.
74. **UNTESTED — Instruction rows + disparities together.** Instructions precede disparities without overwrite/duplication.

#### H. Window/UI persistence
75. **PASS — Drag Guide/Tourist window.** Window can be moved.
76. **PASS? — Reload.** Position persistence was reported as `res` and is currently interpreted as PASS; correct this status if `res` did not mean yes.
77. **UNTESTED — Switch Guide -> Off -> Guide.** Saved window position should remain.
78. **UNTESTED — Switch Tourist -> Off -> Tourist.** Clean behavior with no duplicate frame.
79. **UNTESTED — Repeated mode changes.** No accumulating rows/buttons/errors.
80. **UNTESTED — Show Hidden control.** Only appears/behaves when relevant and should not retain stale state.

#### I. Recovery/robustness stress
81. **UNTESTED — Accept/progress a quest immediately after forming party.** No false empty remote state; eventual correct sync.
82. **UNTESTED — Reload one client during quest activity.** Final state should converge after reload.
83. **UNTESTED — Guide accepts a quest immediately after Tourist pairs.** Instruction should not be lost.
84. **UNTESTED — Guide performs an action around a Tourist reload.** No permanent missing instruction or sequence corruption.
85. **UNTESTED — Rapid quest progress.** Final count correct; no permanently stale revision.
86. **UNTESTED — Party member disconnect/relog.** Stale state invalidates and current state returns.
87. **UNTESTED / SKIP-eligible — Three-player reload/rejoin stress.** No errors/message loops; eventual convergence.
88. **UNTESTED — Watch Lua errors throughout.** Zero PFQG-triggered Lua errors across stress coverage.

#### J. Optional hard-to-force protocol cases
89. **UNTESTED / SKIP-eligible — Missed instruction/full-sync recovery.** Later Guide cursor should recover a missed instruction via full sync.
90. **UNTESTED / SKIP-eligible — Protocol incompatibility.** Older incompatible peer should be excluded cleanly.
91. **UNTESTED / SKIP-eligible — Duplicate-title / numeric quest-ID edge.** Numeric ID wins when both sides have it; no wrong quest match.



### Supplemental Count-Objective Tracker Redesign Tests
These checks cover the intentional 0.1.22-0.1.23 numeric/count presentation change and are separate from binary objective behavior.

C1. **UNTESTED — Count objective heading/self row.** On 0.1.23-dev track a numeric objective such as `Skeletal Fragments: 10/15`. Verify the objective line becomes only `- Skeletal Fragments` and the first child row is the local player as `PlayerName: 10/15`.
C2. **UNTESTED — Self class/count colours.** Verify the local player name is rendered in the local class colour and the local numeric count uses the same progress colour pfQuest previously used for the local inline count.
C3. **UNTESTED — Remote class/count colours.** With a compatible peer on the same count quest, verify their row follows self, their name uses their class colour, and their count uses a colour calculated from their own progress (for example local 10/15 and peer 7/15 may differ in colour).
C4. **UNTESTED — Count progress live update.** Progress self and peer counts and verify values/colours update without duplicated rows, stale values, or objective overlap.
C5. **UNTESTED — Missing equivalent remote objective.** If naturally encountered, verify an otherwise matched remote quest with no equivalent objective shows grey `--`; otherwise SKIP.

### Supplemental Protocol-v2 Reverse-Completion Tests
These checks were added after the original 91-point matrix because reverse Tourist -> Guide completion feedback was introduced later. They are tracked separately so the original matrix numbering remains stable.

#### Assistant mocked/static reconciliation — 0.1.17-dev / 4df6d0b9c1c3682e5077eaaab6b191f445aa3c16
- **PASS — Focused extracted-logic harness: 12/12 assertions.** This is mocked/static coverage under the available texluac/texlua environment, not an in-game test and not a canonical Lua 5.0.3 full-file compiler pass.
- Covered behaviors:
  - one eligible same-session Tourist completion satisfies the Guide-side completion predicate;
  - with two eligible Tourists, one acknowledgement is insufficient and both acknowledgements satisfy completion;
  - a Tourist whose fixed joinBaseline is at/after an older instruction does not block that instruction;
  - zero eligible Tourists do not cause an instruction to auto-complete;
  - a Tourist paired to another Guide is ignored;
  - completion filtering rejects pre-baseline consumed sequences;
  - completion filtering rejects sequences beyond the Guide cursor;
  - completion filtering rejects wrong-session completion state;
  - unrelated PARTY completion traffic is ignored rather than triggering recovery;
  - eligible consumed state is retained only for known Guide instruction records.
- Structural/static reconciliation also passed: protocol remains v2; exactly one instructions component registration remains; Tourist completion uses the existing instructions component; Guide-side feedback reuses the existing Guide/Tourist window; no new owner/component/window was introduced; the current source still has one `SendAddonMessage` call using PARTY transport; no later-Lua/API blacklist token was introduced by this feature.

#### Focused in-game reverse-completion matrix — awaiting user runtime results
R1. **UNTESTED — One Tourist.** Pair the Tourist before the Guide creates a step. When that Tourist completes the matching step, the Guide row must strike through, fade, then disappear.
R2. **UNTESTED — Two Tourists, first completion.** Pair both Tourists before the Guide creates a step. After only Tourist 1 completes it, the Guide row must remain.
R3. **UNTESTED — Two Tourists, all complete.** Continuing R2, after Tourist 2 completes the same step, the Guide row must strike/fade/disappear.
R4. **UNTESTED — Late joiner.** Create a step while Tourist 1 is already paired, then pair Tourist 2 afterward. Tourist 1 completing the older step must be sufficient; late-joining Tourist 2 must not block it.
R5. **UNTESTED — Recovery after Guide reload.** With two eligible Tourists, let Tourist 1 complete the step, reload the Guide and allow synchronization to settle, then let Tourist 2 complete it. The Guide row must then strike/fade/disappear, demonstrating recovered acknowledgement state where practical.
R6. **UNTESTED — Error/replay/premature-completion guard.** Throughout R1-R5, record any PFQG Lua error, duplicate row, row reappearing after removal, repeated completion animation, or Guide completion before every eligible Tourist has finished.
R7. **PASS — Offline/regroup completion recovery.** On 0.1.17-dev both characters logged in with persisted Guide/Tourist modes while initially ungrouped, then formed a party. Pairing resumed and the Guide UI retroactively strike/fade/removed two steps the Tourist had completed previously, confirming persisted consumed-step state can recover through regroup/full-state synchronization.
R8. **UNTESTED — Tourist manual Done for an already-completed stale instruction.** On 0.1.18-dev reproduce a pending instruction for a quest/action the Tourist already completed, click Done on the Tourist row, and verify the Tourist row performs the normal strike/fade/removal.
R9. **UNTESTED — Manual Done feeds back to Guide.** Continuing R8 with one eligible Tourist, verify the corresponding Guide row strike/fade/removes after the Tourist clicks Done; reload/regroup afterward and verify the completed instruction does not return on either side.
R10. **UNTESTED — Instruction NPC-name presentation.** On 0.1.21-dev create new Guide ACCEPT/TURNIN instructions at a resolvable NPC and verify the Tourist row displays `NPC Name` + yellow `!/?` + `Quest Name`, without parentheses or a duplicate marker/gutter. Confirm a long NPC such as `Commander Ashlam Valorfist` displays as `C.A. Valorfist`, short NPC names remain intact, and unresolved-NPC instructions fall back cleanly to yellow `!/?` + quest text.


### Next Implementation / Runtime Sequence
1. Starting from 0.1.23-dev, inspect current Phase 4a/4b persistence and protocol wire/store shapes and implement dormant persisted Guide sessions plus durable Guide-side instruction completion without replacing existing owners.
2. Add PFQG group-hold tracking as a separate supplemental presentation layer: shared tracker retention plus PFQG-owned objective map/minimap nodes/tooltips driven by relevant participant progress. Do not falsify local WoW/pfQuest completion.
3. Keep the linked `Mrs Dalson's Diary` / `Outhouse` / `Locked Cabinet` anomaly deferred as a separate upstream/special-case investigation.
4. After implementation, runtime-test dormant/wake behavior, no instruction generation while dormant, durable completion across reload/regroup/offline eligible Tourists, group-held tracker/map/minimap/tooltips, then run the still-pending C1-C5 and R8-R10 checks before returning to the broad matrix.

## Planned / Next Work
1. Implement dormant persisted Guide semantics and durable Guide-side completion first, preserving Phase 4a/4b ownership and explicitly resolving whether protocol/schema changes are required.
2. Implement PFQG-owned group-hold objective tracking across tracker + world map + minimap + PFQG supplemental tooltips, using real synchronized participant progress and retaining only objectives somebody relevant still needs.
3. Runtime-test the new lifecycle/completion/group-hold behavior together with pending C1-C5 and R8-R10.
4. Fix only demonstrated defects with normal version discipline, then continue the remaining protocol-v2/broad-matrix gaps.
5. Keep the linked three-quest anomaly and unrelated binary/remote visual polish deferred until the above path is stable.
6. After a known-good runtime state exists, review release/promotion readiness separately; do not treat development checks as a runtime test.

## Deferred / Out of Scope
- New feature work beyond the agreed v1 Phase 1–6 scope.
- Release/promotion to main before broad runtime validation is complete or any validation debt is explicitly accepted.
- dev_rulebook.md changes.
- Investigation/fix for the linked `Mrs Dalson's Diary`, `Outhouse`, and `Locked Cabinet` tracking anomaly; user reports the behavior is already incorrect in pfQuest itself as well as PFQG, so handle separately from current tracker presentation work.

## Release / Promotion Notes
- dev_rulebook.md and DEV_PROGRESS.md must never be present on main.
- main remains the bootstrap baseline only.
- No validation debt has been accepted for release.
- External/runtime prerequisite: pfQuest.

## Exact Next Step
From 0.1.23-dev / 3674229c012e6a6eab7c93d87542661d08b9b545, first inspect the existing session/instruction persisted stores and wire formats and implement: (a) persisted Guide session dormant with no window/new instructions until a matching Tourist is present, and (b) permanent Guide-side completion once every Tourist eligible for that instruction has durably acknowledged it, without letting an offline eligible Tourist disappear from the requirement. Then stage the PFQG group-hold tracker/map/minimap/tooltip layer. Keep the three linked-quest anomalies deferred.