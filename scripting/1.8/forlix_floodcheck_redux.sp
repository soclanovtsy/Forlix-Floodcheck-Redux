// Forlix FloodCheck
// http://forlix.org/, df@forlix.org
//
// Copyright (c) 2008-2013 Dominik Friedrichs

//- Includes -//

#include <sdktools>


//- Natives -//

// SourceBans++
native void SBPP_BanPlayer(int iAdmin, int iTarget, int iTime, const char[] sReason);
native void SBPP_ReportPlayer(int iReporter, int iTarget, const char[] sReason);

// Sourcebans 2.X
native void SBBanPlayer(client, target, time, char[] reason);
native void SB_ReportPlayer(int client, int target, const char[] reason);

// BaseComm
native bool BaseComm_IsClientMuted(int client);
native bool BaseComm_SetClientMute(int client, bool muteState);
//native bool BaseComm_IsClientGagged(int client); TODO
//native bool BaseComm_SetClientGag(int client, bool gagState); TODO

// SourceComms
enum bType // Punishments Types
{
	bNot = 0,  // Player chat or voice is not blocked
	bSess,  // ... blocked for player session (until reconnect)
	bTime,  // ... blocked for some time
	bPerm // ... permanently blocked
}

native bType SourceComms_GetClientMuteType(int client);
native bool SourceComms_SetClientMute(int client, bool muteState, int muteLength = -1, bool saveToDB = false, const char[] reason = "Muted through natives");
// native bType SourceComms_GetClientGagType(int client); TODO
// native bool SourceComms_SetClientGag(int client, bool gagState, int gagLength = -1, bool saveToDB = false, const char[] reason = "Gagged through natives"); TODO


//- Defines -//

#define PLUGIN_VERSION "0.1" // TODO: No versioning till the first stable Release

#define VOICE_LOOPBACK_MSG "Voice loopback not allowed!\nYou have been muted."

#define MALFORMED_NAME_MSG "Malformed player name (control chars, zero length, ...)"
#define MALFORMED_MESSAGE_MSG "Malformed message (control chars, zero length, ...)"

#define FLOOD_HARD_MSG "Temporary ban for %s (Hard-flooding)"
#define FLOOD_NAME_MSG "Temporary ban for %s (Name-flooding)"
#define FLOOD_CONNECT_MSG "Too quick successive connection attempts, try again in %s"

#define LOG_MSG_LOOPBACK_MUTE "[Forlix FloodCheck Redux] %L muted for voice loopback"

#define NAME_STR_EMPTY "empty"
#define REASON_STR_EMPTY "Empty reason"

#define HARD_TRACK 16
#define CONNECT_TRACK 16

#define MAX_NAME_LEN 32
#define MAX_MSG_LEN 128
#define MAX_IPPORT_LEN 32
#define MAX_STEAMID_LEN 32

#define REASON_TRUNCATE_LEN 63 // can be max MAX_MSG_LEN-2 // the game now truncates to 63 but only clientside


//- Global Variables -//

bool g_bSourceBans, g_bSourceBansPP, g_bBaseComm, g_bSourceComms;

//- ConVars -//

//- Misc -//
bool g_bExcludeChatTriggers, g_bMuteVoiceLoopback;
//- Chat -//
float g_fChatInterval;
int g_iChatNum;
//- Hard Flood -//
float g_fHardInterval;
int g_iHardNum, g_iHardBanTime;
//- Namecheck -//
float g_fNameInterval;
int g_iNameNum, g_iNameBanTime;
//- Connect Check -//
float g_fConnectInterval;
int g_iConnectNum, g_iConnectBanTime;


public Plugin myinfo = 
{
	name = "Forlix FloodCheck Redux", 
	author = "Playa (Formerly Dominik Friedrichs)", 
	description = "An Universal Anti Spam, Flood and Exploit Solution compactible with most Source Engine Games", 
	version = PLUGIN_VERSION, 
	url = "github.com/DJPlaya/Forlix-Floodcheck-Redux"
}


//- FFCR Modules -// Note that the ordering of these Includes is important

//- ConVars -//
#include "FFCR/convars.sp"
#include "FFCR/markcheats.sp"
#include "FFCR/events.sp"
//- Chat -//
#include "FFCR/chatflood.sp"
//- Hard Flood -//
#include "FFCR/hardflood.sp"
//- Namecheck -//
#include "FFCR/nameflood.sp"
//- Connect Check -//
#include "FFCR/connectflood.sp"
//- Voice Loopback -//
#include "FFCR/voiceloopback.sp"
#include "FFCR/toolfuncs.sp"


//////////////////

