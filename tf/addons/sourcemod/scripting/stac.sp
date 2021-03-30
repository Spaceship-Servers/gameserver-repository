// see the readme for more info:
// https://github.com/stephanieLGBT/StAC-tf2/blob/master/README.md
// written by steph, chloe, and liza
// i love my partners
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <morecolors>
#include <regex>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <autoexecconfig>
#undef REQUIRE_PLUGIN
#include <updater>
#include <sourcebanspp>
#undef REQUIRE_EXTENSIONS
#include <steamtools>
#include <SteamWorks>

#define PLUGIN_VERSION  "4.1.13b"

#define UPDATE_URL      "https://raw.githubusercontent.com/sapphonie/StAC-tf2/master/updatefile.txt"

#pragma newdecls required

public Plugin myinfo =
{
    name             =  "Steph's AntiCheat (StAC)",
    author           =  "steph&nie",
    description      =  "Anticheat plugin [tf2 only] written by Stephanie. Originally forked from IntegriTF2 by Miggy (RIP)",
    version          =   PLUGIN_VERSION,
    url              =  "https://sappho.io"
}

#define TFMAXPLAYERS 33

// TIMER HANDLES
Handle QueryTimer           [TFMAXPLAYERS+1];
Handle TriggerTimedStuffTimer;
// TPS INFO
float tickinterv;
float tps;
float bhopmult;
// DETECTIONS PER CLIENT
int turnTimes               [TFMAXPLAYERS+1];
int fovDesired              [TFMAXPLAYERS+1] = 75;
int fakeAngDetects          [TFMAXPLAYERS+1];
int aimsnapDetects          [TFMAXPLAYERS+1] = -1; // set to -1 to ignore first detections, as theyre most likely junk
int pSilentDetects          [TFMAXPLAYERS+1] = -1; // ^
int bhopDetects             [TFMAXPLAYERS+1] = -1; // set to -1 to ignore single jumps
int cmdnumSpikeDetects      [TFMAXPLAYERS+1];
bool isConsecStringOfBhops  [TFMAXPLAYERS+1];
int bhopConsecDetects       [TFMAXPLAYERS+1];
int settingsChangesFor      [TFMAXPLAYERS+1];

// TIME SINCE LAST ACTION PER CLIENT
float timeSinceSpawn        [TFMAXPLAYERS+1];
float timeSinceTaunt        [TFMAXPLAYERS+1];
float timeSinceTeled        [TFMAXPLAYERS+1];
// STORED ANGLES PER CLIENT
float clangles           [3][TFMAXPLAYERS+1][2];
// STORED POS PER CLIENT
float clpos              [2][TFMAXPLAYERS+1][3];
// STORED cmdnum PER CLIENT
int clcmdnum             [6][TFMAXPLAYERS+1];
// STORED BUTTONS PER CLIENT
int buttonsPrev             [TFMAXPLAYERS+1];
// STORED GRAVITY STATE PER CLIENT
bool highGrav               [TFMAXPLAYERS+1];
// STORED MISC VARS PER CLIENT
bool playerTaunting         [TFMAXPLAYERS+1];
int playerInBadCond         [TFMAXPLAYERS+1];
bool userBanQueued          [TFMAXPLAYERS+1];
// STORED SENS PER CLIENT
float sensFor               [TFMAXPLAYERS+1];
// get last 6 ticks
float engineTime        [11][TFMAXPLAYERS+1];
// time since the map started (duh)
float timeSinceMapStart;
// weapon name, gets passed to aimsnap check
char hurtWeapon             [TFMAXPLAYERS+1][256];
// time since player did damage, for aimsnap check
float timeSinceDidHurt      [TFMAXPLAYERS+1];

// NATIVE BOOLS
bool SOURCEBANS;
bool GBANS;
bool STEAMTOOLS;
bool STEAMWORKS;
bool AIMPLOTTER;

// CVARS
ConVar stac_enabled;
ConVar stac_verbose_info;
ConVar stac_max_allowed_turn_secs;
ConVar stac_ban_for_misccheats;
ConVar stac_optimize_cvars;
ConVar stac_max_aimsnap_detections;
ConVar stac_max_psilent_detections;
ConVar stac_max_bhop_detections;
ConVar stac_max_fakeang_detections;
ConVar stac_max_cmdnum_detections;
ConVar stac_max_settings_changes;
ConVar stac_settings_changes_window;
ConVar stac_min_interp_ms;
ConVar stac_max_interp_ms;
ConVar stac_min_randomcheck_secs;
ConVar stac_max_randomcheck_secs;
ConVar stac_include_demoname_in_banreason;
ConVar stac_log_to_file;

// VARIOUS DETECTION BOUNDS & CVAR VALUES
bool DEBUG                  = false;
float maxAllowedTurnSecs    = -1.0;
bool kickForPingMasking     = false;
bool banForMiscCheats       = true;
bool optimizeCvars          = true;

int maxAimsnapDetections    = 25;
int maxPsilentDetections    = 10;
int maxFakeAngDetections    = 10;
int maxBhopDetections       = 10;
int maxCmdnumDetections     = 25;
// this gets set later
int maxBhopDetectionsScaled;

// max settings changes per...
int maxSettingsChanges      = 30;
// ...this time in seconds
float SettingsChangeWindow  = 60.0;

// interp limits
int min_interp_ms           = -1;
int max_interp_ms           = 101;
// RANDOM CVARS CHECK MIN/MAX BOUNDS (in seconds)
float minRandCheckVal       = 60.0;
float maxRandCheckVal       = 300.0;
// put demoname in sourcebans / gbans?
bool demonameInBanReason    = true;
// log to file?
bool logtofile              = true;

// bool that gets set by steamtools/steamworks forwards - used to kick clients that dont auth
int isSteamAlive            = -1;

// Log file
File StacLogFile;

// REGEX
Regex demonameRegex;

public void OnPluginStart()
{
    // check if tf2, unload if not
    if (GetEngineVersion() != Engine_TF2)
    {
        SetFailState("[StAC] This plugin is only supported for TF2! Aborting!");
    }

    if (MaxClients > TFMAXPLAYERS)
    {
        SetFailState("[StAC] This plugin (and TF2 in general) does not support more than 33 players (32 + 1 for STV). Aborting!");
    }

    // updater
    if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
    // open log
    OpenStacLog();

    // reg admin commands
    // TODO: make these invisible for non admins
    RegAdminCmd("sm_stac_checkall", ForceCheckAll,    ADMFLAG_GENERIC, "Force check all client convars (ALL CLIENTS) for anticheat stuff");
    RegAdminCmd("sm_stac_detections", ShowDetections, ADMFLAG_GENERIC, "Show all current detections on all connected clients");
    //RegAdminCmd("sm_stac_shutup", ShutTheHellUpBitch, ADMFLAG_GENERIC, "Make StAC be quiet for whoever runs this command!");

    // get tick interval - some modded tf2 servers run at >66.7 tick!
    tickinterv = GetTickInterval();
    // reset random server seed
    ActuallySetRandomSeed();

    // setup regex - "Recording to ".*""
    demonameRegex = new Regex("Recording to \".*\"");

    // grab round start events for calculating tps
    HookEvent("teamplay_round_start", eRoundStart);
    // grab player spawns
    HookEvent("player_spawn", ePlayerSpawned);

***REPLACED API KEY***
    CreateTimer(0.1, checkNativesEtc);
    // check EVERYONE's cvars on plugin reload
    CreateTimer(0.5, checkEveryone);

    // hook sv_cheats so we can instantly unload if cheats get turned on
    HookConVarChange(FindConVar("sv_cheats"), GenericCvarChanged);
    // Create ConVars for adjusting settings
    initCvars();
    // load translations
    LoadTranslations("stac.phrases.txt");

    // reset all client based vars on plugin reload
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        if (IsValidClient(Cl))
        {
            int userid = GetClientUserId(Cl);
            ClearClBasedVars(userid);
            // wait a second to let natives get checked
            CreateTimer(1.0, CheckAuthOn, userid);
        }
        if (IsValidClientOrBot(Cl))
        {
            SDKHook(Cl, SDKHook_OnTakeDamage, hOnTakeDamage);
        }
    }

    timeSinceMapStart = GetEngineTime();

    StacLog("[StAC] Plugin vers. ---- %s ---- loaded", PLUGIN_VERSION);
}

