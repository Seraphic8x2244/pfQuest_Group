# Development Progress

## Current
- Branch: dev.
- Version: 0.1.4-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: 84fa3c77e327407a066fa1d9c3a5e7d41f7e89d5 — Phase 4b Guide/Tourist instruction behaviour.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None; main is still exactly repository bootstrap commit 4c5c63f074923266566c36c51ce2718d0060166f and is not a runtime release.
- Goal: Implement the agreed v1 addon across staged development chats, then perform the first broad in-game test on the integrated Phase 6 build.
- Current scope boundary: Phases 1–4b are complete. Phase 5 is split into Phase 5a (Guide/Tourist instruction-window presentation) and Phase 5b (quest-disparity presentation/controls). Phase 5a is next; Phase 5b must not be started in the same development chat unless Phase 5a has first been cleanly checkpointed. No intermediate in-game testing is planned before Phase 6.

## Current Design / Development Contract

### Workflow / Branch Rules
- Active addon development occurs on dev.
- dev_rulebook.md is authoritative and read-only during ordinary addon work.
- DEV_PROGRESS.md is the sole live development/handoff source.
- dev_rulebook.md and DEV_PROGRESS.md are development-only and must never be promoted to or committed on main.
- main is reserved for stable repository/release content.
- pfQuest_Group.toc is the addon version source of truth.

### Architecture / Ownership
- Target: World of Warcraft 1.12.1 / Interface 11200 / Lua 5.0.3.
- Project is a separate companion addon named pfQuest_Group.
- pfQuest is the authoritative local quest/tracker source; do not modify pfQuest source files directly for normal implementation.
- pfQuest_Group.toc hard-depends on pfQuest.
- Saved state is per-character in pfQuest_GroupDB.
- Group Progress and Guide/Tourist are separate systems; Group Progress works without Guide/Tourist mode.
- Keep the implementation small and in one main Lua file unless later implementation pressure justifies a deliberate split.
- Guide/Tourist mode/session ownership remains the Phase 1 session component; Phase 4b did not add a parallel session state machine.

### Foundation / Protocol
- Protocol prefix: PFQGROUP; protocol version: 1; SavedVariables schema: 1.
- Only actual current party members participate in transport/discovery; discovery scans party1 through party4. Remote peer state is ephemeral and removed when that player leaves the party.
- Transport uses Vanilla SendAddonMessage / CHAT_MSG_ADDON over PARTY and targeted WHISPER only.
- Wire message types remain HELLO (H), full-state request (R), full snapshot (F) and component delta (D).
- State synchronization remains component-based through RegisterStateComponent, SendDelta and RequestFullSync.
- Built-in synchronized components are session, quests and instructions.
- Phase 4b adds the instructions component without changing the protocol version or adding a new top-level wire message type; peers that do not know the component ignore it through the existing component registry.

### Quest-State Engine
- Local quest state is normalized from the Vanilla quest log while reusing pfQuest compatibility/data ownership.
- Quest identity uses numeric questID when resolvable; title is the fallback. Later title-to-ID resolution migrates identity without a false accept/remove pair.
- Normalized quests carry title, completion state and normalized objectives.
- Event-driven scans emit LOCAL_QUEST_ACTION with ACCEPT, PROGRESS, TURNIN or REMOVE.
- Accept/turn-in actions carry NPC ID/name context when resolvable.
- Quest state is the quests component with revisioned full/delta synchronization and gap recovery.
- Remote quest state is invalidated on peer restart, incompatibility and party departure.

### Group Quest Progress
- Phase 3 post-processes pfQuest's existing tracker; pfQuest source is not modified.
- Only current compatible party peers are displayed, in party-slot order.
- Numeric questID is matched first, title fallback second.
- Binary objectives append class icon plus check/cross status per compatible peer.
- Count objectives add one class-icon/name/progress row per compatible peer; a missing matching count objective displays --.
- Group UI regions are reused/hidden as peers change; tracker dimensions are recalculated.
- Group Progress remains independent of Guide/Tourist mode.

