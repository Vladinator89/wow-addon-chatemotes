local CEL = LibStub and LibStub("ChatEmotesLib-1.0", true) ---@type ChatEmotesLib-1.0
if not CEL then return end

local _G = _G
local strlenutf8 = _G.strlenutf8

---@class ChatEmotesLocale
---@field public LOCALE_NAME string
---@field public CHAT_EMOTES string
---@field public YOU_HAVE_NO_EMOTES_INSTALLED string
---@field public MISSING_EMOTE_PACK string
---@field public SEARCH_RESULTS string
---@field public CHAT_EMOTES_OPTIONS string
---@field public OPTIONS string
---@field public EMOTE_SCALE string
---@field public EMOTE_HOVER string
---@field public ENABLE_AUTOCOMPLETE string
---@field public AUTOCOMPLETE_CHAR string
---@field public AUTOCOMPLETE_PRESET string
---@field public UNLOCK_BUTTON string
---@field public AUTOCOMPLETE_ACCEPT string
---@field public EMOTE_ANIMATION string
---@field public EMOTE_ANIMATION_IN_COMBAT string
---@field public EMOTE_ANIMATION_INTERVAL string

---@class ChatEmotesNamespace
---@field public NewLocale function
---@field public IsSameLocale function
---@field public L ChatEmotesLocale

local addonName = ... ---@type string @The name of the addon.
local ns = select(2, ...) ---@type ChatEmotesNamespace @The addon namespace.
local L = ns.L

local addon = CreateFrame("Frame") ---@class ChatEmotesAddon : Frame
local addonFrame ---@type ChatEmotesUIMixin
local addonButton ---@type ChatEmotesUIButtonMixin
local addonConfigFrame ---@type ChatEmotesUIConfigMixin
local addonAnimator ---@type ChatEmotesAnimatorMixin

local IS_MAINLINE = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local NO_EMOTE_MARKUP_FALLBACK = format("|T%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", 132048, 16, 10, -1, 0, 16, 16, 4, 13, 0, 16)
local MAX_EMOTES_PER_MESSAGE = 59 -- 60 and above will result in malformed trailing emotes in the chat frame
local INVALID_AUTOCOMPLETE_CHARS = { [" "] = true, [":"] = true, ["|"] = true, ["/"] = true, ["-"] = true }

---@class ChatEmoteStatistics
---@field public sent? number|nil
---@field public received? number|nil

---@class ChatEmotesDB_Options
---@field public emoteScale number
---@field public emoteHover boolean
---@field public enableAutoComplete boolean
---@field public autoCompleteChar string
---@field public autoCompletePreset number
---@field public unlockButton boolean
---@field public emoteAnimation boolean
---@field public emoteAnimationInCombat boolean
---@field public emoteAnimationInterval number

---@class ChatEmotesDB_Position
---@field public point string
---@field public relativeTo? string|nil
---@field public relativePoint string
---@field public x number
---@field public y number
---@field public width number
---@field public height number

---@class ChatEmotesDB
---@field public options ChatEmotesDB_Options
---@field public position ChatEmotesDB_Position
---@field public buttonPosition ChatEmotesDB_Position
---@field public favorites table<string, boolean|nil>
---@field public statistics table<string, ChatEmoteStatistics>

local DB ---@type ChatEmotesDB
local defaults = {
	options = {
		emoteScale = 1.25,
		emoteHover = true,
		enableAutoComplete = true,
		autoCompleteChar = "#",
		autoCompletePreset = 2,
		unlockButton = false,
		emoteAnimation = true,
		emoteAnimationInCombat = true,
		emoteAnimationInterval = 0.03,
	},
	position = {
		point = "LEFT",
		relativeTo = nil,
		relativePoint = "LEFT",
		x = 15,
		y = -175,
		width = 335,
		height = 345,
	},
	buttonPosition = {
		point = "TOP",
		relativeTo = IS_MAINLINE and "ChatFrameMenuButton" or "ChatFrame1ButtonFrame",
		relativePoint = "BOTTOM",
		x = 0,
		y = 0,
	},
	favorites = {},
	statistics = {},
}

---@type table<string, number>
local activeChannels = {}

---@type table<number, boolean>
local ignoreChannels = {
	-- [1] = true, -- General (General - %s)
	[2] = true, -- Trade (Trade - %s)
	-- [22] = true, -- LocalDefense (LocalDefense - %s)
	-- [26] = true, -- LookingForGroup (LookingForGroup)
	-- [27] = true, -- BigfootWorldChannel (BigfootWorldChannel)
	-- [28] = true, -- MeetingStone (MeetingStone)
	-- [32] = true, -- NewcomerChat (Newcomer Chat)
	-- [33] = true, -- ShadowlandsBetaDiscussion (zzOLD Shadowlands Beta Discussion)
	-- [34] = true, -- ShadowlandsPTRDiscussion (zzOLD Shadowlands PTR Discussion)
	-- [35] = true, -- ShadowlandsTestDiscussion (Shadowlands Test Discussion)
	-- [36] = true, -- ChromieTime (Chromie Time - Cataclysm)
	-- [37] = true, -- ChromieTime (Chromie Time - Burning Crusade)
	-- [38] = true, -- ChromieTime (Chromie Time - Wrath of the Lich King)
	-- [39] = true, -- ChromieTime (Chromie Time - Mists of Pandaria)
	-- [40] = true, -- ChromieTime (Chromie Time - Warlords of Draenor)
	-- [41] = true, -- ChromieTime (Chromie Time - Legion)
}

---@type table<ChatFrame, true?>
local hookedChatFrames = {}

---@class ScrollingMessageFrame : FontString, Frame

---@class ChatFrameEditBox : EditBox
---@field public autoCompleteSource? function|nil
---@field public customAutoCompleteFunction? function|nil

---@class ChatFrameLineMessageInfo
---@field public message string

---@class ChatFrameLine : FontString
---@field public messageInfo ChatFrameLineMessageInfo

---@class ChatFrame : ScrollingMessageFrame
---@field public editBox ChatFrameEditBox
---@field public visibleLines ChatFrameLine[]

local supportedChatEvents = {
	-- "CHAT_MSG_COMMUNITIES_CHANNEL", -- protected v Kstring
	"CHAT_MSG_BN",
	"CHAT_MSG_BN_CONVERSATION",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_GUIDE",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_SAY",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_YELL",
}

local function ChatInsert(text, noPadding)
	if not noPadding then
		text = format("%s ", text)
	end
	if ChatEdit_GetActiveWindow() then
		ChatEdit_InsertLink(text)
	else
		ChatFrame_OpenChat(text)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
local function GetEmoteUniqueKey(emote)
	return format("%s %s", emote.package, emote.name)
end

---@param emote ChatEmotesLib-1.0_Emote
local function IsFavorite(emote)
	local unique = GetEmoteUniqueKey(emote)
	return DB.favorites[unique]
end

---@param emote ChatEmotesLib-1.0_Emote
---@param noUpdates? boolean
local function AddToFavorites(emote, noUpdates)
	local unique = GetEmoteUniqueKey(emote)
	DB.favorites[unique] = true
	if not noUpdates then
		addonFrame:UpdateEmoteFrames(emote)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
---@param noUpdates? boolean
local function RemoveFromFavorites(emote, noUpdates)
	local unique = GetEmoteUniqueKey(emote)
	DB.favorites[unique] = nil
	if not noUpdates then
		addonFrame:UpdateEmoteFrames(emote)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
---@param noUpdates? boolean
local function ToggleFavorite(emote, noUpdates)
	if IsFavorite(emote) then
		RemoveFromFavorites(emote, noUpdates)
	else
		AddToFavorites(emote, noUpdates)
	end
	addonFrame.isSortDirty = true
end

---@param emote ChatEmotesLib-1.0_Emote
local function GetStatistics(emote, createIfMissing)
	local unique = GetEmoteUniqueKey(emote)
	local emoteStats = DB.statistics[unique]
	if createIfMissing and not emoteStats then
		emoteStats = {}
		DB.statistics[unique] = emoteStats
	end
	return emoteStats
end

---@param emotes ChatEmotesLib-1.0_Emote[]
---@param guid string
local function LogEmoteStatistics(emotes, guid)
	local isPlayer = guid == UnitGUID("player")
	for _, emote in ipairs(emotes) do
		local emoteStats = GetStatistics(emote, true)
		if isPlayer then
			emoteStats.sent = (emoteStats.sent or 0) + 1
		else
			emoteStats.received = (emoteStats.received or 0) + 1
			-- if not emoteStats.receivedFrom then
			-- 	emoteStats.receivedFrom = {}
			-- end
			-- emoteStats.receivedFrom[guid] = (emoteStats.receivedFrom[guid] or 0) + 1
		end
	end
end

---@param fontString ChatFrame|FontString
---@param forceScale? number|nil
---@param heightOffset? number|nil
---@return number
local function GetHeightForFontString(fontString, forceScale, heightOffset)
	local _, height = fontString:GetFont()
	if not height or height < 1 then
		height = CHAT_FRAME_DEFAULT_FONT_SIZE or 14 ---@diagnostic disable-line: undefined-global
	end
	if heightOffset then
		height = height + heightOffset
	end
	return height * (forceScale or DB.options.emoteScale)
end

---@param emote ChatEmotesLib-1.0_Emote
---@param heightOrObject (number|Region)?
---@param ignoreBoundaries boolean?
---@return string markup
local function GetMarkupForEmote(emote, heightOrObject, ignoreBoundaries)
	if not heightOrObject then
		return emote.markup
	end
	local keepInside = ignoreBoundaries ~= true
	if type(heightOrObject) == "number" then
		return emote("markup", heightOrObject, nil, keepInside, keepInside)
	end
	local height = heightOrObject:GetHeight()
	local width = heightOrObject:GetWidth()
	if height then
		return emote("markup", height, width, keepInside, keepInside)
	end
	return emote.markup
end

local prevLineID

---@param self ChatFrame
---@param event string
---@param text string
local function ChatMessageFilter(self, event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, ...)
	local isIgnored = zoneChannelID and zoneChannelID ~= 0 and ignoreChannels[zoneChannelID]
	if isIgnored then
		return
	end
	local isActive = not zoneChannelID or zoneChannelID == 0 or activeChannels[zoneChannelID]
	if not isActive then
		return
	end
	local height = GetHeightForFontString(self)
	local newText, usedEmotes = CEL.ReplaceEmotesInText(text, height, DB.options.emoteHover, true, MAX_EMOTES_PER_MESSAGE)
	if newText and usedEmotes then
		if prevLineID ~= lineID then
			prevLineID = lineID
			LogEmoteStatistics(usedEmotes, guid)
		end
		return false, newText, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, ...
	end
end

local GameFontDisableSmall = GameFontDisableSmall ---@diagnostic disable-line: undefined-global
local GameFontNormalSmall = GameFontNormalSmall ---@diagnostic disable-line: undefined-global
local GameFontHighlightSmall = GameFontHighlightSmall ---@diagnostic disable-line: undefined-global

local GameFontDisable = GameFontDisable ---@diagnostic disable-line: undefined-global
local GameFontNormal = GameFontNormal ---@diagnostic disable-line: undefined-global
local GameFontHighlight = GameFontHighlight ---@diagnostic disable-line: undefined-global

local GameFontDisableLarge = GameFontDisableLarge ---@diagnostic disable-line: undefined-global
local GameFontNormalLarge = GameFontNormalLarge ---@diagnostic disable-line: undefined-global
local GameFontHighlightLarge = GameFontHighlightLarge ---@diagnostic disable-line: undefined-global

---@class AutoCompleteFontPreset
---@field public id number
---@field public text string
---@field public disabled FontString|Font
---@field public normal FontString|Font
---@field public highlight FontString|Font

---@type AutoCompleteFontPreset[]
local AutoCompleteFontPresets = {
	{
		id = 1,
		text = SMALL, ---@diagnostic disable-line: undefined-global
		disabled = GameFontDisableSmall,
		normal = GameFontNormalSmall,
		highlight = GameFontHighlightSmall,
	},
	{
		id = 2,
		text = DEFAULT, ---@diagnostic disable-line: undefined-global
		disabled = GameFontDisable,
		normal = GameFontNormal,
		highlight = GameFontHighlight,
	},
	{
		id = 3,
		text = LARGE, ---@diagnostic disable-line: undefined-global
		disabled = GameFontDisableLarge,
		normal = GameFontNormalLarge,
		highlight = GameFontHighlightLarge,
	},
}

local AutoCompleteFontPresetFallback = AutoCompleteFontPresets[2]

---@param fontObjectPreset? AutoCompleteFontPreset
local function AutoCompleteFontObjectPresetFallback(fontObjectPreset)
	if DB then
		if fontObjectPreset then
			DB.options.autoCompletePreset = fontObjectPreset.id
			return fontObjectPreset
		end
		for _, _fontObjectPreset in ipairs(AutoCompleteFontPresets) do
			if _fontObjectPreset.id == DB.options.autoCompletePreset then
				return _fontObjectPreset
			end
		end
	end
	return AutoCompleteFontPresetFallback
end

