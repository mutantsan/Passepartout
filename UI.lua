-- Passepartout: UI
--
-- The Forever look: the game's metal portrait frame (ButtonFrameTemplate), an inset over the
-- Journeys backdrop under a dark wash, minimal scrollbar art, bronze-rimmed dark cards and a
-- quest-parchment hero card for the top destination. Every atlas is checked before use and
-- falls back to drawn bronze when this client lacks it.

local _, ns = ...
local A = ns.Analyzer
local Num, Range = ns.Num, ns.Range
local floor, format, min, max = math.floor, string.format, math.min, math.max

local UI = { cards = {}, expanded = {} }
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local FONT_NUM = "Fonts\\ARIALN.TTF"

local W, H = 500, 700
local HEADER_H = 84
local BOTTOM_H = 26
local INSET_W = W - 10
local SCROLL_L, SCROLL_R = 10, 24
local CARD_W = INSET_W - SCROLL_L - SCROLL_R - 2
local PAD = 16
local INNER = CARD_W - PAD * 2
local GAP = 12
local ROW_H = 18
local OTHER_ZONES = 5
local QUESTS_SHOWN = 4

local function rgb(hex)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
local C = {
	gold     = { 1, 0.82, 0 },
	light    = rgb("f2e6c8"),
	summary  = rgb("e6d6b0"),
	muted    = rgb("9a8f7a"),
	bronze   = rgb("c9a25a"),
	bronzeDk = rgb("6e5126"),
	rim      = rgb("6b5230"),
	field    = rgb("0a0908"),
	bandTop  = rgb("1e1b17"),
	inset    = rgb("11100e"),
	elite    = rgb("ff7f3f"),
	log      = rgb("ffd24a"),
}

local DIFF_FALLBACK = {
	impossible = { 1, 0.1, 0.1 }, verydifficult = { 1, 0.5, 0.25 }, difficult = { 1, 1, 0 },
	standard = { 0.25, 0.75, 0.25 }, trivial = { 0.5, 0.5, 0.5 },
}
local function DiffColor(key)
	local c = QuestDifficultyColors and QuestDifficultyColors[key]
	if c and c.r then return { c.r, c.g, c.b } end
	return DIFF_FALLBACK[key] or C.light
end
-- The game's difficulty colours are made for dark backgrounds; on parchment they need ink.
local DIFF_INK = {
	impossible = { 0.58, 0.03, 0.03 }, verydifficult = { 0.60, 0.22, 0.00 }, difficult = { 0.42, 0.31, 0.00 },
	standard = { 0.04, 0.32, 0.04 }, trivial = { 0.32, 0.29, 0.26 },
}
local function InkColor(key, pal)
	if pal and not pal.shadow then return DIFF_INK[key] or pal.body end
	return DiffColor(key)
end

local function Hex(c) return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- Art helpers ----------------------------------------------------------------------

local atlasKnown = {}
local function AtlasInfo(name)
	local info = atlasKnown[name]
	if info == nil then
		info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) or false
		atlasKnown[name] = info
	end
	return info or nil
end

local function Atlas(tex, name, useSize)
	if not AtlasInfo(name) then return false end
	tex:SetAtlas(name, useSize)
	return true
end

local function CoverAtlas(tex, name, w, h)
	local info = AtlasInfo(name)
	local file = info and (info.file or info.filename)
	if not (file and w > 0 and h > 0 and info.width and info.width > 0) then return false end
	local scale = max(w / info.width, h / info.height)
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local du, dv = (r - l) * w / scale / info.width, (b - t) * h / scale / info.height
	local u, v = l + ((r - l) - du) / 2, t + ((b - t) - dv) / 2
	tex:SetTexture(file)
	tex:SetTexCoord(u, u + du, v, v + dv)
	return true
end

local function Gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
	if tex.SetGradient and CreateColor then
		if pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then return end
	end
	if tex.SetGradientAlpha then tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2) end
end

local function VGrad(tex, top, bottom, aTop, aBot)
	Gradient(tex, "VERTICAL", bottom[1], bottom[2], bottom[3], aBot or 1, top[1], top[2], top[3], aTop or 1)
end

