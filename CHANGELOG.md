# Changelog

## Unreleased
- The Recent Allies button now stays on the Allies tab after the first load, as "Refresh Recent Allies". The game does not update the list on its own, so this refreshes it.

## 2.3
- Fixed: opening Recent Allies no longer triggers the "blocked from an action only available to the Blizzard UI" popup.
- Recent Allies remembers the last list it saw and shows it, marked "Saved list", until the game loads live data. You can invite from the saved list. Pinning and notes wait for live data.
- New Load Recent Allies button (experimental). The game only loads this list when Blizzard's own Recent Allies view opens, so the button opens that view for a moment and closes it.

## 2.2: first public release
- Compact one-line-per-friend replacement for the Social window (O key).
- Friends, Recent Allies, Requests and Ignore tabs, with a one-click party invite on every online friend and ally.
- Search, status and queue filters, friend tags, queue badges, notes, favorites and a full right-click menu.
- Two looks, Classic and Enhanced, chosen on first run and switchable with `/of skin`.
- Add Friend by BattleTag, email or character name, and Add WoW Friend from a Recent Ally.
- Every friend row shows the friend's faction emblem next to their realm ruleset icon.
- The party button is disabled, with a reason in its tooltip, for friends and recent allies on a realm with a different ruleset (PvE, PvP, RP, RP-PvP) than yours.
- Shift + the friends key (Shift+O by default) opens Blizzard's own Social window, in case you need it.
- Built-in diagnostics log (`/of log`) and a test mode (`/of test`).
- Does not call any function Blizzard restricts to its own UI, so it should never trigger a "blocked action" message. Changing your own status, Block Invites and Unblock are not possible from an addon and are disabled.
