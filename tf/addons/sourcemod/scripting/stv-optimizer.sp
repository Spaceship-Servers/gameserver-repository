#include <sourcemod>
#include <dhooks>
#include <concolors>

const int TV_MAX_SNAPSHOT_RATE = 66;
const int TV_MAX_MAXRATE       = 0;

const int TV_MIN_SNAPSHOT_RATE = 1;
const int TV_MIN_MAXRATE       = 1;

int Offset_SetHibernateMsgCheck = -1;

ConVar tv_snapshotrate;
ConVar tv_maxrate;

GameData gd;

bool IS_HIBERNATING = false;

public void OnPluginStart()
{
    tv_snapshotrate = FindConVar("tv_snapshotrate");
    tv_maxrate      = FindConVar("tv_maxrate");

    HookConVarChange(tv_snapshotrate, tv_changed);
    HookConVarChange(tv_maxrate, tv_changed);

    DoGamedata();

    CreateTimer(2.5, Timer_ForceHiberCheck);
}

Action Timer_ForceHiberCheck(Handle timer)
{
    tv_changed(null, "", "");
    return Plugin_Continue;
}

void tv_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (IS_HIBERNATING)
    {
        STVOff();
    }
    else
    {
        STVOn();
    }
}

void DoGamedata()
{
    // Our base gamedata file
    gd = LoadGameConfigFile("stv-optimizer");
    if (!gd)
    {
        SetFailState("Failed to load stv-optimizer gamedata.");
        return;
    }

    /*
        Check Msg offset
    */
    {
        char func[64] = "Offset_SetHibernateMsgCheck";
        Offset_SetHibernateMsgCheck = GameConfGetOffset(gd, func);
        if (Offset_SetHibernateMsgCheck == -1)
        {
            SetFailState("Failed to get %s", func);
        }
        PrintToServer("Got %s!", func);
    }
    /*
        CGameServer::SetHibernating(CGameServer *this, bool a2)
    */
    {
        char func[64] = "CGameServer::SetHibernating";
        Handle SetHibernating = DHookCreateFromConf(gd, func);
        if (!SetHibernating)
        {
            SetFailState("Failed to setup detour for %s", func);
        }
        // hook
        if ( !DHookEnableDetour(SetHibernating, false, Hook_CGameServer__SetHibernating) )
        {
            SetFailState("Failed to detour %s.", func);
        }
        PrintToServer("%s detoured!", func);
    }
}


void STVOn()
{
    PrintToServer(ansi_cyan ... "[STV Optimizer] Setting STV to max values"... ansi_reset);

    SetConVarInt( tv_snapshotrate,   TV_MAX_SNAPSHOT_RATE );
    SetConVarInt( tv_maxrate,        TV_MAX_MAXRATE );
}

void STVOff()
{
    PrintToServer(ansi_cyan ... "[STV Optimizer] Setting STV to min values" ... ansi_reset);

    SetConVarInt( tv_snapshotrate,   TV_MIN_SNAPSHOT_RATE );
    SetConVarInt( tv_maxrate,        TV_MIN_MAXRATE );
}


public MRESReturn Hook_CGameServer__SetHibernating(Address pThis, DHookParam hParams)
{
    // bool
    bool a2 = DHookGetParam(hParams, 1);
    /*
        if ( *(this + 172628) != a2 )
        {
            v2 = "Server is hibernating\n";
            if ( !a2 )
            {
                v2 = "Server waking up from hibernation\n";
            }
            *(this + 172628) = a2;
            Msg(v2);

            ...
        }
    */

    // RUNS EVERY FRAME!
    if (!a2)
    {
        IS_HIBERNATING = false;
    }
    else
    {
        IS_HIBERNATING = true;
    }

    if ( LoadFromAddress(pThis + view_as<Address>(Offset_SetHibernateMsgCheck), NumberType_Int8 /* byte */) == a2 )
    {
        return MRES_Ignored;
    }

    // ONLY RUNS WHEN HIBERNATION STATUS CHANGES!
    if (!a2)
    {
        // Wake up
        // LogMessage("UN hibernating");
        STVOn();
    }
    else
    {
        // Go to bed
        // LogMessage("hibernating");
        STVOff();
    }

    return MRES_Ignored;
}
