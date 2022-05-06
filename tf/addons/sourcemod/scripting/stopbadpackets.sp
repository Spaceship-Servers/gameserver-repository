#pragma semicolon 1
#pragma newdecls required

#include <sdktools>
#include <dhooks>
#include <discord>
#include <profiler>

public Plugin myinfo = {
    name        = "StopBadPackets",
    author      = "https://sappho.io",
    description = "Prevents most CNetChan::ProcessPacket/Header based exploits",
    version     = "0.0.4",
    url         = "https://sappho.io"
};


// each channel packet has 1 byte of FLAG bits
#define PACKET_FLAG_RELIABLE            (1<<0)  // packet contains subchannel stream data
#define PACKET_FLAG_COMPRESSED          (1<<1)  // packet is compressed
#define PACKET_FLAG_ENCRYPTED           (1<<2)  // packet is encrypted
#define PACKET_FLAG_SPLIT               (1<<3)  // packet is split
#define PACKET_FLAG_CHOKED              (1<<4)  // packet was choked by sender
#define PACKET_FLAG_CHALLENGE           (1<<5)  // this packet has a challenge number (ALL PACKETS SHOULD HAVE THIS)
#define PACKET_FLAG_IDK                 (1<<6)  // idk

// Not used ?
// PACKET_FLAG_COMPRESSED
// PACKET_FLAG_ENCRYPTED
// PACKET_FLAG_SPLIT
// https://cs.sappho.io/xref/hl2_src/engine/net_chan.cpp#1578

Handle hGameData;

Handle SDKCall_GetPlayerSlot;

Handle profiler;

ConVar sm_max_pps_ratio;
ConVar sm_max_pps_ratio_drop;
ConVar sm_max_bogon_sized_pps_ratio;
ConVar sm_max_invalid_pps_ratio;
ConVar sm_max_packet_processing_time_msec;

float max_pps_ratio;
float max_pps_ratio_drop;
float max_bogon_sized_pps_ratio;
float max_invalid_pps_ratio;
float max_packet_processing_time_msec;


int evilPacketsFor          [MAXPLAYERS+1];
int bogonSizedPacketsFor    [MAXPLAYERS+1];

float proctimeThisSecondFor [MAXPLAYERS+1];
int packets                 [MAXPLAYERS+1];

float tickInterval;
float tps;


// TODO TODO TODO
// Sequence number checking?
//

public void OnPluginStart()
{
    LoadTranslations("stopbadpackets.phrases");

    DoGamedata();
    DoCvars();

    // Timer for punishing clients
    CreateTimer( 1.0, CheckPackets, _, TIMER_REPEAT );

    // For determining how long a packet took to process
    profiler = CreateProfiler();
}

/*
    Gamedata
*/
void DoGamedata()
{
    // Our base gamedata file
    hGameData = LoadGameConfigFile( "sm.stopbadpackets" );
    if ( !hGameData )
    {
        SetFailState( "Failed to load sm.stopbadpackets gamedata." );
        return;
    }


    /*
        ProcessPacketHeader
    */

    Handle hProcessPacketHeader = DHookCreateFromConf( hGameData, "ProcessPacketHeader" );
    if ( !hProcessPacketHeader )
    {
        SetFailState( "Failed to setup DHook for ProcessPacketHeader" );
    }

    // detour
    if ( !DHookEnableDetour( hProcessPacketHeader, false, Detour_ProcessPacketHeader ) )
    {
        SetFailState( "Failed to detour ProcessPacketHeader." );
    }
    PrintToServer( "CNetChan::ProcessPacketHeader detoured!" );

    // hook
    if ( !DHookEnableDetour( hProcessPacketHeader, true, Hook_ProcessPacketHeader ) )
    {
        SetFailState( "Failed to hook ProcessPacketHeader." );
    }
    PrintToServer( "CNetChan::ProcessPacketHeader hooked!" );

    /*
        ProcessPacket
    */

    Handle hProcessPacket = DHookCreateFromConf( hGameData, "ProcessPacket" );
    if ( !hProcessPacket )
    {
        SetFailState( "Failed to setup detour for ProcessPacket" );
    }

    // detour
    if ( !DHookEnableDetour( hProcessPacket, false, Detour_ProcessPacket ) )
    {
        SetFailState( "Failed to detour ProcessPacket." );
    }
    PrintToServer( "CNetChan::ProcessPacket detoured!" );

    // hook
    if ( !DHookEnableDetour( hProcessPacket, true, Hook_ProcessPacket) )
    {
        SetFailState( "Failed to detour ProcessPacket [post]" );
    }
    PrintToServer( "CNetChan::ProcessPacket hooked!" );

    /*
        GetPlayerSlot
    */
    StartPrepSDKCall( SDKCall_Raw );
    PrepSDKCall_SetFromConf( hGameData, SDKConf_Virtual, "CBaseClient::GetPlayerSlot" );
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
    SDKCall_GetPlayerSlot = EndPrepSDKCall();
    if ( SDKCall_GetPlayerSlot != INVALID_HANDLE)
    {
        PrintToServer( "CBaseClient::GetPlayerSlot set up!" );
    }
    else
    {
        SetFailState( "Failed to get CBaseClient::GetPlayerSlot offset." );
    }
}

