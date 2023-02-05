#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
//#include <voiceannounce_ex> // using sourcemod natives
#pragma newdecls required

#define PATH "logs/voicedata_crashfix.log"
#define PLUGIN_VERSION		"1.3"	

ConVar maxVoicePackets;
ConVar punishment;

int g_voicePacketCount[MAXPLAYERS+1];
int iPunishMent;
int iMaxVoicePackets;

public Plugin myinfo = 
{
	name = "Voice Data Crash Fix",
	author = "Ember, V1sual & Franc1sco Franug",
	description = "Punishes players who are overflowing voice data to crash the server",
	version = PLUGIN_VERSION,
	url = "https://github.com/Franc1sco/VoiceData_CrashFix"
};

public void OnPluginStart()
{
	CreateConVar("sm_voicedatacrashfix_version", PLUGIN_VERSION, "Voice Data Crash Fix plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	punishment = CreateConVar("sm_voicedatacrashfix_punishment", "1", "Punishment. 0 = Just mute, 1 = Kick, 2 = Perm ban", _, true, 0.0, true, 2.0);
	maxVoicePackets = CreateConVar("sm_voicedatacrashfix_count", "92", "How many packets per second max?");
	
	AutoExecConfig(); // autogenerate cfg file

	iPunishMent = punishment.IntValue;
	iMaxVoicePackets = maxVoicePackets.IntValue;

	punishment.AddChangeHook(OnConVarHook);
	maxVoicePackets.AddChangeHook(OnConVarHook);
}

public void OnConVarHook(ConVar cvar, const char[] oldVal, const char[] newVal) 
{
	if (cvar == punishment)
	{
		iPunishMent = cvar.IntValue;
	}
	else if (cvar == maxVoicePackets)
	{
		iMaxVoicePackets = cvar.IntValue;
	}
}

public void OnMapStart()
{
	CreateTimer(1.0, ResetCount, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action ResetCount(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
        	g_voicePacketCount[i] = 0;
	}
	
	return Plugin_Continue;
}

public void OnClientSpeaking(int client)
{
	if (++g_voicePacketCount[client] > iMaxVoicePackets) 
	{
		char id[128], ip[32];
		
		GetClientIP(client, ip, sizeof(ip));

		if(!GetClientAuthId(client, AuthId_Steam2, id, sizeof(id))) 
		{
			// not valid steamid so dont ban, kick instead
			if (GetClientAuthId(client, AuthId_Steam2, id, sizeof(id), false))
			{
	            Format(id, sizeof(id), "%s (Not Validated)", id);
			}
			else
			{
	            strcopy(id, sizeof(id), "Unknown");
			}

			LogToPluginFile("%N (ID: %s | IP: %s) was kicked for trying to crash the server with voice data overflow. Total packets: %i",
			client,
			id,
			ip,
			g_voicePacketCount[client]);
			
			if (!IsClientInGame(client) || GetClientListeningFlags(client) != VOICE_MUTED) {
				SetClientListeningFlags(client, VOICE_MUTED);
			}
			
			if (!IsClientInKickQueue(client))
			{
				KickClient(client, "Voice data overflow detected!");
			}
			
			return;
		}
		
		char sPunishment[64];
		switch (iPunishMent)
		{
			case 0:
			{
				strcopy(sPunishment, sizeof(sPunishment), "muted");
			}
			case 1:
			{
				strcopy(sPunishment, sizeof(sPunishment), "kicked");
			}
			case 2:
			{
				strcopy(sPunishment, sizeof(sPunishment), "banned");
			}
		}
		

		LogToPluginFile("%N (ID: %s | IP: %s) was %s for trying to crash the server with voice data overflow. Total packets: %i", 
		client, 
		id, 
		ip, 
		sPunishment, 
		g_voicePacketCount[client]);
		
		if (IsClientInGame(client) && GetClientListeningFlags(client) == VOICE_MUTED) return; // dont flood
		
		SetClientListeningFlags(client, VOICE_MUTED);
		
		switch (iPunishMent)
		{
			case 1:
			{
				if (!IsClientInKickQueue(client))
				{
					KickClient(client, "Voice data overflow detected!");
				}
			}
			case 2:
			{
				ServerCommand("sm_ban #%d 0 \"Voice data overflow detected!\"", GetClientUserId(client));
			}
		}
	}
}

stock void LogToPluginFile(const char[] format, any ...)
{
	char f_sBuffer[1024], f_sPath[1024];
	VFormat(f_sBuffer, sizeof(f_sBuffer), format, 2);
	BuildPath(Path_SM, f_sPath, sizeof(f_sPath), PATH);
	LogToFile(f_sPath, "%s", f_sBuffer);
}