static bool late_load;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, err_max)
{
	CreateNative("IsClientFlooding", Native_IsClientFlooding);
	
	late_load = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegPluginLibrary("forlix_floodcheck_redux");
	
	// chat and radio flood checking
	RegConsoleCmd("say", FloodCheckChat);
	RegConsoleCmd("say_team", FloodCheckChat);
	
	HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_changename", Event_PlayerChangename, EventHookMode_Pre);
	
	// game-specific setup
	char gamedir[16];
	GetGameFolderName(gamedir, sizeof(gamedir));
	
	if (StrEqual(gamedir, "cstrike")) // counter-strike: source
		SetupChatDetection_cstrike();
		
	else if (StrEqual(gamedir, "dod")) // day of defeat: source
		SetupChatDetection_dod();
		
	else if (StrEqual(gamedir, "tf")) // team fortress 2
		SetupChatDetection_tf();
		
	else // all other games
		SetupChatDetection_misc();
		
	SetupConVars();
	MarkCheats();
	
	FloodCheckConnect_PluginStart();
	
	if (late_load)
		Query_VoiceLoopback_All();
		
	late_load = false;
}

public void OnPluginEnd()
{
	FloodCheckConnect_PluginEnd();
}

public void OnAllPluginsLoaded()
{
	// Library Checks
	if (LibraryExists("sourcebans++")) // SB++
		g_bSourceBans = true;
		
	else
		g_bSourceBans = false;
		
	if (LibraryExists("sourcebans")) // SB
		g_bSourceBansPP = true;
		
	else
		g_bSourceBansPP = false;
		
	if (g_bSourceBansPP && g_bSourceBans)
		LogError("[Warning] Sourcebans++ and Sourcebans 2.X are installed at the same Time! This can Result in Problems, FFC will only use SB++ for now");
		
	if (LibraryExists("basecomm")) // BaseComm
		g_bBaseComm = true;
		
	else
		g_bBaseComm = false;
		
	if (LibraryExists("sourcecomms++")) // SourceComms
	{
		g_bSourceComms = true;
		
		if(LibraryExists("sourcecomms"))
			LogError("[Warning] SourceComms++ and SourceComms are installed at the same Time! This can Result in Problems.");
	}
	
	else
	{
		if (LibraryExists("sourcecomms"))
			g_bSourceComms = true;
			
		else
			g_bSourceComms = false;
	}
	
}

//g_bSourceBans, g_bSourceBansPP, g_bBaseComm, g_bSourceComms;

public void OnLibraryAdded(const char[] cName)
{
	if (strcmp(cName, "sourcebans", false))
			g_bSourceBansPP = true;
			
	else if (strcmp(cName, "sourcebans++", false))
			g_bSourceBans = true;
			
	else if (strcmp(cName, "basecomm", false))
			g_bBaseComm = true;
			
	else if (strcmp(cName, "sourcecomms", false))
			g_bSourceComms = true;
			
	else if (strcmp(cName, "sourcecomms++", false))
			g_bSourceComms = true;
}

public void OnLibraryRemoved(const char[] cName)
{
	if (strcmp(cName, "sourcebans", false))
			g_bSourceBansPP = false;
			
	else if (strcmp(cName, "sourcebans++", false))
			g_bSourceBans = false;
			
	else if (strcmp(cName, "basecomm", false))
			g_bBaseComm = false;
			
	else if (strcmp(cName, "sourcecomms", false))
			g_bSourceComms = false;
			
	else if (strcmp(cName, "sourcecomms++", false))
			g_bSourceComms = false;
}

public void OnConfigsExecuted()
{
	//Some games support disallowing voice_inputfromfile server side
	ConVar hCVar_VoiceFromFile = FindConVar("sv_allow_voice_from_file");
	if (hCVar_VoiceFromFile)
	{
		SetConVarBool(hCVar_VoiceFromFile, false);
		g_bMuteVoiceLoopback = false;
	}
}

public bool OnClientConnect(client, char[] rejectmsg, maxlen)
{
	if (!IsClientNameAllowed(client))
	{
		strcopy(rejectmsg, maxlen, MALFORMED_NAME_MSG);
		return false;
	}
	
	return true;
}

public OnClientConnected(client)
{
	//- Chat -//
	FloodCheckChat_Connect(client);
	//- Hard Flood -//
	FloodCheckHard_Connect(client);
	//- Namecheck -//
	FloodCheckName_Connect(client);
	
	return;
}

public OnClientSettingsChanged(client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;
		
	Query_VoiceLoopback(client);
	
	if (!IsClientNameAllowed(client))
		KickClient(client, MALFORMED_NAME_MSG);
		
	// make sure client cant hardflood us with settingschanged
	FloodCheckHard(client);
	return;
}

public Action OnClientCommand(client, args)
{
	FloodCheckHard(client);
	return Plugin_Continue;
} 