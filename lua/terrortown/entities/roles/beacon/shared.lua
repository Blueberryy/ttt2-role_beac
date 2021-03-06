AddCSLuaFile()

if SERVER then
	resource.AddFile("materials/vgui/ttt/dynamic/roles/icon_beac.vmt")
	util.AddNetworkString("TTT2UpdateNumBeaconBuffs")
	util.AddNetworkString("TTT2BeaconRateOfFireUpdate")
end

function ROLE:PreInitialize()
	self.color = Color(255, 255, 153, 255)
	self.abbr = "beac" -- abbreviation
	
	self.surviveBonus = 0.5 -- bonus multiplier for every survive when another player was killed
	self.scoreKillsMultiplier = 1 -- multiplier for kill of player of another team
	self.scoreTeamKillsMultiplier = -16 -- multiplier for teamkill
	
	self.unknownTeam = true -- disables team voice chat.
	self.disableSync = false -- Do tell the player about his role

	self.defaultTeam = TEAM_INNOCENT -- the team name: roles with same team name are working together
	self.defaultEquipment = INNO_EQUIPMENT -- here you can set up your own default equipment

	-- ULX ConVars
	self.conVarData = {
		pct = 0.15, -- necessary: percentage of getting this role selected (per player)
		maximum = 1, -- maximum amount of roles in a round
		minPlayers = 6, -- minimum amount of players until this role is able to get selected
		credits = 0, -- the starting credits of a specific role
		shopFallback = SHOP_DISABLED,
		togglable = true, -- option to toggle a role for a client if possible (F1 menu)
		random = 30
	}
end

function ROLE:Initialize()
	roles.SetBaseRole(self, ROLE_INNOCENT)
end

