#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>
#include <lilac>
#include <lilac_sourcetv>

#define CVAR_ENABLE			   0
#define CVAR_STV_JOIN		   1
#define CVAR_LOG			   2
#define CVAR_RATE			   3
#define CVAR_DETECTIONS		   4
#define CVAR_NOTIFY			   5
#define CVAR_DEMO_DIR		   6
#define CVAR_LOG_DIR		   7
#define CVAR_MAX			   8

// Notification flag bits for granular control
#define NOTIFY_DETECTION	   (1 << 0)																									  // 1 - Show detection notifications
#define NOTIFY_RECORDING_START (1 << 1)																									  // 2 - Show recording start notifications
#define NOTIFY_RECORDING_STOP  (1 << 2)																									  // 4 - Show recording stop notifications
#define NOTIFY_RECORDING_END   (1 << 3)																									  // 8 - Show recording end notifications (disconnect, etc.)
#define NOTIFY_BAN			   (1 << 4)																									  // 16 - Show ban notifications
#define NOTIFY_ALL			   (NOTIFY_DETECTION | NOTIFY_RECORDING_START | NOTIFY_RECORDING_STOP | NOTIFY_RECORDING_END | NOTIFY_BAN)	  // 31 - All notifications

// Enum for administrator notification types
enum LilacNotifyType
{
	LilacNotify_Detection,
	LilacNotify_RecordingStart,
	LilacNotify_RecordingStop,
	LilacNotify_RecordingEnd,
	LilacNotify_Ban
}

ConVar		  g_hCvar[CVAR_MAX];
ConVar        g_hTvEnable;
ConVar        g_hTvAutoRecord;

int			  g_iPlayerDetections[MAXPLAYERS + 1][CHEAT_MAX];  // Use CHEAT_MAX from lilac.inc
bool		  g_bPlayerRecording[MAXPLAYERS + 1];

bool		  g_bStvRestartedMap	  = false;
bool		  g_bStvRecording		  = false;
int			  g_iRecordedPlayersCount = 0;	  // Cache for performance

char		  g_sDemoDir[PLATFORM_MAX_PATH];
char		  g_sLogDir[PLATFORM_MAX_PATH];
char		  g_sCurrentDemo[PLATFORM_MAX_PATH];
int			  g_iRecordingStartTime;
int			  g_iGlobalRecordingTimestamp = 0;	  // Global timestamp for current recording session

// Forward handles
GlobalForward g_hOnRecordingStarted;
GlobalForward g_hOnRecordingStopped;
GlobalForward g_hOnPlayerLogCreated;
GlobalForward g_hOnPlayerBanned;

public Plugin myinfo =
{
	name		= "[Lilac] Auto SourceTV Recorder",
	author		= "J_Tanzanite, lechuga",
	description = "Automatically records SourceTV demos upon cheater detection.",
	version		= "2.0.0",
	url			= ""
};

public void OnPluginStart()
{
	// Load translations
	LoadTranslations("lilac_sourcetv.phrases");

	ConVar hTempCvar;

	// Create ConVars with English descriptions (ConVars should not be translated)
	g_hCvar[CVAR_ENABLE]	 = CreateConVar("lilac_stv_enable", "1", "Enable SourceTV auto recording.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar[CVAR_STV_JOIN]	 = CreateConVar("lilac_stv_autojoin", "0", "Automatically restart map if SourceTV bot hasn't joined.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar[CVAR_LOG]		 = CreateConVar("lilac_stv_log", "1", "Enable KeyValues logging to demo directory.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar[CVAR_RATE]		 = CreateConVar("lilac_stv_tickrate", "1", "Automatically set SourceTV demo tickrate to the highest value possible for best quality recordings.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar[CVAR_DETECTIONS] = CreateConVar("lilac_stv_detections", "2", "Number of detections required before starting SourceTV recording.", FCVAR_NONE, true, 1.0, true, 10.0);
	g_hCvar[CVAR_NOTIFY]	 = CreateConVar("lilac_stv_notify", "14", "Administrator notification flags (bit field): 1=Detection, 2=RecStart, 4=RecStop, 8=RecEnd, 16=Ban, 31=All", FCVAR_NONE, true, 0.0, true, 31.0);
	g_hCvar[CVAR_DEMO_DIR] = CreateConVar("lilac_stv_demo_path", "logs/lilac_demo", "Directory relative to the SourceMod root where SourceTV demos are stored.", FCVAR_NONE);
	g_hCvar[CVAR_LOG_DIR] = CreateConVar("lilac_stv_log_path", "logs/lilac_demo", "Directory relative to the SourceMod root where KeyValues logs are stored.", FCVAR_NONE);
	HookConVarChange(g_hCvar[CVAR_ENABLE], OnPluginCvarChanged);
	HookConVarChange(g_hCvar[CVAR_RATE], OnPluginCvarChanged);
	HookConVarChange(g_hCvar[CVAR_DEMO_DIR], OnPluginCvarChanged);
	HookConVarChange(g_hCvar[CVAR_LOG_DIR], OnPluginCvarChanged);

	AutoExecConfig(false, "lilac_sourcetv", "sourcemod");

	// Create forwards
	g_hOnRecordingStarted = CreateGlobalForward("LilacSTV_OnRecordingStarted", ET_Ignore, Param_Cell, Param_String, Param_String, Param_Cell);
	g_hOnRecordingStopped = CreateGlobalForward("LilacSTV_OnRecordingStopped", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnPlayerLogCreated = CreateGlobalForward("LilacSTV_OnPlayerLogCreated", ET_Ignore, Param_Cell, Param_String, Param_String, Param_Cell);
	g_hOnPlayerBanned	  = CreateGlobalForward("LilacSTV_OnPlayerBanned", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_String);

	RegAdminCmd("sm_lilac_notify", Command_LilacNotify, ADMFLAG_GENERIC, "Show current notification settings for Lilac SourceTV");
	RegAdminCmd("sm_lilac_notify_toggle", Command_LilacNotifyToggle, ADMFLAG_GENERIC, "Toggle specific notification types for Lilac SourceTV");

	// SourceTV must be enabled.
	if ((hTempCvar = FindConVar("tv_enable")) == null)
	{
		SetFailState("ConVar \"tv_enable\" not found!");
	}
	else {
		g_hTvEnable = hTempCvar;
		SetConVarInt(g_hTvEnable, 1, false, false);
		HookConVarChange(g_hTvEnable, OnSourceTVCvarChanged);
	}

	// Block auto-recording.
	if ((hTempCvar = FindConVar("tv_autorecord")) == null)
	{
		SetFailState("ConVar \"tv_autorecord\" not found!");
	}
	else {
		g_hTvAutoRecord = hTempCvar;

		if (GetConVarInt(g_hTvAutoRecord))
			StopRecording(StopReason_Startup);

		SetConVarInt(g_hTvAutoRecord, 0, false, false);
		HookConVarChange(g_hTvAutoRecord, OnSourceTVCvarChanged);
	}

	ApplyPluginEnabledState();

	g_bStvRestartedMap = false;

	RefreshRecordingDirectories();
}

public void OnPluginEnd()
{
	StopRecordingLog(StopReason_PluginEnd);
	StopRecording(StopReason_PluginEnd);
}

public void OnMapStart()
{
	// Reset all player upon a new map start.
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bPlayerRecording[i] = false;

		for (int k = 0; k < CHEAT_MAX; k++)
			g_iPlayerDetections[i][k] = 0;
	}

	// Reset recording cache
	g_iRecordedPlayersCount = 0;

	if (g_bStvRestartedMap == false)
		CreateTimer(10.0, timer_restart_map);

	// Not needed, but just in case.
	StopRecording(StopReason_MapStart);
}

public void OnMapEnd()
{
	StopRecordingLog(StopReason_MapEnd);
	StopRecording(StopReason_MapEnd);
}

public void OnPluginCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_hCvar[CVAR_ENABLE])
	{
		ApplyPluginEnabledState();
		return;
	}

	if (convar == g_hCvar[CVAR_RATE])
		ApplySnapshotRatePolicy();
	else if (convar == g_hCvar[CVAR_DEMO_DIR] || convar == g_hCvar[CVAR_LOG_DIR])
		RefreshRecordingDirectories();
}

