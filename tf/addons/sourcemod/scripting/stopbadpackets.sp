#include <sdktools>
#include <dhooks>
#include <discord>
#include <profiler>

// each channel packet has 1 byte of FLAG bits
#define PACKET_FLAG_RELIABLE            (1<<0)  // packet contains subchannel stream data
#define PACKET_FLAG_COMPRESSED          (1<<1)  // packet is compressed
#define PACKET_FLAG_ENCRYPTED           (1<<2)  // packet is encrypted
#define PACKET_FLAG_SPLIT               (1<<3)  // packet is split
#define PACKET_FLAG_CHOKED              (1<<4)  // packet was choked by sender
#define PACKET_FLAG_CHALLENGE           (1<<5)  // packet contains challenge number, use to prevent packet injection
#define PACKET_FLAG_IDK                 (1<<6)  // who freakin knows man

// this should be a constant in sm...
// Address NULL = view_as<Address>(0x0);


Handle hGameData;

Handle SDKCall_GetPlayerSlot;

Handle profiler;

ConVar sm_max_bad_packets_sec;
ConVar sm_max_packet_processing_time_msec;

int evilPacketsFor          [MAXPLAYERS+1];
float proctimeThisSecondFor [MAXPLAYERS+1];
int ticks                   [MAXPLAYERS+1];

public void OnPluginStart()
{
    hGameData = LoadGameConfigFile("sm.stopbadpackets");
    if (!hGameData)
    {
        SetFailState("Failed to load sm.stopbadpackets gamedata.");
        return;
    }


    /*
        ProcessPacketHeader
    */
    Handle hProcessPacketHeader_Detour = DHookCreateFromConf(hGameData, "ProcessPacketHeader");
    if (!hProcessPacketHeader_Detour)
    {
        SetFailState("Failed to setup detour for ProcessPacketHeader");
    }

    // post hook
    if (!DHookEnableDetour(hProcessPacketHeader_Detour, true, Detour_ProcessPacketHeader))
    {
        SetFailState("Failed to detour ProcessPacketHeader.");
    }
    PrintToServer("CNetChan::ProcessPacketHeader detoured!");

    /*
        ProcessPacket
    */

    Handle hProcessPacket_Detour     = DHookCreateFromConf(hGameData, "ProcessPacket");
    Handle hProcessPacket_DetourPost = DHookCreateFromConf(hGameData, "ProcessPacket");
    if (!hProcessPacket_Detour || !hProcessPacket_DetourPost)
    {
        SetFailState("Failed to setup detour for ProcessPacket");
    }

    // pre hook
    if (!DHookEnableDetour(hProcessPacket_Detour, false, Detour_ProcessPacket))
    {
        SetFailState("Failed to detour ProcessPacket.");
    }
    PrintToServer("CNetChan::ProcessPacket detoured!");

    // post hook
    if (!DHookEnableDetour(hProcessPacket_DetourPost, true, Detour_ProcessPacketPost))
    {
        SetFailState("Failed to detour ProcessPacket [post]");
    }
    PrintToServer("CNetChan::ProcessPacket hooked!");

    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseClient::GetPlayerSlot");
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    SDKCall_GetPlayerSlot = EndPrepSDKCall();
    PrintToServer("CBaseClient::GetPlayerSlot set up!");


    sm_max_bad_packets_sec =
    CreateConVar
    (
        "sm_max_bad_packets_sec",
        "25",
        "[StopBadPackets] Max invalid packets a client is allowed to send, per second. Default 25.",
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
        "50",
        "[StopBadPackets] Max time the client is allowed to make the server spend processing packets, in msec. Default 50.",
        FCVAR_NONE,
        true,
        0.0,
        false,
        _
    );

    CreateTimer(1.0, CheckProcTime, _, TIMER_REPEAT);

    profiler = CreateProfiler();
}

public Action CheckProcTime(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (GetConVarFloat(sm_max_packet_processing_time_msec) == 0.0)
        {
            proctimeThisSecondFor[client] = 0.0;
            ticks[client] = 0;

            // don't run the rest of this logic if there's no point in kicking people :P
            continue;
        }
        if (IsValidClient(client))
        {
            if (proctimeThisSecondFor[client] > GetConVarFloat(sm_max_packet_processing_time_msec) / 1000)
            {
                char hookmsg[256];
                Format(hookmsg, sizeof(hookmsg), "[StopBadPackets] Client -%L- spent [%.2fms] over [%i] ticks in the last second processing a packet - sm_max_packet_processing_time_msec = %.2f",
                    client, proctimeThisSecondFor[client]*1000.0, ticks[client], GetConVarFloat(sm_max_packet_processing_time_msec));
                Discord_SendMessage("badpackets", hookmsg);

                // KickClient(client, "[StopBadPackets] Client %N took too long to process a packet", client);
                PrintToServer("%s", hookmsg);
            }
            // PrintToServer("%N - %f.", client, proctimeThisSecondFor[client] * 1000);
            // PrintToServer("%N - %i ticks.", client, ticks[client]);
        }
        proctimeThisSecondFor[client] = 0.0;
        ticks[client] = 0;
    }
    return Plugin_Continue;
}


