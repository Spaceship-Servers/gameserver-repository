#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
    name             = "No Sentries!",
    author           = "steph&nie",
    description      = "Prevents clients from building sentries and tells them that they can't build",
    version          = "0.0.1",
    url              = "https://sappho.io"
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "obj_sentrygun"))
    {
        RequestFrame(KillSentry, EntIndexToEntRef(entity));
    }
}

void KillSentry(int entityref)
{
    int entity = EntRefToEntIndex(entityref)
    if (IsValidEntity(entity))
    {
        int builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
        RemoveEntity(entity);
        EmitSoundToClient(builder, "vo/engineer_no01.mp3");
        PrintHintText(builder, "This is a Deathmatch server! You can't build sentries!")
    }
}
