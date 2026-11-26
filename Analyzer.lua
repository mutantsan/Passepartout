-- Passepartout: Analyzer
--
-- One pass over every quest QuestieDB knows. For each quest the player could actually take
-- (Questie's own IsDoable: race, class, prerequisites, reputation, professions, exclusives)
-- it resolves the zone, the level of the mobs its objectives send you after (creature, kill
-- credit and item-drop sources), and the XP it pays at your level. Completed quests feed the
-- journey history. Zones are then ranked by the XP you can earn there at a comfortable
-- difficulty. The pass runs in a coroutine under a per-frame time budget so it never hitches.

local _, ns = ...

local floor, max, min, format = math.floor, math.max, math.min, string.format
local tinsert, tsort = table.insert, table.sort

local A = { state = "idle", progress = 0, dirty = true, listeners = {} }
ns.Analyzer = A

local BUDGET_MS = 8
local QUEST_FLAG_RAID = 64
local MAX_DROP_SOURCES = 10

-- Battlegrounds are never a questing destination.
local IGNORED_ZONES = { [2597] = true, [3277] = true, [3358] = true }

-- Difficulty ---------------------------------------------------------------------

local function GrayRange(level)
	if UnitQuestTrivialLevelRange then
		local ok, r = pcall(UnitQuestTrivialLevelRange, "player")
		if ok and type(r) == "number" and r > 0 then return r end
	end
	if level <= 5 then return 5 end
	if level <= 39 then return 5 + floor(level / 10) end
	if level <= 59 then return 1 + floor(level / 5) end
	return 9
end

-- trivial / standard (green) / difficult (yellow) / verydifficult (orange) / impossible (red)
function A.Difficulty(questLevel, level)
	local d = questLevel - level
	if d >= 5 then return "impossible" end
	if d >= 3 then return "verydifficult" end
	if d >= -2 then return "difficult" end
	if -d < GrayRange(level) then return "standard" end
	return "trivial"
end

-- How much a quest's XP is worth per hour of play. Green quests are easier to complete (mobs
-- die faster, less resting, no deaths), so they rank above yellow, tapering off only as they
-- near gray, where the XP itself dries up. Yellow at or above your level takes longer; orange
-- is slow and risky.
local function Fit(diff, questLevel, level)
	local d = questLevel - level
	if diff == "standard" then
		local g = GrayRange(level)
		local t = max(0, min(1, (-d - 3) / max(1, g - 3)))   -- 0 just below yellow, 1 at the gray line
		return 1.15 - 0.45 * t
	elseif diff == "difficult" then
		return d < 0 and 1.05 or 1.0
	elseif diff == "verydifficult" then
		return 0.5
	end
	return 0
end

-- Lookups ------------------------------------------------------------------------

local function Lib() return LibQuestieDB end

local zoneNames = {}
function A.ZoneName(area)
	local n = zoneNames[area]
	if n == nil then
		n = (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)) or false
		if not n and ns.Q then
			local ok, d = pcall(ns.Q.Zone.GetLocalizedDungeonName, ns.Q.Zone, area)
			n = ok and d or false
		end
		zoneNames[area] = n
	end
	return n or ("Zone " .. area)
end

local function NpcZone(npcs)
	if type(npcs) ~= "table" then return nil end
	local N = Lib().Npc
	for _, npc in ipairs(npcs) do
		local z = N.zoneID(npc)
		if z and z > 0 then return z end
	end
end

