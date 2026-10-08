# Development Progress

## Current
- Branch: dev.
- Version: 0.1.53-dev from pfQuest_Group.toc.
- Current gossip implementation: 0.1.53-dev / protocol v4 (G action), committed on dev. Static source inspection only; not compiled or runtime tested.
- Latest addon-affecting development revision: 0.1.52-dev — chained Guide/Tourist instruction renderer, leftmost Guide remove / Tourist Done controls, semantic marker followed by optional abbreviated NPC, separator and priority quest text; FLIGHT has no NPC segment. Implemented, not runtime tested. Commits 71579b4, 101e9d7, 8a2e2a4 (the latter is the version bump).
- Previous addon-affecting development commit: 59608b75a3adcd199b3f0ede641f503cd7529771 — 0.1.51-dev single-item/object alert correction after 0.1.50 runtime. The alert now uses pfQuest's brown item-cluster bag artwork instead of the NPC/sword icon. Guide alert rows are emitted only while at least one matching Tourist still needs the 1/1 item/object; Tourist rows are emitted only while that Tourist still needs it. Fully completed rows therefore do not accumulate or reappear when a later 1/1 objective updates the same quest.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None. main remains exactly bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: runtime-check the 0.1.51 single-item/object alert lifecycle/icon correction and the still-pending 0.1.50 panel-layout correction, then resume the remaining Phase-5 usability validation. FLIGHT rendering/matching already has a positive 0.1.49 runtime result; NPC click-targeting, Guide removal semantics, and the remaining panel checks stay queued.
- Scope boundary: the user explicitly requested post-Phase-6 refinements through the existing owners: Guide reverse-completion feedback, Tourist manual Done, instruction NPC presentation, unified per-player Group Progress rows for both binary and count objectives, dormant/durable Guide sessions, and PFQG-owned group-held objective/map tracking. The old binary tick/cross + remote icon-column presentation is intentionally retired as of 0.1.27-dev. As of 0.1.41 the Tourist panel follows a prepared display-model -> renderer boundary instead of interpreting instruction/session records inside row rendering; NPC-name green/yellow/orange/red colouring is part of that presentation layer.

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
- Phase 2 remains the sole quest-state owner, including the persisted group-hold last-known participant quest cache introduced in 0.1.25-dev.
- Phase 5 remains the sole Guide/Tourist window/disparity presentation architecture.
- Group Progress is independent of Guide/Tourist mode.

### Protocol / Peer State
- Protocol prefix: PFQGROUP; protocol version: 4; SavedVariables schema: 3. Protocol v3 is required as of 0.1.33-dev because the durable instructions wire now supports a third action code, `F` / `FLIGHT`, plus a flight-destination field. Protocol v2 peers are intentionally rejected rather than being treated as compatible with an instruction type they cannot decode. SavedVariables schema remains 3 because normalized local instruction records are additive and require no destructive migration.
- Only actual current party/subgroup members participate; peer/state presentation still scans `party1` through `party4`. Discovery is joiner/self-context announced as of 0.1.32-dev: unrelated member/bot roster changes do not make established PFQG clients announce. A PFQG client announces when its own communication cohort changes (joining from solo, loading/reloading while grouped, or moving raid subgroup).
- Transport remains native Vanilla SendAddonMessage over PARTY. WoW 1.12 SendAddonMessage does not support WHISPER; logical targeting is carried inside PFQG payloads while the physical transport remains PARTY. Ordinary component deltas are silent when no compatible PFQG peer is known.
- Transport wire message types remain HELLO (H), full-state request (R), full snapshot (F), and component delta (D). Instruction records inside the instructions component now support action codes A (ACCEPT), T (TURNIN), and F (FLIGHT).
- State synchronization remains component-based through RegisterStateComponent, SendDelta, and RequestFullSync; flight guidance adds no new state component or transport message type.
- Registered synchronized components remain exactly session, quests, and instructions.
- Live remote peer state remains ephemeral and is removed when the player leaves the party. The Phase-2 group-hold cache separately persists last-known quest snapshots only for relevant members of the current Guide session so an offline unfinished Tourist cannot be mistaken for completion.
- A newly established or changed peer boot id invalidates previously cached remote session/quest/instruction state. Joiner-announced HELLO discovery establishes the boot boundary; compatible existing peers may answer with a logically targeted HELLO and targeted full-state request so both sides learn each other without unrelated PFQG peers responding.
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
- Binary and count objectives now share one presentation system. The native inline progress fraction is replaced by an objective heading, then a self row first followed by one row per compatible peer who has the tracked quest. Binary objectives therefore show per-player `0/1` or `1/1` progress instead of the retired local tick/cross plus remote class/status columns.
- Every player row keeps the class icon, renders `PlayerName:` in that player's class colour, and renders `current/required` using the same pfQuest progress-colour rule for that player's own state (`pfMap.tooltip:GetColor(current, required)` brightened by 0.2 and clamped). A missing matching objective within an otherwise matched remote quest displays grey `--`.
- A compatible PFQG peer who does not have the tracked quest contributes no row for that quest. Group Progress remains independent of Guide/Tourist mode.
- Reusable tracker row regions are hidden/restored as peers change and tracker dimensions are recalculated.

### PFQG Group-Hold Tracking — Implemented in 0.1.25-dev; 0.1.26 native-row correction user-verified, broader GH matrix pending
- WoW/pfQuest remains authoritative for the local player's real quest progress. Group hold never writes local questState progress/completion, Blizzard quest state, pfQuest's PFQUEST node namespace, or personal turn-in state.
- Phase 2 now persists a session-scoped groupHold cache keyed by the active Guide session. It stores last-known ready quest snapshots for relevant same-session participants plus local seen/tracked quest identity. Live peer state is still ephemeral; a temporary disconnect leaves the last-known group-hold snapshot intact so offline unfinished participants continue to count.
- Relevant membership is derived from the existing Phase 4a relationship: a Guide holds for Tourists bound to that Guide/session; a Tourist holds for the selected Guide and same-session sibling Tourists. Explicit session/unpair changes remove that participant from the cache; changing/leaving the local Guide session resets the cache.
- Presentation is dormant whenever no relevant same-session participant is currently present. Rejoining a relevant participant wakes the same persisted hold state immediately, then fresh synchronized quest state replaces the last-known snapshot when available.
- A held objective exists only when at least one persisted relevant participant still has that objective unfinished and the local equivalent is already done or no longer present. If the equivalent quest is still in the local quest log, that current ownership is sufficient relevance proof even if the same-session historical tracked marker was missed; once the local quest is absent, PFQG still requires same-session locally seen + tracked history before retaining remote guidance. This prevents arbitrary remote quests from creating local guidance while covering a completed local objective whose pfQuest tracker row disappeared before PFQG captured tracking history.
- A locally-complete objective that is actively group-held uses the group-held player-row treatment only while pfQuest still exposes a native objective row: objective heading, self first, then persisted relevant participant rows with class/progress colours. As of 0.1.30-dev PFQG does not synthesize a replacement quest/objective block when the native pfQuest row is absent. The Guide/Tourist may still receive separate PFQGROUP map/minimap hold guidance where source mapping is safe.
- World-map/minimap guidance uses the separate PFQGROUP pfMap namespace and only pfQuest's lower objective-source searches (mob, object, item, area trigger, zone). It deliberately never calls SearchQuestID, so it cannot recreate quest giver/start/end/turn-in nodes from another player's state.
- Multi-objective map retention is conservative: PFQG first matches the specific unfinished objective text against localized objective source names from that quest; if no name match exists, it falls back only when exactly one candidate source exists across the relevant categories. Ambiguous complex objectives may therefore retain tracker guidance without a supplemental map node rather than showing a wrong node.
- PFQG supplemental nodes bypass pfQuest's shared unified quest clustering cache and carry a private need key. pfMap.ShowTooltip is wrapped only for PFQGROUP metadata; every ordinary pfQuest tooltip delegates unchanged to the original implementation.
- Group-held map-node tooltips use the real quest/objective heading followed by self and relevant participant progress rows. If the local quest is no longer in the log, the map tooltip may show grey `--` for self rather than inventing a personal completion value; this no longer causes PFQG to create a tracker quest.
- When every persisted relevant participant's latest known state no longer needs an objective, that objective disappears from the supplemental tracker and PFQGROUP map namespace. Only objectives somebody relevant still needs are retained.
- pfQuest source inspection remains the rationale for the supplemental layer: pfQuest's own quest queue deletes/rebuilds PFQUEST nodes from the local quest log, SearchQuestID filters through local GetQuestLogLeaderBoard state and stops on local completion, while the lower database search API accepts an independent addon namespace.

### Guide / Tourist Session and Instructions
- Modes remain Off, Guide, and Tourist. Commands remain /pfqgroup off, /pfqgroup guide, /pfqgroup tourist <player>, /pfqgroup status; /pfqg is an alias.
- Entering Guide from another mode creates a new Guide session id and guideActionSeq=0. Staying in the same Guide mode preserves both. Reload/relog preserves the active Guide session and sequence.
- Tourist follows one specific player and preserves that target through temporary absence.
- Tourist binds only when that compatible peer advertises Guide mode with a Guide session id. joinBaseline is the Guide's current guideActionSeq and remains fixed for that Guide session.
- A different Guide session id causes a fresh binding/baseline. Explicit non-Guide advertisement clears active binding/baseline but preserves Tourist mode and target. Turning Tourist Off clears target/binding/baseline.
- Guide ACCEPT/TURNIN actions and Guide flightpath selections create ordered instruction records using guideActionSeq. Records persist in pfQuest_GroupDB.instructions and synchronize through the existing instructions component.
- A Guide instruction record is validated before guideActionSeq advances.
- Guide sends the instruction delta before the corresponding session cursor delta. A bound Tourist uses the existing Guide session cursor to detect a missing instruction delta and requests the existing full-state resync path; no new scheduler, owner, component, or wire type exists.
- Remote instruction full snapshots are accepted only when coherent with the currently known remote Guide session. Same-session stale cursors cannot roll backward.
- Tourist pending instructions are selected-Guide/session scoped and include only seq > joinBaseline. Consumed instruction sequence numbers persist so reload/full resync does not replay completed work.
- Matching local Tourist ACCEPT/TURNIN consumes the earliest matching pending instruction; numeric questID is authoritative when both sides have one and title is fallback.
- A Tourist may also click Done on a pending instruction when the underlying quest action happened before that instruction could be matched. Done is a semantic completion acknowledgement, not a presentation-only hide: it writes the same persisted consumed sequence state, triggers the existing local strike/fade/removal, and sends the same protocol-v2 completion acknowledgement to the Guide. If PARTY transport is temporarily unavailable, persisted consumed state remains recoverable through the existing instructions full snapshot on later synchronization.
- Tourist consumed sequence state remains persisted in the Phase 4b instruction store. Under protocol v2 a Tourist sends an idempotent completion delta when consuming a step and includes the consumed set in its instructions full snapshot, so missed acknowledgements can recover through the existing full-state path without a new scheduler or component.
- Guide completion is derived only for Tourists paired to the same Guide session whose fixed joinBaseline is below that instruction sequence; Tourists who joined after the step do not block it. When all currently eligible paired Tourists have acknowledged the step, the Guide row uses the existing strike/fade/removal presentation. Acknowledgements seen by unrelated PARTY peers are ignored.

