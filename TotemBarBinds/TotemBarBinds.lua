-- TotemBarBinds: keybinds for Blizzard's shaman totem bar (MultiCastActionBarFrame).
--
-- Each bindable action is a hidden secure button that mirrors the matching
-- button on the totem bar. Keys are attached with override bindings, so they
-- win over the normal keybinds while set.

local ADDON_NAME = ...

-- Shamans only: on any other class, create nothing (no minimap button,
-- settings window, slash command or bindings). Saved binds are left untouched.
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local issecretvalue = issecretvalue or function() return false end
local NUM_SLOTS = 4

-- id, label
local ACTIONS = {
	{ "summon", "Call of Totems" },
	{ "slot1",  "Totem slot 1" },
	{ "slot2",  "Totem slot 2" },
	{ "slot3",  "Totem slot 3" },
	{ "slot4",  "Totem slot 4" },
	{ "recall", "Totemic Recall" },
}

local db
local owner = CreateFrame("Frame")   -- owns the override bindings
local buttons = {}                   -- action id -> secure button
local pendingApply                   -- bindings changed during combat

--------------------------------------------------------------------------------
-- Secure buttons
--------------------------------------------------------------------------------

local function Bar() return _G.MultiCastActionBarFrame end

-- the totem bar button an action id refers to
local function BarButton(id)
	if id == "summon" then return _G.MultiCastSummonSpellButton end
	if id == "recall" then return _G.MultiCastRecallSpellButton end
	local pos = tonumber(id:match("^slot(%d)$"))
	local bar = Bar()
	local page = bar and bar.currentPage
	if not page or issecretvalue(page) or page < 1 then page = 1 end
	return _G["MultiCastActionButton" .. ((page - 1) * NUM_SLOTS + pos)]
end

local function ActionOf(b)
	local action = b.action
	if not action and b.CalculateAction then action = b:CalculateAction() end
	if not action and ActionButton_CalculateAction then action = ActionButton_CalculateAction(b) end
	if action and not issecretvalue(action) and action > 0 then return action end
end

for _, a in ipairs(ACTIONS) do
	local b = CreateFrame("Button", "TotemBarBinds_" .. a[1], UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("pressAndHoldAction", true)   -- fire on key down
	buttons[a[1]] = b
end

-- Points every secure button at what its totem bar button currently does.
-- Secure attributes can't change in combat, so this waits for combat to end.
local function UpdateButtons()
	if InCombatLockdown() then return end
	for id, b in pairs(buttons) do
		local target = BarButton(id)
		local action = target and ActionOf(target)
		local spell = target and target:GetAttribute("spell")
		b:SetAttribute("action", nil)
		b:SetAttribute("spell", nil)
		b:SetAttribute("clickbutton", nil)
		if action then
			b:SetAttribute("type", "action")
			b:SetAttribute("action", action)
		elseif spell then
			b:SetAttribute("type", "spell")
			b:SetAttribute("spell", spell)
		elseif target then
			b:SetAttribute("type", "click")
			b:SetAttribute("clickbutton", target)
		else
			b:SetAttribute("type", nil)
		end
	end
end

--------------------------------------------------------------------------------
-- Bindings
--------------------------------------------------------------------------------

local function ApplyBindings()
	if InCombatLockdown() then pendingApply = true return end
	pendingApply = nil
	ClearOverrideBindings(owner)
	for id, key in pairs(db.binds) do
		if buttons[id] then
			SetOverrideBindingClick(owner, false, key, buttons[id]:GetName(), "LeftButton")
		end
	end
end

local function SetBind(id, key)
	if key then
		for other, k in pairs(db.binds) do   -- one key, one action
			if k == key then db.binds[other] = nil end
		end
	end
	db.binds[id] = key
	ApplyBindings()
end

--------------------------------------------------------------------------------
-- Settings window
--------------------------------------------------------------------------------

local settings, rows, capturing

local IGNORED_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, UNKNOWN = true, LMETA = true, RMETA = true,
}

local function RefreshRows()
	for _, row in ipairs(rows) do
		local key = db.binds[row.id]
		if capturing == row then
			row.bind:SetText("|cffffd100Press a key...|r")
		else
			row.bind:SetText(key and GetBindingText(key) or "|cff808080Not bound|r")
		end
	end
end

local function StopCapture()
	capturing = nil
	settings:EnableKeyboard(false)
	RefreshRows()
end

local function OnKeyDown(self, key)
	if not capturing then return end
	if IGNORED_KEYS[key] then return end
	if key == "ESCAPE" then return StopCapture() end
	local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "")
	SetBind(capturing.id, mods .. key)
	StopCapture()
end

local function CreateSettings()
	local f = CreateFrame("Frame", "TotemBarBindsSettings", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(300, 70 + #ACTIONS * 28)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnKeyDown", OnKeyDown)
	f:SetScript("OnHide", function() if capturing then StopCapture() end end)
	f:Hide()
	tinsert(UISpecialFrames, f:GetName())   -- ESC closes it

	local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not f.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("Totem Bar Binds")

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 12)
	hint:SetText("Left-click to bind, right-click to clear")

	rows = {}
	for i, a in ipairs(ACTIONS) do
		local row = { id = a[1] }
		local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOPLEFT", 16, -35 - (i - 1) * 28)
		label:SetText(a[2])

		local bind = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		bind:SetSize(130, 22)
		bind:SetPoint("TOPRIGHT", -14, -30 - (i - 1) * 28)
		bind:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		bind:SetScript("OnClick", function(_, mouse)
			if InCombatLockdown() then return end
			if mouse == "RightButton" then
				capturing = nil
				SetBind(row.id, nil)
			else
				capturing = row
				f:EnableKeyboard(true)
				f:SetPropagateKeyboardInput(false)
			end
			RefreshRows()
		end)
		row.bind = bind
		rows[i] = row
	end
	return f
end

local function ToggleSettings()
	if InCombatLockdown() then
		print("|cff66dd99" .. ADDON_NAME .. ":|r can't change binds in combat.")
		return
	end
	settings = settings or CreateSettings()
	settings:SetShown(not settings:IsShown())
	RefreshRows()
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local function CreateMinimapButton()
	local b = CreateFrame("Button", "TotemBarBindsMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Spell_Nature_StoneSkinTotem")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	local function Place()
		local angle = math.rad(db.minimapAngle)
		local r = Minimap:GetWidth() / 2 + 5
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
	end

	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			Place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnClick", ToggleSettings)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Totem Bar Binds")
		GameTooltip:AddLine("Click to set totem bar keybinds", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	Place()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
pcall(events.RegisterEvent, events, "UPDATE_MULTI_CAST_ACTIONBAR")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		TotemBarBindsDB = TotemBarBindsDB or {}
		db = TotemBarBindsDB
		db.binds = db.binds or {}
		db.minimapAngle = db.minimapAngle or 200
		CreateMinimapButton()
		if MultiCastActionBarFrame_Update then
			hooksecurefunc("MultiCastActionBarFrame_Update", UpdateButtons)
		end
		ApplyBindings()
	end
	UpdateButtons()
	if event == "PLAYER_REGEN_ENABLED" and pendingApply then ApplyBindings() end
end)

SLASH_TOTEMBARBINDS1 = "/tbb"
SlashCmdList.TOTEMBARBINDS = ToggleSettings
