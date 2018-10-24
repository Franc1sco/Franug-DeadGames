#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <franug_deadgames>

#pragma newdecls required
#define PLUGIN_VERSION "1.00 (edited for franug deadgames plugin)"

/*
* Plugin Information - Please do not change this
*/
public Plugin myinfo = 
{
  name = "Easy Spawn Protection",
  author = "Invex | Byte, based on work of cREANy0 and Fredd",
  description = "Easy to use spawn protection plugin.",
  version = PLUGIN_VERSION,
  url = "http://www.invexgaming.com.au"
}

bool isEnabled;
bool inRoundStartProtectionTime = false;
float roundStartTime = 0.0;
float freezeTime = 0.0;
char PREFIX[] = "[{purple}EasySpawnProtection{default}] ";
#define MODE_PLAYERSPAWN 0
#define MODE_ROUNDSTART 1
#define COLOUR_OFF 0
#define COLOUR_ALL 1
#define COLOUR_TEAMS 2

//Mod information
#define teamOne 2 //CS:S T, CS:GO T, TF2 RED, L4D survivor
#define teamTwo 3 //CS:S CT, CS:GO CT, TF2 BLU, L4D infected
int teamSpectator;
int teamTeamless;
bool hasTeams = true;


//Handles
Handle g_easysp_enabled = null;
Handle g_easysp_time = null;
Handle g_easysp_mode = null;
Handle g_easysp_endOnAttackMode = null;
Handle g_easysp_notify_start = null;
Handle g_easysp_notify_end = null;
Handle g_easysp_rgbcolour_mode = null;
Handle g_easysp_rgbcolour_all = null;
Handle g_easysp_rgbcolour_teamOne = null;
Handle g_easysp_rgbcolour_teamTwo = null;
Handle g_easysp_sponbotcontrol = null;

//Props
int g_renderOffs = -1;
int g_bIsControllingBot = -1; 

enum FX
{
  FxNone = 0,
  FxPulseFast,
  FxPulseSlowWide,
  FxPulseFastWide,
  FxFadeSlow,
  FxFadeFast,
  FxSolidSlow,
  FxSolidFast,
  FxStrobeSlow,
  FxStrobeFast,
  FxStrobeFaster,
  FxFlickerSlow,
  FxFlickerFast,
  FxNoDissipation,
  FxDistort,               // Distort/scale/translate flicker
  FxHologram,              // kRenderFxDistort + distance fade
  FxExplode,               // Scale up really big!
  FxGlowShell,             // Glowing Shell
  FxClampMinScale,         // Keep this sprite from getting very small (SPRITES only!)
  FxEnvRain,               // for environmental rendermode, make rain
  FxEnvSnow,               //  "        "            "    , make snow
  FxSpotlight,     
  FxRagdoll,
  FxPulseFastWider,
};

enum Render
{
  Normal = 0,     // src
  TransColor,     // c*a+dest*(1-a)
  TransTexture,    // src*a+dest*(1-a)
  Glow,        // src*a+dest -- No Z buffer checks -- Fixed size in screen space
  TransAlpha,      // src*srca+dest*(1-srca)
  TransAdd,      // src*a+dest
  Environmental,    // not drawn, used for environmental effects
  TransAddFrameBlend,  // use a fractional frame value to blend between animation frames
  TransAlphaAdd,    // src + dest*(1-a)
  WorldGlow,      // Same as kRenderGlow but not fixed size in screen space
  None,        // Don't render.
};

