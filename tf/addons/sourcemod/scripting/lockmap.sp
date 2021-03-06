#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
    name             =  "LockMap - Remove Objectives",
    author           =  "steph&nie",
    description      =  "Remove objectives from maps - made for Spaceship Servers, ported from SOAP-TF2DM",
    version          =  "0.0.5",
    url              =  "https://sappho.io"
}

char g_entIter[][] =
{
    "team_round_timer",
    "team_control_point_master",
    "team_control_point",
    "tf_logic_koth",
    "logic_auto",
    "logic_relay",
    "item_teamflag",
    "trigger_capture_area",
    "tf_logic_arena",
    "prop_dynamic",
    "team_control_point"
};

public void OnPluginStart()
{
    DoAllEnts()
}

// func to iterate thru all ents and act on them with DoEnt()
void DoAllEnts()
{
    // iterate thru list of entities to act on
    for (int i = 0; i < sizeof(g_entIter); i++)
    {
        // init variable
        int ent = -1;
        // does this entity exist?
        while ((ent = FindEntityByClassname(ent, g_entIter[i])) > 0)
        {
            if (IsValidEntity(ent) && ent > 0)
            {
                //LogMessage("ent %i found", ent);
                DoEnt(i, ent);
            }
        }
    }
}

// catch ents that spawn after map start / plugin load
public void OnEntityCreated(int entity, const char[] className)
{
    // iterate thru list of entities to act on
    for (int i = 0; i < sizeof(g_entIter); i++)
    {
        // does it match any of the ents?
        if (StrContains(className, g_entIter[i]) != -1)
        {
            if (IsValidEntity(entity))
            {
                int entref;
                if (entity < 0)
                {
                    entref = entity;
                }
                else
                {
                    entref = EntIndexToEntRef(entity);
                }
                // make pack
                DataPack pack = CreateDataPack();
                // prepare pack
                WritePackCell(pack, i);
                WritePackCell(pack, entref);
                // reset pack pos to 0
                ResetPack(pack, false);
                // pass it to request frame
                RequestFrame(WaitAFrame_DoEnt, pack);
                // break out of the loop
                break;
            }
        }
    }
}

void WaitAFrame_DoEnt(DataPack pack)
{
    // read i
    int i = ReadPackCell(pack);
    // read i
    int entref = ReadPackCell(pack);
    delete pack;

    int entity = EntRefToEntIndex(entref);
    if (!IsValidEntity(entity))
    {
        LogMessage("ent is invalid");
        return;
    }
    DoEnt(i, entity);
}

// act on the ents: requires iterator #  and entityid
DoEnt(int i, int entity)
{
    if (IsValidEntity(entity))
    {
        // remove arena logic (disabling doesn't properly disable the fight / spectate bullshit)
        if (StrContains(g_entIter[i], "tf_logic_arena", false) != -1)
        {
            RemoveEntity(entity);
        }
        // we don't remove / disable because both cause issues/bugs otherwise
        else if (StrContains(g_entIter[i], "trigger_capture", false) != -1)
        {
            TeleportEntity(entity, view_as<float>({0.0, 0.0, -5000.0}), NULL_VECTOR, NULL_VECTOR);
        }
        // yeet cap points
        else if (StrContains(g_entIter[i], "prop_dynamic") != -1)
        {
            char modelname[128];
            GetEntPropString(entity, Prop_Data, "m_ModelName", modelname, 128);
            if (StrContains(modelname, "cap_point_base") != -1)
            {
                RemoveEntity(entity);
            }
        }
        // yeet control point icons
        else if (StrContains(g_entIter[i], "team_control_point") != -1)
        {
            RemoveEntity(entity);
        }
        // disable every other found matching ent instead of deleting, deleting certain logic/team timer ents is unneeded and can crash servers
        else
        {
            AcceptEntityInput(entity, "Disable");
        }
    }
}
