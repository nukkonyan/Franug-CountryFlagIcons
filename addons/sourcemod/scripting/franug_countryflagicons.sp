/*  SM Franug Country Flag Icons
 *
 *  Copyright (C) 2019 Francisco 'Franc1sco' García
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sdktools>
#include <sdkhooks>
#include <geoip>
#undef REQUIRE_PLUGIN
#include <ScoreboardCustomLevels>
#include <clientprefs>

int m_iOffset = -1;
int m_iLevel[MAXPLAYERS+1];

Cookie hShowFlagCookie;

char serverIp[16];

StringMap trie;

bool g_bCustomLevels;
bool g_hShowflag[MAXPLAYERS + 1] = {true, ...};

ConVar net_public_adr = null;

#define DATA "1.4.5"

public Plugin myinfo =
{
	name = "Franug Country Flag Icons",
	author = "Franc1sco franug, teamkiller324",
	description = "Overrides private rank with a flag corresponding your country you connect from.",
	version = DATA,
	url = "http://steamcommunity.com/id/franug"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("SCL_GetLevel");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("franug_countryflagicons.phrases");
	
	net_public_adr = FindConVar("net_public_adr");
	g_bCustomLevels = LibraryExists("ScoreboardCustomLevels");	
	m_iOffset = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");
	
	RegConsoleCmd("sm_flag", Cmd_Showflag, "[Franug: Scoreboard Flag] This allows players to hide their flag");
	RegConsoleCmd("sm_showflag", Cmd_Showflag, "[Franug: Scoreboard Flag] This allows players to hide their flag");
	hShowFlagCookie = new Cookie("Flags-Icons_No_Flags_Cookie", "Show or hide the flag.", CookieAccess_Private);
		
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/franug_countryflags.cfg");
	
	trie = new StringMap();
	KeyValues kv = new KeyValues("CountryFlags");
	kv.ImportFromFile(path);
	
	switch(kv.JumpToKey("Flags"))
	{
		case false:
		{
			SetFailState("[Franug: Scoreboard Flag] Failed to read flags from config file! (Is it installed in /configs/ directory?)");
		}
		
		case true:
		{
			if(kv.GotoFirstSubKey())
			{
				do
				{
					char flag[4];
					kv.GetSectionName(flag, sizeof(flag));
					int index = kv.GetNum("index");
					
					if(strlen(flag) < 1)
					{
						LogError("[Franug: Scoreboard Flag] Error parsing KeyValues : Country '%s' are invalid (index '%i')", flag, index);
						continue;
					}
					else if(index <= 0)
					{
						LogError("[Franug: Scoreboard Flag] Error parsing KeyValues : Country '%s' have an invalid index '%i'", flag, index);
						continue;
					}
					
					char buffer[64];
					Format(buffer, sizeof(buffer), "materials/panorama/images/icons/xp/level%i.png", index);
					AddFileToDownloadsTable(buffer);
					
					trie.SetValue(flag, index);
				}
				while(kv.GotoNextKey());
				
				kv.GoBack();
			}
			
			kv.GoBack();
		}
	}
	
	if(kv.JumpToKey("CustomFlags"))
	{
		if(kv.GotoFirstSubKey())
		{
			do
			{
				char auth64[24], flag[4];
				kv.GetSectionName(auth64, sizeof(auth64));
				kv.GetString("flag", flag, sizeof(flag));
				
				if(strlen(auth64) < 1)
				{
					LogError("[Franug: Scoreboard Flag] Error parsing KeyValues : SteamID64 '%s' is invalid (index '%i')", auth64, flag);
					continue;
				}
				else if(strlen(flag) < 1)
				{
					LogError("[Franug: Scoreboard Flag] Error parsing KeyValues : SteamID64 '%s' have an invalid flag '%s'", auth64, flag);
					continue;
				}
				
				trie.SetString(auth64, flag);
			}
			while(kv.GotoNextKey());
		}
	}
	
	delete kv;
}

public void OnMapStart()
{
	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnThinkPost);
}

public void OnConfigsExecuted()
{
	net_public_adr.GetString(serverIp, sizeof(serverIp));
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "ScoreboardCustomLevels"))
	{
		g_bCustomLevels = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "ScoreboardCustomLevels"))
	{
		g_bCustomLevels = false;
	}
}

public void OnClientPutInServer(int client)
{
	m_iLevel[client] = -1;

	if(!IsValidClient(client))
	{
		return;
	}
	
	char auth64[24];
	if(GetClientAuthId(client, AuthId_SteamID64, auth64, sizeof(auth64)))
	{
		if(trie.ContainsKey(auth64))
		{
			char flag[4];
			if(trie.GetString(auth64, flag, sizeof(flag)))
			{
				if(trie.ContainsKey(flag))
				{
					trie.GetValue(flag, m_iLevel[client]);
					return;
				}
			}
		}
	}

	char ip[16];
	char code2[3];
	
	if(!GetClientIP(client, ip, sizeof(ip)) || !IsLocalAddress(ip) && !GeoipCode2(ip, code2) || !g_hShowflag[client])
	{
		if(trie.ContainsKey("UNKNOWN"))
		{
			trie.GetValue("UNKNOWN", m_iLevel[client]);
		}
		return;
	}

	if(IsLocalAddress(ip))
	{
		GeoipCode2(serverIp, code2);
	}

	switch(trie.ContainsKey(code2))
	{
		case false:
		{
			if(trie.ContainsKey("UNKNOWN"))
			{
				trie.GetValue("UNKNOWN", m_iLevel[client]);
			}
			LogError("[Franug: Scoreboard Flag] No flag was found with '%s' for ' %N ', using fallback.. (Needs to be added)", code2, client);
		}
		case true: trie.GetValue(code2, m_iLevel[client]);
	}
}

public void OnClientDisconnect(int client)
{
	m_iLevel[client] = -1;
}

Action Cmd_Showflag(int client, int args)
{
	if(AreClientCookiesCached(client))
	{
		char sCookieValue[12];
		hShowFlagCookie.Get(client, sCookieValue, sizeof(sCookieValue));
		int cookieValue = StringToInt(sCookieValue);
		switch(cookieValue == 1)
		{
			case false:
			{
				cookieValue = 1;
				g_hShowflag[client] = false;
				IntToString(cookieValue, sCookieValue, sizeof(sCookieValue));
				hShowFlagCookie.Set(client, sCookieValue);
				OnClientPutInServer(client);
				ReplyToCommand(client, "[SM] %T", "#ScoreBoardFlags_FlagInactive", client);
			}
			case true:
			{
				cookieValue = 0;
				g_hShowflag[client] = true;
				IntToString(cookieValue, sCookieValue, sizeof(sCookieValue));
				hShowFlagCookie.Set(client, sCookieValue);
				OnClientPutInServer(client);
				ReplyToCommand(client, "[SM] %T", "#ScoreBoardFlags_FlagActive", client);
			}
		}
	}
	
	return Plugin_Handled;
}

public void OnClientCookiesCached(int client)
{
	char sCookieValue[12];
	hShowFlagCookie.Get(client, sCookieValue, sizeof(sCookieValue));
	if(StrEqual(sCookieValue, ""))
	{
		sCookieValue = "1"
		hShowFlagCookie.Set(client, sCookieValue);
	}
	if(StringToInt(sCookieValue) == 0)
	{
		g_hShowflag[client] = true;
		OnClientPutInServer(client);
	}
}

public void OnThinkPost(int m_iEntity)
{
	int m_iLevelTemp[MAXPLAYERS+1];
	GetEntDataArray(m_iEntity, m_iOffset, m_iLevelTemp, sizeof(m_iLevelTemp));
	
	for(int i = 1; i <= MAXPLAYERS; i++)
	{
		if(m_iLevel[i] > 0)
		{
			if(m_iLevel[i] != m_iLevelTemp[i])
			{
				if(g_bCustomLevels && SCL_GetLevel(i) > 0)
				{
					continue; // dont overwritte other custom level
				}
				SetEntData(m_iEntity, m_iOffset + (i * 4), m_iLevel[i]);
			}
		}
	}
}

stock bool IsLocalAddress(const char ip[16])
{
	// 192.168.0.0 - 192.168.255.255 (65,536 IP addresses)
	// 10.0.0.0 - 10.255.255.255 (16,777,216 IP addresses)
	if(StrContains(ip, "192.168", false) > -1 || StrContains(ip, "10.", false) > -1)
	{
		return true;
	}

	// 172.16.0.0 - 172.31.255.255 (1,048,576 IP addresses)
	char octets[4][3];
	if(ExplodeString(ip, ".", octets, 4, 3) == 4)
	{
		if(StrContains(octets[0], "172", false) > -1)
		{
			int octet = StringToInt(octets[1]);
			
			return (!(octet < 16) || !(octet > 31));
		}
	}

	return false;
}

bool IsValidClient(int client)
{
	if(client < 1 || client > MAXPLAYERS)
	{
		return false;
	}
	
	if(!IsClientConnected(client))
	{
		return false;
	}
	
	if(IsFakeClient(client))
	{
		return false;
	}
	
	if(IsClientSourceTV(client))
	{
		return false;
	}
	
	if(IsClientReplay(client))
	{
		return false;
	}
	
	return true;
}