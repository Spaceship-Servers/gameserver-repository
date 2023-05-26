#pragma semicolon 1
#pragma tabsize 4
#pragma newdecls required

#include <sourcemod>
#include <tf2attributes>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <sdktools>
#include <sdkhooks>

ConVar g_Cvar_Enabled;
ConVar g_Cvar_FFADM;
ConVar g_Cvar_NoFalldamage;
ConVar g_Cvar_Launcher_Damage;
ConVar g_Cvar_Launcher_Radius;
ConVar g_Cvar_Launcher_FreeRJ;
ConVar g_Cvar_Rail_Damage;
ConVar g_Cvar_Rail_Rateslow;
ConVar g_Cvar_Rail_Sniperange;
ConVar g_Cvar_Rail_Snipemult;
ConVar g_Cvar_Melee_Damage;

public Plugin myinfo =
{
    name = "ras instagib",
    author = "raspy",
    description = "ras instagib gamemode.",
    version = "1.4.2",
    url = "https://discord.gg/V5Z29SXtsY"
};

public void OnPluginStart() {
    g_Cvar_Enabled = CreateConVar("ri_enabled", "1", "Enable ras instagib mode.", _, true, 0.0, true, 1.0);
    g_Cvar_FFADM = CreateConVar("ri_deathmatch", "1", "Whether NON-PASSTIME gamemodes should be a Free-For-All Deathmatch.", _, true, 0.0, true, 1.0);
    g_Cvar_NoFalldamage = CreateConVar("ri_nofalldamage", "1", "Disable fall damage.", _, true, 0.0, true, 1.0);
    g_Cvar_Launcher_Damage = CreateConVar("ri_launcher_damage", "1.8", "Rocket launcher damage multiplier.", _, true, 0.0, true, 10.0);
    g_Cvar_Launcher_Radius = CreateConVar("ri_launcher_radius", "0.1", "Rocket launcher blast radius percentage.", _, true, 0.0, true, 1.0);
    g_Cvar_Launcher_FreeRJ = CreateConVar("ri_launcher_freerj", "1.0", "Whether Rocket Jumping should cost no health.", _, true, 0.0, true, 1.0);
    g_Cvar_Rail_Damage = CreateConVar("ri_rail_damage", "115", "Railgun base damage.", _, true, 0.0, true, 200.0);
    g_Cvar_Rail_Rateslow = CreateConVar("ri_rail_rateslow", "2", "Railgun fire rate penalty.", _, true, 1.0, true, 10.0);
    g_Cvar_Rail_Sniperange = CreateConVar("ri_rail_snipe_range", "1024", "Railgun range to modify damage.", _, true, 0.0, true, 5192.0);
    g_Cvar_Rail_Snipemult = CreateConVar("ri_rail_snipe_mult", "2", "Railgun range multiplier.", _, true, 0.0, true, 200.0);
    g_Cvar_Melee_Damage = CreateConVar("ri_melee_damage", "5", "Melee damage multiplier.", _, true, 0.0, true, 10.0);

    // apply hook to players already connected on reload
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client)) {
            OnClientPutInServer(client);
        }
    }

    HookEvent("post_inventory_application", OnInventoryApplication, EventHookMode_Post);
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float& damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
    // remove fall damage
	if(damagetype & DMG_FALL) {
        if (!GetConVarBool(g_Cvar_NoFalldamage)) {
            return Plugin_Continue;
        }

        // have kill barriers still kill
        // 450< fall damage in one fall shouldn't usually happen
		if(damage > 450) {
            return Plugin_Continue;
        }
        return Plugin_Handled;
	}
    
    // quit early for people potentially only wanting falldamage removal
    if (!GetConVarBool(g_Cvar_Enabled)) {
        return Plugin_Continue;
    }

    // apply very strict railgun damage
    char wepcls[128];
    GetEntityClassname(weapon, wepcls, sizeof(wepcls));
    if(StrContains(wepcls, "tf_weapon_shotgun", false) == 0) {
        damage = g_Cvar_Rail_Damage.FloatValue;

        // measure distance & apply range multiplier
        float pos_victim[3];
        GetEntPropVector(victim, Prop_Send, "m_vecOrigin", pos_victim);
        float pos_inflictor[3];
        GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", pos_inflictor);
        if(GetVectorDistance(pos_victim, pos_inflictor) > g_Cvar_Rail_Sniperange.FloatValue) {
            damage = damage * g_Cvar_Rail_Snipemult.FloatValue;
        }

        // deal damage
        SDKHooks_TakeDamage(victim,
                        attacker,
                        inflictor,
                        damage,
                        DMG_ALWAYSGIB,
                        weapon,
                        damageForce,
                        damagePosition,
                        true);
        return Plugin_Handled;
    }

	return Plugin_Continue;
}