local function ResolveZone(id)
	local Qd, Z = Lib().Quest, ns.Q.Zone
	local area = Qd.zoneOrSort(id)
	if not (area and area > 0) then
		local starts = Qd.startedBy(id)
		area = starts and NpcZone(starts[1])
		if not area then
			local obj = Qd.objectives(id)
			if obj and obj[1] then
				local ids = {}
				for _, o in ipairs(obj[1]) do ids[#ids + 1] = o[1] end
				area = NpcZone(ids)
			end
		end
	end
	if not (area and area > 0) then return nil end
	for _ = 1, 2 do
		local ok, parent = pcall(Z.GetParentZoneId, Z, area)
		if ok and parent and parent ~= area and parent > 0 then area = parent else break end
	end
	if IGNORED_ZONES[area] then return nil end
	return area
end

-- Mob level range and eliteness for a quest's objectives. NPCs far below the quest's level
-- are critters, level-1 kill-credit triggers or helpers, not what you fight; they're skipped.
local MOB_FLOOR = 8
local mobCache = {}
local function MobLevels(id, qLevel)
	local c = mobCache[id]
	if c then return c[1], c[2], c[3], c[4] end
	local L = Lib()
	local N, I = L.Npc, L.Item
	local lo, hi, elite, count = nil, nil, false, 0
	local seen = {}
	local function addNpc(npc)
		if not npc or seen[npc] then return end
		seen[npc] = true
		local a, b = N.minLevel(npc), N.maxLevel(npc)
		a = a or b; b = b or a
		if a and a > 0 and a <= 63 then
			b = (b and b >= a and b <= 63) and b or a
			if qLevel and b < qLevel - MOB_FLOOR then return end
			lo = lo and min(lo, a) or a
			hi = hi and max(hi, b) or b
			count = count + 1
			local rank = N.rank(npc)
			if rank == 1 or rank == 2 or rank == 3 then elite = true end
		end
	end
	local obj = L.Quest.objectives(id)
	if obj then
		for _, o in ipairs(obj[1] or {}) do addNpc(o[1]) end
		for _, o in ipairs(obj[5] or {}) do
			if type(o[1]) == "table" then for _, npc in ipairs(o[1]) do addNpc(npc) end end
			addNpc(o[2])
		end
		for _, o in ipairs(obj[3] or {}) do
			local drops = I.npcDrops(o[1])
			if drops then
				for i = 1, min(#drops, MAX_DROP_SOURCES) do addNpc(drops[i]) end
			end
		end
	end
	mobCache[id] = { lo, hi, elite, count }
	return lo, hi, elite, count
end

-- A quest whose every NPC starter is friendly only to the other faction is not ours.
local function StarterFriendly(id, faction)
	local starts = Lib().Quest.startedBy(id)
	if not starts then return true end
	if (starts[2] and #starts[2] > 0) or (starts[3] and #starts[3] > 0) then return true end
	local npcs = starts[1]
	if not npcs or #npcs == 0 then return true end
	local N = Lib().Npc
	for _, npc in ipairs(npcs) do
		local f = N.friendlyToFaction(npc)
		if not f or f == "AH" or f == faction then return true end
	end
	return false
end

local function InLog(id)
	if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) end
	if GetQuestLogIndexByID then return (GetQuestLogIndexByID(id) or 0) > 0 end
	return false
end

local function IsReady(id)
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, done = pcall(C_QuestLog.IsComplete, id)
		return ok and done == true
	end
	return false
end

-- Continents: zones on another continent cost a boat or a long flight.
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local function ContinentOfMap(id)
	for _ = 1, 10 do
		if not (id and id > 0) then return nil end
		local info = C_Map.GetMapInfo(id)
		if not info then return nil end
		if info.mapType == CONTINENT then return id end
		if info.mapType < CONTINENT then return nil end
		id = info.parentMapID
	end
end

local continentCache = {}
local function ContinentOfArea(area)
	local c = continentCache[area]
	if c == nil then
		local Z = ns.Q.Zone
		local ok, uiMapId = pcall(Z.GetUiMapIdByAreaId, Z, area)
		c = ok and uiMapId and ContinentOfMap(uiMapId) or false
		continentCache[area] = c
	end
	return c or nil
end

function A.UiMapId(area)
	local Q = ns.Questie()
	if not Q then return nil end
	local ok, id = pcall(Q.Zone.GetUiMapIdByAreaId, Q.Zone, area)
	return ok and id and id > 0 and id or nil
end

local function CompletedSet()
	local set, count = {}, 0
	local ids = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
	if ids then
		for _, id in ipairs(ids) do set[id] = true; count = count + 1 end
	end
	local qc = Questie and Questie.db and Questie.db.char and Questie.db.char.complete
	if qc then
		for id, v in pairs(qc) do
			if v and not set[id] then set[id] = true; count = count + 1 end
		end
	end
	return set, count
end

-- The pass -------------------------------------------------------------------------

local function Bucket(t, area)
	local b = t[area]
	if not b then
		b = { area = area, quests = {}, groups = {}, total = 0, done = 0, gray = 0 }
		t[area] = b
	end
	return b
end

local function Scan()
	local L, Q = Lib(), ns.Q
	local Qd = L.Quest
	local level = UnitLevel("player")
	local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
	local includeElite = ns.db.settings.includeElite
	local Player, DB, XP = Q.Player, Q.DB, Q.XP
	local completed, completedCount = CompletedSet()

	-- Quests Questie hides (removed, unobtainable, internal flags) and holiday quests are left
	-- out of everything. Quests Questie only keeps off the map are real and stay in.
	local hidden = Q.Corrections and Q.Corrections.hiddenQuests or {}
	local Event = Q.Event
	local function Unlisted(id)
		local h = hidden[id]
		if h and h ~= "HIDE_ON_MAP" then return true end
		if Event and Event.IsEventQuest then
			local ok, ev = pcall(Event.IsEventQuest, id)
			if ok and ev then return true end
		end
		return false
	end

	local zones, soon, leftovers = {}, {}, {}
	local doneCount = 0
	local ids = Qd.GetAllIds()
	local total = #ids
	local t0 = debugprofilestop()

	for i, id in ipairs(ids) do
		if debugprofilestop() - t0 > BUDGET_MS then
			A.progress = i / total
			A:Notify()
			coroutine.yield()
			t0 = debugprofilestop()
		end

		local special = Qd.specialFlags(id) or 0
		local flags = Qd.questFlags(id) or 0
		local isDone = completed[id]
		local skip = Unlisted(id)
		if isDone and not skip then doneCount = doneCount + 1 end
		if not skip and special % 2 == 0 and (flags % (QUEST_FLAG_RAID * 2)) < QUEST_FLAG_RAID
			and Player.HasRequiredRace(Qd.requiredRaces(id)) and Player.HasRequiredClass(Qd.requiredClasses(id)) then

			local area = ResolveZone(id)
			local qLevel = Qd.questLevel(id) or 0
			if qLevel <= 0 then qLevel = level end
			-- Either/or quests count once toward a zone's completion: key them by the group's lowest ID.
			local ex = Qd.exclusiveTo(id)
			local key = id
			if ex then for _, e in ipairs(ex) do if e < key then key = e end end end

			if isDone then
				if area then Bucket(zones, area).groups[key] = true end
			elseif area and StarterFriendly(id, faction) then
				local b = Bucket(zones, area)
				-- Open profession quests don't count against a zone's completion.
				if b.groups[key] == nil and not Qd.requiredSkill(id) then b.groups[key] = false end
				local req = Qd.requiredLevel(id) or 1
				local maxReq = Qd.requiredMaxLevel(id) or 0
				local diff = A.Difficulty(qLevel, level)
				local inLog = InLog(id)
				if maxReq > 0 and level > maxReq then
					-- aged out
				elseif req > level then
					if req <= level + 3 then
						local ok, doable = pcall(DB.IsDoable, id)
						if ok and doable then
							local s = Bucket(soon, area)
							tinsert(s.quests, { id = id, level = qLevel, req = req })
						end
					end
				elseif diff == "trivial" then
					b.gray = b.gray + 1
					if inLog then
						-- Outlevelled but still in the log: free experience waiting to be handed in.
						local ok, xp = pcall(XP.GetQuestLogRewardXP, XP, id, false)
						tinsert(leftovers, {
							id = id, level = qLevel, diff = diff, area = area, inLog = true, ready = IsReady(id),
							xp = (ok and type(xp) == "number" and xp > 0) and xp or nil,
						})
					end
				elseif diff ~= "impossible" then
					local doable = inLog
					if not doable then
						local ok, d = pcall(DB.IsDoable, id)
						doable = ok and d
					end
					if doable then
						local lo, hi, elite = MobLevels(id, qLevel)
						if not elite or includeElite then
							local ok, xp = pcall(XP.GetQuestLogRewardXP, XP, id, false)
							xp = (ok and type(xp) == "number" and xp > 0) and xp or nil
							local fit = Fit(diff, qLevel, level)
							if hi and hi > level + 3 then fit = fit * 0.5 end
							if elite then fit = fit * 0.35 end
							if inLog then fit = fit * 1.15 end
							tinsert(b.quests, {
								id = id, level = qLevel, diff = diff, xp = xp, fit = fit, area = area, ex = ex,
								mobLo = lo, mobHi = hi, elite = elite, inLog = inLog, ready = inLog and IsReady(id),
							})
						end
					end
				end
			end
		end
	end

	for _, b in pairs(zones) do
		for _, isDone in pairs(b.groups) do
			b.total = b.total + 1
			if isDone then b.done = b.done + 1 end
		end
		b.groups = nil
	end

	-- Fall back to the raw count if Questie's tables weren't readable.
	return zones, soon, leftovers, doneCount > 0 and doneCount or completedCount
end

-- Ranking ---------------------------------------------------------------------------

local function Percentile(sorted, p)
	if #sorted == 0 then return nil end
	local idx = max(1, min(#sorted, floor(#sorted * p + 0.5)))
	return sorted[idx]
end

local function Summarize(b, level)
	if b.summarized then return end
	b.summarized = true
	for _, q in ipairs(b.quests) do q.value = (q.xp or (level * 60)) * q.fit end
	-- Of two mutually exclusive quests you can only do one: keep the better.
	local byId = {}
	for _, q in ipairs(b.quests) do byId[q.id] = q end
	for _, q in ipairs(b.quests) do
		if q.ex and not q.drop then
			for _, e in ipairs(q.ex) do
				local o = byId[e]
				if o and o ~= q and not o.drop then
					if o.value > q.value then q.drop = true; break else o.drop = true end
				end
			end
		end
	end
	local kept = {}
	for _, q in ipairs(b.quests) do if not q.drop then kept[#kept + 1] = q end end
	b.quests = kept

	local los, his = {}, {}
	b.xp, b.baseScore, b.inLog, b.elite = 0, 0, 0, 0
	b.colors = { standard = 0, difficult = 0, verydifficult = 0 }
	for _, q in ipairs(b.quests) do
		b.xp = b.xp + (q.xp or 0)
		b.baseScore = b.baseScore + q.value
		b.colors[q.diff] = b.colors[q.diff] + 1
		if q.inLog then b.inLog = b.inLog + 1 end
		if q.elite then b.elite = b.elite + 1 end
		if q.mobLo then los[#los + 1] = q.mobLo; his[#his + 1] = q.mobHi end
	end
	tsort(los); tsort(his)
	b.mobLo, b.mobHi = Percentile(los, 0.15), Percentile(his, 0.85)
	-- What's actually left to do: the quest levels, and how many sit at each.
	b.byLevel = {}
	for _, q in ipairs(b.quests) do
		b.byLevel[q.level] = (b.byLevel[q.level] or 0) + 1
		b.qLo = b.qLo and min(b.qLo, q.level) or q.level
		b.qHi = b.qHi and max(b.qHi, q.level) or q.level
	end
	if not b.mobLo then
		-- Delivery-only zones: fall back to quest levels.
		local lv = {}
		for _, q in ipairs(b.quests) do lv[#lv + 1] = q.level end
		tsort(lv)
		b.mobLo, b.mobHi, b.questLevels = lv[1], lv[#lv], true
	end
	-- A zone with a single quest is an errand, not a destination.
	if #b.quests < 3 then b.baseScore = b.baseScore * 0.5 end
	tsort(b.quests, function(x, y)
		if x.inLog ~= y.inLog then return x.inLog end
		return x.value > y.value
	end)
	b.name = A.ZoneName(b.area)
	b.continent = ContinentOfArea(b.area)
end

local function Plural(n, one, many) return n == 1 and one or format(many, n) end

local function Reasons(b, level)
	local r = {}
	if b.current then r[#r + 1] = "you're already here" end
	if #b.quests == 0 then
		if b.gray > 0 then r[#r + 1] = Plural(b.gray, "one quest left, but it's gray now", "%d quests left, but they're gray now") end
		if b.done > 0 then r[#r + 1] = format("%d done here already", b.done) end
		if #r == 1 then r[#r + 1] = "nothing left here at your level" end
		return r
	end
	local y = b.colors.difficult
	if y > 0 then r[#r + 1] = Plural(y, "one quest at your level", "%d quests at your level") end
	if b.inLog > 0 then r[#r + 1] = Plural(b.inLog, "one already in your log", "%d already in your log") end
	if b.done > 0 then r[#r + 1] = format("%d done here already", b.done) end
	if b.mobLo and not b.questLevels then
		if b.mobHi <= level then r[#r + 1] = "the mobs are around your level or lower"
		elseif b.mobLo >= level + 2 then r[#r + 1] = "the mobs are a bit higher than you" end
	end
	return r
end

function A:Build(zones, soon, leftovers, completedCount)
	local level = UnitLevel("player")
	local Z = ns.Q.Zone

	local ranked, dungeons, history = {}, {}, {}
	for area, b in pairs(zones) do
		if b.done > 0 then history[#history + 1] = b end
		if #b.quests > 0 then
			Summarize(b, level)
			local okD, isDungeon = pcall(Z.IsDungeonZone, area)
			if okD and isDungeon then
				b.dungeon = true
				dungeons[#dungeons + 1] = b
			else
				ranked[#ranked + 1] = b
			end
		end
	end
	for _, b in ipairs(history) do b.name = b.name or A.ZoneName(b.area) end
	tsort(history, function(x, y) return x.done > y.done end)

	local upcoming = {}
	for _, s in pairs(soon) do
		local okD, isDungeon = pcall(Z.IsDungeonZone, s.area)
		if not (okD and isDungeon) then
			s.name = A.ZoneName(s.area)
			s.req = 99
			for _, q in ipairs(s.quests) do s.req = min(s.req, q.req) end
			upcoming[#upcoming + 1] = s
		end
	end
	tsort(upcoming, function(x, y)
		if #x.quests ~= #y.quests then return #x.quests > #y.quests end
		return x.req < y.req
	end)
	tsort(leftovers, function(x, y)
		if x.ready ~= y.ready then return x.ready end
		return (x.xp or 0) > (y.xp or 0)
	end)

	self.result = {
		level = level,
		xpMax = UnitXPMax("player"),
		zones = ranked,
		dungeons = dungeons,
		upcoming = upcoming,
		leftovers = leftovers,
		history = history,
		byArea = zones,
		completed = completedCount,
		time = time(),
	}
	self:Rerank()
end

-- Where you stand only changes the order, so moving re-ranks in a moment instead of rescanning.
function A:Rerank()
	local r = self.result
	if not (r and ns.Q) then return end
	local ok, current = pcall(ns.Q.Player.GetCurrentZoneId, ns.Q.Player)
	current = ok and current or nil
	local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local playerContinent = here and ContinentOfMap(here)
	for _, list in ipairs({ r.zones, r.dungeons }) do
		for _, b in ipairs(list) do
			b.current = (b.area == current)
			b.far = (playerContinent and b.continent and b.continent ~= playerContinent) and true or false
			-- Distance is shown, not penalised: a boat ride is a fair price for a better zone.
			b.score = b.baseScore * (b.current and 1.1 or 1)
			b.reasons = Reasons(b, r.level)
		end
		tsort(list, function(x, y) return x.score > y.score end)
	end
	r.current = current

	-- Wherever you stand always gets a line, even when it didn't make the cut.
	r.here, r.hereRank = nil, nil
	if current and not IGNORED_ZONES[current] then
		for i, b in ipairs(r.zones) do
			if b.current then r.here, r.hereRank = b, i; break end
		end
		local okD, isDungeon = pcall(ns.Q.Zone.IsDungeonZone, current)
		if not r.here and not (okD and isDungeon) then
			local b = r.byArea and r.byArea[current]
			if not b then
				b = { area = current, quests = {}, total = 0, done = 0, gray = 0 }
				if r.byArea then r.byArea[current] = b end
			end
			Summarize(b, r.level)
			b.current, b.far, b.score = true, false, b.baseScore
			b.reasons = Reasons(b, r.level)
			r.here = b
		end
	end
end

-- Lifecycle --------------------------------------------------------------------------

function A:Notify()
	for _, fn in ipairs(self.listeners) do fn(self.state) end
end

function A:OnChange(fn) tinsert(self.listeners, fn) end

local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
	local co = A.co
	if not co then self:Hide(); return end
	local ok, err = coroutine.resume(co)
	if not ok then
		A.co, A.state, A.error = nil, "error", err
		self:Hide()
		geterrorhandler()(err)
		A:Notify()
	elseif coroutine.status(co) == "dead" then
		A.co = nil
		self:Hide()
		A.state, A.progress = "ready", 1
		A:Notify()
		-- Something changed while we were reading: read again so the advice isn't a step behind.
		if A.dirty and ns.UI and ns.UI:IsShown() then A:Start(true) end
	end
end)

local waiter = CreateFrame("Frame")
waiter:Hide()
waiter.t = 0
waiter:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 1 then return end
	self.t = 0
	if ns.Questie() then
		self:Hide()
		A:Start(true)
	end
end)

function A:Start(force)
	if self.co then return end
	if not force and not self.dirty and self.result then return end
	if not (LibQuestieDB and LibQuestieDB.Quest) or not ns.Questie() then
		self.state = "waiting"
		waiter:Show()
		self:Notify()
		return
	end
	wipe(mobCache)
	self.dirty = false
	self.state, self.progress, self.error = "scanning", 0, nil
	self.co = coroutine.create(function()
		A:Build(Scan())
	end)
	runner:Show()
	self:Notify()
end

-- Debounced: Questie updates its own completed table a moment after turn-in.
local pending
function A:MarkDirty()
	self.dirty = true
	if pending then return end
	pending = true
	C_Timer.After(1.5, function()
		pending = false
		if ns.UI and ns.UI:IsShown() then A:Start(true) end
	end)
end

function A:QuestName(id)
	return (LibQuestieDB and LibQuestieDB.Quest.name(id)) or ("Quest " .. id)
end
