// MEMTOOLS

#include <sourcemod>
#include <concolors>
#define REQUIRE_EXTENSION
#include <getmem>

ConVar MemKillLimit;

public void OnPluginStart()
{
    MemKillLimit = CreateConVar(
        "sm_memkill_limit",
        "4096",
        "Maximum memory usage (in MB) a server can have before gracefully auto-restarting at the end of a map. Replaces the broken/buggy sv_memlimit", // description
        _,
        true,
        0.0,
        false
    );
    RegServerCmd("sm_getmem_mb", GetMem_MB,         "Print the current memory usage of this server, in megabytes.");
    RegServerCmd("sm_cleanmem", AttemptClearMem,    "Run some commands that *should* clear up some unused RAM.");


    int flushflags;

    flushflags      = GetCommandFlags("flush");
    flushflags      &= ~(FCVAR_CHEAT);
    SetCommandFlags("flush", flushflags);

    flushflags      = GetCommandFlags("flush_locked");
    flushflags      &= ~(FCVAR_CHEAT);
    SetCommandFlags("flush_locked", flushflags);
}

Action GetMem_MB(int args)
{
    float mem     = GetMem() / 1000.0;
    PrintToServer("%.4f MB", mem);
    return Plugin_Handled;
}

Action AttemptClearMem(int args)
{
    ServerCommand("mem_compact");
    ServerCommand("r_flushlod");
    ServerCommand("flush");
    ServerCommand("flush_locked");
    return Plugin_Handled;
}

public void OnMapEnd()
{
    float mem   = GetMem() / 1000.0;
    int limit   = GetConVarInt(MemKillLimit);

    if (mem >= limit)
    {
        PrintToChatAll("[MEMKILL] Server is running low on RAM. Restarting.");
        PrintToServer (ansi_red ... "[MEMKILL] Server is running low on RAM. Usage: %.1fMB - Limit: %iMB. Restarting." ... ansi_reset, mem, limit);
        ServerCommand("kickall \"Server restarting, low on RAM.\"; _restart");
    }
    else
    {
        PrintToServer (ansi_green ... "[MEMKILL] Server running under memlimit. Usage: %.1fMB - Limit: %iMB" ... ansi_reset, mem, limit);
    }
}
