#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_BONK_CONSUMPTION "custom_bonk_consumption_boost"

public Plugin myinfo = 
{
	name = "Bonk Consumption Boost",
	author = "TheGabenZone",
	description = "Custom bonk effect when consuming lunchbox items",
	version = PLUGIN_VERSION,
	url = ""
};

// Player data arrays
bool g_bBonkActive[MAXPLAYERS+1];
float g_flBonkEndTime[MAXPLAYERS+1];
bool g_bWasTaunting[MAXPLAYERS+1];
int g_iLunchboxWeapon[MAXPLAYERS+1] = {-1, ...};

public void OnPluginStart()
{
	// Hook events
	HookEvent("player_spawn", Event_PlayerSpawn);
	
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
	ResetPlayerData(client);
	SDKHook(client, SDKHook_PreThink, OnPlayerPreThink);
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnWeaponCanSwitch);
}

public void OnClientDisconnect(int client)
{
	ResetPlayerData(client);
}

void ResetPlayerData(int client)
{
	g_bBonkActive[client] = false;
	g_flBonkEndTime[client] = 0.0;
	g_bWasTaunting[client] = false;
	g_iLunchboxWeapon[client] = -1;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0)
	{
		ResetPlayerData(client);
	}
}

public void OnPlayerPreThink(int client)
{
	if(!IsPlayerAlive(client))
		return;
	
	// Block attacks during bonk
	if(g_bBonkActive[client])
	{
		int buttons = GetClientButtons(client);
		if(buttons & IN_ATTACK || buttons & IN_ATTACK2)
		{
			// Remove attack buttons
			SetEntProp(client, Prop_Data, "m_nButtons", buttons & ~IN_ATTACK & ~IN_ATTACK2);
		}
	}
	
	// Update bonk state
	if(g_bBonkActive[client] && GetGameTime() > g_flBonkEndTime[client])
	{
		DeactivateBonk(client);
	}
	
	// Detect lunchbox consumption with bonk_consumption_boost attribute
	bool isTaunting = TF2_IsPlayerInCondition(client, TFCond_Taunting);
	
	if(isTaunting && !g_bWasTaunting[client])
	{
		// Player just started taunting
		int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if(activeWeapon > MaxClients)
		{
			char classname[64];
			GetEntityClassname(activeWeapon, classname, sizeof(classname));
			
			// Check if it's a lunchbox item
			if(StrEqual(classname, "tf_weapon_lunchbox") || StrEqual(classname, "tf_weapon_lunchbox_drink"))
			{
				char buffer[256];
				if(AttribHookString(buffer, sizeof(buffer), activeWeapon, ATTR_BONK_CONSUMPTION))
				{
					float values[3];
					if(ParseAttributeValues(buffer, values, 3) >= 3 && values[0] > 0.0)
					{
						// Store the weapon and activate bonk after a delay
						g_iLunchboxWeapon[client] = EntIndexToEntRef(activeWeapon);
						
						DataPack pack;
						CreateDataTimer(1.0, Timer_ActivateBonk, pack);
						pack.WriteCell(GetClientUserId(client));
					}
				}
			}
		}
	}
	
	g_bWasTaunting[client] = isTaunting;
}

public Action OnWeaponCanSwitch(int client, int weapon)
{
	// Block weapon switching during bonk
	if(g_bBonkActive[client])
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_ActivateBonk(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	
	int client = GetClientOfUserId(userid);
	int weaponRef = g_iLunchboxWeapon[client];
	int weapon = EntRefToEntIndex(weaponRef);
	
	if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && weapon > MaxClients)
	{
		ActivateBonk(client, weapon);
		g_iLunchboxWeapon[client] = -1;
	}
	
	return Plugin_Stop;
}

void ActivateBonk(int client, int weapon)
{
	char buffer[256];
	if(!AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BONK_CONSUMPTION))
		return;
	
	float values[3];
	if(ParseAttributeValues(buffer, values, 3) < 3)
		return;
	
	float duration = values[1];
	float mfdDuration = values[2];
	
	g_bBonkActive[client] = true;
	g_flBonkEndTime[client] = GetGameTime() + duration;
	
	// Apply invulnerability
	TF2_AddCondition(client, view_as<TFCond>(52), duration);
	
	// Schedule marked for death
	DataPack pack;
	CreateDataTimer(duration, Timer_ApplyMarkedForDeath, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(mfdDuration);
}

public Action Timer_ApplyMarkedForDeath(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	float duration = pack.ReadFloat();
	
	int client = GetClientOfUserId(userid);
	if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		TF2_AddCondition(client, TFCond_MarkedForDeath, duration);
	}
	
	return Plugin_Stop;
}

void DeactivateBonk(int client)
{
	g_bBonkActive[client] = false;
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