public void OnSourceTVCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue)
		return;

	if (convar == g_hTvEnable)
	{
		if (StringToInt(newValue, 10) >= 1)
			return;

		SetConVarInt(g_hTvEnable, 1, false, false);
	}
	else {
		if (StringToInt(newValue, 10) == 0)
			return;

		SetConVarInt(g_hTvAutoRecord, 0, false, false);
	}
}

void ApplyPluginEnabledState()
{
	if (g_hTvEnable == null || g_hTvAutoRecord == null)
		return;

	if (g_hCvar[CVAR_ENABLE].BoolValue)
	{
		if (!g_hTvEnable.BoolValue)
			SetConVarInt(g_hTvEnable, 1, false, false);

		if (g_hTvAutoRecord.BoolValue)
			SetConVarInt(g_hTvAutoRecord, 0, false, false);

		ApplySnapshotRatePolicy();
		return;
	}

	if (g_bStvRecording)
	{
		StopRecordingLog(StopReason_PluginEnd);
		StopRecording(StopReason_PluginEnd);
	}
}

void ApplySnapshotRatePolicy()
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue || !g_hCvar[CVAR_RATE].BoolValue)
		return;

	ServerCommand("tv_snapshotrate %d", RoundToCeil(1.0 / GetTickInterval()));
}

void ResolveRecordingDirectory(ConVar convar, const char[] fallbackPath, char[] outputPath, int maxLength)
{
	char relativePath[PLATFORM_MAX_PATH];
	convar.GetString(relativePath, sizeof(relativePath));
	TrimString(relativePath);
	ReplaceString(relativePath, sizeof(relativePath), "\\", "/");

	if (relativePath[0] == '\0')
		strcopy(relativePath, sizeof(relativePath), fallbackPath);

	int length = strlen(relativePath);
	while (length > 0 && (relativePath[length - 1] == '/' || relativePath[length - 1] == '\\'))
	{
		relativePath[--length] = '\0';
	}

	BuildPath(Path_SM, outputPath, maxLength, "%s", relativePath);
	if (!DirExists(outputPath))
		CreateDirectory(outputPath, 511);
}

void RefreshRecordingDirectories()
{
	ResolveRecordingDirectory(g_hCvar[CVAR_DEMO_DIR], "logs/lilac_demo", g_sDemoDir, sizeof(g_sDemoDir));
	ResolveRecordingDirectory(g_hCvar[CVAR_LOG_DIR], "logs/lilac_demo", g_sLogDir, sizeof(g_sLogDir));
}

void BuildPlayerLogPath(const char[] steamId64, char[] path, int maxLength)
{
	Format(path, maxLength, "%s/%s.cfg", g_sLogDir, steamId64);
}

public void OnClientConnected(int client)
{
	for (int i = 0; i < CHEAT_MAX; i++)
		g_iPlayerDetections[client][i] = 0;

	g_bPlayerRecording[client] = false;
}

public void OnClientDisconnect(int client)
{
	// If the player was being recorded, update their KeyValues log with disconnect reason
	if (g_bPlayerRecording[client])
	{
		UpdatePlayerKeyValuesLogWithRecordingEnd(client, "disconnect");

		// Notify administrators about player disconnection during recording
		NotifyAdministrators(LilacNotify_RecordingEnd, client, "disconnect");
	}

	// Update cache when player was being recorded
	if (g_bPlayerRecording[client] && g_iRecordedPlayersCount > 0)
		g_iRecordedPlayersCount--;

	// Don't stop recording when a player disconnects - keep evidence
	// Only reset their recording status but don't call UpdateRecordingList
	g_bPlayerRecording[client] = false;

	if (g_iRecordedPlayersCount == 0 && g_bStvRecording)
	{
		StopRecordingLog(StopReason_Disconnect);
		StopRecording(StopReason_Disconnect);
	}

	// Reset detection counters for the disconnected player
	for (int i = 0; i < CHEAT_MAX; i++)
		g_iPlayerDetections[client][i] = 0;
}