public void OnPluginStart()
{
  //Load translation
  LoadTranslations("EasySpawnProtection.phrases");
  
  //ConVar List
  g_easysp_enabled = CreateConVar("sm_easysp_enabled", "1", "Enable Easy Spawn Protection Plugin (0 off, 1 on, def. 1)");
  g_easysp_mode = CreateConVar("sm_easysp_mode", "0", "The mode of operation. (0 spawn protection when player is spawned, 1 spawn protection for set time from round start, def. 0");
  g_easysp_time = CreateConVar("sm_easysp_time", "5.0", "Duration of spawn protection. (min. 0.0, def. 5.0)");
  g_easysp_notify_start = CreateConVar("sm_easysp_notify_start", "1", "Let users know that they have gained spawn protection. (0 off, 1 on, def. 1)");
  g_easysp_notify_end = CreateConVar("sm_easysp_notify_end", "1", "Let users know that they have lost spawn protection. (0 off, 1 on, def. 1)");
  g_easysp_rgbcolour_mode = CreateConVar("sm_easysp_colour_mode", "1", "Colour highlighting mode to use. (0 off, 1 highlight all player same colour, 2 use different colours for teamOne/teamTwo, def. 1)");
  g_easysp_rgbcolour_all = CreateConVar("sm_easysp_colour", "0 255 0 120", "Set spawn protection model highlighting colour. <RED> <GREEN> <BLUE> <OPACITY>. (def. \"0 255 0 120\")");
  g_easysp_rgbcolour_teamOne = CreateConVar("sm_easysp_colour_teamOne", "0 255 0 120", "Set spawn protection model highlighting colour for team One (CS:S T, CS:GO T, TF2 RED, L4D Survivor). <RED> <GREEN> <BLUE> <OPACITY>. (def. \"0 255 0 120\")");
  g_easysp_rgbcolour_teamTwo = CreateConVar("sm_easysp_colour_teamTwo", "0 255 0 120", "Set spawn protection model highlighting colour for team Two (CS:S CT, CS:GO CT, TF2 BLU, L4D Infected). <RED> <GREEN> <BLUE> <OPACITY>. (def. \"0 255 0 120\")");
  g_easysp_endOnAttackMode = CreateConVar("sm_easysp_endonattack_mode", "0", "Specifies if spawn protection should end if player attacks. (0 off, 1 turn off SP as soon as player shots or fire any weapon, def. 0)");
  g_easysp_sponbotcontrol = CreateConVar("sm_easysp_sponbotcontrol", "1", "Should bots receive spawn protection if another player takes control of them. (0 off, 1 on, def. 1)");

  //Event hooks
  HookEvent("player_spawn", Event_OnPlayerSpawn);
  HookEvent("round_prestart", Event_RoundPreStart);
  HookEvent("round_start", Event_RoundStart);
  HookEvent("weapon_fire", Event_WeaponFire);
      
  //Enable status hook
  HookConVarChange(g_easysp_enabled, ConVarChange_enabled);

  //Find some props
  g_renderOffs          = FindSendPropInfo("CBasePlayer", "m_clrRender");
  g_bIsControllingBot = FindSendPropInfo("CCSPlayer", "m_bIsControllingBot");
  
  //Detect mod
  char modName[21];
  GetGameFolderName(modName, sizeof(modName));
  
  if(StrEqual(modName, "cstrike", false) || StrEqual(modName, "dod", false) || StrEqual(modName, "csgo", false) || StrEqual(modName, "tf", false)) {
    teamSpectator = 1;
    teamTeamless = 0;
    hasTeams = true;
  }
  else if(StrEqual(modName, "Insurgency", false)) {
    teamSpectator = 3;
    teamTeamless = 0;
    hasTeams = true;
  }
  else if(StrEqual(modName, "hl2mp", false)) {
    hasTeams = false;
  }
  else {
    SetFailState("%s is an unsupported mod", modName);
  }
  
  //Set Variable Values
  isEnabled = true;
  
  //AutoExecConfig
  AutoExecConfig(true, "easyspawnprotection");
}

/*
* If enable convar is changed, use this to turn the plugin off or on
*/
public void ConVarChange_enabled(Handle convar, const char[] oldValue, const char[] newValue)
{
  isEnabled = view_as<bool>(StringToInt(newValue));
}

/*
* Round Pre Start
* We need this to set round start time before player spawns
*/
public Action Event_RoundPreStart(Handle event, const char[] name, bool dontBroadcast)
{
  if (!isEnabled)
    return Plugin_Continue;
  
  //Record round start time
  roundStartTime = GetGameTime();
  
  //Get MP freeze time
  Handle mp_freezetime = FindConVar("mp_freezetime");
  if (mp_freezetime != null) {
    freezeTime = GetConVarFloat(mp_freezetime);
  }
  
  return Plugin_Continue;
}

