
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <franug_deadgames>

#define PLUGIN_VERSION "6.0.1"

// hud msg color
int iColor[4] =  { 0, 0, 0, 255 };

public Plugin myinfo =
{
	name = "SM Franug Games for dead people - Hud Messages",
	author = "Franc1sco franug",
	description = "",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/franug"
};
	
public void OnPluginStart()
{
	LoadTranslations("deadgames_hudmsg.phrases");
	
	CreateTimer(1.0, Check_Players, _, TIMER_REPEAT);
}

public Action Check_Players(Handle timer)
{
	// preparing the variables
	int team;
	int g_iCtsInDM = 0;
	int g_iTsInDM = 0;
	int g_iCtsInBHOP = 0;
	int g_iTsInBHOP = 0;

	for (int i = 1; i < MaxClients; i++)
  		if (IsClientInGame(i))
  		{
  			team = GetClientTeam(i);
  			
  			if(DeadGames_IsOnDM(i))
  			{
  				if(team == CS_TEAM_CT)g_iCtsInDM++;
  				else if(team == CS_TEAM_T)g_iTsInDM++;
  			}
  			else if(DeadGames_IsOnBhop(i))
  			{
  				if(team == CS_TEAM_CT)g_iCtsInBHOP++;
  				else if(team == CS_TEAM_T)g_iTsInBHOP++;
  			}
  		}
  		
  	
  	// show hud msgs to all if is needed
  	
  	char sBuffer[128];
		
	
	// need 2 loops for apply the translations msg per client :/
	if (g_iTsInBHOP > 0 || g_iCtsInBHOP > 0)
	{
		SetHudTextParamsEx(-1.0, 0.88, 1.0, iColor, iColor, 0, 0.0, 0.0, 0.0);
	
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i))
			{
				Format(sBuffer, sizeof(sBuffer), "%T", "People in BHOP", i, g_iCtsInBHOP, g_iTsInBHOP);
	
				ShowHudText(i, 4, sBuffer);	
			}
	}
	
	if (g_iTsInDM > 0 || g_iCtsInDM > 0)
	{
		SetHudTextParamsEx(-1.0, 0.9, 1.0, iColor, iColor, 0, 0.0, 0.0, 0.0);
	
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i))
			{
				Format(sBuffer, sizeof(sBuffer), "%T", "People in DM", i, g_iCtsInDM, g_iTsInDM);
	
				ShowHudText(i, 5, sBuffer);	
			}
	}
}