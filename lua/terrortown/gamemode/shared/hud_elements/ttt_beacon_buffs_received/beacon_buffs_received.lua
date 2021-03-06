local base = "pure_skin_element"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

--Most code here is taken from Vampire and Bodyguard HUD logic.
if CLIENT then
	local pad = 7
	local iconSize = 64
	local icon_beac_unlit = Material("vgui/ttt/dynamic/roles/icon_beac")
	local icon_beac_lit = Material("vgui/ttt/icon_beac_lit")
	
	HUDELEMENT.icon = Material("vgui/ttt/icon_beac_unlit")
	
	local const_defaults = {
		basepos = {x = 0, y = 0},
		size = {w = 365, h = 32},
		minsize = {w = 225, h = 32}
	}

	function HUDELEMENT:PreInitialize()
		BaseClass.PreInitialize(self)

		local hud = huds.GetStored("pure_skin")
		if not hud then return end

		hud:ForceElement(self.id)
	end

	function HUDELEMENT:Initialize()
		self.scale = 1.0
		self.basecolor = self:GetHUDBasecolor()
		self.pad = pad
		self.iconSize = iconSize

		BaseClass.Initialize(self)
	end

	-- parameter overwrites
	function HUDELEMENT:IsResizable()
		return true, false
	end
	-- parameter overwrites end

	function HUDELEMENT:GetDefaults()
		const_defaults["basepos"] = {
			x = 10 * self.scale,
			y = ScrH() - self.size.h - 146 * self.scale - self.pad - 10 * self.scale
		}

		return const_defaults
	end

	function HUDELEMENT:PerformLayout()
		self.scale = self:GetHUDScale()
		self.basecolor = self:GetHUDBasecolor()
		self.iconSize = iconSize * self.scale
		self.pad = pad * self.scale

		BaseClass.PerformLayout(self)
	end

	function HUDELEMENT:ShouldDraw()
		local client = LocalPlayer()

		return HUDEditor.IsEditing or (client:Alive() and client:GetSubRole() == ROLE_BEACON)
	end
	
	function HUDELEMENT:SetIcon(new_icon)
		self.icon = new_icon
	end

	function HUDELEMENT:DrawComponent(text, bg_color, icon_color)
		local pos = self:GetPos()
		local size = self:GetSize()
		local x, y = pos.x, pos.y
		local w, h = size.w, size.h
		
		self:DrawBg(x, y, w, h, bg_color)
		draw.AdvancedText(text, "PureSkinBar", x + self.iconSize + self.pad, y + h * 0.5, util.GetDefaultColor(bg_color), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true, self.scale)
		self:DrawLines(x, y, w, h, self.basecolor.a)
		
		local nSize = self.iconSize - 16
		
		draw.FilteredShadowedTexture(x, y - 2 - (nSize - h), nSize, nSize, self.icon, 255, icon_color, self.scale)
	end
	
	function HUDELEMENT:Draw()
		local client = LocalPlayer()
		local bg_color = self.basecolor
		local icon_color = COLOR_BLACK
		local max_buff_str = ""
		self:SetIcon(icon_beac_unlit)
		
		if client:GetNWBool("IsDetectiveBeacon") then
			--Light up the HUD itself if the beacon becomes detective-like.
			bg_color = BEACON.color
			icon_color = COLOR_WHITE
			self:SetIcon(icon_beac_lit)
		end
		if not bg_color then return end
		
		if client.beac_cl_num_buffs >= GetConVar("ttt2_beacon_max_buffs"):GetInt() then
			max_buff_str = LANG.GetTranslation("max_power_" .. BEACON.name)
		end
		
		self:DrawComponent(LANG.GetTranslation("buffs_received_" .. BEACON.name) .. client.beac_cl_num_buffs .. max_buff_str, bg_color, icon_color)
	end
end