---@class AutoCompleteFrame
local AutoComplete do

	local AUTOCOMPLETE_MAX_BUTTONS = AUTOCOMPLETE_MAX_BUTTONS ---@diagnostic disable-line: undefined-global
	local AUTOCOMPLETE_DEFAULT_Y_OFFSET = AUTOCOMPLETE_DEFAULT_Y_OFFSET ---@diagnostic disable-line: undefined-global

	local BUTTON_FORMAT = "|cffbbbbbb%s|r"
	local BUTTON_FORMAT_CONTINUED = "|cffbbbbbb%s (+%d)|r"
	local BUTTON_OFFSET = 10
	local BUTTON_WIDTH = 120
	local BUTTON_HEIGHT = 14
	local BUTTON_PADDING_X = 30
	local BUTTON_PADDING_Y = 35 - 10

	---@class AutoCompleteFrame : Frame, BackdropTemplate
	---@field public Instructions FontString
	---@field public Buttons AutoCompleteButton[]
	---@field public editBox ChatFrameEditBox
	---@field public attachPoint string
	---@field public results AutoCompleteResult[]
	---@field public numResults number
	---@field public fontObjectPreset AutoCompleteFontPreset
	---@field public disallowAutoComplete boolean
	---@field public selectedIndex number
	---@field public hasInsertedEmote boolean|nil

	---@class AutoCompleteButton : Button
	---@field public Text FontString
	---@field public result AutoCompleteResult

	---@class AutoCompleteResult : table
	---@field public priority number
	---@field public name string
	---@field public emote ChatEmotesLib-1.0_Emote
	---@field public from number
	---@field public to number
	---@field public favorite? boolean

	AutoComplete = CreateFrame("Frame", "VladsChatEmotesAutoCompleteFrame", UIParent, "TooltipBackdropTemplate") ---@class AutoCompleteFrame

	---@param text string
	---@param pos number
	local function GetPosition(text, pos)
		local from = 1
		local to = strlenutf8(text)
		local sfrom
		local sto
		local customChar = DB.options.autoCompleteChar
		for i = pos, 1, -1 do
			local chr = strsub(text, i, i)
			if chr == " " then
				from = i + 1
				break
			elseif chr == customChar then
				sfrom = i
				from = i + 1
				break
			end
		end
		for i = from, to do
			local chr = strsub(text, i, i)
			if chr == " " then
				to = i - 1
				break
			elseif chr == customChar then
				sto = i
				to = i - 1
				break
			end
		end
		return from, to, sfrom or from, sto or to
	end

	---@param a AutoCompleteResult
	---@param b AutoCompleteResult
	local function SortAutoCompleteResults(a, b)
		if a.priority == b.priority then
			return a.name < b.name
		end
		return a.priority < b.priority
	end

	---@param self AutoCompleteFrame
	---@param text string
	---@param cursorPosition number
	local function AutoComplete_UpdateResults(self, text, cursorPosition)
		local results = self.results
		wipe(results)
		local from, to, sfrom, sto = GetPosition(text, cursorPosition)
		local aggressiveMatched = sfrom - from == 0
		if aggressiveMatched then
			return
		end
		local len = to - from
		if len < 1 then
			return
		end
		local query = strsub(text, from, to)
		local emotes, weights = CEL.GetEmotesSearch(query, aggressiveMatched and CEL.filter.nameFindTextStartsWithCaseless or CEL.filter.nameFindTextCaseless)
		if not emotes then
			return
		end
		if emotes[2] and weights then
			CEL.SortEmotes(emotes, weights)
		end
		local index = 0
		for i = 1, emotes[0] do
			---@diagnostic disable-next-line: assign-type-mismatch
			local emote = emotes[i] ---@type ChatEmotesLib-1.0_Emote
			if not emote.ignoreSuggestion then
				local isFavorite = IsFavorite(emote)
				local priority = (isFavorite and 0 or 1000) + (emote.name:find(query, nil, true) or (100 + (emote.name:lower():find(query:lower(), nil, true) or 99)))
				index = index + 1
				results[index] = { ---@type AutoCompleteResult
					priority = priority,
					name = emote.name,
					emote = emote,
					from = sfrom,
					to = sto,
					favorite = isFavorite,
				}
			end
		end
		if not results[1] then
			return
		elseif results[2] then
			table.sort(results, SortAutoCompleteResults)
		end
	end

	---@param self AutoCompleteButton
	local function AutoCompleteButton_OnClick(self)
		local editBox = AutoComplete.editBox
		local result = self.result
		local emote = result.emote
		---@diagnostic disable-next-line: assign-type-mismatch
		local text = editBox:GetText() ---@type string
		local prefix = strsub(text, 1, result.from - 1)
		local suffix = strsub(text, result.to + 1)
		local updatedText = format("%s%s%s", prefix, emote.name, suffix)
		if not editBox:HasFocus() then
			ChatEdit_ActivateChat(editBox)
		end
		editBox:SetText(updatedText)
		editBox:SetCursorPosition(strlenutf8(updatedText) - strlenutf8(suffix))
	end

	do

		AutoComplete:Hide()
		AutoComplete:EnableMouse(true)
		AutoComplete:SetSize(5, 5)
		AutoComplete:SetPoint("CENTER")

		AutoComplete.Instructions = AutoComplete:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		AutoComplete.Instructions:SetPoint("BOTTOMLEFT", 15, 10)
		AutoComplete.Instructions:SetFormattedText(BUTTON_FORMAT, L.AUTOCOMPLETE_ACCEPT) ---@diagnostic disable-line: redundant-parameter

		AutoComplete.Buttons = {}

		do
			for i = 1, AUTOCOMPLETE_MAX_BUTTONS do
				local prevButton = AutoComplete.Buttons[i - 1]
				---@diagnostic disable-next-line: assign-type-mismatch
				local button = CreateFrame("Button", format("$parentButton%d", i), AutoComplete, "AutoCompleteButtonTemplate") ---@type AutoCompleteButton
				button.Text = _G[format("%sText", button:GetName())]
				button:Hide()
				button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
				button:SetScript("OnClick", AutoCompleteButton_OnClick)
				if not prevButton then
					button:SetPoint("TOPLEFT", 0, -BUTTON_OFFSET)
				else
					button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0)
				end
				AutoComplete.Buttons[i] = button
			end
		end

		AutoComplete.results = {}

	end

	---@param editBox ChatFrameEditBox
	function AutoComplete:ShowDropDown(editBox, userInput)
		if not editBox then
			return
		end
		if userInput and self.disallowAutoComplete then
			self:HideDropDown(editBox, true)
			return
		end
		local text = editBox:GetText()
		if not text or text == "" then
			self:HideDropDown(editBox, true)
			return
		end
		local cursorPosition = editBox:GetUTF8CursorPosition()
		if cursorPosition > strlenutf8(text) then
			self:HideDropDown(editBox, true)
			return
		end
		self:SetParent(editBox) ---@diagnostic disable-line: param-type-mismatch
		if self.editBox ~= editBox then
			self.altArrowKeyMode = editBox:GetAltArrowKeyMode()
		end
		editBox:SetAltArrowKeyMode(false)
		local attachPoint
		local _, maxHeight = self:GetBounds()
		if editBox:GetBottom() - maxHeight <= AUTOCOMPLETE_DEFAULT_Y_OFFSET + BUTTON_OFFSET then
			attachPoint = "ABOVE"
		else
			attachPoint = "BELOW"
		end
		if self.editBox ~= editBox or self.attachPoint ~= attachPoint then
			if attachPoint == "ABOVE" then
				self:ClearAllPoints()
				self:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, -AUTOCOMPLETE_DEFAULT_Y_OFFSET)
			elseif attachPoint == "BELOW" then
				self:ClearAllPoints()
				self:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, AUTOCOMPLETE_DEFAULT_Y_OFFSET)
			end
			self.attachPoint = attachPoint
		end
		self.editBox = editBox
		self:UpdateAll()
	end

	---@param editBox ChatFrameEditBox?
	function AutoComplete:HideDropDown(editBox, force)
		if not force and self.editBox ~= editBox then
			return
		end
		if not editBox then
			editBox = self.editBox
		end
		if not editBox then
			return
		end
		if self.altArrowKeyMode ~= nil then
			editBox:SetAltArrowKeyMode(self.altArrowKeyMode)
			self.altArrowKeyMode = nil
		end
		self:SetSelectedIndex(1)
		self:Hide()
		self.editBox = nil
	end

	function AutoComplete:UpdateAll()
		self:UpdateResults()
		self:DisplayResults()
	end

	function AutoComplete:UpdateResults()
		local editBox = self.editBox
		if not editBox then
			return
		end
		---@diagnostic disable-next-line: assign-type-mismatch
		local text = editBox:GetText() ---@type string
		---@diagnostic disable-next-line: assign-type-mismatch
		local cursorPosition = editBox:GetUTF8CursorPosition() ---@type number
		AutoComplete_UpdateResults(self, text, cursorPosition)
	end

	function AutoComplete:DisplayResults()
		local results = self.results
		local totalReturns = #results
		local numResults = min(totalReturns, AUTOCOMPLETE_MAX_BUTTONS)
		local maxWidth = BUTTON_WIDTH
		local maxEmoteSize = 12
		for i = 1, numResults do
			local result = self.results[i]
			local emote = result.emote
			local button = self.Buttons[i]
			button.result = result
			button:SetFormattedText("%s |cff%s%s|r", GetMarkupForEmote(emote, maxEmoteSize), result.favorite and "FFFF55" or "FFFFFF", emote.name)
			maxWidth = max(maxWidth, button.Text:GetStringWidth() + BUTTON_PADDING_X)
			button:Show()
		end
		for i = numResults + 1, AUTOCOMPLETE_MAX_BUTTONS do
			self.Buttons[i]:Hide()
		end
		AutoComplete.Instructions:SetFormattedText(totalReturns > AUTOCOMPLETE_MAX_BUTTONS and BUTTON_FORMAT_CONTINUED or BUTTON_FORMAT, L.AUTOCOMPLETE_ACCEPT, totalReturns - numResults) ---@diagnostic disable-line: redundant-parameter
		self.numResults = numResults
		local selectedIndex = self:GetSelectedIndex()
		if not selectedIndex or selectedIndex > numResults then
			self:SetSelectedIndex(1)
		end
		if numResults > 0 then
			self:UpdateSize()
			self:Show()
			C_Timer.After(0.05, function() self:UpdateSize() end) -- TODO
		else
			self:Hide()
		end
	end

	function AutoComplete:SetSelectedIndex(index)
		self.selectedIndex = index
		for i = 1, AUTOCOMPLETE_MAX_BUTTONS do
			local button = self.Buttons[i]
			if i == index then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
		end
	end

	function AutoComplete:GetSelectedIndex()
		return self.selectedIndex
	end

	function AutoComplete:GetSelected()
		local index = self.selectedIndex
		if not index then
			return
		end
		local button = self.Buttons[index]
		if not button:IsShown() then
			return
		end
		return button
	end

	---@param editBox ChatFrameEditBox
	---@param reversed boolean
	function AutoComplete:OnTab(editBox, reversed)
		if self.editBox ~= editBox or not self:IsShown() then
			return
		end
		local selectedIndex = self:GetSelectedIndex()
		if reversed then
			selectedIndex = selectedIndex - 1
			if selectedIndex < 1 then
				selectedIndex = self.numResults
			end
		else
			selectedIndex = selectedIndex + 1
			if selectedIndex > self.numResults then
				selectedIndex = 1
			end
		end
		self:SetSelectedIndex(selectedIndex)
	end

	---@param editBox ChatFrameEditBox
	function AutoComplete:OnEnter(editBox)
		if self.editBox ~= editBox or not self:IsShown() then
			return
		end
		local button = self:GetSelected()
		if not button then
			return
		end
		button:Click()
		return true
	end

	---@param editBox ChatFrameEditBox
	---@param step number
	function AutoComplete:OnArrow(editBox, step)
		if self.editBox ~= editBox or not self:IsShown() then
			return
		end
		self:OnTab(editBox, step < 1)
	end

	---@param editBox ChatFrameEditBox
	---@param char string
	function AutoComplete:RemoveTrailingCharacter(editBox, char)
		---@diagnostic disable-next-line: assign-type-mismatch
		local index = editBox:GetCursorPosition() ---@type number
		---@diagnostic disable-next-line: assign-type-mismatch
		local text = editBox:GetText() ---@type string
		local mid = strsub(text, index, index)
		if mid ~= char then
			return
		end
		local left = strsub(text, 1, index - 1)
		local right = strsub(text, index + 1)
		editBox:SetText(format("%s%s", left, right))
		editBox:SetCursorPosition(index - 1)
	end

	function AutoComplete:GetFontObjectPreset()
		return self.fontObjectPreset
	end

	---@param fontObjectPreset? AutoCompleteFontPreset
	function AutoComplete:SetFontObjectPreset(fontObjectPreset)
		fontObjectPreset = AutoCompleteFontObjectPresetFallback(fontObjectPreset)
		if self.fontObjectPreset == fontObjectPreset then
			return
		end
		self.Instructions:SetFontObject(fontObjectPreset.disabled) ---@diagnostic disable-line: param-type-mismatch
		for _, button in pairs(self.Buttons) do
			button:SetNormalFontObject(fontObjectPreset.normal) ---@diagnostic disable-line: param-type-mismatch
			button:SetHighlightFontObject(fontObjectPreset.highlight) ---@diagnostic disable-line: param-type-mismatch
		end
		self.Instructions:SetHeight(self.Instructions:GetStringHeight()) ---@diagnostic disable-line: param-type-mismatch
		self.fontObjectPreset = fontObjectPreset
	end

	---@return number, number, number@`height`, `maxHeight`, `maxWidth`
	function AutoComplete:GetBounds()
		local height = max(self.Instructions:GetHeight(), self.Instructions:GetStringHeight())
		local maxHeight = height
		local maxWidth = BUTTON_WIDTH
		for _, button in pairs(self.Buttons) do
			local buttonHeight = max(button:GetHeight(), button.Text:GetStringHeight())
			local buttonWidth = max(button:GetWidth(), button.Text:GetStringWidth())
			if button:IsShown() then
				height = height + buttonHeight
				maxWidth = max(maxWidth, buttonWidth + BUTTON_PADDING_X)
			end
			maxHeight = maxHeight + buttonHeight
		end
		maxWidth = max(maxWidth, max(self.Instructions:GetWidth(), self.Instructions:GetStringWidth()) + BUTTON_PADDING_X)
		return height, maxHeight, maxWidth
	end

	function AutoComplete:UpdateSize()
		local height, _, maxWidth = self:GetBounds()
		self:SetSize(maxWidth, height + BUTTON_PADDING_Y)
	end

	AutoComplete:SetFontObjectPreset()

end

---@param self ChatFrameEditBox
local function ChatEditBoxOnChanged(self, userInput)
	if not DB.options.enableAutoComplete then
		return
	end
	local text = self:GetText()
	if not text or AutoCompleteBox:IsShown() then ---@diagnostic disable-line: undefined-global
		AutoComplete:HideDropDown(self)
	else
		AutoComplete:ShowDropDown(self, userInput == true)
	end
end

---@param self ChatFrameEditBox
local function ChatEditBoxOnTabPressed(self)
	if not DB.options.enableAutoComplete then
		return
	end
	AutoComplete:OnTab(self, IsShiftKeyDown())
end

---@param self ChatFrameEditBox
local function ChatEditBoxOnArrow(self, key)
	if not DB.options.enableAutoComplete then
		return
	end
	if key == "UP" then
		AutoComplete:OnArrow(self, -1)
	elseif key == "DOWN" then
		AutoComplete:OnArrow(self, 1)
	else
		ChatEditBoxOnChanged(self)
	end
end

---@param self ChatFrameEditBox
local function ChatEditBoxOnKeyDown(self, key)
	if not DB.options.enableAutoComplete then
		return
	end
	if key == "BACKSPACE" then
		AutoComplete.disallowAutoComplete = true
	elseif key == "SPACE" then
		AutoComplete.hasInsertedEmote = AutoComplete:OnEnter(self)
	end
end

---@param self ChatFrameEditBox
local function ChatEditBoxOnKeyUp(self, key)
	if not DB.options.enableAutoComplete then
		return
	end
	if key == "BACKSPACE" then
		AutoComplete.disallowAutoComplete = false
	elseif key == "SPACE" then
		if AutoComplete.hasInsertedEmote then
			AutoComplete.hasInsertedEmote = nil
			-- AutoComplete:RemoveTrailingCharacter(self, " ") -- TODO: it's probably best to keep the inserted space as most times you want to write something following the emote and pressing space twice to select then add a space felt more unnatural
		end
	end
