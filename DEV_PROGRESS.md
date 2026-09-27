# Development Progress

## Current
- Branch: dev.
- Version: 0.1.3-dev from pfQuest_Group.toc.
- Latest addon-affecting development commit: b7655c8bd7d7108b38ad19f271a456f9bcad78d4 — Phase 4a Guide/Tourist session foundation.
- Handoff checkpoint: the current dev head carrying this status file; always verify the actual remote branch head before resuming.
- Stable baseline: None; main is repository bootstrap only, not a runtime release.
- Goal: Implement the agreed v1 addon across staged development chats, then perform the first broad in-game test on the integrated Phase 6 build.
- Current scope boundary: Phases 1–4a are complete. Phase 4b has not started. Phase 4b owns instruction behaviour only and must stop before Phase 5 UI/disparity work. No intermediate in-game testing is planned before Phase 6.

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
- Guide/Tourist state continues to use the Phase 1 session state component; do not introduce a parallel session state machine.

### Foundation / Protocol
- Protocol prefix: PFQGROUP; protocol version: 1; SavedVariables schema: 1.
- Only actual current party members participate in transport/discovery; discovery scans party1 through party4. Remote peer state is ephemeral and removed when that player leaves the party.
- Transport uses Vanilla SendAddonMessage / CHAT_MSG_ADDON over PARTY and targeted WHISPER only.
- Wire message types remain HELLO (H), full-state request (R), full snapshot (F) and component delta (D).
- State synchronization remains component-based through RegisterStateComponent, SendDelta and RequestFullSync.
- The built-in session and quests components share that owner.
- Phase 4a did not change the protocol version or add a new wire message type. The session component adds an optional action cursor field, which is backward-tolerant because component payloads are key/value maps.

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

### Guide / Tourist — Phase 4a Implemented
- Modes are Off, Guide and Tourist.
- Commands are /pfqgroup off, /pfqgroup guide, /pfqgroup tourist <player>, /pfqgroup status; /pfqg is an alias.
- Tourist mode requires a specific other player name. If that player is a known party member, the stored display name is canonicalized from the party record. The target may temporarily be absent so saved Tourist intent survives reconnect/rejoin.
- Entering Guide from another mode creates a new Guide session id and sets the Guide action cursor to 0.
- Remaining in the same Guide mode preserves the Guide session id and action cursor.
- Reload/relog preserves an active Guide session id and action cursor through pfQuest_GroupDB.session.
- Turning Guide Off clears the Guide session state; later re-entering Guide creates a new session id.
- guideActionSeq is a monotonic cursor scoped to the active Guide session. It increments only for local ACCEPT and TURNIN actions. It is baseline plumbing only: Phase 4a does not create, transport, match, complete or consume instruction objects.
- A Tourist automatically binds when the selected compatible peer advertises Guide mode with a Guide session id. The Tourist records that Guide session id and the Guide's current guideActionSeq as joinBaseline.
- The Tourist joinBaseline is fixed for the matched Guide session even as the Guide action cursor advances. This lets Phase 4b distinguish actions that occurred before versus after the Tourist joined.
- If the same Guide later advertises a different Guide session id, the Tourist rebinds and captures a fresh baseline from that new session.
- Temporary Guide disappearance, party loss, peer restart or missing remote session state does not by itself clear the Tourist's saved guideName, guideSessionId or joinBaseline.
- If the selected peer is present and explicitly advertises a non-Guide session state, only the Tourist's active binding/baseline is cleared; Tourist mode and the selected guideName remain so it can pair again later.
- Turning Tourist Off clears Tourist target, binding and join baseline.
- Invalid persisted Tourist state without a valid Guide name normalizes to Off.
- The existing session state component carries mode, revision, Guide target/session relationship, Tourist baseline and Guide action cursor. No parallel session owner was added.
- Existing hiddenDisparities persistence remains reserved for Phase 5; Phase 4a adds no disparity behaviour or UI.

### Phase 4b Boundary
- Phase 4b will build only on the Phase 4a session foundation.
- Phase 4b owns Guide ACCEPT/TURNIN instruction creation, instruction transport/synchronization, Tourist matching/completion/consumption, and duplicate/stale/order handling required for reliable instruction state.
- Phase 4b must honor joinBaseline and must not replay Guide actions from at or before the Tourist's captured baseline.
- Phase 4b must not add the Phase 5 Guide/Tourist window, Blizzard !/? presentation, strike-through/fade, missing-quest disparity rows, hidden disparity controls or Show Hidden.