### Phase-5 Guide/Tourist Row Layout Contract — Implemented in 0.1.52-dev / Awaiting Runtime Validation
- Canonical left-to-right order for instruction/objective rows is: `[control] [semantic action icon/marker] [optional NPC/source] [separator] [quest/objective text]`.
- Layout must use a chained left-anchor flow, not absolute per-element x positions and not a control positioned from measured text width. The first visible element anchors to the row's left edge; every later element anchors to the previous visible element's right edge with a small fixed gap. This keeps the row compact and makes each element justify naturally as width changes.
- Guide removable instruction example: `[-] [?] NPC Name - Quest Name`. The Guide `-` is the leftmost control. ACCEPT/pick-up, TURNIN/hand-in and single-item/object loot each use their own semantic marker/icon immediately after the control. The existing ACCEPT `!` / TURNIN `?` meaning is preserved unless a later explicitly approved artwork change replaces those markers; the 1/1 acquisition row uses the approved brown pfQuest item-bag artwork.
- NPC/source text is contextual and optional. When present, it anchors immediately after the semantic icon/marker; the ` - ` separator anchors after the NPC/source. When no NPC/source applies, omit both NPC/source and separator and anchor the quest/objective text directly after the action icon/marker.
- Horizontal-space priority is strict: (1) preserve the left control, (2) preserve the semantic action icon/marker, (3) shorten the NPC/source first using the existing NPC abbreviation/truncation rules, then hide the NPC/source and its separator entirely if required, and only then (4) ellipsize the quest/objective text. Quest/objective text is the primary information and receives all remaining width.
- Raw NPC/source identity must remain separate from rendered text. Hiding, abbreviating or ellipsizing the displayed NPC name must never alter the full raw NPC name used by click-targeting / `TargetByName`.
- FLIGHT follows the same chained grammar but has no NPC/source segment: control (where applicable) -> flight action marker/icon -> destination text. Do not fabricate an NPC or separator for FLIGHT.
- Row types that are semantically different, especially Guide disparity Hide/Unhide rows, are exempt from this instruction/objective grammar and keep their own controls/layout unless explicitly redesigned.
- Tourist rows should follow the same chained ordering principle. Where a Tourist control such as `Done` exists, it occupies the control position for that row rather than being laid out as an unrelated far-right element when this contract is implemented.
- Implemented in 0.1.52-dev; the changed row geometry has not been runtime tested. Guide disparity Hide/Unhide layout remains independent. The legacy split-text renderer remains present but is no longer used by Guide/Tourist instruction rows; removal can follow confirmed runtime behavior.

### Dormant Guide Lifecycle / Durable Completion — Implemented in 0.1.24-dev; 0.1.27 legacy-completion permanence awaiting retest
- Persisted Guide mode/session remains stored across logout/reload, but Guide presentation is now runtime-dormant whenever no Tourist bound to that same Guide session is currently present. The Guide window hides and Guide ACCEPT/TURNIN instruction creation is suppressed while dormant; a matching Tourist reuses/wakes the existing persisted session rather than creating a new one.
- The current behavior observed by the user is the defect motivating this change: logging in solo restored active Guide mode with a very large old instruction list; when Gaia later joined the party, synchronization caused many rows to cross off. The resume/synchronization behavior is desirable, but the solo-active presentation is not.
- Tourist completion acknowledgements remain durable per Tourist. Guide-side schema-2 instruction metadata now persists each new instruction's fixed eligible Tourist cohort, per-Tourist acknowledgements, and derived completed state. Completed Guide instructions are filtered from Guide UI/full instruction snapshots so they do not reappear within the same Guide session.
- Eligibility for permanent Guide completion is frozen when each new instruction is created from the durable Guide participant roster plus current matching Tourists. Temporarily offline eligible Tourists remain in that frozen cohort; explicit unpairing affects future instructions only; late joiners are not retroactively added.
- Ownership remains unchanged: Phase 4a owns session identity/pairing and Phase 4b owns instruction/completion state. Protocol stays v2. Fresh schema-2+ instructions remain authoritative and use only their frozen durable eligibility cohort. Schema-1 historical instructions have no recoverable authoritative historical roster; 0.1.26 restored live-party recovery for them, and 0.1.27 now persists a legacy row as completed once that recovery successfully observes every currently eligible same-session Tourist complete. Persisted completed markers are restored during normalization, so recovered rows should not replay after leave/rejoin, reload, or relog.

### Flightpath Guidance — Implemented in 0.1.33-dev; validation paused until Tourist UI rendering is repaired without Guide regression
- Flightpath guidance is owned by the existing Guide/Tourist instruction system; there is no separate flight state machine, window, scheduler, or protocol component.
- PFQG wraps Vanilla `TakeTaxiNode(slot)`. While the taxi map is open it captures `TaxiNodeName(slot)` and, for a reachable destination, treats the actual Guide taxi selection as a `FLIGHT` instruction.
- A Guide creates a flight instruction only while at least one active same-session Tourist exists, matching the dormant Guide rule used for quest instructions.
- Flight instructions persist in the existing Guide instruction store, participate in the same fixed eligible-Tourist cohort, and use the same completion acknowledgement/durability machinery as ACCEPT/TURNIN.
- Tourist presentation is `Fly to <destination>` in the existing Guide/Tourist window. No separate map marker is created.
- When a bound Tourist calls `TakeTaxiNode` for the same destination name, PFQG consumes the earliest matching pending FLIGHT instruction automatically and sends the ordinary completion acknowledgement. Manual Done remains a fallback for a missed/raced action or an instruction the Tourist cannot reproduce automatically.
- Matching is by the taxi destination name exposed by the client. This is appropriate for the current same-locale addon scope; no cross-locale stable taxi-node identity has been introduced.
- Protocol version is 3 because older v2 clients cannot decode the new durable FLIGHT record. Both PFQG clients must run 0.1.33-dev or later for this feature.

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
- 9ec172dbc8ccf2e9af2835346a7b93f1572f66c5 — 0.1.48-dev Phase-5 panel usability Pass 2: fixed resizable viewport, stock vertical scrollbar, and mouse-wheel scrolling; no horizontal scrolling or truncation.
- 068fa089caa8406c35031071f6846a792dbdb126 — 0.1.47-dev Phase-5 panel usability Pass 1: 15 pt inline ACCEPT/TURNIN marker, bottom-right resize grip, and persisted Guide/Tourist panel width/height; no scrolling or truncation.
- 74a7e9d336a3936bfe170f807a71e4dacb279875 — 0.1.46-dev switch the shared single-item/object alert row to pfQuest's `icon_npc` artwork.
- 1f03df4124f2e28e63c6d1ed6cab3204665a0fb5 — 0.1.27-dev persist recovered legacy Guide completion and migrate binary objectives to unified per-player progress rows.
- 4b1b1bb17b0cfbfc9e1f9864e343745f351454fa — 0.1.26-dev fix for legacy Guide wake completion fallback and group-held native objective presentation.
- e168712cccb9959646491073393df1639e00a5d5 — 0.1.25-dev persisted PFQG group-held tracker/map/minimap/tooltip guidance with schema-3 Phase-2 last-known state.
- 01ec7eec406ecf3a9960149aac80dbbdcb653deb — 0.1.24-dev dormant persisted Guide lifecycle and durable Guide-side completion metadata.
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
- 0.1.27-dev screenshot/runtime: unified binary presentation is visually correct for a completed shared binary objective. The tracker shows the objective heading with separate class-icon/name rows for self and the matched peer, both at `1/1`, with no legacy tick/cross/status column. User explicitly reports the result is clean.
- 0.1.26-dev runtime: after the Tourist rejoins the persisted session, the Guide historical backlog again crosses off/removes as completion state synchronizes. This confirms the live legacy recovery fallback works.
- 0.1.26-dev runtime also exposed that recovered legacy completion was not durable: leaving and rejoining caused the full historical list to appear and cross off again. 0.1.27 targets that demonstrated persistence gap.
- 0.1.26-dev held-objective tracker treatment is user-accepted as clean/intuitive: objective heading plus per-player progress rows. The user explicitly requested that the older binary `0/1`/tick-cross mechanic be migrated to this same presentation globally; 0.1.27 implements that migration.
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
- 0.1.51-dev shared single-item/object alert correction: `SINGLE_OBJECTIVE_ICON` now uses pfQuest `img\\cluster_item` (the brown item bag) instead of `img\\icon_npc`. Guide rows are suppressed once every matched Tourist has completed that 1/1 item/object; Tourist rows are suppressed once the local Tourist has completed it. This prevents completed objectives from reappearing/accumulating when another 1/1 objective on the same quest changes. Sound triggering remains the existing live Guide incomplete -> complete delta path and was not changed.
- 0.1.50-dev Phase-5 panel layout correction: fixes the demonstrated 0.1.49 visual/runtime defects without changing instruction/session ownership. Scrollbar visibility is now derived from content height versus the actual reserved viewport; hidden-footer space is outside the scroll child; the stock scrollbar is re-anchored inside the right border and above the footer/resize-grip area. Guide instruction removal is a compact 20 px `-` button positioned directly after the rendered instruction text, reducing the previous large rightward gap. Runtime is pending.
- 0.1.49-dev Phase-5 panel usability Pass 3: rendered text now uses the current vertical viewport width instead of fixed 180/238 px row widths. Guide/Tourist action controls and shared objective-alert icon/status regions are reserved first; only the remaining text region is eligible for ellipsis. ACCEPT/TURNIN still use the existing >18-character NPC abbreviation before rendered-width truncation, while the raw full NPC name remains untouched in `targetNpcName` for exact click-targeting. FLIGHT still uses the existing `Fly to %s` formatter, the vertical-only Pass-2 scroll architecture remains, and no horizontal scrollbar/path exists. Runtime is pending as part of the combined Passes 1-3 panel check.
- 0.1.48-dev Phase-5 panel usability Pass 2: the shared Guide/Tourist panel now uses a clipped `UIPanelScrollFrameTemplate` content viewport. Guide rows, Tourist rows, and shared single-item/object alert rows are children of the scroll child; content height drives only the vertical scroll range, not panel height. The stock vertical scrollbar is hideable when content fits, mouse-wheel input scrolls by 40 px, and no horizontal scrollbar/path exists. Legacy Pass-1 default size state migrates from 280x34 to a usable 300x154 viewport; minimum resize is 300x74 so the stock 1.12 scrollbar geometry remains valid. Runtime is intentionally deferred until after Pass 3.
- 0.1.47-dev Phase-5 panel usability Pass 1: Guide and Tourist ACCEPT/TURNIN rows split only the inline yellow action marker into a dedicated 15 pt FontString while leaving ordinary row text on the existing 12 pt path. FLIGHT keeps the existing `Fly to %s` text path. The shared panel restores/saves width and height and exposes a bottom-right stock resize grip. Runtime is intentionally deferred until after Pass 3.
- 0.1.29-dev supplemental-node visibility fix: lower pfQuest source searches still receive `cluster=true` so PFQGROUP nodes bypass pfQuest's shared unified clustering cache, but after insertion PFQG clears the stored node metadata's `cluster` display flag for that private need key. This separates cache-isolation semantics from pfQuest's user-facing cluster visibility settings; the node remains in the PFQGROUP namespace and keeps its private need key/tooltip metadata.
- 0.1.28-dev group-hold relevance fix: a current local equivalent quest now qualifies the held-objective path even if `groupHold.localTracked` was not captured before pfQuest removed the completed objective row. If the local quest is no longer present, the previous same-session `localSeen + localTracked` requirement remains. This targets the demonstrated case where a Tourist finished an objective while the Guide still needed it but the Tourist saw no retained Guide objective.
- 0.1.27-dev legacy completion permanence: a successful pre-durable live recovery now writes `guideCompleted[seq]`, and normalization preserves stored completed markers for valid records in the same Guide session. Fresh durable instructions continue to use fixed eligibility snapshots and do not use this fallback.
- 0.1.27-dev unified tracker rows: the dedicated binary texture/column machinery and status-width accounting are removed. Binary objectives now flow through the same reusable `pfqGroupRows` path as count objectives: objective heading, self row, then matched party rows with class icon/name and per-player numeric progress colour.
- 0.1.26-dev regression fix: for pre-durable Guide instructions with unknown historical eligibility only, Guide completion presentation again evaluates currently paired same-session Tourists and their synchronized persisted consumed sets. Fresh schema-2+ instructions still use the fixed durable cohort and are not affected by this fallback.
- 0.1.26-dev held-native tracker fix: when a locally-complete objective is actively held for a relevant participant, the visible native tracker objective uses the same objective-heading + self/participant row treatment as group hold, so the old local tick + remote class icon + cross strip is not shown for that held objective. Supplemental PFQG rows remain the fallback after pfQuest removes the native objective row.
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

