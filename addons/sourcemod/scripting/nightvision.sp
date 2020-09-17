#include "sourcemod"
#include "sdktools"
#include "sdkhooks"
#include "clientprefs"

#define SNAME "[nightvision] "
#define CONFIG_FILE "configs/nightvision.cfg"

public Plugin myinfo =
{
	name = "NightVision",
	author = "GAMMA CASE",
	description = "Allows players to enable \"night vision\"",
	version = "1.0.1",
	url = "http://steamcommunity.com/id/_GAMMACASE_/"
};

enum struct Template
{
	int id;
	char displayName[128];
	char raw_file[PLATFORM_MAX_PATH];
}

methodmap TemplateList < ArrayList
{
	public TemplateList(int size)
	{
		return view_as<TemplateList>(new ArrayList(size));
	}
	
	public void GetDisplayName(int ccid, char[] displayName, int size)
	{
		int idx = this.FindValue(ccid);
		
		if(idx == -1)
			strcopy(displayName, size, "None");
		else
		{
			Template tmpl;
			this.GetArray(idx, tmpl);
			strcopy(displayName, size, tmpl.displayName);
		}
	}
	
	public void GetRawFile(int ccid, char[] raw_file, int size)
	{
		int idx = this.FindValue(ccid);
		
		if(idx == -1)
			ThrowError(SNAME..."Can't find id \"%i\" in gCCTemplates!", ccid);
		else
		{
			Template tmpl;
			this.GetArray(idx, tmpl);
			strcopy(raw_file, size, tmpl.raw_file);
		}
	}
}

TemplateList gCCTemplates;

enum struct Settings
{
	float intensity;
	int ccid;
	
	void Empty()
	{
		this.intensity = 1.0;
		this.ccid = gCCTemplates.Get(0);
	}
}

int gCCEntRefs[MAXPLAYERS] = {INVALID_ENT_REFERENCE, ...};
bool gEnabled[MAXPLAYERS];
Settings gSettings[MAXPLAYERS];
float gLastTimeOfUse[MAXPLAYERS];

bool gLate;

Cookie gSettingsCookie;
ConVar gIntensityDelta,
	gSpamDelta;

public void OnPluginStart()
{
	RegConsoleCmd("sm_nv", SM_NightVision, "Enables configured in \"sm_nightvisionsettings\" night vision.");
	RegConsoleCmd("sm_nightvision", SM_NightVision, "Enables configured in \"sm_nightvisionsettings\" night vision.");
	RegConsoleCmd("sm_nvs", SM_NightVisionSettings, "Open settings menu for night vision.");
	RegConsoleCmd("sm_nightvisionsettings", SM_NightVisionSettings, "Open settings menu for night vision.");
	
	gIntensityDelta = CreateConVar("nv_intensity_delta", "0.05", "Delta value that represents amount for increasing or decreasing in night vision settings.", .hasMin = true, .hasMax = true, .max = 1.0);
	gSpamDelta = CreateConVar("nv_spam_delta", "0.2", "How much seconds should players wait before toggling night vision.", .hasMin = true);
	AutoExecConfig();
	
	gSettingsCookie = new Cookie("nv_settings", "Settings for night vision.", CookieAccess_Private);
	gCCTemplates = new TemplateList(sizeof(Template));
	
	LoadTranslations("nightvision.phrases");
	
	ParseConfigFile();
	
	if(gLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i) || !AreClientCookiesCached(i))
				continue;
			
			OnClientCookiesCached(i);
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gLate = late;
}

public void OnConfigsExecuted()
{
	ParseConfigFile();
}

void ParseConfigFile()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), CONFIG_FILE);
	
	if(!FileExists(path))
		SetFailState(SNAME..."Can't find file \"%s\".", path);
	
	KeyValues kv = new KeyValues("NightVision");
	kv.ImportFromFile(path);
	
	kv.GotoFirstSubKey();
	gCCTemplates.Clear();
	
	char buff[32];
	Template tmpl;
	do
	{
		kv.GetSectionName(buff, sizeof(buff));
		
		tmpl.id = kv.GetNum("id", -1);
		if(tmpl.id == -1)
		{
			LogMessage(SNAME..."Invalid or missing id for \"%s\" section in nightvision.cfg, skipping...", buff);
			continue;
		}
		
		kv.GetString("display_name", tmpl.displayName, sizeof(Template::displayName));
		if(tmpl.displayName[0] == '\0')
		{
			LogMessage(SNAME..."Invalid or missing display_name for \"%s\" section in nightvision.cfg, skipping...", buff);
			continue;
		}
		
		kv.GetString("raw_file", tmpl.raw_file, sizeof(tmpl.raw_file));
		if(tmpl.raw_file[0] == '\0' || !FileExists(tmpl.raw_file, true))
		{
			LogMessage(SNAME..."Invalid or missing raw_file for \"%s\" section in nightvision.cfg, skipping...", buff);
			continue;
		}
		
		AddFileToDownloadsTable(tmpl.raw_file);
		
		gCCTemplates.PushArray(tmpl);
		
	} while(kv.GotoNextKey());
	
	if(gCCTemplates.Length == 0)
		SetFailState(SNAME..."Invalid or empty \"%s\" found, please add some entries to it before you can use that plugin!", path);
	
	delete kv;
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client))
		return;
	DeletePlayerCC(client);
	gEnabled[client] = false;
	gLastTimeOfUse[client] = 0.0;
	gSettings[client].Empty();
}

