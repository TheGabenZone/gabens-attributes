#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>
#include <hudframework>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_BANNER_BOOST "custom_banner_boost"

// Constants
#define THINK_INTERVAL 0.1

public Plugin myinfo = 
{
	name = "Attribute: Banner Boost",
	author = "TheGabenZone",
	description = "Custom banner mechanic with charge and activation",
	version = PLUGIN_VERSION,
	url = ""
};

// Player data arrays
bool g_bBannerActive[MAXPLAYERS+1];
float g_flBannerEndTime[MAXPLAYERS+1];
int g_iBannerProvider[MAXPLAYERS+1] = {-1, ...}; // Who is providing banner buff to this player
int g_iLastButtons[MAXPLAYERS+1];

public void OnPluginStart()
{
	// Hook events
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("teamplay_round_start", Event_RoundStart);
	
	// Late load support
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
	
	// Create timer for think functions
	CreateTimer(THINK_INTERVAL, Timer_Think, _, TIMER_REPEAT);
}

public void OnClientPutInServer(int client)
{
	ResetPlayerData(client);
	SDKHook(client, SDKHook_PreThink, OnPlayerPreThink);
}

public void OnClientDisconnect(int client)
{
	ResetPlayerData(client);
}

void ResetPlayerData(int client)
{
	Tracker_Remove(client, "Banner");
	g_bBannerActive[client] = false;
	g_flBannerEndTime[client] = 0.0;
	g_iBannerProvider[client] = -1;
	g_iLastButtons[client] = 0;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0)
	{
		ResetPlayerData(client);
	}
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if(attacker > 0 && victim > 0 && attacker != victim)
	{
		// Banner boost: Check ALL weapon slots and wearables for the attribute
		bool hasBannerBoost = false;
		int damageThreshold = 0;
		char buffer[256];
		
		// Check all weapon slots
		for(int slot = 0; slot < 5; slot++)
		{
			int checkWeapon = GetPlayerWeaponSlot(attacker, slot);
			if(checkWeapon > MaxClients && AttribHookString(buffer, sizeof(buffer), checkWeapon, ATTR_BANNER_BOOST))
			{
				float values[16];
				int numValues = ParseAttributeValues(buffer, values, sizeof(values));
				if(numValues >= 3)
				{
					hasBannerBoost = true;
					damageThreshold = RoundToFloor(values[1]);
					break;
				}
			}
		}
		
		// Check wearables if not found in weapons
		if(!hasBannerBoost)
		{
			int wearable = -1;
			while((wearable = FindEntityByClassname(wearable, "tf_wearable")) != -1)
			{
				if(GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity") == attacker)
				{
					if(AttribHookString(buffer, sizeof(buffer), wearable, ATTR_BANNER_BOOST))
					{
						float values[16];
						int numValues = ParseAttributeValues(buffer, values, sizeof(values));
						if(numValues >= 3)
						{
							hasBannerBoost = true;
							damageThreshold = RoundToFloor(values[1]);
							break;
						}
					}
				}
			}
		}
		
		if(hasBannerBoost && !g_bBannerActive[attacker])
		{
			int damage = event.GetInt("damageamount");
			
			// Add damage to tracker
			float currentValue = Tracker_GetValue(attacker, "Banner");
			Tracker_SetValue(attacker, "Banner", currentValue + float(damage));
		}
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Reset all player data
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			ResetPlayerData(i);
		}
	}
}

public void OnPlayerPreThink(int client)
{
	if(!IsPlayerAlive(client))
		return;
	
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	
	// Check for banner activation via reload key (BEFORE button tracking update)
	if(weapon > MaxClients)
	{
		char buffer[256];
		if(AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BANNER_BOOST))
		{
			float values[16];
			int numValues = ParseAttributeValues(buffer, values, sizeof(values));
			if(numValues >= 3)
			{
				int damageThreshold = RoundToFloor(values[1]);
				
				// Check if player has enough charge and presses reload
				int buttons = GetClientButtons(client);
				bool reloadPressed = (buttons & IN_RELOAD) && !(g_iLastButtons[client] & IN_RELOAD);
				
				float currentCharge = Tracker_GetValue(client, "Banner");
				if(reloadPressed && currentCharge >= float(damageThreshold) && !g_bBannerActive[client])
				{
					ActivateBanner(client, weapon);
				}
			}
		}
	}
	
	// Track buttons AFTER all checks
	g_iLastButtons[client] = GetClientButtons(client);
	
	// Update banner state
	if(g_bBannerActive[client] && GetGameTime() > g_flBannerEndTime[client])
	{
		DeactivateBanner(client);
	}
}

public Action Timer_Think(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i))
		{
			// Update banner tracker and effects for teammates
			UpdateBannerTracker(i);
			UpdateBannerEffects(i);
		}
	}
	return Plugin_Continue;
}

