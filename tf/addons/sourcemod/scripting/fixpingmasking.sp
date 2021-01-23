#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <regex>

Regex pingmaskRegex;

public Plugin myinfo =
{
	name 		= "Fix ping masking",
	author 		= "sappho",
	description = "Fix fake ping values for clients that are ping masking - originally from Steph's AntiCheat",
	version 	= "0.0.1"
};

public void OnPluginStart()
{
    // set up regex to find nonnumeric values
    pingmaskRegex = new Regex("^\\d*\\.?\\d*$");
    // get player resource entity
    int PlayerResourceEnt = GetPlayerResourceEntity();
    // hook it
    SDKHook(PlayerResourceEnt, SDKHook_ThinkPost, PlayerResource_OnThinkPost);
}

// this runs every 20ms (i think)
public void PlayerResource_OnThinkPost(int entity)
{
    // loop thru all clients
    for (int client = 1; client <= MaxClients; client++)
    {
        // don't check bots
        if (IsValidClient(client))
        {
            // get scoreboard ping
            int ping = GetEntProp(entity, Prop_Send, "m_iPing", _, client);

            // THIS SHOULD NEVER OCCUR, it is a sanity check
            if (ping > 999)
            {
                KickClient(client, "Your ping is too high - %i > 999", ping);
            }

            // cl_cmdrate needs to not have any non numerical chars (xcept the . sign if its a float) in it
            // otherwise player ping gets messed up on the scoreboard
            // set up char
            char char_cmdrate[8];
            // get actual value of cl cmdrate
            GetClientInfo(client, "cl_cmdrate", char_cmdrate, sizeof(char_cmdrate));
            // convert it to float
            float fl_cmdrate = StringToFloat(char_cmdrate);
            // check if client is masking
            if
            (
                // is their cmdrate fucked up?
                MatchRegex(pingmaskRegex, char_cmdrate) <= 0
                ||
                // is their cmdrate below optimal(ish) settings?
                fl_cmdrate < 60.0
                ||
                // is their ping messed up in some other way?
                ping < 5
            )
            {
                // clients want to see ping, not rtt, so slice it in half
                int newping = RoundToNearest((GetClientLatency(client, NetFlow_Both) * 1000) * 0.5);
                // set the scoreboard ping to our new value
                SetEntProp(entity, Prop_Send, "m_iPing", newping, client, _);
                // debug
                // LogMessage("Corrected client %N's ping. original ping: %i - new ping: %i", client, ping, newping);
            }
        }
    }
}

// IsValidClient Stock
bool IsValidClient(int client)
{
    return
    (
        (0 < client <= MaxClients)
        && IsClientInGame(client)
        && !IsFakeClient(client)
    );
}