### Static / Automated Checks — 0.1.26-dev Runtime-Regression Delta
Exact addon-affecting commit: 4b1b1bb17b0cfbfc9e1f9864e343745f351454fa.
- Version discipline: passed; 0.1.25-dev -> 0.1.26-dev in the same addon-affecting commit.
- Protocol/state ownership: PFQGROUP remains protocol v2 and SavedVariables schema 3; synchronized registrations remain exactly session, quests, and instructions.
- Transport: exactly one SendAddonMessage call remains and it uses the existing three-argument PARTY distribution path.
- Legacy completion guard: the restored live-party predicate is reachable only when durable `guideCompleted[seq]` is false and `guideEligibilityKnown[seq]` is false; known schema-2+ eligibility therefore cannot fall back to current-party membership.
- Held tracker guard: `FindGroupHoldNeed` matches numeric quest ID when both sides have one and falls back to title only when at least one side lacks an ID. Only an objective already present in the computed group-hold need set enters the held-native player-row branch.
- Group-hold map ownership is unchanged; the source still contains no `SearchQuestID` call.
- Later-Lua/API blacklist scan on the exact committed source found no `string.match`, `string.gmatch`, `table.unpack`, `RegisterAddonMessagePrefix`, `C_QuestLog`, `C_ChatInfo`, `C_Timer`, or `goto` token.
- No new top-level local was added; expected top-level pressure remains 154, leaving 46 below Lua 5.0.3's 200-local top-level chunk limit.
- Canonical Lua 5.0.3 full-file compiler pass was not run: the GitHub connector source/checker is not mounted in the executable container and that container cannot resolve GitHub. Do not treat the static checks as a compiler or in-game pass.

### Static / Automated Checks — 0.1.27-dev Unified Tracker / Legacy Persistence Delta
Exact addon-affecting commit: 1f03df4124f2e28e63c6d1ed6cab3204665a0fb5.
- Version discipline: passed; 0.1.26-dev -> 0.1.27-dev in the addon-affecting commit.
- Protocol/state ownership unchanged: protocol v2, SavedVariables schema 3, and exactly three synchronized components (session/quests/instructions).
- Transport unchanged: exactly one `SendAddonMessage` call remains.
- Retired binary presentation artifacts are absent from the exact source: no `EnsureLocalBinaryStatus`, `EnsureBinaryGroupStatus`, `pfqGroupLocalBinary`, `pfqGroupBinary`, `pfqGroupStatusWidth`, tick texture, or cross texture remains.
- Binary/count presentation now shares one `EnsureGroupProgressRow` constructor; matched peer filtering and party order are unchanged.
- Legacy completion persistence is limited to successful unknown-eligibility live recovery; stored completed markers are restored only for valid records in the same Guide session.
- Group-hold map ownership is unchanged and the source still contains no `SearchQuestID` call.
- Later-Lua/API blacklist scan found no `string.match`, `string.gmatch`, `table.unpack`, `RegisterAddonMessagePrefix`, `C_QuestLog`, `C_ChatInfo`, `C_Timer`, or `goto` token.
- Expected top-level local pressure is 152, 48 below Lua 5.0.3's 200-local chunk limit.
- Canonical Lua 5.0.3 full-file compiler pass was not run because the connector-backed addon/checker files are not mounted in the executable environment.

### Static / Automated Checks — 0.1.28-dev Group-Hold Relevance Delta
- Focused source review PASS: the only Lua behavior change is the held-quest relevance gate from `seen and tracked` to `localQuest or (seen and tracked)`, preserving historical proof requirements after local quest removal while allowing a current local quest to prove relevance.
- Protocol remains v2; SavedVariables schema remains 3; no new synchronized component, state owner, map namespace, or local quest-state mutation was introduced.
- Canonical Lua 5.0.3 compiler check was not run in this connector-only environment; do not claim a compiler pass.

### Static / Automated Checks — 0.1.29-dev Supplemental Node Visibility
- Focused diff PASS: no quest-state, session, protocol, or source-selection logic changed. The delta only adds `FinalizeGroupHoldNodes(need)` and calls it after successful source insertion, clearing `cluster` on stored PFQGROUP metadata while leaving the source-search input clustered for cache isolation.
- pfQuest source review confirms `showcluster=0` hides world-map nodes whose stored metadata has `cluster=true`, and `showclustermini=0` does the same on minimap. The new finalization step removes only that presentation flag from PFQGROUP nodes.
- Canonical Lua 5.0.3 compiler check was not run in this connector-only environment; do not claim a compiler pass.

### Static / Automated Checks — 0.1.30-dev Tracker Ownership Correction
- Focused diff PASS: `RefreshGroupHoldTracker()` no longer calls `EnsureGroupHoldTrackerFrame()` or renders quest/objective/player rows; if a legacy in-memory fallback frame exists it is hidden and zeroed. Native tracker augmentation remains in `ApplyGroupProgressToButton()` and still resolves held needs through `FindGroupHoldNeed()`.
- Group-hold need calculation, participant durability, PFQGROUP map/minimap source selection, protocol v2, and SavedVariables schema 3 are unchanged.
- Canonical Lua 5.0.3 compiler check was not run in this connector-only environment; do not claim a compiler pass.

### Static / Automated Checks — 0.1.31-dev Raid Sync Burst Reduction
- Focused transport diff PASS: `RefreshParty()` no longer sends `SendFullState()` on every roster event and emits discovery only when the effective local `party1`-`party4` roster changes.
- HELLO handling now requests a full state only for a newly established boot or missing remote state; repeated HELLO from an already synchronized same-boot peer does not produce a full snapshot.
- Full-state requests now include the normalized requested peer name in the existing `R` payload; 0.1.31 peers ignore requests not addressed to themselves, while an empty payload remains backward-compatible with earlier broadcast semantics.
- Protocol remains v2 because wire framing/types are unchanged and the `R` payload extension is additive; older v2 peers may still respond broadly to a targeted request, so the strongest spam reduction requires both PFQG users on 0.1.31-dev.
- Canonical Lua 5.0.3 compiler check was not run in this connector-only environment; do not claim a compiler pass.

### Static / Automated Checks — 0.1.32-dev Joiner-Announced Discovery
- Focused call-path review PASS: ordinary `PARTY_MEMBERS_CHANGED` still rebuilds the local `party1`-`party4` roster and can emit local `PARTY_CHANGED`, but no longer calls `SendHello()` based on roster membership changes.
- `Addon.AnnounceOwnGroupContext()` is the only roster-side discovery trigger. It sends HELLO only when this client's own context changes from the previously recorded context and the client is not solo. Party uses `GROUP:1`; raid uses the player's `GetRaidRosterInfo()` subgroup, so adding/moving other members without moving the local player does not announce.
- Targeted HELLO replies include `target=<normalized player>` in the existing HELLO payload; 0.1.32 peers ignore HELLOs addressed to someone else. Wire type/framing and protocol version remain v2; this is an additive field.
- `Addon.SendDelta()` now returns without network transmission unless the target is a known compatible peer or at least one compatible current peer exists for broadcast deltas. Local quest/session state still advances, so a later discovered peer receives current state through full synchronization.
- Physical transport remains PARTY because Vanilla 1.12 has no addon-message whisper path. The optimization eliminates unnecessary sends; it does not make PARTY packets physically private.
- Canonical Lua 5.0.3 compiler check was not run in this connector-only environment; do not claim a compiler pass.

