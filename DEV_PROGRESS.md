# Development Progress

## Current
- Branch: `dev`
- Version: Not established yet; no addon `.toc` or runtime files exist.
- Development head: `107ab19b47996cb0081735c6d1f94c35392d95eb` (latest pre-status development commit).
- Stable baseline: None; `main` is repository bootstrap only, not a runtime release.
- Goal: Implement the agreed v1 addon across staged development chats, then perform the first broad in-game test on the integrated build.
- Current scope boundary: Coding is authorized by phase; no intermediate in-game testing is planned before the integrated test build.

## Current Design / Development Contract

### Workflow / Branch Rules
- Active addon development will occur on `dev`.
- `dev_rulebook.md` is copied unchanged from `Seraphic8x2244/VanillaTemplate` and is authoritative.
- `dev_rulebook.md` and `DEV_PROGRESS.md` are development-only and must never be promoted to or committed on `main`.
- `main` is reserved for stable repository/release content.
- The addon `.toc` will become the single version source of truth once runtime implementation begins.

### Architecture / Ownership
- Target: World of Warcraft 1.12.1 / Interface 11200 / Lua 5.0.3.
- Project is a separate companion addon named `pfQuest_Group`.
- `pfQuest` is the authoritative local quest/tracker source.
- Do not modify pfQuest source files directly for normal implementation.
- Group Progress and Guide/Tourist are separate systems; Group Progress must work without Guide/Tourist mode.
- Prefer a small architecture and one main Lua file unless implementation pressure justifies a deliberate split.

### Group Quest Progress
- Only current party members with compatible `pfQuest_Group` participate; maximum four remote players.
- Use actual class icons for remote players and class-coloured player names where names are shown.
- Binary objectives (`0/1`, `1/1`) remain on the existing objective line and append compact remote status as class icon + `✓` or `✗`.
- Example intent: `Lakmaeran's Carcass    [class icon]✓    [class icon]✗`.
- Multi-count objectives expand vertically with one additional row per compatible remote player.
- Example intent:
  - local pfQuest row: `Chimaerok Tenderloin: 3/20`
  - remote row: `[class icon]Revenga: Chimaerok Tenderloin: 3/20`
  - remote row: `[class icon]Gaiamania: Chimaerok Tenderloin: 7/20`
- Vertical expansion is preferred over horizontally compressing up to five numeric progress values.

### Guide / Tourist
- Modes: Off, Guide, Tourist.
- A Tourist follows one specific Guide.
- Guide/Tourist uses a compact movable minimal window.
- Guide actions are one-line entries.
- Use Blizzard quest artwork: yellow `!` for accept and yellow `?` for hand-in.
- Accept presentation: `! NPC Name — Quest Name`.
- Hand-in presentation: `? NPC Name — Quest Name`.
- Tourist matching is automatic; no acknowledgement buttons.
- On matching Tourist action, strike through the instruction, fade for about 10 seconds, then remove it.

### Missing Quest / Disparity Handling
- Guide mode compares the Guide's current quest state against active Tourists.
- Show one disparity row per quest, followed by all Tourists missing it.
- Example intent: `✗ The Isle of Dread    [class icon] Gaia    [class icon] Aria`.
- Tourist names are class-coloured and preceded by actual class icons.
- Clicking a disparity row hides it.
- A `Show Hidden` control must allow hidden disparity rows to be restored/viewed.
- Hidden disparity state belongs to the active Guide session.

### Session State
- Guide/Tourist session state should persist across reload, relog and reconnect.
- Turning Guide mode off clears the Guide session state.
- Turning Tourist mode off resets that Tourist session state.
- When a Tourist joins a Guide session, record that join as the instruction baseline.
- Do not replay Guide quest actions from before that Tourist joined as instructions.
- Current quest disparity is separate from the instruction baseline and may show quests accepted by the Guide before the Tourist joined.

