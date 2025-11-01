#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>
#include <tf2c>

#define PLUGIN_VERSION "1.0.0"

// Attribute Name
#define ATTR_INCINERATOR_GAS "custom_incinerator_gas"

// Gas cloud constants
#define MAX_GAS_CLOUDS 32
#define GAS_RADIUS 200.0
#define GAS_CHECK_INTERVAL 0.1
#define NUM_PARTICLES_PER_CLOUD 16 // Number of particles to spread across the radius

public Plugin myinfo = 
{
	name = "Attribute: Incinerator Gas",
	author = "TheGabenZone",
	description = "Throwables create gas clouds that can be ignited to burn enemies",
	version = PLUGIN_VERSION,
	url = ""
};

enum struct GasCloud
{
	int triggerEntity;
	int particleEntities[NUM_PARTICLES_PER_CLOUD];
	int fireParticles[NUM_PARTICLES_PER_CLOUD];
	float position[3];
	float endTime;
	float igniteDuration;
	float afterburnDuration;
	int ownerTeam;
	int ownerClient;
	bool isIgnited;
	float radius;
	float tickRate;
	float damage;
	float nextDamageTime;
	
	void Reset()
	{
		this.triggerEntity = -1;
		for(int i = 0; i < NUM_PARTICLES_PER_CLOUD; i++)
		{
			this.particleEntities[i] = -1;
			this.fireParticles[i] = -1;
		}
		this.position[0] = 0.0;
		this.position[1] = 0.0;
		this.position[2] = 0.0;
		this.endTime = 0.0;
		this.igniteDuration = 0.0;
		this.afterburnDuration = 0.0;
		this.ownerTeam = 0;
		this.ownerClient = 0;
		this.isIgnited = false;
		this.radius = 0.0;
		this.tickRate = 0.0;
		this.damage = 0.0;
		this.nextDamageTime = 0.0;
	}
}

GasCloud g_GasClouds[MAX_GAS_CLOUDS];
int g_iProjectileOwner[2048];
int g_iProjectileWeapon[2048];
float g_flProjectileIgniteDuration[2048];
float g_flProjectileAfterburn[2048];
float g_flProjectileRadius[2048];
float g_flProjectileTickRate[2048];
float g_flProjectileDamage[2048];

