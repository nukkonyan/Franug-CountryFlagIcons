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

// Team Fortress 2 support can be added, if somehow there's a way to replace the casual rank icon with flag.

#include <sdktools>
#include <sdkhooks>
#include <geoip>
#undef REQUIRE_PLUGIN
#include <ScoreboardCustomLevels>
#include <clientprefs>

// rank offset to replace icon with a country flag.
int m_iOffset = -1;

// global client flag index list.
int m_iLevel[MAXPLAYERS+1];

// grab the server ip.
char serverIp[16];

// handles
Cookie hShowFlagCookie;
StringMap g_tFlags; // country flag tree.
StringMap g_tCustomFlags; // custom country flag tree.
StringMap g_tRoutingNodes; // routing node information tree.

// booleans
bool g_bCustomAuthFlags; // custom flag tree is initialized.
bool g_bCustomLevels; // 'CustomLevels' plugin is initialized.
bool g_bRoutingNodes; // routing nodes tree is initialized.
bool g_bShowflag[MAXPLAYERS + 1] = {true, ...}; // flag visibility.

// cvars
ConVar net_public_adr = null;
ConVar g_cvarCustomFlag = null;
ConVar g_cvarRoutingNodeFlag = null;

//

enum struct RouteNode
{
	int flag;
	char host[64];
}

//

#define DATA "1.4.6"

public Plugin myinfo =
{
	name = "Franug Country Flag Icons",
	author = "Franc1sco franug, nukkonyan (Teamkiller324)",
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
	
	RegConsoleCmd("sm_flag", Cmd_Showflag, "[Franug: Scoreboard Flag] This allows players to toggle their flag visibility.");
	RegConsoleCmd("sm_showflag", Cmd_Showflag, "[Franug: Scoreboard Flag] This allows players to toggle their flag visibility.");
	hShowFlagCookie = new Cookie("Flags-Icons_No_Flags_Cookie", "Show or hide the flag.", CookieAccess_Private);
	
	g_cvarCustomFlag = CreateConVar("sm_franug_countryflags_customflags", "1", "Franug: Scoreboard Flag - If Enabled, Custom applied flags will be applied if found.", _, true, _, true, 1.0);
	g_cvarRoutingNodeFlag = CreateConVar("sm_franug_countryflags_routingnodeflags", "0", "Franug: Scoreboard Flag - If Enabled, Flag of the routing node will be used if the user is detected using a routing node.", _, true, _, true, 1.0);
	
	AutoExecConfig(true, "franug.countryflags");
}