public void OnMapStart() {
    if (!g_Cvar_Enabled.BoolValue) {
        return;
    }

    char mapName[256];
    GetCurrentMap(mapName, sizeof(mapName));

    // handle enabling of FFADM
    if (!g_Cvar_FFADM.BoolValue) {
        SetConVarBool(FindConVar("mp_friendlyfire"), false);
        return;
    }

    // PASS Time is Team VS
    if (StrContains(mapName, "pass_", false) == 0) {
        SetConVarBool(FindConVar("mp_friendlyfire"), false);
    }
    else {
        // Everything else is to be treated as DM
        SetConVarBool(FindConVar("mp_friendlyfire"), true);
    }
}

public void OnInventoryApplication(Event event, const char[] name, bool dontBroadcast) {
    if (!g_Cvar_Enabled.BoolValue) {
        return;
    }

    // Automatically re-enable AIA if it's disabled
    if (!GetConVarBool(FindConVar("sm_aia_all"))) {
        SetConVarBool(FindConVar("sm_aia_all"), true);
    }

    int client = GetClientOfUserId(event.GetInt("userid"));

    ////
    // PRIMARY

    // Make airshots one-shot and remove blast radius
    int pWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
    TF2Attrib_SetByName(pWeapon, "damage bonus", g_Cvar_Launcher_Damage.FloatValue);
    TF2Attrib_SetByName(pWeapon, "mod mini-crit airborne", 1.0);
    TF2Attrib_SetByName(pWeapon, "Blast radius decreased", g_Cvar_Launcher_Radius.FloatValue);

    // Remove unfair buffs from weapons
    TF2Attrib_SetByName(pWeapon, "Projectile speed increased", 1.0); // direct hit/liblauncher
    TF2Attrib_SetByName(pWeapon, "rocketjump attackrate bonus", 1.0); // air strike

    // Make rocket jumping free
    if (g_Cvar_Launcher_FreeRJ.BoolValue) {
        TF2Attrib_SetByName(pWeapon, "rocket jump damage reduction", 0.0);
    }

    ////
    // SECONDARY

    // Create weapon
	Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL | FORCE_GENERATION | PRESERVE_ATTRIBUTES);
	TF2Items_SetClassname(hWeapon, "tf_weapon_shotgun_soldier");
	TF2Items_SetItemIndex(hWeapon, 10);
    int iWeapon = TF2Items_GiveNamedItem(client, hWeapon);
    delete hWeapon;

    // Make railgun
    TF2Attrib_SetByName(iWeapon, "sniper fires tracer", 1.0);
    TF2Attrib_SetByName(iWeapon, "minicrits become crits", 1.0); // passjack/escape plan holders
    TF2Attrib_SetByName(iWeapon, "weapon spread bonus", 0.0);
    TF2Attrib_SetByName(iWeapon, "projectile penetration", 1.0);
    TF2Attrib_SetByName(iWeapon, "fire rate penalty", g_Cvar_Rail_Rateslow.FloatValue);

    // Apply random killstreak
    int specKs = GetRandomInt(2002, 2008);
    int profKs = GetRandomInt(1, 7);
    TF2Attrib_SetByName(iWeapon, "killstreak tier", 3.0);
    TF2Attrib_SetByName(iWeapon, "killstreak effect", 		float(specKs));
    TF2Attrib_SetByName(iWeapon, "killstreak idleeffect", 	float(profKs));

    // Replace secondary with railgun
    TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
    EquipPlayerWeapon(client, iWeapon);

    ////
    // MELEE

    // Make melee one-shot always
    int mWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    TF2Attrib_SetByName(mWeapon, "damage bonus", g_Cvar_Melee_Damage.FloatValue);
}