-- Passepartout: Rewards
--
-- QuestieDB knows which items a quest rewards, not whether you get them all or pick one.
-- The game says so whenever a quest's text is open (at its giver, at turn-in) or the quest
-- is in your log, so we remember the answer per quest the first time we see it.

local _, ns = ...

local R = {}
ns.Rewards = R

local function Store()
	ns.db.rewardKinds = ns.db.rewardKinds or {}
	return ns.db.rewardKinds
end

local function IdFromLink(link)
	return link and tonumber(link:match("item:(%d+)"))
end

-- Reads one list through a counter and a per-index reader returning (..., itemID) or a link.
local function ReadList(n, info, link)
	local ids = {}
	for i = 1, n or 0 do
		local ok, _, _, _, _, _, itemID = pcall(info, i)
		local id = ok and tonumber(itemID) or nil
		if not id and link then
			local okL, l = pcall(link, i)
			id = okL and IdFromLink(l) or nil
		end
		if id then ids[#ids + 1] = id end
	end
	return ids
end

local function Save(questID, given, choice)
	if not (questID and questID > 0) then return end
	if #given == 0 and #choice == 0 then return end
	Store()[questID] = { given = given, choice = choice }
end

-- Gossip quest text (QUEST_DETAIL) and the turn-in screen (QUEST_COMPLETE).
local function LearnFromQuestFrame()
	local questID = GetQuestID and GetQuestID()
	if not questID or questID == 0 then return end
	local given = ReadList(GetNumQuestRewards and GetNumQuestRewards(),
		function(i) return GetQuestItemInfo("reward", i) end,
		function(i) return GetQuestItemLink("reward", i) end)
	local choice = ReadList(GetNumQuestChoices and GetNumQuestChoices(),
		function(i) return GetQuestItemInfo("choice", i) end,
		function(i) return GetQuestItemLink("choice", i) end)
	Save(questID, given, choice)
end

-- A quest in your log: the log reward functions read the selected quest, so select it briefly.
local function LearnFromLog(questID)
	if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)) then return end
	if not (GetNumQuestLogRewards and GetNumQuestLogChoices) then return end
	local prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
	if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
	local okG, nG = pcall(GetNumQuestLogRewards, questID)
	local okC, nC = pcall(GetNumQuestLogChoices, questID, false)
	local given = ReadList(okG and nG or 0,
		function(i) return GetQuestLogRewardInfo(i, questID) end,
		function(i) return GetQuestLogItemLink("reward", i) end)
	local choice = ReadList(okC and nC or 0,
		function(i) return GetQuestLogChoiceInfo(i) end,
		function(i) return GetQuestLogItemLink("choice", i) end)
	if C_QuestLog.SetSelectedQuest and prev and prev ~= questID then C_QuestLog.SetSelectedQuest(prev) end
	Save(questID, given, choice)
end

-- { given = {itemIDs}, choice = {itemIDs} } when known, else nil.
function R.Get(questID)
	local known = Store()[questID]
	if known then return known end
	pcall(LearnFromLog, questID)
	return Store()[questID]
end

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_ACCEPTED")
f:SetScript("OnEvent", function(_, event, a1, a2)
	if not ns.db then return end
	local questID = a2 or a1   -- classic-style clients pass (logIndex, questID)
	if event == "QUEST_ACCEPTED" then
		-- Reward data can lag a moment behind acceptance.
		C_Timer.After(1, function() pcall(LearnFromLog, questID) end)
	else
		pcall(LearnFromQuestFrame)
	end
end)
