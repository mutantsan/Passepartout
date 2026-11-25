-- Passepartout: minimap button (LibDataBroker launcher + LibDBIcon)

local _, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local LDB = LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub("LibDBIcon-1.0", true)

function Minimap:Init()
	if not LDB then return end
	self.object = LDB:NewDataObject("Passepartout", {
		type = "launcher",
		text = "Passepartout",
		icon = ns.LOGO,
		OnClick = function() ns.UI:Toggle() end,
		OnTooltipShow = function(tt)
			tt:AddLine(ns.NAME)
			tt:AddLine("Where to quest next", 0.8, 0.8, 0.85)
			local A = ns.Analyzer
			local r = A.result
			if A.dirty or A.state == "scanning" or not r then
				-- Out of date since the last read: refresh quietly so the next look is current.
				A:Start(false)
				tt:AddLine(" ")
				tt:AddLine(r and "Updating..." or "Reading your quest history...", 0.6, 0.6, 0.6)
			end
			if r and #r.zones > 0 then
				tt:AddLine(" ")
				for i = 1, math.min(3, #r.zones) do
					local b = r.zones[i]
					tt:AddDoubleLine(i .. ". " .. b.name, ns.Range(b.mobLo, b.mobHi), 1, 0.82, 0, 1, 1, 1)
				end
			end
			tt:AddLine(" ")
			tt:AddLine("|cffffd24aClick|r to open", 0.8, 0.8, 0.85)
			tt:AddLine("|cffffd24aDrag|r to move", 0.8, 0.8, 0.85)
		end,
	})
	if DBIcon then DBIcon:Register("Passepartout", self.object, ns.db.minimap) end
end

function Minimap:Toggle()
	if not DBIcon then return end
	local db = ns.db.minimap
	db.hide = not db.hide
	if db.hide then DBIcon:Hide("Passepartout") else DBIcon:Show("Passepartout") end
	ns.Print(db.hide and "Minimap button hidden. /pp minimap brings it back." or "Minimap button shown.")
end