if SERVER then
	--CONSTANTS
	--Hardcoded default that everyone uses.
	local DEFAULT_JUMP_POWER = 160
	--ttt2_beacon_search_mode enum
	local SEARCH_MODE = {MATES = 0, OTHER = 1, ANY = 2, NONE = 3}
	--enum for how the beacon's stats will be updated.
	local UPDATE_MODE = {ONE = 0, ALL = 1}
	
	local function SendNumBuffsToClient(ply)
		--Send the updated number of buffs to the client
		net.Start("TTT2UpdateNumBeaconBuffs")
		net.WriteInt(ply.beac_sv_data.num_buffs, 16)
		net.Send(ply)
	end
	
	local function RoundHasNotBegun()
		--Don't do anything if the round hasn't started yet (beac_sv_data may not exist)
		return (GetRoundState() == ROUND_WAIT or GetRoundState() == ROUND_PREP)
	end
	
	local function GetObservedTeam(ply)
		local team = ply:GetTeam()
		
		--Role-specific edge cases: Certain roles may actively lie about what their role actually is.
		--However, this is only truly reflected after the info on the corpse has been compiled and sent.
		if ply:GetSubRole() == ROLE_SPY and GetConVar("ttt2_spy_confirm_as_traitor"):GetBool() then
			team = TEAM_TRAITOR
		end
		
		return team
	end
	
	--UNCOMMENT FOR DEBUGGING
	--local function PrintBeaconStats(prefix_str, ply)
	--	local n = ply.beac_sv_data.num_buffs
	--	local speed = 1 + n * GetConVar("ttt2_beacon_speed_boost"):GetFloat()
	--	local resist = n * GetConVar("ttt2_beacon_resist_boost"):GetFloat()
	--  local hp_regen = n * GetConVar("ttt2_beacon_hp_regen_boost"):GetFloat()
	--	local dmg = 1 + n * GetConVar("ttt2_beacon_damage_boost"):GetFloat()
	--  local fire_rate = 1 + n * GetConVar("ttt2_beacon_fire_rate_boost"):GetFloat()
	--	print(prefix_str, "name=", ply:GetName(), ", num_buffs=", n, ", speed=", speed, ", jump=", ply:GetJumpPower(), ", resist=", resist, ", armor=", ply:GetArmor(), ", hp_regen=", hp_regen, ", dmg=", dmg, ", fire_rate=", fire_rate)
	--end
	
	--WeaponSpeed functionality taken and modified from TTT2 Super Soda mod
	local function ApplyWeaponSpeedForBeacon(wep, n)
		local ply = wep.Owner
		if RoundHasNotBegun() or not IsValid(wep) or not IsValid(ply) then
			return
		end
		
		if (wep.Kind == WEAPON_MELEE or wep.Kind == WEAPON_HEAVY or wep.Kind == WEAPON_PISTOL) then
			if not wep.beac_modded then
				wep.beac_modded = true
			end
			
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG ApplyWeaponSpeedForBeacon Before: ", wep.Primary.Delay)
			
			wep.Primary.Delay = wep.Primary.Delay / (1 + n * GetConVar("ttt2_beacon_fire_rate_boost"):GetFloat())
			
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG ApplyWeaponSpeedForBeacon After: ", wep.Primary.Delay)
			
			net.Start("TTT2BeaconRateOfFireUpdate")
			net.WriteEntity(wep)
			net.WriteFloat(wep.Primary.Delay)
			net.Send(ply)
		end
	end
	
	local function DisableWeaponSpeedForBeacon(ply, wep, n)
		if not IsValid(wep) or not IsValid(ply) then
			return
		end
		
		--Only remove speed if the weapon was tinkered with by the beacon.
		--Prevents issue where the weapon may otherwise get stats removed multiple times on player death (Due to Drop and Switch being called).
		if wep.beac_modded and (wep.Kind == WEAPON_MELEE or wep.Kind == WEAPON_HEAVY or wep.Kind == WEAPON_PISTOL) then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG DisableWeaponSpeedForBeacon Before: ", wep.Primary.Delay)
			
			wep.Primary.Delay = wep.Primary.Delay * (1 + n * GetConVar("ttt2_beacon_fire_rate_boost"):GetFloat())
			
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG DisableWeaponSpeedForBeacon After: ", wep.Primary.Delay)
			
			net.Start("TTT2BeaconRateOfFireUpdate")
			net.WriteEntity(wep)
			net.WriteFloat(wep.Primary.Delay)
			net.Send(ply)
			
			wep.beac_modded = nil
		end
	end
	
	hook.Add("PlayerSwitchWeapon", "UpdateWeaponOnSwitchForBeacon", function(ply, old, new)
		if RoundHasNotBegun() or not IsValid(old) or not IsValid(new) or not IsValid(ply) or ply:GetSubRole() ~= ROLE_BEACON or not ply.beac_sv_data then
			return
		end
		
		--UNCOMMENT FOR DEBUGGING
		--print("BEAC_DEBUG UpdateWeaponOnSwitchForBeacon")
		
		DisableWeaponSpeedForBeacon(ply, old, ply.beac_sv_data.num_buffs)
		ApplyWeaponSpeedForBeacon(new, ply.beac_sv_data.num_buffs)
	end)
	
	hook.Add("PlayerDroppedWeapon", "UpdateWeaponOnDropForBeacon", function(ply, wep)
		if RoundHasNotBegun() or not IsValid(wep) or not IsValid(ply) or ply:GetSubRole() ~= ROLE_BEACON or not ply.beac_sv_data then
			return
		end
		
		--UNCOMMENT FOR DEBUGGING
		--print("BEAC_DEBUG UpdateWeaponOnDropForBeacon")
		
		DisableWeaponSpeedForBeacon(ply, wep, ply.beac_sv_data.num_buffs)
	end)
	
	local function UpdateBeaconStats(ply, update_mode)
		if not IsValid(ply) or not ply:IsPlayer() or not ply.beac_sv_data then
			return
		end
		
		--Speed is handled in TTTPlayerSpeedModifier handle.
		--Damage and Resistance is handled in EntityTakeDamage handle.
		--Health Regen is handled in Think handle.
		
		local n = 1
		if update_mode == UPDATE_MODE.ALL then
			n = ply.beac_sv_data.num_buffs
			
			ApplyWeaponSpeedForBeacon(ply:GetActiveWeapon(), n)
		else
			if ply.beac_sv_data.num_buffs > 0 then
				--This probably isn't the best method, but currently in order for the numbers to line up properly, need to remove the previous rate of fire buff and replace it with the new one.
				--Specifically this is done to avoid quirks with division and multiplication. Would be easier if subtraction and addition could be used here.
				DisableWeaponSpeedForBeacon(ply, ply:GetActiveWeapon(), ply.beac_sv_data.num_buffs - 1)
				ApplyWeaponSpeedForBeacon(ply:GetActiveWeapon(), ply.beac_sv_data.num_buffs)
			else
				--First time we're buffing the beacon, just give them the one buff.
				ApplyWeaponSpeedForBeacon(ply:GetActiveWeapon(), 1)
			end
		end
		
		ply:SetJumpPower(ply:GetJumpPower() + n * (DEFAULT_JUMP_POWER * GetConVar("ttt2_beacon_jump_boost"):GetFloat()))
		ply:GiveArmor(n * GetConVar("ttt2_beacon_armor_boost"):GetInt())
		
		--Only give no fall damage if beacon runs risk of hurting themselves merely from jumping
		if ply:GetJumpPower() > DEFAULT_JUMP_POWER and not ply:HasEquipmentItem("item_ttt_nofalldmg") then
			ply:GiveEquipmentItem("item_ttt_nofalldmg")
		end
		
		if ply.beac_sv_data.num_buffs >= GetConVar("ttt2_beacon_deputize_num_buffs"):GetInt() then
			--Make the beacon known to everyone in game (similar to detective).
			ply:SetNWBool("IsDetectiveBeacon", true)
			SendPlayerToEveryone(ply)
		end
		
		--Allow for the beacon to lose their stats again.
		ply.beac_sv_data.has_buffs = true
	end
	
	local function GiveBeaconBuffToPlayer(ply, provider_id, provider_is_client)
		if RoundHasNotBegun() or not IsValid(ply) or not ply:IsPlayer() or not ply.beac_sv_data then
			return
		end
		
		--Beacon can only have so many buffs
		if ply.beac_sv_data.num_buffs >= GetConVar("ttt2_beacon_max_buffs"):GetInt() then
			return
		end
		
		--Beacon can't be their own provider
		if provider_is_client and ply:SteamID64() == provider_id then
			return
		end
		
		--Only buff the given beacon if they have not already been buffed by the provider.
		--We can also buff the given beacon if the server demands it (not provider_is_client)
		if not provider_is_client or ply.beac_sv_data.buff_providers[provider_id] == nil then
			--UNCOMMENT FOR DEBUGGING
			--PrintBeaconStats("BEAC_DEBUG UpdateBeaconStats Before: ", ply)
			
			--Increment even if the player isn't a beacon, in case they become one (ex. amnesiac).
			ply.beac_sv_data.num_buffs = ply.beac_sv_data.num_buffs + 1
			
			SendNumBuffsToClient(ply)
			
			--Don't directly modify the stats of dead beacons or non-beacons.
			if ply:Alive() and ply:GetSubRole() == ROLE_BEACON then
				UpdateBeaconStats(ply, UPDATE_MODE.ONE)
			end
			
			if provider_is_client then
				--Ensure that duplicate buffs aren't given.
				ply.beac_sv_data.buff_providers[provider_id] = true
			end
			
			--UNCOMMENT FOR DEBUGGING
			--PrintBeaconStats("BEAC_DEBUG UpdateBeaconStats After: ", ply)
		end
	end
	
	local function GiveBeaconBuffToAllPlayers(provider_id)
		for _,ply in pairs(player.GetAll()) do
			GiveBeaconBuffToPlayer(ply, provider_id, true)
		end
	end
	
	local function DebuffABeacon(ply)
		if RoundHasNotBegun() or not IsValid(ply) or not ply:IsPlayer() or not ply.beac_sv_data then
			return
		end
		
		--When this is called the player may not necessarily be a beacon (ex. on a role change), so don't check for that.
		
		--UNCOMMENT FOR DEBUGGING
		--PrintBeaconStats("BEAC_DEBUG DebuffABeacon Before: ", ply)
		
		local n = ply.beac_sv_data.num_buffs
		
		--Speed is handled in TTTPlayerSpeedModifier handle.
		--Damage and Resistance is handled in EntityTakeDamage handle.
		--Health Regeneration is handled in Think handle.
		ply:SetJumpPower(ply:GetJumpPower() - n * (DEFAULT_JUMP_POWER * GetConVar("ttt2_beacon_jump_boost"):GetFloat()))
		ply:RemoveArmor(n * GetConVar("ttt2_beacon_armor_boost"):GetInt())
		DisableWeaponSpeedForBeacon(ply, ply:GetActiveWeapon(), n)
		
		if ply:HasEquipmentItem("item_ttt_nofalldmg") then
			ply:RemoveEquipmentItem("item_ttt_nofalldmg")
		end
		
		--Do not alter num_buffs here, in case they become a beacon later on (ex. admin ulx)
		
		ply:SetNWBool("IsDetectiveBeacon", false)
		
		ply.beac_sv_data.has_buffs = false
		
		--UNCOMMENT FOR DEBUGGING
		--PrintBeaconStats("BEAC_DEBUG DebuffABeacon After: ", ply)
	end
	
	hook.Add("TTTPlayerSpeedModifier", "BeaconModifySpeed", function(ply, _, _, no_lag)
		if RoundHasNotBegun() or not ply.beac_sv_data then
			return
		end
		
		if IsValid(ply) and ply:IsPlayer() and ply:GetSubRole() == ROLE_BEACON then
			no_lag[1] = no_lag[1] * (1 + ply.beac_sv_data.num_buffs * GetConVar("ttt2_beacon_speed_boost"):GetFloat())
		end
	end)
	
	hook.Add("EntityTakeDamage", "BeaconModifyDamage", function(target, dmg_info)
		if RoundHasNotBegun() then
			return
		end
		
		local attacker = dmg_info:GetAttacker()
		
		if not IsValid(target) or not target:IsPlayer() or not IsValid(attacker) or not attacker:IsPlayer() or not attacker.beac_sv_data then
			return
		end
		
		--UNCOMMENT FOR DEBUGGING
		--if target:GetSubRole() == ROLE_BEACON or attacker:GetSubRole() == ROLE_BEACON then
		--	print("BEAC_DEBUG BeaconModifyDamage Target Name=" .. target:GetName() .. ", Attacker Name=" .. attacker:GetName())
		--	print("BEAC_DEBUG BeaconModifyDamage Before: " .. dmg_info:GetDamage())
		--end
		
		if target:GetSubRole() == ROLE_BEACON then
			dmg_info:SetDamage(dmg_info:GetDamage() * (1 - attacker.beac_sv_data.num_buffs * GetConVar("ttt2_beacon_resist_boost"):GetFloat()))
		end
		
		if attacker:GetSubRole() == ROLE_BEACON then
			dmg_info:SetDamage(dmg_info:GetDamage() * (1 + attacker.beac_sv_data.num_buffs * GetConVar("ttt2_beacon_damage_boost"):GetFloat()))
		end
		
		--UNCOMMENT FOR DEBUGGING
		--if target:GetSubRole() == ROLE_BEACON or attacker:GetSubRole() == ROLE_BEACON then
		--	print("BEAC_DEBUG BeaconModifyDamage After: " .. dmg_info:GetDamage())
		--end
	end)
	
	local function BeaconHealthRegen(ply, cur_time)
		local ply_can_be_healed = ((ply.beac_sv_data.last_healed) + 1 <= cur_time) and ply:Health() < ply:GetMaxHealth()
		local healing_enabled_for_ply = (ply.beac_sv_data.num_buffs * GetConVar("ttt2_beacon_hp_regen_boost"):GetFloat() > 0)
		if ply_can_be_healed and healing_enabled_for_ply then
			ply.beac_sv_data.last_healed = cur_time
			ply.beac_sv_data.hp_bank = ply.beac_sv_data.hp_bank + ply.beac_sv_data.num_buffs * GetConVar("ttt2_beacon_hp_regen_boost"):GetFloat()
			
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG BeaconHealthRegen: hp_bank=" .. ply.beac_sv_data.hp_bank)
			
			if ply.beac_sv_data.hp_bank >= 1 then
				--Since HP Regen ConVar is most likely a fraction, add it to a running total, and only heal when the total exceeds 1.
				local heal = math.floor(ply.beac_sv_data.hp_bank)
				ply:SetHealth(ply:Health() + heal)
				ply.beac_sv_data.hp_bank = ply.beac_sv_data.hp_bank - heal
			end
		end
	end
	
	local function BeaconBuffOnTimeInterval(ply, cur_time)
		local time_interval = GetConVar("ttt2_beacon_buff_every_x_seconds"):GetInt()
		if time_interval > 0 then
			if not ply.beac_sv_data.next_time_buffed or ply.beac_sv_data.next_time_buffed < 0 then
				ply.beac_sv_data.next_time_buffed = cur_time + time_interval
			elseif cur_time >= ply.beac_sv_data.next_time_buffed then
				--This is a special case, where the server is providing the buff, not any dead player.
				GiveBeaconBuffToPlayer(ply, nil, false)
				ply.beac_sv_data.next_time_buffed = cur_time + time_interval
			end
		end
	end
	
	hook.Add("Think", "BeaconThink", function()
		if GetRoundState() ~= ROUND_ACTIVE then
			return
		end
		
		local cur_time = CurTime()
		for _, ply in ipairs(player.GetAll()) do
			if IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply.beac_sv_data and ply:GetSubRole() == ROLE_BEACON then
				BeaconHealthRegen(ply, cur_time)
				BeaconBuffOnTimeInterval(ply, cur_time)
			end
		end
	end)
	
	local function CanReceiveBuffFromDeadPlayer(dead_ply)
		if GetRoundState() ~= ROUND_ACTIVE or not IsValid(dead_ply) or not dead_ply:IsPlayer() then
			return false
		end
		
		local team = GetObservedTeam(dead_ply)
		if GetConVar("ttt2_beacon_search_mode"):GetInt() == SEARCH_MODE.MATES then
			return (team == TEAM_INNOCENT)
		elseif GetConVar("ttt2_beacon_search_mode"):GetInt() == SEARCH_MODE.OTHER then
			return (team ~= TEAM_INNOCENT)
		elseif GetConVar("ttt2_beacon_search_mode"):GetInt() == SEARCH_MODE.ANY then
			return true
		end
		
		--SEARCH_MODE.NONE
		return false
	end
	
	hook.Add("TTT2PostPlayerDeath", "JudgeTheBeacon", function(victim, inflictor, attacker)
		if GetRoundState() ~= ROUND_ACTIVE or not attacker.beac_sv_data then
			return
		end
		
		if not IsValid(victim) or not victim:IsPlayer() or not IsValid(attacker) or not attacker:IsPlayer() then
			return
		end
		
		local was_a_suicide = (victim:SteamID64() == attacker:SteamID64())
		local killed_an_inno = (GetObservedTeam(victim) == TEAM_INNOCENT)
		
		if not was_a_suicide and killed_an_inno then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG BeaconUpdateOnDeath: Preventing inno-killer from being beacon.")
			
			--Prevent any role (ex. amnesiac) from becoming a beacon if they kill an innocent.
			attacker.beac_sv_data.has_killed_inno = true
		
			if attacker:GetSubRole() == ROLE_BEACON then
				--Demote the guilty one.
				--Indirectly calls DebuffABeacon()
				attacker:SetRole(ROLE_INNOCENT)
				--Call this whenever a role change occurs during an active round
				SendFullStateUpdate()
				attacker:TakeDamage(GetConVar("ttt2_beacon_judgement"):GetInt(), game.GetWorld())
			end
		end
		
		if GetConVar("ttt2_beacon_buff_on_death"):GetBool() and CanReceiveBuffFromDeadPlayer(victim) then
			GiveBeaconBuffToAllPlayers(victim:SteamID64())
		end
	end)
	
	hook.Add("TTTCanSearchCorpse", "BeaconUpdateOnCorpseSearch", function(ply, rag, isCovert, isLongRange)
		if RoundHasNotBegun() or not ply.beac_sv_data then
			return
		end
		
		local dead_ply = player.GetBySteamID64(rag.sid64)
		
		--Don't do anything if the player searching the corpse isn't actively participating
		if not IsValid(dead_ply) or not IsValid(ply) or not ply:Alive() then
			return
		end
		
		if CanReceiveBuffFromDeadPlayer(dead_ply) then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG BeaconUpdateOnCorpseSearch: isCovert=", isCovert, ", ID=", dead_ply:SteamID64())
			
			if isCovert then
				--Only update the player that's covertly searching the body.
				GiveBeaconBuffToPlayer(ply, dead_ply:SteamID64(), true)
			else
				GiveBeaconBuffToAllPlayers(dead_ply:SteamID64())
			end
		end
	end)
	
	hook.Add("TTT2UpdateSubrole", "BeaconBackgroundCheck", function(self, oldSubrole, subrole)
		if RoundHasNotBegun() or not self.beac_sv_data then
			return
		end
		
		if oldSubrole ~= ROLE_BEACON and subrole == ROLE_BEACON then
			--Looks like someone thinks they can be a beacon.
			if self.beac_sv_data.has_killed_inno then
				--UNCOMMENT FOR DEBUGGING
				--print("BEAC_DEBUG BeaconBackgroundCheck: Refusing to change role to Beacon")
				
				--RDM-ers and bad men not allowed.
				self:SetRole(ROLE_INNOCENT)
				--Call this whenever a role change occurs during an active round
				SendFullStateUpdate()
			end
		end
	end)
	
	hook.Add("TTT2SpecialRoleSyncing", "BeaconRoleSync", function(ply, tbl)
		--This hook is needed to maintain a beacon's "glow" if they respawn or briefly change roles.
		for beac in pairs(tbl) do
			if beac:GetSubRole() == ROLE_BEACON and beac:GetNWBool("IsDetectiveBeacon") then
				tbl[beac] = {ROLE_BEACON, TEAM_INNOCENT}
			end
		end
	end)
	
	local function ResetBeaconPlayerDataForServer(ply)
		if not ply.beac_sv_data or not ply.beac_sv_data.skip_next_reset then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG ResetBeaconPlayerDataForServer: Resetting player " .. ply:GetName())
			
			local ply_was_debuffed = false
			if ply.beac_sv_data and ply.beac_sv_data.has_buffs then
				--UNCOMMENT FOR DEBUGGING
				--print("BEAC_DEBUG ResetBeaconPlayerDataForServer: Debuffing player " .. ply:GetName())
				
				--Remove the beacon's buffs before they are reset.
				--Typically this scenario will be hit if the beacon survives to the end of the round.
				DebuffABeacon(ply)
				ply_was_debuffed = true
			end
			
			--Initialize player data that only the server must know about
			ply.beac_sv_data = {}
			ply.beac_sv_data.has_buffs = false
			ply.beac_sv_data.has_killed_inno = false
			ply.beac_sv_data.next_time_buffed = -1
			ply.beac_sv_data.last_healed = 0
			ply.beac_sv_data.hp_bank = 0
			ply.beac_sv_data.buff_providers = {}
			ply.beac_sv_data.num_buffs = GetConVar("ttt2_beacon_min_buffs"):GetInt()
			if ply_was_debuffed then
				--debuffed player loses all of their buffs, back to the default.
				ply.beac_sv_data.num_buffs = 0
			end
			SendNumBuffsToClient(ply)
			
			--Initialize player data that anyone can pick up from the server at any time.
			ply:SetNWBool("IsDetectiveBeacon", false)
		else
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG ResetBeaconPlayerDataForServer: Not resetting player " .. ply:GetName())
			
			--Beacon was already reset and initialized. Make sure they will be reset at end of round.
			ply.beac_sv_data.skip_next_reset = false
		end
	end
	
	local function ResetAllBeaconDataForServer()
		for i, ply in ipairs(player.GetAll()) do
			ResetBeaconPlayerDataForServer(ply)
		end
	end
	hook.Add("TTTEndRound", "ResetBeaconForServerOnEndRound", ResetAllBeaconDataForServer)
	hook.Add("TTTPrepareRound", "ResetBeaconForServerOnPrepareRound", ResetAllBeaconDataForServer)
	hook.Add("TTTBeginRound", "ResetBeaconForServerOnBeginRound", ResetAllBeaconDataForServer)
	
	function ROLE:GiveRoleLoadout(ply, isRoleChange)
		--UNCOMMENT FOR DEBUGGING
		--print("BEAC_DEBUG GiveRoleLoadout: Giving role to " .. ply:GetName())
			
		if RoundHasNotBegun() then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG GiveRoleLoadout: Resetting " .. ply:GetName())
			
			--GiveRoleLoadout is called before the round has begun proper.
			--Consequently, their server stats may not be defined.
			--This is the best way of ensuring that a player who starts the round as a beacon is properly set up.
			ResetBeaconPlayerDataForServer(ply)
			--This variable is to differentiate between the typical beacon and (for example) an amnesiac.
			ply.beac_sv_data.skip_next_reset = true
		end
		
		--If condition prevents edge case where murderous amnesiac is quickly given beacon buffs before becoming innocent
		if not ply.beac_sv_data.has_killed_inno then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG GiveRoleLoadout: Updating stats for " .. ply:GetName())
			
			--Send # of buffs here because client may try to override the value when the round begins.
			SendNumBuffsToClient(ply)
			
			UpdateBeaconStats(ply, UPDATE_MODE.ALL)
		end
	end

	function ROLE:RemoveRoleLoadout(ply, isRoleChange)
		if RoundHasNotBegun() or not ply.beac_sv_data then
			return
		end
		
		--Sometimes RemoveRoleLoadout is called multiple times in a row, so here's a workaround.
		if ply.beac_sv_data.has_buffs then
			--UNCOMMENT FOR DEBUGGING
			--print("BEAC_DEBUG RemoveRoleLoadout")
			
			DebuffABeacon(ply)
		end
	end
