#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_BLAST_JUMP_MISS_BOOST "custom_blast_jumping_miss_boost"

public Plugin myinfo = 
{
	name = "Attribute: Blast Jump Miss Boost",
	author = "TheGabenZone",
	description = "Provides a velocity boost when missing a shot while blast jumping",
	version = PLUGIN_VERSION,
	url = ""
};

// Player data arrays
bool g_bIsAirborne[MAXPLAYERS+1];
float g_flLastBlastJumpTime[MAXPLAYERS+1];
bool g_bWasBlastJumping[MAXPLAYERS+1];
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
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_PreThink, OnPlayerPreThink);
}

public void OnClientDisconnect(int client)
{
	ResetPlayerData(client);
}

void ResetPlayerData(int client)
{
	g_bIsAirborne[client] = false;
	g_flLastBlastJumpTime[client] = 0.0;
	g_bWasBlastJumping[client] = false;
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

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(attacker < 1 || attacker > MaxClients)
		return Plugin_Continue;
	
	// Detect blast jumping for blast_jumping_miss_boost
	if(attacker == victim && (damagetype & DMG_BLAST))
	{	
		// Check ALL weapon slots and wearables for the attribute (not just active weapon)
		bool hasAttribute = false;
		char buffer[256];
		
		// Check all weapon slots
		for(int slot = 0; slot < 5; slot++)
		{
			int checkWeapon = GetPlayerWeaponSlot(attacker, slot);
			if(checkWeapon > MaxClients && AttribHookString(buffer, sizeof(buffer), checkWeapon, ATTR_BLAST_JUMP_MISS_BOOST))
			{
				float values[2];
				if(ParseAttributeValues(buffer, values, 2) >= 2 && values[0] > 0.0)
				{
					hasAttribute = true;
					break;
				}
			}
		}
		
		// Check wearables if not found in weapons
		if(!hasAttribute)
		{
			int wearable = -1;
			while((wearable = FindEntityByClassname(wearable, "tf_wearable")) != -1)
			{
				if(GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity") == attacker)
				{
					if(AttribHookString(buffer, sizeof(buffer), wearable, ATTR_BLAST_JUMP_MISS_BOOST))
					{
						float values[2];
						if(ParseAttributeValues(buffer, values, 2) >= 2 && values[0] > 0.0)
						{
							hasAttribute = true;
							break;
						}
					}
				}
			}
		}
		
		if(hasAttribute)
		{
			// Mark as blast jumping
			g_bWasBlastJumping[attacker] = true;
			g_flLastBlastJumpTime[attacker] = GetGameTime();
		}
	}
	
	return Plugin_Continue;
}

public void OnPlayerPreThink(int client)
{
	if(!IsPlayerAlive(client))
		return;
	
	// Check if player is airborne
	g_bIsAirborne[client] = IsPlayerAirborne(client);
	
	// Get active weapon for other checks
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	
	// Blast jump miss boost - only check active weapon
	if(weapon > MaxClients)
	{
		char buffer[256];
		if(AttribHookString(buffer, sizeof(buffer), weapon, ATTR_BLAST_JUMP_MISS_BOOST))
		{
			float values[2];
			if(ParseAttributeValues(buffer, values, 2) >= 2 && values[0] > 0.0)
			{
				float blastJumpBoostMult = values[1];
				HandleBlastJumpMissBoost(client, weapon, blastJumpBoostMult);
			}
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

void HandleBlastJumpMissBoost(int client, int weapon, float boostMultiplier)
{
	// Only apply if player was recently blast jumping
	if(!g_bWasBlastJumping[client])
		return;
	
	float gameTime = GetGameTime();
	
	// Check if blast jump was recent (within 2.0 seconds)
	if(gameTime - g_flLastBlastJumpTime[client] > 2.0)
	{
		g_bWasBlastJumping[client] = false;
		return;
	}
	
	// Check if player is airborne
	if(!g_bIsAirborne[client])
	{
		g_bWasBlastJumping[client] = false;
		return;
	}
	
	// Check if player fired their weapon (attack button pressed)
	int buttons = GetClientButtons(client);
	bool attackPressed = (buttons & IN_ATTACK) && !(g_iLastButtons[client] & IN_ATTACK);
	
	if(attackPressed)
	{	
		// Get player's eye angles to determine look direction
		float eyeAngles[3];
		GetClientEyeAngles(client, eyeAngles);
		
		// Calculate forward vector from eye angles
		float forwardVec[3];
		GetAngleVectors(eyeAngles, forwardVec, NULL_VECTOR, NULL_VECTOR);
		
		// Get current velocity
		float vel[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
		
		// Calculate boost magnitude (can adjust this value for strength)
		float boostSpeed = 500.0 * boostMultiplier; // Base boost speed
		
		// Apply boost in the direction player is looking
		vel[0] += forwardVec[0] * boostSpeed;
		vel[1] += forwardVec[1] * boostSpeed;
		vel[2] += forwardVec[2] * boostSpeed;
		
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
		
		// Reset blast jump flag after applying boost so it only happens once per blast jump
		g_bWasBlastJumping[client] = false;
	}
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
