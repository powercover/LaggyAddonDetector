local addonName, ns = ...

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local BORDER_TEXTURE = "Interface\\Minimap\\MiniMap-TrackingBorder"

local function SetButtonPosition(button)
	local angle = math.rad(ns.db and ns.db.minimapPos or 215)
	local x = math.cos(angle)
	local y = math.sin(angle)
	local round = true
	if GetMinimapShape then
		round = GetMinimapShape() ~= "SQUARE"
	end
	local radius = (Minimap:GetWidth() / 2) + 5
	local px, py = x * radius, y * radius
	if not round then
		px = math.max(-radius, math.min(px, radius))
		py = math.max(-radius, math.min(py, radius))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", px, py)
end

local function UpdateIconTint(button)
	local r, g, b = ns.SeverityColor(ns.WorstSeverity())
	button.icon:SetVertexColor(r, g, b)
end

function ns.CreateMinimapButton()
	if ns.minimapButton then
		SetButtonPosition(ns.minimapButton)
		UpdateIconTint(ns.minimapButton)
		if ns.db.minimapHide then
			ns.minimapButton:Hide()
		else
			ns.minimapButton:Show()
		end
		return ns.minimapButton
	end

	local button = CreateFrame("Button", "LaggyAddonDetectorMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetMovable(true)

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture(BORDER_TEXTURE)
	overlay:SetPoint("TOPLEFT")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON_TEXTURE)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon = icon

	button:SetScript("OnClick", function()
		if ns.ToggleFrame then
			ns.ToggleFrame()
		end
	end)

	button:SetScript("OnEnter", function(self)
		ns.Collect({ memory = false })
		ns.ShowHeavyTooltip(self)
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local function DragUpdate(self)
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		ns.db.minimapPos = math.deg(math.atan2(py - my, px - mx)) % 360
		SetButtonPosition(self)
	end

	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", DragUpdate)
	end)

	button:SetScript("OnDragStop", function(self)
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
	end)

	ns.minimapButton = button
	SetButtonPosition(button)
	UpdateIconTint(button)
	if ns.db and ns.db.minimapHide then
		button:Hide()
	end

	ns.RegisterListener(function()
		if ns.minimapButton then
			UpdateIconTint(ns.minimapButton)
			if GameTooltip:IsOwned(ns.minimapButton) then
				ns.ShowHeavyTooltip(ns.minimapButton)
			end
		end
	end)

	return button
end
