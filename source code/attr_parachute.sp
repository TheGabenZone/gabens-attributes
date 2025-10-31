#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_PARACHUTE "custom_parachute_enabled"

// Constants
#define PARACHUTE_MODEL "models/workshop/weapons/c_models/c_paratrooper_pack/c_paratrooper_parachute.mdl"

public Plugin myinfo = 
{
	name = "Parachute",
	author = "TheGabenZone",
	description = "Enables parachute mechanic for weapons",
	version = PLUGIN_VERSION,
	url = ""
};

// Player data arrays
bool g_bIsAirborne[MAXPLAYERS+1];
bool g_bParachuteActive[MAXPLAYERS+1];
float g_flParachuteRedeploy[MAXPLAYERS+1];
bool g_bParachuteUsedThisJump[MAXPLAYERS+1];
int g_iParachuteModel[MAXPLAYERS+1] = {-1, ...};
int g_iLastButtons[MAXPLAYERS+1];

public void OnPluginStart()
{
	// Hook events
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	// Late load support
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnMapStart()
{
	// Precache parachute model
	PrecacheModel(PARACHUTE_MODEL);
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
	RemoveParachuteModel(client);
	
	g_bIsAirborne[client] = false;
	g_bParachuteActive[client] = false;
	g_flParachuteRedeploy[client] = 0.0;
	g_bParachuteUsedThisJump[client] = false;
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

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if(victim > 0)
	{
		ResetPlayerData(victim);
	}
}

public void OnPlayerPreThink(int client)
{
	if(!IsPlayerAlive(client))
		return;
	
	// Check if player is airborne
	g_bIsAirborne[client] = IsPlayerAirborne(client);
	
	// Parachute logic (passive - checks all weapons and wearables)
	char buffer[256];
	bool hasParachute = false;
	
	// Check weapon slots
	for(int slot = 0; slot < 5; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if(weapon > MaxClients && AttribHookString(buffer, sizeof(buffer), weapon, ATTR_PARACHUTE))
		{
			hasParachute = true;
			break;
		}
	}
	
	// Check wearables if not found in weapons
	if(!hasParachute)
	{
		int wearable = -1;
		while((wearable = FindEntityByClassname(wearable, "tf_wearable")) != -1)
		{
			if(GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity") == client)
			{
				if(AttribHookString(buffer, sizeof(buffer), wearable, ATTR_PARACHUTE))
				{
					hasParachute = true;
					break;
				}
			}
		}
	}
	
	if(hasParachute)
	{
		HandleParachute(client, buffer);
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

void HandleParachute(int client, const char[] buffer)
{
	float values[4];
	if(ParseAttributeValues(buffer, values, 4) < 4)
		return;
	
	bool enabled = values[0] > 0.0;
	float horizSpeed = values[1];
	bool redeployEnabled = values[2] > 0.0;
	float redeployDelay = values[3];
	
	if(!enabled)
		return;
	
	int buttons = GetClientButtons(client);
	int lastButtons = g_iLastButtons[client];
	
	// Detect jump button press (button down this frame but not last frame)
	bool jumpPressed = (buttons & IN_JUMP) && !(lastButtons & IN_JUMP);
	
	if(g_bIsAirborne[client])
	{
		// Toggle parachute on jump press while airborne
		if(jumpPressed)
		{
			if(g_bParachuteActive[client])
			{
				// Deactivate parachute
				g_bParachuteActive[client] = false;
				RemoveParachuteModel(client);
			}
			else
			{
				// Try to deploy/redeploy parachute
				float gameTime = GetGameTime();
				bool canDeploy = false;
				
				// Check if we can deploy based on redeploy settings
				if(!g_bParachuteUsedThisJump[client])
				{
					// First activation while airborne - always allowed
					canDeploy = true;
					g_bParachuteUsedThisJump[client] = true;
					g_flParachuteRedeploy[client] = gameTime + redeployDelay;
				}
				else if(redeployEnabled && gameTime >= g_flParachuteRedeploy[client])
				{
					// Mid-air redeployment - only if enabled and cooldown passed
					canDeploy = true;
					g_flParachuteRedeploy[client] = gameTime + redeployDelay;
				}
				
				if(canDeploy)
				{
					g_bParachuteActive[client] = true;
					CreateParachuteModel(client);
					
					// Apply slow falling
					float vel[3];
					GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
					vel[2] = -100.0; // Slow fall speed
					vel[0] *= horizSpeed;
					vel[1] *= horizSpeed;
					TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
				}
			}
		}
		
		if(g_bParachuteActive[client])
		{
			// Maintain slow fall
			float vel[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
			if(vel[2] < -100.0)
			{
				vel[2] = -100.0;
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
			}
		}
	}
	else
	{
		// Landed - reset for next jump
		if(g_bParachuteActive[client] || g_bParachuteUsedThisJump[client])
		{
			g_bParachuteActive[client] = false;
			g_bParachuteUsedThisJump[client] = false;
			RemoveParachuteModel(client);
		}
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

void CreateParachuteModel(int client)
{
	// Remove existing model if any
	RemoveParachuteModel(client);
	
	// Create prop_dynamic for parachute
	int parachute = CreateEntityByName("prop_dynamic_override");
	if(parachute == -1)
		return;
	
	// Set model
	DispatchKeyValue(parachute, "model", PARACHUTE_MODEL);
	
	// Make it non-solid
	DispatchKeyValue(parachute, "solid", "0");
	
	// Spawn the entity
	DispatchSpawn(parachute);
	ActivateEntity(parachute);
	
	// Set owner
	SetEntPropEnt(parachute, Prop_Send, "m_hOwnerEntity", client);
	
	// Parent to player
	float pos[3], ang[3];
	GetClientAbsOrigin(client, pos);
	GetClientAbsAngles(client, ang);
	
	// Calculate forward vector to offset towards player's back
	float fwd[3];
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);
	
	// Offset position
	pos[0] -= fwd[0] * -15.0; // Move backwards (towards player)
	pos[1] -= fwd[1] * -15.0;
	pos[2] += 5.0; // Offset to player's back height
	
	TeleportEntity(parachute, pos, ang, NULL_VECTOR);
	
	// Parent to player's head/spine
	SetVariantString("!activator");
	AcceptEntityInput(parachute, "SetParent", client);
	
	// Try setting animation by sequence number (0 = first sequence)
	SetEntProp(parachute, Prop_Send, "m_nSequence", 0); // deploy should be sequence 0
	
	// Store reference
	g_iParachuteModel[client] = EntIndexToEntRef(parachute);
	
	// Set up timer to switch to idle animation after deploy finishes
	CreateTimer(0.5, Timer_SetParachuteIdle, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SetParachuteIdle(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if(client > 0 && g_iParachuteModel[client] != -1)
	{
		int parachute = EntRefToEntIndex(g_iParachuteModel[client]);
		if(parachute > MaxClients && IsValidEntity(parachute))
		{
			// Set to idle animation (sequence 1)
			SetEntProp(parachute, Prop_Send, "m_nSequence", 1);
		}
	}
	return Plugin_Stop;
}

void RemoveParachuteModel(int client)
{
	if(g_iParachuteModel[client] != -1)
	{
		int parachute = EntRefToEntIndex(g_iParachuteModel[client]);
		if(parachute > MaxClients && IsValidEntity(parachute))
		{
			// Play retract animation (sequence 2)
			SetEntProp(parachute, Prop_Send, "m_nSequence", 2);
			SetEntPropFloat(parachute, Prop_Send, "m_flCycle", 0.0);
			SetEntPropFloat(parachute, Prop_Send, "m_flPlaybackRate", 1.0);
			
			// Try using SetAnimation input as well
			SetVariantString("retract");
			AcceptEntityInput(parachute, "SetAnimation");
			
			// Pack client userid and parachute ref for timer
			DataPack pack;
			CreateDataTimer(0.5, Timer_KillParachute, pack, TIMER_FLAG_NO_MAPCHANGE);
			pack.WriteCell(GetClientUserId(client));
			pack.WriteCell(EntIndexToEntRef(parachute));
		}
		else
		{
			// Entity already invalid, just reset
			g_iParachuteModel[client] = -1;
		}
	}
}

public Action Timer_KillParachute(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int entRef = pack.ReadCell();
	
	int client = GetClientOfUserId(userid);
	int parachute = EntRefToEntIndex(entRef);
	
	if(parachute > MaxClients && IsValidEntity(parachute))
	{
		AcceptEntityInput(parachute, "Kill");
	}
	
	// Reset the client's parachute model reference
	if(client > 0 && client <= MaxClients)
	{
		g_iParachuteModel[client] = -1;
	}
	
	return Plugin_Stop;
}
