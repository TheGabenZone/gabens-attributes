#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Custom damage type for tracking mini-crits internally
// Note: TF2C uses DMG_CRIT for both crits and mini-crits, but we need to differentiate
#define DMG_MINICRIT (1 << 30) // Custom tracking flag
#define DMG_MINICRIT_PROCESSED (1 << 31) // Flag to prevent double application

// Attribute Name
#define ATTR_MULT_MINICRIT "custom_mult_minicrit_dmg"

public Plugin myinfo = 
{
	name = "Mini-Crit Damage Multiplier",
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
	// Note: In TF2/TF2C, we detect mini-crits by checking for specific mini-crit boosting conditions
	if(AttribHookString(buffer, sizeof(buffer), activeWeapon, ATTR_MULT_MINICRIT))
	{
		// Check if attacker has mini-crit boosting conditions but not full crit boost
		bool hasMiniCritBoost = false;
		bool hasFullCritBoost = false;
			
		// Check for full crit boost (Kritzkrieg, etc.) - Condition 11
		if(TF2_IsPlayerInCondition(attacker, view_as<TFCond>(11)))
		{
			hasFullCritBoost = true;
		}
			
		// TF2C Mini-Crit Boost Conditions:
		// 112 - VIP Umbrella boost
		// 123 - Ubercharge Mini-crit boost
		if(TF2_IsPlayerInCondition(attacker, view_as<TFCond>(112)))
		{
			hasMiniCritBoost = true;
		}
		if(TF2_IsPlayerInCondition(attacker, view_as<TFCond>(123)))
		{
			hasMiniCritBoost = true;
		}
			
		// TF2C Marked for Death Conditions (victim takes mini-crits):
		// 30 - Marked for Death
		// 115 - Super Marked for Death
		// 116 - Super Marked for Death Silent
		if(TF2_IsPlayerInCondition(victim, view_as<TFCond>(30)))
		{
			hasMiniCritBoost = true;
		}
		if(TF2_IsPlayerInCondition(victim, view_as<TFCond>(115)))
		{
			hasMiniCritBoost = true;
		}
		if(TF2_IsPlayerInCondition(victim, view_as<TFCond>(116)))
		{
			hasMiniCritBoost = true;
		}
			
		// Apply multiplier if mini-crit boost is active but not full crit boost
		if(hasMiniCritBoost && !hasFullCritBoost)
		{
			float multiplier = StringToFloat(buffer);
			damage *= multiplier;
				
			// Mark this damage as processed to prevent double application
			damagetype |= DMG_MINICRIT_PROCESSED;
			
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}