### Guide / Tourist Session Foundation
- Modes are Off, Guide and Tourist.
- Commands are /pfqgroup off, /pfqgroup guide, /pfqgroup tourist <player>, /pfqgroup status; /pfqg is an alias.
- Tourist mode follows one specific other player and preserves that target through temporary absence.
- Entering Guide from another mode creates a new Guide session id and sets guideActionSeq to 0. Remaining in the same Guide mode preserves both.
- Reload/relog preserves an active Guide session id and guideActionSeq through pfQuest_GroupDB.session.
- Turning Guide Off clears the Guide session; later re-entering Guide creates a new session.
- guideActionSeq is monotonic within the active Guide session and increments only for local ACCEPT and TURNIN actions.
- A Tourist binds when the selected compatible peer advertises Guide mode with a Guide session id, recording that session id and the Guide's current guideActionSeq as joinBaseline.
- joinBaseline remains fixed within one Guide session. A different Guide session id causes rebind and a fresh baseline.
- Temporary Guide disappearance, party loss, peer restart or missing remote session state does not by itself clear the Tourist's saved target/binding/baseline.
- An explicitly advertised non-Guide state clears only the Tourist's active binding/baseline, leaving Tourist mode and guideName so it can pair later.
- Turning Tourist Off clears target, binding and baseline.
- hiddenDisparities remains reserved for Phase 5.

### Guide / Tourist Instruction Behaviour — Phase 4b Implemented
- Guide ACCEPT and TURNIN actions now create ordered instruction records using the existing guideActionSeq as the instruction sequence number.
- Instruction records carry action type plus quest ID/title and NPC ID/name fallback context when available.
- The active Guide instruction log is persisted in pfQuest_GroupDB.instructions and is scoped to the active Guide session id. Leaving that Guide session clears the old Guide log.
- The instructions state component provides full snapshots and per-action deltas through the existing component transport.
- Remote instruction state is scoped by Guide session id and sequence cursor. Peer restart/incompatibility/non-Guide state invalidates the peer's remote instruction cache without creating a second session owner.
- Duplicate/stale instruction deltas at or below the current remote cursor are ignored.
- A forward sequence gap, missing expected record, or delta for an unestablished session requests the existing full-state resync path. A first sequence-1 delta may initialize an empty remote instruction stream when the matching Guide session is already known.
- A stale full instruction snapshot cannot roll an established same-session cursor backward.
- Tourist pending instructions are derived only from the selected paired Guide and only for records with seq > joinBaseline. Records at or before joinBaseline are never replayed.
- Tourist consumption is persisted per paired Guide session as consumed instruction sequence numbers, so full resync/reload does not replay already completed instructions.
- A matching local Tourist ACCEPT/TURNIN consumes the earliest matching pending instruction. Numeric questID is authoritative when both sides have one; title is the fallback.
- New Guide-session pairing clears the previous Tourist consumed/pending instruction state and starts from the new joinBaseline.
- Public behaviour/state hooks for later Phase 5 presentation are Addon.GetGuideInstructions(), Addon.GetTouristInstructions(), GUIDE_INSTRUCTION_CREATED, GUIDE_INSTRUCTIONS_CHANGED, TOURIST_INSTRUCTION_COMPLETED and TOURIST_INSTRUCTIONS_CHANGED.
- Phase 4b adds no Guide/Tourist window, Blizzard !/? presentation, strike-through/fade, disparity rows, hide controls or Show Hidden.

### Phase 5 Presentation Boundary / Split
- Phase 5 owns all Guide/Tourist presentation and is deliberately split into two coding phases so instruction presentation and disparity behaviour can be reviewed/checkpointed independently.
- Phase 5a — Guide/Tourist instruction-window presentation: implement the compact movable Guide/Tourist window, render Guide/Tourist instruction rows using Blizzard-style yellow !/? markers, consume the existing Phase 4b instruction state/events, and implement Tourist completion strike-through/fade/removal presentation. Do not implement disparity rows, hidden disparity state/controls or Show Hidden in Phase 5a.
- Phase 5b — Quest-disparity presentation/controls: build on the completed Phase 5a window and existing Phase 2 remote quest state to show Guide missing-quest disparity rows, plus hidden disparity handling and Show Hidden. Current quest disparity is separate from the instruction baseline and may show quests accepted before a Tourist joined.
- Both Phase 5a and 5b are presentation/disparity work only. They must consume the Phase 4a/4b state and events rather than introducing another Guide/Tourist session or instruction owner.
- Phase 5a must end in a valid self-contained UI state even if Phase 5b does not exist yet.