### Static / Automated Checks — 0.1.33-dev Flightpath Guidance
- Focused source review PASS: `NormalizeInstructionRecord` accepts ACCEPT/TURNIN/FLIGHT and requires a non-empty destination for FLIGHT while keeping quest fields authoritative only for quest actions.
- Instruction serialization PASS by inspection: action code `F` and the destination field round-trip through the same instruction record format; existing A/T records remain represented by their existing codes.
- Ownership PASS: both quest and flight Guide actions now route through `Addon.CreateGuideInstruction`, preserving one durable instruction owner, one sequence, one eligibility snapshot path, one instructions component, and one completion pipeline.
- Taxi hook PASS by inspection: the wrapper captures `TaxiNodeName(slot)` / optional `TaxiNodeGetType(slot)` before calling the original `TakeTaxiNode(slot)`, then records only non-empty/non-INVALID reachable selections.
- Tourist auto-completion PASS by inspection: the earliest pending FLIGHT instruction with the same destination is consumed via `CompleteTouristInstruction`; manual Done remains unchanged.
- Transport/component structure unchanged apart from protocol version: exactly one source call to `SendAddonMessage` remains, and no new synchronized component was added.
- Canonical Lua 5.0.3 compiler check was not run in this connector-only environment; do not claim a compiler pass.

### Static / Automated Checks — 0.1.51-dev Single-Objective Alert Correction
Exact addon-affecting commit: 59608b75a3adcd199b3f0ede641f503cd7529771.
- Version discipline: passed; 0.1.50-dev -> 0.1.51-dev in the same addon-affecting commit.
- Scope check: exact delta changes only `pfQuest_Group.lua` and `pfQuest_Group.toc`.
- Artwork check: the alert texture changes from pfQuest `img\\icon_npc` to pfQuest `img\\cluster_item`; no asset is copied into PFQG.
- Guide lifecycle check: an alert is inserted only when at least one matched participant exists and `allComplete` is false, so a row disappears once every relevant Tourist completes it and cannot be resurrected merely by a later objective-state update.
- Tourist lifecycle check: an alert is inserted only when the Guide objective is complete and the matching local objective is still incomplete, so local completion removes that row immediately on the next state refresh.
- Sound/protocol check: `RemoteGuideSingleObjectiveCompleted`, `PlaySoundFile(SINGLE_OBJECTIVE_SOUND)`, protocol v3, state components and wire formats are unchanged.
- Canonical Lua 5.0.3 full-file compiler pass was not run; connector-backed exact files/checker remain unavailable in the executable environment.

### Static / Automated Checks — 0.1.50-dev Panel Layout Correction
Exact addon-affecting commit: 371f220a8c287446e928d84d98711532efc675e1.
- Version discipline: passed; 0.1.49-dev -> 0.1.50-dev in the same addon-affecting commit.
- Scope check: exact delta changes only `pfQuest_Group.lua` and `pfQuest_Group.toc`.
- Overflow decision: scrollbar visibility is now computed explicitly from row-content height versus the viewport height after footer reservation; no-overflow state resets the scroll value and hides the bar.
- Footer/border geometry: the viewport reserves 31 px at the bottom only when Show Hidden is present; that footer space is no longer added to scroll-child content. The scrollbar is re-anchored 7 px inside the panel right edge and ends above either the Show Hidden footer or the resize grip.
- Width geometry: the viewport reserves right-side scrollbar space only while overflow exists, otherwise reclaiming that width for row text.
- Guide remove control: instruction rows reserve 28 px instead of 58 px, use a 20 px `-` button, and place it 4 px after the measured rendered instruction text. Disparity Hide/Unhide and Tourist Done keep their existing 52 px controls.
- Ownership/protocol check: no session, instruction, transport, protocol, SavedVariables schema, FLIGHT formatter/matcher, or raw NPC-targeting path changed.
- Canonical Lua 5.0.3 full-file compiler pass was not run; connector-backed exact files/checker remain unavailable in the executable environment.

### Static / Automated Checks — 0.1.49-dev Phase-5 Panel Usability Pass 3
Exact addon-affecting commit: 2f330ebe2580df7bcc20009755c8b0efae5c8be7.
- Version discipline: passed; 0.1.48-dev -> 0.1.49-dev in the addon-affecting commit.
- Scope check: the addon commit changes only `pfQuest_Group.lua` and `pfQuest_Group.toc`.
- Width-aware layout check: row width derives from the current vertical scroll viewport and the scroll child is kept to that viewport width. At the 300 px default panel width the previous 264 px row geometry and 238/180 px text allocations are preserved.
- Control/status reservation check: Guide/Tourist action rows reserve 58 px for the 52 px control plus spacing before text width is calculated; shared objective-alert rows reserve their existing icon/status region first and then ellipsize only the remaining text region.
- Rendered-text ellipsis check: the shared display helper measures the actual FontString width, adds `...` only when needed, and preserves WoW colour-code tokens while changing only the rendered FontString text.
- NPC-targeting check: the existing `string.len(npcName) > 18` abbreviation path is unchanged. Guide and Tourist rows still retain the raw full `instruction.npcName` in `targetNpcName`, and both click handlers still call `TargetByName(row.targetNpcName, 1)`.
- FLIGHT preservation check: `GuideTouristInstructionText` is byte-identical to the 0.1.48 handoff version, including `L.INSTRUCTION_FLIGHT or "|cffffd100Fly|r to %s"`; FLIGHT received no special new formatter or state path.
- Horizontal-boundary check: no `SetHorizontalScroll`, `GetHorizontalScroll`, `HorizontalScroll`, horizontal scrollbar, or horizontal handler was introduced; the existing `UIPanelScrollFrameTemplate` remains the sole scrolling path.
- Pass-1/Pass-2 preservation check: the 15 pt inline action-marker path and the vertical scroll template remain present; the exact implementation commit retains the prior instruction builder while changing only panel rendering/geometry plus the required version bump.
- Canonical Lua 5.0.3 full-file compiler pass was not run; the exact connector-backed repository/checker bytes are not mounted into the executable environment. This is static inspection only, not an in-game PASS.

### Static / Automated Checks — 0.1.48-dev Phase-5 Panel Usability Pass 2
Exact addon-affecting commit: 9ec172dbc8ccf2e9af2835346a7b93f1572f66c5.
- Version discipline: passed; 0.1.47-dev -> 0.1.48-dev in the same squashed addon-affecting commit.
- Scope check: the addon commit changes only `pfQuest_Group.lua` and `pfQuest_Group.toc`.
- Viewport check: Guide, Tourist, and shared objective-alert rows are parented to one scroll child under the existing Phase-5 window; content updates resize the scroll child rather than auto-growing the panel.
- Vertical-scroll check: the implementation uses the stock 1.12 `UIPanelScrollFrameTemplate`, marks its scrollbar hideable when no overflow exists, and adds 40 px mouse-wheel movement through the generated vertical scrollbar.
- Horizontal-boundary check: no horizontal-scroll handler or horizontal scrollbar/path was introduced.
- Pass-1 preservation check: the dedicated 15 pt inline-marker assignments are unchanged from the 0.1.47 baseline; `L.INSTRUCTION_FLIGHT or "|cffffd100Fly|r to %s"` remains unchanged; NPC display-name logic occurrence count is unchanged.
- Architecture check: protocol remains v3; no synchronized component, session/instruction/state owner, or top-level local declaration count changed.
- Size migration check: legacy/default 280 width moves to 300 and legacy/default 34 height moves to 154; minimum resize is 300x74 so the stock vertical scrollbar has valid room for its 16 px up/down buttons.
- Pass-3 boundary check: width-aware ellipsizing/truncation is still not implemented.
- Canonical Lua 5.0.3 full-file compiler pass was not run; the exact connector-backed branch bytes were not available in the executable container. This is static inspection only, not an in-game PASS.

### Static / Automated Checks — 0.1.47-dev Phase-5 Panel Usability Pass 1
Exact addon-affecting commit: 068fa089caa8406c35031071f6846a792dbdb126.
- Version discipline: passed; 0.1.46-dev -> 0.1.47-dev in the same addon-affecting commit.
- Scope check: the commit changes only `pfQuest_Group.lua` and `pfQuest_Group.toc`.
- Marker presentation check: Guide and Tourist instruction row constructors each create a dedicated inline action-marker FontString using the existing row font path/flags at 15 pt; ordinary Tourist text and suffix remain on the existing 12 pt font path. The existing Guide normal-text path is unchanged.
- FLIGHT check: `L.INSTRUCTION_FLIGHT or "|cffffd100Fly|r to %s"` remains unchanged and does not receive the enlarged action-marker treatment.
- Resize persistence check: `guideWindow.width` / `height` normalize into the existing UI state, initialize the panel size, and are saved when the bottom-right grip finishes sizing. Position-only drag still saves position without overwriting size.
- Pass-boundary check: no `OnMouseWheel` handler or `ScrollFrame` was introduced; no width-aware ellipsizing/truncation behavior was added.
- Vertical behavior remains intentionally transitional for Pass 1: content-driven auto-grow is retained and saved enlarged height is treated as a minimum. Shrinking below required content height is deferred until the scrolling/viewport pass.
- Canonical Lua 5.0.3 full-file compiler pass was not run because the connector-backed repository/checker files are not available in the executable environment; this is static inspection only, not an in-game PASS.

### Checks Not Actually Runnable
- Exact full-file Lua parser smoke: not run against the exact 0.1.51-dev blob because GitHub connector-backed repository bytes are not materialized into the executable container.
- Canonical Lua 5.0.3 compiler check: not run / unavailable against the exact 0.1.51-dev blob. The canonical checker exists in VanillaTemplate, but the connector-backed checker/source and addon blob are not mounted into the executable environment.
- The 0.1.51-dev alert correction has not yet received in-game validation. The 0.1.50-dev panel-layout delta also remains runtime-pending; automated/compiler limitations remain separate from runtime evidence.