bool IsSupportedRecordingCheat(int cheat)
{
	return cheat == CHEAT_AIMBOT || cheat == CHEAT_AIMLOCK;
}

public void lilac_cheater_detected(int client, int cheat)
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue || !IsPlayerValid(client) || !IsSupportedRecordingCheat(cheat))
		return;

	switch (cheat)
	{
		case CHEAT_AIMBOT:
		{
			CreateTimer(610.0, timer_decrement_detection, GetClientUserId(client) | (CHEAT_AIMBOT << 16));

			if (++g_iPlayerDetections[client][CHEAT_AIMBOT] < g_hCvar[CVAR_DETECTIONS].IntValue)
			{
				// Log detection but don't start recording yet
				LogClientDetection(client, cheat);
				return;
			}
		}
		case CHEAT_AIMLOCK:
		{
			CreateTimer(610.0, timer_decrement_detection, GetClientUserId(client) | (CHEAT_AIMLOCK << 16));

			if (++g_iPlayerDetections[client][CHEAT_AIMLOCK] < g_hCvar[CVAR_DETECTIONS].IntValue)
			{
				// Log detection but don't start recording yet
				LogClientDetection(client, cheat);
				return;
			}
		}
	}

	// Log the final detection that triggers recording
	LogClientDetection(client, cheat);

	UpdateRecordingList(client, true);
	return;
}

public void lilac_cheater_banned(int client, int cheat)
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue || !IsPlayerValid(client) || !IsSupportedRecordingCheat(cheat))
		return;

	// Update KeyValues log with ban information
	UpdatePlayerKeyValuesLogWithBan(client, cheat);

	char sReason[32];
	GetTranslatedCheatName(cheat, sReason, sizeof(sReason));

	// Notify administrators about the ban
	NotifyAdministrators(LilacNotify_Ban, client, sReason);
}

bool TriggerTestDetection(int client, int cheat)
{
	if (!IsPlayerValid(client) || !IsSupportedRecordingCheat(cheat))
		return false;

	lilac_cheater_detected(client, cheat);
	return true;
}

bool TriggerTestBan(int client, int cheat)
{
	if (!IsPlayerValid(client) || !IsSupportedRecordingCheat(cheat))
		return false;

	lilac_cheater_banned(client, cheat);
	return true;
}

bool SetPlayerRecordingState(int client, bool status)
{
	bool previousStatus = g_bPlayerRecording[client];
	if (previousStatus == status)
		return previousStatus;

	if (status)
		g_iRecordedPlayersCount++;
	else if (g_iRecordedPlayersCount > 0)
		g_iRecordedPlayersCount--;

	g_bPlayerRecording[client] = status;
	return previousStatus;
}

void TryStopRecordingWhenEmpty()
{
	if (g_iRecordedPlayersCount != 0 || !g_bStvRecording)
		return;

	StopRecordingLog(StopReason_NoPlayers);
	StopRecording(StopReason_NoPlayers);
}

int GetPrimaryRecordedCheatType(int client)
{
	if (g_iPlayerDetections[client][CHEAT_AIMLOCK] >= g_hCvar[CVAR_DETECTIONS].IntValue)
		return CHEAT_AIMLOCK;

	return CHEAT_AIMBOT;
}

void StartRecordingForClient(int client)
{
	char sSteamID64[64];
	char sDemoName[128];
	char sCheatName[32];
	int timestamp = GetTime();
	int cheatType;

	GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64));
	g_iRecordingStartTime = timestamp;

	Format(sDemoName, sizeof(sDemoName), "%s_%d.dem", sSteamID64, timestamp);
	strcopy(g_sCurrentDemo, sizeof(g_sCurrentDemo), sDemoName);

	ServerCommand("tv_record \"%s/%s\"", g_sDemoDir, sDemoName);
	g_bStvRecording = true;
	g_iGlobalRecordingTimestamp = timestamp;

	CreatePlayerKeyValuesLog(client, timestamp);

	cheatType = GetPrimaryRecordedCheatType(client);

	Call_StartForward(g_hOnRecordingStarted);
	Call_PushCell(client);
	Call_PushString(sDemoName);
	Call_PushString(sSteamID64);
	Call_PushCell(cheatType);
	Call_Finish();

	GetTranslatedCheatName(cheatType, sCheatName, sizeof(sCheatName));
	NotifyAdministrators(LilacNotify_RecordingStart, client, sCheatName);
}

/**
 * Updates the recording list for a specific client.
 * Manages the start and stop of SourceTV recording based on active flagged players.
 *
 * @param client		Client index of the player.
 * @param status		Recording status (true = add to list, false = remove from list).
 * @noreturn
 */
void UpdateRecordingList(int client, bool status)
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue)
		return;

	bool previousStatus = SetPlayerRecordingState(client, status);

	if (status && !previousStatus && g_bStvRecording)
		CreatePlayerKeyValuesLog(client, g_iGlobalRecordingTimestamp);

	// We literally cannot record atm...
	if (GetSourceTVBot() == -1)
		return;

	TryStopRecordingWhenEmpty();

	if (!g_bStvRecording && g_iRecordedPlayersCount > 0)
		StartRecordingForClient(client);
}

/**
 * Stops SourceTV recording and logs the end reason to player KeyValues files.
 * Updates all recorded players' KeyValues logs with recording termination information.
 *
 * @param reason		Reason for stopping recording (StopRecordingReason enum).
 * @noreturn
 */