## Recent Relevant Commits
- 4c5c63f074923266566c36c51ce2718d0060166f — initialize main with repository README only.
- 746265a4561fedcb924bba729aef22458984d994 — implement Phase 1 foundation/protocol.
- d83669c6a476a5a7521a3308102a267c2e79a668 — implement Phase 2 quest-state engine.
- e3b988309054eb86a3ad39953bf5a39332168e83 — implement Phase 3 Group Progress UI.
- 76fcb2e3950325fedc095dabf11a4e623d594b44 — split Phase 4 into 4a and 4b.
- b7655c8bd7d7108b38ad19f271a456f9bcad78d4 — implement Phase 4a Guide/Tourist session foundation.
- 91f8519aa104f69bb618b98c39532ad89348cd23 — checkpoint Phase 4a handoff.
- 84fa3c77e327407a066fa1d9c3a5e7d41f7e89d5 — implement Phase 4b Guide/Tourist instruction behaviour.

## Completed / User-Verified
- Repository and feature/design direction were confirmed by the user.
- User explicitly requires dev_rulebook.md and DEV_PROGRESS.md to remain off main.
- No runtime addon behaviour has been user-tested yet.

## Implemented / Awaiting Runtime Test
- Phase 1 addon skeleton, party peer lifecycle, protocol v1, chunked full/delta component synchronization and persistent local session state.
- Phase 2 local/remote quest-state engine, quest action detection and NPC context fallback.
- Phase 3 Group Progress tracker integration for compatible party peers.
- Phase 4a Off/Guide/Tourist commands, Guide session lifecycle, automatic pairing and fixed Tourist join baseline.
- Phase 4b Guide ACCEPT/TURNIN instruction creation, persistence, component synchronization, Tourist baseline filtering, matching/consumption, and duplicate/stale/gap recovery.
- Phase 5a and Phase 5b remain unimplemented; Phase 5a is the next coding phase.

## Static / Automated Checks

