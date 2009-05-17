-- Thanks to haste for the original tagging code, which I then mostly ripped apart and stole!
local Tags = ShadowUF:NewModule("Tags")
local eventlessUnits, events, tagPool, functionPool, fastTagUpdates, temp, regFontStrings = {}, {}, {}, {}, {}, {}, {}
local frame
local L = ShadowUFLocals

function Tags:OnInitialize()
	self:LoadTags()
end

-- Event management
local function RegisterEvent(fontString, event)
	events[event] = events[event] or {}
	table.insert(events[event], fontString)
	
	frame:RegisterEvent(event)
end

-- Register the associated events with all the tags
local function RegisterTagEvents(fontString, tags)
	-- Strip parantheses and anything inside them
	tags = string.gsub(tags, "%b()", "")
	for tag in string.gmatch(tags, "%[(.-)%]") do
		local tagEvents = Tags.defaultEvents[tag] or ShadowUF.db.profile.tags[tag] and ShadowUF.db.profile.tags[tag].events
		if( tagEvents ) then
			for event in string.gmatch(tagEvents, "%S+") do
				RegisterEvent(fontString, event)
				
				-- If it's for the player, and the tag uses a power event, flag it as needing to be OnUpdate monitored
				if( fontString.parent.unit == "player" and Tags.powerEvents[event] ) then
					fastTagUpdates[fontString] = true
				end
			end
		end
	end
end

