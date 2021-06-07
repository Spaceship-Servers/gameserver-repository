#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define maxip 4

public Plugin myinfo =
{
    name        = "Multiple Connect Blocker",
    author      = ".",
    description = "Block too many concurrent connections from the same IP address",
    version     = "0.0.1",
    url         = ""
};

public void OnClientPutInServer(int client)
{
    char clientIP[16];
    GetClientIP(client, clientIP, sizeof(clientIP));

    int sameip;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            char playersip[16];
            GetClientIP(i, playersip, sizeof(playersip));

            if (StrEqual(clientIP, playersip))
            {
                sameip++;
            }
        }
    }

    if (sameip > maxip)
    {
        KickClient(client, "Too many concurrent connections from your IP address!", maxip);
    }
}

bool IsValidClient(int client)
{
    return ((0 < client <= MaxClients) && IsClientInGame(client) && !IsFakeClient(client));
}