local function Solid(parent, layer, color, a, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	t:SetTexture(WHITE)
	t:SetVertexColor(color[1], color[2], color[3], a or 1)
	return t
end

local function Ring(frame, color, o, layer, a)
	o = o or 0
	local function line(p1, x1, y1, p2, x2, y2, horizontal)
		local t = Solid(frame, layer or "BORDER", color, a)
		t:SetPoint(p1, x1, y1); t:SetPoint(p2, x2, y2)
		if horizontal then t:SetHeight(1) else t:SetWidth(1) end
	end
	line("TOPLEFT", o, -o, "TOPRIGHT", -o, -o, true)
	line("BOTTOMLEFT", o, o, "BOTTOMRIGHT", -o, o, true)
	line("TOPLEFT", o, -o, "BOTTOMLEFT", o, o)
	line("TOPRIGHT", -o, -o, "BOTTOMRIGHT", -o, o)
end

local function FontString(parent, font, size, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(font, size, "")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH("LEFT")
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	return fs
end

local function SetPortrait(tex, path)
	if not tex then return end
	if SetPortraitToTexture and pcall(SetPortraitToTexture, tex, path) then return end
	tex:SetTexture(path)
end

-- Map --------------------------------------------------------------------------------

function UI.ShowOnMap(area)
	local Q = ns.Questie()
	if not Q then return end
	local ok, uiMapId = pcall(Q.Zone.GetUiMapIdByAreaId, Q.Zone, area)
	if not (ok and uiMapId and uiMapId > 0) then return end
	if Q.Compat and Q.Compat.OpenWorldMap then
		if not Q.Compat.OpenWorldMap(uiMapId) then ns.Print("The map can't open during combat.") end
	elseif OpenWorldMap then
		OpenWorldMap(uiMapId)
	end
end

-- Quest tooltip ----------------------------------------------------------------------

local function QuestTooltip(row)
	local q = row.quest
	if not q then return end
	local L = LibQuestieDB
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local dc = DiffColor(q.diff)
	GameTooltip:SetText(A:QuestName(q.id), dc[1], dc[2], dc[3])
	GameTooltip:AddDoubleLine("Quest level", tostring(q.level), 0.8, 0.8, 0.8, 1, 1, 1)
	if q.mobLo then
		GameTooltip:AddDoubleLine("Mob levels", Range(q.mobLo, q.mobHi), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if q.xp then GameTooltip:AddDoubleLine("Experience", Num(q.xp), 0.8, 0.8, 0.8, 1, 1, 1) end
	if q.elite then GameTooltip:AddLine("Elite: bring a group", C.elite[1], C.elite[2], C.elite[3]) end
	if q.ready then GameTooltip:AddLine("Ready to hand in", 0.25, 1, 0.25)
	elseif q.inLog then GameTooltip:AddLine("Already in your quest log", C.log[1], C.log[2], C.log[3]) end
	local text = L and L.Quest.objectivesText(q.id)
	if type(text) == "table" and text[1] then
		GameTooltip:AddLine(" ")
		for _, line in ipairs(text) do GameTooltip:AddLine(line, 1, 0.82, 0, true) end
	end
	local starts = L and L.Quest.startedBy(q.id)
	local npc = starts and starts[1] and starts[1][1]
	if npc then
		local name = L.Npc.name(npc)
		local zone = L.Npc.zoneID(npc)
		if name then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Starts at " .. name .. (zone and zone > 0 and (", " .. A.ZoneName(zone)) or ""), 0.7, 0.7, 0.7, true)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffd24aClick|r " .. (row.hint or "to show the zone on the map"), 0.7, 0.7, 0.7)
	GameTooltip:AddLine("|cffffd24aShift-click|r to link it in chat", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- Card canvas ------------------------------------------------------------------------

local Card = {}
local PAL = {
	dark = { title = C.gold, head = { 1, 1, 1 }, body = { 0.86, 0.84, 0.78 }, muted = { 0.62, 0.60, 0.56 }, rule = { 0.55, 0.45, 0.25 }, shadow = true },
	parchment = { title = { 0.40, 0.22, 0.02 }, head = { 0.18, 0.10, 0.02 }, body = { 0.24, 0.15, 0.07 }, muted = { 0.34, 0.25, 0.14 }, rule = { 0.45, 0.32, 0.15 }, shadow = false },
}
local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 32, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local ICON_FRAME = "Interface\\AchievementFrame\\UI-Achievement-IconFrame"
local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"

function Card:Init()
	self:SetWidth(CARD_W)
	if self.SetBackdrop then
		self:SetBackdrop(BACKDROP)
		self:SetBackdropBorderColor(0.80, 0.64, 0.34, 1)
	else
		Solid(self, "BACKGROUND", { 0.05, 0.05, 0.06 }, 0.95):SetAllPoints()
		Ring(self, { 0, 0, 0 }, -1, "BORDER")
		Ring(self, C.rim, 0, "BORDER")
	end
	self.band = self:CreateTexture(nil, "BACKGROUND", nil, 2)
	self.band:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
	self.band:SetBlendMode("ADD")
	self.band:SetPoint("TOPLEFT", 5, -5)
	self.band:SetPoint("TOPRIGHT", -5, -5)
	self.band:SetHeight(62)
	self.band:SetVertexColor(0.85, 0.62, 0.25, 0.22)
	self.paper = self:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.paper:SetPoint("TOPLEFT", 4, -4)
	self.paper:SetPoint("BOTTOMRIGHT", -4, 4)
	if not Atlas(self.paper, "QuestBG-Parchment") then
		self.paper:SetTexture(WHITE)
		self.paper:SetVertexColor(0.93, 0.86, 0.70, 1)
	end
	self.iconFrame = CreateFrame("Frame", nil, self)
	self.iconFrame:SetSize(36, 36)
	self.iconFrame:SetPoint("TOPLEFT", PAD, -PAD)
	self.art = self.iconFrame:CreateTexture(nil, "ARTWORK")
	self.art:SetPoint("CENTER")
	self.art:SetSize(32, 32)
	self.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local frame = self.iconFrame:CreateTexture(nil, "OVERLAY")
	frame:SetTexture(ICON_FRAME)
	frame:SetTexCoord(0, 0.5625, 0, 0.5625)
	frame:SetPoint("CENTER")
	frame:SetSize(50, 50)
	self.fsPool, self.txPool, self.rowPool, self.btnPool, self.hitPool = {}, {}, {}, {}, {}
end

function Card:Reset(theme, art)
	for _, p in ipairs({ self.fsPool, self.txPool, self.rowPool, self.btnPool, self.hitPool }) do
		for _, o in ipairs(p) do o:Hide() end
	end
	self.fsUsed, self.txUsed, self.rowUsed, self.btnUsed, self.hitUsed, self.y = 0, 0, 0, 0, 0, -PAD
	self.headerDone = false
	self.hasArt = art ~= nil
	theme = (theme == "parchment") and "parchment" or "dark"
	self.pal = PAL[theme]
	self.paper:SetShown(theme == "parchment")
	self.band:SetShown(theme == "dark")
	if art then self.art:SetTexture(art); self.iconFrame:Show() else self.iconFrame:Hide() end
end

function Card:FS(font, size, color)
	self.fsUsed = self.fsUsed + 1
	local fs = self.fsPool[self.fsUsed]
	if not fs then
		fs = FontString(self, font, size)
		self.fsPool[self.fsUsed] = fs
	end
	fs:SetFont(font, size, "")
	color = color or self.pal.body
	fs:SetTextColor(color[1], color[2], color[3], 1)
	fs:SetShadowColor(0, 0, 0, self.pal.shadow and 1 or 0)
	fs:ClearAllPoints()
	fs:SetJustifyH("LEFT")
	fs:SetWidth(0)
	fs:SetWordWrap(false)
	fs:SetText("")
	fs:Show()
	return fs
end

function Card:TX(layer, sub)
	self.txUsed = self.txUsed + 1
	local t = self.txPool[self.txUsed]
	if not t then
		t = self:CreateTexture(nil, "ARTWORK")
		self.txPool[self.txUsed] = t
	end
	t:SetDrawLayer(layer or "ARTWORK", sub or 0)
	t:SetTexture(WHITE)
	t:SetTexCoord(0, 1, 0, 1)
	Gradient(t, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 1)
	t:SetVertexColor(1, 1, 1, 1)
	t:SetDesaturated(false)
	t:SetBlendMode("BLEND")
	t:SetAlpha(1)
	t:ClearAllPoints()
	t:Show()
	return t
end

-- An invisible hover area (tooltips on bars and rulers).
function Card:Hit(x, y, w, h, onEnter)
	self.hitUsed = self.hitUsed + 1
	local f = self.hitPool[self.hitUsed]
	if not f then
		f = CreateFrame("Frame", nil, self)
		f:EnableMouse(true)
		f:SetScript("OnLeave", function() GameTooltip:Hide() end)
		self.hitPool[self.hitUsed] = f
	end
	f:SetScript("OnEnter", onEnter)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", x, y)
	f:SetSize(w, h)
	f:Show()
	return f
end

-- Travel poster: the zone's own world-map art, sepia and fading into the parchment.
-- Tiles are cropped by hand (textures can't be clipped) to the top band of the card.
function Card:Poster(uiMapId, height)
	if not (uiMapId and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return end
	local ok, layers = pcall(C_Map.GetMapArtLayers, uiMapId)
	local info = ok and layers and layers[1]
	if not (info and info.layerWidth and info.layerWidth > 0 and info.tileWidth and info.tileWidth > 0) then return end
	local textures = C_Map.GetMapArtLayerTextures(uiMapId, 1)
	if not (textures and #textures > 0) then return end
	local PW, PH = CARD_W - 8, height
	local scale = PW / info.layerWidth
	local offY = max(0, (info.layerHeight * scale - PH) / 2)
	local tw, th = info.tileWidth * scale, info.tileHeight * scale
	local cols = math.ceil(info.layerWidth / info.tileWidth)
	local rows = math.ceil(info.layerHeight / info.tileHeight)
	local peak = 0.42
	local function alphaAt(y) return peak * max(0, 1 - y / PH) end
	for row = 1, rows do
		for col = 1, cols do
			local file = textures[(row - 1) * cols + col]
			local x0, y0 = (col - 1) * tw, (row - 1) * th - offY
			local ix0, ix1 = max(x0, 0), min(x0 + tw, PW)
			local iy0, iy1 = max(y0, 0), min(y0 + th, PH)
			if file and ix1 > ix0 and iy1 > iy0 then
				local t = self:TX("BACKGROUND", 3)
				t:SetTexture(file)
				t:SetTexCoord((ix0 - x0) / tw, (ix1 - x0) / tw, (iy0 - y0) / th, (iy1 - y0) / th)
				t:SetPoint("TOPLEFT", 4 + ix0, -(4 + iy0))
				t:SetSize(ix1 - ix0, iy1 - iy0)
				t:SetDesaturated(true)
				local r, g, b = 0.55, 0.40, 0.22
				Gradient(t, "VERTICAL", r, g, b, alphaAt(iy1), r, g, b, alphaAt(iy0))
			end
		end
	end
end

function Card:Space(h) self.y = self.y - h end

function Card:Divider()
	local line = self:TX("ARTWORK")
	if Atlas(line, "Options_HorizontalDivider") then
		line:SetHeight(2)
	else
		line:SetVertexColor(self.pal.rule[1], self.pal.rule[2], self.pal.rule[3], 1)
		line:SetHeight(1)
	end
	line:SetWidth(INNER)
	line:SetPoint("TOPLEFT", PAD, self.y)
end

function Card:Kicker(text, scope)
	if not self.headerDone then
		self.headerDone = true
		local x = self.hasArt and (PAD + 48) or PAD
		local title = self:FS(FONT, 14, self.pal.title)
		title:SetText(text)
		title:SetPoint("TOPLEFT", x, -PAD - (scope and 2 or 10))
		if scope then
			local s = self:FS(FONT, 10, self.pal.muted)
			s:SetText(scope:upper())
			s:SetPoint("TOPLEFT", x, -PAD - 21)
		end
		self.y = -PAD - 46
		self:Divider()
		self.y = self.y - 12
		return title
	end
	self:Space(4)
	local fs = self:FS(FONT, 12, self.pal.title)
	fs:SetText(text)
	fs:SetPoint("TOPLEFT", PAD, self.y)
	self.y = self.y - 20
	return fs
end

function Card:Text(text, size, color, font, wrap)
	local fs = self:FS(font or FONT, size or 12, color or self.pal.body)
	fs:SetWidth(INNER)
	fs:SetWordWrap(wrap ~= false)
	fs:SetText(text)
	fs:SetPoint("TOPLEFT", PAD, self.y)
	self.y = self.y - fs:GetStringHeight() - 6
	return fs
end

function Card:Bar(label, value, maxValue, right, color)
	local l = self:FS(FONT, 11, self.pal.head)
	l:SetText(label)
	l:SetPoint("TOPLEFT", PAD, self.y)
	l:SetWidth(INNER - 130)
	local r = self:FS(FONT_NUM, 12, self.pal.muted)
	r:SetJustifyH("RIGHT")
	r:SetText(right)
	r:SetPoint("TOPRIGHT", -PAD, self.y)
	self.y = self.y - 15
	local track = self:TX("ARTWORK", 0)
	track:SetVertexColor(0, 0, 0, 0.45)
	track:SetPoint("TOPLEFT", PAD, self.y)
	track:SetSize(INNER, 5)
	local fill = self:TX("ARTWORK", 1)
	fill:SetTexture(STATUSBAR)
	color = color or C.bronze
	fill:SetVertexColor(color[1], color[2], color[3], 1)
	fill:SetPoint("TOPLEFT", PAD, self.y)
	fill:SetSize(max(1, INNER * min(1, value / max(1, maxValue))), 5)
	self.y = self.y - 12
end

local DIFF_NAMES = {
	{ "standard", "Easy" }, { "difficult", "At your level" }, { "verydifficult", "Tough" },
}

local function ZoneTooltip(owner, b, level)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText(b.name, 1, 0.82, 0)
	GameTooltip:AddDoubleLine("Quest levels", Range(b.qLo, b.qHi), 0.8, 0.8, 0.8, 1, 1, 1)
	if not b.questLevels then GameTooltip:AddDoubleLine("Mob levels", Range(b.mobLo, b.mobHi), 0.8, 0.8, 0.8, 1, 1, 1) end
	GameTooltip:AddDoubleLine("Your level", tostring(level), 0.8, 0.8, 0.8, C.log[1], C.log[2], C.log[3])
	GameTooltip:AddLine(" ")
	for _, d in ipairs(DIFF_NAMES) do
		local n = b.colors[d[1]] or 0
		if n > 0 then
			local c = DiffColor(d[1])
			GameTooltip:AddDoubleLine(d[2], tostring(n), c[1], c[2], c[3], 1, 1, 1)
		end
	end
	if b.elite > 0 then GameTooltip:AddDoubleLine("Elite (group)", tostring(b.elite), C.elite[1], C.elite[2], C.elite[3], 1, 1, 1) end
	if b.inLog > 0 then GameTooltip:AddDoubleLine("In your log", tostring(b.inLog), C.log[1], C.log[2], C.log[3], 1, 1, 1) end
	GameTooltip:Show()
end

-- Level chart: one column per quest level, as tall as the number of quests left at that
-- level and coloured by difficulty, on a hairline baseline with a gold marker at your level.
local CHART_H = 18

function Card:Ruler(b, level, labelled)
	local qLo, qHi = b.qLo or level, b.qHi or level
	local a, z = min(qLo, level) - 2, max(qHi, level) + 2
	local cols = z - a + 1
	local cw = INNER / cols
	local peak = 1
	for _, n in pairs(b.byLevel or {}) do peak = max(peak, n) end
	local top = self.y
	if labelled then self.y = self.y - 13 end
	local base = self.y - CHART_H - 2           -- baseline y

	for lv = a, z do
		local n = b.byLevel and b.byLevel[lv]
		if n then
			local h = 4 + (CHART_H - 4) * n / peak
			local col = self:TX("ARTWORK", 1)
			local c = InkColor(A.Difficulty(lv, level), self.pal)
			col:SetVertexColor(c[1], c[2], c[3], 0.95)
			col:SetPoint("BOTTOMLEFT", self, "TOPLEFT", PAD + (lv - a) * cw + 1, base + 1)
			col:SetSize(max(2, cw - 2), h)
		end
	end
	local line = self:TX("ARTWORK", 0)
	local rc = self.pal.rule
	line:SetVertexColor(rc[1], rc[2], rc[3], 0.9)
	line:SetPoint("TOPLEFT", PAD, base)
	line:SetSize(INNER, 1)

	-- You: a gold post through your level's column.
	local mx = PAD + (level - a + 0.5) * cw
	local shade = self:TX("ARTWORK", 2)
	shade:SetVertexColor(0, 0, 0, self.pal.shadow and 0.7 or 0.25)
	shade:SetPoint("BOTTOMLEFT", self, "TOPLEFT", mx - 2, base - 3)
	shade:SetSize(4, CHART_H + 7)
	local post = self:TX("ARTWORK", 3)
	post:SetVertexColor(C.log[1] * (self.pal.shadow and 1 or 0.7), C.log[2] * (self.pal.shadow and 1 or 0.55), 0, 1)
	post:SetPoint("BOTTOMLEFT", self, "TOPLEFT", mx - 1, base - 2)
	post:SetSize(2, CHART_H + 5)
	if labelled then
		local you = self:FS(FONT, 9, self.pal.title)
		you:SetText("YOU " .. level)
		you:SetPoint("BOTTOM", self, "TOPLEFT", mx, base + CHART_H + 5)
	end

	-- Quest level range under the baseline.
	local function Label(lv)
		local fs = self:FS(FONT_NUM, 10, self.pal.muted)
		fs:SetText(tostring(lv))
		fs:SetPoint("TOP", self, "TOPLEFT", PAD + (lv - a + 0.5) * cw, base - 3)
	end
	Label(qLo)
	if qHi ~= qLo then Label(qHi) end

	self.y = base - 18
	self:Hit(PAD, top, INNER, top - self.y, function(f) ZoneTooltip(f, b, level) end)
end

-- Rows are pooled and shared by quest lines and text links, so every use resets them.
function Card:NewRow()
	self.rowUsed = self.rowUsed + 1
	local row = self.rowPool[self.rowUsed]
	if not row then
		row = CreateFrame("Button", nil, self)
		row:SetSize(INNER, ROW_H)
		row.hl = row:CreateTexture(nil, "HIGHLIGHT")
		row.hl:SetAllPoints()
		row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
		row.hl:SetBlendMode("ADD")
		row.hl:SetVertexColor(0.85, 0.62, 0.25, 0.35)
		row:RegisterForClicks("LeftButtonUp")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(13, 13)
		row.icon:SetPoint("LEFT", 0, 0)
		row.lvl = FontString(row, FONT_NUM, 12)
		row.lvl:SetPoint("LEFT", 16, 0)
		row.lvl:SetWidth(28)
		row.name = FontString(row, FONT, 11)
		row.name:SetPoint("LEFT", 46, 0)
		row.name:SetWordWrap(false)
		row.right = FontString(row, FONT_NUM, 11)
		row.right:SetPoint("RIGHT", -2, 0)
		row.right:SetJustifyH("RIGHT")
		self.rowPool[self.rowUsed] = row
	end
	local shadow = self.pal.shadow and 1 or 0
	for _, fs in ipairs({ row.lvl, row.name, row.right }) do fs:SetShadowColor(0, 0, 0, shadow); fs:SetText("") end
	row.quest, row.hint = nil, nil
	row:SetHeight(ROW_H)
	row.name:SetPoint("LEFT", 46, 0)
	row.icon:Hide()
	row:SetScript("OnEnter", nil)
	row:SetScript("OnLeave", nil)
	row:SetScript("OnClick", nil)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", PAD, self.y)
	row:Show()
	self.y = self.y - ROW_H
	return row
end

local ICON_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_ACTIVE = "Interface\\GossipFrame\\ActiveQuestIcon"

local function EliteMark()
	if AtlasInfo("nameplates-icon-elite-gold") then return "|A:nameplates-icon-elite-gold:13:13|a" end
	return Hex(C.elite) .. "Elite|r"
end

local function QuestLink(q)
	local name = A:QuestName(q.id)
	return format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", q.id, q.level, name)
end

local function QuestClick(row)
	local q = row.quest
	if not q then return end
	if IsShiftKeyDown() then
		local link = QuestLink(q)
		if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
	elseif q.area then
		UI.ShowOnMap(q.area)
	end
end

-- A hoverable, clickable quest line: (icon) [level] name ... mobs / xp
-- onClick replaces the default (show the zone on the map); hint is its tooltip wording.
function Card:QuestRow(q, rightText, onClick, hint)
	local row = self:NewRow()
	row.quest, row.hint = q, hint
	row:SetScript("OnEnter", QuestTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", onClick and function(rw)
		if IsShiftKeyDown() then QuestClick(rw) else onClick(rw.quest) end
	end or QuestClick)
	-- Yellow "!" to pick up; "?" in your log, gold when ready to hand in, grey while in progress.
	row.icon:SetTexture(q.inLog and ICON_ACTIVE or ICON_AVAILABLE)
	row.icon:SetDesaturated(q.inLog and not q.ready or false)
	row.icon:SetAlpha(q.inLog and not q.ready and 0.75 or 1)
	row.icon:Show()
	local dc = InkColor(q.diff, self.pal)
	row.lvl:SetTextColor(dc[1], dc[2], dc[3])
	row.lvl:SetText("[" .. q.level .. "]")
	local name = A:QuestName(q.id)
	if q.elite then name = EliteMark() .. " " .. name end
	row.name:SetText(name)
	local nc = self.pal.head
	row.name:SetTextColor(nc[1], nc[2], nc[3])
	local text = rightText
	if not text then
		local bits = {}
		if q.mobLo then bits[#bits + 1] = "mobs " .. Range(q.mobLo, q.mobHi) end
		if q.xp then bits[#bits + 1] = Num(q.xp) .. " xp" end
		text = table.concat(bits, "  \194\183  ")
	end
	row.right:SetText(text)
	local mc = self.pal.muted
	row.right:SetTextColor(mc[1], mc[2], mc[3])
	row.name:SetWidth(max(60, INNER - 50 - row.right:GetStringWidth() - 8))
	return row
end

-- A standard red-metal UI button.
function Card:Button(text, onClick, anchorRight)
	self.btnUsed = self.btnUsed + 1
	local b = self.btnPool[self.btnUsed]
	if not b then
		local ok, made = pcall(CreateFrame, "Button", nil, self, "UIPanelButtonTemplate")
		b = ok and made or CreateFrame("Button", nil, self)
		if not ok then
			b:SetNormalFontObject(GameFontNormalSmall)
			Solid(b, "BACKGROUND", C.bandTop, 1):SetAllPoints()
			Ring(b, C.bronze, 0, "BORDER")
		end
		b:SetHeight(22)
		self.btnPool[self.btnUsed] = b
	end
	b:SetText(text)
	local fs = b:GetFontString()
	b:SetWidth(max(90, (fs and fs:GetStringWidth() or 60) + 28))
	b:SetScript("OnClick", onClick)
	b:ClearAllPoints()
	if anchorRight then b:SetPoint("TOPRIGHT", -PAD, self.y) else b:SetPoint("TOPLEFT", PAD, self.y) end
	b:Show()
	return b
end

-- Small text link (expand/collapse).
function Card:Link(text, onClick)
	local row = self:NewRow()
	row.name:SetWidth(INNER - 50)
	row.name:SetText(text)
	row.name:SetTextColor(self.pal.title[1], self.pal.title[2], self.pal.title[3])
	row:SetScript("OnClick", onClick)
end

function Card:Finish()
	self:SetHeight(-self.y + PAD - 4)
end

function UI:NewCard(theme, art)
	self.cardIdx = self.cardIdx + 1
	local c = self.cards[self.cardIdx]
	if not c then
		c = CreateFrame("Frame", nil, self.content, BackdropTemplateMixin and "BackdropTemplate" or nil)
		for k, v in pairs(Card) do c[k] = v end
		c:Init()
		self.cards[self.cardIdx] = c
	end
	c:Reset(theme, art)
	c:Show()
	return c
end

-- Window chrome ----------------------------------------------------------------------

local function TryTemplate(name, template)
	local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, template)
	if ok and frame and frame.Inset and frame.CloseButton then return frame end
	if ok and frame then frame:Hide() end
	return nil
end

local function DrawnChrome(f)
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
	bg:SetHorizTile(true); bg:SetVertTile(true)
	bg:SetVertexColor(0.55, 0.55, 0.55, 1)
	bg:SetAllPoints()
	local bar = Solid(f, "BACKGROUND", C.bandTop, 1, -7)
	bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(22)
	Ring(f, { 0, 0, 0 }, -1, "BORDER")
	Ring(f, C.bronzeDk, -2, "BORDER")
	Ring(f, C.bronze, -3, "BORDER")
	Ring(f, { 0, 0, 0 }, -4, "BORDER")
	f.TitleText = FontString(f, FONT, 12, C.gold)
	f.TitleText:SetPoint("TOP", 0, -5)
	local close = CreateFrame("Button", nil, f)
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -2, 0)
	if pcall(close.SetNormalAtlas, close, "RedButton-Exit") and AtlasInfo("RedButton-Exit") then
		pcall(close.SetPushedAtlas, close, "RedButton-exit-pressed")
		pcall(close.SetHighlightAtlas, close, "RedButton-Highlight", "ADD")
	else
		local fill = close:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(); fill:SetTexture(WHITE)
		Gradient(fill, "VERTICAL", 0.35, 0.02, 0.01, 1, 0.72, 0.10, 0.06, 1)
		Ring(close, C.bronze, 0, "BORDER")
		local x = FontString(close, FONT, 12, { 1, 0.83, 0.29 })
		x:SetPoint("CENTER", 0, 1); x:SetText("X")
	end
	close:SetScript("OnClick", function() f:Hide() end)
	f.CloseButton = close
	local inset = CreateFrame("Frame", nil, f)
	Solid(inset, "BACKGROUND", C.inset, 1):SetAllPoints()
	Ring(inset, { 0, 0, 0 }, 0, "BORDER")
	Ring(inset, C.rim, -1, "BORDER")
	f.Inset = inset
end

local function ThreePiece(parent, names, layer, fallback)
	local top, mid, bot = parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer)
	local ok = AtlasInfo(names[1]) and AtlasInfo(names[2]) and AtlasInfo(names[3])
	if ok then
		top:SetAtlas(names[1], true); bot:SetAtlas(names[3], true); mid:SetAtlas(names[2])
		top:SetPoint("TOP"); bot:SetPoint("BOTTOM")
		mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
	else
		top:Hide(); bot:Hide()
		mid:SetTexture(WHITE)
		mid:SetVertexColor(fallback[1], fallback[2], fallback[3], fallback[4] or 1)
		mid:SetPoint("TOP"); mid:SetPoint("BOTTOM"); mid:SetWidth(4)
	end
end

function UI:Create()
	local f = TryTemplate("PassepartoutFrame", "ButtonFrameTemplate")
	local native = f ~= nil
	if not f then
		f = CreateFrame("Frame", "PassepartoutFrame", UIParent)
		DrawnChrome(f)
	end
	self.frame = f
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		ns.db.window.point = { point, rel, x, y }
	end)
	f:ClearAllPoints()
	local pos = ns.db.window.point
	if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
	f:Hide()
	tinsert(UISpecialFrames, "PassepartoutFrame")

	if f.SetTitle then f:SetTitle("Passepartout") elseif f.TitleText then f.TitleText:SetText("Passepartout") end
	SetPortrait(f.PortraitContainer and f.PortraitContainer.portrait or f.portrait, ns.ICON)

	local inset = f.Inset
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -HEADER_H)
	inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, BOTTOM_H)
	local art = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
	art:SetPoint("TOPLEFT", 3, -3)
	art:SetPoint("BOTTOMRIGHT", -3, 3)
	if CoverAtlas(art, "ui-journeys-bg", INSET_W - 6, H - HEADER_H - BOTTOM_H - 6) then
		local wash = inset:CreateTexture(nil, "BACKGROUND", nil, 2)
		wash:SetTexture(WHITE)
		wash:SetAllPoints(art)
		VGrad(wash, { 0, 0, 0 }, { 0, 0, 0 }, 0.35, 0.75)
	else
		art:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
		art:SetHorizTile(true); art:SetVertTile(true)
		art:SetVertexColor(0.35, 0.35, 0.35, 1)
	end

	-- Header.
	local textX = native and 66 or 14
	self.name = FontString(f, FONT, 18, C.light)
	self.name:SetPoint("TOPLEFT", textX, -30)
	self.name:SetWidth(W - textX - 60)
	self.name:SetWordWrap(false)
	self.sub = FontString(f, FONT, 11, C.summary)
	self.sub:SetPoint("TOPLEFT", textX, -54)
	self.sub:SetWidth(W - textX - 60)
	self.sub:SetWordWrap(false)

	local refresh = CreateFrame("Button", nil, f)
	refresh:SetSize(26, 26)
	refresh:SetPoint("TOPRIGHT", -12, -34)
	refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
	refresh:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
	local pushed = refresh:GetPushedTexture()
	if pushed then pushed:SetTexCoord(-0.05, 1.05, -0.05, 1.05); pushed:SetVertexColor(0.7, 0.7, 0.7) end
	refresh:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	refresh:SetScript("OnClick", function() A:Start(true) end)
	local spinTex = refresh:GetNormalTexture()
	if spinTex and spinTex.CreateAnimationGroup then
		local ag = spinTex:CreateAnimationGroup()
		local rot = ag:CreateAnimation("Rotation")
		rot:SetDegrees(-360)
		rot:SetDuration(1.1)
		ag:SetLooping("REPEAT")
		self.spin = ag
	end
	refresh:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Rescan")
		GameTooltip:AddLine("Check your quests again.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Scroll area.
	local sf = CreateFrame("ScrollFrame", nil, inset)
	sf:SetPoint("TOPLEFT", SCROLL_L, -8)
	sf:SetPoint("BOTTOMRIGHT", -SCROLL_R, 8)
	sf:EnableMouseWheel(true)
	self.scroll = sf
	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(CARD_W, 1)
	sf:SetScrollChild(content)
	self.content = content
	self.scrollTarget, self.scrollCur = 0, 0
	sf:SetScript("OnMouseWheel", function(_, delta)
		local range = sf:GetVerticalScrollRange()
		UI.scrollTarget = max(0, min(range, UI.scrollTarget - delta * 80))
	end)

	local track = CreateFrame("Frame", nil, inset)
	track:SetPoint("TOPRIGHT", -8, -10)
	track:SetPoint("BOTTOMRIGHT", -8, 10)
	track:SetWidth(8)
	ThreePiece(track, { "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom" },
		"ARTWORK", { C.field[1], C.field[2], C.field[3], 1 })
	self.track = track
	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(8)
	thumb:SetFrameLevel(track:GetFrameLevel() + 2)
	ThreePiece(thumb, { "minimal-scrollbar-small-thumb-top", "minimal-scrollbar-small-thumb-middle",
		"minimal-scrollbar-small-thumb-bottom" }, "OVERLAY", { C.bronze[1], C.bronze[2], C.bronze[3], 0.9 })
	thumb:SetScript("OnMouseDown", function(self)
		local _, cy = GetCursorPosition()
		self.dragging = { cy = cy / self:GetEffectiveScale(), scroll = UI.scrollCur }
	end)
	thumb:SetScript("OnMouseUp", function(self) self.dragging = nil end)
	self.thumb = thumb

	local fadeTop = inset:CreateTexture(nil, "OVERLAY")
	fadeTop:SetTexture(WHITE)
	fadeTop:SetPoint("TOPLEFT", sf, "TOPLEFT", -SCROLL_L + 4, 8)
	fadeTop:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 8)
	fadeTop:SetHeight(16)
	VGrad(fadeTop, { 0, 0, 0 }, { 0, 0, 0 }, 0.7, 0)
	local fadeBottom = inset:CreateTexture(nil, "OVERLAY")
	fadeBottom:SetTexture(WHITE)
	fadeBottom:SetPoint("BOTTOMLEFT", sf, "BOTTOMLEFT", -SCROLL_L + 4, -8)
	fadeBottom:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, -8)
	fadeBottom:SetHeight(18)
	VGrad(fadeBottom, { 0, 0, 0 }, { 0, 0, 0 }, 0, 0.7)

	self.footLeft = FontString(f, FONT, 10, C.muted)
	self.footLeft:SetPoint("BOTTOMLEFT", 14, 8)
	self.footRight = FontString(f, FONT, 10, C.muted)
	self.footRight:SetPoint("BOTTOMRIGHT", -14, 8)
	self.footRight:SetJustifyH("RIGHT")

	f:SetScript("OnUpdate", function(_, elapsed) UI:OnUpdate(elapsed) end)
	f:SetScript("OnShow", function()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839) end
	end)
	f:SetScript("OnHide", function()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840) end
	end)

	self:CreateTabs()

	-- Background rescans are quiet: the cards stay put, the refresh icon spins and the
	-- footer counts up. Only a first read (nothing to show yet) uses the progress card.
	A:OnChange(function(state)
		if not UI:IsShown() then return end
		UI:SetBusy(state == "scanning")
		if state == "scanning" then
			if A.result then
				UI:Footer()
			elseif UI.progressFill then
				UI:UpdateProgress()
			else
				UI:Refresh(false)
			end
		else
			UI:Refresh(UI.firstReveal)
			UI.firstReveal = false
		end
	end)