/*
* Round Start
*/
public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
  if (!isEnabled)
    return Plugin_Continue;

  //Check if mode is correct, otherwise return
  if (GetConVarInt(g_easysp_mode) != MODE_ROUNDSTART)
    return Plugin_Continue;
  
  //Mode is fixed time mode, give sp to all players
  int iMaxClients = GetMaxClients();
  float sptime = GetConVarFloat(g_easysp_time);
  
  for (int i = 1; i <= iMaxClients; ++i)
  {
    //Ignore players not here or dead players
    if(!IsClientInGame(i) || !IsPlayerAlive(i))
      continue;
    
    //If client is on spectator or is teamless, ignore them
    int iTeam  = GetClientTeam(i);
    if (hasTeams && (iTeam == teamSpectator || iTeam == teamTeamless))
      continue;
    
    //Set spawn protection
    GiveSpawnProtection(i);
    
    //Check if we should notify player of spawn protection
    if(GetConVarBool(g_easysp_notify_start))
      CPrintToChat(i, "%s%t", PREFIX, "Spawn Protection Start", RoundToNearest(sptime));
  }
  
  //Now we must set up a timer to globally disable spawn protection for all
  CreateTimer(sptime + freezeTime, RemoveAllProtection);
  inRoundStartProtectionTime = true;

  return Plugin_Continue;
}

/*
* OnPlayerSpawn
*/

public Action Event_OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
  if (!isEnabled)
    return Plugin_Continue;
  
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  int clientTeam  = GetClientTeam(client);

  //Ignore dead players
  if(!IsPlayerAlive(client))
    return Plugin_Continue;

  //If player controlling a bot and we do not want sp on bot control, then return
  if (!GetConVarBool(g_easysp_sponbotcontrol) && IsPlayerControllingBot(client))
    return Plugin_Continue;
    
  //If client is on spectator or is teamless, ignore them
  if (hasTeams && (clientTeam == teamSpectator || clientTeam == teamTeamless))
    return Plugin_Continue;
  
  if(!DeadGames_IsOnDM(client) || DeadGames_IsOnBhop(client))
  	return Plugin_Continue;
  	
  //Check if mode is correct, otherwise return
  //However, if still in spawn protection time, allow spawn protecting this client
  if (!inRoundStartProtectionTime && GetConVarInt(g_easysp_mode) != MODE_PLAYERSPAWN)
    return Plugin_Continue;
  
  //Set spawn protection
  GiveSpawnProtection(client);
  
  //Check if we should notify player of spawn protection
  if(GetConVarBool(g_easysp_notify_start)) {
    float sptime = GetConVarFloat(g_easysp_time);
    
    if (inRoundStartProtectionTime && GetConVarInt(g_easysp_mode) != MODE_PLAYERSPAWN)
      CPrintToChat(client, "%s%t", PREFIX, "Spawn Protection Start", RoundToNearest(sptime - (GetGameTime() - roundStartTime) + freezeTime));
    else
     CPrintToChat(client, "%s%t", PREFIX, "Spawn Protection Start", RoundToNearest(sptime));
  }
  
  return Plugin_Continue;
}

/*
* Give spawn protection to given player and colours them
*/
void GiveSpawnProtection(int client) 
{
  //Get Colour Highlight information
  int colourMode = GetConVarInt(g_easysp_rgbcolour_mode);
  int clientTeam  = GetClientTeam(client);
  
  if(!DeadGames_IsOnDM(client) || DeadGames_IsOnBhop(client))
  	return;
  	
  if (colourMode != COLOUR_OFF) {
    //We need to apply colour
    char SzColor[32];
    char Colours[4][4];
      
    if (colourMode == COLOUR_ALL) {
      //Use one colour for all
      GetConVarString(g_easysp_rgbcolour_all, SzColor, sizeof(SzColor));
    }
    else if (colourMode == COLOUR_TEAMS) {
      //Different colour for team one and team two
      if (clientTeam == teamOne) {
        GetConVarString(g_easysp_rgbcolour_teamOne, SzColor, sizeof(SzColor));
      }
      else if (clientTeam == teamTwo) {
        GetConVarString(g_easysp_rgbcolour_teamTwo, SzColor, sizeof(SzColor));
      }
    }
    
    //Set Colour
    ExplodeString(SzColor, " ", Colours, 4, 4);
    set_rendering(client, view_as<FX>(FxDistort), StringToInt(Colours[0]),StringToInt(Colours[1]),StringToInt(Colours[2]), view_as<Render>(RENDER_TRANSADD), StringToInt(Colours[3]));
  }
    
  //Set god mode to player
  SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
  
  //Organise time to reset the god mode
  float sptime = GetConVarFloat(g_easysp_time);
  
  //Set a timer to reset spawn protection only if this is player spawn mode
  if (GetConVarInt(g_easysp_mode) == MODE_PLAYERSPAWN) {
    //Check if freeze time will affect this respawn
    float extraTime = 0.0;
    
    //If this spawn is occuring during spawn time
    if (freezeTime > 0.0 && (GetGameTime() - roundStartTime <= freezeTime)) {
      extraTime = freezeTime - (GetGameTime() - roundStartTime);
    }
    
    CreateTimer(sptime + extraTime, RemoveProtection, client); 
  }
}

