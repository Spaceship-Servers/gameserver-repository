char possibleTFTrueLocations[][] =
{
    "/custom/TFTrue.so",
    "/custom/TFTrue.vdf",
    "/custom/TFTrue.dll",
    "/addons/TFTrue.so",
    "/addons/TFTrue.vdf",
    "/addons/TFTrue.dll",
};

public void OnMapStart()
{
    bool needsRestart;
    for (int i = 0; i < sizeof(possibleTFTrueLocations); i++)
    {
        if (FileExists(possibleTFTrueLocations[i]))
        {
            LogMessage("found tftrue at %s. deleting!", possibleTFTrueLocations[i]);
            if (DeleteFile(possibleTFTrueLocations[i]))
            {
                LogMessage("deleted %s", possibleTFTrueLocations[i]);
                needsRestart = true;
            }
            else
            {
                LogMessage("FAILED deleting %s!", possibleTFTrueLocations[i]);
            }
        }
    }
    if (needsRestart)
    {
        ServerCommand("_restart");
    }
}