### Current Issues / Validation Debt
- 0.1.51-dev fixes the demonstrated alert icon/completed-row accumulation defect and is runtime-pending. The dinger itself has positive 0.1.50 runtime evidence.
- 0.1.50-dev fixes the demonstrated 0.1.49 panel geometry defects and is runtime-pending. Do not upgrade the overall Phase-5 Passes 1-3 panel series to PASS until scrollbar visibility/placement/footer clearance, compact remove placement, resize/persistence, overflow scrolling, ellipsis, NPC targeting and Lua-error guard are exercised on the current build.
- 0.1.45-dev shared single-item/object alert is runtime-pending. Static inspection confirms the sound path is `Sound\\Interface\\levelup2.wav`, sound playback occurs only in remote quest delta application (not full-sync application), the qualifier is strictly `required == 1` plus `item`/`object`, and the new presentation uses a separate objective-row pool rather than modifying the stable instruction-row layout. The rows currently remain visibly struck after completion until the matching quest/objective leaves synchronized state; there is no completion fade in this first implementation.
- 0.1.43-dev runtime observation: both clients see each other's quest/objective progress in the tracker and the user describes that path as very stable, but map/minimap tooltip presentation is asymmetric. The Guide sees Gaia's progress through PFQGROUP's retained Group Hold node tooltip; Gaia's ordinary incomplete pfQuest node still uses pfQuest's native local-only tooltip and therefore does not show the Guide's progress. 0.1.44 fixes the presentation boundary by augmenting ordinary pfQuest quest tooltips with the same synchronized group-progress model instead of creating duplicate PFQGROUP nodes or changing Group Hold semantics.
- 0.1.43-dev Guide removal is runtime-pending. The Guide `Remove` button sets a distinct durable removal flag rather than faking completion; Guide/Tourist pending snapshots omit removed records, and late Tourist completion acknowledgements for those records are ignored. The existing full-state snapshot is intentionally used to propagate the changed authoritative pending set because protocol-v3 instruction deltas are append-only and do not encode removals.
- 0.1.40-dev runtime FAIL: restoring the exact 0.1.32 renderer did not restore Tourist text. Guide ACCEPT still rendered correctly; the Tourist panel still showed a blank instruction row with its action button present. This rules out the later 0.1.35-0.1.39 row-layout experiments as the sole cause and justifies the 0.1.41 structural split rather than another shared-renderer patch.
- History reconciliation for the panel regression: 0.1.31 communication-spam changes and 0.1.32 joiner-announced discovery made no Guide/Tourist row-layout changes. 0.1.33 flight/protocol-v3 changed instruction records and added FLIGHT but likewise left the panel row renderer unchanged. 0.1.39 then proved that merely isolating Tourist text from the old zero-width marker anchor was insufficient: Guide ACCEPT displayed normally, the Tourist received a blank row and blank button, and the Tourist turning in the quest still caused the Guide row to strike through. That demonstrates creation, transport, Tourist matching, consumption, and reverse completion while the Tourist text layer remains visually broken. 0.1.40 now restores the exact 0.1.32 renderer wholesale as the decisive renderer-vs-event/state test.
- 0.1.26 live legacy Guide recovery is user-verified, but completion was demonstrated not to persist across leave/rejoin; 0.1.27 persists successful recovered completion and requires runtime verification across leave/rejoin, reload, and relog.
- The 0.1.25 held-native tick/class-icon/cross regression is fixed and user-accepted in 0.1.26. The old binary icon-strip mechanic itself is now intentionally retired in 0.1.27 and replaced globally by per-player progress rows; the new binary presentation is runtime-untested.
- Protocol remains v2 and SavedVariables schema remains 3; 0.1.27 changes only local persistence/presentation. Both clients should use the exact 0.1.27 build for retest.
- The existing no-quest filtering rule remains: peers without the tracked quest must not contribute a row.
- Historical binary icon-strip fixes from 0.1.11-0.1.14 remain useful validation history, but their presentation path no longer exists in 0.1.27 and must not be treated as validation of the new row layout.
- Static triage excludes the Lua 5.0.3 200-local cap as the reported error source; rough current top-level local pressure is 159 on 0.1.41-dev, leaving margin below the 200-local top-level chunk limit.
- No obvious later-Lua syntax/API blacklist hit is present in the current source.
- Canonical Lua 5.0.3 compiler check remains not run against the exact 0.1.27-dev source: the connected GitHub source/checker is not mounted in the executable environment, and the executable container cannot resolve GitHub.
- Protocol-v2 reverse-completion now has partial user runtime validation on 0.1.17-dev: after both players logged in on characters with persisted Guide/Tourist modes while initially ungrouped, forming the party re-established the Guide/Tourist relationship and the Guide UI retroactively strike/fade/removed two steps the Tourist had completed previously. This demonstrates persisted completion state recovering through regroup/full-state synchronization. Live one-Tourist completion, two-Tourist gating, late-join gating, and the focused recovery variants remain separately untested unless explicitly covered below.
- Demonstrated 0.1.17 stale-instruction defect: when the Guide later ACCEPTs/TURNINs a quest action the Tourist had already performed before the instruction existed, the Tourist has no future matching local quest event to consume that instruction, leaving a permanent Tourist row and therefore a permanent Guide row. 0.1.18-dev addresses this with explicit Tourist Done acknowledgement; runtime validation is pending.
- Demonstrated instruction-presentation defect: Tourist rows were not showing NPC names even though `npcName` is already carried in instruction state when resolvable; the shared formatter discarded that field and returned only the quest title. 0.1.19-dev renders the stored NPC name when available; runtime validation is pending.
- Initial performance A/B on 0.1.16: with PFQG enabled, moving the mouse anywhere on screen dropped from about 120 FPS to below 100 with poor frametime; with PFQG disabled but pfQuest still enabled, mouse movement still dropped FPS (about 120 -> 80) but frametime felt substantially smoother.
- 0.1.17-dev performance fix: the always-installed main quest-scan OnUpdate was replaced by a hidden worker frame that is shown only while a quest scan is actually pending and hides itself immediately when idle. Follow-up user A/B after updating and re-enabling PFQG reports that enabled frametime now feels no worse than disabled. Treat the idle quest-scan OnUpdate as a confirmed PFQG performance contributor and the 0.1.17 delta as user-verified for this symptom.
- Separate from the mouse-specific symptom, the current Vanilla PARTY transport still has a known fan-out inefficiency: logically targeted recovery packets are PARTY broadcasts without an encoded recipient, so non-target PFQG peers can process them. This is a concrete optimization candidate, but it has not yet been changed because it does not explain a stutter that occurs only while the mouse moves.
- Deferred linked-quest anomaly reported by user: the related quests `Mrs Dalson's Diary`, `Outhouse`, and `Locked Cabinet` do not track correctly in pfQuest itself and also do not track correctly through PFQG's quest interface. Treat this as a separate later investigation into upstream/special linked-quest identity/objective behavior; do not fold it into the count-tracker UI change.

## Testing

