#include <sourcemod>
#include <autoexecconfig>

#define PLUGIN_VERSION  "0.0.1"

public Plugin myinfo =
{
    name             =  "dyn_idletime",
    author           =  "https://sappho.io",
    description      =  "Dynamicly scale max idle time based on number of players in the server",
    version          =   PLUGIN_VERSION,
    url              =  "https://sappho.io"
}

int clientCount = -1;

ConVar mp_idlemaxtime           = null;
ConVar sm_dyn_idletime_ratio    = null;
ConVar sm_dyn_idletime_mintime  = null;
ConVar sm_dyn_idletime_maxtime  = null;


public void OnPluginStart()
{
    mp_idlemaxtime = FindConVar("mp_idlemaxtime");
    if (!mp_idlemaxtime)
    {
        SetFailState("Couldn't find mp_idlemaxtime!");
    }

    CreateConVar
    (
        "sm_dyn_idletime_version",
        PLUGIN_VERSION,
        "dyn_idletime version",
        FCVAR_SPONLY | FCVAR_CHEAT
    );


    AutoExecConfig_SetFile("dyn_idletime");
    AutoExecConfig_SetCreateFile(true);

    sm_dyn_idletime_ratio =
    AutoExecConfig_CreateConVar
    (
        "sm_dyn_idletime_ratio",
        "1.25",
        "dyn_idletime scales mp_idlemaxtime by (maxclients / currentplayers) * this ratio. This means that as players go up, mp_idlemaxtime goes down.\n\
        Negative values scale with currentplayers directly, ignoring maxclients, meaning that as players go up, mp_idlemaxtime goes up.\n\
        This value can't be zero.",
        FCVAR_NONE
    );

    sm_dyn_idletime_mintime =
    AutoExecConfig_CreateConVar
    (
        "sm_dyn_idletime_mintime",
        "1",
        "Minimum amount (in minutes) that dyn_idletime will set mp_idlemaxtime to.",
        FCVAR_NONE
    );

    sm_dyn_idletime_maxtime =
    AutoExecConfig_CreateConVar
    (
        "sm_dyn_idletime_maxtime",
        "15",
        "Maximum amount (in minutes) that dyn_idletime will set mp_idlemaxtime to.",
        FCVAR_NONE
    );


    GetTheClientCount();
}

public void OnClientPutInServer(int client)
{
    GetTheClientCount();
}

public void OnClientDisconnect_Post(int client)
{
    GetTheClientCount();
}

void GetTheClientCount()
{
    clientCount = GetClientCount();
    SetIdleTime();
}

// #define DBG

void SetIdleTime()
{
    if (clientCount <= 0)
    {
        return;
    }
    int maxcli = MaxClients;

#if defined DBG
for (clientCount = 1; clientCount <= maxcli; clientCount++)
{
#endif
    float ratio_scale = sm_dyn_idletime_ratio.FloatValue;

    float clients_to_scale = 0.0;

    if (ratio_scale == 0.0)
    {
        SetFailState("Can't have a null ratio, sorry.");
    }
    // inverse scaling - clients go up, max idle time goes down
    else if (ratio_scale > 0.0)
    {
        clients_to_scale = float( maxcli / clientCount );
    }
    // direct scaling - clients go up, max idle time goes up
    else if (ratio_scale < 0.0)
    {
        clients_to_scale = float( clientCount );
    }

    // we only use the negative sign to determine if we're scaling inverse or direct - get rid of it
    ratio_scale = FloatAbs(ratio_scale);

    // scale the already scaled number of clients by our ratio to get our unclamped idletime value
    float idletime_preclamp = clients_to_scale * ratio_scale;

    // clamp idletime between min and max cvars, then round it
    int final_idletime =
    RoundFloat
    (
        clamp
        (
            idletime_preclamp,
            float(sm_dyn_idletime_mintime.IntValue),
            float(sm_dyn_idletime_maxtime.IntValue)
        )
    );

#if defined DBG
    LogMessage("max = %i, %i players = %i idle", maxcli, clientCount, final_idletime);
}
#else
    // set the actual convar
    SetConVarInt( mp_idlemaxtime, final_idletime );
#endif
}


any min(any a, any b)
{
    return (a < b ? a : b);
}

any max(any a, any b)
{
    return (a > b ? a : b);
}

any clamp(any clampval, any minval, any maxval)
{
    clampval =  max(clampval, minval);
    return      min(clampval, maxval);
}

// any lerp(any a, any b, any t)
// {
//     return (a + ( b - a ) * t);
// }
