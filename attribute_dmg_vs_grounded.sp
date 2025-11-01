#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_DMG_VS_GROUNDED "custom_dmg_vs_grounded_players"

public Plugin myinfo = 
{
	name = "Attribute: Damage vs Grounded Targets",
	author = "TheGabenZone",
	description = "Increases damage against grounded targets",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	// Late load support
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(attacker < 1 || attacker > MaxClients || victim < 1 || victim > MaxClients)
		return Plugin_Continue;
	
	// Get attacker's weapon
	int activeWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
	if(activeWeapon <= MaxClients)
		return Plugin_Continue;
	
	char buffer[256];
	
	// Damage vs grounded targets
	if(AttribHookString(buffer, sizeof(buffer), activeWeapon, ATTR_DMG_VS_GROUNDED))
	{
		float multiplier = StringToFloat(buffer);
		if(!IsPlayerAirborne(victim))
		{
			damage *= multiplier;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

bool IsPlayerAirborne(int client)
{
	if(!IsPlayerAlive(client))
		return false;
	
	int flags = GetEntityFlags(client);
	return !(flags & FL_ONGROUND);
}
