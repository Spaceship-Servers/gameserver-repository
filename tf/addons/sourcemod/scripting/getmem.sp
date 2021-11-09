#include <sourcemod>
#define REQUIRE_EXTENSIONS
#include <getmem>

public void OnPluginStart()
{
     RegServerCmd("sm_getmem", GetMem_CB, "Print the current memory usage of this server, in kilobytes.");
}

Action GetMem_CB(int args)
{
    int kb = GetMem();
    PrintToServer("%i KB", kb);
}
