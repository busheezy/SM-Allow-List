#include <sdktools>
#pragma newdecls required

#define DB_NAME     "allowlist"
#define ADD_COMMAND "sm_allowlist_add"
#define CHAT_PREFIX " \x04[Allow List] \x01"

Database db = null;

public Plugin myinfo =
{
  name        = "Allow List",
  author      = "BadServers.net",
  description = "Allows only certain steamIds to join the server. Based on simple whitelist by Xines and johan123jo.",
  version     = "1.0.0",
  url         = "https://BadsServers.net",
};

public void OnPluginStart()
{
  RegAdminCmd(ADD_COMMAND, Command_Add, ADMFLAG_CUSTOM2, "Add a steamId to the database.");

  if (SQL_CheckConfig(DB_NAME))
  {
    SQL_TConnect(OnDatabaseConnect, DB_NAME);
  }
  else
  {
    SetFailState("Can't find '%s' entry in sourcemod/configs/databases.cfg!", DB_NAME);
  }
}

public void OnDatabaseConnect(Handle owner, Handle hndl, const char[] error, any data)
{
  if (hndl == null || strlen(error) > 0)
  {
    PrintToServer("Unable to connect to database (%s)", error);
    LogError("Unable to connect to database (%s)", error);
    return;
  }

  Handle clonedHandle = CloneHandle(hndl);
  db                  = view_as<Database>(clonedHandle);

  PrintToServer("Successfully connected to database!");
}

public void OnClientPostAdminCheck(int client)
{
  if (!IsValidClient(client))
  {
    return;
  }

  if (IsFakeClient(client))
  {
    return;
  }

  char steamId[64];
  GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
  StripSteamInputPrefix(steamId, sizeof(steamId));

  char playerName[64];
  GetClientName(client, playerName, sizeof(playerName));

  if (CheckCommandAccess(client, ADD_COMMAND, ADMFLAG_CUSTOM2))
  {
    return;
  }

  char query[256];
  Format(query, sizeof(query), "SELECT steamId FROM %s WHERE steamId = '%s'", DB_NAME, steamId);

  int userId = GetClientUserId(client);
  db.Query(SQL_CheckSteamID, query, userId);
}

public void SQL_CheckSteamID(Handle owner, DBResultSet results, const char[] error, any data)
{
  int client = GetClientOfUserId(data);

  if (client == 0)
  {
    return;
  }

  if (!IsClientConnected(client))
  {
    return;
  }

  if (results == null || strlen(error) > 0)
  {
    LogError("Query failed! %s", error);
    KickClient(client, "Authorization failed, please try again later");
    return;
  }

  if (results.RowCount == 0)
  {
    KickClient(client, "BadServers.net/contact\nVisit our discord to request access");
    return;
  }
}

public Action Command_Add(int client, int args)
{
  if (!IsValidClient(client))
  {
    return Plugin_Handled;
  }

  char exampleInputReply[128];
  FormatEx(exampleInputReply, sizeof(exampleInputReply), "%sInvalid input. Example input: !%s STEAM_0:1:6157769 Name", CHAT_PREFIX, ADD_COMMAND);

  char arguments[256];
  GetCmdArgString(arguments, sizeof(arguments));

  char steamInput[50];
  int  len = BreakString(arguments, steamInput, sizeof(steamInput));

  if (len == -1)
  {
    ReplyToCommand(client, exampleInputReply);
    return Plugin_Handled;
  }

  if (!IsValidSteamInput(steamInput))
  {
    ReplyToCommand(client, exampleInputReply);
    return Plugin_Handled;
  }

  StripSteamInputPrefix(steamInput, sizeof(steamInput));

  char playerNameInput[32];
  BreakString(arguments[len], playerNameInput, sizeof(playerNameInput));

  DataPack pack   = new DataPack();
  int      userId = GetClientUserId(client);
  pack.WriteCell(userId);
  pack.WriteString(steamInput);
  pack.WriteString(playerNameInput);

  char query[256];
  Format(query, sizeof(query), "SELECT steamId FROM %s WHERE steamId = '%s'", DB_NAME, steamInput);

  db.Query(SQL_AddSteamid_Check, query, pack);

  ReplyToCommand(client, "%sChecking if Steam ID: %s is in the database.", CHAT_PREFIX, steamInput);
  return Plugin_Handled;
}

public void SQL_AddSteamid_Check(Handle owner, DBResultSet results, const char[] error, DataPack pack)
{
  pack.Reset();

  int  userId = pack.ReadCell();
  int  client = GetClientOfUserId(userId);
  char steamInput[32];
  pack.ReadString(steamInput, sizeof(steamInput));
  char playerNameInput[32];
  pack.ReadString(playerNameInput, sizeof(playerNameInput));

  if (!IsValidClient(client))
  {
    delete view_as<DataPack>(pack);
    return;
  }

  if (results == null || strlen(error) > 0)
  {
    LogError("Query failed! %s", error);
    PrintToChat(client, "%sQuery failed, please try again later.", CHAT_PREFIX);
    delete view_as<DataPack>(pack);
    return;
  }

  if (results.RowCount == 0)
  {
    char adminName[32];
    GetClientName(client, adminName, sizeof(adminName));

    char query[256];
    Format(query, sizeof(query), "INSERT INTO %s (name, steamId, notes) VALUES ('%s', '%s', 'invited by %s')", DB_NAME, playerNameInput, steamInput, adminName);

    db.Query(SQL_AddSteamid_Add, query, pack);
  }
  else
  {
    PrintToChat(client, "%sThe Steam ID %s is already in the database.", CHAT_PREFIX, steamInput);
    delete view_as<DataPack>(pack);
  }
}

public void SQL_AddSteamid_Add(Handle owner, DBResultSet results, const char[] error, DataPack pack)
{
  pack.Reset();

  int  userId = pack.ReadCell();
  int  client = GetClientOfUserId(userId);
  char steamInput[32];
  pack.ReadString(steamInput, sizeof(steamInput));

  if (!IsValidClient(client))
  {
    delete view_as<DataPack>(pack);
    return;
  }

  if (results == null || strlen(error) > 0)
  {
    LogError("Query failed! %s", error);
    PrintToChat(client, "%sQuery failed, please try again later.", CHAT_PREFIX);
  }
  else
  {
    PrintToChat(client, "%sThe Steam ID %s has been added to the database.", CHAT_PREFIX, steamInput);
  }

  delete view_as<DataPack>(pack);
}

public void SQL_ErrorCheckCallback(Handle owner, DBResultSet results, const char[] error, any pack)
{
  if (results != null && strlen(error) == 0)
  {
    return;
  }

  LogError("Query failed! %s", error);
}

void StripSteamInputPrefix(char[] steamInput, int maxLength)
{
  ReplaceString(steamInput, maxLength, "STEAM_0:", "", false);
  ReplaceString(steamInput, maxLength, "STEAM_1:", "", false);
}

bool IsValidSteamInput(const char[] steamInput)
{
  if (StrContains(steamInput, "STEAM_0:", false) != -1)
  {
    return true;
  }

  if (StrContains(steamInput, "STEAM_1:", false) != -1)
  {
    return true;
  }

  return false;
}

bool IsValidClient(int client)
{
  if (client <= 0 || client > MaxClients)
  {
    return false;
  }

  return true;
}