void UpdateBannerTracker(int client)
{
	// Check if player has a weapon with banner_boost attribute
	bool hasBannerBoost = false;
	int damageThreshold = 0;
	char buffer[256];
	
	// Check all weapon slots
	for(int slot = 0; slot < 5; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if(weapon > MaxClients && AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BANNER_BOOST))
		{
			float values[16];
			int numValues = ParseAttributeValues(buffer, values, sizeof(values));
			if(numValues >= 3)
			{
				hasBannerBoost = true;
				damageThreshold = RoundToFloor(values[1]);
				break;
			}
		}
	}
	
	// Check wearables if not found in weapons
	if(!hasBannerBoost)
	{
		int wearable = -1;
		while((wearable = FindEntityByClassname(wearable, "tf_wearable")) != -1)
		{
			if(GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity") == client)
			{
				if(AttribHookString(buffer, sizeof(buffer), wearable, ATTR_BANNER_BOOST))
				{
					float values[16];
					int numValues = ParseAttributeValues(buffer, values, sizeof(values));
					if(numValues >= 3)
					{
						hasBannerBoost = true;
						damageThreshold = RoundToFloor(values[1]);
						break;
					}
				}
			}
		}
	}
	
	if(hasBannerBoost)
	{
		// Check if tracker already exists
		float currentValue = Tracker_GetValue(client, "Banner");
		
		// Create tracker if it doesn't exist (GetValue returns 0.0 for non-existent trackers)
		// Only create with overwrite=false to preserve existing value
		Tracker_Create(client, "Banner", false);
		Tracker_SetMax(client, "Banner", float(damageThreshold));
		Tracker_SetFlags(client, "Banner", RTF_CLEARONSPAWN);
	}
	else
	{
		// Remove tracker if no banner boost attribute
		Tracker_Remove(client, "Banner");
	}
}

void UpdateBannerEffects(int client)
{
	// Check if any player is providing a banner effect
	for(int provider = 1; provider <= MaxClients; provider++)
	{
		if(provider != client && IsClientInGame(provider) && IsPlayerAlive(provider) && g_bBannerActive[provider])
		{
			// Get the banner weapon
			int weapon = GetEntPropEnt(provider, Prop_Send, "m_hActiveWeapon");
			if(weapon <= MaxClients)
				continue;
			
			char buffer[256];
			if(!AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BANNER_BOOST))
				continue;
			
			float values[16];
			int numValues = ParseAttributeValues(buffer, values, sizeof(values));
			if(numValues < 7)
				continue;
			
			float duration = values[2];
			float bannerRange = values[3];
			bool affectTeammates = values[4] > 0.0;
			bool affectEnemies = values[5] > 0.0;
			
			// Check if this banner affects teammates and if we're on the same team
			if(affectTeammates && TF2_GetClientTeam(client) == TF2_GetClientTeam(provider))
			{
				// Check distance
				float clientPos[3], providerPos[3];
				GetClientAbsOrigin(client, clientPos);
				GetClientAbsOrigin(provider, providerPos);
				float distance = GetVectorDistance(clientPos, providerPos);
				
				if(distance <= bannerRange)
				{
					// Within range - ensure conditions are applied
					if(g_iBannerProvider[client] != provider)
					{
						g_iBannerProvider[client] = provider;
						
						// Apply conditions
						for(int j = 6; j < numValues; j++)
						{
							int condId = RoundToFloor(values[j]);
							if(condId > 0)
							{
								float remainingTime = g_flBannerEndTime[provider] - GetGameTime();
								if(remainingTime > 0.0)
								{
									TF2_AddCondition(client, view_as<TFCond>(condId), remainingTime);
								}
							}
						}
					}
					return; // Found an active banner provider
				}
			}
			// Check if this banner affects enemies and if we're on different teams
			else if(affectEnemies && TF2_GetClientTeam(client) != TF2_GetClientTeam(provider))
			{
				// Check distance
				float clientPos[3], providerPos[3];
				GetClientAbsOrigin(client, clientPos);
				GetClientAbsOrigin(provider, providerPos);
				float distance = GetVectorDistance(clientPos, providerPos);
				
				if(distance <= bannerRange)
				{
					// Within range - ensure conditions are applied
					if(g_iBannerProvider[client] != provider)
					{
						g_iBannerProvider[client] = provider;
						
						// Apply conditions
						for(int j = 6; j < numValues; j++)
						{
							int condId = RoundToFloor(values[j]);
							if(condId > 0)
							{
								float remainingTime = g_flBannerEndTime[provider] - GetGameTime();
								if(remainingTime > 0.0)
								{
									TF2_AddCondition(client, view_as<TFCond>(condId), remainingTime);
								}
							}
						}
					}
					return; // Found an active banner provider
				}
			}
		}
	}
	
	// No banner provider found or out of range - remove conditions if we had a provider
	if(g_iBannerProvider[client] != -1)
	{
		int oldProvider = g_iBannerProvider[client];
		g_iBannerProvider[client] = -1;
		
		// Get the conditions from the old provider and remove them
		if(IsClientInGame(oldProvider) && IsPlayerAlive(oldProvider))
		{
			int weapon = GetEntPropEnt(oldProvider, Prop_Send, "m_hActiveWeapon");
			if(weapon > MaxClients)
			{
				char buffer[256];
				if(AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BANNER_BOOST))
				{
					float values[16];
					int numValues = ParseAttributeValues(buffer, values, sizeof(values));
					if(numValues >= 7)
					{
						for(int j = 6; j < numValues; j++)
						{
							int condId = RoundToFloor(values[j]);
							if(condId > 0)
							{
								TF2_RemoveCondition(client, view_as<TFCond>(condId));
							}
						}
					}
				}
			}
		}
	}
}

void ActivateBanner(int client, int weapon)
{
	char buffer[256];
	if(!AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BANNER_BOOST))
		return;
	
	float values[16];
	int numValues = ParseAttributeValues(buffer, values, sizeof(values));
	if(numValues < 7)
		return;
	
	float duration = values[2];
	
	g_bBannerActive[client] = true;
	g_flBannerEndTime[client] = GetGameTime() + duration;
	Tracker_SetValue(client, "Banner", 0.0);
	
	// Apply conditions to the banner owner (self)
	for(int j = 6; j < numValues; j++)
	{
		int condId = RoundToFloor(values[j]);
		if(condId > 0)
		{
			TF2_AddCondition(client, view_as<TFCond>(condId), duration);
		}
	}
}

void DeactivateBanner(int client)
{
	g_bBannerActive[client] = false;
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
