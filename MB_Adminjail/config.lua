Config = {}

-- Framework: "ESX", "QBCore" or "Standalone".
-- For ESX/QBCore, make sure the framework resource is started before this resource.
Config.Framework = "ESX"

-- Database driver: "oxmysql" or "mysql-async".
-- oxmysql is recommended.
Config.Database = {
    Driver = "oxmysql",

    -- true: deletes active row after release, logs table view will only contain currently stored rows.
    -- false: marks rows as released/completed and keeps them for the Tablet log view.
    DeleteOnRelease = false
}

-- TimerMode:
-- "online"   = jail time only counts while the player is online. Leaving saves the remaining time.
-- "realtime" = jail time continues while the player is offline, based on release_at.
Config.TimerMode = "online"

-- Positions. Use vector4(x, y, z, heading).
Config.JailCoords = vector4(1691.42, 2565.88, 45.56, 180.0)     -- Bolingbroke example
Config.ReleaseCoords = vector4(1847.84, 2586.03, 45.67, 270.0)  -- Outside prison example
Config.JailRadius = 65.0

-- Jail behavior
Config.MaxJailTime = 1440 -- minutes
Config.RemoveWeapons = true
Config.ForceLeaveVehicle = true
Config.FreezePlayer = false -- true = player cannot move; false = may move inside Config.JailRadius
Config.DisableCombatControls = true

-- Ingame Jail HUD. Zeigt nur Restzeit + Grund als kleines NUI-HUD.
-- Keine zusätzlichen Command-Hinweise im HUD.
Config.ShowJailTimerHud = true

-- UI / Commands
Config.OpenTabletCommand = "mbadminjail"
Config.UnjailCommand = "mbunjail"
Config.QuickJailCommand = "mbjail"
Config.RejoinCheckDelay = 5 -- seconds after spawn before DB recheck

-- Notify system: "ox", "framework", "okok", "mythic", "chat", "default".
-- "ox" nutzt ox_lib notify (empfohlen).
Config.Notify = "ox"

-- Permissions. You can combine ACE + framework groups.
Config.Permissions = {
    UseAce = true,
    AcePermission = "mb_adminjail.use",

    UseFrameworkGroups = true,
    ESXGroups = { "admin", "superadmin", "mod" },
    QBCorePermissions = { "god", "admin" },

    -- Optional extra identifiers that always have access.
    -- Example: "license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    AdminIdentifiers = {}
}

-- Discord Webhook / Logs.
-- Trage hier deinen echten Discord Webhook ein.
-- Beispiel: "https://discord.com/api/webhooks/WEBHOOK_ID/WEBHOOK_TOKEN"
-- Leer lassen = Webhook deaktiviert.
Config.DiscordWebhook = ""
Config.DiscordBotName = "MB_Adminjail Logs"
Config.DiscordAvatar = ""
Config.DiscordServerName = "FiveM Server"
Config.DiscordFooter = "MB_Adminjail"
Config.DiscordMention = "" -- Optional: z. B. "<@&ROLE_ID>" oder leer lassen.
Config.DiscordDebug = false -- true = gibt erfolgreiche Webhook-Requests in der Server-Konsole aus.
Config.DiscordShowIdentifiers = false -- false = keine license:/char1:/citizenid im Discord-Log sichtbar.
Config.DiscordDebugPayload = false -- true = druckt den exakten Components-V2-JSON-Payload in die Server-Konsole.
-- Webhook wird als Discord Components V2 Container gesendet, nicht als Embed.
Config.DiscordColors = {
    Jail = 15158332,
    Unjail = 3066993
}

-- Date format used in Discord logs and UI output.
Config.DateFormat = "%d.%m.%Y %H:%M:%S"

-- How often active jails are saved / counted down.
-- Keep at 60 unless you specifically need faster updates.
Config.TickSeconds = 60
