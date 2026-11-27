# Changelog

## Unreleased

- Zone names come from Questie first, then the client, so Forever's new zones (such as Shen'dralas) show by name instead of "Zone 16651".
- Quest page: reputation rewards are read straight from QuestieDB (Questie's helper re-maps old-world amounts and lost them), and factions you haven't met yet are named.
- Quest page: "Starts at" and "Hand in to" lines are clickable: they put the game's map pin (with the tracking arrow) on the NPC or object and open the map there.
- Quest page: rewards show "You get" and "Choose one of" separately once Passepartout has seen the quest in the game (its text at the giver, the turn-in screen, or your quest log). Until then it says whether it's probably a choice.
- Quest page: a quest opened from another zone's quest now shows its real status and zone; dropped the unclear "Not on your list for this zone" line.
- Quest colours now match the quest log on Forever: each quest's own difficulty from the client when it's known, otherwise the client's green range (inclusive). Quests the game shows as green were being counted as gray, which also hid them from suggestions.
- Journey tab: lists every zone with quests for you, not just those you've quested in. Zones you haven't started sit under "Not started yet", lowest level first.
- Journey tab: click a zone to see the quests you haven't done there, grouped by why: can do now, opens at a higher level, too hard, not unlocked yet, gray, no longer offered.
- Journey tab: click a quest for its page: level, whether you can take it and what's stopping you, objectives, where it starts and ends, its prequests and the quests it leads to, and its rewards: XP, items (hover for the tooltip, shift-click to link), reputation, and money once it's in your log. Linked quests open their own page; a back button returns where you were.

## 1.1.0

- Journey tab: the quest count and every zone's percentage now leave out quests Questie hides (removed, unobtainable, internal flags), holiday quests and open profession quests, so city and starting zones no longer look barely touched.
- Journey tab: zone bars show how much of the zone you've finished (matching the percentage) instead of quest count against your busiest zone, and each row reads "done of total".
- Journey tab: dropped the "you've mostly levelled without quests" note, which fired for anyone whose average quest level trailed theirs; it now says only what share of your zones' quests you've done.
- Journey tab: shows 15 zones with "Show all", and the footer counts zones quested in rather than zones checked for suggestions.
- Gray-quest counts in zone reasons no longer include hidden or holiday quests.

- The zone you're standing in is always listed under "Other good zones", with its rank, even when it falls outside the top six or has nothing left at your level (it then says how many of its quests have gone gray).

## 1.0.0

First release.