void StopRecordingLog(StopRecordingReason reason = StopReason_Timeout)
{
	if (!g_hCvar[CVAR_LOG].BoolValue || !g_hCvar[CVAR_ENABLE].BoolValue || !g_bStvRecording)
		return;

	char sReasonStr[32];
	GetStopReasonString(reason, sReasonStr, sizeof(sReasonStr));

	// Update KeyValues logs for all players who were being recorded
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bPlayerRecording[i] && IsPlayerValid(i))
		{
			UpdatePlayerKeyValuesLogWithRecordingEnd(i, sReasonStr);
		}
	}

	// Notify administrators about recording stop
	NotifyAdministrators(LilacNotify_RecordingStop, -1, sReasonStr);

	// Note: Recording end details are now only logged to individual player KeyValues files
}

/**
 * Stops SourceTV recording by sending server command.
 * Note: StopRecordingLog() should be called first if you want to log the end of recording.
 *
 * @param reason		Reason for stopping recording (StopRecordingReason enum).
 * @noreturn
 */
void StopRecording(StopRecordingReason reason = StopReason_Timeout)
{
	if (g_bStvRecording)
	{
		// Calculate recording duration
		int duration = (g_iRecordingStartTime > 0) ? (GetTime() - g_iRecordingStartTime) : 0;

		// Call forward to notify other plugins
		Call_StartForward(g_hOnRecordingStopped);
		Call_PushCell(reason);
		Call_PushCell(duration);
		Call_Finish();
	}

	ServerCommand("tv_stoprecord");
	g_bStvRecording				= false;
	g_sCurrentDemo[0]			= '\0';
	g_iRecordingStartTime		= 0;
	g_iGlobalRecordingTimestamp = 0;	// Reset global timestamp
}

/**
 * Gets the client index of the SourceTV bot if available.
 * Uses a static cache to avoid repeated searches.
 *
 * @return				Client index of SourceTV bot, or -1 if not found.
 */
int GetSourceTVBot()
{
	static int bot = -1;

	if (bot != -1)
	{
		// Check if this index is still valid.
		if (IsPlayerValid(bot) && IsClientSourceTV(bot))
			return bot;

		bot = -1;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsPlayerValid(i) || !IsClientSourceTV(i))
			continue;

		bot = i;
		return bot;
	}

	return -1;
}

public Action timer_restart_map(Handle timer)
{
	char mapname[256];

	if (!g_hCvar[CVAR_ENABLE].BoolValue || !g_hCvar[CVAR_STV_JOIN].BoolValue)
		return Plugin_Continue;

	// Server may JUST have installed this plugin while players
	// 	are on the server.
	// 	Don't restart the map while there are players.
	if (GetGameTime() > 60.0)
	{
		int players = 0;

		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsPlayerValid(i) || IsFakeClient(i))
				continue;

			players++;
		}

		// Try again in 30 seconds.
		if (players > 2 && g_bStvRestartedMap == false)
		{
			CreateTimer(30.0, timer_restart_map);

			return Plugin_Continue;
		}
	}

	// Map has already been restarted once, don't do it again.
	if (g_bStvRestartedMap == true)
		return Plugin_Continue;

	// Prevent constant map restarts.
	g_bStvRestartedMap = true;

	// Bot already in-game.
	if (GetSourceTVBot() != -1)
		return Plugin_Continue;

	GetCurrentMap(mapname, sizeof(mapname));
	ServerCommand("changelevel \"%s\"", mapname);

	return Plugin_Continue;
}

public Action timer_decrement_detection(Handle timer, int data)
{
	int client		  = GetClientOfUserId(data & 0xFFFF);
	int detectionType = (data >> 16) & 0xFF;

	if (!IsPlayerValid(client) || detectionType >= CHEAT_MAX)
		return Plugin_Continue;

	if (g_iPlayerDetections[client][detectionType] > 0)
		g_iPlayerDetections[client][detectionType]--;

	// Check if we should stop recording for this client
	if (g_iPlayerDetections[client][detectionType] == 0 && !HasActiveRecordingDetections(client))
		UpdateRecordingList(client, false);

	return Plugin_Continue;
}

// Optimized cheat detection strings
static const char g_sCheatNames[][] = {
	"AIMBOT",
	"AIMLOCK",
	"UNKNOWN"
};

/**
 * Logs detailed information about a cheat detection.
 * Only prints to server console, actual KeyValues file creation happens when recording starts.
 *
 * @param client		Client index of the player who was detected cheating.
 * @param cheat			Type of cheat detected (CHEAT_AIMBOT, CHEAT_AIMLOCK, etc.).
 * @noreturn
 */
void LogClientDetection(int client, int cheat)
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue)
		return;

	// Get cheat reason using optimized lookup
	int cheatIndex;
	switch (cheat)
	{
		case CHEAT_AIMBOT: cheatIndex = 0;
		case CHEAT_AIMLOCK: cheatIndex = 1;
		default: cheatIndex = 2;
	}

	// Notify administrators about the detection
	NotifyAdministrators(LilacNotify_Detection, client, g_sCheatNames[cheatIndex]);
}

/**
 * Gets client information in a single optimized call for Lilac logging.
 * Reduces redundant API calls by getting all needed info at once.
 *
 * @param client		Client index.
 * @param steamid64		Buffer for SteamID64.
 * @param steamid2		Buffer for SteamID2.
 * @param nickname		Buffer for nickname.
 * @param nicknameEscaped Buffer for escaped nickname.
 * @return				True if all information was retrieved successfully.
 */
bool GetLilacClientInfo(int client, char[] steamid64, char[] steamid2, char[] nickname, char[] nicknameEscaped)
{
	if (!GetClientAuthId(client, AuthId_SteamID64, steamid64, 64))
	{
		Format(steamid64, 64, "Invalid_SteamID64");
		return false;
	}

	if (!GetClientAuthId(client, AuthId_Steam2, steamid2, 64, true))
	{
		Format(steamid2, 64, "Invalid_SteamID2");
	}

	GetClientName(client, nickname, 64);
	EscapeString(nickname, nicknameEscaped, 128);

	return true;
}

