# pfQuest Group

Party quest progress and Guide/Tourist companion for [pfQuest](https://github.com/shagu/pfQuest) on World of Warcraft Vanilla 1.12.1.

## Install

Place the `pfQuest_Group` folder inside `Interface/AddOns` alongside `pfQuest`. Both addons must be enabled.

## Use

Use the minimap button to toggle the Guide/Tourist panel and choose a mode from its right-click menu. The addon also supports `/pfqg guide`, `/pfqg tourist <player>`, `/pfqg off`, and `/pfqg status`.

The Guide/Tourist panel automatically uses the installed pfUI skin where available. Otherwise it retains its native appearance.

## Compatibility

This first stable release is `0.3.27` (protocol 5). Guide/Tourist instructions and shared quest progress currently require participating players to be in the same party, not different raid subgroups. Guide-owned Tourist admission and cross-raid sharing are planned, not implemented.

Per-character configuration and Guide/Tourist progress use `pfQuest_GroupDB` SavedVariables. Before installing or updating, preserve your character-specific SavedVariables file if you need a backup.

Known validation debt: some persistence and reconnection edge cases have not been conclusively exercised. The live pfUI panel skin has been user-tested and accepted.

Development is tracked on the `dev` branch; stable releases appear on `main`.
