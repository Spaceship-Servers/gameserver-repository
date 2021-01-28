#pragma semicolon 1

#include <sourcemod>
#include <color_literals>
#include <sourcebanspp>
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION  "0.0.5"
#define UPDATE_URL      "https://raw.githubusercontent.com/stephanieLGBT/spaceship-servers-plugin/master/updatefile.txt"

// bracket color
#define bColor "1F1F2A"
// text color
#define tColor "696996"
// actual tag
#define sTag "\x07" ... bColor ... "[" ... "\x07" ... tColor ... "Spaceship Servers" ... "\x07" ... bColor ... "]" ... COLOR_DEFAULT ... " "
// discord link
#define discordLink "discord.gg/Dn4wRu3"
// pretty discord link (colored)
#define pDiscord COLOR_DODGERBLUE ... discordLink ... COLOR_DEFAULT

public Plugin myinfo =
{
    name             =  "Spaceship Servers Plugin",
    author           =  "stephanie",
    description      =  "handles misc stuff for all spaceship servers",
    version          =   PLUGIN_VERSION,
    url              =  "https://sappho.io"
}

char hostname[84];

// plugin just started
public OnPluginStart()
{
    // updater
    if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public OnMapStart()
{
    GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
}

public OnMapEnd()
{
    GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
}

// player join
public OnClientPostAdminCheck(Cl)
{
    GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
    CreateTimer(10.0, WelcomeClient, GetClientUserId(Cl), TIMER_FLAG_NO_MAPCHANGE);
}

// greet player!
public Action WelcomeClient(Handle timer, int userid)
{
    int Cl = GetClientOfUserId(userid);
    if (IsValidClient(Cl))
    {
        PrintColoredChat(Cl, sTag ... "Welcome to \x07" ... tColor ... "%s", hostname);
        PrintColoredChat(Cl, sTag ... "To turn off cross server IRC chat, type " ... COLOR_GREEN ... "/irc" ... COLOR_DEFAULT ... ".");
        PrintColoredChat(Cl, sTag ... "To see information about the discord, type " ... COLOR_SKYBLUE ... "!discord" ... COLOR_DEFAULT ... ".");
    }
}

public Action OnClientSayCommand(int Cl, const char[] command, const char[] sArgs)
{
    if (IsValidClient(Cl))
    {
        if (StrContains(sArgs, "!calladmin", false) != -1)
        {
            PrintColoredChat(Cl, sTag ... "Try typing !call to report a player. To report a server issue, join the Discord by typing !discord");
        }
        if
        (
            StrContains(sArgs, "!discord", false) != -1
            ||
            StrContains(sArgs, "/discord", false) != -1
        )
        {
            PrintColoredChat(Cl, sTag ... "Join the Discord over at " ... pDiscord ... "!");
            return Plugin_Stop;
        }
    }
    return Plugin_Continue;
}

bool IsValidClient(int client)
{
    return
    (
        (0 < client <= MaxClients)
        && IsClientInGame(client)
        && !IsFakeClient(client)
    );
}