### Phase 5 / Disparity Boundary
- Guide/Tourist presentation remains Phase 5.
- The compact movable window, Blizzard yellow !/? rows, automatic completion presentation, strike-through/fade removal, disparity rows and Show Hidden are all unimplemented.
- Current quest disparity is separate from the instruction baseline and may later show quests accepted before a Tourist joined.

## Recent Relevant Commits
- 4c5c63f074923266566c36c51ce2718d0060166f — initialize main with repository README only.
- 746265a4561fedcb924bba729aef22458984d994 — implement Phase 1 foundation/protocol.
- d83669c6a476a5a7521a3308102a267c2e79a668 — implement Phase 2 quest-state engine.
- e3b988309054eb86a3ad39953bf5a39332168e83 — implement Phase 3 Group Progress UI.
- 76fcb2e3950325fedc095dabf11a4e623d594b44 — split Phase 4 into Phase 4a and Phase 4b.
- b7655c8bd7d7108b38ad19f271a456f9bcad78d4 — implement Phase 4a Guide/Tourist session foundation.

## Completed / User-Verified
- Repository and feature/design direction were confirmed by the user.
- User explicitly requires dev_rulebook.md and DEV_PROGRESS.md to remain off main.
- No runtime addon behaviour has been user-tested yet.

## Implemented / Awaiting Runtime Test
- Phase 1 addon skeleton, party peer lifecycle, protocol v1, chunked full/delta component synchronization and persistent local session state.
- Phase 2 local/remote quest-state engine, quest action detection and NPC context fallback.
- Phase 3 Group Progress tracker integration for compatible party peers.
- Phase 4a Off/Guide/Tourist commands and state transitions.
- Phase 4a Guide session lifecycle and persistent per-session Guide action cursor.
- Phase 4a automatic selected-Guide pairing, fixed Tourist join baseline, rebind-on-new-session behaviour and persistence/reset rules.
- All Phase 4b instruction behaviour and all Phase 5 Guide/Tourist UI/disparity behaviour remain unimplemented.

## Static / Automated Checks

