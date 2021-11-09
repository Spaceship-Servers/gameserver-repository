#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <concolors>

public Plugin myinfo =
{
    name    = "SrcTV CPU Saver",
    author  = "sappho.io",
    version = "0.0.5"
}

int TV_MAX_SNAPSHOT_RATE = 66;
int TV_MAX_MAXRATE       = 0;

int TV_MIN_SNAPSHOT_RATE = 1;
int TV_MIN_MAXRATE       = 1;

bool STV_is_on;

ConVar tv_snapshotrate;
ConVar tv_maxrate;

public void OnPluginStart()
{
    tv_snapshotrate = FindConVar("tv_snapshotrate");
    tv_maxrate      = FindConVar("tv_maxrate");
}

public void OnConfigsExecuted()
{
    TV_MAX_SNAPSHOT_RATE    = tv_snapshotrate.IntValue;
    TV_MAX_MAXRATE          = tv_maxrate.IntValue;

    // This is needed to avoid bullshit with SizzlingStats/TFTrue changing stv values on map change
    CreateTimer(5.0, AvoidRaceCondition);
}

public void OnClientConnected(int client)
{
    IsServerEmpty();
}

public void OnClientDisconnect_Post(int client)
{
    IsServerEmpty();
}

Action AvoidRaceCondition(Handle timer)
{
    IsServerEmpty();
}

bool IsServerEmpty()
{
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        if (IsValidClient(Cl))
        {
            if (!STV_is_on)
            {
                STVOn();
            }
            return false;
        }
    }
    STVOff();
    return true;
}

void STVOn()
{
    STV_is_on = true;

    PrintToServer(ansi_cyan ... "[STV Optimizer] Setting STV to max values"... ansi_reset);

    SetConVarInt( tv_snapshotrate,   TV_MAX_SNAPSHOT_RATE );
    SetConVarInt( tv_maxrate,        TV_MAX_MAXRATE );
}

void STVOff()
{
    STV_is_on = false;

    PrintToServer(ansi_cyan ... "[STV Optimizer] Setting STV to min values" ... ansi_reset);

    SetConVarInt( tv_snapshotrate,   TV_MIN_SNAPSHOT_RATE );
    SetConVarInt( tv_maxrate,        TV_MIN_MAXRATE );

}

bool IsValidClient(int iClient)
{
    if (iClient <= 0 || iClient > MaxClients || !IsClientConnected(iClient))
    {
        return false;
    }
    if (IsClientSourceTV(iClient) || IsClientReplay(iClient))
    {
        return false;
    }
    return true;
}