end

if CLIENT then
	local function ResetBeaconPlayerDataForClient()
		--Initialize data that this client needs to know, but must be kept secret from other clients.
		local client = LocalPlayer()
		if not client.beac_cl_num_buffs then
			client.beac_cl_num_buffs = 0
		end
	end
	hook.Add("TTTEndRound", "ResetBeaconForClientOnEndRound", ResetBeaconPlayerDataForClient)
	hook.Add("TTTPrepareRound", "ResetBeaconForClientOnPrepareRound", ResetBeaconPlayerDataForClient)
	hook.Add("TTTBeginRound", "ResetBeaconForClientOnBeginRound", ResetBeaconPlayerDataForClient)

	net.Receive("TTT2UpdateNumBeaconBuffs", function()
		local client = LocalPlayer()
		local num_buffs = net.ReadInt(16)
		
		client.beac_cl_num_buffs = num_buffs
	end)
	
	net.Receive("TTT2BeaconRateOfFireUpdate", function()
		local wep = net.ReadEntity()
		if wep and wep.Primary then
			wep.Primary.Delay = net.ReadFloat()
		end
	end)
	
	--Modified from Pharoah's Ankh.
	function BeaconDynamicLight(ply, color, brightness)
		-- make sure initial values are set
		if not ply.beac_light_next_state then
			ply.beac_light_next_state = CurTime()
		end
		
		--Create dynamic light
		local dlight = DynamicLight(ply:EntIndex())
		dlight.r = color.r
		dlight.g = color.g
		dlight.b = color.b
		dlight.brightness = brightness
		dlight.Decay = 1000
		dlight.Size = 200
		dlight.DieTime = CurTime() + 0.1
		dlight.Pos = ply:GetPos() + Vector(0, 0, 35)
	end
	
	hook.Add("Think", "BeaconLightUp", function()
		for _,ply in pairs(player.GetAll()) do
			if IsValid(ply) and ply:IsPlayer() and ply:GetNWBool("IsDetectiveBeacon") then
				BeaconDynamicLight(ply, BEACON.color, 1)
			end
		end
	end)
end