#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_JUMP_WHILE_CHARGING "custom_wearer_can_jump_while_charging"

public Plugin myinfo = 
{
	name = "Attribute: Jump While Charging",
	author = "TheGabenZone",
	description = "Allows Demoman to jump while shield charging",
	version = PLUGIN_VERSION,
	url = ""
};

// Player data arrays
bool g_bIsAirborne[MAXPLAYERS+1];
bool g_bUsedChargeJump[MAXPLAYERS+1];
int g_iLastButtons[MAXPLAYERS+1];

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
}

public void OnClientDisconnect(int client)
{
	ResetPlayerData(client);
}

void ResetPlayerData(int client)
{
	g_bIsAirborne[client] = false;
	g_bUsedChargeJump[client] = false;
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

public void OnPlayerPreThink(int client)
{
	if(!IsPlayerAlive(client))
		return;
	
	// Check if player is airborne
	g_bIsAirborne[client] = IsPlayerAirborne(client);
	
	// Jump while charging (for Demoman shields - checks weapons and wearables)
	bool hasJumpWhileCharging = false;
	char buffer[256];
	
	// Check weapon slots
	for(int slot = 0; slot < 5; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if(weapon > MaxClients && AttribHookString(buffer, sizeof(buffer), weapon, ATTR_JUMP_WHILE_CHARGING))
		{
			hasJumpWhileCharging = true;
			break;
		}
	}
	
	// Check wearables (shields) if not found in weapons
	if(!hasJumpWhileCharging)
	{
		int wearable = -1;
		while((wearable = FindEntityByClassname(wearable, "tf_wearable")) != -1)
		{
			if(GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity") == client)
			{
				if(AttribHookString(buffer, sizeof(buffer), wearable, ATTR_JUMP_WHILE_CHARGING))
				{
					hasJumpWhileCharging = true;
					break;
				}
			}
		}
	}
	
	if(hasJumpWhileCharging)
	{
		// Check if player is charging (Condition ID 17)
		bool isCharging = TF2_IsPlayerInCondition(client, view_as<TFCond>(17));
		if(isCharging) // TFCond_Charging
		{
			// Reset jump flag when player lands
			if(!g_bIsAirborne[client])
			{
				g_bUsedChargeJump[client] = false;
			}
			
			int buttons = GetClientButtons(client);
			bool jumpPressed = (buttons & IN_JUMP) && !(g_iLastButtons[client] & IN_JUMP);
			
			// Apply vertical momentum boost on jump press (only if not already used)
			if(jumpPressed && !g_bUsedChargeJump[client])
			{
				float vel[3];
				GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
				
				// Set vertical velocity to a fixed upward boost (overriding current Z velocity)
				vel[2] = 300.0; // Upward boost (changed from += to = for consistent jump)
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
				
				// Also remove FL_ONGROUND flag temporarily to ensure jump happens
				int flags = GetEntityFlags(client);
				SetEntityFlags(client, flags & ~FL_ONGROUND);
				
				// Mark that we've used the charge jump
				g_bUsedChargeJump[client] = true;
			}
		}
		else
		{
			// Reset jump flag when not charging
			g_bUsedChargeJump[client] = false;
		}
	}
	
	// Track buttons
	g_iLastButtons[client] = GetClientButtons(client);
}

bool IsPlayerAirborne(int client)
{
	if(!IsPlayerAlive(client))
		return false;
	
	int flags = GetEntityFlags(client);
	return !(flags & FL_ONGROUND);
}