/*
    ConVars
*/
void DoCvars()
{
    sm_max_pps_ratio =
    CreateConVar
    (
        "sm_max_pps_ratio",
        "10.0",
        "[StopBadPackets] Max total packets that the client is allowed to send before getting kicked, as a ratio of the server's tickrate.\n\
        Default 10.0, e.g. a client would have to send 640 total packets per second to get kicked on a 64 tick server.",
        FCVAR_NONE,
        true,
        0.0,
        false,
        _
    );

    sm_max_pps_ratio_drop =
    CreateConVar
    (
        "sm_max_pps_ratio_drop",
        "3.0",
        "[StopBadPackets] Max total packets that the client is allowed to send before their packets are silently dropped, as a ratio of the server's tickrate.\n\
        Default 3.0, e.g. a client would have to send 192 total packets per second before their packets get dropped on a 64 tick server.",
        FCVAR_NONE,
        true,
        0.0,
        false,
        _
    );

    sm_max_bogon_sized_pps_ratio =
    CreateConVar
    (
        "sm_max_bogon_sized_pps_ratio",
        "0.75",
        "[StopBadPackets] Max oddly sized packets ( <=8 bytes or >=2048 bytes ) a client is allowed to send before getting kicked, as a ratio of the server's tickrate.\n\
        Default 0.75, e.g. a client would have to send 48 oddly sized packets per second to get kicked on a 64 tick server.\n\
        These packets are automatically dropped.",
        FCVAR_NONE,
        true,
        0.0,
        false,
        _
    );

    sm_max_invalid_pps_ratio =
    CreateConVar
    (
        "sm_max_invalid_pps_ratio",
        "0.75",
        "[StopBadPackets] Max invalid packets a client is allowed to send before getting kicked, as a ratio of the server's tickrate.\n\
        Default 0.75, e.g. a client would have to send 48 invalid packets per second to get kicked on a 64 tick server.",
        FCVAR_NONE,
        true,
        0.0,
        false,
        _
    );

    sm_max_packet_processing_time_msec =
    CreateConVar
    (
        "sm_max_packet_processing_time_msec",
        "150.0",
        "[StopBadPackets] Max time in milliseconds the client is allowed to make the server spend processing packets before getting kicked, per second.\n\
        Default 150.",
        FCVAR_NONE,
        true,
        0.0,
        false,
        _
    );


    // Hook our cvars
    HookConVarChange(sm_max_pps_ratio,                      OurCvarsChanged);
    HookConVarChange(sm_max_pps_ratio_drop,                 OurCvarsChanged);
    HookConVarChange(sm_max_bogon_sized_pps_ratio,          OurCvarsChanged);
    HookConVarChange(sm_max_invalid_pps_ratio,              OurCvarsChanged);
    HookConVarChange(sm_max_packet_processing_time_msec,    OurCvarsChanged);

    // Update our cvars
    OurCvarsChanged(null, "", "");
}