end

function UI:OnUpdate(elapsed)
	local sf, thumb, track = self.scroll, self.thumb, self.track
	local range = sf:GetVerticalScrollRange()
	local trackH = track:GetHeight()
	if thumb.dragging then
		local _, cy = GetCursorPosition()
		cy = cy / thumb:GetEffectiveScale()
		local room = trackH - thumb:GetHeight()
		if room > 0 then
			self.scrollTarget = max(0, min(range, thumb.dragging.scroll + (thumb.dragging.cy - cy) / room * range))
			self.scrollCur = self.scrollTarget
		end
	end
	self.scrollTarget = min(self.scrollTarget, range)
	if math.abs(self.scrollTarget - self.scrollCur) > 0.5 then
		self.scrollCur = self.scrollCur + (self.scrollTarget - self.scrollCur) * min(1, elapsed * 12)
	else
		self.scrollCur = self.scrollTarget
	end
	sf:SetVerticalScroll(self.scrollCur)
	if range > 1 then
		local viewH = sf:GetHeight()
		local th = max(40, trackH * viewH / (viewH + range))
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -(self.scrollCur / range) * (trackH - th))
		track:Show()
		self:ShiftCards(0)
	else
		track:Hide()
		-- No scrollbar: give its gutter back so the margins match on both sides.
		self:ShiftCards(floor((SCROLL_R - SCROLL_L) / 2))
	end
	if self.fadeStart then
		local t = GetTime() - self.fadeStart
		local done = true
		for i = 1, self.cardIdx do
			local a = max(0, min(1, (t - min(i - 1, 6) * 0.06) / 0.35))
			self.cards[i]:SetAlpha(1 - (1 - a) ^ 3)
			if a < 1 then done = false end
		end
		if done then self.fadeStart = nil end
	end
