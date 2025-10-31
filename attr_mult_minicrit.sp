#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_MULT_MINICRIT "custom_mult_minicrit_dmg"

public Plugin myinfo = 
{
	name = "Attribute: Mini-Crit Damage Multiplier",
	author = "TheGabenZone",
	description = "Modifies damage dealt when player has mini-crit boost",
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
	
	// Mini-crit damage multiplier
	if(AttribHookString(buffer, sizeof(buffer), activeWeapon, ATTR_MULT_MINICRIT))
	{
		// Check if attacker has mini-crit boost conditions
		// Conditions 112 (VIP Umbrella) and 123 (Ubercharge Mini-crit)
		bool hasMiniCritBoost = TF2_IsPlayerInCondition(attacker, view_as<TFCond>(112)) || 
		                        TF2_IsPlayerInCondition(attacker, view_as<TFCond>(123));
		
		// Also check if victim has marked for death (makes them take mini-crits)
		bool victimMarkedForDeath = TF2_IsPlayerInCondition(victim, view_as<TFCond>(30)) ||
		                            TF2_IsPlayerInCondition(victim, view_as<TFCond>(115)) ||
		                            TF2_IsPlayerInCondition(victim, view_as<TFCond>(116));
		
		// Apply multiplier if there's a mini-crit boost (and not a full crit)
		if((hasMiniCritBoost || victimMarkedForDeath) && !(damagetype & DMG_CRIT))
		{
			float multiplier = StringToFloat(buffer);
			damage *= multiplier;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}
