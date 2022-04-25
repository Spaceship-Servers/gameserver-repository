#pragma semicolon 1
#pragma newdecls required

#include <sdktools>
#include <dhooks>
#include <discord>
#include <profiler>

Handle hGameData;

Handle SDKCall_GetPlayerSlot;

Handle profiler;

ConVar sm_max_pps_ratio;
ConVar sm_max_bogon_sized_pps_ratio;
ConVar sm_max_invalid_pps_ratio;
ConVar sm_max_packet_processing_time_msec;

int evilPacketsFor          [MAXPLAYERS+1];
int bogonSizedPacketsFor    [MAXPLAYERS+1];

float proctimeThisSecondFor [MAXPLAYERS+1];
int packets                 [MAXPLAYERS+1];


float tickInterval;
float tps;


// TODO TODO TODO
// Sequence number checking
// Invalid packet checking in the ProcessPacketHeader detour so we can return MRES_Supercede and mitigate more lag

public void OnPluginStart()
{
    hGameData = LoadGameConfigFile( "sm.stopbadpackets" );
    if ( !hGameData )
    {
        SetFailState( "Failed to load sm.stopbadpackets gamedata." );
        return;
    }

    LoadTranslations("stopbadpackets.phrases");

    /*

        Gamedata

    */
    {
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
    {
        sm_max_pps_ratio =
        CreateConVar
        (
            "sm_max_pps_ratio",
            "2.0",
            "[StopBadPackets] Max total packets that the client is allowed to send, as a ratio of the server's tickrate.\n\
            Default 2.0, e.g. a client would have to send 128 total packets per second to get kicked on a 64 tick server.",
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
            "[StopBadPackets] Max oddly sized packets ( <8 bytes or >2048 bytes ) a client is allowed to send, as a ratio of the server's tickrate.\n\
            Default 0.75, e.g. a client would have to send 48 oddly sized packets per second to get kicked on a 64 tick server.",
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
            "[StopBadPackets] Max invalid packets a client is allowed to send, as a ratio of the server's tickrate.\n\
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
            "100",
            "[StopBadPackets] Max time in milliseconds the client is allowed to make the server spend processing packets, per second.\n\
            Default 100.",
            FCVAR_NONE,
            true,
            0.0,
            false,
            _
        );
    }

    // Timer for punishing clients
    CreateTimer( 1.0, CheckPackets, _, TIMER_REPEAT );

    // For determining pps -> server tickrate ratios
    tickInterval = GetTickInterval();
    tps = 1 / tickInterval;

    // For determining how long a packet took to process
    profiler = CreateProfiler();
}


public MRESReturn Detour_ProcessPacketHeader( int pThis, DHookReturn hReturn, DHookParam hParams )
{
    return MRES_Ignored;
}

public MRESReturn Hook_ProcessPacketHeader( int pThis, DHookReturn hReturn, DHookParam hParams )
{
    int ret = DHookGetReturn( hReturn );

    // Packet was invalid somehow.
    if ( ret <= -1 )
    {
        int client = GetClientFromThis( pThis );
        if ( IsValidClient( client ))
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
    // get this packet's size
    int offset = GameConfGetOffset( hGameData, "Offset_PacketSize" );

    // Get size of this packet
    Address netpacket = DHookGetParamAddress( hParams, 1 );
    int size = LoadFromAddress( ( netpacket + view_as< Address >( offset ) ), NumberType_Int8 );

    // Is it a wacky size?
    if ( size < 8 || size >= 2048 )
    {
        int client = GetClientFromThis( pThis );
        if ( IsValidClient( client ) )
        {
            bogonSizedPacketsFor[ client ]++;

            // This mitigates a lot of the lag if the client is flooding funnily sized packets!
            return MRES_Supercede;
        }
    }
    return MRES_Ignored;
}

public MRESReturn Hook_ProcessPacket( int pThis, DHookParam hParams )
{
    StopProfiling( profiler );
    int client = GetClientFromThis( pThis );

    if ( IsValidClient( client ) )
    {
        packets[ client ]++;
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
                GetConVarFloat( sm_max_pps_ratio ) > 0.0
                &&
                packets[ client ] >= ( tps * GetConVarFloat( sm_max_pps_ratio ) )
            )
            {
                char publicmsg[256];
                Format( publicmsg, sizeof( publicmsg ), "%t", "packetFlood_ToAll", client, packets[ client ]);

                char clientmsg[256];
                Format( clientmsg, sizeof( clientmsg ), "%t", "packetFlood_Player", packets[ client ]);

                Discord_SendMessage( "badpackets", publicmsg );

                PrintToServer ( publicmsg );
                PrintToChatAll( publicmsg );
                PrintToConsole( client, clientmsg );
                KickClient    ( client, clientmsg );
            }

            // Oddly sized packets next
            else if
            (
                GetConVarFloat( sm_max_bogon_sized_pps_ratio ) > 0.0
                &&
                bogonSizedPacketsFor[client] >= ( tps * GetConVarFloat( sm_max_bogon_sized_pps_ratio ) )
            )
            {
                char publicmsg[256];
                Format(publicmsg, sizeof( publicmsg ), "%t", "bogonSizedPackets_ToAll", client, bogonSizedPacketsFor[ client ] );

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
                GetConVarFloat( sm_max_invalid_pps_ratio ) > 0.0
                &&
                evilPacketsFor[ client ] >= ( tps * GetConVarFloat( sm_max_invalid_pps_ratio ) )
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
                GetConVarFloat( sm_max_packet_processing_time_msec ) > 0.0
                &&
                proctime_ms > GetConVarFloat( sm_max_packet_processing_time_msec )
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
        && IsClientInGame( client )
        && !IsFakeClient( client )
    )
    {
        return true;
    }
    return false;
}

// This looks simple but it took literally 6 hours to figure out
int GetClientFromThis( any pThis )
{
    // sanity check
    if ( pThis == Address_Null )
    {
        return -1;
    }
    int offset = GameConfGetOffset( hGameData, "Offset_MessageHandler" );
    Address IClient = DerefPtr( pThis + offset );
    if ( IClient == Address_Null )
    {
        return -1;
    }
    int client = SDKCall( SDKCall_GetPlayerSlot, IClient ) + 1;
    return client;
}

Address DerefPtr( Address addr )
{
    return view_as< Address >( LoadFromAddress( addr, NumberType_Int32 ) );
}