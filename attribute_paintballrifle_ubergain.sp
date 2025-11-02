#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_PAINTBALLRIFLE_NO_UBER "custom_paintballrifle_ubergain"

public Plugin myinfo = 
{
	name = "Attribute: Paintball Rifle No Uber",
	author = "TheGabenZone",
	description = "Prevents tf_weapon_paintballrifle weapons from building uber when attribute is enabled",
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
	// Validate attacker is a valid client
	if(attacker < 1 || attacker > MaxClients)
		return;
	
	// Check if the weapon is valid
	if(!IsValidEntity(weapon))
		return;
	
	// Get the weapon classname
	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	
	// Check if it's a paintball rifle
	if(StrEqual(classname, "tf_weapon_paintballrifle"))
	{
		char buffer[256];
		
		// Check if weapon has the no-uber attribute
		if(AttribHookString(buffer, sizeof(buffer), weapon, ATTR_PAINTBALLRIFLE_NO_UBER))
		{
			// Parse values: 1st = enabled
			float values[1];
			int valueCount = ParseAttributeValues(buffer, values, 1);
			
			if(valueCount >= 1 && values[0] > 0.0)
			{
				// Attribute is enabled, prevent uber building
				
				// Get the attacker's medigun (if they have one equipped)
				int medigun = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Secondary);
				
				if(IsValidEntity(medigun))
				{
					char medigunClass[64];
					GetEntityClassname(medigun, medigunClass, sizeof(medigunClass));
					
					// Check if it's a medigun
					if(StrEqual(medigunClass, "tf_weapon_medigun"))
					{
						// Get current charge level
						float currentCharge = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
						
						// Set it back to what it was (preventing uber build from this damage)
						// We need to delay this slightly to override the game's uber building
						DataPack pack = new DataPack();
						pack.WriteCell(GetClientUserId(attacker));
						pack.WriteFloat(currentCharge);
						RequestFrame(ResetUberCharge, pack);
					}
				}
			}
		}
	}
}

public void ResetUberCharge(DataPack pack)
{
	pack.Reset();
	int userId = pack.ReadCell();
	float charge = pack.ReadFloat();
	delete pack;
	
	int client = GetClientOfUserId(userId);
	if(client < 1 || !IsClientInGame(client))
		return;
	
	int medigun = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if(!IsValidEntity(medigun))
		return;
	
	SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", charge);
}

int ParseAttributeValues(const char[] input, float[] output, int maxValues)
{
	char pieces[16][32];
	int count = ExplodeString(input, " ", pieces, sizeof(pieces), sizeof(pieces[]));
	
	if(count > maxValues)
		count = maxValues;
	
	for(int i = 0; i < count; i++)
	{
		output[i] = StringToFloat(pieces[i]);
	}
	
	return count;
}