public void OnClientCookiesCached(int client)
{
	if(gCCTemplates.Length == 0 || IsFakeClient(client))
		return;
	
	char buff[32];
	gSettingsCookie.Get(client, buff, sizeof(buff));
	
	if(buff[0] == '\0')
		gSettings[client].Empty();
	else
	{
		char pts[2][16];
		ExplodeString(buff, ";", pts, sizeof(pts), sizeof(pts[]));
		gSettings[client].intensity = StringToFloat(pts[0]);
		gSettings[client].ccid = StringToInt(pts[1]);
		
		if(gCCTemplates.FindValue(gSettings[client].ccid) == -1)
			gSettings[client].ccid = gCCTemplates.Get(0);
	}
}

public Action SM_NightVisionSettings(int client, int args)
{
	if(client == 0)
		return Plugin_Handled;
	
	OpenNightVisionSettingsMenu(client);
	
	return Plugin_Handled;
}

void OpenNightVisionSettingsMenu(int client)
{
	Menu menu = new Menu(NightVisionSettings_Menu, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	
	menu.SetTitle("%T\n ", "nvs_menu_title", client);
	
	char buff[256];
	Format(buff, sizeof(buff), "%T\n ", "nvs_menu_ccselect", client);
	menu.AddItem("ccselect", buff);
	Format(buff, sizeof(buff), "%T\n ", "nvs_menu_intensity", client, gSettings[client].intensity);
	menu.AddItem("ccint", buff, ITEMDRAW_DISABLED);
	
	Format(buff, sizeof(buff), "%T", "nvs_menu_intensity_increase", client, gIntensityDelta.FloatValue);
	menu.AddItem("ccint_inc", buff);
	Format(buff, sizeof(buff), "%T", "nvs_menu_intensity_decrease", client, gIntensityDelta.FloatValue);
	menu.AddItem("ccint_dec", buff);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int NightVisionSettings_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DisplayItem:
		{
			char buff[16];
			menu.GetItem(param2, buff, sizeof(buff));
			
			if(StrEqual(buff, "ccint"))
			{
				char displ[256];
				Format(displ, sizeof(displ), "%T\n ", "nvs_menu_intensity", param1, gSettings[param1].intensity);
				return RedrawMenuItem(displ);
			}
		}
		
		case MenuAction_Select:
		{
			char buff[128];
			menu.GetItem(param2, buff, sizeof(buff));
			
			if(StrEqual(buff, "ccselect"))
			{
				Menu ccmenu = new Menu(CCTemplates_Menu, MENU_ACTIONS_DEFAULT | MenuAction_Display);
				
				gCCTemplates.GetDisplayName(gSettings[param1].ccid, buff, sizeof(buff));
				ccmenu.SetTitle("%T\n%T\n ", "cct_menu_title", param1, "cct_menu_curr_template", param1, buff);
				
				Template tmpl;
				for(int i = 0; i < gCCTemplates.Length; i++)
				{
					gCCTemplates.GetArray(i, tmpl);
					IntToString(tmpl.id, buff, sizeof(buff));
					ccmenu.AddItem(buff, tmpl.displayName);
				}
				
				ccmenu.ExitBackButton = true;
				
				ccmenu.Display(param1, MENU_TIME_FOREVER);
				delete menu;
			}
			else
			{
				if(StrEqual(buff, "ccint_inc"))
					gSettings[param1].intensity = Clamp(gSettings[param1].intensity + gIntensityDelta.FloatValue, 0.0, 1.0);
				else if(StrEqual(buff, "ccint_dec"))
					gSettings[param1].intensity = Clamp(gSettings[param1].intensity - gIntensityDelta.FloatValue, 0.0, 1.0);
				
				ReflectIntensityChange(param1);
				
				menu.Display(param1, MENU_TIME_FOREVER);
			}
		}
		
		case MenuAction_Cancel:
		{
			SaveSettings(param1);
		}
		
		case MenuAction_End:
		{
			if (param1 != MenuEnd_Selected)
				delete menu;
		}
	}
	
	return 0;
}

