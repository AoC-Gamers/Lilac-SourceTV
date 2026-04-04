#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lilac>
#include <lilac_sourcetv>

public Plugin myinfo =
{
    name = "[Lilac] SourceTV Recorder Test",
    author = "GitHub Copilot",
    description = "Admin-only test commands for lilac_sourcetv.",
    version = "1.1.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("lilac_sourcetv.phrases");

    RegAdminCmd("sm_lilac_test", Command_LilacTestDetection, ADMFLAG_ROOT,
        "Test lilac_sourcetv detection flow - Usage: sm_lilac_test <target> <1=aimbot|2=aimlock>");
    RegAdminCmd("sm_lilac_test_ban", Command_LilacTestBan, ADMFLAG_ROOT,
        "Test lilac_sourcetv ban flow - Usage: sm_lilac_test_ban <target> <1=aimbot|2=aimlock>");
}

public Action Command_LilacTestDetection(int client, int args)
{
    if (args != 2)
    {
        ReplyTranslated(client, "test_usage");
        ReplyTranslated(client, "test_cheat_types");
        return Plugin_Handled;
    }

    int target;
    int cheat;
    if (!GetCommandTestContext(client, target, cheat))
        return Plugin_Handled;

    char targetName[64];
    GetClientName(target, targetName, sizeof(targetName));

    PrintToChat(client, "%T", "test_simulating_detection", client, targetName);

    if (!LilacSTV_DebugTriggerDetection(target, cheat))
        ReplyToCommand(client, "[LilacSTV Test] The recorder rejected the simulated detection.");

    return Plugin_Handled;
}

public Action Command_LilacTestBan(int client, int args)
{
    if (args != 2)
    {
        ReplyToCommand(client, "Usage: sm_lilac_test_ban <target> <1=aimbot|2=aimlock>");
        return Plugin_Handled;
    }

    int target;
    int cheat;
    if (!GetCommandTestContext(client, target, cheat))
        return Plugin_Handled;

    char targetName[64];
    char message[128];
    GetClientName(target, targetName, sizeof(targetName));

    FormatEx(message, sizeof(message), "[LilacSTV Test] Simulating ban callback for %s.", targetName);
    ReplyToCommand(client, message);

    if (!LilacSTV_DebugTriggerBan(target, cheat))
        ReplyToCommand(client, "[LilacSTV Test] The recorder rejected the simulated ban callback.");

    return Plugin_Handled;
}

bool GetCommandTestContext(int client, int &target, int &cheat)
{
    char arg1[64], arg2[8];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    target = FindTarget(client, arg1, true, false);
    if (target == -1)
        return false;

    if (!IsClientConnected(target) || !IsClientInGame(target))
    {
        ReplyTranslated(client, "test_invalid_target");
        return false;
    }

    cheat = GetTestCheatType(StringToInt(arg2));
    if (cheat == -1)
    {
        ReplyTranslated(client, "test_invalid_cheat_type");
        return false;
    }

    return true;
}

void ReplyTranslated(int client, const char[] phrase)
{
    char buffer[192];
    FormatEx(buffer, sizeof(buffer), "%T", phrase, client);
    ReplyToCommand(client, buffer);
}

int GetTestCheatType(int selection)
{
    switch (selection)
    {
        case 1: return CHEAT_AIMBOT;
        case 2: return CHEAT_AIMLOCK;
    }

    return -1;
}
