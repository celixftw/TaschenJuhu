-- TaschenJuhu
-- When you loot a bag or a rare (blue or better) item: a happy sound ("Juhu!") and a short golden flash of the screen.
-- Bags are items of the "Container" class. Only your own loot counts (CHAT_MSG_LOOT).
--
-- Sound: the level-up fanfare plus "Juhu!" spoken by the game's text to speech. If a file
-- hallelujah.ogg/.mp3 or juhu.ogg/.mp3 is put into this addon's folder, it is played instead
-- of the voice (the user's own file, e.g. from their copy of Worms 2).
-- /juhu: test once, /juhu testmodus: every looted item triggers it (to try the real loot
-- detection), /juhu stimme: voice on/off, /juhu blitz: flash on/off.

local ADDON = ...
local db

local function Print(msg)
	print("|cffffd100TaschenJuhu:|r "..msg)
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

local LEVEL_UP_SOUND = 888 -- the level-up fanfare

-- Hallelujah clips cut from Handel's Messiah (MIT Concert Choir, CC BY-SA 2.0, see LIZENZ.txt).
local VARIANT_FILES = { kurz = "hallelujah_kurz", normal = "hallelujah", lang = "hallelujah_lang" }

-- Prefers a German voice of the game's text to speech.
local function GetVoiceID()
	if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return nil end
	local fallback
	for _, voice in ipairs(C_VoiceChat.GetTtsVoices() or {}) do
		local name = voice.name or ""
		if name:find("German") or name:find("Deutsch") or name:find("Hedda") or name:find("Katja") then
			return voice.voiceID
		end
		fallback = fallback or voice.voiceID
	end
	return fallback
end

local function SpeakJuhu()
	local voiceID = GetVoiceID()
	if not voiceID or not C_VoiceChat.SpeakText then return end
	-- The signature changed over the game versions; try the current one, then the older one.
	if not pcall(C_VoiceChat.SpeakText, voiceID, "Juhu!", 2, 100, true) then
		local destination = Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback or 1
		pcall(C_VoiceChat.SpeakText, voiceID, "Juhu!", destination, 2, 100)
	end
end

local function PlayJuhu()
	-- Own sound file first (the chosen hallelujah variant, then juhu.*). Only without one: the
	-- level-up fanfare and the spoken "Juhu!" (fanfare and choir together sound muddy).
	local variant = VARIANT_FILES[db.variant] or "hallelujah"
	for _, name in ipairs { variant, "hallelujah", "juhu" } do
		for _, ext in ipairs { "ogg", "mp3" } do
			if PlaySoundFile("Interface\\AddOns\\"..ADDON.."\\"..name.."."..ext, "Master") then
				return
			end
		end
	end
	PlaySound(LEVEL_UP_SOUND, "Master")
	if db.voice then
		SpeakJuhu()
	end
end

--------------------------------------------------------------------------------
-- Screen flash
--------------------------------------------------------------------------------

local flash = CreateFrame("Frame", nil, UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("FULLSCREEN_DIALOG")
flash:EnableMouse(false)
flash:Hide()

local glow = flash:CreateTexture(nil, "BACKGROUND")
glow:SetAllPoints()
glow:SetColorTexture(1, 0.82, 0.25, 1) -- warm gold
glow:SetBlendMode("ADD")
flash:SetAlpha(0)

-- Two quick golden pulses.
local pulses = flash:CreateAnimationGroup()
local function Pulse(order, peak)
	local up = pulses:CreateAnimation("Alpha")
	up:SetOrder(order)
	up:SetFromAlpha(0)
	up:SetToAlpha(peak)
	up:SetDuration(0.12)
	local down = pulses:CreateAnimation("Alpha")
	down:SetOrder(order + 1)
	down:SetFromAlpha(peak)
	down:SetToAlpha(0)
	down:SetDuration(0.3)
end
Pulse(1, 0.45)
Pulse(3, 0.3)
pulses:SetScript("OnFinished", function() flash:Hide() end)

local function Flash()
	pulses:Stop()
	flash:SetAlpha(0)
	flash:Show()
	pulses:Play()
end

--------------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------------

local function Celebrate()
	PlayJuhu()
	if db.flash then Flash() end
end

local function IsBag(link)
	local classID = select(6, C_Item.GetItemInfoInstant(link))
	return classID == Enum.ItemClass.Container
end

-- Rare (blue) or better. The quality comes from the item data, or from the link colour while the
-- item is not cached yet.
local RARE = (Enum.ItemQuality and Enum.ItemQuality.Rare) or 3
local LINK_QUALITY = { ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7 }
local function IsRare(link, text)
	local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
	if not quality then
		-- Newer clients colour links as |cnIQ3:...; older ones as |cff0070dd.
		quality = tonumber(text:match("|cnIQ(%d+):") or "")
		local color = not quality and text:match("|c%x%x(%x%x%x%x%x%x)|Hitem:")
		quality = quality or (color and LINK_QUALITY[color:lower()])
	end
	return quality ~= nil and quality >= RARE
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then return end
		self:UnregisterEvent("ADDON_LOADED")
		TaschenJuhuDB = TaschenJuhuDB or {}
		db = TaschenJuhuDB
		if db.voice == nil then db.voice = true end
		if db.flash == nil then db.flash = true end
		if db.rare == nil then db.rare = true end
		self:RegisterEvent("CHAT_MSG_LOOT")
		if db.testMode then
			-- So it is not forgotten on.
			C_Timer.After(5, function() Print("|cffff8040Testmodus ist an|r: jedes Item löst Juhu aus. Ausschalten mit /juhu testmodus.") end)
		end
	else
		local text, _, _, _, _, _, _, _, _, _, _, guid = ...
		-- In some instances chat text is protected and cannot be read.
		if issecretvalue and (issecretvalue(text) or issecretvalue(guid)) then return end
		if guid ~= UnitGUID("player") then return end -- only your own loot
		local link = text:match("(|c%x+|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h)")
		-- Test mode: every looted item counts, to try the real loot detection.
		if link and (IsBag(link) or (db.rare and IsRare(link, text)) or db.testMode) then
			Celebrate()
		end
	end
end)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

SLASH_TASCHENJUHU1 = "/juhu"
SlashCmdList.TASCHENJUHU = function(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")
	if cmd == "stimme" then
		db.voice = not db.voice
		Print("Stimme "..(db.voice and "an" or "aus")..".")
	elseif cmd == "blitz" then
		db.flash = not db.flash
		Print("Bildschirm-Blitz "..(db.flash and "an" or "aus")..".")
	elseif cmd == "kurz" or cmd == "normal" or cmd == "lang" then
		db.variant = cmd
		Print("Halleluja: "..cmd..".")
		Celebrate()
	elseif cmd == "selten" then
		db.rare = not db.rare
		Print("Seltene Items (blau und besser) "..(db.rare and "lösen auch Juhu aus." or "lösen kein Juhu mehr aus."))
	elseif cmd == "testmodus" then
		db.testMode = not db.testMode
		Print(db.testMode and "|cffff8040Testmodus an|r: jedes Item, das du lootest, löst Juhu aus."
			or "Testmodus aus: nur noch Taschen (und seltene Items) lösen Juhu aus.")
	elseif cmd == "" or cmd == "test" then
		Celebrate()
		Print("Test! /juhu testmodus – jedes Item löst aus, /juhu selten – auch bei blauen Items an/aus, /juhu stimme – Stimme an/aus, /juhu blitz – Blitz an/aus.")
	else
		Print("/juhu – einmal testen, /juhu kurz|normal|lang – Halleluja-Länge, /juhu selten – auch bei seltenen (blauen) Items an/aus, /juhu testmodus – jedes Item löst aus, /juhu stimme – Stimme an/aus, /juhu blitz – Blitz an/aus")
	end
end