public int CCTemplates_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Display:
		{
			char buff[128];
			gCCTemplates.GetDisplayName(gSettings[param1].ccid, buff, sizeof(buff));
			menu.SetTitle("%T\n%T\n ", "cct_menu_title", param1, "cct_menu_curr_template", param1, buff);
		}
		
		case MenuAction_Select:
		{
			char buff[PLATFORM_MAX_PATH];
			menu.GetItem(param2, buff, sizeof(buff));
			
			gSettings[param1].ccid = StringToInt(buff);
			if(gCCTemplates.FindValue(gSettings[param1].ccid) == -1)
				ThrowError(SNAME..."Invalid id \"%i\" found in gCCTemplates!", gSettings[param1].ccid);
				
			if(gEnabled[param1])
			{
				if(IsSpamming(param1))
					PrintToChat(param1, "%T", "nightvision_spam_attempt", param1);
				else
				{
					DeletePlayerCC(param1);
					
					gCCTemplates.GetRawFile(gSettings[param1].ccid, buff, sizeof(buff));
					if(!CreatePlayerCC(param1, buff))
					{
						LogError(SNAME..."Can't create \"color_correction\" entity for %i (%N)", param1, param1);
						return 0;
					}
				}
			}
			
			menu.Display(param1, MENU_TIME_FOREVER);
		}
		
		case MenuAction_Cancel:
		{
			SaveSettings(param1);
			if(param2 == MenuCancel_ExitBack)
				OpenNightVisionSettingsMenu(param1);
		}
		
		case MenuAction_End:
		{
			if (param1 != MenuEnd_Selected)
				delete menu;
		}
	}
	
	return 0;
}

public Action SM_NightVision(int client, int args)
{
	if(client == 0)
		return Plugin_Handled;
	
	if(IsSpamming(client))
	{
		ReplyToCommand(client, "%T", "nightvision_spam_attempt", client);
		return Plugin_Handled;
	}
	
	gEnabled[client] = !gEnabled[client];
	
	DeletePlayerCC(client);
	
	if(!gEnabled[client])
		ReplyToCommand(client, "%T", "nightvision_disabled", client);
	else
	{
		char buff[PLATFORM_MAX_PATH];
		
		gCCTemplates.GetRawFile(gSettings[client].ccid, buff, sizeof(buff));
		if(!CreatePlayerCC(client, buff))
		{
			LogError(SNAME..."Can't create \"color_correction\" entity for %i (%N)", client, client);
			gEnabled[client] = false;
		}
		else
			ReplyToCommand(client, "%T", "nightvision_enabled", client);
	}
	
	return Plugin_Handled;
}

bool CreatePlayerCC(int client, const char[] raw_file)
{
	int ent = CreateEntityByName("color_correction");
	
	if(ent != -1)
	{
		DispatchKeyValue(ent, "StartDisabled", "0");
		DispatchKeyValue(ent, "maxweight", "1.0");
		DispatchKeyValue(ent, "maxfalloff", "-1.0");
		DispatchKeyValue(ent, "minfalloff", "0.0");
		DispatchKeyValue(ent, "filename", raw_file);
		
		DispatchSpawn(ent);
		ActivateEntity(ent);
		
		SetEntPropFloat(ent, Prop_Send, "m_flCurWeight", gSettings[client].intensity);
		SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_ALWAYS);
		SDKHook(ent, SDKHook_SetTransmit, CC_SetTransmit);
		gCCEntRefs[client] = EntIndexToEntRef(ent);
	}
	else
		return false;
	
	return true;
}

public Action CC_SetTransmit(int entity, int client)
{
	SetEdictFlags(entity, GetEdictFlags(entity) & ~FL_EDICT_ALWAYS);
	
	if (EntRefToEntIndex(gCCEntRefs[client]) != entity)
		return Plugin_Handled;
	else
	{
		SetEdictFlags(entity, GetEdictFlags(entity) | FL_EDICT_DONTSEND);
		SetEntPropFloat(entity, Prop_Send, "m_flCurWeight", gSettings[client].intensity);
		return Plugin_Continue;
	}
}

void DeletePlayerCC(int client)
{
	int ent = EntRefToEntIndex(gCCEntRefs[client]);
	if(ent != -1 && IsValidEntity(ent))
		RemoveEntity(ent);
	
	gCCEntRefs[client] = INVALID_ENT_REFERENCE;
}

float Clamp(float val, float min, float max)
{
	return (val < min) ? min : (max < val) ? max : val;
}

void SaveSettings(int client)
{
	char buff[32];
	Format(buff, sizeof(buff), "%.2f;%i", gSettings[client].intensity, gSettings[client].ccid);
	gSettingsCookie.Set(client, buff);
}

void ReflectIntensityChange(int client)
{
	if(gCCEntRefs[client] != INVALID_ENT_REFERENCE)
	{
		int ent = EntRefToEntIndex(gCCEntRefs[client]);
		
		if(ent != -1)
			SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_ALWAYS & ~FL_EDICT_DONTSEND);
	}
}

bool IsSpamming(int client)
{
	if(gLastTimeOfUse[client] < GetGameTime())
	{
		gLastTimeOfUse[client] = GetGameTime() + gSpamDelta.FloatValue;
		return false;
	}
	else
		return true;
}