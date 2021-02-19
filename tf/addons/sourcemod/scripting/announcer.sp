#pragma semicolon 1;
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name             = "Announcer Countdown",
    author           = "stephanie",
    description      = "Plugin for non objective based servers (like DM/MGE) to announce server timelimit",
    version          = "0.0.3",
    url              = "https://sappho.io"
}

static char soundstoCache[][] =
{
    "vo/announcer_ends_1sec.mp3",
    "vo/announcer_ends_2sec.mp3",
    "vo/announcer_ends_3sec.mp3",
    "vo/announcer_ends_4sec.mp3",
    "vo/announcer_ends_5sec.mp3",
    //"vo/announcer_ends_6sec.mp3",
    //"vo/announcer_ends_7sec.mp3",
    //"vo/announcer_ends_8sec.mp3",
    //"vo/announcer_ends_9sec.mp3",
    "vo/announcer_ends_10sec.mp3",
    //"vo/announcer_ends_20sec.mp3",
    "vo/announcer_ends_30sec.mp3",
    "vo/announcer_ends_60sec.mp3",
    //"vo/announcer_ends_2min.mp3",
    "vo/announcer_ends_5min.mp3"
};

public void OnPluginStart()
{
    CreateTimer(1.0, CheckMapTimeLeft, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(soundstoCache); i++)
    {
        PrecacheSound(soundstoCache[i]);
    }
}

public Action CheckMapTimeLeft(Handle timer)
{
    int timelimit;
    GetMapTimeLimit(timelimit);
    int totalsecs;
    GetMapTimeLeft(totalsecs);

    if (timelimit == 0 || totalsecs <= 0)
    {
        return Plugin_Handled;
    }

    int mins = totalsecs / 60;
    int secs = totalsecs % 60;

    //PrintToServer("Timeleft for current map: %i min %i sec", mins, secs);

    // minutes left
    if (mins > 1 && secs == 0)
    {
        char path[35];
        char soundName[28];
        Format(soundName, sizeof(soundName), "vo/announcer_ends_%dmin.mp3", mins);
        Format(path, sizeof(path), "sound/%s", soundName);

        if (FileExists(path, true))
        {
            for (int i = 0; i < sizeof(soundstoCache); i++)
            {
                if (StrEqual(soundName, soundstoCache[i]))
                {
                    EmitSoundToAll(soundName);
                }
            }
        }
    }
    // seconds left, including 60
    else if (totalsecs <= 60)
    {
        char path[35];
        char soundName[28];
        Format(soundName, sizeof(soundName), "vo/announcer_ends_%dsec.mp3", totalsecs);
        Format(path, sizeof(path), "sound/%s", soundName);

        if (FileExists(path, true))
        {
            for (int i = 0; i < sizeof(soundstoCache); i++)
            {
                if (StrEqual(soundName, soundstoCache[i]))
                {
                    EmitSoundToAll(soundName);
                }
            }
        }
    }

    return Plugin_Handled;
}
