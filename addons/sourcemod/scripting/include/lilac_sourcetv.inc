/*
    Lilac SourceTV Auto Recorder
    Copyright (C) 2023 J_Tanzanite

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <https://www.gnu.org/licenses/>.
*/

#if defined _lilac_sourcetv_included
 #endinput
#endif
#define _lilac_sourcetv_included

/**
 * StopRecordingReason: the 'reason' parameter for stopping recording
 */
enum StopRecordingReason
{
    StopReason_Unknown    = 0,
    StopReason_Timeout    = 1,
    StopReason_MapEnd     = 2,
    StopReason_MapStart   = 3,
    StopReason_NoPlayers  = 4,
    StopReason_Disconnect = 5,
    StopReason_PluginEnd  = 6,
    StopReason_Startup    = 7,
    StopReason_Manual     = 8,

    StopReason_Size       = 9
};

/**
 * StopRecordingReason: the name of the 'reason' for stopping recording
 */
stock char sStopRecordingReason[StopReason_Size][] = {
    "unknown",
    "timeout",
    "mapend",
    "mapstart",
    "no_players",
    "disconnect",
    "plugin_end",
    "startup",
    "manual"
};

/**
 * Called when SourceTV recording starts due to cheat detection.
 * Other plugins should avoid starting their own recordings during this time.
 *
 * @param client        Client index of the player who triggered the recording.
 * @param demoName      Name of the demo file being recorded.
 * @param steamid64     SteamID64 of the player who triggered the recording.
 * @param cheat         Type of cheat detected (CHEAT_AIMBOT or CHEAT_AIMLOCK).
 * @noreturn
 */
forward void LilacSTV_OnRecordingStarted(int client, const char[] demoName, const char[] steamid64, int cheat);

/**
 * Called when SourceTV recording stops.
 * Other plugins can resume their normal SourceTV operations after this.
 *
 * @param reason        Reason for stopping recording (StopRecordingReason enum value).
 * @param duration      Duration of the recording in seconds.
 * @noreturn
 */
forward void LilacSTV_OnRecordingStopped(StopRecordingReason reason, int duration);

/**
 * Called when a player's KeyValues log is created.
 * Allows other plugins to add custom data or perform additional logging.
 *
 * @param client        Client index of the player.
 * @param steamid64     SteamID64 of the player.
 * @param logPath       Full path to the created KeyValues log file (.cfg format).
 * @param timestamp     Timestamp when the log was created.
 * @noreturn
 */
forward void LilacSTV_OnPlayerLogCreated(int client, const char[] steamid64, const char[] logPath, int timestamp);

/**
 * Called when a player is banned and their KeyValues log is updated.
 * Allows other plugins to perform additional actions when a ban occurs.
 *
 * @param client        Client index of the banned player.
 * @param steamid64     SteamID64 of the banned player.
 * @param cheat         Type of cheat that caused the ban.
 * @param logPath       Path to the updated KeyValues log file (.cfg format).
 * @noreturn
 */
forward void LilacSTV_OnPlayerBanned(int client, const char[] steamid64, int cheat, const char[] logPath);

/**
 * Checks if Lilac SourceTV is currently recording.
 * Other plugins should use this to avoid conflicts.
 *
 * @return              True if currently recording, false otherwise.
 */
native bool LilacSTV_IsRecording();

/**
 * Gets the current demo name being recorded (if any).
 *
 * @param buffer        Buffer to store the demo name.
 * @param maxlen        Maximum length of the buffer.
 * @return              True if recording and name retrieved, false otherwise.
 */
native bool LilacSTV_GetCurrentDemo(char[] buffer, int maxlen);

/**
 * Gets the number of players currently being recorded.
 *
 * @return              Number of players with active detections being recorded.
 */
native int LilacSTV_GetRecordedPlayersCount();

/**
 * Checks if a specific player is currently being recorded.
 *
 * @param client        Client index to check.
 * @return              True if player is being recorded, false otherwise.
 */
native bool LilacSTV_IsPlayerRecorded(int client);

/**
 * Debug helper to simulate a supported Lilac detection inside the recorder.
 * Intended for test plugins and admin-only tooling.
 *
 * @param client        Client index to simulate detection for.
 * @param cheat         Supported cheat type (CHEAT_AIMBOT or CHEAT_AIMLOCK).
 * @return              True if the simulated detection was accepted, false otherwise.
 */
native bool LilacSTV_DebugTriggerDetection(int client, int cheat);

/**
 * Debug helper to simulate a supported Lilac ban callback inside the recorder.
 * Intended for test plugins and admin-only tooling.
 *
 * @param client        Client index to simulate ban for.
 * @param cheat         Supported cheat type (CHEAT_AIMBOT or CHEAT_AIMLOCK).
 * @return              True if the simulated ban callback was accepted, false otherwise.
 */
native bool LilacSTV_DebugTriggerBan(int client, int cheat);

public SharedPlugin __pl_lilac_sourcetv =
{
    name = "lilac_sourcetv",
    file = "lilac_sourcetv.smx",
    #if defined REQUIRE_PLUGIN
    required = 1,
    #else
    required = 0
    #endif
};

public void __pl_lilac_sourcetv_SetNTVOptional()
{
    MarkNativeAsOptional("LilacSTV_IsRecording");
    MarkNativeAsOptional("LilacSTV_GetCurrentDemo");
    MarkNativeAsOptional("LilacSTV_GetRecordedPlayersCount");
    MarkNativeAsOptional("LilacSTV_IsPlayerRecorded");
    MarkNativeAsOptional("LilacSTV_DebugTriggerDetection");
    MarkNativeAsOptional("LilacSTV_DebugTriggerBan");
}
