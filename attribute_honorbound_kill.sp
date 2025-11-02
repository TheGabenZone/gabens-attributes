#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_HONORBOUND_KILL "custom_honorbound_kill"

public Plugin myinfo = 
{
	name = "Attribute: Honorbound Kill",
	author = "TheGabenZone",
	description = "Instantly kills players with the same weapon equipped",
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
	// Validate clients
	if(attacker < 1 || attacker > MaxClients || victim < 1 || victim > MaxClients)
		return Plugin_Continue;
	
	// Don't allow self-damage honorbound kills
	if(attacker == victim)
		return Plugin_Continue;
	
	// Get attacker's active weapon
	int attackerWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
	if(attackerWeapon <= MaxClients)
		return Plugin_Continue;
	
	// Get victim's active weapon
	int victimWeapon = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
	if(victimWeapon <= MaxClients)
		return Plugin_Continue;
	
	char buffer[256];
	
	// Check if attacker's weapon has the honorbound attribute
	if(AttribHookString(buffer, sizeof(buffer), attackerWeapon, ATTR_HONORBOUND_KILL))
	{
		float enabled = StringToFloat(buffer);
		
		if(enabled > 0.0)
		{
			// Get weapon definition indices to compare
			int attackerWeaponIndex = GetEntProp(attackerWeapon, Prop_Send, "m_iItemDefinitionIndex");
			int victimWeaponIndex = GetEntProp(victimWeapon, Prop_Send, "m_iItemDefinitionIndex");
			
			// Check if both players have the same weapon equipped (by item definition index)
			if(attackerWeaponIndex == victimWeaponIndex && attackerWeaponIndex != -1)
			{
				// Apply massive damage to guarantee kill
				damage = float(GetClientHealth(victim)) * 10.0;
				damagetype |= DMG_PREVENT_PHYSICS_FORCE; // Prevent ragdoll physics from force
				
				return Plugin_Changed;
			}
		}
	}
	
	return Plugin_Continue;
}