void initCvars()
{
    AutoExecConfig_SetFile("stac");
    AutoExecConfig_SetCreateFile(true);

    char buffer[16];

    // plugin enabled
    stac_enabled =
    AutoExecConfig_CreateConVar
    (
        "stac_enabled",
        "1",
        "[StAC] enable/disable plugin (setting this to 0 immediately unloads stac)",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    HookConVarChange(stac_enabled, stacVarChanged);

    // verbose mode
    if (DEBUG)
    {
        buffer = "1";
    }
    else
    {
        buffer = "0";
    }
    stac_verbose_info =
    AutoExecConfig_CreateConVar
    (
        "stac_verbose_info",
        buffer,
        "[StAC] enable/disable showing verbose info about players' cvars and other similar info in admin console\n(recommended 0 unless you want spam in console)",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    HookConVarChange(stac_verbose_info, stacVarChanged);

    // turn seconds
    FloatToString(maxAllowedTurnSecs, buffer, sizeof(buffer));
    stac_max_allowed_turn_secs =
    AutoExecConfig_CreateConVar
    (
        "stac_max_allowed_turn_secs",
        buffer,
        "[StAC] maximum allowed time in seconds before client is autokicked for using turn binds (+right/+left inputs). -1 to disable autokicking, 0 instakicks\n(recommended -1.0 unless you're using this in a competitive setting)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_allowed_turn_secs, stacVarChanged);

    // pingmasking
    if (kickForPingMasking)
    {
        buffer = "1";
    }
    else
    {
        buffer = "0";
    }

    // cheatvars ban bool
    if (banForMiscCheats)
    {
        buffer = "1";
    }
    else
    {
        buffer = "0";
    }
    stac_ban_for_misccheats =
    AutoExecConfig_CreateConVar
    (
        "stac_ban_for_misccheats",
        buffer,
        "[StAC] ban clients for non angle based cheats, aka cheat locked cvars, netprops, invalid names, invalid chat characters, etc.\n(defaults to 1)",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    HookConVarChange(stac_ban_for_misccheats, stacVarChanged);

    // cheatvars ban bool
    if (optimizeCvars)
    {
        buffer = "1";
    }
    else
    {
        buffer = "0";
    }
    stac_optimize_cvars =
    AutoExecConfig_CreateConVar
    (
        "stac_optimize_cvars",
        buffer,
        "[StAC] optimize cvars related to patching backtracking, mostly patching doubletap, limiting fakelag, patching any possible tele expoits, etc.\n(defaults to 1)",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    HookConVarChange(stac_optimize_cvars, stacVarChanged);

    // aimsnap detections
    IntToString(maxAimsnapDetections, buffer, sizeof(buffer));
    stac_max_aimsnap_detections =
    AutoExecConfig_CreateConVar
    (
        "stac_max_aimsnap_detections",
        buffer,
        "[StAC] maximum aimsnap detections before banning a client.\n-1 to disable even checking angles (saves cpu), 0 to print to admins/stv but never ban\n(recommended 25 or higher)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_aimsnap_detections, stacVarChanged);

    // psilent detections
    IntToString(maxPsilentDetections, buffer, sizeof(buffer));
    stac_max_psilent_detections =
    AutoExecConfig_CreateConVar
    (
        "stac_max_psilent_detections",
        buffer,
        "[StAC] maximum silent aim/norecoil detections before banning a client.\n-1 to disable even checking angles (saves cpu), 0 to print to admins/stv but never ban\n(recommended 15 or higher)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_psilent_detections, stacVarChanged);

    // bhop detections
    IntToString(maxBhopDetections, buffer, sizeof(buffer));
    stac_max_bhop_detections =
    AutoExecConfig_CreateConVar
    (
        "stac_max_bhop_detections",
        buffer,
        "[StAC] maximum consecutive bhop detecions on a client before they get \"antibhopped\". client will get banned on this value + 2, so for default cvar settings, client will get banned on 12 tick perfect bhops.\nctrl + f for \"antibhop\" in stac.sp for more detailed info.\n-1 to disable even checking bhops (saves cpu), 0 to print to admins/stv but never ban\n(recommended 10 or higher)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_bhop_detections, stacVarChanged);

    // fakeang detections
    IntToString(maxFakeAngDetections, buffer, sizeof(buffer));
    stac_max_fakeang_detections =
    AutoExecConfig_CreateConVar
    (
        "stac_max_fakeang_detections",
        buffer,
        "[StAC] maximum fake angle / wrong / OOB angle detecions before banning a client.\n-1 to disable even checking angles (saves cpu), 0 to print to admins/stv but never ban\n(recommended 10)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_fakeang_detections, stacVarChanged);


    // cmdnum spike detections
    IntToString(maxCmdnumDetections, buffer, sizeof(buffer));
    stac_max_cmdnum_detections =
    AutoExecConfig_CreateConVar
    (
        "stac_max_cmdnum_detections",
        buffer,
        "[StAC] maximum cmdnum spikes a client can have before getting banned. lmaobox does this with nospread on certain weapons, other cheats may also utilize it. legit users should not ever trigger this!\n(recommended 25)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_cmdnum_detections, stacVarChanged);

    // userinfo spam changes
    IntToString(maxSettingsChanges, buffer, sizeof(buffer));
    stac_max_settings_changes =
    AutoExecConfig_CreateConVar
    (
        "stac_max_settings_changes",
        buffer,
        "[StAC] maximum client settings changes (userinfo changes) per stac_settings_changes_window before client is automatically kicked. 0 or -1 to disable",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_settings_changes, stacVarChanged);

    // settingschangewindow
    FloatToString(SettingsChangeWindow, buffer, sizeof(buffer));
    stac_settings_changes_window =
    AutoExecConfig_CreateConVar
    (
        "stac_settings_changes_window",
        buffer,
        "[StAC] if client changes userinfo more than stac_max_settings_changes during this cvar value (in seconds), client is autokicked for spamming userinfo changes. 0 or -1 to disable",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_settings_changes_window, stacVarChanged);

    // min interp
    IntToString(min_interp_ms, buffer, sizeof(buffer));
    stac_min_interp_ms =
    AutoExecConfig_CreateConVar
    (
        "stac_min_interp_ms",
        buffer,
        "[StAC] minimum interp (lerp) in milliseconds that a client is allowed to have before getting autokicked. set this to -1 to disable having a min interp\n(recommended disabled, but if you want to enable it, feel free. interp values below 15.1515151 ms don't seem to have any noticable effects on anything meaningful)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_min_interp_ms, stacVarChanged);

    // min interp
    IntToString(max_interp_ms, buffer, sizeof(buffer));
    stac_max_interp_ms =
    AutoExecConfig_CreateConVar
    (
        "stac_max_interp_ms",
        buffer,
        "[StAC] maximum interp (lerp) in milliseconds that a client is allowed to have before getting autokicked. set this to -1 to disable having a max interp\n(recommended 101)",
        FCVAR_NONE,
        true,
        -1.0,
        false,
        _
    );
    HookConVarChange(stac_max_interp_ms, stacVarChanged);

    // min random check secs
    FloatToString(minRandCheckVal, buffer, sizeof(buffer));
    stac_min_randomcheck_secs =
    AutoExecConfig_CreateConVar
    (
        "stac_min_randomcheck_secs",
        buffer,
        "[StAC] check AT LEAST this often in seconds for clients with violating cvar values/netprops\n(recommended 60)",
        FCVAR_NONE,
        true,
        5.0,
        false,
        _
    );
    HookConVarChange(stac_min_randomcheck_secs, stacVarChanged);

    // min random check secs
    FloatToString(maxRandCheckVal, buffer, sizeof(buffer));
    stac_max_randomcheck_secs =
    AutoExecConfig_CreateConVar
    (
        "stac_max_randomcheck_secs",
        buffer,
        "[StAC] check AT MOST this often in seconds for clients with violating cvar values/netprops\n(recommended 300)",
        FCVAR_NONE,
        true,
        15.0,
        false,
        _
    );
    HookConVarChange(stac_max_randomcheck_secs, stacVarChanged);

    // demoname in ban reason
    if (demonameInBanReason)
    {
        buffer = "1";
    }
    else
    {
        buffer = "0";
    }
    stac_include_demoname_in_banreason =
    AutoExecConfig_CreateConVar
    (
        "stac_include_demoname_in_banreason",
        buffer,
        "[StAC] enable/disable putting the currently recording demo in the SourceBans / gbans ban reason\n(recommended 1)",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    HookConVarChange(stac_include_demoname_in_banreason, stacVarChanged);

    // log to file
    if (logtofile)
    {
        buffer = "1";
    }
    else
    {
        buffer = "0";
    }
    stac_log_to_file =
    AutoExecConfig_CreateConVar
    (
        "stac_log_to_file",
        buffer,
        "[StAC] enable/disable logging to file\n(recommended 1)",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    HookConVarChange(stac_log_to_file, stacVarChanged);

    // actually exec the cfg after initing cvars lol
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
    setStacVars();
}

void stacVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    // this regrabs all cvar values but it's neater than having two similar functions that do the same thing
    setStacVars();
}

void setStacVars()
{
    // now covers late loads

    // enabled var
    if (!GetConVarBool(stac_enabled))
    {
        SetFailState("[StAC] stac_enabled is set to 0 - aborting!");
    }

    // verbose info var
    DEBUG                   = GetConVarBool(stac_verbose_info);

    // turn seconds var
    maxAllowedTurnSecs      = GetConVarFloat(stac_max_allowed_turn_secs);
    if (maxAllowedTurnSecs < 0.0 && maxAllowedTurnSecs != -1.0)
    {
        maxAllowedTurnSecs = 0.0;
    }

    // misccheats
    banForMiscCheats        = GetConVarBool(stac_ban_for_misccheats);

    // optimizecvars
    optimizeCvars           = GetConVarBool(stac_optimize_cvars);
    if (optimizeCvars)
    {
        RunOptimizeCvars();
    }

    // aimsnap var
    maxAimsnapDetections    = GetConVarInt(stac_max_aimsnap_detections);

    // psilent var
    maxPsilentDetections    = GetConVarInt(stac_max_psilent_detections);

    // bhop var
    maxBhopDetections       = GetConVarInt(stac_max_bhop_detections);

    // fakeang var
    maxFakeAngDetections    = GetConVarInt(stac_max_fakeang_detections);

    // cmdnum spikes var
    maxCmdnumDetections     = GetConVarInt(stac_max_cmdnum_detections);

    // max settings changes var
    maxSettingsChanges      = GetConVarInt(stac_max_settings_changes);

    // settings change var
    SettingsChangeWindow    = GetConVarFloat(stac_settings_changes_window);

    // minterp var - clamp to -1 if 0
    min_interp_ms           = GetConVarInt(stac_min_interp_ms);
    if (min_interp_ms == 0)
    {
        min_interp_ms = -1;
    }

    // maxterp var - clamp to -1 if 0
    max_interp_ms           = GetConVarInt(stac_max_interp_ms);
    if (max_interp_ms == 0)
    {
        max_interp_ms = -1;
    }

    // min check sec var
    minRandCheckVal         = GetConVarFloat(stac_min_randomcheck_secs);

    // max check sec var
    maxRandCheckVal         = GetConVarFloat(stac_max_randomcheck_secs);

    // log to file
    logtofile               = GetConVarBool(stac_log_to_file);

    // this is for bhop detection only
    DoTPSMath();
}

void GenericCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    // IMMEDIATELY unload if we enable sv cheats
    if (convar == FindConVar("sv_cheats"))
    {
        if (StringToInt(newValue) != 0)
        {
            SetFailState("[StAC] sv_cheats set to 1! Aborting!");
        }
    }
}

void RunOptimizeCvars()
{
    // attempt to patch doubletap
    SetConVarInt(FindConVar("sv_maxusrcmdprocessticks"), 16);
    // limit fakelag abuse
    SetConVarFloat(FindConVar("sv_maxunlag"), 0.2);
    // fix backtracking
    // dont error out on server start
    ConVar jay_backtrack_enable     = FindConVar("jay_backtrack_enable");
    ConVar jay_backtrack_tolerance  = FindConVar("jay_backtrack_tolerance");
    if (jay_backtrack_enable != null && jay_backtrack_tolerance != null)
    {
        // enable jaypatch
        SetConVarInt(jay_backtrack_enable, 1);
        // clamp jaypatch to sane values
        SetConVarInt(jay_backtrack_tolerance, Math_Clamp(GetConVarInt(jay_backtrack_tolerance), 0, 1));
    }
    // get rid of any possible exploits by using teleporters and fov
    SetConVarInt(FindConVar("tf_teleporter_fov_start"), 90);
    SetConVarFloat(FindConVar("tf_teleporter_fov_time"), 0.0);
}

public Action checkNativesEtc(Handle timer)
{
    // check sv cheats
    if (GetConVarBool(FindConVar("sv_cheats")))
    {
        SetFailState("[StAC] sv_cheats set to 1! Aborting!");
    }
    // check natives!
    if (GetFeatureStatus(FeatureType_Native, "Steam_IsConnected") == FeatureStatus_Available)
    {
        STEAMTOOLS = true;
    }
    if (GetFeatureStatus(FeatureType_Native, "SteamWorks_IsConnected") == FeatureStatus_Available)
    {
        STEAMWORKS = true;
    }
    if (GetFeatureStatus(FeatureType_Native, "SBPP_BanPlayer") == FeatureStatus_Available)
    {
        SOURCEBANS = true;
    }
    if (CommandExists("gb_ban"))
    {
        GBANS = true;
    }
    if (CommandExists("sm_aimplot"))
    {
        AIMPLOTTER = true;
    }

    if (DEBUG)
    {
        LogMessage
        (
            "\nSTEAMTOOLS = %i\nSTEAMWORKS = %i\nSOURCEBANS = %i\nGBANS = %i",
            STEAMTOOLS,
            STEAMWORKS,
            SOURCEBANS,
            GBANS
        );
    }
}

public Action checkEveryone(Handle timer)
{
    QueryEverythingAllClients();
}

public Action ForceCheckAll(int client, int args)
{
    QueryEverythingAllClients();
}

public Action ShowDetections(int callingCl, int args)
{
    if (callingCl != 0)
    {
        ReplyToCommand(callingCl, "Check your console!");
    }
    PrintToConsole(callingCl, "\n[StAC] == CURRENT DETECTIONS == ");
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        if (IsValidClient(Cl))
        {
            if
            (
                   turnTimes[Cl]           >= 1
                || aimsnapDetects[Cl]      >= 1
                || pSilentDetects[Cl]      >= 1
                || fakeAngDetects[Cl]      >= 1
                || bhopConsecDetects[Cl]   >= 1
                || cmdnumSpikeDetects[Cl]  >= 1
            )
            {
                PrintToConsole(callingCl, "Detections for %L", Cl);
                if (turnTimes[Cl] >= 1)
                {
                    PrintToConsole(callingCl, "- %i turn bind frames for %N", turnTimes[Cl], Cl);
                }
                if (aimsnapDetects[Cl] >= 1)
                {
                    PrintToConsole(callingCl, "- %i aimsnap detections for %N", aimsnapDetects[Cl], Cl);
                }
                if (pSilentDetects[Cl] >= 1)
                {
                    PrintToConsole(callingCl, "- %i silent aim detections for %N", pSilentDetects[Cl], Cl);
                }
                if (fakeAngDetects[Cl] >= 1)
                {
                    PrintToConsole(callingCl, "- %i fake angle detections for %N", fakeAngDetects[Cl], Cl);
                }
                if (bhopConsecDetects[Cl] >= 1)
                {
                    PrintToConsole(callingCl, "- %i consecutive bhop strings for %N", bhopConsecDetects[Cl], Cl);
                }
                if (cmdnumSpikeDetects[Cl] >= 1)
                {
                    PrintToConsole(callingCl, "- %i cmdnum spikes for %N", cmdnumSpikeDetects[Cl], Cl);
                }
            }
        }
    }
    PrintToConsole(callingCl, "[StAC] == END DETECTIONS == \n");
}

public void OnPluginEnd()
{
    StacLog("[StAC] Plugin vers. ---- %s ---- unloaded", PLUGIN_VERSION);
    NukeTimers();
    OnMapEnd();
}

// reseed random server seed to help prevent certain nospread stuff from working
// this does not fix lmaobox's nospread, as it uses an essentially undetectable viewangle (maybe time based?) based method to remove spread
void ActuallySetRandomSeed()
{
    int seed = GetURandomInt();
    if (DEBUG)
    {
        StacLog("[StAC] setting random server seed to %i", seed);
    }
    SetRandomSeed(seed);
}

// NUKE the client timers from orbit on plugin and map reload
void NukeTimers()
{
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        // delete QueryTimer[Cl];
        if (QueryTimer[Cl] != null)
        {
            if (DEBUG)
            {
                StacLog("[StAC] Destroying timer for %L", Cl);
            }
            CloseHandle(QueryTimer[Cl]);
            QueryTimer[Cl] = null;
        }
    }
    // delete TriggerTimedStuffTimer;
    if (TriggerTimedStuffTimer != null)
    {
        if (DEBUG)
        {
            StacLog("[StAC] Destroying reseeding timer");
        }
        CloseHandle(TriggerTimedStuffTimer);
        TriggerTimedStuffTimer = null;
    }
}

// recreate the timers we just nuked
void ResetTimers()
{
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        if (IsValidClient(Cl))
        {
            int userid = GetClientUserId(Cl);

            if (DEBUG)
            {
                StacLog("[StAC] Creating timer for %L", Cl);
            }
            // lets make a timer with a random length between stac_min_randomcheck_secs and stac_max_randomcheck_secs
            QueryTimer[Cl] =
            CreateTimer
            (
                GetRandomFloat
                (
                    minRandCheckVal,
                    maxRandCheckVal
                ),
                Timer_CheckClientConVars,
                userid
            );
        }
    }
    // create timer to reset seed every 15 mins
    TriggerTimedStuffTimer = CreateTimer(900.0, timer_TriggerTimedStuff, _, TIMER_REPEAT);
}

public Action eRoundStart(Handle event, char[] name, bool dontBroadcast)
{
    DoTPSMath();
    // might as well do this here!
    ActuallySetRandomSeed();
}

public Action ePlayerSpawned(Handle event, char[] name, bool dontBroadcast)
{
    int Cl = GetClientOfUserId(GetEventInt(event, "userid"));
    if (IsValidClient(Cl))
    {
        timeSinceSpawn[Cl] = GetEngineTime();
    }
}

Action hOnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
    // get ent classname AKA the weapon name
    if (!IsValidEntity(weapon) || weapon <= 0)
    {
        return Plugin_Continue;
    }
    GetEntityClassname(weapon, hurtWeapon[attacker], 256);
    // get distance between attacker and victim
    float distance = GetVectorDistance(clpos[0][attacker], clpos[0][victim]);
    if
    (
        // player didn't hurt self
           victim != attacker
        // weapon is hitscan
        && isWeaponHitscan(hurtWeapon[attacker])
        // players are at least 400 hu apart
        && distance >= 400.0
    )
    {
        timeSinceDidHurt[attacker] = GetEngineTime();
        return Plugin_Continue;
    }
    return Plugin_Continue;
}

public Action TF2_OnPlayerTeleport(int Cl, int teleporter, bool& result)
{
    if (IsValidClient(Cl))
    {
        timeSinceTeled[Cl] = GetEngineTime();
    }
}

public void TF2_OnConditionAdded(int Cl, TFCond condition)
{
    if (IsValidClient(Cl))
    {
        if (condition == TFCond_Taunting)
        {
            playerTaunting[Cl] = true;
        }
        else if (IsHalloweenCond(condition))
        {
            playerInBadCond[Cl]++;
        }
    }
}

public void TF2_OnConditionRemoved(int Cl, TFCond condition)
{
    if (IsValidClient(Cl))
    {
        if (condition == TFCond_Taunting)
        {
            timeSinceTaunt[Cl] = GetEngineTime();
            playerTaunting[Cl] = false;
        }
        else if (IsHalloweenCond(condition))
        {
            if (playerInBadCond[Cl] > 0)
            {
                playerInBadCond[Cl]--;
            }
        }
    }
}

public Action timer_TriggerTimedStuff(Handle timer)
{
    ActuallySetRandomSeed();
}

void DoTPSMath()
{
    tickinterv = GetTickInterval();
    tps = Pow(tickinterv, -1.0);

    // we have to adjust bhop stuff for tickrate - ignore past 200
    // you can bhop easier on higher tick
    // 66 = default, 133 = * 2, 200 = * 3

    // thanks to joined senses for some cleanup
    if (tps > 210.0 || tps < 60.0)
    {
        bhopmult = 0.0;
    }
    else if (tps >= 195.0)
    {
        bhopmult = 2.0;
    }
    else if (tps >= 165.0)
    {
        bhopmult = 1.75;
    }
    else if (tps >= 99.0)
    {
        bhopmult = 1.5;
    }
    else
    {
        bhopmult = 1.0;
    }

    maxBhopDetectionsScaled = RoundFloat(bhopmult * maxBhopDetections);

    if (maxBhopDetections == 0)
    {
        maxBhopDetectionsScaled = RoundFloat(bhopmult * 10);
    }

    if (DEBUG)
    {
        StacLog("tickinterv %f, tps %f, bhopmult %.2f, maxBhopDetectionsScaled %i", tickinterv, tps, bhopmult, maxBhopDetectionsScaled);
    }
}

public void OnMapStart()
{
    OpenStacLog();
    ActuallySetRandomSeed();
    DoTPSMath();
    ResetTimers();
    if (optimizeCvars)
    {
        RunOptimizeCvars();
    }
    timeSinceMapStart = GetEngineTime();
}

public void OnMapEnd()
{
    ActuallySetRandomSeed();
    DoTPSMath();
    NukeTimers();
    CloseStacLog();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

void ClearClBasedVars(int userid)
{
    // get fresh cli id
    int Cl = GetClientOfUserId(userid);
    // clear all old values for cli id based stuff
    turnTimes               [Cl] = 0;
    fovDesired              [Cl] = 0;
    fakeAngDetects          [Cl] = 0;
    aimsnapDetects          [Cl] = -1; // set to -1 to ignore first detections, as theyre most likely junk
    pSilentDetects          [Cl] = -1; // ^
    bhopDetects             [Cl] = -1; // set to -1 to ignore single jumps
    cmdnumSpikeDetects      [Cl] = 0;
    isConsecStringOfBhops   [Cl] = false;
    bhopConsecDetects       [Cl] = 0;
    settingsChangesFor      [Cl] = 0;

    // TIME SINCE LAST ACTION PER CLIENT
    timeSinceSpawn          [Cl] = 0.0;
    timeSinceTaunt          [Cl] = 0.0;
    timeSinceTeled          [Cl] = 0.0;
    // STORED BUTTONS PER CLIENT
    buttonsPrev             [Cl] = 0;
    // STORED GRAVITY STATE PER CLIENT
    highGrav                [Cl] = false;
    // STORED MISC VARS PER CLIENT
    playerTaunting          [Cl] = false;
    playerInBadCond         [Cl] = 0;
    userBanQueued           [Cl] = false;
    // STORED SENS PER CLIENT
    sensFor                 [Cl] = 0.0;

    // time since player did damage, for aimsnap check
    timeSinceDidHurt        [Cl] = 0.0;

    // don't bother clearing arrays
}

public void OnClientPutInServer(int Cl)
{
    int userid = GetClientUserId(Cl);

    if (IsValidClientOrBot(Cl))
    {
        SDKHook(Cl, SDKHook_OnTakeDamage, hOnTakeDamage);
    }
    if (IsValidClient(Cl))
    {
        // clear per client values
        ClearClBasedVars(userid);
        // clear timer
        QueryTimer[Cl] = null;
        // query convars on player connect
        if (DEBUG)
        {
            StacLog("[StAC] %N joined. Checking cvars", Cl);
        }
        QueryTimer[Cl] = CreateTimer(0.1, Timer_CheckClientConVars, userid);
        // wait 5 seconds just in case
        CreateTimer(5.0, CheckAuthOn, userid);
    }
}

Action CheckAuthOn(Handle timer, int userid)
{
    int Cl = GetClientOfUserId(userid);

    if (IsValidClient(Cl))
    {
        // don't bother checking if already authed and DEFINITELY don't check if steam is down or there's no way to do so thru an ext
        if (!IsClientAuthorized(Cl) && (isSteamAlive == 1))
        {
            PrintToImportant("Client %N isn't authorized and Steam is online. Checking in 5 seconds and kicking them if both are still true!", Cl);
            CreateTimer(5.0, Timer_checkAuth, userid);
        }
    }
}

Action Timer_checkAuth(Handle timer, int userid)
{
    int Cl = GetClientOfUserId(userid);
    if (!IsClientAuthorized(Cl) && (isSteamAlive == 1))
    {
        StacLog("[StAC] Kicking %N for not being authorized with Steam.", Cl);
        KickClient(Cl, "[StAC] Not authorized with Steam Network, please reconnect");
    }
}

public void OnClientDisconnect(int Cl)
{
    int userid = GetClientUserId(Cl);
    // clear per client values
    ClearClBasedVars(userid);
    // delete QueryTimer[Cl];
    if (QueryTimer[Cl] != null)
    {
        CloseHandle(QueryTimer[Cl]);
        QueryTimer[Cl] = null;
    }
}

// TODO: monitor server tickrate
//float gameEngineTime[2];
//float realTPS[2];
//float minTPS = 10000.0;
//public void OnGameFrame()
//{
//    gameEngineTime[1] = gameEngineTime[0];
//    gameEngineTime[0] = GetEngineTime();
//
//    realTPS[1] = realTPS[0];
//    realTPS[0] = 1/(gameEngineTime[0] - gameEngineTime[1]);
//
//    if (realTPS < (tps)
//}

/*
    in OnPlayerRunCmd, we check for:
    - CMDNUM SPIKES
    - SILENT AIM
    - AIM SNAPS
    - FAKE ANGLES
    - TURN BINDS
*/
public Action OnPlayerRunCmd
(
    int Cl,
    int& buttons,
    int& impulse,
    float vel[3],
    float angles[3],
    int& weapon,
    int& subtype,
    int& cmdnum,
    int& tickcount,
    int& seed,
    int mouse[2]
)
{
    // sanity check, don't let banned clients do anything!
    if (userBanQueued[Cl])
    {
        return Plugin_Handled;
    }

    // make sure client is real & not a bot - don't bother checking if so
    if (!IsValidClient(Cl))
    {
        return Plugin_Continue;
    }

    // originally from ssac - block invalid usercmds with invalid data
    if (cmdnum <= 0 || tickcount <= 0)
    {
        if (cmdnum < 0 || tickcount < 0)
        {
            KickClient(Cl, "%t", "invalidUsercmdData");
            return Plugin_Handled;
        }
        return Plugin_Continue;
    }

    // need this basically no matter what
    int userid = GetClientUserId(Cl);

    // set previous tick times to test lagginess (THANK YOU BACKWARDS FOR HELP WITH THIS)
    for (int i = 10; i > 0; --i)
    {
        engineTime[i][Cl] = engineTime[i-1][Cl];
    }
    engineTime[0][Cl] = GetEngineTime();


    // grab current time to compare to time since last spawn/taunt/tele
    // convert to percentages
    float loss = GetClientAvgLoss(Cl, NetFlow_Both) * 100.0;
    float choke = GetClientAvgChoke(Cl, NetFlow_Both) * 100.0;
    // convert to ms
    float ping = GetClientAvgLatency(Cl, NetFlow_Both) * 1000.0;

    // grab angles
    // thanks to nosoop from the sm discord for some help with this
    clangles[2][Cl] = clangles[1][Cl];
    clangles[1][Cl] = clangles[0][Cl];
    clangles[0][Cl][0] = angles[0];
    clangles[0][Cl][1] = angles[1];

    // grab cmdnum
    for (int i = 5; i > 0; --i)
    {
        clcmdnum[i][Cl] = clcmdnum[i-1][Cl];
    }
    clcmdnum[0][Cl] = cmdnum;


    // grab position
    clpos[1][Cl] = clpos[0][Cl];
    GetClientEyePosition(Cl, clpos[0][Cl]);

    // detect trigger teleports
    if (GetVectorDistance(clpos[0][Cl], clpos[1][Cl], false) > 500)
    {
        // reuse this variable
        timeSinceTeled[Cl] = GetEngineTime();
    }

    // R O U N D ( fuzzy psilent detection to detect lmaobox silent+ and better detect other forms of silent aim )
    float fuzzyClangles[3][2];

    fuzzyClangles[2][0] = RoundFloat(clangles[2][Cl][0] * 10.0) / 10.0;
    fuzzyClangles[2][1] = RoundFloat(clangles[2][Cl][1] * 10.0) / 10.0;
    fuzzyClangles[1][0] = RoundFloat(clangles[1][Cl][0] * 10.0) / 10.0;
    fuzzyClangles[1][1] = RoundFloat(clangles[1][Cl][1] * 10.0) / 10.0;
    fuzzyClangles[0][0] = RoundFloat(clangles[0][Cl][0] * 10.0) / 10.0;
    fuzzyClangles[0][1] = RoundFloat(clangles[0][Cl][1] * 10.0) / 10.0;


    // neither of these tests need fancy checks, so we do them first

    /*
        BHOP DETECTION - using lilac and ssac as reference, this one's better tho
    */
    // IGNORE IF HIGHER TICKRATE (AKA invalid bhop mult) as bhops become SIGNIFICANTLY easier for noncheaters on higher tickrates
    // don't run this check if cvar is -1
    if (maxBhopDetections != -1)
    {
        // get movement flags
        int flags = GetEntityFlags(Cl);

        // only check on not weirdo tickrate servers
        if (bhopmult >= 1.0 && bhopmult <= 2.0)
        {
            // reset their gravity if it's high!
            if (highGrav[Cl])
            {
                SetEntityGravity(Cl, 1.0);
                highGrav[Cl] = false;
            }

            if
            (
                // player didn't press jump
                !(
                    buttons & IN_JUMP
                )
                // player is on the ground
                &&
                (
                    flags & FL_ONGROUND
                )
            )
            // RESET COUNT!
            {
                // set to -1 to ignore single jumps, we ONLY want to count bhops
                bhopDetects[Cl] = -1;
                // count consecutive strings of bhops- a "consecutive string" is maxBhopDetectionsScaled or more
                // bhopmult is for higher tickrate servers
                if (isConsecStringOfBhops[Cl])
                {
                    bhopConsecDetects[Cl]++;
                    isConsecStringOfBhops[Cl] = false;
                    // print to admins if we get a consec detection
                    // i don't want to ban legits who are REALLY fucking good at real bhopping, so I removed the consec ban code for now
                    PrintToImportant("{hotpink}[StAC]{white} Player %N {mediumpurple}bhopped consecutively {yellow}%i{mediumpurple} or more times{white}!\nDetections so far: {palegreen}%i", Cl, maxBhopDetectionsScaled, bhopConsecDetects[Cl]);
                    StacLog("\n[StAC] Player %N bhopped consecutively %i or more times! Detections so far: %i", Cl, maxBhopDetectionsScaled, bhopConsecDetects[Cl]);
                }
            }
            // if a client didn't trigger the reset conditions above, they bhopped
            else if
            (
                // last input didn't have a jump - include to prevent legits holding spacebar from triggering detections
                !(
                    buttonsPrev[Cl] & IN_JUMP
                )
                &&
                // player pressed jump
                (
                    buttons & IN_JUMP
                )
                // they were on the ground when they pressed space
                &&
                (
                    flags & FL_ONGROUND
                )
            )
            {
                // increment bhops
                bhopDetects[Cl]++;

                // print to admin if halfway to getting banned - or halfway to default bhop amt ( 10 on 66.6 tps )
                if
                (
                    bhopDetects[Cl] >= RoundToFloor(maxBhopDetectionsScaled / 2.0)
                )
                {
                    PrintToImportant("{hotpink}[StAC]{white} Player %N {mediumpurple}bhopped{white}!\nConsecutive detections so far: {palegreen}%i" , Cl, bhopDetects[Cl]);
                    StacLog("\n[StAC] Player %N bhopped! Consecutive detections so far: %i" , Cl, bhopDetects[Cl]);
                }

                if (bhopDetects[Cl] >= maxBhopDetectionsScaled)
                {
                    isConsecStringOfBhops[Cl] = true;

                    // don't run antibhop if cvar is 0
                    if (maxBhopDetections > 0)
                    {
                        /* ANTIBHOP */
                        // set the player's gravity to 8x.
                        // if idiot cheaters keep holding their spacebar for an extra second and do 2 tick perfect bhops WHILE at 8x gravity...
                        // ...we will catch them autohopping and ban them!
                        SetEntityGravity(Cl, 8.0);
                        highGrav[Cl] = true;
                    }
                }
                // punish on maxBhopDetectionsScaled + 2 (for the extra TWO tick perfect bhops at 8x grav with no warning - no human can do this!)
                if (bhopDetects[Cl] >= (maxBhopDetectionsScaled + 2) && maxBhopDetections > 0)
                {
                    char reason[128];
                    Format(reason, sizeof(reason), "%t", "bhopBanMsg", bhopDetects[Cl]);
                    char pubreason[128];
                    Format(pubreason, sizeof(pubreason), "%t", "bhopBanAllChat", Cl, bhopDetects[Cl]);
                    return Plugin_Handled;
                }
            }
            buttonsPrev[Cl] = buttons;
        }
    }
    /*
        TURN BIND TEST
    */
    if
    (
        buttons & IN_LEFT
        ||
        buttons & IN_RIGHT
    )
    {
        if (maxAllowedTurnSecs != -1.0)
        {
            turnTimes[Cl]++;
            float turnSec = turnTimes[Cl] * tickinterv;
            PrintToImportant("%t", "turnbindAdminMsg", Cl, turnSec);

            if (turnSec < maxAllowedTurnSecs)
            {
                MC_PrintToChat(Cl, "%t", "turnbindWarnPlayer");
            }
            else if (turnSec >= maxAllowedTurnSecs)
            {
                KickClient(Cl, "%t", "turnbindKickMsg");
                MC_PrintToChatAll("%t", "turnbindAllChat", Cl);
                StacLog("%t", "turnbindAllChat", Cl);
            }
        }
    }

    // we have to do all these annoying checks to make sure we get as few false positives as possible.
    if
    (
        // make sure client is on a team & alive - spec cameras can cause fake angs!
           !IsClientPlaying(Cl)
        // ...isn't currently taunting - can cause fake angs!
        || playerTaunting[Cl]
        // ...didn't recently spawn - can cause invalid psilent detects
        || engineTime[0][Cl] - 1.0 < timeSinceSpawn[Cl]
        // ...didn't recently taunt - can (obviously) cause fake angs!
        || engineTime[0][Cl] - 1.0 < timeSinceTaunt[Cl]
        // ...didn't recently teleport - can cause psilent detects
        || engineTime[0][Cl] - 1.0 < timeSinceTeled[Cl]
        // don't touch if map or plugin just started - let the server framerate stabilize a bit
        || engineTime[0][Cl] - 1.0 < timeSinceMapStart
        // make sure client isn't timing out - duh
        || IsClientTimingOut(Cl)
        // this is just for halloween shit - plenty of halloween effects can and will mess up all of these checks
        || playerInBadCond[Cl] != 0
    )
    {
        return Plugin_Continue;
    }

    /*
        EYE ANGLES TEST
        if clients are outside of allowed angles in tf2, which are
          +/- 89.0 x (up / down)
          +/- 180 y (left / right, but we don't check this atm because there's things that naturally fuck up y angles, such as taunts)
          +/- 50 z (roll / tilt)
        while they are not in spec & on a map camera, we should log it.
        we would fix them but cheaters can just ignore server-enforced viewangle changes so there's no point

        these bounds were lifted from lilac. Thanks lilac.
        lilac patches roll, we do not, i think it (screen shake) is an important part of tf2,
        jtanz says that lmaobox can abuse roll so it should just be removed. i think both opinions are fine
    */
    if
    (
        // don't bother checking if fakeang detection is off
        maxFakeAngDetections != -1
        &&
        (
               angles[0] < -89.01
            || angles[0] > 89.01
            || angles[2] < -50.01
            || angles[2] > 50.01
        )
    )
    {
        fakeAngDetects[Cl]++;
        PrintToImportant
        (
            "{hotpink}[StAC]{white} Player %N has {mediumpurple}invalid eye angles{white}!\nCurrent angles: {mediumpurple}%.2f %.2f %.2f{white}.\nDetections so far: {palegreen}%i",
            Cl,
            angles[0],
            angles[1],
            angles[2],
            fakeAngDetects[Cl]
        );
        StacLog
        (
            "\n==========\n[StAC] Player %N has invalid eye angles!\nCurrent angles: %f %f %f.\nDetections so far: %i\n==========",
            Cl,
            angles[0],
            angles[1],
            angles[2],
            fakeAngDetects[Cl]
        );
        if (fakeAngDetects[Cl] >= maxFakeAngDetections && maxFakeAngDetections > 0)
        {
            char reason[128];
            Format(reason, sizeof(reason), "%t", "fakeangBanMsg", fakeAngDetects[Cl]);
            char pubreason[128];
            Format(pubreason, sizeof(pubreason), "%t", "fakeangBanAllChat", Cl, fakeAngDetects[Cl]);
            BanUser(userid, reason, pubreason);
            return Plugin_Handled;
        }
    }
    /*
        SILENT AIM DETECTION
        silent aim (in this context) works by aimbotting for 1 tick and then snapping your viewangle back to what it was
        example snap:
            L 03/25/2020 - 06:03:50: [stac.smx] [StAC] pSilent detection: angles0  angles: x 5.120096 y 9.763162
            L 03/25/2020 - 06:03:50: [stac.smx] [StAC] pSilent detection: angles1  angles: x 1.635611 y 12.876886
            L 03/25/2020 - 06:03:50: [stac.smx] [StAC] pSilent detection: angles2  angles: x 5.120096 y 9.763162
        we can just look for these snaps and log them as detections!
        note that this won't detect some snaps when a player is moving their strafe keys and mouse @ the same time while they are aimlocking.
        i'll *try* to work mouse movement into this function at SOME point but it works reasonably well for right now.
    */
    // we have to do EXTRA checks because a lot of things can fuck up silent aim detection
    // make sure ticks are sequential, hopefully avoid laggy players
    // example real detection:
    /*
        [StAC] pSilent / NoRecoil detection of 5.20° on <user>.
        Detections so far: 15
        User Net Info: 0.00% loss, 24.10% choke, 66.22 ms ping
         clcmdnum[0]: 61167
         clcmdnum[1]: 61166
         clcmdnum[2]: 61165
         angles0: x 8.82 y 127.68
         angles1: x 5.38 y 131.60
         angles2: x 8.82 y 127.68
    */
    if
    (
        // make sure client doesn't have invalid angles. "invalid" in this case means "any angle is 0.000000", usually caused by plugin / trigger based teleportation
        !HasValidAngles(Cl)
        // make sure client isnt using a spin bind
        || buttons & IN_LEFT
        || buttons & IN_RIGHT
        // make sure client doesn't have 2.5% or more packet loss - this would be annoying to play with for cheaters - but may be tweaked in the future if cheats decide to try to get around it
        || loss >= 2.5
        // make sure client doesn't have 52% or more choke - nullcore fakechoke goes up to 51!
        // we might not need to check this !! !
        //|| choke >= 52.0
        // if a client misses 8 ticks, its safe to assume they're lagging
        // so check the difference between the last 10 ticks
        // if a client missed any of the 10 server ticks by 8 ticks of time or more, don't check them
        || (engineTime[0][Cl] - engineTime[1][Cl])  >= (tickinterv*8.0)
        || (engineTime[1][Cl] - engineTime[2][Cl])  >= (tickinterv*8.0)
        || (engineTime[2][Cl] - engineTime[3][Cl])  >= (tickinterv*8.0)
        || (engineTime[3][Cl] - engineTime[4][Cl])  >= (tickinterv*8.0)
        || (engineTime[4][Cl] - engineTime[5][Cl])  >= (tickinterv*8.0)
        || (engineTime[5][Cl] - engineTime[6][Cl])  >= (tickinterv*8.0)
        || (engineTime[6][Cl] - engineTime[7][Cl])  >= (tickinterv*8.0)
        || (engineTime[7][Cl] - engineTime[8][Cl])  >= (tickinterv*8.0)
        || (engineTime[8][Cl] - engineTime[9][Cl])  >= (tickinterv*8.0)
        || (engineTime[9][Cl] - engineTime[10][Cl]) >= (tickinterv*8.0)
    )
    // if any of these things are true, don't check angles or cmdnum spikes
    {
        return Plugin_Continue;
    }

    /* cmdnum test, heavily modified from ssac */
    int spikeamt = abs(clcmdnum[1][Cl] - clcmdnum[0][Cl]);
    // 256 is a nice number but this could be raised or lowered, haven't done TOO much testing and so far zero legits have managed to trigger this since we ignore nullcmds.
    // this is for detecting when cheats "skip ahead" their cmdnum so they can (at my best guess) fire a "perfect shot" aka a shot with no spread
    if (spikeamt >= 256)
    {
        char heldWeapon[256];
        GetClientWeapon(Cl, heldWeapon, sizeof(heldWeapon));

        cmdnumSpikeDetects[Cl]++;
        PrintToImportant
        (
            "{hotpink}[StAC]{white} Cmdnum SPIKE of {yellow}%i{white} on %N.\nDetections so far: {palegreen}%i{white}.",
            spikeamt,
            Cl,
            cmdnumSpikeDetects[Cl]
        );
        StacLog
        (
            "\n[StAC] Cmdnum SPIKE of %i on %L.\nDetections so far: %i. Held weapon: %s",
            spikeamt,
            Cl,
            cmdnumSpikeDetects[Cl],
            heldWeapon
        );
        StacLog
        (
            "\nPrevious cmdnums:\n0 %i\n1 %i\n2 %i\n3 %i\n4 %i\n5 %i\n",
            clcmdnum[0][Cl],
            clcmdnum[1][Cl],
            clcmdnum[2][Cl],
            clcmdnum[3][Cl],
            clcmdnum[4][Cl],
            clcmdnum[5][Cl]
        );
        // punish if we reach limit set by cvar
        if (cmdnumSpikeDetects[Cl] >= maxCmdnumDetections && maxCmdnumDetections > 0)
        {
            char reason[128];
            Format(reason, sizeof(reason), "%t", "cmdnumSpikesBanMsg", cmdnumSpikeDetects[Cl]);
            char pubreason[128];
            Format(pubreason, sizeof(pubreason), "%t", "cmdnumSpikesBanAllChat", Cl, cmdnumSpikeDetects[Cl]);
            BanUser(userid, reason, pubreason);
            return Plugin_Handled;
        }
    }

    //if (clcmdnum[1][Cl] == clcmdnum[0][Cl])
    //{
    //    StacLog("[StAC] SAME CMDNUM REPORTED!!!");
    //    return Plugin_Handled;
    //}
    //if (clcmdnum[1][Cl] > clcmdnum[0][Cl])
    //{
    //    LogMessage("[StAC] cmdnum DROP of %i!", clcmdnum[1][Cl] - clcmdnum[0][Cl]);
    //    LogMessage("%i , %i", clcmdnum[1][Cl], clcmdnum[0][Cl]);
    //    cmdnum = cmdnum;
    //    //return Plugin_Handled;
    //}

    // we can reuse this for aimsnap as well!
    float aDiffReal = CalcAngDeg(clangles[0][Cl], clangles[1][Cl]);
    // refactored from smac - make sure we don't fuck up angles near the x/y axes!
    if (aDiffReal > 180.0)
    {
        aDiffReal = FloatAbs(aDiffReal - 360.0);
    }

    // is this a fuzzy detect or not
    int fuzzy = -1;
    // don't run this check if silent aim cvar is -1
    if (maxPsilentDetections != -1)
    {
        if
        (
            // so the current and 2nd previous angles match...
            (
                   clangles[0][Cl][0] == clangles[2][Cl][0]
                && clangles[0][Cl][1] == clangles[2][Cl][1]
            )
            &&
            // BUT the 1st previous (in between) angle doesnt?
            (
                   clangles[1][Cl][0] != clangles[0][Cl][0]
                && clangles[1][Cl][1] != clangles[0][Cl][1]
                && clangles[1][Cl][0] != clangles[2][Cl][0]
                && clangles[1][Cl][1] != clangles[2][Cl][1]
            )
        )
        {
            fuzzy = 0;
        }
        else if
        (
            // etc
            (
                   fuzzyClangles[0][0] == fuzzyClangles[2][0]
                && fuzzyClangles[0][1] == fuzzyClangles[2][1]
            )
            &&
            // etc
            (
                   fuzzyClangles[1][0] != fuzzyClangles[0][0]
                && fuzzyClangles[1][1] != fuzzyClangles[0][1]
                && fuzzyClangles[1][0] != fuzzyClangles[2][0]
                && fuzzyClangles[1][1] != fuzzyClangles[2][1]
            )
        )
        {
            fuzzy = 1;
        }
        //  ok - lets make sure there's a difference of at least 1 degree on either axis to avoid most fake detections
        //  these are probably caused by packets arriving out of order but i'm not a fucking network engineer (yet) so idk
        //  examples of fake detections we want to avoid:
        //      03/25/2020 - 18:18:11: [stac.smx] [StAC] pSilent detection on [redacted]: curang angles: x 14.871331 y 154.979812
        //      03/25/2020 - 18:18:11: [stac.smx] [StAC] pSilent detection on [redacted]: prev1  angles: x 14.901910 y 155.010391
        //      03/25/2020 - 18:18:11: [stac.smx] [StAC] pSilent detection on [redacted]: prev2  angles: x 14.871331 y 154.979812
        //  and
        //      03/25/2020 - 22:16:36: [stac.smx] [StAC] pSilent detection on [redacted2]: curang angles: x 21.516006 y -140.723709
        //      03/25/2020 - 22:16:36: [stac.smx] [StAC] pSilent detection on [redacted2]: prev1  angles: x 21.560007 y -140.943710
        //      03/25/2020 - 22:16:36: [stac.smx] [StAC] pSilent detection on [redacted2]: prev2  angles: x 21.516006 y -140.723709
        //  doing this might make it harder to detect legitcheaters but like. legitcheating in a 12 yr old dead game OMEGALUL who fucking cares
        if
        (
            (
                // needs to be more than a degree if not fuzzy
                aDiffReal >= 1.0 && fuzzy == 0
            )
            ||
            (
                // needs to be more 3 degrees if fuzzy - laggy players can trigger fuzzy detects below 3!
                aDiffReal >= 3.0 && fuzzy == 1
            )
        )
        {
            pSilentDetects[Cl]++;
            // have this detection expire in 10 minutes
            CreateTimer(600.0, Timer_decr_pSilent, userid, TIMER_FLAG_NO_MAPCHANGE);
            // first detection is LIKELY bullshit
            if (pSilentDetects[Cl] > 0)
            {
                // only print a bit in chat, rest goes to console (stv and admin and also the stac log)
                PrintToImportant
                (
                    "{hotpink}[StAC]{white} SilentAim detection of {yellow}%.2f{white}° on %N.\nDetections so far: {palegreen}%i{white}. fuzzy = {blue}%i",
                    aDiffReal,
                    Cl,
                    pSilentDetects[Cl],
                    fuzzy
                );
                StacLog
                (
                    "\n==========\n[StAC] SilentAim detection of %f° on \n%L.\nDetections so far: %i.\nfuzzy = %i",
                    aDiffReal,
                    Cl,
                    pSilentDetects[Cl],
                    fuzzy
                );
                StacLog
                (
                    "\nNetwork:\n %f loss\n %f choke\n %f ms ping\nAngles:\n angles0: x %f y %f\n angles1: x %f y %f\n angles2: x %f y %f\n",
                    loss,
                    choke,
                    ping,
                    clangles[0][Cl][0],
                    clangles[0][Cl][1],
                    clangles[1][Cl][0],
                    clangles[1][Cl][1],
                    clangles[2][Cl][0],
                    clangles[2][Cl][1]
                );
                StacLog
                (
                    "\nTime between last 5 client ticks (most recent first):\n1 %f\n2 %f\n3 %f\n4 %f\n5 %f\n==========",
                    engineTime[0][Cl] - engineTime[1][Cl],
                    engineTime[1][Cl] - engineTime[2][Cl],
                    engineTime[2][Cl] - engineTime[3][Cl],
                    engineTime[3][Cl] - engineTime[4][Cl],
                    engineTime[4][Cl] - engineTime[5][Cl]
                );

                if (AIMPLOTTER)
                {
                    ServerCommand("sm_aimplot #%i on", userid);
                }

                // BAN USER if they trigger too many detections
                if (pSilentDetects[Cl] >= maxPsilentDetections && maxPsilentDetections > 0)
                {
                    char reason[128];
                    Format(reason, sizeof(reason), "%t", "pSilentBanMsg", pSilentDetects[Cl]);
                    char pubreason[128];
                    Format(pubreason, sizeof(pubreason), "%t", "pSilentBanAllChat", Cl, pSilentDetects[Cl]);
                    BanUser(userid, reason, pubreason);
                    return Plugin_Handled;
                }
            }
        }
    }

    /*
        AIMSNAP DETECTION
        Now lets be fair here - this also detects silent aim a lot too, but it's more for checking plain snaps.
    */
    // only check if we actually did dmg with a hitscan weapon in the last 3(ish) ticks
    // in the future i want this to look ahead 3 ticks and behind 3 ticks - aka, if there was a snap within +/- 3 ticks, record it
    // currently it only looks behind
    // this could probably be done with requestframe 3 times and then just checking (timeSinceDidHurt[Cl] <= (tickinterv * 6)
    if
    (
        engineTime[0][Cl] - timeSinceDidHurt[Cl] <= (tickinterv * 3)
    )
    {
        if (aDiffReal >= 10.0)
        {
            // fun fact: we don't actually need to check sens, but it can help with filtering out false detects in logs
            //so far, i've not seen this get triggered very often though. */

            // init vars - weightedx and weightedy
            int wx;
            int wy;
            // TODO: MAKE SURE sensFor IS AS ACC AS POSSIBLE
            // scale mouse movement to sensitivity
            if (sensFor[Cl] != 0.0)
            {
                wx = abs(RoundFloat(mouse[0] * ( 1 / sensFor[Cl])));
                wy = abs(RoundFloat(mouse[1] * ( 1 / sensFor[Cl])));
            }
            // increment aimsnap detects
            aimsnapDetects[Cl]++;
            // have this detection expire in 10 minutes
            CreateTimer(600.0, Timer_decr_aimsnaps, userid, TIMER_FLAG_NO_MAPCHANGE);
            // first detection is, likely bullshit - this is copied from smac but in my genuine experience it's also true, and i can't really tell you why
            // because i don't fucking know
            if (aimsnapDetects[Cl] > 0)
            {
                PrintToImportant
                (
                    "{hotpink}[StAC]{white} Aimsnap detection of {yellow}%.2f{white}° on %N.\nDetections so far: {palegreen}%i{white}.",
                    aDiffReal,
                    Cl,
                    aimsnapDetects[Cl]
                );
                // etc
                StacLog
                (
                    "\n==========\n[StAC] Aimsnap detection of %f° on \n%L.\nDetections so far: %i.",
                    aDiffReal,
                    Cl,
                    aimsnapDetects[Cl]
                );
                StacLog
                (
                    "\nNetwork:\n %f loss\n %f choke\n %f ms ping\nAngles:\n angles0: x %f y %f\n angles1: x %f y %f\n",
                    loss,
                    choke,
                    ping,
                    clangles[0][Cl][0],
                    clangles[0][Cl][1],
                    clangles[1][Cl][0],
                    clangles[1][Cl][1]
                );
                StacLog
                (
                    "\nTime between last 5 client ticks (most recent first):\n 1 %f\n 2 %f\n 3 %f\n 4 %f\n 5 %f",
                    engineTime[0][Cl] - engineTime[1][Cl],
                    engineTime[1][Cl] - engineTime[2][Cl],
                    engineTime[2][Cl] - engineTime[3][Cl],
                    engineTime[3][Cl] - engineTime[4][Cl],
                    engineTime[4][Cl] - engineTime[5][Cl]
                );
                StacLog
                (
                    "\nUser Mouse Movement (weighted to sens): abs(x): %i, abs(y): %i\nUser Mouse Movement (unweighted): x: %i, y: %i.",
                    wx,
                    wy,
                    mouse[0],
                    mouse[1]
                );
                StacLog
                (
                    "Sens for client: %f\nWeapon used: %s\n==========",
                    sensFor[Cl],
                    hurtWeapon[Cl]
                );

                if (AIMPLOTTER)
                {
                    ServerCommand("sm_aimplot #%i on", userid);
                }

                // BAN USER if they trigger too many detections
                if (aimsnapDetects[Cl] >= maxAimsnapDetections && maxAimsnapDetections > 0)
                {
                    char reason[128];
                    Format(reason, sizeof(reason), "%t", "AimsnapBanMsg", aimsnapDetects[Cl]);
                    char pubreason[128];
                    Format(pubreason, sizeof(pubreason), "%t", "AimsnapBanAllChat", Cl, aimsnapDetects[Cl]);
                    BanUser(userid, reason, pubreason);
                    return Plugin_Handled;
                }
            }
        }
    }

    return Plugin_Continue;
}

public Action Timer_decr_aimsnaps(Handle timer, any userid)
{
    int Cl = GetClientOfUserId(userid);

    if (IsValidClient(Cl))
    {
        if (aimsnapDetects[Cl] > -1)
        {
            aimsnapDetects[Cl]--;
        }
        if (aimsnapDetects[Cl] <= 0)
        {
            if (AIMPLOTTER)
            {
                ServerCommand("sm_aimplot #%i off", userid);
            }
        }
    }
}

public Action Timer_decr_pSilent(Handle timer, any userid)
{
    int Cl = GetClientOfUserId(userid);

    if (IsValidClient(Cl))
    {
        if (pSilentDetects[Cl] > -1)
        {
            pSilentDetects[Cl]--;
        }
        if (pSilentDetects[Cl] <= 0)
        {
            if (AIMPLOTTER)
            {
                ServerCommand("sm_aimplot #%i off", userid);
            }
        }
    }
}


public Action Timer_decr_settingsChanges(Handle timer, any userid)
{
    int Cl = GetClientOfUserId(userid);

    if (IsValidClient(Cl))
    {
        if (settingsChangesFor[Cl] > 0)
        {
            settingsChangesFor[Cl]--;
        }
    }
}

char cvarsToCheck[][] =
{
    // misc vars
    "sensitivity",
    // possible cheat vars
    "cl_interpolate",
    // this is a useless check but we leave it here to set fov randomly to annoy cheaters
    "fov_desired",
};

public void ConVarCheck(QueryCookie cookie, int Cl, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    // make sure client is valid
    if (!IsValidClient(Cl))
    {
        return;
    }
    int userid = GetClientUserId(Cl);

    if (DEBUG)
    {
        StacLog("[StAC] Checked cvar %s value %s on %N", cvarName, cvarValue, Cl);
    }

    // log something about cvar errors
    if (result != ConVarQuery_Okay)
    {
        PrintToImportant("{hotpink}[StAC]{white} Could not query cvar %s on Player %N", Cl);
        StacLog("[StAC] Could not query cvar %s on player %N", cvarName, Cl);
        return;
    }

    if (StrEqual(cvarName, "sensitivity"))
    {
        sensFor[Cl] = StringToFloat(cvarValue);
    }

    /*
        POSSIBLE CHEAT VARS
    */
    // cl_interpolate (hidden cvar! should NEVER not be 1)
    else if (StrEqual(cvarName, "cl_interpolate"))
    {
        if (StringToInt(cvarValue) != 1)
        {
            if (banForMiscCheats)
            {
                char reason[128];
                Format(reason, sizeof(reason), "%t", "nolerpBanMsg");
                char pubreason[128];
                Format(pubreason, sizeof(pubreason), "%t", "nolerpBanAllChat", Cl);
                // we have to do extra bullshit here so we don't crash when banning clients out of this callback
                // make a pack
                DataPack pack = CreateDataPack();

                // prepare pack
                WritePackCell(pack, userid);
                WritePackString(pack, reason);
                WritePackString(pack, pubreason);

                ResetPack(pack, false);

                // make data timer
                CreateTimer(0.1, Timer_BanUser, pack, TIMER_DATA_HNDL_CLOSE);
                return;
            }
            else
            {
                PrintToImportant("{hotpink}[StAC]{white} [Detection] Player %L is using NoLerp!", Cl);
                StacLog("[StAC] [Detection] Player %L is using NoLerp!", Cl);
            }
        }
    }
    // fov check #1 (if u get banned by this you are a clown)
    else if (StrEqual(cvarName, "fov_desired"))
    {
        // save fov to var to reset later with netpropcheck
        fovDesired[Cl] = StringToInt(cvarValue);
        // check just in case
        if
        (
            fovDesired[Cl] < 20
            ||
            fovDesired[Cl] > 90
        )
        {
            if (banForMiscCheats)
            {
                char reason[128];
                Format(reason, sizeof(reason), "%t", "fovBanMsg");
                char pubreason[128];
                Format(pubreason, sizeof(pubreason), "%t", "fovBanAllChat", Cl);
                // we have to do extra bullshit here so we don't crash when banning clients out of this callback
                // make a pack
                DataPack pack = CreateDataPack();

                // prepare pack
                WritePackCell(pack, userid);
                WritePackString(pack, reason);
                WritePackString(pack, pubreason);

                ResetPack(pack, false);

                // make data timer
                CreateTimer(0.1, Timer_BanUser, pack, TIMER_DATA_HNDL_CLOSE);
                return;
            }
            else
            {
                PrintToImportant("{hotpink}[StAC]{white} [Detection] Player %L is using fov cheats!", Cl);
                StacLog("[StAC] [Detection] Player %L is using fov cheats!", Cl);
            }
        }
    }
}

// we wait a bit to prevent crashing the server when banning a player from a queryclientconvar callback
public Action Timer_BanUser(Handle timer, DataPack pack)
{
    int userid          = ReadPackCell(pack);
    char reason[128];
    ReadPackString(pack, reason, sizeof(reason));
    char pubreason[128];
    ReadPackString(pack, pubreason, sizeof(pubreason));

    // get client index out of userid
    int Cl              = GetClientOfUserId(userid);

    // check validity of client index
    if (IsValidClient(Cl))
    {
        BanUser(userid, reason, pubreason);
    }
}

// ban on invalid characters (newlines, carriage returns, etc)
public Action OnClientSayCommand(int Cl, const char[] command, const char[] sArgs)
{
    // don't pick up console or bots
    if (!IsValidClient(Cl))
    {
        return Plugin_Continue;
    }
    if
    (
        StrContains(sArgs, "\n", false) != -1
        ||
        StrContains(sArgs, "\r", false) != -1
    )
    {
        if (banForMiscCheats)
        {
            int userid = GetClientUserId(Cl);
            char reason[128];
            Format(reason, sizeof(reason), "%t", "newlineBanMsg");
            char pubreason[128];
            Format(pubreason, sizeof(pubreason), "%t", "newlineBanAllChat", Cl);
            BanUser(userid, reason, pubreason);
        }
        else
        {
            PrintToImportant("{hotpink}[StAC]{white} [Detection] Blocked newline print from player %L", Cl);
            StacLog("[StAC] [Detection] Blocked newline print from player %L", Cl);
        }
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

// block long commands - i don't know if this actually does anything but it makes me feel better
public Action OnClientCommand(int Cl, int args)
{
    if (IsValidClient(Cl))
    {
        // init var
        char ClientCommandChar[512];
        // gets the first command
        GetCmdArg(0, ClientCommandChar, sizeof(ClientCommandChar));
        // get length of string
        int len = strlen(ClientCommandChar);

        // is there more after this command?
        if (GetCmdArgs() > 0)
        {
            // add a space at the end of it
            ClientCommandChar[len++] = ' ';
            GetCmdArgString(ClientCommandChar[len++], sizeof(ClientCommandChar));
        }

        // clean it up ( PROBABLY NOT NEEDED )
        // TrimString(ClientCommandChar);

        if (DEBUG)
        {
            StacLog("[StAC] '%L' issued client side command '%s' - '%i' length.", Cl, ClientCommandChar, strlen(ClientCommandChar));
        }
        // total length CAN NOT be more than 254 char (from my own testing), first arg can't be more than 128 (from my own testing)
        if (strlen(ClientCommandChar) > 254 || len > 128)
        {
            StacLog("[StAC] '%L' issued client side command '%s' - '%i' length.", Cl, ClientCommandChar, strlen(ClientCommandChar));
            KickClient(Cl, "%t", "commandTooBig");
            return Plugin_Stop;
        }
    }
    return Plugin_Continue;
}

public void OnClientSettingsChanged(int Cl)
{
    // check for "too many client settings changes" cuz nullcore and lmaobox both spam this
    // although that might be a bug with them interacting with mastercomfig ?

    // ignore invalid clients and dead / in spec clients
    if (!IsValidClient(Cl) || !IsClientPlaying(Cl))
    {
        return;
    }
    // ignore if cvar says ignore
    if (maxSettingsChanges <= 0 || SettingsChangeWindow <= 0.0)
    {
        return;
    }

    // get userid for timer
    int userid = GetClientUserId(Cl);

    settingsChangesFor[Cl]++;
    // have this detection expire in 1 minute (default)
    CreateTimer(SettingsChangeWindow, Timer_decr_settingsChanges, userid, TIMER_FLAG_NO_MAPCHANGE);

    // notify admins if player is close to getting yeeted
    if (settingsChangesFor[Cl] > (maxSettingsChanges - 5))
    {
        PrintToImportant
        (
            "{hotpink}[StAC]{white} Player %N changed settings {yellow}%i{white} times within the last 60 seconds",
            Cl,
            settingsChangesFor[Cl]
        );
        StacLog
        (
            "[StAC] Player %N changed settings %i times within the last 60 seconds",
            Cl,
            settingsChangesFor[Cl]
        );
        if (settingsChangesFor[Cl] >= maxSettingsChanges)
        {
            MC_PrintToChatAll("%t", "settingsChangesSpamAllChat", Cl, settingsChangesFor[Cl], SettingsChangeWindow);
            StacLog("%t", "settingsChangesSpamAllChat", Cl, settingsChangesFor[Cl], SettingsChangeWindow);
            KickClient(Cl, "%t", "settingsChangesSpamKickMsg");
        }
    }
}

public void BanUser(int userid, char[] reason, char[] pubreason)
{
    int Cl = GetClientOfUserId(userid);

    if (userBanQueued[Cl])
    {
        return;
    }
    // make sure we dont detect on already banned players
    userBanQueued[Cl] = true;

    // check if client is authed before banning normally
    bool isAuthed = IsClientAuthorized(Cl);

    if (demonameInBanReason)
    {
        char tvStatus[512];
        char demoname[128];
        ServerCommandEx(tvStatus, sizeof(tvStatus), "tv_status");
        // if we found a match, there's a demo recording
        if (MatchRegex(demonameRegex, tvStatus))
        {
            if (GetRegexSubString(demonameRegex, 0, demoname, sizeof(demoname)))
            {
                ReplaceString(demoname, sizeof(demoname), "Recording to ", "");
                TrimString(demoname);
                StripQuotes(demoname);

                Format(demoname, sizeof(demoname), ". Demo file: %s", demoname);
                StrCat(reason, 256, demoname);
                StacLog("Reason: %s", reason);
            }
            else
            {
                StacLog("[StAC] No STV demo is being recorded, no demo name will be printed to the ban reason!");
            }
        }
        else
        {
            StacLog("[StAC] No STV demo is being recorded, no demo name will be printed to the ban reason!");
        }
    }

    // ext ban handlers
    if (SOURCEBANS || GBANS)
    {
        if (SOURCEBANS)
        {
            SBPP_BanPlayer(0, Cl, 0, reason);
        }
        if (GBANS)
        {
            ServerCommand("gb_ban %i, 0, %s", userid, reason);
        }
        // now lets check if that player was connected to steam
        if
        (
            !isAuthed
        )
        {
            PrintToImportant("{hotpink}[StAC]{white} Client %N is UNAUTHORIZED or STEAM IS DOWN!!! Banning by IP instead...", Cl);
            StacLog("Client %N is UNAUTHORIZED or STEAM IS DOWN!!! Banning by IP instead...", Cl);
            if (SOURCEBANS)
            {
                char ip[48];
                GetClientIP(Cl, ip, sizeof(ip));
                ServerCommand("sm_banip %s 0 %s", ip, reason);
            }
            else
            {
                BanClient(Cl, 0, BANFLAG_IP, reason, reason, _, _);
            }
        }
    }
    // default
    else
    {
        BanClient(Cl, 0, BANFLAG_AUTO, reason, reason, _, _);
    }
    MC_PrintToChatAll("%s", pubreason);
    StacLog("%s", pubreason);
}

// no longer just for netprops!
void NetPropEtcCheck(int userid)
{
    int Cl = GetClientOfUserId(userid);

    if (IsValidClient(Cl))
    {
        // there used to be an fov check here - but there's odd behavior that i don't want to work around regarding the m_iFov netprop.
        // sorry!

        // forcibly disables thirdperson with some cheats
        ClientCommand(Cl, "firstperson");
        if (DEBUG)
        {
            StacLog("[StAC] Executed firstperson command on Player %N", Cl);
        }
        // lerp check - we check the netprop
        // don't check if not default tickrate
        if (tps < 70.0 && tps > 60.0)
        {
            float lerp = GetEntPropFloat(Cl, Prop_Data, "m_fLerpTime") * 1000;
            if (DEBUG)
            {
                StacLog("%.2f ms interp on %N", lerp, Cl);
            }
            if
            (
                lerp < min_interp_ms && min_interp_ms != -1
                ||
                lerp > max_interp_ms && max_interp_ms != -1
            )
            {
                KickClient(Cl, "%t", "interpKickMsg", lerp, min_interp_ms, max_interp_ms);
                MC_PrintToChatAll("%t", "interpAllChat", Cl, lerp);
                StacLog("%t", "interpAllChat", Cl, lerp);
            }
        }
        if (IsClientPlaying(Cl))
        {
            // fix broken equip slots. Note: this was patched by valve but you can still equip invalid items...
            // ...just without the annoying unequipping other people's items part.
            // cathook is cringe
            // maybe one of these days i'll make this non-hardcoded and check for ANY item schema violation
            // not right now though

            // only check if player has 3 (or more, hello creators.tf) valid hats on
            if (TF2_GetNumWearables(Cl) >= 3)
            {
                int slot1wearable = TF2_GetWearable(Cl, 0);
                int slot2wearable = TF2_GetWearable(Cl, 1);
                int slot3wearable = TF2_GetWearable(Cl, 2);
                // check that the ents are valid and have the correct entprops
                if
                (
                       IsValidEntity(slot1wearable)
                    && IsValidEntity(slot2wearable)
                    && IsValidEntity(slot3wearable)
                    && HasEntProp(slot1wearable, Prop_Send, "m_iItemDefinitionIndex")
                    && HasEntProp(slot2wearable, Prop_Send, "m_iItemDefinitionIndex")
                    && HasEntProp(slot3wearable, Prop_Send, "m_iItemDefinitionIndex")
                )
                {
                    int slot1itemdef = GetEntProp(slot1wearable, Prop_Send, "m_iItemDefinitionIndex");
                    int slot2itemdef = GetEntProp(slot2wearable, Prop_Send, "m_iItemDefinitionIndex");
                    int slot3itemdef = GetEntProp(slot3wearable, Prop_Send, "m_iItemDefinitionIndex");
                    if
                    (
                        // frontline field recorder
                        (
                               slot1itemdef == 302
                            || slot2itemdef == 302
                            || slot3itemdef == 302
                        )
                        // gibus
                        &&
                        (
                               slot1itemdef == 940
                            || slot2itemdef == 940
                            || slot3itemdef == 940
                        )
                        &&
                        // skull topper
                        (
                               slot1itemdef == 941
                            || slot2itemdef == 941
                            || slot3itemdef == 941
                        )
                    )
                    {
                        if (banForMiscCheats)
                        {
                            char reason[128];
                            Format(reason, sizeof(reason), "%t", "badItemSchemaBanMsg");
                            char pubreason[128];
                            Format(pubreason, sizeof(pubreason), "%t", "badItemSchemaBanAllChat", Cl);
                            BanUser(userid, reason, pubreason);
                        }
                        else
                        {
                            PrintToImportant("{hotpink}[StAC]{white} [Detection] Player %L has an illegal item schema!", Cl);
                            StacLog("[StAC] [Detection] Player %L has an illegal item schema!", Cl);
                        }
                    }
                }
            }
        }
    }
}

/////////////////
// TIMER STUFF //
/////////////////

// timer for (re)checking ALL cvars and net props and everything else
public Action Timer_CheckClientConVars(Handle timer, int userid)
{
    // get actual client index
    int Cl = GetClientOfUserId(userid);
    // null out timer here
    QueryTimer[Cl] = null;
    if (IsValidClient(Cl))
    {
        if (DEBUG)
        {
            StacLog("[StAC] Checking client id, %i, %N", Cl, Cl);
        }
        // init variable to pass to QueryCvarsEtc
        int i;
        // query the client!
        QueryCvarsEtc(userid, i);
        // we just checked, but we want to check again eventually
        // lets make a timer with a random length between stac_min_randomcheck_secs and stac_max_randomcheck_secs
        QueryTimer[Cl] =
        CreateTimer
        (
            GetRandomFloat
            (
                minRandCheckVal,
                maxRandCheckVal
            ),
            Timer_CheckClientConVars,
            userid
        );
    }
}

// query all cvars and netprops for userid
void QueryCvarsEtc(int userid, int i)
{
    // get client index of userid
    int Cl = GetClientOfUserId(userid);
    // don't go no further if client isn't valid!
    if (IsValidClient(Cl))
    {
        // check cvars!
        if (i < sizeof(cvarsToCheck))
        {
            // make pack
            DataPack pack = CreateDataPack();
            // actually query the cvar here based on pos in convar array
            QueryClientConVar(Cl, cvarsToCheck[i], ConVarCheck);
            // increase pos in convar array
            i++;
            // prepare pack
            WritePackCell(pack, userid);
            WritePackCell(pack, i);
            // reset pack pos to 0
            ResetPack(pack, false);
            // make data timer
            CreateTimer(2.5, timer_QueryNextCvar, pack, TIMER_DATA_HNDL_CLOSE);
        }
        // we checked all the cvars!
        else
        {
            // now lets check some AC related netprops and other misc stuff
            NetPropEtcCheck(userid);
        }
    }
}

// timer for checking the next cvar in the list (waits a bit to balance out server load)
public Action timer_QueryNextCvar(Handle timer, DataPack pack)
{
    // read userid
    int userid = ReadPackCell(pack);
    // read i
    int i      = ReadPackCell(pack);

    // get client index out of userid
    int Cl     = GetClientOfUserId(userid);

    // check validity of client index
    if (IsValidClient(Cl))
    {
        QueryCvarsEtc(userid, i);
    }
}

// expensive!
void QueryEverythingAllClients()
{
    if (DEBUG)
    {
        StacLog("[StAC] Querying all clients");
    }
    // loop thru all clients
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        if (IsValidClient(Cl))
        {
            // get userid of this client index
            int userid = GetClientUserId(Cl);
            // init variable to pass to QueryCvarsEtc
            int i;
            // query the client!
            QueryCvarsEtc(userid, i);
        }
    }
}

////////////
// STONKS //
////////////

// Open log file for StAC
void OpenStacLog()
{
    // current date for log file (gets updated on map change to not spread out maps across files on date changes)
    char curDate[32];

    // get current date
    FormatTime(curDate, sizeof(curDate), "%m%d%y", GetTime());

    // init path
    char path[128];
    // set path
    BuildPath(Path_SM, path, sizeof(path), "logs/stac");

    // create directory if not extant
    if (!DirExists(path, false))
    {
        LogMessage("[StAC] StAC directory not extant! Creating...");
        // 511 = unix 775 ?
        if (!CreateDirectory(path, 511, false))
        {
            LogMessage("[StAC] StAC directory could not be created!");
        }
    }

    // set up the full path here
    Format(path, sizeof(path), "%s/stac_%s.log", path, curDate);

    // actually create file here
    StacLogFile = OpenFile(path, "at", false);
}

// Close log file for StAC
void CloseStacLog()
{
    // delete StacLogFile;
    if (StacLogFile != null)
    {
        if (DEBUG)
        {
            StacLog("[StAC] Closing StAC log file");
        }
        CloseHandle(StacLogFile);
        StacLogFile = null;
    }
}

// log to StAC log file
void StacLog(const char[] format, any ...)
{
    char buffer[254];
    VFormat(buffer, sizeof(buffer), format, 2);
    // clear color tags
    MC_RemoveTags(buffer, sizeof(buffer));

    if (StacLogFile != null)
    {
        LogToOpenFile(StacLogFile, buffer);
    }
    else
    {
        LogMessage("[StAC] File handle invalid!");
        LogMessage("%s", buffer);
    }
    PrintToConsoleAllAdmins("%s", buffer);
}

// i hope youre proud of me, 9th grade geometry teacher
float CalcAngDeg(const float array1[2], const float array2[2])
{
    float arDiff[2];
    arDiff[0] = array1[0] - array2[0];
    arDiff[1] = array1[1] - array2[1];
    return SquareRoot((arDiff[0] * arDiff[0]) + (arDiff[1] * arDiff[1]));
}

// IsValidClient stocks
bool IsValidClient(int client)
{
    return
    (
        (0 < client <= MaxClients)
        && IsClientInGame(client)
        && !IsClientInKickQueue(client)
        && !userBanQueued[client]
        && !IsFakeClient(client)
    );
}

bool IsValidClientOrBot(int client)
{
    return
    (
        (0 < client <= MaxClients)
        && IsClientInGame(client)
        && !IsClientInKickQueue(client)
        && !userBanQueued[client]
        // don't bother sdkhooking stv or replay bots lol
        && !IsClientSourceTV(client)
        && !IsClientReplay(client)
    );
}

// is client on a team and not dead
bool IsClientPlaying(int client)
{
    TFTeam team = TF2_GetClientTeam(client);
    if
    (
        IsPlayerAlive(client)
        &&
        (
            team != TFTeam_Unassigned
            &&
            team != TFTeam_Spectator
        )
    )
    {
        return true;
    }
    return false;
}

bool HasValidAngles(int Cl)
{
    if
    (
        // ignore weird angle resets in mge / dm
           clangles[0][Cl][0] == 0.0
        || clangles[0][Cl][1] == 0.0
        || clangles[1][Cl][0] == 0.0
        || clangles[1][Cl][1] == 0.0
        || clangles[2][Cl][0] == 0.0
        || clangles[2][Cl][1] == 0.0
    )
    {
        return false;
    }
    return true;
}

// print colored chat to all server/sourcemod admins
void PrintColoredChatToAdmins(const char[] format, any ...)
{
    char buffer[254];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && CheckCommandAccess(i, "sm_ban", ADMFLAG_GENERIC))
        {
            SetGlobalTransTarget(i);
            VFormat(buffer, sizeof(buffer), format, 2);
            MC_PrintToChat(i, "%s", buffer);
        }
    }
}

// print to important ppl on server
void PrintToImportant(const char[] format, any ...)
{
    char buffer[254];
    VFormat(buffer, sizeof(buffer), format, 2);
    PrintColoredChatToAdmins("%s", buffer);
    CPrintToSTV("%s", buffer);
}

// print to all server/sourcemod admin's consoles
void PrintToConsoleAllAdmins(const char[] format, any ...)
{
    char buffer[254];

    for (int i = 1; i <= MaxClients; i++)
    {
        if
        (
            (
                   IsClientInGame(i)
                && CheckCommandAccess(i, "sm_ban", ADMFLAG_GENERIC)
            )
            ||
            (
                IsClientConnected(i)
                && IsClientInGame(i)
                && IsClientSourceTV(i)
            )
        )
        {
            SetGlobalTransTarget(i);
            VFormat(buffer, sizeof(buffer), format, 2);
            PrintToConsole(i, "%s", buffer);
        }
    }
}

// adapted & deuglified from f2stocks
// Finds STV Bot to use for CPrintToSTV
int CachedSTV;
int FindSTV()
{
    if
    (
        !(
               CachedSTV >= 1
            && CachedSTV <= MaxClients
            && IsClientConnected(CachedSTV)
            && IsClientInGame(CachedSTV)
            && IsClientSourceTV(CachedSTV)
        )
    )
    {
        CachedSTV = -1;
        for (int client = 1; client <= MaxClients; client++)
        {
            if
            (
                   IsClientConnected(client)
                && IsClientInGame(client)
                && IsClientSourceTV(client)
            )
            {
                CachedSTV = client;
                break;
            }
        }
    }
    return CachedSTV;
}

// adapted & deuglified from f2stocks
// print to stv (now with color)
void CPrintToSTV(const char[] format, any ...)
{
    int stv = FindSTV();
    if (stv <= 0)
    {
        return;
    }
    char buffer[254];
    VFormat(buffer, sizeof(buffer), format, 2);
    MC_PrintToChat(stv, "%s", buffer);
}

// get entindx of player wearable, thanks scags
// https://github.com/Scags/The-Dump/blob/master/scripting/tfwearables.sp#L33-L40
int TF2_GetWearable(int client, int wearableidx)
{
    // 3540 linux
    // 3520 windows
    int offset = FindSendPropInfo("CTFPlayer", "m_flMaxspeed") - 20;
    Address m_hMyWearables = view_as< Address >(LoadFromAddress(GetEntityAddress(client) + view_as< Address >(offset), NumberType_Int32));
    return LoadFromAddress(m_hMyWearables + view_as< Address >(4 * wearableidx), NumberType_Int32) & 0xFFF;
}

int TF2_GetNumWearables(int client)
{
    // 3552 linux
    // 3532 windows
    int offset = FindSendPropInfo("CTFPlayer", "m_flMaxspeed") - 20 + 12;
    return GetEntData(client, offset);
}

any abs(any x)
{
   return x > 0 ? x : -x;
}

// check if this weapon is hitscan - yes i manually fucking created this list, shoot me
bool isWeaponHitscan(char weaponname[256])
{
    if
    (
    // multiclass shotgun
        StrEqual(weaponname, "tf_weapon_shotgun")
    // multiclass pistol
    ||  StrEqual(weaponname, "tf_weapon_pistol")
    // scout
    ||  StrEqual(weaponname, "tf_weapon_scattergun")
    ||  StrEqual(weaponname, "tf_weapon_handgun_scout_primary")
    ||  StrEqual(weaponname, "tf_weapon_soda_popper")
    ||  StrEqual(weaponname, "tf_weapon_pep_brawler_blaster")
    ||  StrEqual(weaponname, "tf_weapon_handgun_scout_secondary")
    // soldier
    ||  StrEqual(weaponname, "tf_weapon_shotgun_soldier")
    // pyro
    ||  StrEqual(weaponname, "tf_weapon_shotgun_pyro")
    // pootis
    ||  StrEqual(weaponname, "tf_weapon_minigun")
    ||  StrEqual(weaponname, "tf_weapon_shotgun_hwg")
    // engie
    ||  StrEqual(weaponname, "tf_weapon_shotgun_primary")
    ||  StrEqual(weaponname, "tf_weapon_sentry_revenge")
    // sniper
    ||  StrEqual(weaponname, "tf_weapon_sniperrifle")
    ||  StrEqual(weaponname, "tf_weapon_sniperrifle_decap")
    ||  StrEqual(weaponname, "tf_weapon_sniperrifle_classic")
    ||  StrEqual(weaponname, "tf_weapon_smg")
    ||  StrEqual(weaponname, "tf_weapon_charged_smg")
    // spy
    ||  StrEqual(weaponname, "tf_weapon_revolver")
    )
    {
        return true;
    }
    return false;
}


public void Steam_SteamServersConnected()
{
    isSteamAlive = 1;
    StacLog("[Steamtools] Steam connected.");
}
public void Steam_SteamServersDisconnected()
{
    isSteamAlive = 0;
    StacLog("[Steamtools] Steam disconnected.");
}

public void SteamWorks_SteamServersConnected()
{
    StacLog("[SteamWorks] Steam connected.");
    if (!STEAMTOOLS)
    {
        isSteamAlive = 1;
    }
}

public void SteamWorks_SteamServersDisconnected()
{
    StacLog("[SteamWorks] Steam disconnected.");
    if (!STEAMTOOLS)
    {
        isSteamAlive = 0;
    }
}

bool IsHalloweenCond(TFCond condition)
{
    if
    (
           condition == TFCond_HalloweenKart
        || condition == TFCond_HalloweenKartDash
        || condition == TFCond_HalloweenThriller
        || condition == TFCond_HalloweenBombHead
        || condition == TFCond_HalloweenGiant
        || condition == TFCond_HalloweenTiny
        || condition == TFCond_HalloweenInHell
        || condition == TFCond_HalloweenGhostMode
        || condition == TFCond_HalloweenKartNoTurn
        || condition == TFCond_HalloweenKartCage
        || condition == TFCond_SwimmingCurse
    )
    {
        return true;
    }
    return false;
}

// stolen from smlib
int Math_Clamp(int value, int min, int max)
{
    value = Math_Min(value, min);
    value = Math_Max(value, max);

    return value;
}

int Math_Min(int value, int min)
{
    if (value < min)
    {
        value = min;
    }

    return value;
}

int Math_Max(int value, int max)
{
    if (value > max)
    {
        value = max;
    }

    return value;
}