#define PLUGIN_VERSION "1.1.1"

/*
	1.1.1 <-> 2016 6/11 - Caelan Borowiec
		Removed duplicate updater code
		Plugin now detects when the motd.txt file contains only a URL (redirect) and will add variables to this URL as well.
	1.0.0 <-> 2016 5/24 - Caelan Borowiec
		Initial Version
		Now with updater
*/

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#tryinclude <updater>
#define REQUIRE_PLUGIN

enum VGUIKVState {
	STATE_MSG,
	STATE_TITLE,
	STATE_CMD,
	STATE_TYPE,
	STATE_INVALID
}
new VGUIKVState:g_State = STATE_INVALID;

new String:g_BaseURL[PLATFORM_MAX_PATH];
new String:g_MotdFileURL[PLATFORM_MAX_PATH];

#define UPDATE_URL "http://bin.pinion.gg/bin/pinion-adverts-callback/adverts-callback.txt"


public OnPluginStart()
{
	// Catch the MOTD
	new UserMsg:VGUIMenu = GetUserMessageId("VGUIMenu");
	if (VGUIMenu == INVALID_MESSAGE_ID)
		SetFailState("Failed to find VGUIMenu usermessage");
	
	HookUserMessage(VGUIMenu, OnMsgVGUIMenu, true);
	
	BaseURLSetup();
	
	// Version of plugin - Make visible to game-monitor.com - Dont store in configuration file
	CreateConVar("pinion_adverts_callback_version", PLUGIN_VERSION, "[SM] Pinion Adverts Callback Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	#if defined _updater_included
		if (LibraryExists("updater"))
		{
			Updater_AddPlugin(UPDATE_URL);
		}
	#endif

}

public Action:OnMsgVGUIMenu(UserMsg:msg_id, Handle:self, const players[], playersNum, bool:reliable, bool:init)
{
	new client = players[0];
	if (playersNum > 1 || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	decl String:buffer[256];
	/*
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
		PbReadString(self, "name", buffer, sizeof(buffer));	
	else
		BfReadString(self, buffer, sizeof(buffer));
	*/
	
	BfReadString(self, buffer, sizeof(buffer));
		
	if (BfReadByte(self) != 1)
		return Plugin_Continue;
		
	PrintToServer("OnMsgVGUIMenu called");
	
	if (strcmp(buffer, "info") != 0)
			return Plugin_Continue;
			
	/*
	Data is arranged in pairs that can be read with BfReadString
	Odd key reads MAY be the data handle (eg, 'title' 'type' 'msg')
	Even data reads MAY be the data itself (eg, 'Sponsor Message', '2', 'http://google.com')
	If data values are not set, this ordering will not be predictable apart from the key first and the value second
	*/
	
	 // we need to read twice to get each "pair" of data
	 // this may over-estimate the number of reads needed (if some data values are missing) 
	new count = BfReadByte(self) * 2;
	//PrintToServer("Expecting %i values", count);
	
	decl String:title[256];
	decl String:type[16];
	decl String:msg[256];
	decl String:cmd[64];
	
	//PrintToServer("Debug dump:\n-----");

	for (new i = 0; i < count; i++)
	{
		BfReadString(self, buffer, sizeof(buffer));
		
		if (!strcmp(buffer, ""))
			continue; //We could probably safely break here
		
		//PrintToServer(buffer);
		
		g_State = STATE_INVALID;
		
		// Figure out which bit of data it is
		if (!strcmp(buffer, "title"))
			g_State = STATE_TITLE;
		else if (!strcmp(buffer, "type"))
			g_State = STATE_TYPE;
		else if (!strcmp(buffer, "msg"))
			g_State = STATE_MSG;
		else if (!strcmp(buffer, "cmd"))
			g_State = STATE_CMD;
		
		// Now read the actual data
		BfReadString(self, buffer, sizeof(buffer));
		switch (g_State)
		{
			case STATE_TITLE:
			{
				strcopy(title, sizeof(title), buffer);
			}
			case STATE_TYPE:
			{
				strcopy(type, sizeof(type), buffer);
			}
			case STATE_MSG:
			{
				strcopy(msg, sizeof(msg), buffer);
			}
			case STATE_CMD:
			{
				strcopy(cmd, sizeof(cmd), buffer);
			}
		}
	}
	
	PrintToServer("-----");

	PrintToServer("title = %s", title);
	PrintToServer("type = %s", type);
	PrintToServer("msg = %s", msg);
	PrintToServer("cmd = %s", cmd);
	
	// Check for valid web URLs and block them so we can create a modified version
	if((StrContains(msg, "http://", false) == 0) || (StrContains(msg, "https://", false) == 0))
	{
		PrintToServer("Valid URL detected!");
		
		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientSerial(client));
		WritePackString(pack, title);
		WritePackString(pack, type);
		WritePackString(pack, msg);
		WritePackString(pack, cmd);
		
		CreateTimer(0.0, RedirectPage, pack, TIMER_FLAG_NO_MAPCHANGE);  // Delay a frame so this hook can die

		return Plugin_Handled;
	}
	else 	if (StringToInt(type) == MOTDPANEL_TYPE_INDEX && StrEqual(msg, "motd") && !StrEqual(g_MotdFileURL, ""))
	{
		//Loading motd.txt (hopefully) and it has a URL
		PrintToServer("URL detected in MOTD.txt");
		 
		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientSerial(client));
		WritePackString(pack, title);
		WritePackString(pack, type);
		WritePackString(pack, g_MotdFileURL);
		WritePackString(pack, cmd);
		
		CreateTimer(0.0, RedirectPage, pack, TIMER_FLAG_NO_MAPCHANGE);  // Delay a frame so this hook can die

		return Plugin_Handled;
	}
		
	return Plugin_Continue;
}


