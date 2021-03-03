public void OnMapStart()
{
    CreateTimer(0.1, checkPrintOut);
}

Action checkPrintOut(Handle timer)
{
    char pluginPrintOut[512];
    ServerCommandEx(pluginPrintOut, sizeof(pluginPrintOut), "plugin_print");

    // strip the hyphens
    ReplaceString(pluginPrintOut, sizeof(pluginPrintOut), "-",  "\0");
    // strip this dumb print
    ReplaceString(pluginPrintOut, sizeof(pluginPrintOut), "Loaded plugins:", "\0");
    // strip tabs
    ReplaceString(pluginPrintOut, sizeof(pluginPrintOut), "\t", " ");
    // strip any whitespace chars on the edges of the string
    TrimString(pluginPrintOut);
    // get num of plugin indexes here by counting the remaining \n characters ( this is # of plugins - 1 )
    int lines = ReplaceString(pluginPrintOut, sizeof(pluginPrintOut), "\n", "\n");
    for (int i = 0; i <= lines; i++)
    {
        char buff[16];
        Format(buff, sizeof(buff), "%i: \"TFTrue", i);
        LogMessage("searching for %s", buff);
        if (StrContains(pluginPrintOut, buff) != -1)
        {
            LogMessage("Found tftrue at plugin index %i - unloading!", i);
            ServerCommand("plugin_unload %i", i);
            // just in case somehow they have more than one loaded
            continue;
        }
    }
}

/*
Loaded plugins:
---------------------
0:      "TFTrue v4.79, AnAkkk"
1:      "Metamod:Source 1.10.7-dev"
---------------------
*/