public void OnPluginStart()
{
	// Hook events
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	// Initialize gas clouds
	for(int i = 0; i < MAX_GAS_CLOUDS; i++)
	{
		g_GasClouds[i].Reset();
	}
	
	// Start timer to check gas clouds
	CreateTimer(GAS_CHECK_INTERVAL, Timer_CheckGasClouds, _, TIMER_REPEAT);
	
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
	// Precache particles for all teams
	PrecacheParticleSystem("gas_loop_red");
	PrecacheParticleSystem("gas_loop_blue");
	PrecacheParticleSystem("gas_loop_green");
	PrecacheParticleSystem("gas_loop_yellow");
	PrecacheParticleSystem("gas_can_impact_red");
	PrecacheParticleSystem("gas_can_impact_blue");
	PrecacheParticleSystem("gas_can_impact_green");
	PrecacheParticleSystem("gas_can_impact_yellow");
	PrecacheParticleSystem("burningplayer_red");
	PrecacheParticleSystem("burningplayer_blue");
	PrecacheParticleSystem("burningplayer_green");
	PrecacheParticleSystem("burningplayer_yellow");
	
	// Precache sounds
	PrecacheSound("items/gas_can_explode.wav");
	
	// Clear all gas clouds on map start
	for(int i = 0; i < MAX_GAS_CLOUDS; i++)
	{
		RemoveGasCloud(i);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Hook throwable projectiles
	if(StrEqual(classname, "tf_projectile_brick") || 
	   StrEqual(classname, "tf_projectile_pipe"))
	{
		// Store entity reference for timer
		int entityRef = EntIndexToEntRef(entity);
		
		// Use a timer instead of SpawnPost hook
		DataPack pack = new DataPack();
		pack.WriteCell(entityRef);
		pack.Reset();
		
		CreateTimer(0.1, Timer_CheckProjectile, pack);
	}
}

public Action Timer_CheckProjectile(Handle timer, DataPack pack)
{
	pack.Reset();
	int entityRef = pack.ReadCell();
	
	CheckProjectile(entityRef);
	
	delete pack;
	return Plugin_Stop;
}

void CheckProjectile(int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	
	if(entity == -1)
		return;
	
	// Get the owner of the projectile - try both properties
	int owner = -1;
	
	// Try m_hThrower first (for jars/throwables)
	if(HasEntProp(entity, Prop_Send, "m_hThrower"))
	{
		owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	}
	
	if(owner < 1 || owner > MaxClients)
	{
		// Try alternative property
		if(HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		{
			owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		}
	}
	
	if(owner < 1 || owner > MaxClients)
		return;
	
	// Get the weapon that fired this projectile
	int weapon = GetEntPropEnt(owner, Prop_Send, "m_hActiveWeapon");
	
	if(weapon <= MaxClients)
		return;
	
	// Check if weapon has the incinerator gas attribute
	char buffer[256];
	if(!AttribHookString(buffer, sizeof(buffer), weapon, ATTR_INCINERATOR_GAS))
		return;
	
	float values[6];
	int numValues = ParseAttributeValues(buffer, values, 6);
	if(numValues < 3 || values[0] <= 0.0)
		return;
	
	// Set default values for optional parameters
	float radius = (numValues >= 4 && values[3] > 0.0) ? values[3] : GAS_RADIUS;
	float tickRate = (numValues >= 5 && values[4] > 0.0) ? values[4] : 0.1;
	float damage = (numValues >= 6 && values[5] > 0.0) ? values[5] : 5.0;
	
	// Store owner and weapon info for when projectile explodes
	g_iProjectileOwner[entity] = GetClientUserId(owner);
	g_iProjectileWeapon[entity] = EntIndexToEntRef(weapon);
	g_flProjectileIgniteDuration[entity] = values[1];
	g_flProjectileAfterburn[entity] = values[2];
	g_flProjectileRadius[entity] = radius;
	g_flProjectileTickRate[entity] = tickRate;
	g_flProjectileDamage[entity] = damage;
	
	// Start tracking this projectile with a repeating timer
	DataPack trackPack = new DataPack();
	trackPack.WriteCell(EntIndexToEntRef(entity));
	trackPack.WriteCell(GetClientUserId(owner));
	trackPack.Reset();
	
	CreateTimer(0.1, Timer_TrackProjectile, trackPack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_TrackProjectile(Handle timer, DataPack pack)
{
	pack.Reset();
	int entityRef = pack.ReadCell();
	int ownerUserId = pack.ReadCell();
	
	int entity = EntRefToEntIndex(entityRef);
	
	// If entity is invalid, stop tracking
	if(entity == -1)
	{
		delete pack;
		return Plugin_Stop;
	}
	
	// Get stored attribute values from global arrays
	float igniteDuration = g_flProjectileIgniteDuration[entity];
	float afterburnDuration = g_flProjectileAfterburn[entity];
	float radius = g_flProjectileRadius[entity];
	float tickRate = g_flProjectileTickRate[entity];
	float damage = g_flProjectileDamage[entity];
	
	// Check velocity
	float velocity[3];
	GetEntPropVector(entity, Prop_Data, "m_vecVelocity", velocity);
	float speed = SquareRoot(velocity[0]*velocity[0] + velocity[1]*velocity[1] + velocity[2]*velocity[2]);
	
	// Check if projectile has stopped moving (landed)
	if(speed < 5.0)
	{
		// Additional check: make sure it's not just floating in air
		// Do a trace downward to check if there's a surface below
		float position[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", position);
		
		float endPos[3];
		endPos[0] = position[0];
		endPos[1] = position[1];
		endPos[2] = position[2] - 50.0; // Trace 50 units down
		
		Handle trace = TR_TraceRayFilterEx(position, endPos, MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_World);
		bool hitSurface = TR_DidHit(trace);
		delete trace;
		
		// Only create gas cloud if there's a surface nearby
		if(hitSurface)
		{
			int owner = GetClientOfUserId(ownerUserId);
			if(owner > 0 && owner <= MaxClients && IsClientInGame(owner))
			{
				// Create splash particle
				int team = GetClientTeam(owner);
				char splashParticle[64];
				GetTeamSplashParticle(team, splashParticle, sizeof(splashParticle));
				CreateParticle(splashParticle, position, NULL_VECTOR, 2.0);
				
				CreateGasCloud(position, owner, igniteDuration, afterburnDuration, radius, tickRate, damage);
				
				// Remove the projectile
				AcceptEntityInput(entity, "Kill");
				
				// Clean up stored data
				g_iProjectileOwner[entity] = 0;
				g_iProjectileWeapon[entity] = 0;
				g_flProjectileIgniteDuration[entity] = 0.0;
				g_flProjectileAfterburn[entity] = 0.0;
				g_flProjectileRadius[entity] = 0.0;
				g_flProjectileTickRate[entity] = 0.0;
				g_flProjectileDamage[entity] = 0.0;
			}
			
			delete pack;
			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

bool TraceFilter_World(int entity, int contentsMask)
{
	// Only hit world geometry, not players or entities
	return entity == 0;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0)
	{
		// Nothing specific to reset on spawn for this attribute
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	// Check if damage is fire-based
	if(!(damagetype & DMG_BURN) && !(damagetype & DMG_IGNITE))
		return Plugin_Continue;
	
	// Check all gas clouds to see if any should be ignited
	for(int i = 0; i < MAX_GAS_CLOUDS; i++)
	{
		if(g_GasClouds[i].triggerEntity == -1 || g_GasClouds[i].isIgnited)
			continue;
		
		// Check if damage position is near this gas cloud
		float distance = GetVectorDistance(damagePosition, g_GasClouds[i].position);
		if(distance <= g_GasClouds[i].radius * 1.5) // Slightly larger radius for ignition detection
		{
			IgniteGasCloud(i);
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_CheckGasClouds(Handle timer)
{
	float currentTime = GetGameTime();
	
	for(int i = 0; i < MAX_GAS_CLOUDS; i++)
	{
		if(g_GasClouds[i].triggerEntity == -1)
			continue;
		
		// Check if gas cloud has expired
		if(currentTime > g_GasClouds[i].endTime)
		{
			RemoveGasCloud(i);
			continue;
		}
		
		// If ignited, check for players in the area and apply damage
		if(g_GasClouds[i].isIgnited)
		{
			DamagePlayersInGasCloud(i);
		}
	}
	
	return Plugin_Continue;
}

void CreateGasCloud(float position[3], int owner, float igniteDuration, float afterburnDuration, float radius, float tickRate, float damage)
{
	// Find a free slot
	int slot = -1;
	for(int i = 0; i < MAX_GAS_CLOUDS; i++)
	{
		if(g_GasClouds[i].triggerEntity == -1)
		{
			slot = i;
			break;
		}
	}
	
	if(slot == -1)
	{
		// No free slots, remove oldest cloud
		RemoveGasCloud(0);
		slot = 0;
	}
	
	// Get team-specific particle name
	int team = GetClientTeam(owner);
	char gasParticle[64];
	GetTeamGasParticle(team, gasParticle, sizeof(gasParticle));
	
	// Create multiple particles spread across the radius
	for(int i = 0; i < NUM_PARTICLES_PER_CLOUD; i++)
	{
		float particlePos[3];
		GetRandomPositionInRadius(position, radius * 0.8, particlePos); // 80% of radius for better coverage
		
		int particle = CreateParticle(gasParticle, particlePos, NULL_VECTOR, igniteDuration);
		g_GasClouds[slot].particleEntities[i] = particle;
	}
	
	// Create trigger entity for collision detection
	int trigger = CreateEntityByName("trigger_multiple");
	if(trigger > MaxClients)
	{
		DispatchKeyValue(trigger, "spawnflags", "1"); // Clients only
		DispatchKeyValue(trigger, "wait", "0");
		DispatchSpawn(trigger);
		
		// Set trigger size and position
		float mins[3];
		float maxs[3];
		mins[0] = -radius;
		mins[1] = -radius;
		mins[2] = -radius;
		maxs[0] = radius;
		maxs[1] = radius;
		maxs[2] = radius;
		SetSize(trigger, mins, maxs);
		TeleportEntity(trigger, position, NULL_VECTOR, NULL_VECTOR);
		
		SetSolid(trigger, SOLID_BBOX);
		SetSolidFlags(trigger, FSOLID_NOT_SOLID | FSOLID_TRIGGER);
	}
	
	// Store gas cloud data
	g_GasClouds[slot].triggerEntity = trigger;
	g_GasClouds[slot].position = position;
	g_GasClouds[slot].endTime = GetGameTime() + igniteDuration;
	g_GasClouds[slot].igniteDuration = igniteDuration;
	g_GasClouds[slot].afterburnDuration = afterburnDuration;
	g_GasClouds[slot].ownerTeam = GetClientTeam(owner);
	g_GasClouds[slot].ownerClient = GetClientUserId(owner);
	g_GasClouds[slot].isIgnited = false;
	g_GasClouds[slot].radius = radius;
	g_GasClouds[slot].tickRate = tickRate;
	g_GasClouds[slot].damage = damage;
	g_GasClouds[slot].nextDamageTime = 0.0;
}

void IgniteGasCloud(int index)
{
	if(g_GasClouds[index].isIgnited)
		return;
	
	g_GasClouds[index].isIgnited = true;
	
	// Play explosion sound at the gas cloud location
	EmitSoundToAll("items/gas_can_explode.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, g_GasClouds[index].position);
	
	// Get team-specific fire particle name
	char fireParticle[64];
	GetTeamFireParticle(g_GasClouds[index].ownerTeam, fireParticle, sizeof(fireParticle));
	
	// Remove gas particles, create fire particles
	for(int i = 0; i < NUM_PARTICLES_PER_CLOUD; i++)
	{
		if(g_GasClouds[index].particleEntities[i] > MaxClients && IsValidEntity(g_GasClouds[index].particleEntities[i]))
		{
			float particlePos[3];
			GetEntPropVector(g_GasClouds[index].particleEntities[i], Prop_Data, "m_vecAbsOrigin", particlePos);
			RemoveEntity(g_GasClouds[index].particleEntities[i]);
			g_GasClouds[index].particleEntities[i] = -1;
			
			// Create fire particle at same location
			float remainingTime = g_GasClouds[index].endTime - GetGameTime();
			if(remainingTime > 0.0)
			{
				int newFireParticle = CreateParticle(fireParticle, particlePos, NULL_VECTOR, remainingTime);
				g_GasClouds[index].fireParticles[i] = newFireParticle;
			}
		}
	}
	
	// Immediately damage players in the area
	DamagePlayersInGasCloud(index);
}

void DamagePlayersInGasCloud(int index)
{
	// Check if enough time has passed for next damage tick
	float currentTime = GetGameTime();
	if(currentTime < g_GasClouds[index].nextDamageTime)
		return;
	
	// Set next damage time
	g_GasClouds[index].nextDamageTime = currentTime + g_GasClouds[index].tickRate;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		
		// Don't damage teammates
		if(GetClientTeam(i) == g_GasClouds[index].ownerTeam)
			continue;
		
		// Check if player is in the gas cloud
		float playerPos[3];
		GetClientAbsOrigin(i, playerPos);
		
		float distance = GetVectorDistance(playerPos, g_GasClouds[index].position);
		if(distance <= g_GasClouds[index].radius)
		{
			// Get the owner for damage attribution
			int owner = GetClientOfUserId(g_GasClouds[index].ownerClient);
			if(owner > 0 && owner <= MaxClients && IsClientInGame(owner))
			{
				// Apply burn damage using configured damage value
				SDKHooks_TakeDamage(i, owner, owner, g_GasClouds[index].damage, DMG_BURN);
				
				// Apply afterburn by igniting player
				TF2_IgnitePlayer(i, owner);
				
				// Set the burn duration manually
				if(HasEntProp(i, Prop_Send, "m_flFlameRemoveTime"))
				{
					SetEntPropFloat(i, Prop_Send, "m_flFlameRemoveTime", GetGameTime() + g_GasClouds[index].afterburnDuration);
				}
			}
		}
	}
}

void RemoveGasCloud(int index)
{
	if(g_GasClouds[index].triggerEntity == -1)
		return; // Already removed
	
	if(g_GasClouds[index].triggerEntity > MaxClients && IsValidEntity(g_GasClouds[index].triggerEntity))
	{
		RemoveEntity(g_GasClouds[index].triggerEntity);
	}
	
	// Remove all particle entities
	for(int i = 0; i < NUM_PARTICLES_PER_CLOUD; i++)
	{
		if(g_GasClouds[index].particleEntities[i] > MaxClients && IsValidEntity(g_GasClouds[index].particleEntities[i]))
		{
			RemoveEntity(g_GasClouds[index].particleEntities[i]);
		}
		
		if(g_GasClouds[index].fireParticles[i] > MaxClients && IsValidEntity(g_GasClouds[index].fireParticles[i]))
		{
			RemoveEntity(g_GasClouds[index].fireParticles[i]);
		}
	}
	
	g_GasClouds[index].Reset();
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

void GetTeamGasParticle(int team, char[] buffer, int maxlen)
{
	switch(team)
	{
		case 2: strcopy(buffer, maxlen, "gas_loop_red");      // Red
		case 3: strcopy(buffer, maxlen, "gas_loop_blue");     // Blue
		case 4: strcopy(buffer, maxlen, "gas_loop_green");    // Green
		case 5: strcopy(buffer, maxlen, "gas_loop_yellow");   // Yellow
		default: strcopy(buffer, maxlen, "gas_loop_red");     // Fallback
	}
}

void GetTeamFireParticle(int team, char[] buffer, int maxlen)
{
	switch(team)
	{
		case 2: strcopy(buffer, maxlen, "burningplayer_red");      // Red
		case 3: strcopy(buffer, maxlen, "burningplayer_blue");     // Blue
		case 4: strcopy(buffer, maxlen, "burningplayer_green");    // Green
		case 5: strcopy(buffer, maxlen, "burningplayer_yellow");   // Yellow
		default: strcopy(buffer, maxlen, "burningplayer_red");     // Fallback
	}
}

void GetTeamSplashParticle(int team, char[] buffer, int maxlen)
{
	switch(team)
	{
		case 2: strcopy(buffer, maxlen, "gas_can_impact_red");      // Red
		case 3: strcopy(buffer, maxlen, "gas_can_impact_blue");     // Blue
		case 4: strcopy(buffer, maxlen, "gas_can_impact_green");    // Green
		case 5: strcopy(buffer, maxlen, "gas_can_impact_yellow");   // Yellow
		default: strcopy(buffer, maxlen, "gas_can_impact_red");     // Fallback
	}
}

void GetRandomPositionInRadius(const float center[3], float radius, float output[3])
{
	// Generate random position within a circle
	float angle = GetRandomFloat(0.0, 2.0 * 3.14159265359);
	float distance = GetRandomFloat(0.0, radius);
	
	output[0] = center[0] + (distance * Cosine(angle));
	output[1] = center[1] + (distance * Sine(angle));
	output[2] = center[2];
}