public MRESReturn Detour_ProcessPacket(int pThis, DHookParam hParams)
{
    StartProfiling(profiler);
    int offset = GameConfGetOffset(hGameData, "Offset_PacketSize");

    // Get size of this packet
    Address netpacket = DHookGetParamAddress(hParams, 1);
    int size = LoadFromAddress((netpacket + view_as<Address>(offset)), NumberType_Int32);

    // sanity check
    if (size < 8 || size >= 2048)
    {
        int client = GetClientFromThis(pThis);
        if (IsValidClient(client))
        {
            char hookmsg[256];
            Format(hookmsg, sizeof(hookmsg), "[StopBadPackets] Client -%L- sent a packet with a sussy size: [%i]", client, size);
            Discord_SendMessage("badpackets", hookmsg);
            PrintToServer("%s", hookmsg);
            // KickClient(client, "[StopBadPackets] Client %N sent a packet with a sussy size!", client);
            // return MRES_Supercede;
        }
    }
    return MRES_Ignored;
}

// this isn't a detour but shut up
public MRESReturn Detour_ProcessPacketPost(int pThis, DHookParam hParams)
{
    StopProfiling(profiler);
    int client = GetClientFromThis(pThis);

    if (IsValidClient(client))
    {
        ticks[client]++;
        proctimeThisSecondFor[client] += GetProfilerTime(profiler);

    }
    return MRES_Ignored;

}

public MRESReturn Detour_ProcessPacketHeader(int pThis, DHookReturn hReturn, DHookParam hParams)
{
    int ret             = DHookGetReturn(hReturn);
    // Address netpacket   = DHookGetParamAddress(hParams, 1);

    /*
    char flags[64];
    if (ret & PACKET_FLAG_RELIABLE)
    {
        StrCat(flags, sizeof(flags), "RELIABLE ");
    }
    if (ret & PACKET_FLAG_COMPRESSED)
    {
        StrCat(flags, sizeof(flags), "COMPRESSED ");
    }
    if (ret & PACKET_FLAG_ENCRYPTED)
    {
        StrCat(flags, sizeof(flags), "ENCRYPTED ");
    }
    if (ret & PACKET_FLAG_SPLIT)
    {
        StrCat(flags, sizeof(flags), "SPLIT ");
    }
    if (ret & PACKET_FLAG_CHOKED)
    {
        StrCat(flags, sizeof(flags), "CHOKED ");
    }
    if (ret & PACKET_FLAG_CHALLENGE)
    {
        StrCat(flags, sizeof(flags), "CHALLENGE ");
    }
    if (ret & PACKET_FLAG_IDK)
    {
        StrCat(flags, sizeof(flags), "UNKNOWN FLAG ");
    }

    LogMessage("processing packet header %i %s", ret, flags);

    */


    // Packet was invalid somehow.
    if (ret == -1)
    {
        int client = GetClientFromThis(pThis);
        evilPacketsFor[client]++;
        PrintToServer("[StopBadPackets] Client %N sent an invalid packet. Detections within the last second: %i", client, evilPacketsFor[client]);

        // expire this detection in 1 second
        int userid = GetClientUserId(client);
        CreateTimer(1.0, Timer_decr_BadPacket, userid, TIMER_FLAG_NO_MAPCHANGE);

        if (evilPacketsFor[client] % 5 == 0)
        {
            char hookmsg[256];
            Format(hookmsg, sizeof(hookmsg), "[StopBadPackets] Client -%L- sent too many invalid packets [%i]/s - sm_max_bad_packets_sec = %.2f", client, evilPacketsFor[client], GetConVarFloat(sm_max_bad_packets_sec));
            Discord_SendMessage("badpackets", hookmsg);
        }

        if (evilPacketsFor[client] >= GetConVarFloat(sm_max_bad_packets_sec))
        {
            // KickClient(client, "[StopBadPackets] Client %N sent too many invalid packets", client);
            PrintToServer("[StopBadPackets] Client %N sent too many invalid packets", client);
        }
    }

    return MRES_Ignored;
}


Action Timer_decr_BadPacket(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (client)
    {
        if (evilPacketsFor[client] > 0)
        {
            evilPacketsFor[client]--;
        }
    }
    return Plugin_Handled;
}

// client join
public void OnClientPutInServer(int client)
{
    evilPacketsFor[client] = 0;
}

// player left and mapchanges
public void OnClientDisconnect(int client)
{
    evilPacketsFor[client] = 0;
}

bool IsValidClient(int client)
{
    if
    (
        (0 < client <= MaxClients)
        && IsClientInGame(client)
        && !IsFakeClient(client)
    )
    {
        return true;
    }
    return false;
}

// This looks simple but it took literally 6 hours to figure out
int GetClientFromThis(any pThis)
{
    if (pThis == Address_Null)
    {
        LogMessage("pThis == NULL!")
        return 0;
    }
    int offset  = GameConfGetOffset(hGameData, "Offset_MessageHandler");
    Address IClient = DerefPtr(pThis + offset );
    // Address IClient = pThis + offset;
    if (IClient == Address_Null)
    {
        LogMessage("IClient == NULL!")
        return 0;
    }
    int client = SDKCall(SDKCall_GetPlayerSlot, IClient) + 1;
    return client;
}


Address DerefPtr(Address addr)
{
    return view_as<Address>(LoadFromAddress(addr, NumberType_Int32));
}


