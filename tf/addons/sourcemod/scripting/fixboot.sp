// this forces server settings to get properly set up after the server first reboots
// on boot there's a bunch of fucking race conditions with plugins and cfgs and this just
// fixes that.

bool firstmap = true;

public void OnMapStart()
{
    CreateTimer(5.0, GoToNextMap);
}

Action GoToNextMap(Handle timer)
{
    if (firstmap)
    {
        firstmap = false;
	ServerCommand("sm exts load cleaner");
        ServerCommand("changelevel_next");
    }
}