BaseURLSetup()
{
	new Handle:hFile = OpenFile("motd.txt", "r");
	if(hFile != INVALID_HANDLE)
	{
		decl String:sBuffer[256];
		if(ReadFileLine(hFile, sBuffer, sizeof(sBuffer)))  // Only read one line
		{
			TrimString(sBuffer);
			if((StrContains(sBuffer, "http://", false) == 0) || (StrContains(sBuffer, "https://", false) == 0))
			{
				// Valid URL at the start of the file
				strcopy(g_MotdFileURL, sizeof(g_MotdFileURL), sBuffer);
			}
		}
	}
	CloseHandle(hFile);


	decl String:szGameProfile[32];
	GetGameFolderName(szGameProfile, sizeof(szGameProfile));

	new hostip = GetConVarInt(FindConVar("hostip"));
	new hostport = GetConVarInt(FindConVar("hostport"));

	Format(g_BaseURL, sizeof(g_BaseURL), "?game=%s&ip=%d.%d.%d.%d&po=%d",
		szGameProfile,
		hostip >>> 24 & 255, hostip >>> 16 & 255, hostip >>> 8 & 255, hostip & 255,
		hostport);
}

public Action:RedirectPage(Handle:timer, Handle:pack)
{
	ResetPack(pack);
	new client = GetClientFromSerial(ReadPackCell(pack));
	if (!client)
		return Plugin_Stop;
		
	decl String:title[256];
	decl String:type[16];
	decl String:msg[256];
	decl String:cmd[64];
	
	ReadPackString(pack, title, sizeof(title));
	ReadPackString(pack, type, sizeof(type));
	ReadPackString(pack, msg, sizeof(msg));
	ReadPackString(pack, cmd, sizeof(cmd));
	
	decl String:szAuth[64];
	GetClientAuthId(client, AuthId_Steam2, szAuth, sizeof(szAuth));
		
	Format(msg, sizeof(msg), "%s%s&si=%s", msg, g_BaseURL, szAuth);
	
	new Handle:kv = CreateKeyValues("data");
	KvSetString(kv, "msg",	msg);
	KvSetString(kv, "title", title);
	KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
	ShowVGUIPanelEx(client, "info", kv, true, USERMSG_BLOCKHOOKS|USERMSG_RELIABLE);
	CloseHandle(kv);
	
	CloseHandle(pack);
	
	return Plugin_Stop;
}


ShowVGUIPanelEx(client, const String:name[], Handle:kv=INVALID_HANDLE, bool:show=true, usermessageFlags=0)
{
	new Handle:msg = StartMessageOne("VGUIMenu", client, usermessageFlags);

	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
	{
		PbSetString(msg, "name", name);
		PbSetBool(msg, "show", true);

		if (kv != INVALID_HANDLE && KvGotoFirstSubKey(kv, false))
		{
			new Handle:subkey;

			do
			{
				decl String:key[128], String:value[128];
				KvGetSectionName(kv, key, sizeof(key));
				KvGetString(kv, NULL_STRING, value, sizeof(value), "");

				subkey = PbAddMessage(msg, "subkeys");
				PbSetString(subkey, "name", key);
				PbSetString(subkey, "str", value);

			} while (KvGotoNextKey(kv, false));
		}
	}
	else //BitBuffer
	{
		BfWriteString(msg, name);
		BfWriteByte(msg, show);

		if (kv == INVALID_HANDLE)
		{
			BfWriteByte(msg, 0);
		}
		else
		{
			if (!KvGotoFirstSubKey(kv, false))
			{
				BfWriteByte(msg, 0);
			}
			else
			{
				new keyCount = 0;
				do
				{
					++keyCount;
				} while (KvGotoNextKey(kv, false));

				BfWriteByte(msg, keyCount);

				if (keyCount > 0)
				{
					KvGoBack(kv);
					KvGotoFirstSubKey(kv, false);
					do
					{
						decl String:key[128], String:value[128];
						KvGetSectionName(kv, key, sizeof(key));
						KvGetString(kv, NULL_STRING, value, sizeof(value), "");

						BfWriteString(msg, key);
						BfWriteString(msg, value);
					} while (KvGotoNextKey(kv, false));
				}
			}
		}
	}

	EndMessage();
}