### Phase 4b exact implementation state
Exact implementation commit: 84fa3c77e327407a066fa1d9c3a5e7d41f7e89d5.
- Exact pfQuest_Group.lua Git blob: db73598f637d3bf8cf2641c0ea2b9287f9aab861.
- Exact pfQuest_Group.toc Git blob: d7be058f982dbb65abe9399d2572862da7721f13.
- TOC version: 0.1.4-dev.
- Pre-write handoff verification: dev was exactly 91f8519aa104f69bb618b98c39532ad89348cd23 and had no newer branch movement.
- Stable-baseline verification: main was still exactly 4c5c63f074923266566c36c51ce2718d0060166f.
- Implementation commit scope check: passed. Relative to the Phase 4a handoff it changes only pfQuest_Group.lua and pfQuest_Group.toc. dev_rulebook.md and DEV_PROGRESS.md are unchanged by the addon-affecting commit.
- Version check: passed; 0.1.3-dev -> 0.1.4-dev.
- Protocol/ownership check: passed. PFQGROUP protocol version remains 1; top-level wire message types remain H/R/F/D; there is exactly one session component registration, one quests component registration, one instructions component registration and one Addon.SetMode definition.
- Phase boundary/UI check: passed. CreateFrame, CreateFontString and CreateTexture call counts remain 1, 2 and 2 respectively, unchanged from Phase 4a, so Phase 4b adds no Phase 5 UI regions.
- Static later-Lua/API scan: passed for the exact committed source; no string.match, string.gmatch, table.unpack, select(, RegisterAddonMessagePrefix or modern C_ API tokens are present.
- Top-level local-declaration line count: 130 versus 116 before Phase 4b, below Lua 5.0.3's 200-local top-level chunk limit. This is a structural count, not a compiler proof.
- Focused mocked Phase 4b instruction harness: passed wire round-trip, Guide sequence/instruction creation, joinBaseline filtering, persisted Tourist consumption, duplicate suppression, gap-triggered full resync, contiguous-delta acceptance, stale-full rejection, new-session consumption reset and same-session Guide-log persistence.
- The focused harness passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. It validates the focused Phase 4b logic only; it is not the canonical Lua 5.0.3 compiler check and not an in-game test.

### Checks not actually runnable
- Exact full-file texluac parser smoke check for the Phase 4b Git blob: not run in the executable shell. Repository content is available through the GitHub connector, but the connector-backed file is not materialized into the shell and the shell has no direct GitHub network access.
- Canonical Lua 5.0.3 compiler check: not run / unavailable for the exact Phase 4b blob. The executable environment has gcc and Lua 5.3.6 texlua/texluac, but no materialized canonical tools/lua50 checker/source; no system Lua 5.0 compiler is present.
- No in-game testing was performed, by plan.

### Earlier validation baseline
- Phase 3's exact runtime previously passed the available Lua 5.3.6 full-file parser smoke check, structural/static scans and mocked tracker harness documented at its checkpoint.
- Phase 4a's focused session harness passed under Lua 5.3.6 as documented at its checkpoint.
- The canonical Lua 5.0.3 compiler pass remains outstanding from Phase 3 onward.

## Current Issues
- Validation debt: the exact current Phase 4b runtime still needs the canonical Lua 5.0.3 compiler pass when the checker and addon source are executable in the same environment.
- Exact current full-file Lua 5.3.6 parser smoke remains unavailable because connector repository bytes are not materialized into the executable shell.
- No known Phase 4b implementation defect is recorded at this checkpoint.

## Testing

### Last Runtime Test
- Version/commit: None.
- Passed: None.
- Failed: None.
- Not tested: all Phase 1–4b in-game behaviour.

### Next Runtime Test
- Per the agreed staged plan, no intermediate in-game test is scheduled.
- The first broad in-game test remains the integrated Phase 6 build unless the development contract is explicitly changed.

## Planned / Next Work
1. Phase 1 — Foundation / protocol: complete at 746265a4561fedcb924bba729aef22458984d994.
2. Phase 2 — Quest-state engine: complete at d83669c6a476a5a7521a3308102a267c2e79a668.
3. Phase 3 — Group Progress UI: complete at e3b988309054eb86a3ad39953bf5a39332168e83.
4. Phase 4a — Guide/Tourist mode/session foundation: complete at b7655c8bd7d7108b38ad19f271a456f9bcad78d4.
5. Phase 4b — Guide/Tourist instruction behaviour: complete at 84fa3c77e327407a066fa1d9c3a5e7d41f7e89d5.
6. Phase 5a — Guide/Tourist instruction-window presentation: next. Build the compact movable Guide/Tourist window on the existing Phase 4a/4b state owners, render Blizzard-style yellow !/? instruction rows, and implement Tourist completion strike-through/fade/removal presentation. No disparity UI/state in 5a.
7. Phase 5b — Quest-disparity presentation/controls: deferred until Phase 5a is cleanly checkpointed. Add Guide missing-quest disparity rows plus hidden disparity handling and Show Hidden using the existing Phase 2 quest state and the Phase 5a window; do not add another session/instruction owner.
8. Phase 6 — Integration hardening / test build: deferred; run whole-system audit, remaining protocol robustness work and final available checks, then provide the first broad in-game test plan.

Each coding phase ends with available static/compiler checks, a clean commit checkpoint and an updated handoff. Runtime behaviour remains untested until Phase 6 unless the user explicitly changes that plan.

## Deferred / Out of Scope
- Phase 5a has not started and is the next active scope.
- Phase 5b disparity work is explicitly deferred until Phase 5a is completed and checkpointed.
- Phase 6 integration hardening and broad in-game testing remain deferred.
- No in-game testing was performed in Phase 4b.

## Release / Promotion Notes
- dev_rulebook.md and DEV_PROGRESS.md must never be present on main.
- main currently remains the repository bootstrap baseline only.
- Known validation debt accepted for release: None; the current compiler/parser debt is development validation debt, not an accepted release exception.
- External/runtime prerequisite: pfQuest.

## Exact Next Step
Begin Phase 5a — Guide/Tourist instruction-window presentation only from the current dev handoff after verifying the actual branch head against this file. Use the existing Phase 4a session owner and Phase 4b instructions component/state/events. Implement the compact movable Guide/Tourist window, Blizzard-style yellow !/? instruction rows, and Tourist completion strike-through/fade/removal presentation. Do not implement quest-disparity rows, hidden disparity handling or Show Hidden until Phase 5b; do not introduce another Guide/Tourist session/instruction owner, do not modify dev_rulebook.md, and do not perform in-game testing yet.