### Phase 4a exact implementation state
Exact implementation commit: b7655c8bd7d7108b38ad19f271a456f9bcad78d4.
- Exact pfQuest_Group.lua Git blob: 4abdf2ebf802dfa64198cd9475c475f6a85bdcba.
- TOC version: 0.1.3-dev.
- Pre-write handoff verification: dev was exactly 76fcb2e3950325fedc095dabf11a4e623d594b44 and had no newer branch movement.
- Pre-commit/concurrency verification was repeated immediately before moving dev; the branch was still exactly at the documented handoff and was fast-forwarded without force.
- Scope diff check: passed. The implementation changes only locales/enUS.lua, pfQuest_Group.lua and pfQuest_Group.toc. dev_rulebook.md and DEV_PROGRESS.md were unchanged by the implementation commit.
- Version check: passed; 0.1.2-dev -> 0.1.3-dev.
- Protocol ownership check: passed; protocol prefix/version remain PFQGROUP/1, there is still exactly one session component registration and exactly one Addon.SetMode definition.
- Phase boundary/UI check: passed. No Phase 4b instruction-generation/matching/consumption tokens were introduced. CreateFrame, CreateFontString and CreateTexture call counts are unchanged from Phase 3, so Phase 4a adds no Phase 5 UI regions.
- Static later-Lua/API scan: passed for the exact candidate source; no string.match, string.gmatch, table.unpack, select(, RegisterAddonMessagePrefix or modern C_ API tokens were introduced/present.
- Top-level local-declaration line count: 116 versus 110 before Phase 4a, below Lua 5.0.3's 200-local top-level chunk limit. This is a structural count, not a compiler proof.
- Focused mocked Phase 4a session harness: passed Guide session preservation/reset, ACCEPT/TURNIN-only cursor increments, automatic Tourist pairing, fixed baseline within one Guide session, persistence through temporary Guide disappearance, rebaseline on a new Guide session, explicit remote non-Guide unbinding, self-target rejection and Off reset semantics.
- The focused harness also passed texluac -p and runtime assertions under the available Lua 5.3.6 texluac/texlua environment. This validates the harness only; it is not the canonical Lua 5.0.3 compiler check and not an in-game test.

### Checks not actually runnable
- Exact full-file texluac parser smoke check for the Phase 4a Git blob: not run in the executable shell. Repository content is available through the GitHub connector, but the connector checkout/blob is not materialized into the shell; the shell also has no direct GitHub network access.
- Canonical Lua 5.0.3 compiler check: not run / unavailable in the executable environment for the exact Phase 4a blob. A C compiler is available, but the canonical VanillaTemplate checker/source and this connector-backed candidate cannot be assembled together in the shell. Do not treat the Lua 5.3.6 focused harness as a Lua 5.0.3 compiler pass.
- No in-game testing was performed, by plan.

### Earlier validation baseline
- Phase 3's exact runtime previously passed the available Lua 5.3.6 texluac parser smoke check, structural/static scans and the mocked tracker runtime harness documented at its checkpoint.
- The canonical Lua 5.0.3 compiler pass remains outstanding from Phase 3 onward.

## Current Issues
- Validation debt: the exact current Phase 4a runtime still needs the canonical Lua 5.0.3 compiler pass when the checker and addon source are executable in the same environment.
- Exact current full-file parser smoke in the available Lua 5.3.6 shell could not be run because connector repository bytes are not materialized there; the changed session logic received the focused parser/runtime harness described above.
- No known Phase 4a implementation defect is recorded at this checkpoint.

## Testing

### Last Runtime Test
- Version/commit: None.
- Passed: None.
- Failed: None.
- Not tested: all Phase 1–4a in-game behaviour.

### Next Runtime Test
- Per the agreed staged plan, no intermediate in-game test is scheduled.
- The first broad in-game test remains the integrated Phase 6 build unless the development contract is explicitly changed.

## Planned / Next Work
1. Phase 1 — Foundation / protocol: complete at 746265a4561fedcb924bba729aef22458984d994.
2. Phase 2 — Quest-state engine: complete at d83669c6a476a5a7521a3308102a267c2e79a668.
3. Phase 3 — Group Progress UI: complete at e3b988309054eb86a3ad39953bf5a39332168e83.
4. Phase 4a — Guide/Tourist mode/session foundation: complete at b7655c8bd7d7108b38ad19f271a456f9bcad78d4.
5. Phase 4b — Guide/Tourist instruction behaviour: next. Implement Guide accept/hand-in instruction creation, transport/synchronization, Tourist matching and automatic completion/consumption, and the minimum duplicate/stale/order handling required for reliable instruction state. Honor the Phase 4a Guide session id/action cursor/join baseline and stop before Phase 5.
6. Phase 5 — Guide/Tourist UI + disparity: deferred.
7. Phase 6 — Integration hardening / test build: deferred; run whole-system audit, remaining protocol robustness work and final available checks, then provide the first broad in-game test plan.

Each coding phase ends with available static/compiler checks, a clean commit checkpoint and an updated handoff. Runtime behaviour remains untested until Phase 6 unless the user explicitly changes that plan.

## Deferred / Out of Scope
- Phase 4b Guide/Tourist instruction behaviour has not started.
- All Phase 5 Guide/Tourist UI/disparity work remains deferred.
- Phase 6 integration hardening and broad in-game testing remain deferred.
- No in-game testing was performed in Phase 4a.

## Release / Promotion Notes
- dev_rulebook.md and DEV_PROGRESS.md must never be present on main.
- main currently remains the repository bootstrap baseline only.
- Known validation debt accepted for release: None; the current compiler-check debt is development validation debt, not an accepted release exception.
- External/runtime prerequisite: pfQuest.

## Exact Next Step
Begin Phase 4b — Guide/Tourist instruction behaviour from the current dev handoff after verifying the actual branch head against this file. Use the existing Phase 4a session owner and its Guide session id, guideActionSeq and Tourist joinBaseline. Implement only Guide ACCEPT/TURNIN instruction creation, instruction synchronization/transport, Tourist matching/completion/consumption and the minimum duplicate/stale/order handling required for reliable instruction state. Do not implement any Phase 5 UI/disparity behaviour, do not modify dev_rulebook.md, and do not perform in-game testing yet.