### Latest Runtime Result
- 0.1.50-dev shared single-item/object alert partial runtime: Tourist dinger PASS for the tested 1/1 loot objective. The user reports the cue fires correctly. Visual/lifecycle FAIL: the row used the wrong sword/NPC icon instead of the intended brown bag; after a later second 1/1 item objective updated, both completed rows were visible and did not clear. The first tested row had appeared to hide after both players looted it, then reappeared with the second update. 0.1.51 directly filters completed alert rows and swaps the icon; this delta is runtime-pending.
- 0.1.49-dev partial runtime result: FLIGHT presentation/matching PASS. Both Guide and Tourist saw the flight instruction for travel to Ironforge; when the Tourist selected the same flight, the Tourist instruction disappeared as expected. This is positive runtime evidence for FLIGHT rendering, matching and completion on the exact 0.1.49-dev behavior inherited by 0.1.50-dev; the new 0.1.50 panel-layout delta itself remains untested.
- 0.1.49-dev panel-layout runtime FAIL before the full combined checklist: screenshot/user observation showed the scrollbar visible without overflow, too far right over the panel border, and vertically too long so it overlapped the Show Hidden/footer row. The Guide `Remove` control also tracked width resize but sat too far to the right. These demonstrated defects authorize the focused 0.1.50 layout correction; no broader Passes 1-3 PASS is recorded.
- 0.1.48-dev implemented / static-checked / runtime deliberately deferred: Phase-5 panel usability Passes 1-2 are present at exact addon commit 9ec172dbc8ccf2e9af2835346a7b93f1572f66c5. No in-game result is recorded for marker sizing, resizing/persistence, viewport behavior, scrollbar, or mouse-wheel scrolling; user requested runtime only after Pass 3.
- 0.1.45-dev implemented / runtime pending: shared single-item/object alert now derives entirely from synchronized quest state. Tourist one-shot audio uses `Sound\\Interface\\levelup2.wav` on a live Guide incomplete -> complete delta only. Guide/Tourist bag rows and X/check/strike presentation are derived locally from current matching quest state; no new protocol wire/state was introduced.
- 0.1.44-dev runtime PASS: user confirms the symmetric shared-quest map/minimap tooltip now works. Together with the prior tracker report, bidirectional Group Progress presentation is currently described as stable.
- 0.1.43-dev runtime PASS for bidirectional Group Progress tracker stability: user reports both Guide and Tourist consistently see each other in the quest tracker and describes it as very stable. Runtime FAIL/ASYMMETRY for map tooltip presentation: Guide receives Gaia progress in a PFQGROUP tooltip, while Gaia does not receive the Guide's progress on her ordinary pfQuest quest node. State synchronization is therefore not implicated; 0.1.44 targets only native tooltip augmentation.
- 0.1.42-dev NPC click-targeting was implemented but not separately runtime-tested before being superseded by 0.1.43-dev, which carries the same targeting behavior plus Guide instruction removal. Validate both on 0.1.43 rather than returning to 0.1.42.
- 0.1.41-dev runtime PASS: user confirms Tourist hand-ins strike through the corresponding Guide instruction row, validating reverse-completion feedback on the working structural renderer. User also confirms NPC-name difficulty colours render correctly. FLIGHT remains explicitly untested.
- 0.1.41-dev runtime PASS for the structural Tourist presentation boundary: user reports the Tourist panel now works, and the Tourist can also see the Guide's shared quest objectives. This validates visible Tourist row presentation and confirms shared quest/objective state is reaching the Tourist under the dedicated prepared-model renderer. This report does not yet separately validate completion fade/removal, NPC-name difficulty colours, or FLIGHT automatic completion.
- 0.1.40-dev runtime FAIL: using the byte-for-byte 0.1.32 renderer still produced no Tourist instruction text; only the blank row/action control appeared. This demonstrates that restoring the old shared renderer alone is insufficient. 0.1.41-dev now moves Tourist presentation onto a prepared display model and dedicated row pool while leaving Guide rendering separate.
- 0.1.39-dev runtime FAIL with semantics intact: Guide accepting a quest displayed correctly in the Guide panel. The Tourist panel created the corresponding row/button shell but both instruction text and button caption were blank. When the Tourist handed in/completed the matching quest, the Guide row struck through normally. This confirms the instruction and reverse-completion pipelines are functioning while Tourist row text rendering remains broken. 0.1.40 replaces the entire renderer trio with the exact 0.1.32 implementation while leaving current data/protocol/transport behavior intact.
- 0.1.39-dev implemented / runtime pending: code history was traced from the last clearly healthy 0.1.30/0.1.32 panel state through the spam/discovery and flight changes. No direct panel-layout edit occurred in 0.1.31, 0.1.32 or 0.1.33. 0.1.39 therefore avoids another shared rewrite: Guide/disparity rendering uses the exact 0.1.32 row text behavior, while Tourist instruction text/strike are isolated onto direct main-window regions so they cannot depend on the zero-width marker anchor. The existing Tourist Done button remains on the existing row frame.
- 0.1.37-dev runtime FAIL: the broad direct-anchor rewrite regressed previously working Guide quest/instruction behavior. User reports quests in the Guide no longer work. 0.1.38-dev immediately reverts the shared row rewrite and restores the exact 0.1.36 row implementation; do not continue testing 0.1.37.
- 0.1.36-dev runtime FAIL / root cause narrowed to UI geometry: manual Tourist `Done` initially appeared to work, but when the Guide accepted two quests the Tourist box showed no corresponding instruction text while two `Done` buttons/row controls rendered displaced in the middle of the screen. When the Tourist accepted those two quests, the displaced controls/rows disappeared normally. This proves the ACCEPT records, synchronization, pending state, matching and consumption paths were correct; the remaining defect was row-region anchoring/presentation. 0.1.37-dev removes the intermediate child row frames and anchors marker/text/disparity/button regions directly to the main Guide/Tourist window.
- 0.1.35-dev runtime FAIL after initial rendering recovery: Gaia's Tourist rows became visible, but when she selected the matching flight, text disappeared from all entries while the row slots and `Done` buttons remained. This indicates the underlying pending rows survived but the shared instruction FontString render state was invalidated during completion/refresh. 0.1.36-dev replaced the dynamically re-anchored shared text region with fixed normal/disparity FontStrings and explicit Show/Hide state, but 0.1.36 still reproduced a broader geometry failure on new ACCEPT rows.
- 0.1.34-dev final pre-fix UI diagnostic: Gaia's Tourist row 1 was shown, alpha=1, `DIALOG` strata/frame level above parent, and contained `Fly to Ironforge, Dun Morogh`; parent showed 12 pending rows with expected height, but the box rendered visually empty. Coordinate probing returned nil on this 1.12 client and was not diagnostically useful. This isolated the defect to effective text rendering geometry. 0.1.35-dev removes the zero-width marker FontString from normal instruction-text anchoring; runtime retest pending.
- 0.1.34-dev Tourist row layering diagnostic: Gaia's Tourist parent frame is frame level 1, the populated row is frame level 2, and both are `DIALOG` strata. This rules out the obvious child-behind-parent frame-level failure. Next check effective row/fontstring screen geometry before changing rendering code.
- 0.1.34-dev Tourist row diagnostic: Gaia row 1 reports shown=true, alpha=1, and its text region contains `Fly to Ironforge, Dun Morogh`, while the Tourist window still appears visually empty. Combined with pending=12 and frame height ~=274, this proves row creation, row visibility state, text population, and parent layout all succeeded. Remaining defect is actual rendering geometry/layering on Gaia's client (for example child frame level/strata or region placement), not synchronization or reconciliation.
- 0.1.33-dev Tourist UI diagnostic: Gaia reports `GetTouristInstructions()` count=12, `pfQuest_GroupGuideTouristFrame:GetHeight()` ~=274 (exactly 34 + 12*20), and `IsShown()`=true while the Tourist box appears visually empty. This proves pending data, display-count layout, frame expansion, and parent-frame visibility are all working. The remaining defect is row-level rendering/visibility (child rows / fontstrings / buttons), not pairing, component sync, Tourist reconciliation, or parent window refresh.
- 0.1.33-dev flight root cause confirmed by Guide diagnostics: immediately after the reported flight test, Guide `guideActionSeq` remained 10 and the last durable Guide instruction was seq 10 `ACCEPT`; no FLIGHT record was committed. Therefore the 0.1.33 post-`TakeTaxiNode` callback did not reliably reach `Addon.HandleFlightAction`/`CreateGuideInstruction` after the Vanilla taxi transition. This is consistent with the 0.1.34-dev change that moves PFQG flight creation before calling the original `TakeTaxiNode`. Retest must use 0.1.34-dev on both clients; do not diagnose Tourist transport unless Guide actionSeq actually advances to a FLIGHT record.
- 0.1.33-dev Tourist diagnostic: Gaia reports remote instruction seq 10 is `ACCEPT`; local Tourist session baseline is 0; `GetTouristInstructions()` returns 10 pending instructions. Therefore Tourist filtering is not globally dropping instructions. The synced Guide instruction snapshot stops at cursor 10 and contains the pre-existing 10 records; the newly created flight instruction is absent from the Tourist snapshot. Next confirm the Guide's local `guideActionSeq`/last record after flight creation to determine whether the flight is local seq 11 and was lost/rejected in transit versus not actually appended.
- 0.1.33-dev Tourist diagnostic narrowed below transport: on Gaia, `GetPeer("Rewenga")` reports `compatible=true`; the remote quest state reports ready=true; the remote instructions snapshot exists with cursor=10. Thus peer discovery, session pairing, and receipt of component state are functioning. The missing visible flight/quest presentation is now suspected in Tourist-side record contents/filtering/presentation rather than Guide -> Tourist transport. Next inspect whether instruction seq 10 exists in the remote snapshot and whether `GetTouristInstructions()` filters it out relative to `joinBaseline`/consumed state.
- 0.1.33-dev sync diagnostic: on the Tourist client, `/pfqg status` reports `following Rewenga (paired)`. This proves the Tourist has received enough Guide session state to bind to the current Guide session. The remaining failure is therefore below discovery/session pairing: Guide quest state and the new FLIGHT instruction are not visible on the Tourist side, so distinguish missing quest/instruction component state from Tourist-side presentation/reconciliation before further taxi-specific changes.
- 0.1.33-dev runtime FAIL / asymmetrical synchronization: both real clients were confirmed on exact 0.1.33-dev. Guide-side flight capture worked and `Fly to <destination>` appeared locally in the Guide window, but the Tourist did not receive that flight instruction and also was not seeing the Guide's quest state. Because the Guide still recognized the Tourist strongly enough to create the instruction, this is not a simple protocol-version mismatch and not flight-specific; investigate Guide -> Tourist peer/state receive/recovery asymmetry. 0.1.34-dev has not yet been runtime-tested.
- 0.1.33-dev flightpath guidance IMPLEMENTED / RUNTIME PENDING: Guide taxi selection now creates a durable `FLIGHT` instruction with the selected destination; Tourist selection of the same destination auto-completes it through the existing completion pipeline. Protocol is v3, so both clients must update. No in-game result has yet been reported for this delta.
- GH5 remains PENDING by availability, not failure: the user has not yet spent enough time questing in the world on a suitable multi-objective quest to exercise objective-specific held-node filtering. Test only when such a quest arises naturally; do not block unrelated work on it.
- 0.1.32-dev GH6 PASS: user reports held guidance releases correctly when the final relevant participant finishes the held objective; no lingering PFQGROUP guidance/native-row hold remains after completion.
- 0.1.32-dev focused matrix update: user reports C1-C5 all PASS, R8-R10 all PASS, GH1 PASS, GH3 PASS, GH7 PASS, and GH8 PASS. GH2 is removed from the active matrix by design/user direction. Earlier 0.1.28 runtime evidence already demonstrated GH4 held-node tooltip behavior on `Moontouched Wildkin`, so GH4 is reconciled to PASS. Remaining explicit Group Hold checks are GH5, GH6, and GH9 (GH9 remains skip-eligible).
- 0.1.32-dev attribution correction: the SoloCraft `spam detected` warnings were ultimately traced by the user to a combination of Quest Tracker Sharing and WanderingGaia, both now fixed. PFQG was not the demonstrated root cause of the server warning. Keep the 0.1.31/0.1.32 transport reductions as valid efficiency improvements, but do not cite the warning as proof of a PFQG transport defect.
- 0.1.32-dev native-only tracker ownership remains PENDING: the user has not yet naturally encountered the post-turn-in/local-quest-absent scenario needed to verify that PFQG never synthesizes a replacement tracker quest.
- 0.1.32-dev `Strange Sources` retest remains BLOCKED BY AVAILABILITY: that exploration objective cannot be recompleted on the current characters, so the 0.1.29 area-trigger/map visibility correction may remain unverified for some time rather than blocking unrelated validation.
- 0.1.32-dev legacy Guide completion observation — PARTIAL PASS: after continued use the user has not seen the prior mass/replayed strike-through/cross-out behavior recur. This is good runtime evidence that replay/permanence is fixed, but it is not the exact leave/rejoin + reload/relog permanence sequence, so retain that narrower check as optional follow-up rather than an active blocker.
- 0.1.32-dev Group Progress regression — PASS by user report: ordinary shared objective progress, including the current binary/no-quest-peer behavior represented by the immediate regression check, is working cleanly.
- 0.1.32-dev transport observation: user initially reported the joiner-announced discovery change felt "much better" in the SoloCraft raid/bot scenario, but later identified Quest Tracker Sharing + WanderingGaia as the actual sources of the server `spam detected` warnings. Treat 0.1.32 as a transport-efficiency improvement, not as the proven fix for that server warning.
- 0.1.32-dev transport redesign awaiting runtime: user requested joiner-announced discovery after identifying that established PFQG clients should remain silent while non-PFQG raid members/bots join. `7fb8de8036fc56674fe382b2af6357ef4a59205d` now keys discovery to the local client's own group/subgroup context (`GROUP:1` for party / raid subgroup number for raid), sends HELLO only when that context changes, adds logical targeting to HELLO replies, and suppresses ordinary state deltas when no compatible PFQG peer is known. This supersedes 0.1.31's broader "effective subgroup roster changed -> HELLO" trigger. Runtime spam/discovery validation pending.
- 0.1.30-dev transport inefficiency observation (server-warning attribution later cleared): static trace found multiplicative roster-sync traffic — every `PARTY_MEMBERS_CHANGED` unconditionally sent HELLO + a chunked full snapshot, and every received HELLO unconditionally sent another chunked full snapshot. 0.1.31/0.1.32 removed this unnecessary traffic. However, the user's later diagnosis traced the actual SoloCraft `spam detected` warnings to Quest Tracker Sharing + WanderingGaia, so do not classify PFQG as the demonstrated source of those warnings.
- 0.1.30-dev design correction awaiting runtime: user rejected PFQG-created fallback quest blocks after observing the historical `Are We There, Yeti?` hold. Product rule is now that PFQG may augment native pfQuest tracker rows but must not create its own replacement quest in the tracker once pfQuest has no native row. The Guide is responsible for deciding whether to delay turn-in. Map/minimap group-hold guidance remains unchanged for now. 0.1.29's synthetic historical tracker block is therefore superseded behavior, not a target to preserve.
- 0.1.29-dev runtime: `Are We There, Yeti?` supplemental historical hold behaves as intended. The Guide confirmed they previously had/tracked and completed the quest earlier in the same Guide session while Gaiallmighty remained incomplete. With the local quest now absent, PFQG retains Gaia's unfinished `0/2` objective and renders the local self row as grey `--`, matching the intended GH8 historical-hold semantics rather than remote-only quest injection. This is partial GH8 evidence; no claim is made yet for final release, map/minimap retention, or no-falsification beyond the observed tracker state.
- 0.1.29-dev performance observation — PINNED / UNATTRIBUTED: user reports raid play felt shaky while grouped with one same-subgroup PFQG peer (Gaia) and both were progressing `Echoes of War` (quest 9033), but several other addons were updated recently and raid FPS had previously been good. Do not treat PFQG as the likely cause or block current PFQG validation on this observation. If it recurs with stronger PFQG correlation, isolate with PFQGROUP node-count/node-removal A-B testing first, then inspect tracker relayout / PARTY roster-sync frequency.
- 0.1.28-dev `Strange Sources` diagnostic: while the held exploration objective remained in the Guide tracker, the exact-node probe returned `node=false`, with local pfQuest `showcluster=0` and `showclustermini=0`. Source inspection confirms PFQG was marking all supplemental nodes `cluster=true`; pfQuest hides such nodes under those settings. Because the exact coordinate probe may also miss a node stored at a database-version-specific coordinate, 0.1.29 fixes the demonstrated display-flag misuse without claiming an area-trigger insertion bug until retested.
- 0.1.28-dev runtime: the Tourist-complete / Guide-incomplete hold now works for `Moontouched Wildkin` / `Moontouched Feather`: the completed Tourist continues to see the Guide's unfinished objective on the minimap, and hovering the retained PFQGROUP node shows both Tourist and Guide progress. This runtime-validates the 0.1.28 relevance fix for that item-source case and provides a GH4 group-aware-tooltip PASS for that held node. In the mirror Guide-complete / Tourist-incomplete case on `Strange Sources` (quest 4842, exploration/area-trigger objective), the Guide's quest tracker correctly retained the Tourist's unfinished objective, but no retained map marker was visible. pfQuest data has exactly one area-trigger source for quest 4842 (trigger 2327 at Winterspring 59.8, 74.2), so the tracker hold is valid and the remaining failure is isolated to PFQGROUP area-trigger map insertion/visibility. Do not generalize GH3 to PASS until this is resolved.
- 0.1.27-dev runtime FAIL (general GH path; exact numbered GH provenance not claimed): with the Tourist locally done on a shared objective while the Guide remained incomplete, the Tourist did not retain/show the Guide's still-needed objective. Source inspection found the hold builder required same-session `localTracked` history even when the Tourist still had the equivalent quest locally; this history can be absent if the live Guide/Tourist session wakes after pfQuest has already removed the completed tracker row. 0.1.28-dev / ff54f9711c5a065141023e30293a3c6e97ccba66 relaxes only that relevance gate and awaits retest.
- 0.1.27-dev runtime: in a 10-player raid, the persisted Guide/Tourist session remained intact while the Tourist was outside the Guide's current raid subgroup. The Guide had no live peer record, so the Guide window and remote tracker rows correctly went dormant; moving the Tourist back into the Guide's subgroup immediately restored live PFQG behavior. This validates the current party1-party4 participation boundary and a dormant/resume path, but does not by itself complete GH7 because no held-objective offline durability or premature-release behavior was exercised.
- 0.1.27-dev / 1f03df4124f2e28e63c6d1ed6cab3204665a0fb5 screenshot/runtime: completed binary objective presentation passes the intended visual migration. The native inline/tick-cross treatment is replaced by an objective heading plus per-player rows; self and the matched peer are both shown at `1/1`, and the user reports the result is clean. This does not yet validate incomplete `0/1`, no-quest filtering, or live `0/1 -> 1/1` update.
- 0.1.26-dev runtime: Guide legacy rows clear correctly again after the Tourist rejoins and synchronization settles, but the result is not permanent; leaving/rejoining makes the historical list replay its strike/fade removal. The held-objective tracker row treatment looks correct and was explicitly preferred by the user. 0.1.27-dev / 1f03df4124f2e28e63c6d1ed6cab3204665a0fb5 persists recovered legacy completion and generalizes that clean row treatment to all binary objectives.
- 0.1.25-dev user runtime screenshot after the persisted Tourist rejoined demonstrated two regressions: the Guide window remained populated with a large historical instruction backlog, and a locally-complete held binary objective in the top-left tracker rendered as local tick + Paladin class icon + remote cross. The Tourist had not yet been updated to the latest addon build, but protocol remained v2 and the older build was still wire-compatible, so neither behavior is being attributed to a protocol-version mismatch. 0.1.26-dev / 4b1b1bb17b0cfbfc9e1f9864e343745f351454fa targets both observed failures; no runtime PASS is claimed yet.
- 0.1.25-dev / e168712cccb9959646491073393df1639e00a5d5 implementation checkpoint: Phase-2 persisted last-known relevant participant quest state and PFQG supplemental group-hold tracker/world-map/minimap/tooltips are committed. Static ownership guards confirm protocol remains v2, schema is 3, synchronized components remain exactly session/quests/instructions, the group-hold block does not call SearchQuestID, does not write local questState completion/progress, and uses only the PFQGROUP map namespace. This is not an in-game PASS.
- 0.1.24-dev / 01ec7eec406ecf3a9960149aac80dbbdcb653deb implementation checkpoint: dormant Guide UI/instruction suppression and schema-2 durable Guide eligibility/ack/completion persistence are committed. Protocol remains v2. This is code/static review only; no new in-game PASS is claimed yet. The canonical vendored Lua 5.0.3 checker is not mounted in the current executable environment and the container cannot resolve GitHub, so no canonical full-file compiler pass was run in this chat.
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
11. **UNTESTED — Binary objective at 0/1 after 0.1.27 redesign.** Objective line should be heading-only; self row should show class/name plus coloured `0/1`. The prior PASS covered the retired incomplete-symbol layout.
12. **PASS — Binary objective at completed `1/1` after 0.1.27 redesign.** Screenshot shows heading-only objective presentation with self and matched-peer class/name rows at `1/1`, and no tick/cross/status column. Live transition into this state remains covered separately by item 14.
13. **UNTESTED — Binary quest nobody else has after 0.1.27 redesign.** Only the self row should appear; no remote player row should be fabricated. The prior PASS covered the retired symbol layout.
14. **UNTESTED — Binary state changes live.** Incomplete -> complete should update without reload.
15. **UNTESTED — Normal count objective after redesign.** Numeric progress must remain numeric, but the objective line now shows only the objective name and the local `PlayerName: current/required` row appears beneath it. The prior PASS covered the pre-0.1.22 layout and does not validate this redesign.
16. **UNTESTED — Multiple objectives on one quest.** Binary/count objectives should coexist without row collisions.
17. **PASS — Collapse/expand a tracked quest.** PFQG regions hide/show cleanly without duplicated icons.
18. **UNTESTED — Tracker refresh/update.** No duplicated rows, drifting icons, or stale text during repeated progress.
19. **UNTESTED — Switch pfQuest tracker mode away and back.** PFQG overlays should not remain on unrelated tracker content.