end

function UI:IsShown() return self.frame and self.frame:IsShown() end

function UI:SetBusy(busy)
	if not self.spin then return end
	if busy and not self.spin:IsPlaying() then self.spin:Play()
	elseif not busy and self.spin:IsPlaying() then self.spin:Stop() end
end

-- Tabs ------------------------------------------------------------------------------

local TABS = { "Where to go", "Journey" }

local function TemplateExists(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

function UI:CreateTabs()
	local f = self.frame
	local template
	for _, t in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }) do
		if TemplateExists(t) then template = t; break end
	end
	f.Tabs = {}
	for i, label in ipairs(TABS) do
		local tab
		if template then
			tab = CreateFrame("Button", "PassepartoutFrameTab" .. i, f, template)
		else
			tab = CreateFrame("Button", "PassepartoutFrameTab" .. i, f, "UIPanelButtonTemplate")
			tab:SetSize(110, 24)
		end
		tab:SetID(i)
		tab:SetText(label)
		if template and PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
		tab:SetScript("OnClick", function(b) UI:SelectTab(b:GetID()) end)
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
		else
			tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", template and -14 or 4, 0)
		end
		f.Tabs[i] = tab
	end
	self.tabsTemplated = template ~= nil
	if self.tabsTemplated and PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #TABS) end
	self.tab = 1
	if self.tabsTemplated and PanelTemplates_SetTab then PanelTemplates_SetTab(f, 1) end