/**
 * Builds detection reason string based on client detection counters.
 * Optimized function to avoid repetitive logic.
 *
 * @param client		Client index.
 * @param buffer		Buffer to store the detection reasons.
 * @param maxLength		Maximum length of the buffer.
 * @noreturn
 */
void BuildDetectionReason(int client, char[] buffer, int maxLength)
{
	buffer[0]	= '\0';
	bool bFirst = true;

	if (g_iPlayerDetections[client][CHEAT_AIMBOT] >= g_hCvar[CVAR_DETECTIONS].IntValue)
	{
		StrCat(buffer, maxLength, "AIMBOT");
		bFirst = false;
	}

	if (g_iPlayerDetections[client][CHEAT_AIMLOCK] >= g_hCvar[CVAR_DETECTIONS].IntValue)
	{
		if (!bFirst)
			StrCat(buffer, maxLength, ", ");
		StrCat(buffer, maxLength, "AIMLOCK");
		bFirst = false;
	}

	if (bFirst)	   // No detections found
		strcopy(buffer, maxLength, "UNKNOWN");
}

/**
 * Creates or appends a KeyValues log entry for a player with their detection information.
 * The log file uses timestamp-keyed structure allowing multiple detection records per player.
 * The file is named using only the player's SteamID64 and saved as .cfg format.
 *
 * @param client		Client index of the player.
 * @param timestamp		Timestamp to use as KeyValues section for this detection record.
 * @noreturn
 */
void CreatePlayerKeyValuesLog(int client, int timestamp)
{
	if (!g_hCvar[CVAR_LOG].BoolValue || !g_hCvar[CVAR_ENABLE].BoolValue)
		return;

	char sSteamID64[64], sSteamID2[64], sNickname[64], sNicknameEscaped[128];
	char sLogPath[PLATFORM_MAX_PATH];
	char sDateTime[64];
	char sTimestampKey[32];

	// Get client information in one optimized call
	if (!GetLilacClientInfo(client, sSteamID64, sSteamID2, sNickname, sNicknameEscaped))
		return;

	// Determine detection reasons
	char sReasons[128];
	BuildDetectionReason(client, sReasons, sizeof(sReasons));

	BuildPlayerLogPath(sSteamID64, sLogPath, sizeof(sLogPath));

	// Create datetime string
	FormatTime(sDateTime, sizeof(sDateTime), "%Y-%m-%d %H:%M:%S", timestamp);

	// Format timestamp as section key
	Format(sTimestampKey, sizeof(sTimestampKey), "%d", timestamp);

	// Create or append to KeyValues log
	AppendPlayerKeyValuesLog(sLogPath, sTimestampKey, sSteamID2, sNicknameEscaped, sReasons, sDateTime);

	// Call forward to notify other plugins
	Call_StartForward(g_hOnPlayerLogCreated);
	Call_PushCell(client);
	Call_PushString(sSteamID64);
	Call_PushString(sLogPath);
	Call_PushCell(timestamp);
	Call_Finish();
}

/**
 * Updates a player's KeyValues log file with ban information.
 * Adds ban information to the existing global recording timestamp section instead of creating a new one.
 *
 * @param client		Client index of the banned player.
 * @param cheat			Type of cheat that triggered the ban.
 * @noreturn
 */
void UpdatePlayerKeyValuesLogWithBan(int client, int cheat)
{
	if (!g_hCvar[CVAR_LOG].BoolValue || !g_hCvar[CVAR_ENABLE].BoolValue)
		return;

	char sSteamID64[64];
	char sLogPath[PLATFORM_MAX_PATH];
	char sBanReason[32];
	char sBanDateTime[64];
	char sTimestampKey[32];
	int	 iBanTimestamp;

	// Get client Steam ID
	if (!GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64)))
		return;

	// Find the KeyValues file for this player
	if (!FindPlayerKeyValuesLog(client, sLogPath, sizeof(sLogPath)))
		return;

	// Check if file exists
	if (!FileExists(sLogPath))
		return;

	// Get ban information
	GetTranslatedCheatName(cheat, sBanReason, sizeof(sBanReason));
	iBanTimestamp = GetTime();
	FormatTime(sBanDateTime, sizeof(sBanDateTime), "%Y-%m-%d %H:%M:%S", iBanTimestamp);

	// Use global recording timestamp instead of creating new section
	Format(sTimestampKey, sizeof(sTimestampKey), "%d", g_iGlobalRecordingTimestamp);

	// Add ban entry to existing detection section
	AppendPlayerKeyValuesLogBan(sLogPath, sTimestampKey, sBanReason, sBanDateTime);

	// Call forward to notify other plugins
	Call_StartForward(g_hOnPlayerBanned);
	Call_PushCell(client);
	Call_PushString(sSteamID64);
	Call_PushCell(cheat);
	Call_PushString(sLogPath);
	Call_Finish();
}

/**
 * Updates a player's KeyValues log file with recording end information.
 * Adds end reason to the existing global recording timestamp section instead of creating a new one.
 *
 * @param client		Client index of the player.
 * @param reason		Reason for stopping recording (e.g., "timeout", "mapend", "disconnect", "manual").
 * @noreturn
 */
void UpdatePlayerKeyValuesLogWithRecordingEnd(int client, const char[] reason = "timeout")
{
	if (!g_hCvar[CVAR_LOG].BoolValue || !g_hCvar[CVAR_ENABLE].BoolValue)
		return;

	char sSteamID64[64];
	char sLogPath[PLATFORM_MAX_PATH];
	char sTimestampKey[32];

	// Get client Steam ID
	if (!GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64)))
		return;

	// Find the KeyValues file for this player
	if (!FindPlayerKeyValuesLog(client, sLogPath, sizeof(sLogPath)))
		return;

	// Check if file exists
	if (!FileExists(sLogPath))
		return;

	// Use global recording timestamp instead of creating new section
	Format(sTimestampKey, sizeof(sTimestampKey), "%d", g_iGlobalRecordingTimestamp);
	AppendPlayerKeyValuesLogEndReason(sLogPath, sTimestampKey, reason);
}