#### C. Remote Group Progress
20. **UNTESTED — Peer has same binary quest, incomplete after 0.1.27 redesign.** Peer row should follow self with class icon/name and coloured `0/1`; no separate cross/status column should exist. The prior PASS covered the retired icon-strip layout.
21. **UNTESTED — Peer completes that binary objective.** Remote row should update to `1/1` without reload.
22. **UNTESTED — Peer does not have the quest after 0.1.27 redesign.** No row should appear for that peer. The prior PASS covered the retired icon-strip layout.
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

C1. **PASS — Count objective heading/self row.** User reports the count-objective presentation behaves correctly: the objective heading is separated from the local player's count row.
C2. **PASS — Self class/count colours.** User reports the local class/name and numeric progress colouring behave correctly.
C3. **PASS — Remote class/count colours.** User reports compatible peer count rows use the expected class/progress colouring.
C4. **PASS — Count progress live update.** User reports self/peer numeric counts update cleanly without duplicate/stale rows or overlap.
C5. **PASS — Missing equivalent remote objective.** User reports the count-objective edge behavior is clean, including the missing-equivalent-objective presentation.

### Supplemental Protocol-v2 Reverse-Completion Tests

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
R8. **PASS — Tourist manual Done for an already-completed stale instruction.** User reports manual Done behaves correctly with the normal completion/removal presentation.
R9. **PASS — Manual Done feeds back to Guide.** User reports Tourist Done correctly feeds completion back to the Guide and does not replay improperly.
R10. **PASS — Instruction NPC-name presentation.** User reports the Guide/Tourist instruction NPC presentation behaves correctly, including the current accept/turn-in row formatting.


### Focused in-game group-hold matrix