end

---@param self ChatFrameEditBox
local function ChatEditBoxOnFocusLost(self)
	AutoComplete:HideDropDown(self)
end

---@param self ChatFrame
---@param link string
---@param text string
---@param button string
local function ChatFrameOnHyperlinkClick(self, link, text, button)
	if not DB.options.emoteHover then
		return
	end
	local emote = CEL.GetEmoteFromLink(link)
	if not emote then
		return
	end
	if button == "RightButton" then
		addon:TogglePicker(emote)
	else
		ChatInsert(emote.name)
	end
end

---@param self ChatFrame
---@param link string
---@param text string
local function ChatFrameOnHyperlinkEnter(self, link, text)
	if not DB.options.emoteHover then
		return
	end
	local emote = CEL.GetEmoteFromLink(link)
	if not emote then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, 0)
	GameTooltip:AddLine(tostring(emote.name), 1, 1, 1)
	GameTooltip:AddLine(GetMarkupForEmote(emote, 32), 1, 1, 1)
	GameTooltip:AddLine(tostring(emote.package), 0.5, 0.5, 0.5)
	GameTooltip:AddLine(tostring(emote.folder), 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

---@param self ChatFrame
---@param link string
---@param text string
local function ChatFrameOnHyperlinkLeave(self, link, text)
	if not DB.options.emoteHover then
		return
	end
	GameTooltip:Hide()
end

local PackageSortOrder = {
	["Discord"] = 1,
	["BTTV"] = 2,
	["Twitch"] = 3,
	FALLBACK = 1000,
}

---@param a ChatEmotesLib-1.0_Emote
---@param b ChatEmotesLib-1.0_Emote
local function SortEmotes(a, b)
	local x = PackageSortOrder[a.package] or PackageSortOrder.FALLBACK ---@type number|string
	local y = PackageSortOrder[b.package] or PackageSortOrder.FALLBACK ---@type number|string
	if x == y then
		x = a.folder
		y = b.folder
		if x == y then
			return a.index < b.index
		end
		return x < y
	end
	return x < y
end

---@type ChatEmotesLib-1.0_Emote[]
local sortedEmotes

local function GetRandomEmote()
	local index = random(1, min(100, max(1, #sortedEmotes)))
	return sortedEmotes[index]
end

local CreateUI
local CreateButton
local CreateConfig

do

	---@class CallbackRegistryMixin : Frame
	---@field public OnLoad function
	---@field public GenerateCallbackEvents function
	---@field public TriggerEvent function
	---@field public RegisterCallback fun(self: CallbackRegistryMixin, event: any, callback: fun(...: any), context: any)

	---@class ScrollBoxListViewMixin : CallbackRegistryMixin
	---@field public FindFrame fun(self: ScrollBoxListViewMixin, elementData: ChatEmotesUIScrollBoxEmoteButtonMixin): ChatEmotesUIScrollBoxEmoteButtonMixin?
	---@field public HasScrollableExtent fun(self: ScrollBoxListViewMixin)
	---@field public ScrollToEnd fun(self: ScrollBoxListViewMixin, noInterpolation: any)
	---@field public GetScrollPercentage fun(self: ScrollBoxListViewMixin)
	---@field public GetVisibleExtentPercentage fun(self: ScrollBoxListViewMixin)
	---@field public IsScrollAllowed fun(self: ScrollBoxListViewMixin)
	---@field public GetView fun(self: ScrollBoxListViewMixin): ScrollBoxListViewMixin
	---@field public Init fun(self: ScrollBoxListViewMixin, view: ScrollBoxListViewMixin)
	---@field public SetView fun(self: ScrollBoxListViewMixin, view: ScrollBoxListViewMixin)
	---@field public Flush fun(self: ScrollBoxListViewMixin)
	---@field public ForEachFrame fun(self: ScrollBoxListViewMixin, callback: fun(button: ChatEmotesUIScrollBoxEmoteButtonMixin))
	---@field public EnumerateFrames fun(self: ScrollBoxListViewMixin): fun(): number, ChatEmotesUIScrollBoxEmoteButtonMixin
	---@field public FindElementDataByPredicate fun(self: ScrollBoxListViewMixin, predicate: fun(): boolean?): button: ChatEmotesUIScrollBoxEmoteButtonMixin?
	---@field public FindElementDataIndexByPredicate fun(self: ScrollBoxListViewMixin, predicate: fun(): boolean?): button: ChatEmotesUIScrollBoxEmoteButtonMixin?
	---@field public FindByPredicate fun(self: ScrollBoxListViewMixin, predicate: fun(): boolean?): button: ChatEmotesUIScrollBoxEmoteButtonMixin?
	---@field public Find fun(self: ScrollBoxListViewMixin, index: number): button: ChatEmotesUIScrollBoxEmoteButtonMixin?
	---@field public FindIndex fun(self: ScrollBoxListViewMixin, elementData: ChatEmotesUIScrollBoxEmoteButtonMixin): button: ChatEmotesUIScrollBoxEmoteButtonMixin?
	---@field public InsertElementData fun(self: ScrollBoxListViewMixin, ...: any)
	---@field public InsertElementDataTable fun(self: ScrollBoxListViewMixin, tbl: any[])
	---@field public InsertElementDataTableRange fun(self: ScrollBoxListViewMixin, tbl: any[], indexBegin: number, indexEnd: number)
	---@field public ContainsElementDataByPredicate fun(self: ScrollBoxListViewMixin, predicate: fun(elementData: ChatEmotesUIScrollBoxEmoteButtonMixin): boolean?)
	---@field public GetDataProvider fun(self: ScrollBoxListViewMixin): ChatEmotesDataProvider
	---@field public HasDataProvider fun(self: ScrollBoxListViewMixin): boolean
	---@field public ClearDataProvider fun(self: ScrollBoxListViewMixin)
	---@field public GetDataIndexBegin fun(self: ScrollBoxListViewMixin): number
	---@field public GetDataIndexEnd fun(self: ScrollBoxListViewMixin): number
	---@field public IsVirtualized fun(self: ScrollBoxListViewMixin): boolean
	---@field public GetElementExtent fun(self: ScrollBoxListViewMixin, dataIndex: number)
	---@field public GetExtentUntil fun(self: ScrollBoxListViewMixin, dataIndex: number)
	---@field public SetDataProvider fun(self: ScrollBoxListViewMixin, dataProvider: ChatEmotesDataProvider, retainScrollPosition: boolean?)
	---@field public GetDataProviderSize fun(self: ScrollBoxListViewMixin)
	---@field public OnViewDataChanged fun(self: ScrollBoxListViewMixin)
	---@field public Rebuild fun(self: ScrollBoxListViewMixin)
	---@field public OnViewAcquiredFrame fun(self: ScrollBoxListViewMixin, frame: ChatEmotesUIScrollBoxEmoteButtonMixin, elementData: ChatEmotesLib-1.0_Emote, new: any)
	---@field public OnViewReleasedFrame fun(self: ScrollBoxListViewMixin, frame: ChatEmotesUIScrollBoxEmoteButtonMixin, oldElementData: ChatEmotesLib-1.0_Emote)
	---@field public IsAcquireLocked fun(self: ScrollBoxListViewMixin)
	---@field public FullUpdateInternal fun(self: ScrollBoxListViewMixin)
	---@field public Update fun(self: ScrollBoxListViewMixin, forceLayout: boolean?)
	---@field public ScrollToElementDataByPredicate fun(self: ScrollBoxListViewMixin, predicate: (fun(elementData: ChatEmotesLib-1.0_Emote): boolean?), alignment?: number, offset?: number, noInterpolation?: boolean): ChatEmotesUIScrollBoxEmoteButtonMixin?

	---@class WowScrollBoxList : ScrollBoxListViewMixin, Frame
	---@field public Background Texture

	---@class ChatEmotesUIScrollCollectionMixin : CallbackRegistryMixin

	---@param scrollBox ScrollBoxListViewMixin
	local function SetScrollBoxButtonAlternateState(scrollBox)
		local index = scrollBox:GetDataIndexBegin()
		scrollBox:ForEachFrame(function(button)
			button:SetAlternateOverlayShown(index % 2 == 1)
			index = index + 1
		end)
	end

	---@class ChatEmotesUIScrollCollectionMixin
	local UIScrollCollectionMixin = CreateFromMixins(CallbackRegistryMixin)

	UIScrollCollectionMixin:GenerateCallbackEvents({
		"OnHide",
		"OnShow",
		"OnSizeChanged",
		"OnScroll", -- WowScrollBoxList
		"OnAllowScrollChanged", -- WowScrollBoxList
	})

	function UIScrollCollectionMixin:OnLoad()
		CallbackRegistryMixin.OnLoad(self)
	end

	function UIScrollCollectionMixin:OnHide()
		self:TriggerEvent("OnHide")
	end

	function UIScrollCollectionMixin:OnShow()
		self:TriggerEvent("OnShow")
	end

	function UIScrollCollectionMixin:OnSizeChanged(width, height)
		self:TriggerEvent("OnSizeChanged", width, height)
	end

	---@class ChatEmotesUIScrollBoxEmoteButtonMixin : Button
	---@field public isInitialized? boolean

	---@class ChatEmotesUIScrollBoxEmoteButtonMixin
	local UIScrollBoxEmoteButtonMixin = {}

	local ScrollBoxEmoteButtonSize = 30

	function UIScrollBoxEmoteButtonMixin:OnLoad()
		-- self:SetHeight(ButtonSize)
		self:SetSize(ScrollBoxEmoteButtonSize, ScrollBoxEmoteButtonSize) -- grid
		self.Label = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		self.Label:SetJustifyH("CENTER")
		self.Label:SetJustifyV("MIDDLE")
		self.Label:SetAllPoints()
		self.Label:SetScale(2)
		self.Background = self:CreateTexture(nil, "BACKGROUND", nil, 1)
		self.Background:SetAllPoints()
		self.Background:SetColorTexture(0.1, 0.1, 0.1, 1)
		self.MouseoverOverlay = self:CreateTexture(nil, "ARTWORK", nil, 2)
		self.MouseoverOverlay:SetAllPoints()
		self.MouseoverOverlay:SetColorTexture(0.5, 0.5, 0.5, 1)
		self.MouseoverOverlay:Hide()
		self.Alternate = self:CreateTexture(nil, "BACKGROUND", nil, 2)
		self.Alternate:SetAllPoints()
		self.Alternate:SetColorTexture(0.2, 0.2, 0.2, 1)
		self.Alternate:Hide()
		self.Star = self:CreateTexture(nil, "OVERLAY", nil, 1)
		-- self.Star:SetTexture(2923258)
		-- self.Star:SetTexCoord(2/32, 16/32, 2/32, 16/32)
		self.Star:SetTexture(984826)
		self.Star:SetTexCoord(99/512, 117/512, 10/512, 28/512)
		self.Star:SetSize(10, 10)
		self.Star:SetPoint("TOPRIGHT", -0.5, -1)
		self.Star:Hide()
		self.FlashOverlay = self:CreateAnimationGroup() ---@class ChatEmotesUIScrollBoxEmoteButtonMixinFlashOverlay : AnimationGroup
		self.FlashOverlay.duration = 1.5
		self.FlashOverlay.scale = 1.1
		self.FlashOverlay.alphaFrom = 1
		self.FlashOverlay.alphaTo = 0.8
		self.FlashOverlay.Background = self:CreateTexture(nil, "ARTWORK", nil, 3)
		self.FlashOverlay.Background:SetAllPoints()
		self.FlashOverlay.Background:SetColorTexture(0.25, 0.25, 0.25, 1)
		self.FlashOverlay.Background:Hide()
		self.FlashOverlay.BackgroundFadeIn = self.FlashOverlay:CreateAnimation("Alpha")
		self.FlashOverlay.BackgroundFadeIn:SetOrder(1)
		self.FlashOverlay.BackgroundFadeIn:SetTarget(self.FlashOverlay.Background)
		self.FlashOverlay.BackgroundFadeIn:SetDuration(self.FlashOverlay.duration*0.2)
		self.FlashOverlay.BackgroundFadeIn:SetFromAlpha(0)
		self.FlashOverlay.BackgroundFadeIn:SetToAlpha(1)
		self.FlashOverlay.BackgroundFadeOut = self.FlashOverlay:CreateAnimation("Alpha")
		self.FlashOverlay.BackgroundFadeOut:SetOrder(3)
		self.FlashOverlay.BackgroundFadeOut:SetTarget(self.FlashOverlay.Background)
		self.FlashOverlay.BackgroundFadeOut:SetDuration(self.FlashOverlay.duration*0.2)
		self.FlashOverlay.BackgroundFadeOut:SetFromAlpha(1)
		self.FlashOverlay.BackgroundFadeOut:SetToAlpha(0)
		self.FlashOverlay.BackgroundFadeOut:SetSmoothing("OUT")
		self.FlashOverlay.Rotate = self.FlashOverlay:CreateAnimation("Rotation")
		self.FlashOverlay.Rotate:SetOrder(1)
		self.FlashOverlay.Rotate:SetDuration(self.FlashOverlay.duration/2)
		self.FlashOverlay.Rotate:SetDegrees(360)
		self.FlashOverlay.Rotate:SetSmoothing("IN_OUT")
		self.FlashOverlay.Scale1 = self.FlashOverlay:CreateAnimation("Scale")
		self.FlashOverlay.Scale1:SetOrder(1)
		self.FlashOverlay.Scale1:SetDuration(self.FlashOverlay.duration*0.4)
		self.FlashOverlay.Scale1:SetScaleFrom(1, 1)
		self.FlashOverlay.Scale1:SetScaleTo(self.FlashOverlay.scale, self.FlashOverlay.scale)
		self.FlashOverlay.Scale2 = self.FlashOverlay:CreateAnimation("Scale")
		self.FlashOverlay.Scale2:SetOrder(2)
		self.FlashOverlay.Scale2:SetDuration(self.FlashOverlay.duration*0.4)
		self.FlashOverlay.Scale2:SetScaleFrom(self.FlashOverlay.scale, self.FlashOverlay.scale)
		self.FlashOverlay.Scale2:SetScaleTo(1, 1)
		self.FlashOverlay.Scale2:SetSmoothing("OUT")
		self.FlashOverlay.Alpha1 = self.FlashOverlay:CreateAnimation("Alpha")
		self.FlashOverlay.Alpha1:SetOrder(1)
		self.FlashOverlay.Alpha1:SetDuration(self.FlashOverlay.duration*0.4)
		self.FlashOverlay.Alpha1:SetFromAlpha(self.FlashOverlay.alphaFrom)
		self.FlashOverlay.Alpha1:SetToAlpha(self.FlashOverlay.alphaTo)
		self.FlashOverlay.Alpha2 = self.FlashOverlay:CreateAnimation("Alpha")
		self.FlashOverlay.Alpha2:SetOrder(2)
		self.FlashOverlay.Alpha2:SetDuration(self.FlashOverlay.duration*0.4)
		self.FlashOverlay.Alpha2:SetFromAlpha(self.FlashOverlay.alphaFrom)
		self.FlashOverlay.Alpha2:SetToAlpha(self.FlashOverlay.alphaTo)
		self.FlashOverlay.Alpha3 = self.FlashOverlay:CreateAnimation("Alpha")
		self.FlashOverlay.Alpha3:SetOrder(3)
		self.FlashOverlay.Alpha3:SetDuration(self.FlashOverlay.duration*0.2)
		self.FlashOverlay.Alpha3:SetFromAlpha(self.FlashOverlay.alphaTo)
		self.FlashOverlay.Alpha3:SetToAlpha(self.FlashOverlay.alphaFrom)
		self.FlashOverlay:SetScript("OnPlay", function() self.FlashOverlay.Background:Show() end)
		self.FlashOverlay:SetScript("OnStop", function() self.FlashOverlay.Background:Hide() end)
		self.FlashOverlay:SetScript("OnFinished", function() self.FlashOverlay.Background:Hide() end)
		self:SetScript("OnEnter", self.OnEnter)
		self:SetScript("OnLeave", self.OnLeave)
		self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		self:SetScript("OnClick", self.OnClick)
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIScrollBoxEmoteButtonMixin:Init(emote)
		self.emote = emote
		self.Label:SetText(GetMarkupForEmote(emote, 14)) -- self.Label
		self.FlashOverlay:Stop()
		self.FlashOverlay:Finish()
		self:Update()
	end

	function UIScrollBoxEmoteButtonMixin:OnEnter()
		self.MouseoverOverlay:Show()
		local emote = self.emote
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
		GameTooltip:AddLine(tostring(emote.name), 1, 1, 1)
		-- GameTooltip:AddLine(GetMarkupForEmote("markup", 32), 1, 1, 1)
		GameTooltip:AddLine(tostring(emote.package), 0.5, 0.5, 0.5)
		GameTooltip:AddLine(tostring(emote.folder), 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end

	function UIScrollBoxEmoteButtonMixin:OnLeave()
		self.MouseoverOverlay:Hide()
		GameTooltip:Hide()
	end

	function UIScrollBoxEmoteButtonMixin:OnClick(button)
		local emote = self.emote
		if button == "LeftButton" then
			ChatInsert(emote.name)
		elseif button == "RightButton" then
			ToggleFavorite(emote)
		end
	end

	function UIScrollBoxEmoteButtonMixin:SetAlternateOverlayShown(alternate)
		self.Alternate:SetShown(alternate)
	end

	function UIScrollBoxEmoteButtonMixin:Update()
		local emote = self.emote
		local isFavorite = IsFavorite(emote)
		self.Star:SetShown(isFavorite)
		-- if isFavorite then
		-- 	self.Background:SetColorTexture(0.2, 0.2, 0, 1)
		-- 	self.MouseoverOverlay:SetColorTexture(0.6, 0.6, 0.4, 1)
		-- else
		-- 	self.Background:SetColorTexture(0.1, 0.1, 0.1, 1)
		-- 	self.MouseoverOverlay:SetColorTexture(0.4, 0.4, 0.4, 1)
		-- end
	end

	function UIScrollBoxEmoteButtonMixin:Flash()
		self.FlashOverlay:Play()
	end

	local MinPanelWidth = 400
	local MinPanelHeight = 320
	local MaxPanelWidth = MinPanelWidth * 2
	local MaxPanelHeight = MinPanelHeight * 2
	local DefaultPanelWidth = MinPanelWidth
	local DefaultPanelHeight = MinPanelHeight
	local isGridView = true
	local SearchMaxResults = 200

	---@alias ChatEmotesDataProviderEnumerator fun(): number, ChatEmotesLib-1.0_Emote

	---@alias ChatEmotesDataProviderCallback fun(elementData: ChatEmotesLib-1.0_Emote)

	---@alias ChatEmotesDataProviderPredicate fun(elementData: ChatEmotesLib-1.0_Emote): boolean?

	---@class ChatEmotesDataProvider
	---@field public collection ChatEmotesLib-1.0_Emote[]
	---@field public RegisterCallback fun(self: ChatEmotesDataProvider, event: any, callback: fun(...: any), context: any)
	---@field public Insert fun(self: ChatEmotesDataProvider, elementData: ChatEmotesLib-1.0_Emote)
	---@field public InsertTableRange fun(self: ChatEmotesDataProvider, elements: ChatEmotesLib-1.0_Emote[], position: number, element: ChatEmotesLib-1.0_Emote)
	---@field public Flush fun(self: ChatEmotesDataProvider)
	---@field public GetCollection fun(self: ChatEmotesDataProvider): collection: ChatEmotesLib-1.0_Emote[]
	---@field public GetSize fun(self: ChatEmotesDataProvider): size: number
	---@field public IsEmpty fun(self: ChatEmotesDataProvider): isEmpty: boolean
	---@field public Sort fun(self: ChatEmotesDataProvider)
	---@field public HasSortComparator fun(self: ChatEmotesDataProvider): boolean
	---@field public ClearSortComparator fun(self: ChatEmotesDataProvider)
	---@field public SetSortComparator fun(self: ChatEmotesDataProvider, sortComparator: (fun(a: ChatEmotesLib-1.0_Emote, b: ChatEmotesLib-1.0_Emote): boolean?), skipSort?: boolean)
	---@field public Enumerate fun(): enumerator: ChatEmotesDataProviderEnumerator
	---@field public ReverseEnumerate fun(): enumerator: ChatEmotesDataProviderEnumerator
	---@field public ForEach fun(self: ChatEmotesDataProvider, callback: ChatEmotesDataProviderCallback)
	---@field public ReverseForEach fun(self: ChatEmotesDataProvider, callback: ChatEmotesDataProviderCallback)
	---@field public Find fun(self: ChatEmotesDataProvider, index: number): elementData: ChatEmotesLib-1.0_Emote?
	---@field public FindByPredicate fun(self: ChatEmotesDataProvider, predicate: ChatEmotesDataProviderPredicate): index: number?, elementData: ChatEmotesLib-1.0_Emote?
	---@field public FindElementDataByPredicate fun(self: ChatEmotesDataProvider, predicate: ChatEmotesDataProviderPredicate): elementData: ChatEmotesLib-1.0_Emote?
	---@field public FindIndex fun(self: ChatEmotesDataProvider, elementData: ChatEmotesLib-1.0_Emote): index: number?
	---@field public FindIndexByPredicate fun(self: ChatEmotesDataProvider, predicate: ChatEmotesDataProviderPredicate): index: number?
	---@field public ContainsByPredicate fun(self: ChatEmotesDataProvider, predicate: ChatEmotesDataProviderPredicate): contains: boolean

	---@class ChatEmotesUIMixinTitleBar : Frame
	---@field public Init fun(self: ChatEmotesUIMixinTitleBar, parent: ChatEmotesUIMixin)

	---@class ChatEmotesUIMixinResizeButton : Button
	---@field public Init fun(self: ChatEmotesUIMixinResizeButton, parent: ChatEmotesUIMixin, minWidth: number, minHeight: number, maxWidth: number, maxHeight: number)

	---@class ChatEmotesUIMixinConfigButton : Button
	---@field public Texture Texture

	---@class ChatEmotesUIMixinLog : Frame

	---@class ChatEmotesUIMixinLogBar : Frame

	---@class ChatEmotesUIMixinLogBarSearchBox : EditBox

	---@class ChatEmotesUIMixinScrollFrame : Frame
	---@field public Background Texture
	---@field public ScrollBox WowScrollBoxList
	---@field public ScrollBar ChatEmotesUIScrollCollectionMixin

	---@class ChatEmotesUIMixinLogEvents : ChatEmotesUIMixinScrollFrame

	---@class ChatEmotesUIMixinLogSearch : ChatEmotesUIMixinScrollFrame

	---@class ChatEmotesUIMixinMissingEmotePackage : Frame

	---@class ChatEmotesUIMixin : Frame
	---@field public isSortDirty? boolean
	---@field public emotes ChatEmotesLib-1.0_Emote[]
	---@field public emotesMap table<ChatEmotesLib-1.0_Emote, number>
	---@field public showingArguments boolean
	---@field public filterDataProvider ChatEmotesDataProvider
	---@field public logDataProvider ChatEmotesDataProvider
	---@field public searchDataProvider ChatEmotesDataProvider
	---@field public pendingSearch? ChatEmotesLib-1.0_Emote
	---@field public Inset Frame
	---@field public NineSlice? Frame
	---@field public SetTitle fun(self: ChatEmotesUIMixin, text: string)

	---@class ChatEmotesUIMixin
	local UIMixin = {}

	function UIMixin:OnLoad()
		self:SetToplevel(true)
		self:SetMovable(true)
		self:SetResizable(true)
		self:EnableMouse(true)
		self:SetClampedToScreen(true)
		self:SetSize(DefaultPanelWidth, DefaultPanelHeight)
		ButtonFrameTemplate_HidePortrait(self) ---@diagnostic disable-line: undefined-global
		if self.NineSlice then
			self.NineSlice:SetPoint("TOPLEFT", -1, 0)
		end
		self.Inset:SetPoint("TOPLEFT", 4, -24) -- -60
		self.TitleBar:Init(self)
		self.ResizeButton:Init(self, MinPanelWidth, MinPanelHeight, MaxPanelWidth, MaxPanelHeight)
		self:SetTitle(L.CHAT_EMOTES)
		self.showingArguments = false
		self.filterDataProvider = CreateDataProvider()
		self.logDataProvider = CreateDataProvider()
		self.searchDataProvider = CreateDataProvider()
		self.searchDataProvider:RegisterCallback(DataProviderMixin.Event.OnSizeChanged, self.OnSearchDataProviderChanged, self)
		self:InitializeLog()
		self:HookScript("OnShow", self.OnShow)
		self:HookScript("OnHide", self.OnHide)
		self.ConfigButton:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHAT_EMOTE_BUTTON) ---@diagnostic disable-line: undefined-global
			addon:ToggleConfig()
		end)
		self.ConfigButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(self.ConfigButton, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, L.OPTIONS) ---@diagnostic disable-line: undefined-global
			GameTooltip:Show()
		end)
		self.ConfigButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	function UIMixin:OnShow()
		local position = DB.position
		local width, height = position.width, position.height
		if not width then
			width, height = DefaultPanelWidth, DefaultPanelHeight
		end
		local point, relativeTo, relativePoint, x, y = position.point, position.relativeTo, position.relativePoint, position.x, position.y
		if not point then
			point, relativeTo, relativePoint, x, y = "CENTER", nil, "CENTER", 0, 0
		end
		self:SetSize(width, height)
		self:ClearAllPoints()
		self:SetPoint(point, relativeTo, relativePoint, x, y) ---@diagnostic disable-line: param-type-mismatch
		self.MissingEmotePackage:SetShown(self.logDataProvider:GetSize() == 0)
		if not self.isSortDirty then
			return
		end
		self.isSortDirty = false
		---@param a ChatEmotesLib-1.0_Emote
		---@param b ChatEmotesLib-1.0_Emote
		local function SortFavoritesFirst(a, b)
			local af = IsFavorite(a) and 1 or 0
			local bf = IsFavorite(b) and 1 or 0
			if af == bf then
				local ai = self.emotesMap[a]
				local bi = self.emotesMap[b]
				return ai < bi
			end
			return af > bf
		end
		self.logDataProvider:SetSortComparator(SortFavoritesFirst)
		self.logDataProvider:ClearSortComparator()
		self.searchDataProvider:SetSortComparator(SortFavoritesFirst)
		self.searchDataProvider:ClearSortComparator()
	end

	function UIMixin:OnHide()
		local point, relativeTo, relativePoint, x, y = self:GetPoint(1)
		if not point then
			return
		end
		local position = DB.position
		position.width, position.height = self:GetSize()
		position.point, position.relativeTo, position.relativePoint, position.x, position.y = point, relativeTo and relativeTo:GetName() or nil, relativePoint, x, y
	end

	function UIMixin:OnSearchDataProviderChanged(hasSortComparator)
		local size = self.searchDataProvider:GetSize()
		local text = L.SEARCH_RESULTS:format(size)
		self.Log.Bar.Label:SetText(text)
	end

	---@param elementData ChatEmotesLib-1.0_Emote
	---@param search string
	function UIMixin:TryAddToSearch(elementData, search)
		if not search or search == "" then
			return false
		end
		local searchTrimmed = search:trim() ---@diagnostic disable-line: undefined-field
		if searchTrimmed:len() < 2 then
			return false
		end
		local searchLC = searchTrimmed:lower()
		local found
		if searchLC == "animated" then
			found = elementData.animated
		elseif elementData.package:lower():find(searchLC, nil, true) == 1 then
			found = true
		elseif elementData.folder:lower():find(searchLC, nil, true) == 1 then
			found = true
		elseif elementData.name:lower():find(searchLC, nil, true) then
			found = true
		elseif elementData.alias then
			for _, alias in ipairs(elementData.alias) do
				if alias:lower():find(searchLC, nil, true) then
					found = true
					break
				end
			end
		end
		if found then
			self.searchDataProvider:Insert(elementData)
			-- self.searchDataProvider:Insert(CopyTable(elementData, true)) -- shallow
			return true
		end
		return false
	end

	function UIMixin:DisplayEvents()
		self.Log.Bar.Label:SetText()
		self.Log.Search:Hide()
		self.Log.Events:Show()
	end

	function UIMixin:DisplaySearch()
		self.Log.Events:Hide()
		self.Log.Search:Show()
	end

	---@param elementData ChatEmotesLib-1.0_Emote
	function UIMixin:RemoveFromDataProvider(dataProvider, elementData)
		local index = dataProvider:GetSize()
		while index >= 1 do
			local _elementData = dataProvider:Find(index) ---@type ChatEmotesLib-1.0_Emote
			if _elementData == elementData then
				dataProvider:RemoveIndex(index)
			end
			index = index - 1
		end
	end

	function UIMixin:InitializeLog()
		self.Log.Bar.Label:SetText()
		self.Log.Bar.SearchBox:HookScript("OnTextChanged", function()
			self.searchDataProvider:Flush()
			---@diagnostic disable-next-line: assign-type-mismatch
			local text = self.Log.Bar.SearchBox:GetText() ---@type string
			---@diagnostic disable-next-line: undefined-field
			local empty = not text or text:len() == 0 or text:trim():len() < 2 -- min length requirement before searching
			if empty then
				self:DisplayEvents()
				return
			end
			self:DisplaySearch()
			local found = 0
			---@diagnostic disable-next-line: undefined-field
			text = text:trim() ---@type string
			for index, elementData in self.logDataProvider:Enumerate() do
				if self:TryAddToSearch(elementData, text) then
					found = found + 1
				end
				if found >= SearchMaxResults then
					break
				end
			end
			-- self.Log.Search.ScrollBox:ScrollToElementDataIndex(1)
			local pendingSearch = self.pendingSearch
			if pendingSearch then
				self.pendingSearch = nil
				local element = self.Log.Search.ScrollBox:ScrollToElementDataByPredicate(
					function(elementData) return elementData == pendingSearch end,
					ScrollBoxConstants.AlignCenter,
					0,
					ScrollBoxConstants.NoScrollInterpolation
				)
				if element then
					local button = self.Log.Search.ScrollBox:FindFrame(element)
					if button then
						button:Flash()
					end
				end
			elseif self.Log.Search.ScrollBox:HasScrollableExtent() then
				-- self.Log.Search.ScrollBox:ScrollToEnd(ScrollBoxConstants.NoScrollInterpolation)
			end
		end)
		---@param scrollBox ScrollBoxListViewMixin
		local function SetOnDataRangeChanged(scrollBox)
			local function OnDataRangeChanged(sortPending)
				SetScrollBoxButtonAlternateState(scrollBox)
			end
			scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, OnDataRangeChanged, self)
		end
		if not isGridView then
			SetOnDataRangeChanged(self.Log.Events.ScrollBox)
		end
		-- ---@param elementData ChatEmotesLib-1.0_Emote
		-- local function AddEventToFilter(scrollBox, elementData)
		-- 	local found = self.filterDataProvider:FindElementDataByPredicate(
		-- 		function(filterData)
		-- 			return filterData == elementData
		-- 		end
		-- 	)
		-- 	if found then
		-- 		found.enabled = true
		-- 		local button = scrollBox:FindFrame(elementData)
		-- 		if button then
		-- 			button:UpdateEnabledState()
		-- 		end
		-- 	else
		-- 		self.filterDataProvider:Insert(elementData)
		-- 	end
		-- 	self:RemoveFromDataProvider(self.logDataProvider, elementData)
		-- 	self:RemoveFromDataProvider(self.searchDataProvider, elementData)
		-- end
		do
			-- ---@param elementData ChatEmotesLib-1.0_Emote
			-- ---@param text string
			-- local function LocateInSearch(elementData, text)
			-- 	self.pendingSearch = elementData
			-- 	self.Log.Bar.SearchBox:SetText(text)
			-- end
			local view = CreateScrollBoxListGridView() -- CreateScrollBoxListLinearView()
			view:SetElementExtent(ScrollBoxEmoteButtonSize)
			---@param button ChatEmotesUIScrollBoxEmoteButtonMixin
			---@param emote ChatEmotesLib-1.0_Emote
			view:SetElementInitializer("Button", function(button, emote)
				if not button.isInitialized then
					button.isInitialized = true
					Mixin(button, UIScrollBoxEmoteButtonMixin)
					button:OnLoad()
					-- button.HideButton:SetScript("OnMouseDown", function(button, buttonName) LocateInLog(emote) end)
					-- button:SetScript("OnDoubleClick", function(button, buttonName) LocateInLog(emote) end)
				end
				button:Init(emote)
			end)
			local pad = 2
			local spacing = 2
			view:SetPadding(pad, pad, pad, pad, spacing, spacing)
			view:SetHorizontal(false)
			view:SetStride(ScrollBoxEmoteButtonSize)
			view:SetStrideExtent(ScrollBoxEmoteButtonSize)
			ScrollUtil.InitScrollBoxWithScrollBar(self.Log.Events.ScrollBox, self.Log.Events.ScrollBar, view)
			self.Log.Events.ScrollBox:SetDataProvider(self.logDataProvider)
		end
		do
			-- ---@param elementData ChatEmotesLib-1.0_Emote
			-- local function LocateInLog(elementData)
			-- 	self.Log.Bar.SearchBox:SetText()
			-- 	self:DisplayEvents()
			-- 	local found = self.Log.Events.ScrollBox:ScrollToElementDataByPredicate(
			-- 		function(data)
			-- 			return data == elementData
			-- 		end,
			-- 		ScrollBoxConstants.AlignCenter,
			-- 		ScrollBoxConstants.NoScrollInterpolation
			-- 	)
			-- 	local button = found and self.Log.Events.ScrollBox:FindFrame(found)
			-- 	if button then
			-- 		button:Flash()
			-- 	end
			-- end
			local view = CreateScrollBoxListGridView() -- CreateScrollBoxListLinearView()
			view:SetElementExtent(ScrollBoxEmoteButtonSize)
			---@param button ChatEmotesUIScrollBoxEmoteButtonMixin
			---@param emote ChatEmotesLib-1.0_Emote
			view:SetElementInitializer("Button", function(button, emote)
				if not button.isInitialized then
					button.isInitialized = true
					Mixin(button, UIScrollBoxEmoteButtonMixin)
					button:OnLoad()
					-- button.HideButton:SetScript("OnMouseDown", function(button, buttonName) LocateInLog(emote) end)
					-- button:SetScript("OnDoubleClick", function(button, buttonName) LocateInLog(emote) end)
				end
				button:Init(emote)
			end)
			local pad = 2
			local spacing = 2
			view:SetPadding(pad, pad, pad, pad, spacing, spacing)
			view:SetHorizontal(false)
			view:SetStride(ScrollBoxEmoteButtonSize)
			view:SetStrideExtent(ScrollBoxEmoteButtonSize)
			ScrollUtil.InitScrollBoxWithScrollBar(self.Log.Search.ScrollBox, self.Log.Search.ScrollBar, view)
			self.Log.Search.ScrollBox:SetDataProvider(self.searchDataProvider)
		end
	end

	---@param emotes ChatEmotesLib-1.0_Emote[]
	function UIMixin:SetEmotes(emotes)
		self.emotes = emotes
		self.emotesMap = wipe(self.emotesMap or {})
		self.logDataProvider:Flush()
		if not emotes or not emotes[1] then
			return
		end
		for index, emote in ipairs(emotes) do
			self.emotesMap[emote] = index
		end
		self.logDataProvider:InsertTableRange(emotes, 1, emotes[0])
		self.isSortDirty = next(DB.favorites) ~= nil
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIMixin:ShowEmote(emote)
		self:Show()
		local element = self.Log.Events.ScrollBox:ScrollToElementDataByPredicate(
			function(elementData) return elementData == emote end,
			ScrollBoxConstants.AlignCenter,
			0,
			ScrollBoxConstants.NoScrollInterpolation
		)
		if not element then
			return
		end
		local button = self.Log.Events.ScrollBox:FindFrame(element)
		if button then
			button:Flash()
		end
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIMixin:UpdateEmoteFrames(emote)
		local scrollBox = self.Log.Events:IsShown() and self.Log.Events.ScrollBox or self.Log.Search.ScrollBox
		local view = scrollBox:GetView()
		local dataProvider = view:GetDataProvider()
		dataProvider:Sort()
		scrollBox:ForEachFrame(function(button)
			if not emote or emote == button.emote then
				button:Update()
			end
		end)
	end

	---@param frameName string
	function CreateUI(frameName)
		local frame = CreateFrame("Frame", frameName, UIParent, "ButtonFrameTemplate") ---@class ChatEmotesUIMixin
		Mixin(frame, UIMixin)
		frame.TitleBar = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate") ---@class ChatEmotesUIMixinTitleBar
		frame.TitleBar:SetHeight(32)
		frame.TitleBar:SetPoint("TOPLEFT")
		frame.TitleBar:SetPoint("TOPRIGHT")
		frame.ResizeButton = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate") ---@class ChatEmotesUIMixinResizeButton
		frame.ResizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
		frame.ConfigButton = CreateFrame("Button", nil, frame) ---@class ChatEmotesUIMixinConfigButton
		frame.ConfigButton:SetSize(16, 16)
		frame.ConfigButton:SetPoint("BOTTOMLEFT", 6, 6)
		frame.ConfigButton.Texture = frame.ConfigButton:CreateTexture(nil, "ARTWORK")
		frame.ConfigButton.Texture:SetAllPoints()
		frame.ConfigButton.Texture:SetTexture(851903)
		frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.StatusText:SetJustifyH("LEFT")
		frame.StatusText:SetHeight(18)
		frame.StatusText:SetPoint("BOTTOMLEFT", frame.ConfigButton, "BOTTOMRIGHT", 2, 0)
		frame.StatusText:SetPoint("BOTTOMRIGHT", frame.ResizeButton, "BOTTOMLEFT", -2, 0)
		frame.Log = CreateFrame("Frame", nil, frame) ---@class ChatEmotesUIMixinLog
		frame.Log:SetPoint("TOPLEFT", frame.TitleBar, "BOTTOMLEFT", 8, 4)
		frame.Log:SetPoint("BOTTOMRIGHT", -9, 28)
		frame.Log.Bar = CreateFrame("Frame", nil,frame.Log) ---@class ChatEmotesUIMixinLogBar
		frame.Log.Bar:SetHeight(24)
		frame.Log.Bar:SetPoint("TOPLEFT")
		frame.Log.Bar:SetPoint("TOPRIGHT")
		frame.Log.Bar.Label = frame.Log.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.Log.Bar.Label:SetJustifyH("RIGHT")
		frame.Log.Bar.Label:SetSize(135, 10)
		frame.Log.Bar.Label:SetPoint("RIGHT", -12*2, 0)
		frame.Log.Bar.SearchBox = CreateFrame("EditBox", nil, frame.Log.Bar, "SearchBoxTemplate") ---@class ChatEmotesUIMixinLogBarSearchBox
		frame.Log.Bar.SearchBox:SetAutoFocus(false)
		frame.Log.Bar.SearchBox:SetHistoryLines(1)
		frame.Log.Bar.SearchBox:SetMaxBytes(64)
		frame.Log.Bar.SearchBox:SetSize(180, 22)
		frame.Log.Bar.SearchBox:SetPoint("LEFT", 6, 0)
		frame.Log.Bar.SearchBox:SetPoint("RIGHT", -2, 0)
		frame.Log.Events = CreateFrame("Frame", nil, frame.Log) ---@class ChatEmotesUIMixinLogEvents
		frame.Log.Events:SetPoint("TOPLEFT", frame.Log.Bar, "BOTTOMLEFT", 0, -2)
		frame.Log.Events:SetPoint("BOTTOMRIGHT")
		---@diagnostic disable-next-line: assign-type-mismatch
		frame.Log.Events.ScrollBox = CreateFrame("Frame", nil, frame.Log.Events, "WowScrollBoxList") ---@type WowScrollBoxList
		frame.Log.Events.ScrollBox:SetPoint("TOPLEFT")
		frame.Log.Events.ScrollBox:SetPoint("BOTTOMRIGHT", -25, 0)
		frame.Log.Events.ScrollBox.Background = frame.Log.Events.ScrollBox:CreateTexture(nil, "BACKGROUND")
		frame.Log.Events.ScrollBox.Background:SetAllPoints()
		frame.Log.Events.ScrollBox.Background:SetColorTexture(0.03, 0.03, 0.03, 1)
		---@diagnostic disable-next-line: assign-type-mismatch
		frame.Log.Events.ScrollBar = CreateFrame("Frame", nil, frame.Log.Events, "WowTrimScrollBar") ---@type ChatEmotesUIScrollCollectionMixin
		frame.Log.Events.ScrollBar:SetPoint("TOPLEFT", frame.Log.Events.ScrollBox, "TOPRIGHT", 0, -3)
		frame.Log.Events.ScrollBar:SetPoint("BOTTOMLEFT", frame.Log.Events.ScrollBox, "BOTTOMRIGHT", 0, 0)
		Mixin(frame.Log.Events.ScrollBar, UIScrollCollectionMixin)
		frame.Log.Events.ScrollBar:OnLoad()
		frame.Log.Search = CreateFrame("Frame", nil, frame.Log) ---@class ChatEmotesUIMixinLogSearch
		frame.Log.Search:SetPoint("TOPLEFT", frame.Log.Bar, "BOTTOMLEFT", 0, -2)
		frame.Log.Search:SetPoint("BOTTOMRIGHT")
		---@diagnostic disable-next-line: assign-type-mismatch
		frame.Log.Search.ScrollBox = CreateFrame("Frame", nil, frame.Log.Search, "WowScrollBoxList") ---@type WowScrollBoxList
		frame.Log.Search.ScrollBox:SetPoint("TOPLEFT")
		frame.Log.Search.ScrollBox:SetPoint("BOTTOMRIGHT", -25, 0)
		frame.Log.Search.ScrollBox.Background = frame.Log.Search.ScrollBox:CreateTexture(nil, "BACKGROUND")
		frame.Log.Search.ScrollBox.Background:SetAllPoints()
		frame.Log.Search.ScrollBox.Background:SetColorTexture(0.03, 0.03, 0.03, 1)
		---@diagnostic disable-next-line: assign-type-mismatch
		frame.Log.Search.ScrollBar = CreateFrame("Frame", nil, frame.Log.Search, "WowTrimScrollBar") ---@type ChatEmotesUIScrollCollectionMixin
		frame.Log.Search.ScrollBar:SetPoint("TOPLEFT", frame.Log.Search.ScrollBox, "TOPRIGHT", 0, -3)
		frame.Log.Search.ScrollBar:SetPoint("BOTTOMLEFT", frame.Log.Search.ScrollBox, "BOTTOMRIGHT", 0, 0)
		Mixin(frame.Log.Search.ScrollBar, UIScrollCollectionMixin)
		frame.Log.Search.ScrollBar:OnLoad()
		frame.MissingEmotePackage = CreateFrame("Frame", nil, frame) ---@class ChatEmotesUIMixinMissingEmotePackage
		frame.MissingEmotePackage:SetFrameStrata("HIGH")
		frame.MissingEmotePackage:SetAllPoints(frame.Log)
		frame.MissingEmotePackage.Background = frame.MissingEmotePackage:CreateTexture(nil, "BACKGROUND")
		frame.MissingEmotePackage.Background:SetAllPoints()
		frame.MissingEmotePackage.Background:SetColorTexture(0, 0, 0)
		frame.MissingEmotePackage.Text = frame.MissingEmotePackage:CreateFontString(nil, "OVERLAY", "GameFontNormalLargeOutline")
		frame.MissingEmotePackage.Text:SetPoint("TOPLEFT", 20, -20)
		frame.MissingEmotePackage.Text:SetPoint("BOTTOMRIGHT", -20, 20)
		frame.MissingEmotePackage.Text:SetJustifyH("CENTER")
		frame.MissingEmotePackage.Text:SetJustifyV("MIDDLE")
		frame.MissingEmotePackage.Text:SetText(L.MISSING_EMOTE_PACK)
		frame:OnLoad()
		frame:Hide()
		return frame
	end

	---@class ChatEmotesUIButtonMixin : Button

	---@class ChatEmotesUIButtonMixin
	local UIButtonMixin = {}

	function UIButtonMixin:OnLoad()
		self:SetFrameStrata("LOW")
		self:SetSize(32, 32)
		self:SetClampedToScreen(true)
		self:UpdatePosition()
		self:UpdateTexture()
		self:SetScript("OnClick", self.OnClick)
		self:SetScript("OnEnable", self.OnEnable)
		self:SetScript("OnDisable", self.OnDisable)
		self:SetScript("OnEnter", self.OnEnter)
		self:SetScript("OnLeave", self.OnLeave)
		self:SetScript("OnShow", self.OnShow)
		self:SetScript("OnHide", self.OnHide)
		self:SetScript("OnDragStart", self.OnDragStart)
		self:SetScript("OnDragStop", self.OnDragStop)
	end

	function UIButtonMixin:UpdateTexture()
		local text
		if not sortedEmotes or not sortedEmotes[1] then
			text = NO_EMOTE_MARKUP_FALLBACK
		else
			local emote = GetRandomEmote()
			text = GetMarkupForEmote(emote, 14)
		end
		self.Text:SetText(text)
	end

	---@param self ChatEmotesUIButtonMixin
	local function LoadPosition(self)
		local position = DB.buttonPosition
		local point, relativeTo, relativePoint, x, y = position.point, position.relativeTo, position.relativePoint, position.x, position.y
		if not point then
			local oposition = defaults.buttonPosition
			point, relativeTo, relativePoint, x, y = oposition.point, oposition.relativeTo, oposition.relativePoint, oposition.x, oposition.y
		end
		self:ClearAllPoints()
		self:SetPoint(point, relativeTo, relativePoint, x, y) ---@diagnostic disable-line: param-type-mismatch
		return point, relativeTo, relativePoint, x, y
	end

	---@param self ChatEmotesUIButtonMixin
	local function SavePosition(self)
		if not DB.options.unlockButton then
			return
		end
		local point, relativeTo, relativePoint, x, y = self:GetPoint(1)
		if not point then
			return
		end
		local position = DB.buttonPosition
		position.point, position.relativeTo, position.relativePoint, position.x, position.y = point, relativeTo and relativeTo:GetName() or "UIParent", relativePoint, x, y
		return position.point, position.relativeTo, position.relativePoint, position.x, position.y
	end

	function UIButtonMixin:UpdatePosition(forceToMiddle)
		local unlocked = DB.options.unlockButton
		local position = DB.buttonPosition
		if not unlocked then
			local oposition = defaults.buttonPosition
			position.point, position.relativeTo, position.relativePoint, position.x, position.y = oposition.point, oposition.relativeTo, oposition.relativePoint, oposition.x, oposition.y
		elseif forceToMiddle then
			position.point, position.relativeTo, position.relativePoint, position.x, position.y = "CENTER", "UIParent", "CENTER", 0, 0
		end
		LoadPosition(self)
		SavePosition(self)
		self:SetMovable(unlocked)
		if unlocked then
			self:RegisterForDrag("LeftButton")
		else
			self:RegisterForDrag()
		end
	end

	function UIButtonMixin:OnClick()
		PlaySound(SOUNDKIT.IG_CHAT_EMOTE_BUTTON) ---@diagnostic disable-line: undefined-global
		addon:TogglePicker()
		self:UpdateTexture()
	end

	function UIButtonMixin:OnEnable()
		self.Text:Show()
	end

	function UIButtonMixin:OnDisable()
		self.Text:Hide()
	end

	function UIButtonMixin:OnEnter()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.CHAT_EMOTES) ---@diagnostic disable-line: undefined-global
		GameTooltip:Show()
	end

	function UIButtonMixin:OnLeave()
		GameTooltip:Hide()
	end

	function UIButtonMixin:OnShow()
		self:UpdatePosition()
	end

	function UIButtonMixin:OnHide()
		self:UpdatePosition()
	end

	---@param button string
	function UIButtonMixin:OnDragStart(button)
		if button ~= "LeftButton" then
			return
		end
		self:StartMoving()
	end

	function UIButtonMixin:OnDragStop()
		self:StopMovingOrSizing()
		SavePosition(self)
		self:UpdatePosition()
	end

	---@param frameName string
	function CreateButton(frameName)
		local button = CreateFrame("Button", frameName, UIParent) ---@class ChatEmotesUIButtonMixin
		Mixin(button, UIButtonMixin)
		button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		button.Text:SetJustifyH("CENTER")
		button.Text:SetJustifyV("MIDDLE")
		button.Text:SetAllPoints()
		button:SetNormalTexture(format("Interface\\AddOns\\%s\\textures\\chat-button-up", addonName))
		button:SetPushedTexture(format("Interface\\AddOns\\%s\\textures\\chat-button-down", addonName))
		button:SetDisabledTexture(format("Interface\\AddOns\\%s\\textures\\chat-button-disabled", addonName))
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		button:OnLoad()
		button:Show()
		return button
	end

	---@class FauxScrollFrameTemplateScrollChildFrame : Frame
	---@field public Options ConfigWidget[]

	---@class FauxScrollFrameTemplate : Frame
	---@field public ScrollBarMiddle Texture
	---@field public ScrollChildFrame FauxScrollFrameTemplateScrollChildFrame

	---@class ChatEmotesUIConfigMixin : Frame
	---@field public Inset Frame
	---@field public NineSlice? Frame
	---@field public Options ConfigWidget[]
	---@field public ScrollFrame FauxScrollFrameTemplate

	---@class ChatEmotesUIConfigMixin
	local UIConfigMixin = {}

	function UIConfigMixin:OnLoad()
		self:SetToplevel(true)
		self:SetMovable(true)
		self:EnableMouse(true)
		self:SetClampedToScreen(true)
		self:SetSize(DefaultPanelWidth, DefaultPanelHeight)
		self:SetPoint("CENTER")
		ButtonFrameTemplate_HidePortrait(self) ---@diagnostic disable-line: undefined-global
		if self.NineSlice then
			self.NineSlice:SetPoint("TOPLEFT", -1, 0)
		end
		self.Inset:SetPoint("TOPLEFT", 4, -24) -- -60
		self.TitleBar:Init(self) ---@diagnostic disable-line: undefined-field
		self:SetTitle(L.CHAT_EMOTES_OPTIONS) ---@diagnostic disable-line: undefined-field
		self:UpdateScrollFrame()
	end

	function UIConfigMixin:UpdateScrollFrame()
		local totalHeight = 0
		for _, widget in ipairs(self.Options) do
			totalHeight = totalHeight + widget:GetHeight()
		end
		local numToDisplay = 8
		local fakeItemHeight = 32
		local numItems = floor(totalHeight / fakeItemHeight + 0.5)
		local scrollFrame = self.ScrollFrame
		FauxScrollFrame_Update(scrollFrame, numItems, numToDisplay, fakeItemHeight, nil, nil, nil, nil, nil, nil, true) ---@diagnostic disable-line: undefined-global
		if numItems > numToDisplay then
			scrollFrame.ScrollBar:Show() ---@diagnostic disable-line: undefined-field
		else
			scrollFrame.ScrollBar:Hide() ---@diagnostic disable-line: undefined-field
			scrollFrame.ScrollBar:SetValue(0) ---@diagnostic disable-line: undefined-field
		end
	end

	---@class ConfigOption
	---@field public key string
	---@field public type? string
	---@field public percentile? boolean
	---@field public requires? string

	---@class ConfigWidget : EditBox
	---@field public cvar ConfigOption
	---@field public finalized boolean
	---@field public frame ChatEmotesUIConfigMixin
	---@field public OnShow function
	---@field public OnSave function
	---@field public CanSave function
	---@field public Update function
	---@field public UpdateState function
	---@field public UpdateOtherStates function
	---@field public value? any
	---@field public Label? FontString

	---@class ConfigInputFactory
	local InputFactory = {}

	do

		---@param widget ConfigWidget
		local function OnShow(widget)
			local cvar = widget.cvar
			local key = cvar.key
			local options = DB.options
			local value = options[key]
			local widgetType = widget:GetObjectType()
			if widgetType == "EditBox" then
				if cvar.type == "number" then
					if cvar.percentile then
						widget.value = floor(value * 100 + 0.5)
					else
						widget.value = value
					end
					widget:SetNumber(widget.value)
				else
					widget.value = value
					widget:SetText(widget.value)
				end
			elseif widgetType == "CheckButton" then
				widget.value = value
				widget:SetChecked(widget.value) ---@diagnostic disable-line: undefined-field
			end
		end

		---@param widget ConfigWidget
		local function OnSave(widget)
			DB.options[widget.cvar.key] = widget.value
		end

		---@param widget ConfigWidget
		local function CanSave(widget)
			local value = widget.value
			local cvar = widget.cvar
			local widgetType = widget:GetObjectType()
			if widgetType == "EditBox" then
				if cvar.type == "number" then
					return type(value) == "number"
				else
					return type(value) == "string"
				end
			elseif widgetType == "CheckButton" then
				return type(value) == "boolean"
			end
		end

		---@param widget ConfigWidget
		local function Update(widget)
		end

		---@param widget ConfigWidget
		local function UpdateState(widget)
			local cvar = widget.cvar
			if not cvar then
				return
			end
			if not cvar.requires then
				return
			end
			if not widget.SetEnabled then
				return
			end
			widget:SetEnabled(DB.options[cvar.requires]) ---@diagnostic disable-line: redundant-parameter
		end

		---@param widget ConfigWidget
		local function UpdateOtherStates(widget)
			local options = widget.frame.Options
			for _, otherWidget in ipairs(options) do
				if otherWidget ~= widget then
					otherWidget:UpdateState()
				end
			end
		end

		---@param self ConfigWidget
		local function Common_OnEnable(self)
			local r, g, b = 1, 1, 1
			local SetTextColor = self.SetTextColor ---@diagnostic disable-line: undefined-field
			if SetTextColor then
				SetTextColor(self, r, g, b)
			end
			local Label = self.Label
			if Label then
				Label:SetTextColor(r, g, b)
			end
		end

		---@param self ConfigWidget
		local function Common_OnDisable(self)
			local r, g, b = 0.5, 0.5, 0.5
			local SetTextColor = self.SetTextColor ---@diagnostic disable-line: undefined-field
			if SetTextColor then
				SetTextColor(self, r, g, b)
			end
			local Label = self.Label
			if Label then
				Label:SetTextColor(r, g, b)
			end
		end

		---@param self ConfigWidget
		local function Common_OnShow(self)
			self:OnShow()
			self:UpdateState()
		end

		---@param self ConfigWidget
		local function Common_OnSave(self)
			local widgetType = self:GetObjectType()
			if widgetType == "CheckButton" then
				self.value = not not self:GetChecked() ---@diagnostic disable-line: undefined-field
			end
			if not self:CanSave() then
				self:OnShow()
				return
			end
			self:OnSave()
			self:UpdateOtherStates()
		end

		---@param self ConfigWidget
		local function EditBox_OnEnterPressed(self)
			local cvar = self.cvar
			if cvar.type == "number" then
				self.value = self:GetNumber()
			else
				self.value = self:GetText()
			end
			Common_OnSave(self)
			self:ClearFocus()
		end

		---@param self ConfigWidget
		local function EditBox_OnTextChanged(self)
			self:Update()
		end

		---@param self ConfigWidget
		local function EditBox_OnArrowPressed(self)
			self:Update(true)
		end

		---@param frame ChatEmotesUIConfigMixin
		---@param widget ConfigWidget
		function InputFactory:FinalizeOption(frame, widget)
			if widget.finalized then
				return widget
			end
			widget.finalized = true
			widget.frame = frame
			widget.OnShow = OnShow
			widget.OnSave = OnSave
			widget.CanSave = CanSave
			widget.Update = Update
			widget.UpdateState = UpdateState
			widget.UpdateOtherStates = UpdateOtherStates
			if widget.cvar then
				local widgetType = widget:GetObjectType()
				if widgetType == "EditBox" then
					widget:HookScript("OnEnable", Common_OnEnable)
					widget:HookScript("OnDisable", Common_OnDisable)
					widget:HookScript("OnShow", Common_OnShow)
					widget:HookScript("OnEditFocusLost", Common_OnShow)
					widget:HookScript("OnTextChanged", EditBox_OnTextChanged)
					widget:HookScript("OnArrowPressed", EditBox_OnArrowPressed)
					widget:SetScript("OnEnterPressed", EditBox_OnEnterPressed) -- override default
				elseif widgetType == "CheckButton" then
					widget:HookScript("OnEnable", Common_OnEnable)
					widget:HookScript("OnDisable", Common_OnDisable)
					widget:HookScript("OnShow", Common_OnShow)
					widget:HookScript("OnClick", Common_OnSave) ---@diagnostic disable-line: param-type-mismatch
				end
			end
			local index = #frame.Options
			local prevOption = frame.Options[index]
			if prevOption then
				widget:SetPoint("TOPLEFT", prevOption, "BOTTOMLEFT", 0, 0)
			else
				widget:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, 0)
			end
			frame.Options[index + 1] = widget
			return widget
		end

	end

	local function CreateLabel(frame, widget, text, offsetX, offsetY)
		local label = widget:CreateFontString(nil, "ARTWORK", "GameFontHighlight") ---@type FontString
		label:SetPoint("LEFT", widget, "RIGHT", 4 + (offsetX or 0), offsetY or 0)
		label:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
		label:SetJustifyH("LEFT")
		label:SetJustifyV("TOP")
		label:SetText(text)
		return label
	end

	---@return ConfigWidget
	function InputFactory:CreateEditBox(frame, cvar, label)
		---@diagnostic disable-next-line: assign-type-mismatch
		local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate") ---@type ConfigWidget
		editBox.cvar = cvar
		editBox:SetSize(48, 32)
		editBox:SetAutoFocus(false)
		editBox.Label = CreateLabel(frame, editBox, label)
		editBox:SetScript("OnTabPressed", EditBox_OnTabPressed) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEscapePressed", EditBox_ClearFocus) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEditFocusLost", EditBox_ClearHighlight) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEditFocusGained", EditBox_HighlightText) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEnterPressed", EditBox_ClearFocus) ---@diagnostic disable-line: undefined-global
		return InputFactory:FinalizeOption(frame, editBox)
	end

	---@return ConfigWidget
	function InputFactory:CreateEditBoxNumeric(frame, cvar, label)
		local editBox = self:CreateEditBox(frame, cvar, label)
		editBox:SetNumeric(true)
		editBox:SetNumber(100)
		editBox:SetMaxLetters(3)
		return InputFactory:FinalizeOption(frame, editBox)
	end

	---@return ConfigWidget
	function InputFactory:CreateEditBoxChar(frame, cvar, label)
		local editBox = self:CreateEditBox(frame, cvar, label)
		editBox:SetMaxLetters(1)
		return InputFactory:FinalizeOption(frame, editBox)
	end

	---@return FontString
	function InputFactory:CreateFontString(frame)
		local fontString = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight") ---@type FontString
		fontString:SetNonSpaceWrap(false)
		fontString:SetWordWrap(false) ---@diagnostic disable-line: redundant-parameter
		fontString:SetSize(0, 20)
		fontString:SetJustifyH("LEFT")
		fontString:SetJustifyV("TOP")
		---@diagnostic disable-next-line: return-type-mismatch, param-type-mismatch
		return InputFactory:FinalizeOption(frame, fontString)
	end

	function InputFactory:CreateButton(frame, label)
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(80, 24)
		button:SetText(label)
		return button
	end

	---@class UICheckButtonTemplate : CheckButton, ConfigWidget
	---@field public text FontString

	---@return UICheckButtonTemplate
	function InputFactory:CreateCheckBox(frame, cvar, label)
		---@diagnostic disable-next-line: assign-type-mismatch
		local checkBox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate") ---@type UICheckButtonTemplate
		checkBox.cvar = cvar
		checkBox:SetSize(32, 32)
		checkBox.Label = CreateLabel(frame, checkBox, label, -5, 0)
		---@diagnostic disable-next-line: return-type-mismatch
		return InputFactory:FinalizeOption(frame, checkBox)
	end

	---@param frameName string
	function CreateConfig(frameName)
		local frame = CreateFrame("Frame", frameName, UIParent, "ButtonFrameTemplate") ---@class ChatEmotesUIConfigMixin
		Mixin(frame, UIConfigMixin)
		frame.TitleBar = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate")
		frame.TitleBar:SetHeight(32)
		frame.TitleBar:SetPoint("TOPLEFT")
		frame.TitleBar:SetPoint("TOPRIGHT")
		do -- frame.Options
			frame.Options = {}
			frame.ScrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "FauxScrollFrameTemplate")---@diagnostic disable-line: assign-type-mismatch
			frame.ScrollFrame.ScrollBarMiddle = _G[format("%s%s", frame.ScrollFrame:GetName(), "Middle")] ---@type Texture
			frame.ScrollFrame.ScrollChildFrame.Options = frame.Options ---@diagnostic disable-line: undefined-field -- alias
			frame.ScrollFrame.ScrollBar.scrollStep = 32 ---@diagnostic disable-line: undefined-field
			frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -29)
			frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 29)
			do -- emoteScale

				local emoteScale = InputFactory:CreateEditBoxNumeric(frame.ScrollFrame.ScrollChildFrame, { type = "number", key = "emoteScale", percentile = true }, L.EMOTE_SCALE) ---@class ConfigEditBoxEmoteScaleWidget : ConfigWidget, EditBox
				emoteScale.Preview = InputFactory:CreateFontString(frame.ScrollFrame.ScrollChildFrame)

				-- emoteScale.ReloadUI = InputFactory:CreateButton(frame.ScrollFrame.ScrollChildFrame, RELOADUI)
				-- emoteScale.ReloadUI:SetPoint("LEFT", emoteScale.Label, "RIGHT", -32, 0)
				-- emoteScale.ReloadUI:HookScript("OnClick", C_UI.Reload)
				-- emoteScale.ReloadUI:Hide()

				function emoteScale:OnShow()
					local cvar = self.cvar
					local key = cvar.key
					local options = DB.options
					if cvar.percentile then
						self.value = floor(options[key] * 100 + 0.5)
					else
						self.value = options[key]
					end
					self:SetNumber(self.value)
				end

				function emoteScale:OnSave()
					local cvar = self.cvar
					local key = cvar.key
					local options = DB.options
					local value = self.value
					if not value or value < 1 then
						local ovalue = defaults.options[key]
						value = floor(ovalue * 100 + 0.5)
					elseif value > 999 then
						value = 999
					end
					local oldValue = options[key]
					if cvar.percentile then
						options[key] = value / 100
					else
						options[key] = value
					end
					self:SetNumber(value)
					if oldValue ~= value then
						-- emoteScale.ReloadUI:Show()
						addonAnimator:ClearCache()
					end
				end

				---@param newEmote boolean
				function emoteScale:Update(newEmote)
					if newEmote or not self.emote then
						self:GetRandomEmote()
					end
					self:UpdateEmote()
				end

				function emoteScale:GetRandomEmote()
					local emote = GetRandomEmote()
					self.emote = emote
					return emote
				end

				function emoteScale:UpdateEmote()
					local emote = self.emote
					local scale = self:GetNumber() / 100
					local height = GetHeightForFontString(DEFAULT_CHAT_FRAME, scale, 3) ---@diagnostic disable-line: undefined-global
					local text
					if emote then
						text = CEL.SafeReplace(emote.name, nil, emote, height, false)
					else
						text = NO_EMOTE_MARKUP_FALLBACK
					end
					self.Preview:SetText(text)
					---@diagnostic disable-next-line: assign-type-mismatch
					local size = self.Preview:GetUnboundedStringWidth() ---@type number
					self.Preview:SetSize(size, size * (emote and emote.ratio or 1))
					addonConfigFrame:UpdateScrollFrame()
				end

			end
			do -- emoteHover

				local emoteHover = InputFactory:CreateCheckBox(frame.ScrollFrame.ScrollChildFrame, { key = "emoteHover" }, L.EMOTE_HOVER) ---@class ConfigEditBoxEmoteHoverWidget : UICheckButtonTemplate

				emoteHover:SetPoint("TOPLEFT", frame.Options[#frame.Options - 1], "BOTTOMLEFT", -10, 0)

			end
			do -- enableAutoComplete

				local enableAutoComplete = InputFactory:CreateCheckBox(frame.ScrollFrame.ScrollChildFrame, { key = "enableAutoComplete" }, L.ENABLE_AUTOCOMPLETE) ---@class ConfigEditBoxEnableAutoCompleteWidget : UICheckButtonTemplate

				local OnSave = enableAutoComplete.OnSave

				function enableAutoComplete:OnSave(...)
					OnSave(self, ...)
					AutoComplete:HideDropDown(nil, true)
				end

			end
			do -- autoCompleteChar

				local autoCompleteChar = InputFactory:CreateEditBoxChar(frame.ScrollFrame.ScrollChildFrame, { key = "autoCompleteChar", requires = "enableAutoComplete" }, L.AUTOCOMPLETE_CHAR) ---@class ConfigEditBoxAutoCompleteCharWidget : ConfigWidget, EditBox

				autoCompleteChar:SetPoint("TOPLEFT", frame.Options[#frame.Options - 1], "BOTTOMLEFT", 10, 0)

				function autoCompleteChar:CanSave()
					local chr = self.value
					if type(chr) ~= "string" then
						return false
					end
					chr = chr:trim()
					if strlenutf8(chr) ~= 1 then
						return false
					end
					if INVALID_AUTOCOMPLETE_CHARS[chr] then
						return false
					end
					return true
				end

			end
			do -- autoCompletePreset

				local autoCompletePreset = InputFactory:CreateEditBoxNumeric(frame.ScrollFrame.ScrollChildFrame, { type = "number", key = "autoCompletePreset" }, L.AUTOCOMPLETE_PRESET) ---@class ConfigEditBoxAutoCompletePresetWidget : ConfigWidget, EditBox

				autoCompletePreset.Text = InputFactory:CreateFontString(frame.ScrollFrame.ScrollChildFrame)
				autoCompletePreset.Text:SetTextColor(1, 1, 0.5)
				local text = {}
				for i, fontObjectPreset in ipairs(AutoCompleteFontPresets) do
					text[i] = format("%d = %s", fontObjectPreset.id, fontObjectPreset.text)
				end
				text = table.concat(text, ", ") ---@diagnostic disable-line: cast-local-type
				autoCompletePreset.Text:SetText(text)

				function autoCompletePreset:CanSave()
					local number = self.value
					for _, fontObjectPreset in ipairs(AutoCompleteFontPresets) do
						if fontObjectPreset.id == number then
							return true
						end
					end
					if not number or number < 1 then
						self.value = AutoCompleteFontPresetFallback.id
						return true
					end
					return false
				end

				local OnSave = autoCompletePreset.OnSave

				function autoCompletePreset:OnSave(...)
					OnSave(self, ...)
					DB.options.autoCompletePreset = self.value
					AutoComplete:SetFontObjectPreset()
				end

			end
			do -- unlockButton

				local unlockButton = InputFactory:CreateCheckBox(frame.ScrollFrame.ScrollChildFrame, { key = "unlockButton" }, L.UNLOCK_BUTTON) ---@class ConfigEditBoxUnlockButtonWidget : UICheckButtonTemplate

				unlockButton:SetPoint("TOPLEFT", frame.Options[#frame.Options - 1], "BOTTOMLEFT", -10, 0)

				local OnSave = unlockButton.OnSave

				function unlockButton:OnSave(...)
					OnSave(self, ...)
					addonButton:UpdatePosition(true)
				end

			end
			do -- emoteAnimation

				local emoteAnimation = InputFactory:CreateCheckBox(frame.ScrollFrame.ScrollChildFrame, { key = "emoteAnimation" }, L.EMOTE_ANIMATION) ---@class ConfigEditBoxEmoteAnimationButtonWidget : UICheckButtonTemplate

			end
			do -- emoteAnimationInCombat

				local emoteAnimationInCombat = InputFactory:CreateCheckBox(frame.ScrollFrame.ScrollChildFrame, { key = "emoteAnimationInCombat", requires = "emoteAnimation" }, L.EMOTE_ANIMATION_IN_COMBAT) ---@class ConfigEditBoxEmoteAnimationInCombatButtonWidget : UICheckButtonTemplate

			end
			do -- emoteAnimationInterval

				local emoteAnimationInterval = InputFactory:CreateEditBoxNumeric(frame.ScrollFrame.ScrollChildFrame, { type = "number", key = "emoteAnimationInterval", requires = "emoteAnimation" }, L.EMOTE_ANIMATION_INTERVAL) ---@class ConfigEditBoxEmoteAnimationIntervalWidget : ConfigWidget, EditBox

				emoteAnimationInterval:SetPoint("TOPLEFT", frame.Options[#frame.Options - 1], "BOTTOMLEFT", 10, 0)

				function emoteAnimationInterval:OnShow()
					local cvar = self.cvar
					local key = cvar.key
					local options = DB.options
					self.value = options[key]
					self:SetMaxLetters(4)
					self:SetNumber(self.value * 1000)
				end

				function emoteAnimationInterval:OnSave()
					local cvar = self.cvar
					local key = cvar.key
					local options = DB.options
					local value = self.value
					if not value or value < 1 then
						value = defaults.options[key] * 1000
					elseif value > 9999 then
						value = 9999
					end
					options[key] = value / 1000
					self:SetNumber(value)
				end

			end
		end
		frame:OnLoad()
		frame:Hide()
		return frame
	end

end

local function CreateSlashCommand()
	local function CommandHandler(text, editBox)
		if text and (text:find("[Cc][Oo][Nn][Ff][Ii][Gg]") or text:find("[Oo][Pp][Tt][Ii][Oo][Nn][Ss]?")) then
			addon:ToggleConfig()
		else
			addon:TogglePicker()
		end
	end
	---@diagnostic disable-next-line: undefined-field
	_G.SlashCmdList[addonName] = CommandHandler
	_G[format("SLASH_%s1", addonName)] = "/vladschatemotes"
	_G[format("SLASH_%s2", addonName)] = "/vce"
	_G[format("SLASH_%s3", addonName)] = "/chatemotes"
	_G[format("SLASH_%s4", addonName)] = "/ce"
	return CommandHandler
end

-- TODO: the animation support should be moved into the library and instead register the areas which one wishes it to update
local CreateAnimator

do

	---@class ChatEmotesAnimatorMixin : Frame

	local ANIMATION_PATTERN = "(|T([^:]-)_(%d+)_(%d+)_(%d+):(.-)|t)"
	local ANIMATION_FORMAT = "|T%s_%d_%d_%d:%s|t"
	local SUFFIX_SIZE_PATTERN = "^((%d+):(%d+))"

	---@type table<string, ChatEmotesLib-1.0_Emote?>
	local cachedEmotes = {}

	---@type table<string, string?>
	local cachedFrames = {}

	---@type table<string, number?>
	local cachedTimers = {}

	---@type table<string, string?>
	local cachedPatterns = {}

	local function ClearCache()
		wipe(cachedFrames)
		wipe(cachedTimers)
		wipe(cachedPatterns)
	end

	---@param emote ChatEmotesLib-1.0_Emote
	---@param frameIndex number
	---@return number? newDuration
	local function GetNextDuration(emote, frameIndex)
		if not emote.duration then
			return
		end
		local duration
		if type(emote.duration) == "table" then
			if not emote.duration.length then
				local length = 0
				for index, _ in pairs(emote.duration) do if index > length then length = index end end ---@diagnostic disable-line: param-type-mismatch
				emote.duration.length = length ---@diagnostic disable-line: inject-field
			end
			for index = 1, emote.duration.length do
				local value = emote.duration[index]
				if value and frameIndex >= index then
					duration = value
				end
			end
			if not duration then
				duration = emote.duration[1]
			end
		elseif type(emote.duration) == "number" then
			---@diagnostic disable-next-line: assign-type-mismatch
			duration = emote.duration ---@type number
		end
		return duration
	end

	---@param suffix string
	---@param height? number
	---@return string? newSuffix
	local function GetNextSuffix(suffix, height)
		local width = height
		local existingSize, existingHeight, existingWidth = suffix:match(SUFFIX_SIZE_PATTERN)
		if existingSize then
			if height then
				existingHeight = 0 + existingHeight
				existingWidth = 0 + existingWidth
				if existingHeight <= 0 then existingHeight = 1 end
				if existingWidth <= 0 then existingWidth = 1 end
				height = floor(height + 0.5)
				width = floor(height * (existingWidth/existingHeight) + 0.5)
			else
				height = existingHeight
				width = existingWidth
			end
		end
		height = height or 0
		width = width or 0
		local newSize = format("%d:%d", height, width)
		local newSuffix = suffix:gsub(SUFFIX_SIZE_PATTERN, newSize, 1)
		if suffix ~= newSuffix then
			return newSuffix
		end
	end

	---@param parent Region
	---@param text string
	---@param elapsed number
	---@param height? number
	---@return table<string, string>? replacements
	local function ReplaceAnimationEmotes(parent, text, elapsed, height)
		local replacements ---@type table<string, string>?
		for emoteText, prefix, current, total, duration, suffix in text:gmatch(ANIMATION_PATTERN) do
			if not replacements or not replacements[emoteText] then
				current = 0 + current ---@type number
				total = 0 + total ---@type number
				duration = 0 + duration ---@type number
				local uniqueEmote = format("%s:%s", tostring(parent), prefix)
				local durationMS = duration/100
				local timer = cachedTimers[uniqueEmote]
				timer = (timer or 0) + elapsed
				-- TODO: there is a minor bug where this skip can cause multiple frames to have their duration also skipped
				-- to fix this we would need to per frame skipped also substract the original duration for that frame
				-- this is costly and we currently only do this further down this block but it's such a minor visual artifact
				-- I'm just noting the issue here for future me to fix (this whole code should be part of the library anyway)
				while timer >= durationMS do
					timer = timer - durationMS
					current = current + 1
					if current > total then
						current = 1
					end
				end
				cachedTimers[uniqueEmote] = timer
				local cachedEmote = cachedEmotes[prefix]
				if not cachedEmote then
					cachedEmote = CEL.GetAnimatedEmoteByFile(prefix)
					cachedEmotes[prefix] = cachedEmote
				end
				local uniqueFrameKey = format("%s:%s:%s", prefix, current, suffix)
				local cache = cachedFrames[uniqueFrameKey]
				if not cache then
					local nextDuration = GetNextDuration(cachedEmote, current) or duration
					local nextSuffix = GetNextSuffix(suffix, height) or suffix
					cache = format(ANIMATION_FORMAT, prefix, current, total, nextDuration, nextSuffix)
					cachedFrames[uniqueFrameKey] = cache
				end
				if not replacements then
					replacements = {}
				end
				replacements[emoteText] = cache
			end
		end
		return replacements
	end

	---@param parent Region
	---@param text string
	---@param elapsed number
	---@param height? number
	---@return string? newText
	local function GetNextAnimationFrame(parent, text, elapsed, height)
		local replacements = ReplaceAnimationEmotes(parent, text, elapsed, height)
		if not replacements then
			return
		end
		for from, to in pairs(replacements) do
			local cache = cachedPatterns[from]
			if not cache then
				cache = CEL.TextToPattern(from)
				cachedPatterns[from] = cache
			end
			text = CEL.ReplaceText(text, cache, to)
		end
		return text
	end

	---@param fontString FontString
	---@param elapsed number
	---@param height? number|true
	---@return boolean? success
	local function AnimateFontString(fontString, elapsed, height)
		if not fontString:IsVisible() then
			return
		end
		local text = fontString:GetText() ---@type string?
		if not text then
			return
		end
		if height == true then
			height = GetHeightForFontString(fontString)
		end
		local newText = GetNextAnimationFrame(fontString, text, elapsed, height)
		if not newText then
			return
		end
		fontString:SetText(newText)
		return true
	end

	---@param button ChatEmotesUIScrollBoxEmoteButtonMixin
	---@param elapsed number
	---@return boolean? success
	local function AnimateFrameButton(button, elapsed)
		if not button:IsVisible() then
			return
		end
		local emote = button.emote
		if not emote or not emote.animated then
			return
		end
		return AnimateFontString(button.Label, elapsed)
	end

	---@param button AutoCompleteButton
	---@param elapsed number
	---@return boolean? success
	local function AnimateAutoCompleteButton(button, elapsed)
		local result = button.result
		if not result then
			return
		end
		local emote = result.emote
		if not emote or not emote.animated then
			return
		end
		return AnimateFontString(button.Text, elapsed)
	end

	---@param line ChatFrameLine
	---@param elapsed number
	---@param height? number
	---@return boolean? success
	local function AnimateChatLine(line, elapsed, height)
		local messageInfo = line.messageInfo
		if not messageInfo then
			return
		end
		local text = messageInfo.message
		if not text then
			return
		end
		local newText = GetNextAnimationFrame(line, text, elapsed, height)
		if not newText then
			return
		end
		if messageInfo.message == newText then
			return
		end
		messageInfo.message = newText
		line:SetText(newText)
		return true
	end

	local inCombat = InCombatLockdown()

	---@param self ChatEmotesAnimatorMixin
	---@param event WowEvent
	local function OnEvent(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
		elseif event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
		end
	end

	local elapsedTime = 0

	---@param self ChatEmotesAnimatorMixin
	---@param elapsed number
	local function OnUpdate(self, elapsed)

		if (not DB.options.emoteAnimation) or (inCombat and not DB.options.emoteAnimationInCombat) then
			return
		end

		elapsedTime = elapsedTime + elapsed

		if elapsedTime < DB.options.emoteAnimationInterval then
			return
		end

		if addonFrame and addonFrame:IsVisible() then
			if addonFrame.Log.Events.ScrollBox:IsVisible() then
				for _, button in addonFrame.Log.Events.ScrollBox:EnumerateFrames() do
					if button:IsVisible() then
						AnimateFrameButton(button, elapsedTime)
					end
				end
			end
			if addonFrame.Log.Search.ScrollBox:IsVisible() then
				for _, button in addonFrame.Log.Search.ScrollBox:EnumerateFrames() do
					if button:IsVisible() then
						AnimateFrameButton(button, elapsedTime)
					end
				end
			end
		end

		if AutoComplete and AutoComplete:IsVisible() then
			for _, button in ipairs(AutoComplete.Buttons) do
				if button:IsVisible() then
					AnimateAutoCompleteButton(button, elapsedTime)
				end
			end
		end

		for chatFrame, _ in pairs(hookedChatFrames) do
			if chatFrame:IsVisible() then
				local height
				for _, visibleLine in ipairs(chatFrame.visibleLines) do
					if visibleLine:IsVisible() then
						if not height then
							height = GetHeightForFontString(chatFrame)
						end
						AnimateChatLine(visibleLine, elapsedTime, height)
					end
				end
			end
		end

		elapsedTime = 0

	end

	function CreateAnimator()
		---@diagnostic disable-next-line: cast-local-type
		addonAnimator = CreateFrame("Frame") ---@class ChatEmotesAnimatorMixin
		addonAnimator:RegisterEvent("PLAYER_REGEN_DISABLED")
		addonAnimator:RegisterEvent("PLAYER_REGEN_ENABLED")
		addonAnimator:SetScript("OnEvent", OnEvent)
		addonAnimator:SetScript("OnUpdate", OnUpdate)
		addonAnimator.ClearCache = ClearCache
	end

end

local function UpdateChannels()
	wipe(activeChannels)
	for chatFrame, _ in pairs(hookedChatFrames) do
		local index = chatFrame:GetID()
		local channels = { GetChatWindowChannels(index) }
		for j = 1, #channels, 2 do
			local channel, id = channels[j], channels[j + 1] ---@type string|number, number|string
			activeChannels[channel] = id
			activeChannels[id] = channel
		end
	end
end

local function UpdateChannelsReduntant()
	UpdateChannels()
	C_Timer.After(3, UpdateChannels)
end

local function InitDB()
	ChatEmotesDB = type(ChatEmotesDB) == "table" and ChatEmotesDB or {}
	DB = setmetatable(ChatEmotesDB, { __index = defaults })
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			local t = rawget(DB, k)
			if type(t) ~= "table" then
				t = {}
				DB[k] = t
			end
			setmetatable(t, { __index = v })
		end
	end
	AutoComplete:SetFontObjectPreset()
end

local function HookChatFrames()
	for i = 1, NUM_CHAT_WINDOWS + 1000 do
		local chatFrame = _G[format("ChatFrame%d", i)] ---@type ChatFrame?
		if not chatFrame and i > NUM_CHAT_WINDOWS then
			break
		end
		if chatFrame and not hookedChatFrames[chatFrame] then
			hookedChatFrames[chatFrame] = true
			local editBox = chatFrame.editBox
			editBox:HookScript("OnTextChanged", ChatEditBoxOnChanged)
			editBox:HookScript("OnChar", ChatEditBoxOnChanged)
			editBox:HookScript("OnArrowPressed", ChatEditBoxOnArrow)
			editBox:HookScript("OnKeyDown", ChatEditBoxOnKeyDown)
			editBox:HookScript("OnKeyUp", ChatEditBoxOnKeyUp)
			editBox:HookScript("OnTabPressed", ChatEditBoxOnTabPressed)
			editBox:HookScript("OnEscapePressed", ChatEditBoxOnFocusLost)
			chatFrame:HookScript("OnHyperlinkClick", ChatFrameOnHyperlinkClick) ---@diagnostic disable-line: param-type-mismatch
			chatFrame:HookScript("OnHyperlinkEnter", ChatFrameOnHyperlinkEnter) ---@diagnostic disable-line: param-type-mismatch
			chatFrame:HookScript("OnHyperlinkLeave", ChatFrameOnHyperlinkLeave) ---@diagnostic disable-line: param-type-mismatch
		end
	end
end

local function Init()
	sortedEmotes = CEL.GetEmotes()
	table.sort(sortedEmotes, SortEmotes)
	UpdateChannelsReduntant()
	for _, event in ipairs(supportedChatEvents) do
		ChatFrame_AddMessageEventFilter(event, ChatMessageFilter) ---@diagnostic disable-line: undefined-global
	end
	HookChatFrames()
	CreateSlashCommand()
	CreateAnimator()
	addonButton = CreateButton("VladsChatEmotesButton")
end

addon:SetScript("OnEvent", function(self, event, ...) self[event](self, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")

local function InitChannelMonitor()
	hooksecurefunc("FCF_OpenTemporaryWindow", HookChatFrames)
	hooksecurefunc("AddChatWindowChannel", HookChatFrames)
	hooksecurefunc("AddChatWindowChannel", UpdateChannelsReduntant)
	hooksecurefunc("RemoveChatWindowChannel", UpdateChannelsReduntant)
	addon.CHANNEL_UI_UPDATE = UpdateChannels
	addon.CHANNEL_FLAGS_UPDATED = UpdateChannels
	addon.CHANNEL_LEFT = UpdateChannels
	addon.CHAT_MSG_CHANNEL_JOIN = UpdateChannels
	addon.CHAT_MSG_CHANNEL_LEAVE = UpdateChannels
	addon.CHAT_MSG_CHANNEL_LIST = UpdateChannels
	addon.CHAT_MSG_CHANNEL_NOTICE = UpdateChannels
	addon:RegisterEvent("CHANNEL_UI_UPDATE")
	addon:RegisterEvent("CHANNEL_FLAGS_UPDATED")
	addon:RegisterEvent("CHANNEL_LEFT")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_LIST")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
end

function addon:ADDON_LOADED(event, name)
	if name ~= addonName then
		return
	end
	addon:UnregisterEvent(event)
	C_Timer.After(0, function()
		InitDB()
		Init()
		InitChannelMonitor()
	end)
end

function addon:TogglePicker(showEmote)
	if not addonFrame then
		addonFrame = CreateUI("VladsChatEmotesFrame")
		table.insert(UISpecialFrames, addonFrame:GetName()) ---@diagnostic disable-line: undefined-global
		addonFrame:SetEmotes(sortedEmotes)
	end
	if showEmote then
		addonFrame:ShowEmote(showEmote)
	else
		addonFrame:SetShown(not addonFrame:IsShown())
	end
end

function addon:ToggleConfig()
	if not addonConfigFrame then
		addonConfigFrame = CreateConfig("VladsChatEmotesConfigFrame")
		table.insert(UISpecialFrames, addonConfigFrame:GetName()) ---@diagnostic disable-line: undefined-global
	end
	addonConfigFrame:SetShown(not addonConfigFrame:IsShown())
end

--[=[

-- Log channel messages using:
-- /dump EmotesLibLogChannel(500)

-- Parse logged messages using:
-- /dump EmotesLibLogChannelTest(0.5)

-- Parse one specific message using:
-- /dump EmotesLibLogChannelTestOne(9)

do
	local f, m, x, i, p, d = CreateFrame("Frame"), 100, nil, nil, nil, nil
	f:SetScript("OnEvent", function (_, event, ...)
		if not x then
			x = ChatEmotesDB.DEBUG
			if not x then
				x = {}
				ChatEmotesDB.DEBUG = x
			end
			i = #x
			p = x[i]
		end
		i = i + 1
		d = debugprofilestop()
		local t = { index = i, after = p and d - p.after or 0, event = event, args = { ... } }
		x[i] = t
		p = t
		print(format("%d/%d events...", i, m))
		if i >= m then
			f:UnregisterAllEvents()
			print("Done!")
		end
	end)
	_G.EmotesLibLogChannel = function(maxItems)
		m = maxItems or m
		f:RegisterEvent("CHAT_MSG_CHANNEL")
	end
end

do
	local CEL_ReplaceEmotesInText = CEL.ReplaceEmotesInText
	local HEIGHT
	local function DebugChatMessageFilter(self, event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, ...)
		if not HEIGHT then
			HEIGHT = GetHeightForChatFrame(self)
		end
		local a = debugprofilestop()
		local newText, usedEmotes = CEL_ReplaceEmotesInText(text, HEIGHT, DB.options.emoteHover, true)
		local d = debugprofilestop() - a
		if newText then
			return d, false, newText, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, ...
		end
		return d
	end
	local dd
	local x, t, i, e
	local sum, num
	local function tick()
		i = i + 1
		e = x[i]
		if not e then
			if t then
				t:Cancel()
				t = nil
			end
			print("Done!")
			return
		end
		local result = { DebugChatMessageFilter(DEFAULT_CHAT_FRAME, e.event, unpack(e.args)) } ---@diagnostic disable-line: undefined-global
		local d, status, newText, playerName = result[1], result[2], result[3], result[4]
		sum, num = sum + d, num + 1
		local ol = format("[%d] %.2f (~ %.2f)", i, d, sum/num)
		if status ~= nil then
			print(ol, playerName, newText)
		else
			print(ol)
		end
		if dd > 0 and d >= dd then
			if t then
				t:Cancel()
				t = nil
			end
			print("Debug!")
		end
	end
	_G.EmotesLibLogChannelTest = function(debugMs, delayBetween, startAt)
		x = ChatEmotesDB.DEBUG
		if not x then
			return
		end
		if t then
			t:Cancel()
			t = nil
		end
		dd = debugMs or 10
		delayBetween = delayBetween or 0
		i = startAt or 0
		sum, num = 0, 0
		t = C_Timer.NewTicker(delayBetween, tick)
	end
	_G.EmotesLibLogChannelTestOne = function(index)
		x = ChatEmotesDB.DEBUG
		if not x then
			return
		end
		dd = 0
		i = (index or 1) - 1
		sum, num = 0, 0
		tick()
	end
end

--]=]
