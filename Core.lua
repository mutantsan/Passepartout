-- Passepartout: core (saved variables, helpers, events, slash commands)

local ADDON, ns = ...

ns.ICON = "Interface\\Icons\\INV_Misc_Map_01"
ns.LOGO = "Interface\\AddOns\\Passepartout\\media\\icon"
ns.NAME = "|cffc9a25aPassepartout|r"

local floor, format = math.floor, string.format

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(ns.NAME .. " " .. msg)
end

function ns.Num(n)
	n = floor((n or 0) + 0.5)
	local s = tostring(n)
	local k
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

function ns.Range(lo, hi)
	if not lo then return "?" end
	if not hi or hi == lo then return tostring(lo) end
	return lo .. "-" .. hi
end

-- Questie modules, once Questie has finished its own start-up.
function ns.Questie()
	if not (QuestieLoader and Questie and Questie.started) then return nil end
	if not ns.Q then
		local ok, mods = pcall(function()
			return {
				DB = QuestieLoader:ImportModule("QuestieDB"),
				XP = QuestieLoader:ImportModule("QuestXP"),
				Zone = QuestieLoader:ImportModule("ZoneDB"),
				Player = QuestieLoader:ImportModule("QuestiePlayer"),
				Compat = QuestieLoader:ImportModule("QuestieCompat"),
			}
		end)
		if not ok then return nil end
		ns.Q = mods
	end
	return ns.Q
end

function ns:InitDB()
	PassepartoutDB = PassepartoutDB or {}
	local db = PassepartoutDB
	db.minimap = db.minimap or {}
	db.window = db.window or {}
	db.settings = db.settings or {}
	if db.settings.includeElite == nil then db.settings.includeElite = true end
	self.db = db
end

-- Events --------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_LEVEL_UP")
boot:RegisterEvent("QUEST_TURNED_IN")
boot:RegisterEvent("QUEST_ACCEPTED")
boot:RegisterEvent("QUEST_REMOVED")
boot:RegisterEvent("ZONE_CHANGED_NEW_AREA")
boot:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then ns:InitDB() end
	elseif event == "PLAYER_LOGIN" then
		if ns.Minimap then ns.Minimap:Init() end
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		-- Moving only reorders the advice; no rescan needed, and it applies with the window closed too.
		if ns.Analyzer.result then
			ns.Analyzer:Rerank()
			ns.Analyzer:Notify()
		end
	else
		-- Level, turn-ins and the quest log all change the advice.
		ns.Analyzer:MarkDirty(event == "PLAYER_LEVEL_UP" and (arg1 or UnitLevel("player")) or nil)
	end
end)

-- Slash commands ----------------------------------------------------------------

SLASH_PASSEPARTOUT1, SLASH_PASSEPARTOUT2 = "/passepartout", "/pp"
SlashCmdList.PASSEPARTOUT = function(input)
	local cmd = (input or ""):lower():match("^%s*(.-)%s*$")
	if cmd == "minimap" then
		ns.Minimap:Toggle()
	elseif cmd == "scan" or cmd == "rescan" then
		ns.Analyzer:Start(true)
		ns.Print("Re-reading your quest history...")
	elseif cmd == "elite" then
		ns.db.settings.includeElite = not ns.db.settings.includeElite
		ns.Print(ns.db.settings.includeElite and "Elite (group) quests are now counted." or "Elite (group) quests are now ignored.")
		ns.Analyzer:Start(true)
	elseif cmd == "help" then
		ns.Print("/pp - open   /pp scan - rescan   /pp elite - toggle elite quests   /pp minimap - show/hide minimap button")
	else
		ns.UI:Toggle()
	end
end

function Passepartout_OnAddonCompartmentClick()
	ns.UI:Toggle()
end