/**
 * Escapes special characters in a string for safe KeyValues formatting.
 * Handles quotes, backslashes, newlines, and other control characters.
 *
 * @param input			Input string to escape.
 * @param output		Output buffer for escaped string.
 * @param maxlength		Maximum length of output buffer.
 * @noreturn
 */
void EscapeString(const char[] input, char[] output, int maxlength)
{
	int inputLen  = strlen(input);
	int outputPos = 0;

	for (int i = 0; i < inputLen && outputPos < maxlength - 1; i++)
	{
		char c = input[i];

		switch (c)
		{
			case '"':
			{
				if (outputPos < maxlength - 2)
				{
					output[outputPos++] = '\\';
					output[outputPos++] = '"';
				}
			}
			case '\\':
			{
				if (outputPos < maxlength - 2)
				{
					output[outputPos++] = '\\';
					output[outputPos++] = '\\';
				}
			}
			case '\n':
			{
				if (outputPos < maxlength - 2)
				{
					output[outputPos++] = '\\';
					output[outputPos++] = 'n';
				}
			}
			case '\r':
			{
				if (outputPos < maxlength - 2)
				{
					output[outputPos++] = '\\';
					output[outputPos++] = 'r';
				}
			}
			case '\t':
			{
				if (outputPos < maxlength - 2)
				{
					output[outputPos++] = '\\';
					output[outputPos++] = 't';
				}
			}
			default:
			{
				// Remove any control characters (ASCII < 32)
				if (c >= 32)
				{
					output[outputPos++] = c;
				}
			}
		}
	}

	output[outputPos] = '\0';
}

/**
 * Gets the string representation of a StopRecordingReason enum value.
 * Now supports translation for client-specific language.
 *
 * @param reason		StopRecordingReason enum value.
 * @param buffer		Buffer to store the string representation.
 * @param maxlength		Maximum length of the buffer.
 * @param client		Client index for translation (LANG_SERVER if 0).
 * @noreturn
 */
void GetStopReasonString(StopRecordingReason reason, char[] buffer, int maxlength, int client = 0)
{
	if (view_as<int>(reason) >= view_as<int>(StopReason_Size) || view_as<int>(reason) < 0)
		reason = StopReason_Unknown;

	// Use translation system with fallback to original strings
	int targetLang = (client > 0) ? client : LANG_SERVER;

	switch (reason)
	{
		case StopReason_Timeout:
		{
			FormatEx(buffer, maxlength, "%T", "timeout", targetLang);
		}
		case StopReason_Disconnect:
		{
			FormatEx(buffer, maxlength, "%T", "disconnect", targetLang);
		}
		case StopReason_Manual:
		{
			FormatEx(buffer, maxlength, "%T", "manual_stop", targetLang);
		}
		default:
		{
			// Fallback to original hardcoded strings for other cases
			strcopy(buffer, maxlength, sStopRecordingReason[reason]);
		}
	}
}

KeyValues OpenPlayerKeyValuesSection(const char[] filePath, const char[] timestampKey, bool createSection)
{
	KeyValues kv = new KeyValues("LilacDetections");

	if (createSection)
	{
		kv.ImportFromFile(filePath);
	}
	else if (!kv.ImportFromFile(filePath))
	{
		delete kv;
		return null;
	}

	if (!kv.JumpToKey(timestampKey, createSection))
	{
		delete kv;
		return null;
	}

	return kv;
}

void SavePlayerKeyValuesSection(KeyValues kv, const char[] filePath)
{
	kv.Rewind();
	kv.ExportToFile(filePath);
	delete kv;
}

/**
 * Appends or creates a KeyValues log entry for a player using timestamp-keyed structure.
 * Each timestamp represents a separate detection record section in the KeyValues file.
 * The format is: "timestamp" { "steamid2" "..." "nickname" "..." "reason" "..." "datetime" "..." }
 *
 * @param filePath		Full path to the KeyValues log file.
 * @param timestampKey	Timestamp section name.
 * @param steamid2		Player's SteamID2.
 * @param nickname		Player's escaped nickname.
 * @param reason		Detection reason string.
 * @param datetime		Formatted datetime string.
 * @noreturn
 */
void AppendPlayerKeyValuesLog(const char[] filePath, const char[] timestampKey, const char[] steamid2, const char[] nickname, const char[] reason, const char[] datetime)
{
	KeyValues kv = OpenPlayerKeyValuesSection(filePath, timestampKey, true);
	if (kv == null)
		return;

	kv.SetString("steamid2", steamid2);
	kv.SetString("nickname", nickname);
	kv.SetString("reason", reason);
	kv.SetString("datetime", datetime);
	kv.SetString("demo", g_sCurrentDemo);

	SavePlayerKeyValuesSection(kv, filePath);
}

/**
 * Appends ban information to an existing KeyValues detection section.
 * Adds ban data to the existing timestamp section instead of overwriting it.
 *
 * @param filePath		Full path to the KeyValues log file.
 * @param timestampKey	Existing timestamp section name.
 * @param banReason		Ban reason string.
 * @param datetime		Formatted ban datetime string.
 * @noreturn
 */
void AppendPlayerKeyValuesLogBan(const char[] filePath, const char[] timestampKey, const char[] banReason, const char[] datetime)
{
	KeyValues kv = OpenPlayerKeyValuesSection(filePath, timestampKey, false);
	if (kv == null)
		return;

	kv.SetString("banned", "yes");
	kv.SetString("ban_reason", banReason);
	kv.SetString("ban_datetime", datetime);

	SavePlayerKeyValuesSection(kv, filePath);
}