void OurCvarsChanged( ConVar convar, const char[] oldValue, const char[] newValue )
{
    max_pps_ratio                   = GetConVarFloat(sm_max_pps_ratio);
    max_pps_ratio_drop              = GetConVarFloat(sm_max_pps_ratio_drop);
    max_bogon_sized_pps_ratio       = GetConVarFloat(sm_max_bogon_sized_pps_ratio);
    max_invalid_pps_ratio           = GetConVarFloat(sm_max_invalid_pps_ratio);
    max_packet_processing_time_msec = GetConVarFloat(sm_max_packet_processing_time_msec);
}

public void OnMapStart()
{
    // For determining pps -> server tickrate ratios
    tickInterval = GetTickInterval();
    tps = 1 / tickInterval;
}

// We're not doing anything here yet
public MRESReturn Detour_ProcessPacketHeader( int pThis, DHookReturn hReturn, DHookParam hParams )
{
    return MRES_Ignored;
}

#define retinit 1024
int ret = retinit;
public MRESReturn Hook_ProcessPacketHeader( int pThis, DHookReturn hReturn, DHookParam hParams )
{
    // ProcessPacketHeader will return the flags of the packet it processes
    // https://cs.sappho.io/xref/hl2_src/engine/net_chan.cpp#2235
    ret = DHookGetReturn( hReturn );

    // Packet was invalid somehow.
    if ( ret <= -1 )
    {
        int client = GetClientFromThis( pThis );
        if ( IsValidClient( client ) )
        {
            evilPacketsFor[ client ]++;
        }
    }

    return MRES_Ignored;
}

