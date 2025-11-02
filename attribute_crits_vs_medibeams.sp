#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_CRITS_VS_MEDIBEAMS "custom_crits_vs_medigun_beams"

public Plugin myinfo = 
{
	name = "Attribute: Damage vs Medigun Beams",
	author = "TheGabenZone",
	description = "Damages both medic and patient when hitting a heal target",
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
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	// Validate clients
	if(attacker < 1 || attacker > MaxClients || victim < 1 || victim > MaxClients)
		return;
	
	// Don't allow self-damage
	if(attacker == victim)
		return;
	
	// Make sure victim is alive
	if(!IsPlayerAlive(victim))
		return;
	
	// Get attacker's active weapon
	int attackerWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
	if(attackerWeapon <= MaxClients)
		return;
	
	char buffer[256];
	
	// Check if attacker's weapon has the medibeam damage attribute
	if(AttribHookString(buffer, sizeof(buffer), attackerWeapon, ATTR_CRITS_VS_MEDIBEAMS))
	{
		float enabled = StringToFloat(buffer);
		
		if(enabled > 0.0)
		{
			// Check if victim is being healed by a medic or is healing someone as a medic
			int healingMedic = -1;
			int healingPatient = -1;
			
			// Check if victim is being healed (victim is patient)
			for(int i = 1; i <= MaxClients; i++)
			{
				if(i != victim && IsClientInGame(i) && IsPlayerAlive(i))
				{
					// Check if this player is a medic healing the victim
					int medigun = GetPlayerWeaponSlot(i, 1); // Slot 1 is secondary (medigun for medics)
					if(medigun > MaxClients)
					{
						char classname[64];
						GetEntityClassname(medigun, classname, sizeof(classname));
						
						// Check if it's a medigun
						if(StrContains(classname, "tf_weapon_medigun", false) != -1)
						{
							// Check if the medigun is healing the victim
							int healTarget = GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget");
							if(healTarget == victim)
							{
								healingMedic = i;
								break;
							}
						}
					}
				}
			}
			
			// Check if victim is a medic healing someone (victim is medic)
			int victimMedigun = GetPlayerWeaponSlot(victim, 1);
			if(victimMedigun > MaxClients)
			{
				char classname[64];
				GetEntityClassname(victimMedigun, classname, sizeof(classname));
				
				if(StrContains(classname, "tf_weapon_medigun", false) != -1)
				{
					int healTarget = GetEntPropEnt(victimMedigun, Prop_Send, "m_hHealingTarget");
					if(healTarget > 0 && healTarget <= MaxClients && IsClientInGame(healTarget) && IsPlayerAlive(healTarget))
					{
						healingPatient = healTarget;
					}
				}
			}
			
			// Apply damage to connected players
			if(healingMedic > 0)
			{
				// Victim was hit and is being healed - damage the medic
				// Preserve damage type flags (crits, minicrits, etc)
				SDKHooks_TakeDamage(healingMedic, attacker, attacker, damage, damagetype, attackerWeapon);
			}
			
			if(healingPatient > 0)
			{
				// Victim was hit and is a medic - damage their patient
				// Preserve damage type flags (crits, minicrits, etc)
				SDKHooks_TakeDamage(healingPatient, attacker, attacker, damage, damagetype, attackerWeapon);
			}
		}
	}
}