/**
 * Appends recording end reason to an existing player's KeyValues detection section.
 * Adds end information to the existing timestamp section instead of creating a new one.
 *
 * @param filePath		Path to the KeyValues log file.
 * @param timestampKey	Existing timestamp section name.
 * @param reason		Reason for recording termination.
 * @noreturn
 */
void AppendPlayerKeyValuesLogEndReason(const char[] filePath, const char[] timestampKey, const char[] reason)
{
	KeyValues kv = OpenPlayerKeyValuesSection(filePath, timestampKey, false);
	if (kv == null)
		return;

	kv.SetString("recording_end", reason);

	SavePlayerKeyValuesSection(kv, filePath);
}

/**
 * Finds the KeyValues log file for a player.
 * Searches for files with pattern: SteamID64.cfg
 *
 * @param client		Client index of the player.
 * @param foundPath		Buffer to store the found file path.
 * @param maxLength		Maximum length of the foundPath buffer.
 * @return				True if file found, false otherwise.
 */
bool FindPlayerKeyValuesLog(int client, char[] foundPath, int maxLength)
{
	char sSteamID64[64];
	char sLogPath[PLATFORM_MAX_PATH];

	// Get client Steam ID
	if (!GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64)))
		return false;

	BuildPlayerLogPath(sSteamID64, sLogPath, sizeof(sLogPath));

	// Check if file exists
	if (FileExists(sLogPath))
	{
		strcopy(foundPath, maxLength, sLogPath);
		return true;
	}

	return false;
}

bool HasActiveRecordingDetections(int client)
{
	return g_iPlayerDetections[client][CHEAT_AIMBOT] > 0 || g_iPlayerDetections[client][CHEAT_AIMLOCK] > 0;
}

/**
 * Checks if a client index represents a valid connected player.
 * Validates client bounds, connection status, and in-game status.
 *
 * @param client		Client index to validate.
 * @return				True if client is valid, false otherwise.
 */
bool IsPlayerValid(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client));
}

// ============================================================================
// NATIVE FUNCTIONS
// ============================================================================
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// Register natives
	CreateNative("LilacSTV_IsRecording", Native_IsRecording);
	CreateNative("LilacSTV_GetCurrentDemo", Native_GetCurrentDemo);
	CreateNative("LilacSTV_GetRecordedPlayersCount", Native_GetRecordedPlayersCount);
	CreateNative("LilacSTV_IsPlayerRecorded", Native_IsPlayerRecorded);
	CreateNative("LilacSTV_DebugTriggerDetection", Native_DebugTriggerDetection);
	CreateNative("LilacSTV_DebugTriggerBan", Native_DebugTriggerBan);

	RegPluginLibrary("lilac_sourcetv");
	return APLRes_Success;
}

/**
 * Native: LilacSTV_IsRecording
 * Checks if Lilac SourceTV is currently recording.
 */
public int Native_IsRecording(Handle plugin, int numParams)
{
	return g_bStvRecording;
}

/**
 * Native: LilacSTV_GetCurrentDemo
 * Gets the current demo name being recorded (if any).
 */
public int Native_GetCurrentDemo(Handle plugin, int numParams)
{
	if (!g_bStvRecording || strlen(g_sCurrentDemo) == 0)
		return false;

	int maxlen = GetNativeCell(2);
	SetNativeString(1, g_sCurrentDemo, maxlen);
	return true;
}

/**
 * Native: LilacSTV_GetRecordedPlayersCount
 * Gets the number of players currently being recorded.
 */
public int Native_GetRecordedPlayersCount(Handle plugin, int numParams)
{
	return g_iRecordedPlayersCount;
}

/**
 * Native: LilacSTV_IsPlayerRecorded
 * Checks if a specific player is currently being recorded.
 */
public int Native_IsPlayerRecorded(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients)
		return false;

	return g_bPlayerRecording[client];
}

public int Native_DebugTriggerDetection(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int cheat = GetNativeCell(2);

	return TriggerTestDetection(client, cheat);
}

public int Native_DebugTriggerBan(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int cheat = GetNativeCell(2);

	return TriggerTestBan(client, cheat);
}

/**
 * Sends colored chat notifications to administrators about Lilac SourceTV events.
 * Uses colors.inc for L4D2 compatible colored messages and admin.inc for admin detection.
 *
 * @param messageType	Type of message using LilacNotifyType enum.
 * @param client		Client index of the affected player.
 * @param extraInfo		Extra information string (cheat type, demo name, etc.).
 * @noreturn
 */
void NotifyAdministrators(LilacNotifyType messageType, int client = -1, const char[] extraInfo = "")
{
	if (!g_hCvar[CVAR_ENABLE].BoolValue || !g_hCvar[CVAR_NOTIFY].IntValue)
		return;

	// Check if this specific notification type is enabled
	int notifyFlag = 0;
	switch (messageType)
	{
		case LilacNotify_Detection: notifyFlag = NOTIFY_DETECTION;
		case LilacNotify_RecordingStart: notifyFlag = NOTIFY_RECORDING_START;
		case LilacNotify_RecordingStop: notifyFlag = NOTIFY_RECORDING_STOP;
		case LilacNotify_RecordingEnd: notifyFlag = NOTIFY_RECORDING_END;
		case LilacNotify_Ban: notifyFlag = NOTIFY_BAN;
		default: return;	// Unknown type
	}

	// Check if this notification type is enabled in the flags
	if (!(g_hCvar[CVAR_NOTIFY].IntValue & notifyFlag))
		return;

	char sMessage[256];
	char sPlayerName[64];
	char sSteamID[32];

	// Get player info if client is valid
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		GetClientName(client, sPlayerName, sizeof(sPlayerName));
		GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	}
	else
	{
		strcopy(sPlayerName, sizeof(sPlayerName), "Unknown");
		strcopy(sSteamID, sizeof(sSteamID), "N/A");
	}

	// Send message to all administrators
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !CanClientReceiveLilacNotifications(i))
			continue;

		// Format message based on enum type for each admin in their language
		switch (messageType)
		{
			case LilacNotify_Detection:
			{
				Format(sMessage, sizeof(sMessage), "%T", "notify_detection", i, sPlayerName, sSteamID, extraInfo);
			}
			case LilacNotify_RecordingStart:
			{
				Format(sMessage, sizeof(sMessage), "%T", "notify_recording_start", i, sPlayerName, sSteamID, extraInfo);
			}
			case LilacNotify_RecordingStop:
			{
				Format(sMessage, sizeof(sMessage), "%T", "notify_recording_stop", i, extraInfo);
			}
			case LilacNotify_Ban:
			{
				Format(sMessage, sizeof(sMessage), "%T", "notify_ban", i, sPlayerName, sSteamID, extraInfo);
			}
			case LilacNotify_RecordingEnd:
			{
				Format(sMessage, sizeof(sMessage), "%T", "notify_recording_end", i, sPlayerName, sSteamID, extraInfo);
			}
			default:
			{
				continue;	 // Unknown message type
			}
		}

		CPrintToChat(i, "%s", sMessage);
	}
}