end

function UI:SelectTab(i)
	self.tab = i
	self.nav = nil
	if self.tabsTemplated and PanelTemplates_SetTab then PanelTemplates_SetTab(self.frame, i) end
	if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB or 841) end
	self.scrollTarget, self.scrollCur = 0, 0
	self:Refresh(true)
end

function UI:Toggle()
	if not self.frame then self:Create() end
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self.scrollTarget, self.scrollCur = 0, 0
		A:Rerank()
		-- Fade the cards in on the first reveal only, not on every quiet update after it.
		self.firstReveal = not A.result
		self:Refresh(A.result ~= nil)
		A:Start(false)
	end
end

-- Content ----------------------------------------------------------------------------

local function LevelsWorth(xp, r)
	if not r.xpMax or r.xpMax <= 0 then return nil end
	return xp / r.xpMax
end

local function Capitalize(s) return (s:gsub("^%l", string.upper)) end

-- "A.", "A and b.", "A, b, and c."
local function Sentence(reasons)
	local n = #reasons
	if n == 0 then return nil end
	if n == 1 then return Capitalize(reasons[1]) .. "." end
	if n == 2 then return Capitalize(reasons[1]) .. " and " .. reasons[2] .. "." end
	local head = {}
	for k = 1, n - 1 do head[k] = reasons[k] end
	return Capitalize(table.concat(head, ", ")) .. ", and " .. reasons[n] .. "."
end

local FAR_NOTE = "It's on the other continent."

