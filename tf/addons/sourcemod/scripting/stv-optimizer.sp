#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <concolors>

public Plugin myinfo =
{
    name    = "SrcTV CPU Saver",
    author  = "sappho.io",
    version = "0.0.1"
}

int TV_MAX_SNAPSHOT_RATE = 66;
int TV_MAX_MAXRATE       = 0;
int TV_MAX_MAXCLIENTS    = 2;

int TV_MIN_SNAPSHOT_RATE = 1;
int TV_MIN_MAXRATE       = 1;
int TV_MIN_MAXCLIENTS    = 1;

public void OnConfigsExecuted()
{
    IsServerEmpty();
}

public void OnClientConnected(int client)
{
    IsServerEmpty();
}

public void OnClientDisconnect_Post(int client)
{
    IsServerEmpty();
}

bool IsServerEmpty()
{
    for (int Cl = 1; Cl <= MaxClients; Cl++)
    {
        if (IsValidClient(Cl))
        {
            STVOn();
            return;
        }
    }
    STVOff();
    return;
}

void STVOn()
{
    PrintToServer(ansi_cyan ... "[STV Optimizer] Setting STV to max values"... ansi_reset);
    SetConVarInt(FindConVar("tv_snapshotrate"), TV_MAX_SNAPSHOT_RATE);
    SetConVarInt(FindConVar("tv_maxrate"),      TV_MAX_MAXRATE);
    SetConVarInt(FindConVar("tv_maxclients"),   TV_MAX_MAXCLIENTS);
}

void STVOff()
{
    PrintToServer(ansi_cyan ... "[STV Optimizer] Setting STV to min values" ... ansi_reset);
    SetConVarInt(FindConVar("tv_snapshotrate"), TV_MIN_SNAPSHOT_RATE);
    SetConVarInt(FindConVar("tv_maxrate"),      TV_MIN_MAXRATE);
    SetConVarInt(FindConVar("tv_maxclients"),   TV_MIN_MAXCLIENTS);
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