### Protocol / Data Model
- Communication protocol is versioned from the first implementation.
- Quest identity: `questID` authoritative when available, quest title fallback.
- NPC identity: `mobID` authoritative when available, NPC name fallback.
- Guide messages should carry IDs plus display/fallback names when available.
- Initial synchronization reconstructs compatible-client presence, relevant quest/objective state, Guide/Tourist relationships, disparity state and session baselines.
- After synchronization, prefer deltas rather than repeatedly sending full state.
- Group Progress synchronization is independent of Guide/Tourist mode.

### Refresh / Event Behaviour
- Quest disparity refreshes when relevant Guide or Tourist quest state changes and when session/sync state changes.
- Prefer event/state-driven updates over unnecessary continuous full rescans.
- Reuse pfQuest's existing state/refresh ownership where practical rather than creating parallel quest-state machinery.

## Recent Relevant Commits
- `4c5c63f074923266566c36c51ce2718d0060166f` — initialize `main` with repository README only.
- `107ab19b47996cb0081735c6d1f94c35392d95eb` — add canonical unchanged `dev_rulebook.md` on `dev`.

## Completed / User-Verified
- Repository exists as `Seraphic8x2244/pfQuest_Group`.
- User confirmed the initial feature/spec direction before repository setup.
- User explicitly required `dev_rulebook.md` and `DEV_PROGRESS.md` to remain off `main`.

## Implemented / Awaiting Runtime Test
- None. Runtime implementation has not started.

## Static / Automated Checks
- None required yet; no runtime Lua or loader files exist.

## Current Issues
- None.

## Testing

### Last Runtime Test
- Version/commit: None.
- Passed: None.
- Failed: None.
- Not tested: All runtime behaviour; no runtime implementation exists.

### Next Runtime Test
- To be defined after the first authorized runtime implementation checkpoint.

## Planned / Next Work
Use six coding phases, each ending with static/Lua 5.0.3 checks where available, a clean commit checkpoint, and an updated handoff. Runtime behaviour remains untested until Phase 6 produces the integrated test build.

1. **Foundation / protocol** — addon skeleton, versioning, SavedVariables, pfQuest dependency, party discovery, versioned messaging, full-sync/delta framework, persistent Guide/Tourist session state.
2. **Quest-state engine** — normalize local pfQuest quest/objective state, accept/remove/turn-in/progress detection, remote state, reload/group resync, quest/NPC ID fallback handling.
3. **Group Progress UI** — pfQuest tracker integration, binary class-icon + ✓/✗ statuses, expanded multi-count rows, class colours/icons, layout and group churn handling.
4. **Guide/Tourist behaviour** — commands/modes, pairing, join baseline, accept/hand-in instructions, automatic Tourist completion, persistence/reset rules.
5. **Guide/Tourist UI + disparity** — compact window, Blizzard !/?, strike-through/fade, missing-quest rows, hide/Show Hidden, layout/persistence.
6. **Integration hardening / test build** — whole-system audit, stale/duplicate/order handling, SavedVariables/protocol robustness, final static/compiler checks, then one broad in-game test plan.

Phases may be split or combined if implementation complexity warrants it, but each chat must end at a coherent handoff checkpoint.

## Deferred / Out of Scope
- No additional product scope is documented here beyond the currently agreed v1 contract.
- Runtime coding is intentionally deferred until explicit user authorization.

## Release / Promotion Notes
- `dev_rulebook.md` and `DEV_PROGRESS.md` must never be present on `main`.
- Main-only/release-only content to preserve: current repository README until a later stable release changes it deliberately.
- Known validation debt accepted for release: None.
- External/runtime prerequisites: pfQuest; exact dependency metadata/path will be established during implementation.

## Exact Next Step
Begin Phase 1: create the minimal addon skeleton on `dev`, establish the initial `-dev` version, then implement party discovery, protocol/state ownership, synchronization framework and persistent Guide/Tourist session state. Do not begin tracker or Guide/Tourist UI work in Phase 1.