/*
* Timer used to remove protection
*/
public Action RemoveProtection(Handle timer, any client)
{
  //Check if this player currently has god mode (aka spawn protection) 
  if(IsClientInGame(client) && IsClientSpawnProtected(client)) {
    SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
    set_rendering(client); //reset rendering

    if(GetConVarBool(g_easysp_notify_end) && IsPlayerAlive(client))
      CPrintToChat(client, "%s%t", PREFIX, "Spawn Protection End Normal");
  }
}

/*
* Timer used to remove protection from all players
*/
public Action RemoveAllProtection(Handle timer)
{
  inRoundStartProtectionTime = false;
  
  int iMaxClients = GetMaxClients();

  for (int i = 1; i <= iMaxClients; ++i)
  {
    //Check if this player currently has god mode (aka spawn protection)
    if(IsClientInGame(i) && IsClientSpawnProtected(i)) {
      SetEntProp(i, Prop_Data, "m_takedamage", 2, 1);
      set_rendering(i); //reset rendering

      if(GetConVarBool(g_easysp_notify_end) && IsPlayerAlive(i))
        CPrintToChat(i, "%s%t", PREFIX, "Spawn Protection End Normal");
    }
  }
}

/*
* Weapon Fire
*/
public Action Event_WeaponFire(Handle event, const char[] name, bool dontBroadcast)
{
  if (!isEnabled)
    return Plugin_Continue;
  
  //Return if option is disabled
  if (!GetConVarBool(g_easysp_endOnAttackMode))
    return Plugin_Continue;
  
  //Get client who fired
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  
  if(!DeadGames_IsOnDM(client))
  	return Plugin_Continue;
  	
  //Check if this player currently has god mode (aka spawn protection)
  if (IsClientSpawnProtected(client)) {
    SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
    set_rendering(client); //reset rendering
    
    if(GetConVarBool(g_easysp_notify_end) && IsPlayerAlive(client))
      CPrintToChat(client, "%s%t", PREFIX, "Spawn Protection End Attack");
  }
    
  return Plugin_Continue;
}

/*
* Function to set player rendering (colour highlighting)
*/
stock void set_rendering(int index, FX fx=FxNone, int r=255, int g=255, int b=255, Render render=Normal, int amount=255)
{
  SetEntProp(index, Prop_Send, "m_nRenderFX", fx, 1);
  SetEntProp(index, Prop_Send, "m_nRenderMode", render, 1);  
  SetEntData(index, g_renderOffs, r, 1, true);
  SetEntData(index, g_renderOffs + 1, g, 1, true);
  SetEntData(index, g_renderOffs + 2, b, 1, true);
  SetEntData(index, g_renderOffs + 3, amount, 1, true);  
}

/* 
* Check if a player is controlling a bot
* Credit: TnTSCS
* Url: https://forums.alliedmods.net/showthread.php?t=188807&page=13
*/
bool IsPlayerControllingBot(int client) 
{ 
  return view_as<bool>(GetEntData(client, g_bIsControllingBot, 1));  
}

/*
* Public function to check if player has spawn protection
*/
public bool IsClientSpawnProtected(int client)
{
  return (GetEntProp(client, Prop_Data, "m_takedamage") == 0);
}