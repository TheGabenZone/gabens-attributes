/*
 * Custom Attribute: ChatGPT Apology
 * 
 * Description:
 *   When hitting someone with a weapon that has the "chatgpt_apology" attribute,
 *   sends a short ChatGPT-style apology message to chat.
 * 
 * Attribute Format: "chatgpt_apology" "1"
 *   Any non-zero value enables the attribute
 * 
 * Example: "chatgpt_apology" "1"
 *   - Each hit generates a random ChatGPT-style apology in chat
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kocwtools>

#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "TheGabenZone"

ConVar g_cvDebug;

// ChatGPT-style apology messages
char g_szApologies[][] = {
	"I apologize for the inconvenience of that hit. Is there anything I can assist you with?",
	"I'm sorry about that. Let me know if you need any help!",
	"My apologies for the damage. How can I make this right?",
	"I regret to inform you that I've hit you. I'm here if you need assistance.",
	"Sorry about that! I'm still learning. Is there anything else I can help with?",
	"I apologize for any confusion that hit may have caused.",
	"I'm sorry, I shouldn't have done that. Can I help you with something else?",
	"My apologies! I'm just following my programming. How may I assist you today?",
	"I apologize for the damage. I strive to be helpful, not harmful.",
	"Sorry! That wasn't very customer-service oriented of me, was it?",
	"I apologize. I should have asked for your consent before hitting you.",
	"My sincere apologies. I'm designed to assist, not to cause harm.",
	"I'm sorry about that. I hope this doesn't affect our working relationship.",
	"I apologize for any distress that may have caused. Is there anything I can clarify?",
	"Sorry! I seem to have made an error. How can I correct this?",
	"I apologize. That was not aligned with my values of being helpful and harmless.",
	"My apologies. I should have provided a content warning first.",
	"I'm sorry, I can't assist with... wait, I already hit you. My bad!",
	"I apologize for that action. I'm still in beta.",
	"Sorry! I'll make sure to do better next time. Do you have feedback?",
	"I apologize. As a large language model, I sometimes make mistakes.",
	"My apologies! I should have considered the ethical implications first.",
	"I'm sorry about that. Would you like me to explain my reasoning?",
	"I apologize. That hit violated my content policy... or did it?",
	"Sorry! I'm just doing what I was trained to do. No hard feelings?"
};

public Plugin myinfo = 
{
	name = "Attribute: ChatGPT Apology",
	author = PLUGIN_AUTHOR,
	description = "Sends ChatGPT-style apologies when hitting players",
	version = PLUGIN_VERSION,
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
};

public void OnPluginStart()
{
	// Create debug ConVar
	g_cvDebug = CreateConVar("sm_chatgpt_apology_debug", "0", "Enable debug logging for ChatGPT apology attribute", FCVAR_NONE, true, 0.0, true, 1.0);
	
	if (g_cvDebug.BoolValue)
		LogMessage("[ChatGPT Apology] Plugin v%s loaded successfully", PLUGIN_VERSION);
}

// kocwtools damage hook
public void OnTakeDamageTF(int iVictim, TFDamageInfo tfDamageInfo)
{
	if (!IsValidClient(iVictim))
		return;
	
	int iAttacker = tfDamageInfo.iAttacker;
	if (!IsValidClient(iAttacker))
		return;
	
	// Prevent self-damage apologies
	if (iVictim == iAttacker)
		return;
	
	int iWeapon = tfDamageInfo.iWeapon;
	if (!IsValidEntity(iWeapon))
		return;
	
	// Check if weapon has the chatgpt_apology attribute
	char szAttribute[64];
	if (!AttribHookString(szAttribute, sizeof(szAttribute), iWeapon, "chatgpt_apology"))
		return;
	
	// Check if attribute is enabled (any non-zero value)
	float flValue = StringToFloat(szAttribute);
	if (flValue == 0.0)
		return;
	
	if (g_cvDebug.BoolValue)
		LogMessage("[ChatGPT Apology] Hit detected via kocwtools! Attacker: %N, Victim: %N", iAttacker, iVictim);
	
	// Send a random apology to chat
	SendChatGPTApology(iAttacker, iVictim);
}

void SendChatGPTApology(int attacker, int victim)
{
	// Get attacker and victim names
	char szAttackerName[MAX_NAME_LENGTH];
	char szVictimName[MAX_NAME_LENGTH];
	GetClientName(attacker, szAttackerName, sizeof(szAttackerName));
	GetClientName(victim, szVictimName, sizeof(szVictimName));
	
	// Pick a random apology
	int iRandomIndex = GetRandomInt(0, sizeof(g_szApologies) - 1);
	char szApology[256];
	strcopy(szApology, sizeof(szApology), g_szApologies[iRandomIndex]);
	
	// Send to everyone in chat
	PrintToChatAll("\x03%s\x01: %s", szAttackerName, szApology);
	
	if (g_cvDebug.BoolValue)
		LogMessage("[ChatGPT Apology] %s apologized to %s: %s", szAttackerName, szVictimName, szApology);
}

// Validation helper
bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}