local function StatLine(b, r)
	local bits = {}
	bits[#bits + 1] = format("%d quest%s, level %s", #b.quests, #b.quests == 1 and "" or "s", Range(b.qLo, b.qHi))
	if not b.questLevels then bits[#bits + 1] = "mobs " .. Range(b.mobLo, b.mobHi) end
	if b.xp > 0 then
		bits[#bits + 1] = Num(b.xp) .. " xp"
		local lv = LevelsWorth(b.xp, r)
		if lv and lv >= 0.1 then bits[#bits + 1] = format("\226\137\136 %.1f level%s", lv, lv >= 0.95 and lv < 1.05 and "" or "s") end
	end
	return table.concat(bits, "   \194\183   ")
end

local function QuestList(card, b, limit, key)
	key = key or b.area
	local expanded = UI.expanded[key]
	local n = expanded and #b.quests or min(limit, #b.quests)
	for i = 1, n do card:QuestRow(b.quests[i]) end
	if #b.quests > limit then
		card:Link(expanded and "Show fewer" or format("Show all %d quests", #b.quests), function()
			UI.expanded[key] = not UI.expanded[key]
			UI:Refresh(false)
		end)
	end
end

function UI:Header()
	-- Forever characters have a first name and a surname; UnitName returns both.
	local first, surname = UnitName("player")
	local function readable(v)
		return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
	end
	local name = readable(first) and first or nil
	if name and readable(surname) then name = name .. " " .. surname end
	local level = UnitLevel("player")
	self.name:SetText(format("Where to next, %s?", name or "adventurer"))
	local r = A.result
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	local bits = { "Level " .. level }
	if r then bits[#bits + 1] = Num(r.completed) .. " quests completed" end
	if xpMax and xpMax > 0 then bits[#bits + 1] = format("%d%% to %d", floor(xp / xpMax * 100), level + 1) end
	self.sub:SetText(table.concat(bits, "   \194\183   "))
end

function UI:Footer()
	local r = A.result
	if A.state == "scanning" and r then
		self.footLeft:SetText(format("Updating... %d%%", floor((A.progress or 0) * 100)))
	elseif r then
		self.footLeft:SetText(format("Updated %s", date("%H:%M", r.time)))
	else
		self.footLeft:SetText("")
	end
	if not r then self.footRight:SetText("")
	elseif self.tab == 2 then self.footRight:SetText(format("%d of %d zones quested in", #r.history, #(r.atlas or {})))
	else self.footRight:SetText(format("%d zones checked", #r.zones)) end
end

function UI:UpdateProgress()
	if not self.progressFill then return end
	self.progressFill:SetWidth(max(1, INNER * (A.progress or 0)))
	self.progressText:SetText(format("Reading your quests... %d%%", floor((A.progress or 0) * 100)))
end

function UI:Refresh(animate)
	if not self.frame then return end
	self.cardIdx = 0
	self.progressFill = nil
	self.itemsPending = false
	self:Header()
	local r = A.result

	if A.state == "waiting" then
		local c = self:NewCard("dark", "Interface\\Icons\\INV_Misc_PocketWatch_01")
		c:Kicker("Waiting for Questie")
		c:Text("Passepartout uses Questie's quest data and starts once Questie has loaded.")
		c:Finish()
	elseif A.state == "error" then
		local c = self:NewCard("dark", "Interface\\Icons\\INV_Misc_QuestionMark")
		c:Kicker("Something went wrong")
		c:Text(tostring(A.error), 11, C.muted)
		c:Finish()
	elseif not r and A.state == "scanning" then
		self:ScanCard()
	end

	if r then
		if self.tab == 2 then
			self:Journey(r)
		else
			self:Hero(r)
			self:Others(r)
			self:LooseEnds(r)
			self:Dungeons(r)
			self:Upcoming(r)
		end
	end
	self:Footer()
	self:Layout(animate)
end

function UI:ScanCard()
	local c = self:NewCard("dark", "Interface\\Icons\\INV_Misc_Book_09")
	c:Kicker("Reading your quests")
	local track = c:TX("ARTWORK", 0)
	track:SetVertexColor(0, 0, 0, 0.5)
	track:SetPoint("TOPLEFT", PAD, c.y)
	track:SetSize(INNER, 8)
	local fill = c:TX("ARTWORK", 1)
	fill:SetTexture(STATUSBAR)
	fill:SetVertexColor(C.bronze[1], C.bronze[2], C.bronze[3], 1)
	fill:SetPoint("TOPLEFT", PAD, c.y)
	fill:SetHeight(8)
	c:Space(16)
	self.progressFill = fill
	self.progressText = c:Text("", 11, C.muted)
	c:Finish()
	self:UpdateProgress()
end

function UI:Hero(r)
	local b = r.zones[1]
	local c = self:NewCard("parchment", "Interface\\Icons\\INV_Misc_Map_01")
	if not b then
		c:Kicker("Nothing to suggest")
		c:Text("No quests at your level right now. Try a dungeon, grind a bit, or check the quests coming up below.")
		c:Finish()
		return
	end
	c:Poster(A.UiMapId(b.area), 200)
	c:Kicker("Best zone right now", b.current and "you are here" or "suggested")
	c:Text(b.name, 24, c.pal.head, FONT, false)
	c:Text(StatLine(b, r), 12, c.pal.title, FONT_NUM, false)
	local why = Sentence(b.reasons)
	if why then c:Text(why, 12, c.pal.body) end
	if b.far then c:Text(FAR_NOTE, 11, c.pal.muted) end
	c:Space(4)
	c:Ruler(b, r.level, true)
	c:Space(2)
	QuestList(c, b, 6)
	c:Space(8)
	c:Button("Show on map", function() UI.ShowOnMap(b.area) end)
	c:Space(26)
	c:Finish()
end

local function OtherZone(c, b, r, label, first)
	if not first then c:Space(6); c:Divider(); c:Space(10) end
	local tag = ""
	if b.current then tag = "  " .. Hex(C.log) .. "(you are here)|r"
	elseif b.far then tag = "  " .. Hex(C.muted) .. "(other continent)|r" end
	local title = c:FS(FONT, 14, C.light)
	title:SetText(format("%s%s|r  %s%s", Hex(C.bronze), label, b.name or "?", tag))
	title:SetPoint("TOPLEFT", PAD, c.y)
	title:SetWidth(INNER - 70)
	local map = c:Button("Map", function() UI.ShowOnMap(b.area) end, true)
	map:SetWidth(60)
	map:SetPoint("TOPRIGHT", -PAD, c.y + 3)
	c:Space(20)
	if #b.quests > 0 then c:Text(StatLine(b, r), 11, C.summary, FONT_NUM, false) end
	local why = Sentence(b.reasons or {})
	if why then c:Text(why, 11, c.pal.muted) end
	if #b.quests > 0 then
		c:Ruler(b, r.level, false)
		QuestList(c, b, QUESTS_SHOWN)
	end
end

function UI:Others(r)
	local shown = min(#r.zones, OTHER_ZONES + 1)
	local here = r.here
	if here and r.hereRank and r.hereRank <= shown then here = nil end
	if shown < 2 and not here then return end
	local c = self:NewCard("dark", "Interface\\Icons\\INV_Misc_Spyglass_02")
	c:Kicker("Other good zones", "by experience at your level")
	for i = 2, shown do OtherZone(c, r.zones[i], r, i .. ".", i == 2) end
	if here then OtherZone(c, here, r, r.hereRank and (r.hereRank .. ".") or "\226\128\148", shown < 2) end
	c:Finish()
end

function UI:LooseEnds(r)
	local list = r.leftovers
	if not list or #list == 0 then return end
	local c = self:NewCard("dark", "Interface\\Icons\\INV_Letter_15")
	c:Kicker("Quests to finish", "low level, still in your log")
	c:Text("Easy experience if you're passing by.", 11, c.pal.muted)
	local key = "leftovers"
	local limit = 5
	local expanded = UI.expanded[key]
	for i = 1, expanded and #list or min(limit, #list) do
		local q = list[i]
		c:QuestRow(q, A.ZoneName(q.area) .. (q.xp and ("  \194\183  " .. Num(q.xp) .. " xp") or ""))
	end
	if #list > limit then
		c:Link(expanded and "Show fewer" or format("Show all %d", #list), function()
			UI.expanded[key] = not UI.expanded[key]
			UI:Refresh(false)
		end)
	end
	c:Finish()
end

function UI:Dungeons(r)
	if #r.dungeons == 0 then return end
	local c = self:NewCard("dark", "Interface\\Icons\\INV_Misc_Key_10")
	c:Kicker("Dungeons", "for a group of five")
	for i = 1, min(#r.dungeons, 4) do
		local b = r.dungeons[i]
		if i > 1 then c:Space(4) end
		local t = c:FS(FONT, 13, C.light)
		t:SetText(b.name)
		t:SetPoint("TOPLEFT", PAD, c.y)
		t:SetWidth(INNER - 160)
		local s = c:FS(FONT_NUM, 12, c.pal.muted)
		s:SetJustifyH("RIGHT")
		s:SetText(format("mobs %s  \194\183  %d quest%s", Range(b.mobLo, b.mobHi), #b.quests, #b.quests == 1 and "" or "s"))
		s:SetPoint("TOPRIGHT", -PAD, c.y)
		c:Space(18)
		QuestList(c, b, 3)
	end
	c:Finish()
end

function UI:Upcoming(r)
	if #r.upcoming == 0 then return end
	local c = self:NewCard("dark", "Interface\\Icons\\INV_Misc_PocketWatch_02")
	c:Kicker("Coming up", "within three levels")
	for i = 1, min(#r.upcoming, 5) do
		local s = r.upcoming[i]
		local t = c:FS(FONT, 12, C.light)
		t:SetText(s.name)
		t:SetPoint("TOPLEFT", PAD, c.y)
		t:SetWidth(INNER - 150)
		local n = c:FS(FONT_NUM, 12, c.pal.muted)
		n:SetJustifyH("RIGHT")
		n:SetText(format("%d new quest%s from level %d", #s.quests, #s.quests == 1 and "" or "s", s.req))
		n:SetPoint("TOPRIGHT", -PAD, c.y)
		c:Space(18)
	end
	c:Finish()
end

-- Journey: every zone, then a zone's open quests, then one quest. A small stack of pages
-- on this tab; Back returns to where you were scrolled.

function UI:Push(page)
	self.nav = self.nav or {}
	local top = self.nav[#self.nav]
	if top then top.scroll = self.scrollTarget else self.overviewScroll = self.scrollTarget end
	self.nav[#self.nav + 1] = page
	self.scrollTarget, self.scrollCur = 0, 0
	if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
	self:Refresh(true)
end

function UI:Pop()
	if not (self.nav and #self.nav > 0) then return end
	self.nav[#self.nav] = nil
	local top = self.nav[#self.nav]
	local y = (top and top.scroll) or (not top and self.overviewScroll) or 0
	if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857) end
	self:Refresh(false)
	self.scrollTarget, self.scrollCur = y, y
end

function UI:Journey(r)
	local top = self.nav and self.nav[#self.nav]
	if top and top.quest then return self:QuestPage(r, top.quest, top.area) end
	if top and top.zone then
		local b = r.byArea and r.byArea[top.zone]
		if b then return self:ZonePage(r, b) end
		self.nav = nil
	end
	self:JourneyOverview(r)
end

local DUNGEON_TAG = "  " .. Hex(C.muted) .. "(dungeon)|r"

local function ZoneBar(h, b)
	local y0 = h.y
	local row = h:NewRow()
	h.y = y0
	row:SetHeight(27)
	row:SetPoint("TOPLEFT", PAD, y0 + 2)
	row:SetScript("OnClick", function() UI:Push({ zone = b.area }) end)
	row:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:SetText(b.name, 1, 0.82, 0)
		local left = b.total - b.done
		GameTooltip:AddDoubleLine("Done", format("%d of %d", b.done, b.total), 0.8, 0.8, 0.8, 1, 1, 1)
		if b.lvLo then GameTooltip:AddDoubleLine("Quests left, levels", Range(b.lvLo, b.lvHi), 0.8, 0.8, 0.8, 1, 1, 1) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format("|cffffd24aClick|r to see the %d quest%s left", left, left == 1 and "" or "s"), 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local label = b.name .. (b.isDungeon and DUNGEON_TAG or "")
	if b.done > 0 then
		local pct = floor(b.done / b.total * 100)
		local color = pct >= 100 and { 0.30, 0.65, 0.25 } or C.bronze
		-- The bar is how much of the zone is done, so it agrees with the percentage beside it.
		h:Bar(label, b.done, b.total, format("%d of %d  \194\183  %d%%", b.done, b.total, pct), color)
	else
		local lv = b.lvLo and ("  \194\183  level " .. Range(b.lvLo, b.lvHi)) or ""
		h:Bar(label, 0, b.total, format("%d quest%s%s", b.total, b.total == 1 and "" or "s", lv))
	end
end

local function ZoneList(h, list, key, limit)
	local expanded = UI.expanded[key]
	for i = 1, expanded and #list or min(#list, limit) do ZoneBar(h, list[i]) end
	if #list > limit then
		h:Link(expanded and "Show fewer" or format("Show all %d zones", #list), function()
			UI.expanded[key] = not UI.expanded[key]
			UI:Refresh(false)
		end)
	end
end

function UI:JourneyOverview(r)
	local done, total = 0, 0
	for _, b in ipairs(r.history) do done, total = done + b.done, total + b.total end

	local c = self:NewCard("parchment", "Interface\\Icons\\INV_Misc_Book_11")
	c:Kicker("Quests so far", "from your completed quests")
	c:Text(format("You've completed |cff6a3a05%s|r quests.", Num(r.completed)), 16, c.pal.head)
	if total > 0 then
		c:Text(format("That's %d%% of everything in the %d zones you've quested in.",
			floor(done / total * 100), #r.history), 12, c.pal.body)
	end
	c:Finish()

	local atlas = r.atlas or r.history
	if #atlas == 0 then return end
	local started, fresh = {}, {}
	for _, b in ipairs(atlas) do
		if b.done > 0 then started[#started + 1] = b else fresh[#fresh + 1] = b end
	end
	local h = self:NewCard("dark", "Interface\\Icons\\INV_Misc_Map02")
	h:Kicker("Zones", "click one to see what's left")
	if #started > 0 then
		h:Kicker(format("Quested in  \194\183  %d", #started))
		ZoneList(h, started, "history", 15)
	end
	if #fresh > 0 then
		if #started > 0 then h:Space(6) end
		h:Kicker(format("Not started yet  \194\183  %d", #fresh))
		ZoneList(h, fresh, "fresh", 10)
	end
	h:Space(4)
	h:Text("Counts only quests your race and class can take. Holiday, profession and removed quests are left out, and either-or quests count once.", 10, h.pal.muted)
	h:Finish()
end

-- Zone page --------------------------------------------------------------------------

local STATUS_GROUPS = {
	{ "available", "You can do these now", "you can do now" },
	{ "level", "Opening at a higher level", "open later" },
	{ "hard", "Too hard for now", "too hard for now" },
	{ "locked", "Not unlocked yet", "locked" },
	{ "gray", "Gray now", "gray" },
	{ "aged", "No longer offered", "no longer offered" },
}
local STATUS_FOLD = { gray = 5, aged = 5, locked = 12 }

local function Prereqs(id)
	local Qd = LibQuestieDB.Quest
	return Qd.preQuestGroup(id), Qd.preQuestSingle(id)
end

-- Whether the quests a quest waits on are done: all of the group, any one of the singles.
local function PrereqsMet(id, set)
	local group, single = Prereqs(id)
	if group then for _, p in ipairs(group) do if not set[p] then return false end end end
	if single and #single > 0 then
		for _, p in ipairs(single) do if set[p] then return true end end
		return false
	end
	return true
end

local function RowNote(q, r)
	local s = q.status
	if q.ready then return "ready to hand in" end
	if q.inLog then return "in your log" end
	if s == "available" then
		local bits = {}
		if q.mobLo then bits[#bits + 1] = "mobs " .. Range(q.mobLo, q.mobHi) end
		if q.xp then bits[#bits + 1] = Num(q.xp) .. " xp" end
		return table.concat(bits, "  \194\183  ")
	elseif s == "level" then return "from level " .. (q.req or q.level)
	elseif s == "locked" then
		if not PrereqsMet(q.id, r.completedSet) then return "needs an earlier quest" end
		if LibQuestieDB.Quest.requiredMinRep(q.id) then return "needs reputation" end
		return ""
	end
	return ""
end

local function OpenQuest(q) UI:Push({ quest = q.id, area = q.area }) end

function UI:ZonePage(r, b)
	local todo = b.todo or {}
	local c = self:NewCard("parchment", b.isDungeon and "Interface\\Icons\\INV_Misc_Key_10" or "Interface\\Icons\\INV_Misc_Map_01")
	if not b.isDungeon then c:Poster(A.UiMapId(b.area), 170) end
	c:Kicker(b.isDungeon and "Dungeon" or "Zone", b.current and "you are here" or (b.done > 0 and "quested in" or "not started yet"))
	c:Button("< All zones", function() UI:Pop() end)
	c:Space(30)
	c:Text(b.name or A.ZoneName(b.area), 24, c.pal.head, FONT, false)
	local pct = b.total > 0 and floor(b.done / b.total * 100) or 0
	c:Bar(format("%d of %d done", b.done, b.total), b.done, b.total, format("%d%%", pct),
		pct >= 100 and { 0.30, 0.65, 0.25 } or C.bronze)
	local counts = {}
	for _, q in ipairs(todo) do counts[q.status] = (counts[q.status] or 0) + 1 end
	local bits = {}
	for _, g in ipairs(STATUS_GROUPS) do
		local n = counts[g[1]]
		if n then bits[#bits + 1] = format("%d %s", n, g[3]) end
	end
	if #todo == 0 then
		c:Text("Nothing left here. Every quest you can take in this zone is done.", 12, c.pal.body)
	else
		c:Text(format("%d quest%s left: %s.", #todo, #todo == 1 and "" or "s", table.concat(bits, ", ")), 12, c.pal.body)
	end
	c:Space(4)
	c:Button("Show on map", function() UI.ShowOnMap(b.area) end)
	c:Space(26)
	c:Finish()

	if #todo == 0 then return end
	local h = self:NewCard("dark", "Interface\\Icons\\INV_Misc_Note_01")
	h:Kicker("Quests left", "click one for details")
	local first = true
	for _, g in ipairs(STATUS_GROUPS) do
		local list = {}
		for _, q in ipairs(todo) do if q.status == g[1] then list[#list + 1] = q end end
		if #list > 0 then
			if not first then h:Space(6) end
			first = false
			h:Kicker(format("%s  \194\183  %d", g[2], #list))
			local key = "zone:" .. b.area .. ":" .. g[1]
			local limit = STATUS_FOLD[g[1]] or #list
			local expanded = UI.expanded[key]
			for i = 1, expanded and #list or min(limit, #list) do
				h:QuestRow(list[i], RowNote(list[i], r), OpenQuest, "for details")
			end
			if #list > limit then
				h:Link(expanded and "Show fewer" or format("Show all %d", #list), function()
					UI.expanded[key] = not UI.expanded[key]
					UI:Refresh(false)
				end)
			end
		end
	end
	h:Finish()
end

-- Quest page -------------------------------------------------------------------------

-- The quest's open entry: in the zone you came from first, then anywhere.
local function FindOpen(r, id, area)
	local b = area and r.byArea and r.byArea[area]
	for _, q in ipairs(b and b.todo or {}) do if q.id == id then return q end end
	for _, z in pairs(r.byArea or {}) do
		for _, q in ipairs(z.todo or {}) do if q.id == id then return q end end
	end
end

-- The first real spawn of an NPC or object, preferring its home zone: area, x, y (0-100).
local function Spawn(kind, id)
	local L = LibQuestieDB
	local db = kind == 1 and L.Npc or kind == 2 and L.Object
	local sp = db and db.spawns and db.spawns(id)
	if type(sp) ~= "table" then return nil end
	local function first(list)
		for _, c in ipairs(list or {}) do
			if type(c) == "table" and c[1] and c[2] and c[1] >= 0 and c[2] >= 0 then return c end
		end
	end
	local home = db.zoneID and db.zoneID(id)
	local c = home and first(sp[home])
	if c then return home, c[1], c[2] end
	for area, list in pairs(sp) do
		c = first(list)
		if c then return area, c[1], c[2] end
	end
end

local function Places(t, kinds)
	local out = {}
	if type(t) ~= "table" then return out end
	local L = LibQuestieDB
	for _, kind in ipairs(kinds) do
		local db = kind == 1 and L.Npc or kind == 2 and L.Object or L.Item
		for _, id in ipairs(t[kind] or {}) do
			local name = db and db.name(id)
			if name then
				local p = { name = kind == 3 and (name .. " (item)") or name }
				if kind ~= 3 then p.area, p.x, p.y = Spawn(kind, id) end
				p.area = p.area or (db.zoneID and db.zoneID(id)) or nil
				if p.area == 0 then p.area = nil end
				out[#out + 1] = p
			end
			if #out >= 3 then return out end
		end
	end
	return out
end

-- Open the world map on a uiMap.
local function OpenMap(uiMapId)
	local Q = ns.Questie()
	if Q and Q.Compat and Q.Compat.OpenWorldMap then
		if not Q.Compat.OpenWorldMap(uiMapId) then ns.Print("The map can't open during combat.") end
	elseif OpenWorldMap then
		OpenWorldMap(uiMapId)
	end
end

-- Drop the game's map pin (with the tracking arrow) on a spot and show it on the map.
function UI.Pin(area, x, y, title)
	local uiMapId = A.UiMapId(area)
	if not uiMapId then return end
	local placed = false
	if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local can = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(uiMapId)
		if can then
			placed = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(uiMapId, x / 100, y / 100))
			if placed and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
			end
		end
	end
	if not placed and TomTom and TomTom.AddWaypoint then
		placed = pcall(TomTom.AddWaypoint, TomTom, uiMapId, x / 100, y / 100, { title = title })
	end
	OpenMap(uiMapId)
	if placed then
		ns.Print(format("Map pin set: %s, %s (%.1f, %.1f)", title, A.ZoneName(area), x, y))
	else
		ns.Print(format("%s is at %.1f, %.1f in %s.", title, x, y, A.ZoneName(area)))
	end
end

-- A "Starts at" / "Hand in to" line; with a known spawn it pins it on the map.
function Card:PlaceRow(prefix, p)
	local row = self:NewRow()
	row.name:SetPoint("LEFT", 0, 0)
	local where = p.area and (", " .. A.ZoneName(p.area)) or ""
	row.name:SetText(format("%s%s|r %s%s", Hex(self.pal.muted), prefix, p.name, where))
	local nc = self.pal.head
	row.name:SetTextColor(nc[1], nc[2], nc[3])
	local mc = self.pal.muted
	row.right:SetTextColor(mc[1], mc[2], mc[3])
	if p.x then
		row.right:SetText(format("%.0f, %.0f", p.x, p.y))
		row:SetScript("OnClick", function() UI.Pin(p.area, p.x, p.y, p.name) end)
		row:SetScript("OnEnter", function(f)
			GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
			GameTooltip:SetText(p.name, 1, 0.82, 0)
			GameTooltip:AddLine(format("%s  %.1f, %.1f", A.ZoneName(p.area), p.x, p.y), 0.8, 0.8, 0.8)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffffd24aClick|r to put a pin on the map", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	row.name:SetWidth(max(60, INNER - row.right:GetStringWidth() - 10))
	return row
end

-- The client only names factions you've met; these cover the rest of the old world.
local FACTION_NAMES = {
	[21] = "Booty Bay", [47] = "Ironforge", [54] = "Gnomeregan Exiles", [59] = "Thorium Brotherhood",
	[68] = "Undercity", [69] = "Darnassus", [70] = "Syndicate", [72] = "Stormwind", [76] = "Orgrimmar",
	[81] = "Thunder Bluff", [87] = "Bloodsail Buccaneers", [92] = "Gelkis Clan Centaur",
	[93] = "Magram Clan Centaur", [270] = "Zandalar Tribe", [349] = "Ravenholdt", [369] = "Gadgetzan",
	[470] = "Ratchet", [471] = "Wildhammer Clan", [509] = "The League of Arathor", [510] = "The Defilers",
	[529] = "Argent Dawn", [530] = "Darkspear Trolls", [576] = "Timbermaw Hold", [577] = "Everlook",
	[589] = "Wintersaber Trainers", [609] = "Cenarion Circle", [729] = "Frostwolf Clan",
	[730] = "Stormpike Guard", [749] = "Hydraxian Waterlords", [809] = "Shen'dralar",
	[889] = "Warsong Outriders", [890] = "Silverwing Sentinels", [909] = "Darkmoon Faire",
	[910] = "Brood of Nozdormu",
}

local function FactionName(fid)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, d = pcall(C_Reputation.GetFactionDataByID, fid)
		if ok and d and d.name and d.name ~= "" then return d.name end
	end
	if GetFactionInfoByID then
		local ok, n = pcall(GetFactionInfoByID, fid)
		if ok and n and n ~= "" then return n end
	end
	return FACTION_NAMES[fid] or ("faction " .. fid)
end

local function StatusLine(q, r, id, level)
	local set = r.completedSet
	if set[id] then return "You've done this one.", DIFF_INK.standard end
	if not q then return nil end
	if q.ready then return "Ready to hand in.", DIFF_INK.standard end
	if q.inLog then return "In your quest log.", DIFF_INK.difficult end
	local s = q.status
	if s == "available" then
		return q.elite and "You can pick this up now. It's elite: bring a group." or "You can pick this up now.", DIFF_INK.standard
	elseif s == "level" then
		return format("Opens at level %d.", q.req or q.level), nil
	elseif s == "hard" then
		return format("Red at your level. It turns yellow around level %d.", q.level - 4), DIFF_INK.impossible
	elseif s == "gray" then
		return "Gray now: little experience left in it, but it still counts toward the zone.", DIFF_INK.trivial
	elseif s == "aged" then
		return "No longer offered at your level.", DIFF_INK.trivial
	elseif s == "locked" then
		if not PrereqsMet(id, set) then return "Not unlocked yet: it needs an earlier quest (below).", DIFF_INK.verydifficult end
		local rep = LibQuestieDB.Quest.requiredMinRep(id)
		if rep and rep[1] then return format("Not unlocked yet: it needs reputation with %s.", FactionName(rep[1])), DIFF_INK.verydifficult end
		return "Not offered to you yet. Questie says something else unlocks it first.", DIFF_INK.verydifficult
	end
	return nil
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemQualityByID = (C_Item and C_Item.GetItemQualityByID) or GetItemQualityByID

local QUALITY_INK = {
	[2] = { 0.03, 0.34, 0.00 }, [3] = { 0.00, 0.22, 0.52 }, [4] = { 0.40, 0.10, 0.60 }, [5] = { 0.62, 0.30, 0.00 },
}

-- An item line: icon, name in its quality colour; hover for the item tooltip, shift-click to link.
function Card:ItemRow(item, rightText)
	local row = self:NewRow()
	local name, link, quality = GetItemInfo(item)
	if not name then
		name = LibQuestieDB.Item.name(item) or ("Item " .. item)
		quality = GetItemQualityByID and GetItemQualityByID(item)
		UI.itemsPending = true
	end
	local icon = select(5, GetItemInfoInstant(item))
	row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.icon:SetDesaturated(false)
	row.icon:SetAlpha(1)
	row.icon:Show()
	local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local nc = self.pal.head
	-- Quality colours are made for dark backgrounds; on parchment they get a darker ink.
	if qc and quality >= 2 then
		nc = self.pal.shadow and { qc.r, qc.g, qc.b } or QUALITY_INK[quality] or nc
	end
	row.name:SetText(name)
	row.name:SetTextColor(nc[1], nc[2], nc[3])
	row.right:SetText(rightText or "")
	local mc = self.pal.muted
	row.right:SetTextColor(mc[1], mc[2], mc[3])
	row.name:SetPoint("LEFT", 18, 0)
	row.name:SetWidth(max(60, INNER - 22 - row.right:GetStringWidth() - 8))
	row:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(item)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function()
		if not IsShiftKeyDown() then return end
		local l = link or select(2, GetItemInfo(item))
		if l and not (ChatEdit_InsertLink and ChatEdit_InsertLink(l)) and ChatFrame_OpenChat then ChatFrame_OpenChat(l) end
	end)
	return row
end

local function Money(copper)
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	return format("%dg %ds %dc", floor(copper / 10000), floor(copper / 100) % 100, copper % 100)
end

function UI:QuestPage(r, id, area)
	local Qd = LibQuestieDB.Quest
	local level = r.level
	local qLevel = Qd.questLevel(id) or 0
	if qLevel <= 0 then qLevel = level end
	local q = FindOpen(r, id, area)
	if q and q.area then area = q.area end
	local zoneName = area and A.ZoneName(area)

	local c = self:NewCard("parchment", "Interface\\Icons\\INV_Misc_Note_06")
	c:Kicker("Quest", zoneName)
	local prev = self.nav and self.nav[#self.nav - 1]
	local backTo = prev and (prev.zone and A.ZoneName(prev.zone) or (prev.quest and A:QuestName(prev.quest))) or "All zones"
	local back = c:Button("< " .. backTo, function() UI:Pop() end)
	if back:GetWidth() > INNER then back:SetWidth(INNER) end
	c:Space(30)
	local diff = (q and q.diff) or A.QuestDifficulty(id, qLevel, level)
	local dc = InkColor(diff, c.pal)
	c:Text(A:QuestName(id), 20, c.pal.head, FONT)
	local facts = { format("%sLevel %d|r", Hex(dc), qLevel) }
	local req = Qd.requiredLevel(id)
	if req and req > 1 then facts[#facts + 1] = "requires " .. req end
	local xp = q and q.xp
	if not xp and ns.Q and ns.Q.XP then
		local ok, v = pcall(ns.Q.XP.GetQuestLogRewardXP, ns.Q.XP, id, false)
		xp = ok and type(v) == "number" and v > 0 and v or nil
	end
	if q and q.elite then facts[#facts + 1] = Hex(DIFF_INK.verydifficult) .. "Elite|r" end
	c:Text(table.concat(facts, "   \194\183   "), 13, c.pal.body, FONT_NUM, false)
	local status, sc = StatusLine(q, r, id, level)
	if status then c:Text(status, 13, sc or c.pal.head) end

	local text = Qd.objectivesText(id)
	if type(text) == "table" and text[1] then
		c:Kicker("Objectives")
		for _, line in ipairs(text) do c:Text(line, 12, c.pal.body) end
	end
	local starts = Places(Qd.startedBy(id), { 1, 2, 3 })
	local ends = Places(Qd.finishedBy(id), { 1, 2 })
	if #starts > 0 or #ends > 0 then
		c:Kicker("Where")
		for _, p in ipairs(starts) do c:PlaceRow("Starts at", p) end
		for _, p in ipairs(ends) do c:PlaceRow("Hand in to", p) end
	end

	-- The quests around this one: what it waits on and where it leads. Each opens its own page.
	local function Linked(qid, note)
		local lv = Qd.questLevel(qid) or 0
		if lv <= 0 then lv = level end
		local done = r.completedSet[qid]
		c:QuestRow({ id = qid, level = lv, diff = A.QuestDifficulty(qid, lv, level), area = area },
			done and "done" or note or "not done",
			function(lq) UI:Push({ quest = lq.id, area = area }) end, "for details")
	end
	local group, single = Prereqs(id)
	if (group and #group > 0) or (single and #single > 0) then
		c:Kicker("Prequest")
		for _, p in ipairs(group or {}) do Linked(p) end
		if single and #single > 0 then
			for _, p in ipairs(single) do Linked(p, #single > 1 and "any one of these" or nil) end
		end
	end
	-- Rewards: items from QuestieDB, reputation from Questie, money only once it's in your log.
	local items = A.rewards and A.rewards[id] or {}
	-- Reputation straight from QuestieDB: Questie's own helper re-maps the amounts through a
	-- later-expansion table, which loses old-world values on this client.
	local reps = {}
	local okR, raw = pcall(Qd.reputationReward, id)
	if okR and type(raw) == "table" then
		for _, rp in ipairs(raw) do
			if type(rp) == "table" and rp[1] then reps[#reps + 1] = { rp[1], tonumber(rp[2]) } end
		end
	end
	local money
	if q and q.inLog and GetQuestLogRewardMoney then
		local ok, m = pcall(GetQuestLogRewardMoney, id)
		money = ok and type(m) == "number" and m > 0 and m or nil
	end
	if xp or #items > 0 or #reps > 0 or money then
		c:Kicker("Rewards")
		local line = {}
		if xp then line[#line + 1] = Num(xp) .. " xp" end
		if money then line[#line + 1] = Money(money) end
		if #line > 0 then c:Text(table.concat(line, "   \194\183   "), 12, c.pal.body, FONT_NUM, false) end
		local known = ns.Rewards and ns.Rewards.Get(id)
		if known then
			-- Seen in the game: exactly what you get and what you pick from.
			if #known.given > 0 then
				if #known.choice > 0 then c:Text("You get", 11, c.pal.muted) end
				for _, item in ipairs(known.given) do c:ItemRow(item) end
			end
			if #known.choice > 0 then
				c:Text(#known.choice > 1 and "Choose one of" or "You get", 11, c.pal.muted)
				for _, item in ipairs(known.choice) do c:ItemRow(item) end
			end
		elseif #items > 0 then
			for _, item in ipairs(items) do c:ItemRow(item) end
			if #items > 1 then
				-- Several pieces of gear are almost always a pick-one; anything else is a guess.
				local gear = 0
				for _, item in ipairs(items) do
					local equip = select(4, GetItemInfoInstant(item))
					if equip and equip ~= "" and equip ~= "INVTYPE_NON_EQUIP_IGNORE" and equip ~= "INVTYPE_BAG" then gear = gear + 1 end
				end
				local guess = gear == #items and "Probably a choice of one." or "Not sure yet whether you get all of these or pick one."
				c:Text(guess .. " Open the quest at its giver once and Passepartout will know.", 10, c.pal.muted)
			end
		end
		for _, rp in ipairs(reps) do
			local v = rp[2]
			if v and v ~= 0 then
				c:Text(format("%s%d reputation with %s", v > 0 and "+" or "", v, FactionName(rp[1])), 12, c.pal.body)
			else
				c:Text("Reputation with " .. FactionName(rp[1]), 12, c.pal.body)
			end
		end
	end

	local nextId = Qd.nextQuestInChain(id)
	local crumb = Qd.breadcrumbForQuestId(id)
	if (nextId and nextId > 0) or (crumb and crumb > 0) then
		c:Kicker("Leads to")
		if nextId and nextId > 0 then Linked(nextId, "next in the chain") end
		if crumb and crumb > 0 then Linked(crumb, "this sends you there") end
	end

	c:Space(8)
	if area then
		c:Button("Show on map", function() UI.ShowOnMap(area) end)
	end
	c:Button("Link in chat", function()
		local ql = format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", id, qLevel, A:QuestName(id))
		if not (ChatEdit_InsertLink and ChatEdit_InsertLink(ql)) and ChatFrame_OpenChat then ChatFrame_OpenChat(ql) end
	end, area ~= nil)
	c:Space(26)
	c:Finish()
end

-- Item names and colours arrive from the server a moment after first asked for.
local itemWatch = CreateFrame("Frame")
itemWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemWatch:SetScript("OnEvent", function()
	if not (UI.itemsPending and UI:IsShown()) or UI.itemRefreshQueued then return end
	UI.itemRefreshQueued = true
	C_Timer.After(0.2, function()
		UI.itemRefreshQueued = false
		local y = UI.scrollTarget
		UI:Refresh(false)
		UI.scrollTarget, UI.scrollCur = y, y
	end)
end)

function UI:ShiftCards(x)
	if self.cardX == x then return end
	self.cardX = x
	for i = 1, self.cardIdx do
		local card = self.cards[i]
		local _, _, _, _, y = card:GetPoint(1)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y or 0)
	end
end

function UI:Layout(animate)
	local y = 0
	for i = 1, self.cardIdx do
		local card = self.cards[i]
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", self.content, "TOPLEFT", self.cardX or 0, -y)
		y = y + card:GetHeight() + GAP
		card:SetAlpha(animate and 0 or 1)
	end
	for i = self.cardIdx + 1, #self.cards do self.cards[i]:Hide() end
	self.content:SetHeight(max(1, y))
	self.fadeStart = animate and GetTime() or nil
end
