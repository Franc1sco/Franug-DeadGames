/*  SM Franug Games for dead people
 *
 *  Copyright (C) 2017-2019 Francisco 'Franc1sco' García
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <basecomm>
#undef REQUIRE_PLUGIN
#include <devzones>
#include <myjailbreak>
#include <warden>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "6.1"

bool g_bDeadGame[MAXPLAYERS+1] = {false, ...};
bool g_bDeadGameDM[MAXPLAYERS+1] = {false, ...};
bool g_bDeadGameBhop[MAXPLAYERS+1] = {false, ...};
bool g_bNoWeapons[MAXPLAYERS+1] = {false, ...};
bool g_bClosed = false;
int g_offsCollisionGroup;

int g_iOffset_PlayerResource_Alive = -1;

ConVar cv_MapWithDMZone, cv_useDevZones;

ConVar cv_lr;

public Plugin myinfo =
{
	name = "SM Franug Games for dead people",
	author = "Franc1sco franug",
	description = "",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/franug"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	//Register the plugin library.
	RegPluginLibrary("franug_deadgames");
	
	// the natives for this plugin
	CreateNative("DeadGames_IsOnDM", Native_IsOnDm);
	CreateNative("DeadGames_IsOnBhop", Native_IsOnBhop);
	CreateNative("DeadGames_IsOnGame", Native_IsOnGame);
	
	// compatibility for old 3party plugins
	CreateNative("DM_isdm", Native_IsOnGame);
	CreateNative("DM_isbhop", Native_IsOnBhop);
	
	// optional natives of others plugins
	MarkNativeAsOptional("MyJailbreak_IsEventDayRunning");
	
	return APLRes_Success;
}

public void OnConfigsExecuted()
{
	// use the sm_hosties_lr_ts_max value for check ts alive if the server is a hosties server
	if(cv_lr == null)
		cv_lr = FindConVar("sm_hosties_lr_ts_max");
}

public void BaseComm_OnClientMute(int client, bool muteState)
{
	// keep muted to people on dead game in order dont confuse to alive people
	if(!muteState && g_bDeadGame[client] && !GetAdminFlag(GetUserAdmin(client), Admin_Chat)) 
		SetClientListeningFlags(client, VOICE_MUTED);
}
public Action warden_OnWardenCreate(int client)
{
	// people on dead game will not be a warden
	if (g_bDeadGame[client])
		return Plugin_Handled;
		
	
	return Plugin_Continue;
}

public int Native_IsOnGame(Handle plugin, int argc)
{  
	return g_bDeadGame[GetNativeCell(1)];
}

public int Native_IsOnDm(Handle plugin, int argc)
{  
	return g_bDeadGameDM[GetNativeCell(1)];
}

public int Native_IsOnBhop(Handle plugin, int argc)
{  
	return g_bDeadGameBhop[GetNativeCell(1)];
}

public void OnPluginStart()
{
	LoadTranslations("deadgames.phrases");
	
	CreateConVar("sm_franugdeadgames_version", PLUGIN_VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	cv_MapWithDMZone = CreateConVar("sm_franugdeadgames_mapwithdmzone", "0", "This cvar is used for maps that have a separated dm zone with weapons for dead people.");
	
	cv_useDevZones = CreateConVar("sm_franugdeadgames_usedevzones", "1", "1 = Use devzones for set the spawn points of dm people and the area. 1 = allow people to run freely in the map like redie (if you dont have devzones installed is like have this cvar to 0).");
	
	g_offsCollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	
	// the plugin commands
	RegConsoleCmd("sm_godm", Command_dm);
	RegConsoleCmd("sm_nodm", Command_nodm);
	RegConsoleCmd("sm_gobhop", Command_bhop);
	RegConsoleCmd("sm_nobhop", Command_nobhop);
	
	// plugin events
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_Round_End);
	HookEvent("player_team", Event_Team);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	HookEvent("player_jump", Event_OnPlayerJump);
	
	// offset for alive status
	g_iOffset_PlayerResource_Alive = FindSendPropInfo("CCSPlayerResource", "m_bAlive");
	
	// weapon sounds
	AddTempEntHook("Shotgun Shot", Hook_ShotgunShot);
	
	// player sounds
	AddNormalSoundHook(SoundHook);
	
	// hooks for late load
	for (int i = 1; i < MaxClients; i++)
		if (IsClientInGame(i)) 
			OnClientPutInServer(i);
	
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// block chat commands from people on dead games because if not the alive people will see it
	if(client > 0 && g_bDeadGame[client] && IsPlayerAlive(client))
	{
		PrintToChat(client, " \x04%T", "On a dead game you cant write for prevent to be readed by alive people", client);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void OnPluginEnd()
{
	// kill people on dead games when plugin end
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if(g_bDeadGame[i])
			{
				SafeKill(i);
				
				g_bDeadGame[i] = false;
				g_bDeadGameDM[i] = false;
				g_bDeadGameBhop[i] = false;
				g_bNoWeapons[i] = false;
					
				// unmute people on dead game
				if(!BaseComm_IsClientMuted(i))
					SetClientListeningFlags(i, VOICE_NORMAL);

			}
		}
	}
}

public Action SoundHook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	// no sounds for people on dead games
	if(IsValidClient(entity) && g_bDeadGame[entity]) 
		return Plugin_Stop;
	 
	return Plugin_Continue;
}

public Action Event_Team(Handle event, const char[] name, bool dontBroadcast) 
{
	CheckDeadPeople();
}

public Action Event_OnPlayerJump(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// easy hop for people on bhop dead game
	if (g_bDeadGameBhop[client]) 
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
}

public void OnMapStart()
{
	// used for set dead status on scoreboard
	int entity = FindEntityByClassname(0, "cs_player_manager");
	SDKHook(entity, SDKHook_ThinkPost, OnPlayerManager_ThinkPost);
}

public Action OnPlayerManager_ThinkPost(int entity) 
{
	// people on dead games appear as dead on scoreboard
	for (int i = 1; i < MaxClients; i++)
		if(g_bDeadGame[i])
			SetEntData(entity, (g_iOffset_PlayerResource_Alive+i*4), 0, 1, true);
}

public void OnClientDisconnect(int client)
{
	g_bDeadGame[client] = false;
	g_bDeadGameDM[client] = false;
	g_bDeadGameBhop[client] = false;
	g_bNoWeapons[client] = false;
}

public void OnClientDisconnect_Post(int client)
{
	CheckDeadPeople();
}

public Action Command_nodm(int client, int args)
{
	if(g_bDeadGameDM[client])
	{
		SafeKill(client);
		
		g_bDeadGame[client] = false;
		g_bDeadGameDM[client] = false;

		g_bNoWeapons[client] = false;
		
		if(!BaseComm_IsClientMuted(client))
			SetClientListeningFlags(client, VOICE_NORMAL);
	}
		
	return Plugin_Handled;
}

public Action Command_dm(int client, int args)
{
	// is myjailbreak plugin running and this round is a special day then disable dead games
	if((GetFeatureStatus(FeatureType_Native, "MyJailbreak_IsEventDayRunning") == FeatureStatus_Available) && MyJailbreak_IsEventDayRunning())
		return Plugin_Handled;
		
	// if no dm zone created then return
	if(GetFeatureStatus(FeatureType_Native, "Zone_GetZonePosition") == FeatureStatus_Available && cv_useDevZones.BoolValue)
	{
		float Position[3];
		if(!Zone_GetZonePosition("dmzone", false, Position)) return Plugin_Handled;
	}
		
	if (!g_bClosed && !IsPlayerAlive(client) && !g_bDeadGame[client])
	{
				g_bDeadGameDM[client] = true; 
				g_bDeadGame[client] = true; 
				
				// mute player on dead games zone (admins have inmunity)
				if(!BaseComm_IsClientMuted(client) && !GetAdminFlag(GetUserAdmin(client), Admin_Chat))
					SetClientListeningFlags(client, VOICE_MUTED);
					
				CreateTimer(0.5, Timer_RespawnOnDG, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				PrintToChat(client," \x04%T","Now you go to DM", client);
	}
	else PrintToChat(client," \x04%T", "You cant go to DM now.", client);
		
	return Plugin_Handled;
}

public Action Command_nobhop(int client, int args)
{
	if(g_bDeadGameBhop[client])
	{
		SafeKill(client);
		
		g_bDeadGame[client] = false;
		g_bDeadGameBhop[client] = false;
		g_bNoWeapons[client] = false;
		
		if(!BaseComm_IsClientMuted(client))
			SetClientListeningFlags(client, VOICE_NORMAL);
	}
		
	return Plugin_Handled;
}

public Action Command_bhop(int client,int args)
{
	// is myjailbreak plugin running and this round is a special day then disable dead games
	if((GetFeatureStatus(FeatureType_Native, "MyJailbreak_IsEventDayRunning") == FeatureStatus_Available) && MyJailbreak_IsEventDayRunning())
		return Plugin_Handled;
		
	// if no bhop zone created then return
	if(GetFeatureStatus(FeatureType_Native, "Zone_GetZonePosition") == FeatureStatus_Available && cv_useDevZones.BoolValue)
	{
		float Position[3];
		if(!Zone_GetZonePosition("bhopzone", false, Position)) return Plugin_Handled;
	}
	
	if (!g_bClosed && !IsPlayerAlive(client) && !g_bDeadGame[client])
	{
		g_bDeadGame[client] = true;
		g_bDeadGameBhop[client] = true;
		SDKHook(client, SDKHook_PostThink, Hook_Think);
		SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit); 
		
		if(!BaseComm_IsClientMuted(client) && !GetAdminFlag(GetUserAdmin(client), Admin_Chat))
			SetClientListeningFlags(client, VOICE_MUTED);
		
		CreateTimer(0.5, Timer_RespawnOnDG, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		PrintToChat(client," \x04%T", "Now you go to BHOP", client);
	}
	else PrintToChat(client," \x04%T", "You cant go to BHOP now.", client);
		
	return Plugin_Handled;
}

public Action Event_PlayerDeathPre(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	// hide dead events of people on a dead game
	if(g_bDeadGame[victim])
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
	
}

void CheckDeadPeople()
{
	// count real alive players and kill people on dead games for prevent "no round end" bug
	int iCount_cts = 0;
	int iCount_terrorist = 0;
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{

			if(GetClientTeam(i) == 2 && !g_bDeadGame[i])
				iCount_terrorist++;
			else if(GetClientTeam(i) == 3 && !g_bDeadGame[i])
				iCount_cts++;
		}
	}
	
	// 
	int iMinTerrorists;
	
	if(cv_lr == null)
		iMinTerrorists = 0;
	else
		iMinTerrorists = GetConVarInt(cv_lr);
	
	// if 0 cts alive or 0 ts alive or sm_hosties_lr_ts_max value ts alive (for do !lr if is a jailbreak server) then terminate dead games for all
	if(iCount_terrorist <= iMinTerrorists || iCount_cts == 0)
	{
		g_bClosed = true;
		for (int i = 1; i < MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				if(g_bDeadGame[i])
				{
					SafeKill(i);
					
					g_bDeadGame[i] = false;
					g_bDeadGameDM[i] = false;
					g_bDeadGameBhop[i] = false;
					g_bNoWeapons[i] = false;
					
					if(!BaseComm_IsClientMuted(i))
						SetClientListeningFlags(i, VOICE_NORMAL);

				}
			}
		}
	}
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	// if not dead zones created then dont continue
	if(GetFeatureStatus(FeatureType_Native, "Zone_GetZonePosition") == FeatureStatus_Available && cv_useDevZones.BoolValue)
	{
		float Position[3];
		if(!Zone_GetZonePosition("dmzone", false, Position) && !Zone_GetZonePosition("bhopzone", false, Position)) 
			return Plugin_Continue;
	}
	// respawn on dead zone in X seconds
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_bDeadGame[victim])
	{
		CreateTimer(2.0, Timer_RespawnOnDG, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Continue;
	}
	
	// check again for be sure that no bugs
	CheckDeadPeople();
	
	return Plugin_Continue;
}

public Action Event_Round_End(Handle event, const char[] name, bool dontBroadcast)
{
	// closed dead game and kill people on these zones
	g_bClosed = true;
 	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if(g_bDeadGame[i])
			{
				SafeKill(i);
				g_bDeadGameDM[i] = false;
				g_bDeadGame[i] = false;
				g_bDeadGameBhop[i] = false;
					
				if(!BaseComm_IsClientMuted(i))
					SetClientListeningFlags(i, VOICE_NORMAL);
						
				g_bNoWeapons[i] = false;
					
			}
		}
	}
}

public Action Timer_RespawnOnDG(Handle timer,int userid)
{
	int client = GetClientOfUserId(userid);
	
	if(IsValidClient(client) && (GetClientTeam(client) == 2 || GetClientTeam(client) == 3) && g_bDeadGame[client] && !g_bClosed && !IsPlayerAlive(client))
	{
		// msg depending if is dm zone or bhop zone
		if(!g_bDeadGameBhop[client]) 
			PrintToChat(client," \x04%T", "Type !nodm for exit dm zone and !godm for join again.", client);
		else 
			PrintToChat(client," \x04%T", "Type !nobhop for exit dm zone and !gobhop for join again.", client);
		
		// respawn player
		g_bNoWeapons[client] = false;
		CS_RespawnPlayer(client);
		
		// set noblock
		SetEntData(client, g_offsCollisionGroup, 2, 4, true);
		
		// remove weapons
		StripAllWeapons(client);
		
		// change player color only for bhop people
		if (g_bDeadGameBhop[client])
		{		
			SetEntityRenderMode(client, RENDER_TRANSADD);
			SetEntityRenderColor(client, 0, 255, 0, 120);
		}
		
		float Position[3];
		if(GetClientTeam(client) == CS_TEAM_T)
		{
			// weapons for Ts. Do it configurable in future updates
			if(g_bDeadGameDM[client])
			{
				GivePlayerItem(client, "weapon_ak47");
				GivePlayerItem(client, "weapon_glock");
				GivePlayerItem(client, "weapon_knife");
			}
			
			if(GetFeatureStatus(FeatureType_Native, "Zone_GetZonePosition") == FeatureStatus_Available && cv_useDevZones.BoolValue)
			{
				// teleport player to the dead game zone
				if(g_bDeadGameBhop[client] && Zone_GetZonePosition("bhop1", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
				else if(Zone_GetZonePosition("dm1", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
			
			g_bNoWeapons[client] = true;
		}
		else if(GetClientTeam(client) == CS_TEAM_CT)
		{
			// weapons for CTs. Do it configurable in future updates
			if(g_bDeadGameDM[client])
			{
				GivePlayerItem(client, "weapon_ak47");
				GivePlayerItem(client, "weapon_glock");
				GivePlayerItem(client, "weapon_knife");
			}
			
			if(GetFeatureStatus(FeatureType_Native, "Zone_GetZonePosition") == FeatureStatus_Available && cv_useDevZones.BoolValue)
			{
				// teleport player to the dead game zone
				if(g_bDeadGameBhop[client] && Zone_GetZonePosition("bhop2", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
				else if(Zone_GetZonePosition("dm2", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
			g_bNoWeapons[client] = true;
		}
		
	}
}

stock void StripAllWeapons(int client)
{
	int wepIdx;
	for (int i; i < 5; i++)
	{
		while ((wepIdx = GetPlayerWeaponSlot(client, i)) != -1)
		{
			RemovePlayerItem(client, wepIdx);
			AcceptEntityInput(wepIdx, "Kill");
		}
	}
}

public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	// clear all
	
	g_bClosed = false;

	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if(g_bDeadGame[i])
			{
				g_bDeadGame[i] = false;
				g_bDeadGameDM[i] = false;
				g_bDeadGameBhop[i] = false;
				
				if(!BaseComm_IsClientMuted(i))
					SetClientListeningFlags(i, VOICE_NORMAL);
				
			}
			g_bNoWeapons[i] = false;
		}
	}
}

public int Zone_OnClientLeave(int client, char[] zone)
{
	if(IsValidClient(client) && g_bDeadGame[client] && !g_bClosed && cv_useDevZones.BoolValue)
	{
		// prevent people to go out from dead zone in order to dont bother alive people
		if(g_bDeadGameDM[client] && StrContains(zone, "dmzone", false) == 0)
		{
			
			float Position[3];
			if(GetClientTeam(client) == CS_TEAM_CT)
			{
				if(Zone_GetZonePosition("dm2", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
			else if(GetClientTeam(client) == CS_TEAM_T)
			{
				if(Zone_GetZonePosition("dm1", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
		}
		else if(g_bDeadGameBhop[client] && StrContains(zone, "bhopzone", false) == 0)
		{
			float Position[3];
			if(GetClientTeam(client) == CS_TEAM_CT)
			{
				if(Zone_GetZonePosition("bhop2", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
			else if(GetClientTeam(client) == CS_TEAM_T)
			{
				if(Zone_GetZonePosition("bhop1", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
		}
	}
}

public int Zone_OnClientEntry(int client, char[] zone)
{
	// prevent people to go to a banned zone for "dead players"
	if(IsValidClient(client) && g_bDeadGame[client] && !g_bClosed && cv_useDevZones.BoolValue)
	{
		if(g_bDeadGameDM[client] && StrContains(zone, "nodead", false) == 0)
		{
			float Position[3];
			if(GetClientTeam(client) == CS_TEAM_CT)
			{
				if(Zone_GetZonePosition("dm2", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
			else if(GetClientTeam(client) == CS_TEAM_T)
			{
				if(Zone_GetZonePosition("dm1", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
		}
		else if(g_bDeadGameBhop[client] && StrContains(zone, "nodead", false) == 0)
		{
			float Position[3];
			if(GetClientTeam(client) == CS_TEAM_CT)
			{
				if(Zone_GetZonePosition("bhop2", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
			else if(GetClientTeam(client) == CS_TEAM_T)
			{
				if(Zone_GetZonePosition("bhop1", false, Position)) 
					TeleportEntity(client, Position, NULL_VECTOR, NULL_VECTOR);
			}
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public Action Hook_Think(int client) 
{ 
	// remove onground flag for people on bhop zone in order to silence foopsteps
    if (g_bDeadGameBhop[client]) 
    {
    	if(IsPlayerAlive(client) && GetEntityFlags(client) & FL_ONGROUND)
		{
			int flags = GetEntityFlags(client);
			SetEntityFlags(client, flags&~FL_ONGROUND);
		}
    }
	else SDKUnhook(client, SDKHook_PostThink, Hook_Think); // if he is not on bhop zone then remove hook for optimization
}   

public Action OnTakeDamage(int victim,int &attacker,int &inflictor,float &damage,int &damagetype)
{
	// players on bhop zone cant be damaged
	if(g_bDeadGameBhop[victim]) return Plugin_Handled;
	
	// allow himself damage
	if(!IsValidClient(attacker)) return Plugin_Continue;
	
	// only allow damage if both player are on dead zone or alive
	if(g_bDeadGameDM[victim] != g_bDeadGameDM[attacker])
	{
		if(g_bDeadGameDM[attacker])
		{
			// prevent people on dead games bother to alive people with shots
			CreateTimer(0.1, Timer_KillAnnoyingPeople, GetClientUserId(attacker), TIMER_FLAG_NO_MAPCHANGE);
			
		}
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_KillAnnoyingPeople(Handle timer, int id)
{
	int client = GetClientOfUserId(id);
	
	if (!client || !IsClientInGame(client) || !g_bDeadGameDM[client] || !IsPlayerAlive(client))
		return;
	
	PrintToChat(client, " \x03%T", "Dont bother to the alive people!", client);
	
	SafeKill(client);
}

public Action OnWeaponDrop(int client, int entity)
{
	// remove weapons on drop in order to no spawn weapons to the alive people
    if (!IsClientInGame(client) || !g_bDeadGame[client] || !IsValidEntity(entity) || !IsValidEdict(entity))
        return;

    AcceptEntityInput(entity, "kill");
}

public Action OnWeaponCanUse(int client, int weapon)
{
	// on bhop zone dont allow weapons, or in maps that dont have a zone specially for dm
	if (g_bNoWeapons[client] && (!GetConVarBool(cv_MapWithDMZone) || g_bDeadGameBhop[client])) 
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action Hook_SetTransmit(int entity,int client) 
{ 
	if (entity == client) return Plugin_Continue;
	
	if(!g_bDeadGame[entity])
	{
		SDKUnhook(entity, SDKHook_SetTransmit, Hook_SetTransmit); 
		return Plugin_Continue; 
	}
	
	// if both players not are on the same zone then they cant see to the other
	if (g_bDeadGame[client] != g_bDeadGame[entity]) 
		return Plugin_Handled;
     
	return Plugin_Continue; 
}   

public Action OnPlayerRunCmd(int client,int &buttons,int &impulse, float vel[3], float angles[3],int &weapon)
{
	// prevent people on dead zones use the E button
	if(g_bDeadGame[client])
	{
		if(g_bDeadGameBhop[client] || !GetConVarBool(cv_MapWithDMZone))
			buttons &= ~IN_USE;
	}
	return Plugin_Continue;
}

// this means that no negative score and prevent that sometimes in csgo the forceplayersuicide dont work
public void SafeKill(int client)
{
	if(IsPlayerAlive(client))
	{
		ForcePlayerSuicide(client);
		if(IsPlayerAlive(client)) // double check for csgo
		{
			int team = GetClientTeam(client);
			ChangeClientTeam(client, CS_TEAM_SPECTATOR);
			ChangeClientTeam(client, team);
		}
		
		// prevent negative score
		SetEntProp(client, Prop_Data, "m_iFrags", GetClientFrags(client)+1);
		int olddeaths = GetEntProp(client, Prop_Data, "m_iDeaths");
		SetEntProp(client, Prop_Data, "m_iDeaths", olddeaths-1);
	}
}

public bool IsValidClient( int client ) 
{ 
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) 
        return false; 
     
    return true; 
}

//
// The next code was taken from splewis multi1v1 plugin 
// with small editions to use on this "dead games" plugin
//

public bool CanHear(int shooter, int client) {
    if (!IsValidClient(shooter) || !IsValidClient(client) || shooter == client) {
        return true;
    }

    float pos[3];
    GetClientAbsOrigin(client, pos);

    // Block the transmisson.
    if (g_bDeadGameDM[shooter] != g_bDeadGameDM[client]) {
        return false;
    }

    // Transmit by default.
    return true;
}

public Action Hook_ShotgunShot(const char[] te_name, const int[] players, int numClients, float delay) {

    int shooterIndex = TE_ReadNum("m_iPlayer") + 1;

    // Check which clients need to be excluded.
    int[] newClients = new int[MaxClients];
    int newTotal = 0;

    for (int i = 0; i < numClients; i++) {
        int client = players[i];

        bool rebroadcast = true;
        if (!IsValidClient(client)) {
            rebroadcast = true;
        } else {
            rebroadcast = CanHear(shooterIndex, client);
        }

        if (rebroadcast) {
            // This Client should be able to hear it.
            newClients[newTotal] = client;
            newTotal++;
        }
    }

    // No clients were excluded.
    if (newTotal == numClients) {
        return Plugin_Continue;
    }

    // All clients were excluded and there is no need to broadcast.
    if (newTotal == 0) {
        return Plugin_Stop;
    }

    // Re-broadcast to clients that still need it.
    float vTemp[3];
    TE_Start("Shotgun Shot");
    TE_ReadVector("m_vecOrigin", vTemp);
    TE_WriteVector("m_vecOrigin", vTemp);
    TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
    TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
    TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
    TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
    TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
    TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
    TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
    TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
    TE_Send(newClients, newTotal, delay);

    return Plugin_Stop;
}