### Focused in-game group-hold matrix — awaiting user runtime results
Pre-matrix held-native presentation regression: **PASS on 0.1.26-dev** by user observation; the objective uses the preferred per-player row treatment rather than the old tick/class-icon/cross strip. Current focused Group Hold status is recorded below; GH2 has been removed from the active matrix by design.
GH1. **PASS — Count objective local completion hold.** User reports the local-completes-first count-objective hold behaves correctly while the relevant participant remains incomplete.
GH3. **PASS — World-map/minimap held nodes.** User reports relevant PFQGROUP held-objective nodes persist correctly on map/minimap after local completion without resurrecting quest start/end state.
GH4. **PASS — Group-aware held tooltip.** Reconciled from earlier 0.1.28 user runtime evidence on `Moontouched Wildkin`: hovering the retained PFQGROUP node showed both Tourist and Guide progress correctly.
GH5. **UNTESTED — Multi-objective filtering.** On a quest with multiple objectives, complete one locally while another participant still needs only that objective. Verify PFQG retains only objective sources still needed by somebody relevant and does not blindly restore all quest nodes.
GH6. **PASS — Completion release.** User reports that when the final relevant participant finishes the held objective, retained PFQGROUP map/minimap guidance and native-row hold presentation release cleanly without altering local quest/pfQuest state.
GH7. **PASS — Offline unfinished durability + dormancy.** User reports the held-objective state survives the relevant leave/disconnect/rejoin behavior correctly without premature release.
GH8. **PASS — Local completion/removal historical hold without synthetic tracker state.** User reports the post-completion/turn-in behavior is correct under the current native-only tracker rule: no fake local tracker quest/personal quest state is recreated while non-tracker hold guidance remains safe.
GH9. **UNTESTED / SKIP-eligible — Ambiguous complex objective mapping.** If a held objective has multiple database sources that cannot be matched safely by localized objective text, verify PFQG prefers tracker-only guidance over showing unrelated map nodes. The deferred Mrs Dalson's Diary / Outhouse / Locked Cabinet chain is not a test target for this case.

### Next Implementation / Runtime Sequence
1. Runtime-check 0.1.51-dev single-item/object alerts: brown bag artwork; dinger still once on the Tourist for a live Guide 0/1 -> 1/1 item/object; Guide row remains only while at least one matching Tourist is incomplete; Tourist row disappears when that Tourist completes; completing a later second 1/1 objective must not resurrect the first completed row.
2. Also verify reload/resync remains silent and that a 1/1 monster kill plus any item/object objective requiring more than one still produce no alert row/sound.
3. Runtime-check the inherited 0.1.50 panel geometry: no scrollbar when content fits; overflow scrollbar inside the border and clear of Show Hidden / resize grip; compact `-` stays adjacent to instruction text across width resize.
4. If those focused checks pass, resume the remaining combined Phase-5 checks: 15 pt ACCEPT/TURNIN marker versus 12 pt ordinary text; persisted dimensions; shrinking without content auto-grow; mouse-wheel vertical scrolling; no horizontal scrolling; width-aware ellipsis; exact raw-name NPC targeting; and zero PFQG Lua errors. FLIGHT matching/completion already passed on 0.1.49.
5. Continue the carried Guide removal-semantics check, ordinary completion, GH5 when a suitable quest arises, and GH9 only if naturally encountered. Keep the Mrs Dalson's Diary / Outhouse / Locked Cabinet anomaly deferred.

## Planned / Next Work
1. **Phase-5 chained row layout — IMPLEMENTED / UNTESTED in 0.1.52-dev:** validate leftmost remove/Done, marker, optional abbreviated/truncated NPC, separator and quest priority on both panels; verify FLIGHT has no NPC segment and disparity controls remain independent.
2. **Phase-5 panel usability refinement:** Passes 1-3 remain implemented; 0.1.50-dev adds the focused runtime-driven layout correction for scrollbar visibility/geometry/footer clearance and compact Guide removal control. Runtime is pending on the new delta.
3. Retest the 0.1.50 layout correction first, then finish the combined Passes 1-3 runtime checklist before any further panel refinement.
4. Runtime-test the shared single-item/object acquisition alert end-to-end on 0.1.51, including pfQuest brown `cluster_item` bag artwork, sound-on-live-delta, Guide X/check progression while somebody still needs it, immediate row removal when locally/all complete, reload/resync silence, and 1/1-kill/multi-count exclusion.
5. Preserve the stable bidirectional Group Progress tracker/tooltips and the prepared Tourist display-model -> renderer boundary; objective-alert rows remain a separate Phase-5 row pool.
6. Runtime-test carried NPC click-targeting on both Guide and Tourist instruction rows as part of the post-Pass-3 panel check.
7. Runtime-test Guide `-` as the same authoritative instruction cancellation. FLIGHT rendering/matching already passed on 0.1.49; treat 0.1.50 as inherited behavior unless a regression appears.
8. Continue only remaining relevant gaps: GH5 when available, GH9 if naturally encountered, and any current protocol-v3 regression that appears during normal play.
9. Fix only demonstrated defects, bumping the dev version for every addon-affecting revision.
10. Keep the linked Mrs Dalson's Diary / Outhouse / Locked Cabinet anomaly deferred.
11. After a known-good runtime state exists, review release/promotion readiness separately; do not treat development checks as a runtime test.

## Deferred / Out of Scope
- Raid-FPS investigation is pinned unless the issue recurs with a stronger PFQG correlation; current observation is confounded by several recently updated addons.
- New feature work beyond the currently agreed post-Phase-6 tracker/Guide refinements.
- Release/promotion to main before broad runtime validation is complete or any validation debt is explicitly accepted.
- dev_rulebook.md changes.
- Investigation/fix for the linked `Mrs Dalson's Diary`, `Outhouse`, and `Locked Cabinet` tracking anomaly; user reports the behavior is already incorrect in pfQuest itself as well as PFQG, so handle separately from current tracker presentation work.

## Release / Promotion Notes
- dev_rulebook.md and DEV_PROGRESS.md must never be present on main.
- main remains the bootstrap baseline only.
- No validation debt has been accepted for release.
- External/runtime prerequisite: pfQuest.

### Latest user runtime observations — 0.1.52-dev
- PASS (user report): brown pfQuest bag icon; single-item/object alert row removal; a later separate 1/1 objective does not resurrect the earlier completed row; reload/resync produced no observed issues.
- NOT YET EXERCISED: overflow scrollbar geometry.
- New observation/question: exploration objective `Explore the Hidden Chamber` from `The Hidden Chamber` did not appear in the single-objective alert. Current eligibility deliberately filters to required=1 and type `item` or `object`; exploration is excluded. No change approved yet.
- New observed tooltip duplication: pfQuest's original map-node objective/progress line overlaps semantically with PFQG's Group Progress section. Await user's preferred presentation before changing it.
- Phase-5 chained layout controls, targeting, resizing and completion strike remain unverified specifically on 0.1.52.

### Agreed Next Feature Contract — Gossip Reminder (implemented 0.1.53-dev; untested)
- Scope: lightweight reminder that the Guide wants the Tourist to talk to an NPC, NOT a full quest handholding or dialogue-option/quest-completion tracker.
- While a Guide has at least one active same-session Tourist, opening an NPC gossip window should create an instruction through the existing Phase 4b owner. Do not generate while Guide is dormant; do not create another pending same-NPC gossip instruction merely because that conversation is reopened.
- Guide row: `[-] [gossip speech-bubble icon] NPC_Name`; Tourist row: `[Done] [gossip speech-bubble icon] NPC_Name`. Follow the 0.1.52 chained row contract, without fabricating quest title or separator. Preserve raw NPC identity for matching/targeting.
- Tourist opens gossip with the matching NPC -> automatically consume the earliest matching pending gossip instruction; Tourist manual Done must also work. Reuse the existing durable Guide/Tourist acknowledgement, completion strike/fade/removal, session and synchronization ownership.
- Do not track which gossip menu choice was made and do not claim the underlying quest objective was completed. Inspect Vanilla 1.12.1 event/API limits and protocol v3 compatibility before implementing; bump protocol version only if the wire requires it.
- Implemented on dev in 0.1.53-dev: GOSSIP_SHOW captures NPC name via UnitName npc/target with visible gossip-frame text fallback; Phase 4b creates a session-owned GOSSIP instruction only with active Tourists and deduplicates still-pending same-NPC records. Tourist opening a same-name gossip window consumes earliest matching pending step using normal durable Done/ack flow. Phase 5 renders a native speech-bubble texture plus clickable raw NPC name without invented quest title/separator. Protocol bumped v3 -> v4 for the new `G` code; SavedVariables schema remains 3. Both clients must upgrade. No gossip-option/quest-completion tracking.
- Checked by code inspection and targeted source assertions only; canonical Lua 5.0.3 compiler not run (GitHub connector has repository access but no checkout/executable checker available). No in-game test yet.

### Approved Investigation / Design Boundaries — Not Yet Implemented
- Objective alerts: investigate `The Hidden Chamber` / `Explore the Hidden Chamber` and `The Platinum Discs` in Uldaman. Current eligible alert predicate requires `required == 1` and objective type `item` or `object`. Inspect real quest/objective types and progression before adding exploration/gossip/object events; use semantic iconography, not the loot bag for every event. No blanket expansion has been implemented.
- Group Hold tracker expansion: user wants native pfQuest tracker quests to stay expanded after local objective completion while any relevant Guide/Tourist still needs an objective, and release automatic-collapse hold when all relevant participants finish. Respect manual user collapse. Inspect pfQuest automatic-collapse mechanism and use a narrow PFQG-owned integration without modifying pfQuest source unless explicitly approved. Do not fake local incompletion or synthesize a quest state.
- Tooltip: map-node tooltip duplicates pfQuest's native objective/progress line and PFQG's added Group Progress section. User has not yet chosen desired retained text, so wait for formatting approval before changing it.

## Exact Next Step
Runtime-test 0.1.53-dev on **both** Guide and Tourist (protocol v4): (1) Guide gossip with an active paired Tourist creates exactly one speech-bubble/NPC row; reopening same NPC does not duplicate while pending; (2) dormant Guide creates none; (3) Tourist's GOSSIP_SHOW on the same NPC auto-consumes earliest pending gossip, with Guide completion acknowledgement and strike/fade/removal; (4) Tourist manual Done works and remains durable over reload/resync; (5) clicking displayed/abbreviated NPC name still targets the full raw name, and chained row geometry/ellipsis remain correct; (6) different NPCs, flight and ACCEPT/TURNIN still behave normally, and no Lua errors occur. Gossip is a talk reminder only, never a quest-completion claim.
Then investigate Hidden Chamber and Platinum Discs objective classification; separately design group-held pfQuest tracker auto-collapse suppression that respects manual collapse. Await user tooltip formatting. Continue inherited 0.1.52 Phase-5 resizing/scroll testing. Do not promote to main without validation.