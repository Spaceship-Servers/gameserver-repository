#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <morecolors>

// THIS PLUGIN IS ROUGHLY BASED ON THIS PLUGIN - http://forums.alliedmods.net/showthread.php?t=189956
public Plugin myinfo =
{
    name        = "Rough Sourcemod AimPlotter",
    author      = "MitchDizzle_, steph&nie",
    description = "Show where client is aiming - for spotting cheaters!",
    version     = "0.0.3",
    url         = "https://sappho.io"
}

float LastLaser[MAXPLAYERS+1][3];
bool LaserE[MAXPLAYERS+1];
int g_sprite;

public void OnPluginStart()
{
    // need to load this or the targeting stuff doesn't work
    LoadTranslations("common.phrases");
    // only admins should have access to this!
    RegAdminCmd("sm_aimplot", togglelaser, ADMFLAG_BAN);
}

// precache the laser sprite
public void OnMapStart()
{
    g_sprite = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public Action togglelaser(int client, int args)
{
    if (args < 1 || args > 2)
    {
        MC_ReplyToCommand(client, "{white}Usage: sm_laser {darkgray}<client> [on/off]\n{white}Toggles if \"on\" or \"off\" isn't specified.");
    }
    else
    {
        // init first arg
        char arg1[32];
        // get client name
        GetCmdArg(1, arg1, sizeof(arg1));
        // init second arg
        char arg2[8];
        // get on/off string
        GetCmdArg(2, arg2, sizeof(arg2));

        // -1 = toggle, 0 = turn off, 1 = turn on
        int offon = -1;
        if (StrContains(arg2, "off", false) != -1)
        {
            offon = 0;
        }
        else if ((StrContains(arg2, "on", false) != -1))
        {
            offon = 1;
        }
        // init vars for targeting users
        char target_name[MAX_TARGET_LENGTH];
        int target_list[MAXPLAYERS];
        int target_count;
        bool tn_is_ml;

        // target users!
        if
        (
            (
                target_count = ProcessTargetString
                (
                    arg1,
                    client,
                    target_list,
                    MAXPLAYERS,
                    COMMAND_FILTER_NO_IMMUNITY,
                    target_name,
                    sizeof(target_name),
                    tn_is_ml
                )
            )
            // we can't find any!
            <= 0
        )
        {
            ReplyToTargetError(client, target_count);
            return Plugin_Handled;
        }

        // loop thru found targets
        for (int i = 0; i < target_count; i++)
        {
            // assign current target to a more readable variable
            int targetclient = target_list[i];
            // are they a real target?
            if (IsValidClientOrBot(targetclient))
            {
                // toggle
                if (offon == -1)
                {
                    LaserE[targetclient] = !LaserE[targetclient];
                }
                // off
                else if (offon == 0)
                {
                    LaserE[targetclient] = false;
                }
                // on
                else if (offon == 1)
                {
                    LaserE[targetclient] = true;
                }
            }
        }
    }

    return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
    LaserE[client] = false;
}

// color defines
int red[4]   = {255,000,000,100};
int white[4] = {255,255,255,100};

// runs every second, might be better in OnGameFrame ? not sure
public Action OnPlayerRunCmd
(
    int client,
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
    // if the laser isn't enabled, null it
    if (!LaserE[client])
    {
        // only null it if it aint already null
        if (!IsNullVector(LastLaser[client]))
        {
            LastLaser[client] = NULL_VECTOR;
        }
        return Plugin_Continue;
    }

    float pos[3];
    if (IsClientInGame(client) && LaserE[client] && IsPlayerAlive(client))
    {
        TraceEye(client, pos);
        if (GetVectorDistance(pos, LastLaser[client]) > 0.5)
        {
            // might color it team colors, white if mouse 1, black if player did damage, but i'll do that later if ever.
            // for now:
            // if the user is pressing m1 color the beam red
            if (buttons & IN_ATTACK)
            {
                SetUpLaser(LastLaser[client], pos, red);
            }
            // otherwise, color it white
            else
            {
                SetUpLaser(LastLaser[client], pos, white);
            }
            LastLaser[client] = pos;
        }
    }
    return Plugin_Continue;
}

// set up the laser sprite
void SetUpLaser(float start[3], float end[3], int color[4])
{
    TE_SetupBeamPoints
    (
        start,      // startpos
        end,        // endpos
        g_sprite,   // precached model index
        0,          // precached model index for halo
        0,          // startframe
        0,          // framerate
        1.0,        // lifetime
        1.0,        // starting width
        1.0,        // ending width
        0,          // fade time duration
        0.0,        // amplitude
        color,      // color
        0           // beam speed
    );
    TE_SendToAdminsAndSTV();
}

// trace 200 units in front of the player, if we hit something before then, trace over top of it
void TraceEye(int client, float pos[3])
{
    float angles[3];
    float origin[3];
    float angvec[3];
    float newpos[3];

    // get clients eye position
    GetClientEyePosition(client, origin);
    // get where the client is looking
    GetClientEyeAngles(client, angles);
    // convert angles to being in front of the user (? no idea)
    GetAngleVectors(angles, angvec, NULL_VECTOR, NULL_VECTOR);
    // scale the angles 200 units
    ScaleVector(angvec, 200.0);
    // add em
    AddVectors(origin, angvec, newpos);
    // trace with a filter to ignore teammates and ourselves !
    TR_TraceRayFilter(origin, newpos, MASK_VISIBLE, RayType_EndPoint, TraceEntityFilterPlayer, client);
    // if we hit something, set pos to where we hit
    if (TR_DidHit())
    {
        TR_GetEndPosition(pos);
    }
    // otherwise, set pos to 200 units in front of us, aka newpos
    else
    {
        pos = newpos;
    }
}

// draw over clients on the other team, don't draw over teammates
public bool TraceEntityFilterPlayer(int entity, int contentsMask, int client)
{
    // don't trace on ourselves!
    if (entity == client)
    {
        return false;
    }

    // trace on the world ALWAYS
    if (entity == 0)
    {
        return true;
    }

    // we ran into an entity. are they a client?
    if (IsValidClientOrBot(entity))
    {
        // yeah, theyre a client. what team are they on?
        int clientTeam  = GetClientTeam(client);
        int entTeam     = GetClientTeam(entity);
        // are they on our team? if so, don't draw on them, keep tracing thru them!
        if (clientTeam == entTeam)
        {
            return false;
        }
        // if they're an enemy gamer, draw on top of them!
        else
        {
            return true;
        }
    }
    // don't know what this entity is - ignore it!
    return false;
}

// is valid client stock
bool IsValidClientOrBot(int client)
{
    return
    (
        (0 < client <= MaxClients)
        && IsClientInGame(client)
        && !IsClientInKickQueue(client)
        // don't bother with stv or replay bots lol
        && !IsClientSourceTV(client)
        && !IsClientReplay(client)
    );
}

// duh
void TE_SendToAdminsAndSTV()
{
    int total = 0;
    int[] clients = new int[MaxClients];

    int stv = FindSTV();

    for (int i = 1; i <= MaxClients; i++)
    {
        if
        (
            IsClientInGame(i)
            &&
            (
                CheckCommandAccess(i, "sm_ban", ADMFLAG_GENERIC)
                ||
                stv == i
            )
        )
        {
            clients[total++] = i;
        }
    }
    TE_Send(clients, total);
}

// adapted & deuglified from f2stocks
// Finds STV Bot
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