bool CanClientReceiveLilacNotifications(int client)
{
	AdminId adminId = GetUserAdmin(client);
	if (adminId == INVALID_ADMIN_ID)
		return false;

	return GetAdminFlag(adminId, Admin_Generic, Access_Effective);
}

/**
 * Command to display current notification settings
 */
public Action Command_LilacNotify(int client, int args)
{
	int	 notifyFlags = g_hCvar[CVAR_NOTIFY].IntValue;

	char buffer[256];
	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_header", client);
	ReplyToCommand(client, buffer);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_current_value", client, notifyFlags);
	ReplyToCommand(client, buffer);

	char enabledText[32], disabledText[32];
	FormatEx(enabledText, sizeof(enabledText), "%T", "enabled", client);
	FormatEx(disabledText, sizeof(disabledText), "%T", "disabled", client);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_detection", client,
			 (notifyFlags & NOTIFY_DETECTION) ? enabledText : disabledText, NOTIFY_DETECTION);
	ReplyToCommand(client, buffer);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_recording_start", client,
			 (notifyFlags & NOTIFY_RECORDING_START) ? enabledText : disabledText, NOTIFY_RECORDING_START);
	ReplyToCommand(client, buffer);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_recording_stop", client,
			 (notifyFlags & NOTIFY_RECORDING_STOP) ? enabledText : disabledText, NOTIFY_RECORDING_STOP);
	ReplyToCommand(client, buffer);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_recording_end", client,
			 (notifyFlags & NOTIFY_RECORDING_END) ? enabledText : disabledText, NOTIFY_RECORDING_END);
	ReplyToCommand(client, buffer);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_status_ban", client,
			 (notifyFlags & NOTIFY_BAN) ? enabledText : disabledText, NOTIFY_BAN);
	ReplyToCommand(client, buffer);

	ReplyToCommand(client, "%T", "notify_change_instructions", client);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_flag_values", client, NOTIFY_ALL);
	ReplyToCommand(client, buffer);

	FormatEx(buffer, sizeof(buffer), "%T", "notify_examples", client,
			 NOTIFY_DETECTION | NOTIFY_BAN,
			 NOTIFY_RECORDING_START | NOTIFY_RECORDING_STOP | NOTIFY_RECORDING_END);
	ReplyToCommand(client, buffer);

	return Plugin_Handled;
}

/**
 * Command to toggle specific notification types
 */
public Action Command_LilacNotifyToggle(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "%T", "toggle_usage", client);
		ReplyToCommand(client, "%T", "toggle_types", client);
		return Plugin_Handled;
	}

	int type		 = GetCmdArgInt(1);

	// Toggle the specific notification type
	int currentValue = g_hCvar[CVAR_NOTIFY].IntValue;
	switch (type)
	{
		case 1: g_hCvar[CVAR_NOTIFY].SetInt(currentValue ^ NOTIFY_DETECTION);
		case 2: g_hCvar[CVAR_NOTIFY].SetInt(currentValue ^ NOTIFY_RECORDING_START);
		case 3: g_hCvar[CVAR_NOTIFY].SetInt(currentValue ^ NOTIFY_RECORDING_STOP);
		case 4: g_hCvar[CVAR_NOTIFY].SetInt(currentValue ^ NOTIFY_RECORDING_END);
		case 5: g_hCvar[CVAR_NOTIFY].SetInt(currentValue ^ NOTIFY_BAN);
		default:
		{
			ReplyToCommand(client, "%T", "toggle_invalid_type", client);
			return Plugin_Handled;
		}
	}

	ReplyToCommand(client, "%T", "toggle_success", client);
	return Plugin_Handled;
}

/**
 * Gets the translated name of a cheat type.
 * Supports client-specific language for AIMBOT and AIMLOCK.
 *
 * @param type			Cheat type (CHEAT_AIMBOT, CHEAT_AIMLOCK, etc.).
 * @param buffer		Buffer to store the cheat name.
 * @param maxlen		Maximum length of the buffer.
 * @param client		Client index for translation (LANG_SERVER if 0).
 * @noreturn
 */
void GetTranslatedCheatName(int type, char[] buffer, int maxlen, int client = 0)
{
	int targetLang = (client > 0) ? client : LANG_SERVER;
	
	switch (type)
	{
		case CHEAT_AIMBOT:
		{
			FormatEx(buffer, maxlen, "%T", "aimbot", targetLang);
		}
		case CHEAT_AIMLOCK:
		{
			FormatEx(buffer, maxlen, "%T", "aimlock", targetLang);
		}
		default:
		{
			// Fallback to original function for other cheat types
			GetCheatName(type, buffer, maxlen);
		}
	}
}
