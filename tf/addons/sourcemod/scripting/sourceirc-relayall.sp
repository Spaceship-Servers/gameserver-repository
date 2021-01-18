/*
	   This file is part of SourceIRC.

	SourceIRC is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	SourceIRC is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with SourceIRC.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <sourcemod>
#include <regex>
#include <tf2_stocks.inc>
#undef REQUIRE_PLUGIN
#include <sourceirc>
#include <clientprefs>

new g_userid = 0;

new bool:g_isteam = false;
new bool:g_bShowIRC[MAXPLAYERS+1];
new bool:g_bLateLoad;
new Handle:g_cvAllowHide;
new Handle:g_cvAllowFilter;
new Handle:g_cvHideDisconnect;
new Handle:g_cvShowMapChanges;
new Handle:g_hIRCboolCookie;

public Plugin:myinfo = {
	name = "SourceIRC -> Relay All",
	author = "Azelphur",
	description = "Relays various game events",
	version = IRC_VERSION,
	url = "http://azelphur.com/"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public OnPluginStart() {
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
	HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Post);
	HookEvent("player_say", Event_PlayerSay, EventHookMode_Post);
	HookEvent("player_chat", Event_PlayerSay, EventHookMode_Post);

	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say2", Command_Say);
	RegConsoleCmd("say_team", Command_SayTeam);
	RegConsoleCmd("sm_irc", cmdIRC, "Toggles IRC chat");
	g_cvAllowHide = CreateConVar("irc_allow_hide", "0", "Sets whether players can hide IRC chat", FCVAR_NOTIFY);
	g_cvAllowFilter = CreateConVar("irc_allow_filter", "0", "Sets whether IRC filters sentences beginning with !", FCVAR_NOTIFY);
	g_cvHideDisconnect = CreateConVar("irc_disconnect_filter", "0", "Sets whether IRC filters disconnect messages", FCVAR_NOTIFY);
	g_cvShowMapChanges = CreateConVar("irc_show_mapchanges", "1", "Sets whether IRC prints map changes", FCVAR_NOTIFY);

	LoadTranslations("sourceirc.phrases");

	g_hIRCboolCookie = RegClientCookie("ircboolcookie", "cookie for determining if irc chat is on or off for user", CookieAccess_Protected);
}

public OnAllPluginsLoaded() {
	if (LibraryExists("sourceirc"))
		IRC_Loaded();
}

public OnLibraryAdded(const String:name[]) {
	if (StrEqual(name, "sourceirc"))
		IRC_Loaded();
}

IRC_Loaded() {
	IRC_CleanUp(); // Call IRC_CleanUp as this function can be called more than once.
	IRC_HookEvent("PRIVMSG", Event_PRIVMSG);
}

public Action:Command_Say(client, args) {
	g_isteam = false; // Ugly hack to get around player_chat event not working.
}

public Action:Command_SayTeam(client, args) {
	g_isteam = true; // Ugly hack to get around player_chat event not working.
}

public Action:Event_PlayerSay(Handle:event, const String:name[], bool:dontBroadcast) {
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);

	decl String:result[IRC_MAXLEN], String:message[256];
	result[0] = '\0';
	GetEventString(event, "text", message, sizeof(message));
	if (GetConVarBool(g_cvAllowFilter)) {
		if (message[0] == '!') {
			return Plugin_Continue;
		}
	}
	// ONLY WORKS FOR TF2 I DONT PLAY OTHER SOURCE GAMES
	if (IsValidClient(client) && (TF2_GetClientTeam(client) == TFTeam_Unassigned || TF2_GetClientTeam(client) == TFTeam_Spectator))
	{
		StrCat(result, sizeof(result), "*SPEC* ");
	}
	else if (IsValidClient(client) && !IsPlayerAlive(client))
	{
		StrCat(result, sizeof(result), "*DEAD* ");
	}

	if (IsValidClient(client) && g_isteam)
	{
		StrCat(result, sizeof(result), "(TEAM) ");
	}
	new team
	if (IsValidClient(client))
		team = IRC_GetTeamColor(GetClientTeam(client));
	else
		team = 0;
	if (team == -1)
		Format(result, sizeof(result), "%s%N: %s", result, client, message);
	else
		Format(result, sizeof(result), "%s\x03%02d%N\x03: %s", result, team, client, message);

	IRC_MsgFlaggedChannels("relay", "%s", result);
	return Plugin_Continue;
}


public void OnClientAuthorized(client, const String:auth[]) { // We are hooking this instead of the player_connect event as we want the steamid
	new userid = GetClientUserId(client);
	if (userid <= g_userid) // Ugly hack to get around mass connects on map change
		return;
	g_userid = userid;
	decl String:playername[MAX_NAME_LENGTH], String:result[IRC_MAXLEN];
	GetClientName(client, playername, sizeof(playername));
	Format(result, sizeof(result), "%t", "Player Connected", playername, auth, userid);
	if (result[0] != '\0' && !IsFakeClient(client))
		IRC_MsgFlaggedChannels("relay", "%s", result);
}

public Action:Event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarBool(g_cvHideDisconnect)) {
		new userid = GetEventInt(event, "userid");
		new client = GetClientOfUserId(userid);
		if (IsValidClient(client)) {
			decl String:reason[128], String:playername[MAX_NAME_LENGTH], String:auth[64], String:result[IRC_MAXLEN];
			GetEventString(event, "reason", reason, sizeof(reason));
			GetClientName(client, playername, sizeof(playername));
			GetClientAuthId(client, AuthId_Engine, auth, sizeof(auth));
			for (new i = 0; i <= strlen(reason); i++) { // For some reason, certain disconnect reasons have \n in them, so i'm stripping them. Silly valve.
				if (reason[i] == '\n')
					RemoveChar(reason, sizeof(reason), i);
			}
			Format(result, sizeof(result), "%t", "Player Disconnected", playername, auth, userid, reason);
			if (result[0] != '\0' && !IsFakeClient(client))
				IRC_MsgFlaggedChannels("relay", "%s", result);
		}
	}
}

public Action:Event_PlayerChangeName(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	if (IsValidClient(client))
	{
		decl String:oldname[128], String:newname[MAX_NAME_LENGTH], String:auth[64], String:result[IRC_MAXLEN];
		GetEventString(event, "oldname", oldname, sizeof(oldname));
		GetEventString(event, "newname", newname, sizeof(newname));
		GetClientAuthId(client, AuthId_Engine, auth, sizeof(auth));
		Format(result, sizeof(result), "%t", "Changed Name", oldname, auth, userid, newname);
		if (result[0] != '\0')
			IRC_MsgFlaggedChannels("relay", "%s", result);
	}
}

public OnMapEnd() {
	g_bLateLoad = false;
	if (GetConVarBool(g_cvShowMapChanges)) {
		IRC_MsgFlaggedChannels("relay", "%t", "Map Changing");
	}
}

public OnMapStart() {
	if (g_bLateLoad) {
		return;
	}
	if (GetConVarBool(g_cvShowMapChanges)) {
		decl String:map[128];
		GetCurrentMap(map, sizeof(map));
		IRC_MsgFlaggedChannels("relay", "%t", "Map Changed", map);
	}
}

public Action:Event_PRIVMSG(const String:hostmask[], args) {
	decl String:channel[64];
	IRC_GetEventArg(1, channel, sizeof(channel));
	if (IRC_ChannelHasFlag(channel, "relay")) {
		decl String:nick[IRC_NICK_MAXLEN], String:text[IRC_MAXLEN];
		IRC_GetNickFromHostMask(hostmask, nick, sizeof(nick));
		IRC_GetEventArg(2, text, sizeof(text));
		if (!strncmp(text, "\x01ACTION ", 8) && text[strlen(text)-1] == '\x01') {
			text[strlen(text)-1] = '\x00';
			IRC_Strip(text, sizeof(text)); // Strip IRC Color Codes
			IRC_StripGame(text, sizeof(text)); // Strip Game color codes

			for (new i=1; i<=MaxClients; i++) {
				if (IsClientInGame(i) && !IsFakeClient(i) && g_bShowIRC[i]) {
				PrintToChat(i, "\x01[\x04IRC\x01] * %s %s", nick, text[7]);
				}
			}
		}
		else {
			IRC_Strip(text, sizeof(text)); // Strip IRC Color Codes
			IRC_StripGame(text, sizeof(text)); // Strip Game color codes

			for (new i=1; i<=MaxClients; i++) {
				if (IsClientInGame(i) && !IsFakeClient(i) && g_bShowIRC[i]) {
				PrintToChat(i, "\x01[\x04IRC\x01] %s :  %s", nick, text);
				}
			}
		}
	}
}

public void OnClientCookiesCached(int client)
{
	if (IsValidClient(client))
	{
		char sValue[8];
		GetClientCookie(client, g_hIRCboolCookie, sValue, sizeof(sValue)); // Gets stored value for specific client and stores in sValue
		if (!sValue[0])   // If the string is null, it'll be set to true - we want irc defaulted on
		{
			SetClientCookie(client, g_hIRCboolCookie, "1");
			sValue = "1";
			g_bShowIRC[client] = (StringToInt(sValue) != 0);
			SetClientCookie(client, g_hIRCboolCookie, sValue); // save to cookie
		}
		else
		{
			g_bShowIRC[client] = (StringToInt(sValue) != 0);
		}
	}
}

public Action:cmdIRC(client, iArgC) {
	if (IsValidClient(client))
	{
		if (GetConVarBool(g_cvAllowHide)) {
			g_bShowIRC[client] = !g_bShowIRC[client]; // Flip boolean
			if (AreClientCookiesCached(client))
			{
				char sValue[8];
				IntToString(g_bShowIRC[client], sValue, sizeof(sValue)); // convert to string
				SetClientCookie(client, g_hIRCboolCookie, sValue); 		 // save to cookie
			}
			if (g_bShowIRC[client]) {
				ReplyToCommand(client, "[SourceIRC] Now listening to IRC chat");
			}
			else {
				ReplyToCommand(client, "[SourceIRC] Stopped listening to IRC chat");
			}
		}
		else {
			PrintToChat(client, "\x01[\x04IRC\x01] IRC Hide not allowed for this server");
		}
	}
	return Plugin_Handled;
}

public OnPluginEnd() {
	IRC_CleanUp();
}

// cleaned up IsValidClient Stock
stock bool:IsValidClient(client)
{
	if  (
			client <= 0
			|| client > MaxClients
			|| !IsClientConnected(client)
			|| IsFakeClient(client)
		)
	{
		return false;
	}
	return IsClientInGame(client);
}

// http://bit.ly/defcon