public MRESReturn Detour_ProcessPacket( int pThis, DHookParam hParams )
{
    // let's see how long this packet takes to process
    StartProfiling( profiler );

    // Get our client
    int client          = GetClientFromThis( pThis );

    // Don't run anything on non connected/invalid/fake clients
    if ( !IsValidClient( client ) )
    {
        return MRES_Ignored;
    }

    // inc our total packet count for our client
    packets[ client ]++;

    // Get size of this packet
    int offset          = GameConfGetOffset( hGameData, "Offset_PacketSize" );
    Address netpacket   = DHookGetParamAddress( hParams, 1 );
    int size            = LoadFromAddress( ( netpacket + view_as< Address >( offset ) ), NumberType_Int8 );

    // Is it a wacky size?
    if ( size <= 8 || size >= 2048 )
    {
        bogonSizedPacketsFor[ client ]++;

        // This mitigates a lot of the lag if the client is flooding funnily sized packets!
        return MRES_Supercede;
    }

    // Debug
    // DumpPacketFlags( ret );

    // Ignore non challenge packets
    // PACKETS SHOULD ALWAYS HAVE A CHALLENGE NUMBER!!
    // https://cs.sappho.io/xref/hl2_src/engine/net_chan.cpp#1655-1656
    // [ we need to check that this has been set by an actual client, so we check retinit etc ]
    if ( !( ret & PACKET_FLAG_CHALLENGE ) && ret != retinit )
    {
        char publicmsg[256];
        Format( publicmsg, sizeof( publicmsg ), "[StopBadPackets] Client %L sent a packet without a challenge flag, flags [%i]", client, ret );
        Discord_SendMessage( "badpackets", publicmsg );
        PrintToServer( "%s", publicmsg );

        // evilPacketsFor[ client ]++;

        return MRES_Ignored;
        // return MRES_Supercede;
    }

    // Ignore packets with unused packet headers
    // AS FAR AS I CAN TELL, none of these flags are used ANYWHERE, in TF2 nor CSGO
    // https://cs.sappho.io/search?project=hl2_src&full=PACKET_FLAG_COMPRESSED&defs=&refs=&path=&hist=&type=&xrd=&nn=1&si=full&si=full
    // https://cs.sappho.io/search?project=hl2_src&full=PACKET_FLAG_ENCRYPTED&defs=&refs=&path=&hist=&type=&xrd=&nn=1&si=full&si=full
    // https://cs.sappho.io/search?project=hl2_src&full=PACKET_FLAG_SPLIT&defs=&refs=&path=&hist=&type=&xrd=&nn=1&si=full&si=full
    // https://cs.sappho.io/search?project=cstrike15_src&full=PACKET_FLAG_COMPRESSED&defs=&refs=&path=&hist=&type=&xrd=&nn=1&si=full&si=full
    // https://cs.sappho.io/search?project=cstrike15_src&full=PACKET_FLAG_ENCRYPTED&defs=&refs=&path=&hist=&type=&xrd=&nn=1&si=full&si=full
    // https://cs.sappho.io/search?project=cstrike15_src&full=PACKET_FLAG_SPLIT&defs=&refs=&path=&hist=&type=&xrd=&nn=1&si=full&si=full
    // [ BETA, obviously, because neither source is the current game, duh ]
    if ( ret & PACKET_FLAG_COMPRESSED || ret & PACKET_FLAG_ENCRYPTED || ret & PACKET_FLAG_SPLIT )
    {
        char publicmsg[256];
        Format( publicmsg, sizeof( publicmsg ), "[StopBadPackets] Client %L sent a funky packet, flags [%i]", client, ret );
        Discord_SendMessage( "badpackets", publicmsg );
        PrintToServer( "%s", publicmsg );

        // evilPacketsFor[ client ]++;

        return MRES_Ignored;
        // return MRES_Supercede;
    }

    // Ignore packets that ProcessPacketHeader has already deemed garbage ( we already have counted them as evilPackets in our ProcessPacketHeader detour )
    if ( ret <= -1 )
    {
        return MRES_Supercede;
    }

    // Check if this client is spamming the server
    if
    (
        max_pps_ratio_drop > 0.0
        &&
        packets[ client ] >= ( tps * max_pps_ratio_drop )
    )
    {
        char publicmsg[256];
        Format( publicmsg, sizeof( publicmsg ), "[StopBadPackets] Client %L sent too many packets [%i] - dropping", client, packets[ client ] );
        Discord_SendMessage( "badpackets", publicmsg );
        PrintToServer( "%s", publicmsg );

        // Mitigate any possible lag they could cause
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

public MRESReturn Hook_ProcessPacket( int pThis, DHookParam hParams )
{
    StopProfiling( profiler );
    int client = GetClientFromThis( pThis );

    if ( IsValidClient( client ) )
    {
        proctimeThisSecondFor[ client ] += GetProfilerTime( profiler );
    }

    return MRES_Ignored;
}

public Action CheckPackets( Handle timer )
{
    for ( int client = 1; client <= MaxClients; client++ )
    {
        if ( IsValidClient( client ) )
        {
            float proctime_ms = proctimeThisSecondFor[client] * 1000;

            // Packet flood first
            if
            (
                max_pps_ratio > 0.0
                &&
                packets[ client ] >= ( tps * max_pps_ratio )
            )
            {
                char publicmsg[256];
                Format( publicmsg, sizeof( publicmsg ), "%t", "packetFlood_ToAll", client, packets[ client ] );

                char clientmsg[256];
                Format( clientmsg, sizeof( clientmsg ), "%t", "packetFlood_Player", packets[ client ] );

                Discord_SendMessage( "badpackets", publicmsg );

                PrintToServer ( publicmsg );
                PrintToChatAll( publicmsg );
                PrintToConsole( client, clientmsg );
                KickClient    ( client, clientmsg );
            }

            // Oddly sized packets next
            else if
            (
                max_bogon_sized_pps_ratio > 0.0
                &&
                bogonSizedPacketsFor[client] >= ( tps * max_bogon_sized_pps_ratio )
            )
            {
                char publicmsg[256];
                Format( publicmsg, sizeof( publicmsg ), "%t", "bogonSizedPackets_ToAll", client, bogonSizedPacketsFor[ client ] );

                char clientmsg[256];
                Format( clientmsg, sizeof( clientmsg ), "%t", "bogonSizedPackets_Player", bogonSizedPacketsFor[ client ] );

                Discord_SendMessage( "badpackets", publicmsg );

                PrintToServer ( publicmsg );
                PrintToChatAll( publicmsg );
                PrintToConsole( client, clientmsg );
                KickClient    ( client, clientmsg );
            }

            // Invalid packets next
            else if
            (
                max_invalid_pps_ratio > 0.0
                &&
                evilPacketsFor[ client ] >= ( tps * max_invalid_pps_ratio )
            )
            {
                char publicmsg[256];
                Format( publicmsg, sizeof( publicmsg ), "%t", "invalidPackets_ToAll", client, evilPacketsFor[ client ] );

                char clientmsg[256];
                Format( clientmsg, sizeof( clientmsg ), "%t", "invalidPackets_Player", evilPacketsFor[ client ] );

                Discord_SendMessage( "badpackets", publicmsg );

                PrintToServer ( publicmsg );
                PrintToChatAll( publicmsg );
                PrintToConsole( client, clientmsg );
                KickClient    ( client, clientmsg );
            }

            else if
            (
                max_packet_processing_time_msec > 0.0
                &&
                proctime_ms > max_packet_processing_time_msec
            )
            {
                char publicmsg[256];
                Format( publicmsg, sizeof( publicmsg ), "%t", "processingTime_ToAll", proctime_ms, packets[ client ], client );

                char clientmsg[256];
                Format( clientmsg, sizeof( clientmsg ), "%t", "processingTime_Player", proctime_ms, packets[ client ] );

                Discord_SendMessage( "badpackets", publicmsg );

                PrintToServer ( publicmsg );
                PrintToChatAll( publicmsg );
                PrintToConsole( client, clientmsg );
                KickClient    ( client, clientmsg );
            }
        }
        resetVals( client );
    }
    return Plugin_Continue;
}

// client join
public void OnClientPutInServer( int client )
{
    resetVals( client );
}

// player left and mapchanges
public void OnClientDisconnect( int client )
{
    resetVals( client );
}

void resetVals( int client )
{
    proctimeThisSecondFor[ client ] = 0.0;
    packets              [ client ] = 0;
    evilPacketsFor       [ client ] = 0;
    bogonSizedPacketsFor [ client ] = 0;
}

bool IsValidClient( int client )
{
    if
    (
        ( 0 < client <= MaxClients )
        && IsClientConnected( client )
        && !IsFakeClient( client )
    )
    {
        return true;
    }
    return false;
}

// This looks simple but it took literally 6 hours to figure out offsets for on TF2 lol
int GetClientFromThis( any pThis )
{
    // sanity check
    if ( pThis == Address_Null )
    {
        return -1;
    }
    int offset = GameConfGetOffset( hGameData, "Offset_MessageHandler" );
    Address IClient = DerefPtr( pThis + offset );
    // Clients will be null when connecting and disconnecting
    if ( IClient == Address_Null )
    {
        return -1;
    }
    // Client's ent index is always GetPlayerSlot() + 1
    int client = SDKCall( SDKCall_GetPlayerSlot, IClient ) + 1;
    return client;
}

Address DerefPtr( Address addr )
{
    return view_as< Address >( LoadFromAddress( addr, NumberType_Int32 ) );
}

/*
void DumpPacketFlags(int flags)
{
    char flagstring[128] = "| ";
    if (ret & PACKET_FLAG_RELIABLE)
    {
        StrCat(flagstring, sizeof(flagstring), "RELIABLE | ");
    }
    if (ret & PACKET_FLAG_COMPRESSED)
    {
        StrCat(flagstring, sizeof(flagstring), "COMPRESSED | ");
    }
    if (ret & PACKET_FLAG_ENCRYPTED)
    {
        StrCat(flagstring, sizeof(flagstring), "ENCRYPTED | ");
    }
    if (ret & PACKET_FLAG_SPLIT)
    {
        StrCat(flagstring, sizeof(flagstring), "SPLIT | ");
    }
    if (ret & PACKET_FLAG_CHOKED)
    {
        StrCat(flagstring, sizeof(flagstring), "CHOKED | ");
    }
    if (ret & PACKET_FLAG_CHALLENGE)
    {
        StrCat(flagstring, sizeof(flagstring), "CHALLENGE | ");
    }
    if (ret & PACKET_FLAG_IDK)
    {
        StrCat(flagstring, sizeof(flagstring), "IDK | ");
    }

    PrintToServer("[StopBadPackets] Packet header %i == %s", flags, flagstring);
}
*/