-- Unregister all events for this tag
local function UnregisterTagEvents(fontString)
	for event, fsList in pairs(events) do
		for i=#(fsList), 1, -1 do
			if( fsList[i] == fontString ) then
				table.remove(fsList, i)
				
				if( #(fsList) == 0 ) then
					frame:UnregisterEvent(event)
				end
			end
		end
	end
end

-- Tag needs an update!
local timeElapsed = 0
frame = CreateFrame("Frame")
frame:Hide()

frame:SetScript("OnUpdate", function(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 0.50 ) then
		for _, text in pairs(eventlessUnits) do
			if( text.parent:IsVisible() and UnitExists(text.parent.unit) ) then
				text:UpdateTags()
			end
		end
		
		timeElapsed = 0
	end
end)

frame:SetScript("OnEvent", function(self, event, unit)
	if( not events[event] ) then
		return
	end
	
	for _, fontString in pairs(events[event]) do
		if( Tags.unitlessEvents[event] or ( not Tags.unitlessEvents[event] and fontString.parent.unit == unit ) ) then
			fontString:UpdateTags()
		end
	end	
end)

-- Tag updating for power to make it smooth
local fastFrame = CreateFrame("Frame")
fastFrame:SetScript("OnUpdate", function(self, elapsed)
	for fontString in pairs(fastTagUpdates) do
		fontString:UpdateTags()
	end
end)

-- This pretty much means a tag was updated in some way (or deleted) so we have to do a full update to get the new values shown
function Tags:FullUpdate()
	for fontString in pairs(regFontStrings) do
		if( fontString:IsVisible() ) then
			fontString:UpdateTags()
		end
	end
end

function Tags:Register(parent, fontString, tags)
	-- Unregister the font string first if we did register it already
	if( fontString.UpdateTags ) then
		self:Unregister(fontString)
	end
	
	fontString.parent = parent
	
	fastTagUpdates[fontString] = nil
	regFontStrings[fontString] = true
	
	local updateFunc = tagPool[tags]
	if( not updateFunc ) then
		-- Using .- prevents supporting tags such as [foo ([)]. Supporting that and having a single pattern
		-- here is a pain however (Or, so haste says!)
		local formattedText = string.gsub(string.gsub(tags, "%%", "%%%%"), "[[].-[]]", "%%s")
		local args = {}
		
		for tag in string.gmatch(tags, "%[(.-)%]") do
			-- If they enter a tag such as "foo(|)" then we won't find a regular tag, meaning will go into our function pool code
			local cachedFunc = functionPool[tag] or ShadowUF.tagFunc[tag]
			if( not cachedFunc ) then
				local pre, tagKey, ap = string.match(tag, "(%b())([%w]+)(%b())")
				if( not pre ) then pre, tagKey = string.match(tag, "(%b())([%w]+)") end
				if( not pre ) then tagKey, ap = string.match(tag, "([%w]+)(%b())") end
				
				local tag = tagKey and ShadowUF.tagFunc[tagKey]
				if( tag ) then
					pre = pre and string.sub(pre, 2, -2) or ""
					ap = ap and string.sub(ap, 2, -2) or ""

					cachedFunc = function(unit)
						local str = tag(unit)
						if( str ) then
							return pre .. str .. ap
						end
					end
					
					functionPool[tag] = cachedFunc
				end
			end
			
			-- It's an invalid tag, simply return the tag itself
			if( not cachedFunc ) then
				functionPool[tag] = functionPool[tag] or function() return string.format("[%s]", tag) end
				cachedFunc = functionPool[tag]
			end
			
			if( cachedFunc ) then
				table.insert(args, cachedFunc)
			end
		end
		
		-- Create our update function now
		updateFunc = function(fontString)
			local unit = fontString.parent.unit
			for id, func in pairs(args) do
				temp[id] = func(unit) or ""
			end
			
			fontString:SetFormattedText(formattedText, unpack(temp))
		end

		tagPool[tags] = updateFunc
	end
	
	fontString.UpdateTags = updateFunc
	
	local unit = parent.unit
	if( unit and string.match(unit, "%w+target") ) then
		table.insert(eventlessUnits, fontString)
		frame:Show()
	else
		RegisterTagEvents(fontString, tags)
		
		if( unit == "focus" ) then
			RegisterEvent(fontString, "PLAYER_FOCUS_CHANGED")
		elseif( unit == "target" ) then
			RegisterEvent(fontString, "PLAYER_TARGET_CHANGED")
		elseif( unit == "mouseover" ) then
			RegisterEvent(fontString, "UPDATE_MOUSEOVER_UNIT")
		end
	end
end

function Tags:Unregister(fontString)
	UnregisterTagEvents(fontString)
		
	for i=#(eventlessUnits), 1, -1 do
		if( eventlessUnits[i] == fontString ) then
			table.remove(eventlessUnits, i)
		end
	end
	
	if( #(eventlessUnits) == 0 ) then
		frame:Hide()
	end
	
	fastTagUpdates[fontString] = nil
	regFontStrings[fontString] = nil
	
	fontString.UpdateTags = nil
end

-- Helper functions for tags, the reason I store it in ShadowUF is it's easier to type ShadowUF
-- than ShadowUF.modules.Tags, and simpler for users who want to implement it.
function ShadowUF:Hex(r, g, b)
	if( type(r) == "table" ) then
		if( r.r ) then
			r, g, b = r.r, r.g, r.b
		else
			r, g, b = unpack(r)
		end
	end

	return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function ShadowUF:FormatLargeNumber(number)
	if( number < 9999 ) then
		return number
	elseif( number < 999999 ) then
		return string.format("%.1fk", number / 1000)
	end
	
	return string.format("%.2fm", number / 1000000)
end

function ShadowUF:GetClassColor(unit)
	if( not UnitIsPlayer(unit) ) then
		return nil
	end
	
	local class = select(2, UnitClass(unit))
	return class and ShadowUF:Hex(RAID_CLASS_COLORS[class])
end

function Tags:LoadTags()
	self.defaultTags = {
		["colorname"] = [[function(unit)
			local name = UnitName(unit)
			if( not name or not UnitIsPlayer(unit) ) then
				return name
			end
			
			local color = ShadowUF:GetClassColor(unit)
			if( not color ) then
				return name
			end
			
			return color .. name .. "|r"
		end]],
		["class"]       = [[function(unit) return UnitClass(unit) end]],
		["classcolor"] = [[function(unit)
			local color = ShadowUF:GetClassColor(unit)
			local class = UnitClass(unit)
			if( not color or not class ) then
				return class
			end
			
			return color .. class .. "|r"
		end]],
		["creature"]    = [[function(unit) return UnitCreatureFamily(unit) or UnitCreatureType(unit) end]],
		["curhp"]       = [[function(unit)
			local health = UnitHealth(unit)
			if( health == 1 or UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) ) then
				health = 0
			end
			return ShadowUF:FormatLargeNumber(health)
		end]],
		["curpp"]       = [[function(unit) return ShadowUF:FormatLargeNumber(UnitPower(unit)) end]],
		["curmaxhp"] = [[function(unit)
			local offline = ShadowUF.tagFunc.offline(unit)
			if( offline ) then
				return offline
			end

			local dead = ShadowUF.tagFunc.dead(unit)
			if( dead ) then
				return dead
			end
			
			return string.format("%s/%s", ShadowUF.tagFunc.curhp(unit), ShadowUF.tagFunc.maxhp(unit))
		end]],
		["curmaxpp"] = [[function(unit)
			local dead = ShadowUF.tagFunc.dead(unit)
			if( dead ) then
				return string.format("0/%s", ShadowUF.tagFunc.maxpp(unit))
			end
			
			return string.format("%s/%s", ShadowUF.tagFunc.curpp(unit), ShadowUF.tagFunc.maxpp(unit))
		end]],
		["dead"]        = [[function(unit) return UnitIsDead(unit) and ShadowUFLocals["Dead"] or UnitIsGhost(unit) and ShadowUFLocals["Ghost"] end]],
		["levelcolor"]  = [[function(unit)
			local level = UnitLevel(unit);
			if( UnitCanAttack("player", unit) ) then
				return ShadowUF:Hex(GetDifficultyColor(level > 0 and level or 99))
			else
				return level
			end
		end]],
		["faction"]     = [[function(unit) return UnitFactionGroup(unit) end]],
		["level"]       = [[function(unit) local l = UnitLevel(unit) return (l > 0) and l or ShadowUFLocals["??"] end]],
		["maxhp"]       = [[function(unit) return ShadowUF:FormatLargeNumber(UnitHealthMax(unit)) end]],
		["maxpp"]       = [[function(unit) return ShadowUF:FormatLargeNumber(UnitPowerMax(unit)) end]],
		["missinghp"]   = [[function(unit)
			local missing = UnitHealthMax(unit) - UnitHealth(unit)
			if( missing <= 0 ) then return "" end
			return "-" .. ShadowUF:FormatLargeNumber(UnitHealthMax(unit) - UnitHealth(unit)) 
		end]],
		["missingpp"]   = [[function(unit) return ShadowUF:FormatLargeNumber(UnitPowerMax(unit) - UnitPower(unit)) end]],
		["name"]        = [[function(unit) return UnitName(unit) end]],
		["offline"]     = [[function(unit) return  (not UnitIsConnected(unit) and ShadowUFLocals["Offline"]) end]],
		["perhp"]       = [[function(unit)
			local offline = ShadowUF.tagFunc.offline(unit)
			if( offline ) then
				return offline
			end

			local dead = ShadowUF.tagFunc.dead(unit)
			if( dead ) then
				return dead
			end
			
			local max = UnitHealthMax(unit);
			
			return max == 0 and 0 or math.floor(UnitHealth(unit) / max * 100 + 0.5) .. "%"
		end]],
		["perpp"]       = [[function(unit) local m = UnitPowerMax(unit); return m == 0 and 0 or math.floor(UnitPower(unit)/m*100+0.5) .. "%" end]],
		["plus"]        = [[function(unit) local c = UnitClassification(unit); return (c == "elite" or c == "rareelite") and "+" end]],
		["race"]        = [[function(unit) return UnitRace(unit) end]],
		["rare"]        = [[function(unit) local c = UnitClassification(unit); return (c == "rare" or c == "rareelite") and ShadowUFLocals["Rare"] end]],
		["sex"]         = [[function(unit) local s = UnitSex(unit) return s == 2 and ShadowUFLocals["Male"] or s == 3 and ShadowUFLocals["Female"] end]],
		["smartclass"]  = [[function(unit) return UnitIsPlayer(unit) and ShadowUF.tagFunc.class(unit) or ShadowUF.tagFunc.creature(unit) end]],
		["status"]      = [[function(unit)
			if( UnitIsDead(unit) ) then
				return ShadowUFLocals["Dead"]
			elseif( UnitIsGhost(unit) ) then
				return ShadowUFLocals["Ghost"]
			elseif( not UnitIsConnected(unit) ) then
				return ShadowUFLocals["Offline"]
			end
			return ""
		end]],
		["cpoints"]     = [[function(unit) local cp = GetComboPoints(unit, "target") return (cp > 0) and cp end]],
		["smartlevel"] = [[function(unit)
			local c = UnitClassification(unit)
			if(c == "worldboss") then
				return ShadowUFLocals["Boss"]
			else
				local plus = ShadowUF.tagFunc.plus(unit)
				local level = ShadowUF.tagFunc.level(unit)
				if( plus ) then
					return level .. plus
				else
					return level
				end
			end
		end]],
		["classification"] = [[function(unit)
			local c = UnitClassification(unit)
			return c == "rare" and ShadowUFLocals["Rare"] or c == "eliterare" and ShadowUFLocals["Rare Elite"] or c == "elite" and ShadowUFLocals["Elite"] or c == "worldboss" and ShadowUFLocals["Boss"]
		end]],
		["shortclassification"] = [[function(unit)
			local c = UnitClassification(unit)
			return c == "rare" and "R" or c == "eliterare" and "R+" or c == "elite" and "+" or c == "worldboss" and "B"
		end]],
	}

	self.defaultHelp = {
		["cpoints"] = L["Total number of combo points you have on your target."],
		["smartlevel"] = L["Smart level, returns Boss for bosses, +50 for a level 50 elite mob, or just 80 for a level 80."],
		["classification"] = L["Units classification, Rare, Rare Elite, Elite, Boss, nothing is shown if they aren't any of those."],
		["shortclassification"] = L["Short classifications, R for Rare, R+ for Rare Elite, + for Elite, B for boss, nothing is shown if they aren't any of those."],
		["rare"] = L["Returns Rare if the unit is a rare or rare elite mob."],
		["plus"] = L["Returns + if the unit is an elite or rare elite mob."],
		["sex"] = L["Returns the units sex."],
		["smartclass"] = L["For players, it will return a class, for mobs than it will return their creature type."],
		["status"] = L["Units status, Dead, Ghost, Offline, nothing is shown if they aren't any of those."],
		["race"] = L["Unit race, for a Blood Elf then Blood Elf is returned, for a Night Elf than Night Elf is returned and so on."],
		["level"] = L["Level without any coloring."],
		["maxhp"] = L["Max health, uses a short format, 17750 is formatted as 17.7k, values below 10000 are formatted as is."],
		["maxpp"] = L["Max power, uses a short format, 16000 is formatted as 16k, values below 10000 are formatted as is."],
		["missinghp"] = L["Amount of health missing, if none is missing nothing is shown. Uses a short format, -18500 is shown as -18.5k, values below 10000 are formatted as is."],
		["missingpp"] = L["Amount of power missing,  if none is missing nothing is shown. Uses a short format, -13850 is shown as 13.8k, values below 10000 are formatted as is."],
		["name"] = L["Unit name"],
		["offline"] = L["Returns Offline if the unit is offline, otherwise nothing is shown."],
		["perhp"] = L["Returns current health as a percentage, if the unit is dead or offline than that is shown instead."],
		["perpp"] = L["Returns current power as a percentage."],
		["class"] = L["Class, use [classcolor] if you want a colored class name."],
		["classcolor"] = L["Colored class, use [class] for just the class name without coloring."],
		["creature"] = L["Create type, for example, if you're targeting a Felguard then this will return Felguard."],
		["curhp"] = L["Current health, uses a short format, 11500 is formatted as 11.5k, values below 10000 are formatted as is."],
		["curpp"] = L["Current power, uses a short format, 12750 is formatted as 12.7k, values below 10000 are formatted as is."],
		["curmaxhp"] = L["Current and maximum health, formatted as [curhp]/[maxhp], if the unit is dead or offline then that is shown instead."],
		["curmaxpp"] = L["Current and maximum power, formatted as [curpp]/[maxpp]."],
		["dead"] = L["If the unit is dead, returns dead, if they are a ghost then ghost is returned, if they aren't either then nothing is shown."],
		["levelcolor"] = L["Colored level by difficulty, no color used if you cannot attack the unit."],
		["faction"] = L["Units alignment, Thrall will return Horde, Magni Bronzebeard will return Alliance."],
		["colorname"] = L["Unit name colored by class."],
	}

	-- Default tag events
	self.defaultEvents = {
		["curhp"]               = "UNIT_HEALTH",
		["curmaxhp"]			= "UNIT_HEALTH UNIT_MAXHEALTH",
		["curpp"]               = "UNIT_ENERGY UNIT_FOCUS UNIT_MANA UNIT_RAGE UNIT_RUNIC_POWER UNIT_DISPLAYPOWER",
		["curmaxpp"]			= "UNIT_ENERGY UNIT_FOCUS UNIT_MANA UNIT_RAGE UNIT_RUNIC_POWER UNIT_DISPLAYPOWER UNIT_MAXENERGY UNIT_MAXFOCUS UNIT_MAXMANA UNIT_MAXRAGE UNIT_MAXRUNIC_POWER",
		["dead"]                = "UNIT_HEALTH",
		["level"]               = "UNIT_LEVEL PLAYER_LEVEL_UP",
		["maxhp"]               = "UNIT_MAXHEALTH",
		["maxpp"]               = "UNIT_MAXENERGY UNIT_MAXFOCUS UNIT_MAXMANA UNIT_MAXRAGE UNIT_MAXRUNIC_POWER",
		["missinghp"]           = "UNIT_HEALTH UNIT_MAXHEALTH",
		["missingpp"]           = "UNIT_MAXENERGY UNIT_MAXFOCUS UNIT_MAXMANA UNIT_MAXRAGE UNIT_ENERGY UNIT_FOCUS UNIT_MANA UNIT_RAGE UNIT_MAXRUNIC_POWER UNIT_RUNIC_POWER",
		["name"]                = "UNIT_NAME_UPDATE",
		["colorname"]			= "UNIT_NAME_UPDATE",
		["offline"]             = "UNIT_HEALTH",
		["perhp"]               = "UNIT_HEALTH UNIT_MAXHEALTH",
		["perpp"]               = "UNIT_MAXENERGY UNIT_MAXFOCUS UNIT_MAXMANA UNIT_MAXRAGE UNIT_ENERGY UNIT_FOCUS UNIT_MANA UNIT_RAGE UNIT_MAXRUNIC_POWER UNIT_RUNIC_POWER",
		["status"]              = "UNIT_HEALTH PLAYER_UPDATE_RESTING",
		["smartlevel"]          = "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED",
		["cpoints"]             = "UNIT_COMBO_POINTS UNIT_TARGET",
		["rare"]                = "UNIT_CLASSIFICATION_CHANGED",
		["classification"]      = "UNIT_CLASSIFICATION_CHANGED",
		["shortclassification"] = "UNIT_CLASSIFICATION_CHANGED",
	}
	
	self.powerEvents = {
		["UNIT_ENERGY"] = true,
		["UNIT_FOCUS"] = true,
		["UNIT_MANA"] = true,
		["UNIT_RAGE"] = true,
		["UNIT_RUNIC_POWER"] = true,
	}
	
	-- Events that should call every font string, and not bother checking for unit
	self.unitlessEvents = {
		["PLAYER_TARGET_CHANGED"] = true,
		["PLAYER_FOCUS_CHANGED"] = true,
		["PLAYER_LEVEL_UP"] = true,
	}
end

function Tags:Verify()
	local fine = true
	for tag, events in pairs(self.defaultEvents) do
		if( not self.defaultTags[tag] ) then
			print(string.format("Found event for %s, but no tag associated with it.", tag))
			fine = nil
		end
	end
	
	for tag, data in pairs(self.defaultTags) do
		if( not self.defaultTags[tag] ) then
			print(string.format("Found tag for %s, but no event associated with it.", tag))
			fine = nil
		end
		
		if( not self.defaultHelp[tag] ) then
			print(string.format("Found tag for %s, but no help text associated with it.", tag))
			fine = nil
		end
		
		local funct, msg = loadstring("return " .. data)
		if( not funct and msg ) then
			print(string.format("Failed to load tag %s.", tag))
			print(msg)
			fine = nil
		end
	end
	
	if( fine ) then
		print("Verified tags, everything is fine.")
	end
end