public void OnAllPluginsLoaded()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/franug_countryflags.cfg");
	
	KeyValues kv = new KeyValues("CountryFlags");
	kv.ImportFromFile(path);
	
	// -- Load country flags ..
	
	g_tFlags = new StringMap();
	
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
					char flag[4], index[11];
					kv.GetSectionName(flag, sizeof(flag));
					kv.GetString("index", index, sizeof(index));
					
					if(strlen(flag) < 1)
					{
						LogError("Error parsing KeyValues : Country '%s' are invalid (index '%s')", flag, index);
					}
					else if(strlen(index) < 1 || StringToInt(index) <= 0)
					{
						LogError("Error parsing KeyValues : Country '%s' have an invalid index '%s'", flag, index);
					}
					
					char buffer[64];
					Format(buffer, sizeof(buffer), "materials/panorama/images/icons/xp/level%s.png", index);
					AddFileToDownloadsTable(buffer);
					
					g_tFlags.SetValue(flag, StringToInt(index));
				}
				while(kv.GotoNextKey());
				
				kv.GoBack();
			}
			
			kv.GoBack();
		}
	}
	
	// -- Load custom profile64 flags ..
	
	if(g_cvarCustomFlag.BoolValue)
	{
		g_tCustomFlags = new StringMap();
		
		if((g_bCustomAuthFlags = kv.JumpToKey("CustomFlags")))
		{
			int count;
			
			if(kv.GotoFirstSubKey())
			{
				do
				{
					count++;
					
					char auth64[24], flag[4];
					kv.GetSectionName(auth64, sizeof(auth64));
					kv.GetString("flag", flag, sizeof(flag));
					
					if(strlen(auth64) < 1)
					{
						LogError("Error parsing KeyValues : SteamID64 '%s' is invalid (index '%s')", auth64, flag);
					}
					else if(strlen(flag) < 1)
					{
						LogError("Error parsing KeyValues : SteamID64 '%s' have an invalid flag '%s'", auth64, flag);
					}
					
					g_tCustomFlags.SetValue(auth64, StringToInt(flag));
				}
				while(kv.GotoNextKey());
				
				kv.GoBack();
			}
			else
			{
				g_bCustomAuthFlags = false;
			}
			
			kv.GoBack();
		}
		else
		{
			PrintToServer("[Franug: CountryFlagIcons] No Custom SteamID64 flags were found when loading the config file, ignoring ..");
		}
	}
	
	// -- Load routing node information ..
	
	g_tRoutingNodes = new StringMap();
	
	if((g_bRoutingNodes = kv.JumpToKey("RoutingNodes")))
	{
		int count;
		
		if(kv.GotoFirstSubKey())
		{
			do
			{
				count++;
				
				char ip[16], host[64], flag[11];
				kv.GetSectionName(ip, sizeof(ip));
				kv.GetString("host", host, sizeof(host));
				kv.GetString("flag", flag, sizeof(flag));
				
				if(!IsValidIPv4(ip))
				{
					LogError("Error parsing KeyValues : Routing Node IP '%s' is invalid (hostname '%s')", ip, host);
				}
				else if(strlen(host) < 1)
				{
					LogError("Error parsing KeyValues : Routing Node IP '%s' have an invalid hostname '%s'", ip, host);
				}
				else if(strlen(flag) < 1)
				{
					LogError("Error parsing KeyValues : Routing Node IP '%s' have an invalid flag index '%s'", ip, flag);
				}
				
				RouteNode node;
				node.flag = StringToInt(flag);
				node.host = host;
				g_tRoutingNodes.SetArray(ip, node, sizeof(node));
			}
			while(kv.GotoNextKey());
			
			kv.GoBack();
		}
		else
		{
			g_bRoutingNodes = false;
		}
		
		kv.GoBack();
	}
	else
	{
		PrintToServer("[Franug: CountryFlagIcons] No Routing Node ip's were found when loading the config file, ignoring ..");
	}
	
	CreateTimer(2.5, Timer_CheckInGamePlayers);
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
	
	if(g_bCustomAuthFlags)
	{
		char auth64[24];
		if(GetClientAuthId(client, AuthId_SteamID64, auth64, sizeof(auth64)))
		{
			if(g_tCustomFlags.ContainsKey(auth64))
			{
				g_tCustomFlags.GetValue(auth64, m_iLevel[client]);
				return;
			}
		}
	}
	
	// --

	char ip[16];
	char code2[3];
	
	if(!GetClientIP(client, ip, sizeof(ip)) || !IsLocalAddress(ip) && !GeoipCode2(ip, code2) || !g_bShowflag[client])
	{
		g_tFlags.GetValue("UNKNOWN", m_iLevel[client]);		
		return;
	}
	
	if(IsLocalAddress(ip))
	{
		GeoipCode2(serverIp, code2);
	}
	
	// --
	
	if(g_bRoutingNodes)
	{
		if(g_tRoutingNodes.ContainsKey(ip))
		{
			RouteNode node;
			g_tRoutingNodes.GetArray(ip, node, sizeof(node));
			
			switch(g_cvarRoutingNodeFlag.BoolValue) // If allowed, set routing node flag ..
			{
				case false:
				{
					LogMessage("Player '%N' (UserID %i) Detected using routing node '%s'"
					, client, GetClientUserId(client), node.host);
				}
				case true:
				{
					LogMessage("Player '%N' (UserID %i) Detected using routing node '%s' and will use routing node flag."
					, client, GetClientUserId(client), node.host);
					
					m_iLevel[client] = node.flag;
					return;
				}
			}
		}
	}
	
	// --
	
	if(g_tFlags.ContainsKey(code2))
	{
		g_tFlags.GetValue(code2, m_iLevel[client]);
	}
	else
	{
		g_tFlags.GetValue("UNKNOWN", m_iLevel[client]);
		LogError("The flag '%s' for userid %i is unknown, using fallback.. (Needs to be added)", code2, GetClientUserId(client));
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
				g_bShowflag[client] = false;
				IntToString(cookieValue, sCookieValue, sizeof(sCookieValue));
				hShowFlagCookie.Set(client, sCookieValue);
				OnClientPutInServer(client);
				ReplyToCommand(client, "[SM] %T", "#ScoreBoardFlags_FlagInactive", client);
			}
			case true:
			{
				cookieValue = 0;
				g_bShowflag[client] = true;
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
	else if(StringToInt(sCookieValue) == 0)
	{
		g_bShowflag[client] = true;
		OnClientPutInServer(client);
	}
}

void OnThinkPost(int m_iEntity)
{
	int m_iLevelTemp[MAXPLAYERS+1];
	GetEntDataArray(m_iEntity, m_iOffset, m_iLevelTemp, sizeof(m_iLevelTemp));
	
	int i;
	while((i = FindEntityByClassname(i, "player")) != -1)
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

// -- callbacks

Action Timer_CheckInGamePlayers(Handle timer)
{
	int player;
	
	while((player = FindEntityByClassname(player, "player")) != -1)
	{
		OnClientPutInServer(player);
	}
	
	return Plugin_Continue;
}

// -- stocks

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

/*
 * Checks if the given IPv4 is valid.
 * 255.255.255.255 > 4x3=12+3=15 bytes
 *
 * @pragma ip The IPv4 Address.
 *
 * @return Returns the validity of the IPv4 address.
 */
bool IsValidIPv4(const char szIPv4[16])
{
	char buffer[4][3];
	if(ExplodeString(szIPv4, ".", buffer, sizeof(buffer), 16))
	{
		for(int i = 0; i < sizeof(buffer); i++)
		{
			if( !( (StringToInt(buffer[i]) >= 0) && (strlen(buffer[i]) > 0) ) )
			{
				return false;
			}
		}
	}
	
	return true;
}

/*
 * It wont be long until IPv6 will be required, replacing IPv4. IPv4 addresses are running out..
 */
/*IsValidIPv6(const char szIPv6[64])
{
	
}*/