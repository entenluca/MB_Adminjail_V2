local ESX, QBCore = nil, nil
local jailedPlayers = {}
local checkJailOnJoin

local CREATE_TABLE_SQL = [[
CREATE TABLE IF NOT EXISTS `mb_adminjail` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(100) NOT NULL,
  `name` VARCHAR(80) NOT NULL,
  `reason` TEXT NOT NULL,
  `time_left` INT NOT NULL DEFAULT 0 COMMENT 'Remaining jail time in seconds',
  `jailed_by` VARCHAR(80) NOT NULL,
  `jailed_by_identifier` VARCHAR(100) DEFAULT NULL,
  `jailed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `release_at` INT DEFAULT NULL COMMENT 'Unix timestamp used when Config.TimerMode = realtime',
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `released_by` VARCHAR(80) DEFAULT NULL,
  `released_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_identifier_status` (`identifier`, `status`),
  KEY `idx_status` (`status`),
  KEY `idx_jailed_at` (`jailed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local function trim(value)
    if value == nil then return "" end
    return tostring(value):match('^%s*(.-)%s*$') or ""
end

local function contains(list, value)
    if not list then return false end
    for _, item in ipairs(list) do
        if tostring(item):lower() == tostring(value):lower() then
            return true
        end
    end
    return false
end

local function tableLength(t)
    local count = 0
    for _ in pairs(t or {}) do count = count + 1 end
    return count
end

local function isOxmysql()
    return (Config.Database.Driver == "oxmysql" and GetResourceState('oxmysql') == 'started')
end

local function waitForDatabase(maxAttempts)
    maxAttempts = maxAttempts or 40

    for attempt = 1, maxAttempts do
        if isOxmysql() then
            if MySQL and MySQL.ready and MySQL.ready.await then
                MySQL.ready.await()
            end
            return true
        end

        if MySQL and MySQL.Async then
            return true
        end

        Wait(500)
    end

    return false
end

local function getAutoCreateSql()
    local sqlFile = LoadResourceFile(GetCurrentResourceName(), 'sql/mb_adminjail.sql')
    if sqlFile and trim(sqlFile) ~= '' then
        return sqlFile
    end

    return CREATE_TABLE_SQL
end

local function initDatabase(cb)
    if Config.Database.AutoCreateTable == false then
        if cb then cb(false) end
        return
    end

    local sql = getAutoCreateSql()

    if isOxmysql() and MySQL and MySQL.query and MySQL.query.await then
        local ok, err = pcall(function()
            MySQL.query.await(sql)
        end)

        if not ok then
            print(('^1[MB_Adminjail] SQL Auto-Setup fehlgeschlagen: %s^0'):format(tostring(err)))
            if cb then cb(false) end
            return
        end

        print('^2[MB_Adminjail] SQL-Tabelle automatisch geprüft/erstellt (mb_adminjail).^0')
        if cb then cb(true) end
        return
    end

    dbExecute(sql, {}, function()
        print('^2[MB_Adminjail] SQL-Tabelle automatisch geprüft/erstellt (mb_adminjail).^0')
        if cb then cb(true) end
    end)
end

local function dbExecute(query, params, cb)
    params = params or {}

    if isOxmysql() then
        exports.oxmysql:execute(query, params, function(result)
            if cb then cb(result) end
        end)
        return
    end

    if MySQL and MySQL.Async then
        MySQL.Async.execute(query, params, function(result)
            if cb then cb(result) end
        end)
        return
    end

    print('^1[MB_Adminjail] No supported MySQL driver found. Start oxmysql or mysql-async before this resource.^0')
    if cb then cb(nil) end
end

local function dbQuery(query, params, cb)
    params = params or {}

    if isOxmysql() then
        exports.oxmysql:query(query, params, function(result)
            if cb then cb(result or {}) end
        end)
        return
    end

    if MySQL and MySQL.Async then
        MySQL.Async.fetchAll(query, params, function(result)
            if cb then cb(result or {}) end
        end)
        return
    end

    print('^1[MB_Adminjail] No supported MySQL driver found. Start oxmysql or mysql-async before this resource.^0')
    if cb then cb({}) end
end

local function dbInsert(query, params, cb)
    params = params or {}

    if isOxmysql() then
        exports.oxmysql:insert(query, params, function(insertId)
            if cb then cb(insertId or 0) end
        end)
        return
    end

    if MySQL and MySQL.Async and MySQL.Async.insert then
        MySQL.Async.insert(query, params, function(insertId)
            if cb then cb(insertId or 0) end
        end)
        return
    end

    dbExecute(query, params, function()
        if cb then cb(0) end
    end)
end

local function initFramework()
    if Config.Framework == "ESX" then
        if exports['es_extended'] and exports['es_extended'].getSharedObject then
            ESX = exports['es_extended']:getSharedObject()
        else
            TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        end
    elseif Config.Framework == "QBCore" then
        if exports['qb-core'] and exports['qb-core'].GetCoreObject then
            QBCore = exports['qb-core']:GetCoreObject()
        end
    end
end

local function getLicenseIdentifier(src)
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:find('license:', 1, true) then
            return identifier
        end
    end

    local identifiers = GetPlayerIdentifiers(src)
    return identifiers[1] or ('source:' .. tostring(src))
end

local function getIdentifier(src)
    src = tonumber(src)
    if not src then return nil end

    if Config.Framework == "ESX" and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.identifier then
            return xPlayer.identifier
        end
    elseif Config.Framework == "QBCore" and QBCore then
        local player = QBCore.Functions.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.citizenid then
            return player.PlayerData.citizenid
        end
    end

    return getLicenseIdentifier(src)
end

local function getDisplayName(src)
    src = tonumber(src)
    if not src then return "Console" end

    if Config.Framework == "ESX" and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.getName then
            local name = xPlayer.getName()
            if name and name ~= "" then return name end
        end
    elseif Config.Framework == "QBCore" and QBCore then
        local player = QBCore.Functions.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.charinfo then
            local info = player.PlayerData.charinfo
            local fullName = trim((info.firstname or "") .. " " .. (info.lastname or ""))
            if fullName ~= "" then return fullName end
        end
    end

    return GetPlayerName(src) or ('ID ' .. tostring(src))
end

local function getFiveMName(src)
    src = tonumber(src)
    if not src or src == 0 then return 'Console' end
    return GetPlayerName(src) or getDisplayName(src)
end

local function notify(src, message, notifyType)
    if not src or tonumber(src) == 0 then
        print('[MB_Adminjail] ' .. message)
        return
    end

    TriggerClientEvent('mb_adminjail:client:notify', src, message, notifyType or 'info')
end

local function coordsToTable(coords)
    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = coords.w or coords.heading or 0.0
    }
end

local function secondsToClock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local rest = seconds % 60

    if hours > 0 then
        return ('%02d:%02d:%02d'):format(hours, minutes, rest)
    end

    return ('%02d:%02d'):format(minutes, rest)
end

local function minutesLeftLabel(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds <= 0 then return '0' end

    local minutes = math.floor(seconds / 60)
    if minutes <= 0 then return 'unter 1' end

    return tostring(minutes)
end

-- Hält die Jailzeit serverseitig exakt. Wichtig für Rejoin-Schutz:
-- Bei Config.TimerMode = "online" wird beim Disconnect die wirklich verbleibende Zeit gespeichert.
local function applyTimeProgress(data)
    if not data then return 0 end

    local now = os.time()

    if Config.TimerMode == "realtime" then
        data.timeLeft = math.max(0, (tonumber(data.releaseAt) or now) - now)
        data.lastUpdated = now
        return data.timeLeft
    end

    local lastUpdated = tonumber(data.lastUpdated) or now
    local elapsed = math.max(0, now - lastUpdated)

    if elapsed > 0 then
        data.timeLeft = math.max(0, (tonumber(data.timeLeft) or 0) - elapsed)
        data.lastUpdated = now
    end

    return data.timeLeft
end

local function findOnlineSourceByIdentifier(identifier)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if getIdentifier(src) == identifier then
            return src
        end
    end

    return nil
end

local function hasIdentifierPermission(src)
    local allIdentifiers = GetPlayerIdentifiers(src)
    local frameworkIdentifier = getIdentifier(src)

    for _, allowed in ipairs(Config.Permissions.AdminIdentifiers or {}) do
        if frameworkIdentifier == allowed then return true end

        for _, identifier in ipairs(allIdentifiers) do
            if identifier == allowed then return true end
        end
    end

    return false
end

local function hasPermission(src)
    src = tonumber(src)
    if src == 0 then return true end
    if not src then return false end

    if hasIdentifierPermission(src) then return true end

    if Config.Permissions.UseAce and Config.Permissions.AcePermission then
        if IsPlayerAceAllowed(src, Config.Permissions.AcePermission) then
            return true
        end
    end

    if Config.Permissions.UseFrameworkGroups then
        if Config.Framework == "ESX" and ESX then
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer and xPlayer.getGroup then
                local group = xPlayer.getGroup()
                if contains(Config.Permissions.ESXGroups, group) then
                    return true
                end
            end
        elseif Config.Framework == "QBCore" and QBCore then
            for _, permission in ipairs(Config.Permissions.QBCorePermissions or {}) do
                if QBCore.Functions.HasPermission(src, permission) then
                    return true
                end
            end
        end
    end

    return false
end



local function buildWebhookUrl(url)
    url = trim(url or '')
    if url == '' then return '' end

    -- Components V2 braucht bei normalen Discord-Webhooks den Query-Parameter.
    local separator = url:find('?', 1, true) and '&' or '?'
    if not url:find('with_components=', 1, true) then
        url = url .. separator .. 'with_components=true'
        separator = '&'
    end

    -- wait=true gibt bei Discord-Fehlern einen lesbaren Body zurück.
    if not url:find('wait=', 1, true) then
        url = url .. separator .. 'wait=true'
    end

    return url
end

local function discordValue(value, fallback)
    value = tostring(value or fallback or 'Unbekannt')
    if value == '' then value = fallback or 'Unbekannt' end
    value = value:gsub('`', '´')
    if #value > 950 then value = value:sub(1, 947) .. '...' end
    return value
end

local function discordLine(label, value)
    return ('**%s:** %s'):format(label, discordValue(value, '-'))
end

local function webhook(action, data)
    local webhookUrl = buildWebhookUrl(Config.DiscordWebhook)
    if webhookUrl == '' then return end

    data = data or {}

    local isJail = action == 'jail'
    local colors = Config.DiscordColors or {}
    local color = isJail and (colors.Jail or 15158332) or (colors.Unjail or 3066993)
    local title = isJail and 'AdminJail | Spieler eingesperrt' or 'AdminJail | Spieler entlassen'
    local actionText = isJail and 'Neue Strafe wurde ausgestellt.' or (data.automatic and 'Die Jail-Zeit ist automatisch abgelaufen.' or 'Spieler wurde manuell entlassen.')
    local playerServerId = data.playerSource and tostring(data.playerSource) or 'Offline'
    local timeLabel = isJail and 'Jail-Zeit' or 'Restzeit beim Entlassen'
    local releaseType = data.automatic and 'Automatisch' or 'Manuell'
    local serverName = Config.DiscordServerName or GetConvar('sv_hostname', 'FiveM Server')
    local showIdentifiers = Config.DiscordShowIdentifiers == true
    local mention = trim(Config.DiscordMention or '')

    local function textDisplay(content)
        return { type = 10, content = discordValue(content, '-') }
    end

    local function separator(spacing)
        return { type = 14, divider = true, spacing = spacing or 1 }
    end

    local function lines(...)
        local out = {}
        for i = 1, select('#', ...) do
            local value = select(i, ...)
            if value and value ~= '' then out[#out + 1] = value end
        end
        return table.concat(out, '\n')
    end

    local overview = lines(
        '# ' .. title,
        actionText,
        mention ~= '' and ('-# Hinweis: ' .. mention) or nil
    )

    local adminBlock = lines(
        '## Admin',
        ('Name: %s'):format(discordValue(data.adminName)),
        showIdentifiers and ('Identifier: %s'):format(discordValue(data.adminIdentifier)) or nil
    )

    local playerBlock = lines(
        '## Spieler',
        ('Name: %s'):format(discordValue(data.playerName)),
        ('Server-ID: %s'):format(discordValue(playerServerId)),
        showIdentifiers and ('Identifier: %s'):format(discordValue(data.playerIdentifier)) or nil
    )

    local detailsBlock = lines(
        '## Details',
        ('Grund: %s'):format(discordValue(data.reason or 'Kein Grund gespeichert')),
        ('%s: %s Minuten'):format(timeLabel, tostring(tonumber(data.minutes) or 0)),
        (not isJail) and ('Entlassung: ' .. releaseType) or nil
    )

    local footerBlock = lines(
        '## System',
        ('Datum/Uhrzeit: %s'):format(discordValue(os.date(Config.DateFormat))),
        ('Server: %s'):format(discordValue(serverName)),
        trim(Config.DiscordFooter or '') ~= '' and discordValue(Config.DiscordFooter) or nil
    )

    local payload = {
        username = Config.DiscordBotName or 'AdminJail Logs',
        avatar_url = trim(Config.DiscordAvatar or '') ~= '' and Config.DiscordAvatar or nil,
        flags = 32768,
        components = {
            {
                type = 17,
                accent_color = color,
                components = {
                    textDisplay(overview),
                    separator(1),
                    textDisplay(adminBlock),
                    textDisplay(playerBlock),
                    separator(1),
                    textDisplay(detailsBlock),
                    separator(1),
                    textDisplay(footerBlock)
                }
            }
        }
    }

    if mention ~= '' then
        payload.allowed_mentions = { parse = { 'roles', 'users' } }
    end

    if Config.DiscordDebugPayload == true then
        print('^3[MB_Adminjail] Discord Components V2 Payload:^0 ' .. json.encode(payload))
    end

    PerformHttpRequest(webhookUrl, function(statusCode, body)
        statusCode = tonumber(statusCode) or 0
        if statusCode < 200 or statusCode >= 300 then
            print(('^1[MB_Adminjail] Discord Webhook Fehler: HTTP %s | %s^0'):format(statusCode, body or 'keine Antwort'))
            print('^3[MB_Adminjail] Components V2 erwartet: flags=32768, URL mit ?with_components=true, keine embeds/content.^0')
        elseif Config.DiscordDebug then
            print(('^2[MB_Adminjail] Discord Webhook Components V2 gesendet: HTTP %s^0'):format(statusCode))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function completeJailRecord(identifier, rowId, releasedBy)
    local params = {
        ['@identifier'] = identifier,
        ['@id'] = rowId or 0,
        ['@released_by'] = releasedBy or 'SYSTEM'
    }

    if Config.Database.DeleteOnRelease then
        if rowId and tonumber(rowId) and tonumber(rowId) > 0 then
            dbExecute('DELETE FROM `mb_adminjail` WHERE `id` = @id LIMIT 1', params)
        else
            dbExecute('DELETE FROM `mb_adminjail` WHERE `identifier` = @identifier AND `status` = "active" ORDER BY `id` DESC LIMIT 1', params)
        end
        return
    end

    if rowId and tonumber(rowId) and tonumber(rowId) > 0 then
        dbExecute('UPDATE `mb_adminjail` SET `status` = "released", `time_left` = 0, `released_by` = @released_by, `released_at` = CURRENT_TIMESTAMP WHERE `id` = @id LIMIT 1', params)
    else
        dbExecute('UPDATE `mb_adminjail` SET `status` = "released", `time_left` = 0, `released_by` = @released_by, `released_at` = CURRENT_TIMESTAMP WHERE `identifier` = @identifier AND `status` = "active" ORDER BY `id` DESC LIMIT 1', params)
    end
end

local function saveJailProgress(data, sync)
    if not data or not data.identifier then return false end

    applyTimeProgress(data)

    local params = {
        ['@id'] = data.id or 0,
        ['@identifier'] = data.identifier,
        ['@time_left'] = math.max(0, math.floor(data.timeLeft or 0)),
        ['@release_at'] = data.releaseAt or nil,
        ['@name'] = data.name or 'Unbekannt'
    }

    local queryById = 'UPDATE `mb_adminjail` SET `time_left` = @time_left, `release_at` = @release_at, `name` = @name WHERE `id` = @id AND `status` = "active" LIMIT 1'
    local queryByIdentifier = 'UPDATE `mb_adminjail` SET `time_left` = @time_left, `release_at` = @release_at, `name` = @name WHERE `identifier` = @identifier AND `status` = "active" ORDER BY `id` DESC LIMIT 1'
    local query = (data.id and data.id > 0) and queryById or queryByIdentifier

    if sync and isOxmysql() and MySQL and MySQL.update and MySQL.update.await then
        local ok, err = pcall(function()
            MySQL.update.await(query, params)
        end)

        if not ok then
            print(('^1[MB_Adminjail] Sync-Speichern fehlgeschlagen (%s): %s^0'):format(data.identifier, tostring(err)))
            return false
        end

        return true
    end

    dbExecute(query, params)
    return true
end

local function saveTimeLeft(data)
    saveJailProgress(data, false)
end

local function sendPlayersToAdmin(src)
    if not hasPermission(src) then return end

    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        -- Wichtig: Identifier/Char-ID werden bewusst NICHT an die NUI gesendet.
        -- Im Tablet wird nur mit Server-ID + Name gearbeitet.
        players[#players + 1] = {
            source = target,
            name = getDisplayName(target),
            serverName = GetPlayerName(target) or getDisplayName(target)
        }
    end

    table.sort(players, function(a, b) return a.source < b.source end)
    TriggerClientEvent('mb_adminjail:client:setPlayers', src, players)
end

local function publicJailRows(rows)
    local publicRows = {}

    for _, row in ipairs(rows or {}) do
        local onlineSrc = findOnlineSourceByIdentifier(row.identifier)

        publicRows[#publicRows + 1] = {
            id = tonumber(row.id) or 0,
            name = row.name or 'Unbekannt',
            reason = row.reason or 'Kein Grund',
            time_left = tonumber(row.time_left) or 0,
            jailed_by = row.jailed_by or 'Unbekannt',
            jailed_at = row.jailed_at or '',
            released_by = row.released_by,
            released_at = row.released_at,
            status = row.status or 'active',
            online = onlineSrc ~= nil,
            source = onlineSrc
        }
    end

    return publicRows
end

local function sendActiveJailsToAdmin(src)
    if not hasPermission(src) then return end

    dbQuery('SELECT * FROM `mb_adminjail` WHERE `status` = "active" ORDER BY `id` DESC LIMIT 100', {}, function(rows)
        TriggerClientEvent('mb_adminjail:client:setActiveJails', src, publicJailRows(rows))
    end)
end

local function sendLogsToAdmin(src)
    if not hasPermission(src) then return end

    dbQuery('SELECT * FROM `mb_adminjail` ORDER BY `id` DESC LIMIT 50', {}, function(rows)
        TriggerClientEvent('mb_adminjail:client:setLogs', src, publicJailRows(rows))
    end)
end

local function refreshAdminTablet(src)
    if not src or tonumber(src) == 0 or not hasPermission(src) then return end
    sendPlayersToAdmin(src)
    sendActiveJailsToAdmin(src)
end

local function finishJail(identifier, targetSrc, releasedByName, releasedByIdentifier, automatic, rowId, cachedData)
    if not identifier then return end

    local data = cachedData or (targetSrc and jailedPlayers[targetSrc]) or nil
    local playerName = data and data.name or (targetSrc and getDisplayName(targetSrc)) or 'Offline Spieler'
    local reason = data and data.reason or 'Manuell entlassen'
    local originalMinutes = data and math.ceil((data.originalTime or data.timeLeft or 0) / 60) or 0

    if targetSrc and GetPlayerPing(targetSrc) > 0 then
        jailedPlayers[targetSrc] = nil
        TriggerClientEvent('mb_adminjail:client:endJail', targetSrc, {
            releaseCoords = coordsToTable(Config.ReleaseCoords)
        })
        notify(targetSrc, 'Du wurdest aus dem AdminJail entlassen.', 'success')
    end

    completeJailRecord(identifier, rowId or (data and data.id), releasedByName)

    webhook('unjail', {
        adminName = releasedByName,
        adminIdentifier = releasedByIdentifier,
        playerName = playerName,
        playerIdentifier = identifier,
        playerSource = targetSrc,
        reason = reason,
        minutes = originalMinutes,
        automatic = automatic
    })
end

local function isValidJailReason(reason)
    reason = trim(reason)
    if reason == '' then return false, 'Du musst einen Grund angeben.' end

    local minLength = math.max(1, tonumber(Config.MinJailReasonLength) or 5)
    if #reason < minLength then
        return false, ('Der Grund muss mindestens %s Zeichen haben.'):format(minLength)
    end

    local lowered = reason:lower()
    for _, blocked in ipairs(Config.BlockedJailReasons or {}) do
        if lowered == tostring(blocked):lower() then
            return false, 'Bitte gib einen echten Grund an (kein Test-Text).'
        end
    end

    return true
end

local function jailPlayer(target, adminSrc, minutes, reason)
    target = tonumber(target)
    adminSrc = tonumber(adminSrc) or 0
    minutes = tonumber(minutes)
    reason = trim(reason)

    if not target or not GetPlayerName(target) then
        notify(adminSrc, 'Ungültige Spieler-ID.', 'error')
        return
    end

    if not minutes or minutes <= 0 then
        notify(adminSrc, 'Ungültige Jail-Zeit.', 'error')
        return
    end

    minutes = math.floor(minutes)

    if minutes > Config.MaxJailTime then
        notify(adminSrc, ('Maximale Jail-Zeit: %s Minuten.'):format(Config.MaxJailTime), 'error')
        return
    end

    local reasonOk, reasonError = isValidJailReason(reason)
    if not reasonOk then
        notify(adminSrc, reasonError, 'error')
        return
    end

    local identifier = getIdentifier(target)
    if not identifier then
        notify(adminSrc, 'Spielerdaten konnten nicht gelesen werden.', 'error')
        return
    end

    local seconds = minutes * 60
    local releaseAt = os.time() + seconds
    local playerName = getDisplayName(target)
    local adminName = adminSrc == 0 and 'Console' or getDisplayName(adminSrc)
    local adminFiveMName = getFiveMName(adminSrc)
    local adminIdentifier = adminSrc == 0 and 'console' or getIdentifier(adminSrc)

    dbExecute('UPDATE `mb_adminjail` SET `status` = "replaced", `released_by` = @released_by, `released_at` = CURRENT_TIMESTAMP WHERE `identifier` = @identifier AND `status` = "active"', {
        ['@identifier'] = identifier,
        ['@released_by'] = adminName
    }, function()
        dbInsert('INSERT INTO `mb_adminjail` (`identifier`, `name`, `reason`, `time_left`, `jailed_by`, `jailed_by_identifier`, `release_at`, `status`) VALUES (@identifier, @name, @reason, @time_left, @jailed_by, @jailed_by_identifier, @release_at, "active")', {
            ['@identifier'] = identifier,
            ['@name'] = playerName,
            ['@reason'] = reason,
            ['@time_left'] = seconds,
            ['@jailed_by'] = adminFiveMName,
            ['@jailed_by_identifier'] = adminIdentifier,
            ['@release_at'] = releaseAt
        }, function(insertId)
            jailedPlayers[target] = {
                id = tonumber(insertId) or 0,
                identifier = identifier,
                name = playerName,
                reason = reason,
                timeLeft = seconds,
                originalTime = seconds,
                releaseAt = releaseAt,
                lastUpdated = os.time(),
                jailedBy = adminFiveMName,
                jailedByIdentifier = adminIdentifier
            }

            TriggerClientEvent('mb_adminjail:client:startJail', target, {
                jailCoords = coordsToTable(Config.JailCoords),
                releaseCoords = coordsToTable(Config.ReleaseCoords),
                radius = Config.JailRadius,
                timeLeft = seconds,
                originalTime = seconds,
                reason = reason,
                jailedBy = adminFiveMName,
                removeWeapons = Config.RemoveWeapons,
                forceLeaveVehicle = Config.ForceLeaveVehicle,
                freezePlayer = Config.FreezePlayer,
                disableCombatControls = Config.DisableCombatControls
            })

            notify(target, ('Du wurdest eingesperrt. Restzeit: %s Minuten'):format(minutes), 'error')
            notify(adminSrc, ('Spieler %s wurde erfolgreich eingesperrt.'):format(playerName), 'success')

            webhook('jail', {
                adminName = adminName,
                adminIdentifier = adminIdentifier,
                playerName = playerName,
                playerIdentifier = identifier,
                playerSource = target,
                reason = reason,
                minutes = minutes
            })

            if adminSrc ~= 0 then refreshAdminTablet(adminSrc) end
        end)
    end)
end

checkJailOnJoin = function(src, attempt)
    attempt = tonumber(attempt) or 1
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end
    if jailedPlayers[src] then return end

    local identifier = getIdentifier(src)
    if not identifier then
        local maxAttempts = math.max(1, tonumber(Config.RejoinCheckRetries) or 8)
        if attempt < maxAttempts then
            SetTimeout(2000, function()
                checkJailOnJoin(src, attempt + 1)
            end)
        end
        return
    end

    dbQuery('SELECT * FROM `mb_adminjail` WHERE `identifier` = @identifier AND `status` = "active" ORDER BY `id` DESC LIMIT 1', {
        ['@identifier'] = identifier
    }, function(rows)
        local row = rows and rows[1]
        if not row or not GetPlayerName(src) then return end
        if jailedPlayers[src] then return end

        local timeLeft = tonumber(row.time_left) or 0
        local releaseAt = tonumber(row.release_at) or (os.time() + timeLeft)

        if Config.TimerMode == "realtime" then
            timeLeft = math.max(0, releaseAt - os.time())
        end

        if timeLeft <= 0 then
            completeJailRecord(identifier, tonumber(row.id), 'SYSTEM')
            return
        end

        jailedPlayers[src] = {
            id = tonumber(row.id) or 0,
            identifier = identifier,
            name = getDisplayName(src),
            reason = row.reason or 'Kein Grund gespeichert',
            timeLeft = timeLeft,
            originalTime = timeLeft,
            releaseAt = releaseAt,
            lastUpdated = os.time(),
            jailedBy = row.jailed_by or 'Unbekannt',
            jailedByIdentifier = row.jailed_by_identifier or 'Unbekannt'
        }

        TriggerClientEvent('mb_adminjail:client:startJail', src, {
            jailCoords = coordsToTable(Config.JailCoords),
            releaseCoords = coordsToTable(Config.ReleaseCoords),
            radius = Config.JailRadius,
            timeLeft = timeLeft,
            originalTime = timeLeft,
            reason = row.reason,
            jailedBy = row.jailed_by or 'Unbekannt',
            removeWeapons = Config.RemoveWeapons,
            forceLeaveVehicle = Config.ForceLeaveVehicle,
            freezePlayer = Config.FreezePlayer,
            disableCombatControls = Config.DisableCombatControls
        })

        notify(src, ('Du bist noch im AdminJail. Restzeit: %s Minuten (%s)'):format(minutesLeftLabel(timeLeft), secondsToClock(timeLeft)), 'error')
    end)
end

local function restoreOnlineJails()
    for _, playerId in ipairs(GetPlayers()) do
        checkJailOnJoin(tonumber(playerId))
    end
end

local function scheduleJailCheck(src)
    src = tonumber(src)
    if not src then return end

    SetTimeout((Config.RejoinCheckDelay or 5) * 1000, function()
        checkJailOnJoin(src)
    end)
end

local function unjailByRecord(rowId, adminSrc)
    rowId = tonumber(rowId)
    adminSrc = tonumber(adminSrc) or 0

    if not rowId then
        notify(adminSrc, 'Ungültiger Jail-Eintrag.', 'error')
        return
    end

    dbQuery('SELECT * FROM `mb_adminjail` WHERE `id` = @id AND `status` = "active" LIMIT 1', {
        ['@id'] = rowId
    }, function(rows)
        local row = rows and rows[1]
        if not row then
            notify(adminSrc, 'Dieser Jail-Eintrag ist nicht mehr aktiv.', 'error')
            refreshAdminTablet(adminSrc)
            return
        end

        local adminName = adminSrc == 0 and 'Console' or getDisplayName(adminSrc)
        local adminIdentifier = adminSrc == 0 and 'console' or getIdentifier(adminSrc)
        local targetSrc = findOnlineSourceByIdentifier(row.identifier)

        if targetSrc then
            finishJail(row.identifier, targetSrc, adminName, adminIdentifier, false, rowId, jailedPlayers[targetSrc])
        else
            completeJailRecord(row.identifier, rowId, adminName)
            webhook('unjail', {
                adminName = adminName,
                adminIdentifier = adminIdentifier,
                playerName = row.name,
                playerIdentifier = row.identifier,
                playerSource = targetSrc,
                reason = row.reason,
                minutes = math.ceil((tonumber(row.time_left) or 0) / 60),
                automatic = false
            })
        end

        notify(adminSrc, ('Spieler %s wurde aus dem AdminJail entlassen.'):format(row.name or 'Unbekannt'), 'success')
        refreshAdminTablet(adminSrc)
    end)
end


CreateThread(function()
    Wait(1000)
    initFramework()

    if not waitForDatabase() then
        print('^1[MB_Adminjail] Keine MySQL-Verbindung. Starte oxmysql vor MB_Adminjail.^0')
        return
    end

    initDatabase(function()
        print(('^2[MB_Adminjail] MB_Adminjail Loaded. Framework=%s, TimerMode=%s^0'):format(Config.Framework, Config.TimerMode))
        restoreOnlineJails()
    end)
end)

CreateThread(function()
    -- Runtime-Timer läuft jede Sekunde, damit Spieler exakt automatisch entlassen werden.
    -- Datenbank-Save bleibt gedrosselt über Config.TickSeconds, damit MySQL nicht gespammt wird.
    local saveInterval = math.max(10, tonumber(Config.TickSeconds) or 60)
    local lastSave = os.time()

    while true do
        Wait(1000)

        local now = os.time()
        local shouldSave = (now - lastSave) >= saveInterval
        if shouldSave then lastSave = now end

        for src, data in pairs(jailedPlayers) do
            if GetPlayerPing(src) > 0 then
                applyTimeProgress(data)

                if data.timeLeft <= 0 then
                    finishJail(data.identifier, src, 'SYSTEM', 'system', true, data.id, data)
                else
                    if shouldSave then
                        data.name = getDisplayName(src)
                        saveJailProgress(data, false)
                    end
                    TriggerClientEvent('mb_adminjail:client:updateTime', src, data.timeLeft)
                end
            end
        end
    end
end)

RegisterNetEvent('mb_adminjail:server:clientTimeExpired', function()
    local src = source
    local data = jailedPlayers[src]
    if not data then return end

    applyTimeProgress(data)

    -- Server entscheidet final. Kleine Toleranz verhindert, dass der Spieler bei 0 noch warten muss.
    if (tonumber(data.timeLeft) or 0) <= 1 then
        finishJail(data.identifier, src, 'SYSTEM', 'system', true, data.id, data)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local data = jailedPlayers[src]

    if data then
        if GetPlayerName(src) then
            data.name = getDisplayName(src)
        end

        saveJailProgress(data, true)
        jailedPlayers[src] = nil
    end
end)

RegisterNetEvent('mb_adminjail:server:playerReady', function()
    scheduleJailCheck(source)
end)

if Config.Framework == 'ESX' then
    AddEventHandler('esx:playerLoaded', function(playerId)
        scheduleJailCheck(playerId)
    end)
elseif Config.Framework == 'QBCore' then
    RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
        scheduleJailCheck(source)
    end)
end

RegisterNetEvent('mb_adminjail:server:requestPlayers', function()
    local src = source
    sendPlayersToAdmin(src)
end)

RegisterNetEvent('mb_adminjail:server:requestActiveJails', function()
    local src = source
    sendActiveJailsToAdmin(src)
end)

RegisterNetEvent('mb_adminjail:server:requestLogs', function()
    local src = source
    sendLogsToAdmin(src)
end)

RegisterNetEvent('mb_adminjail:server:jailPlayer', function(target, minutes, reason)
    local src = source
    if not hasPermission(src) then
        notify(src, 'Dazu hast du keine Berechtigung.', 'error')
        return
    end

    jailPlayer(target, src, minutes, reason)
end)

RegisterNetEvent('mb_adminjail:server:unjailPlayer', function(rowId)
    local src = source
    if not hasPermission(src) then
        notify(src, 'Dazu hast du keine Berechtigung.', 'error')
        return
    end

    unjailByRecord(rowId, src)
end)

RegisterCommand(Config.OpenTabletCommand, function(source)
    if not hasPermission(source) then
        notify(source, 'Dazu hast du keine Berechtigung.', 'error')
        return
    end

    if source == 0 then
        print('[MB_Adminjail] Tablet kann nur ingame geöffnet werden.')
        return
    end

    TriggerClientEvent('mb_adminjail:client:openTablet', source)
    refreshAdminTablet(source)
end, false)

RegisterCommand(Config.QuickJailCommand, function(source, args)
    if not hasPermission(source) then
        notify(source, 'Dazu hast du keine Berechtigung.', 'error')
        return
    end

    local target = tonumber(args[1])
    local minutes = tonumber(args[2])
    local reason = trim(table.concat(args, ' ', 3))

    if not target or not minutes or reason == '' then
        notify(source, ('Nutzung: /%s [id] [zeit] [grund]'):format(Config.QuickJailCommand), 'error')
        return
    end

    jailPlayer(target, source, minutes, reason)
end, false)

RegisterCommand(Config.UnjailCommand, function(source, args)
    if not hasPermission(source) then
        notify(source, 'Dazu hast du keine Berechtigung.', 'error')
        return
    end

    local target = tonumber(args[1])
    if not target or not GetPlayerName(target) then
        notify(source, ('Nutzung: /%s [id]'):format(Config.UnjailCommand), 'error')
        return
    end

    local identifier = getIdentifier(target)
    local data = jailedPlayers[target]
    if not data then
        notify(source, 'Dieser Spieler ist aktuell nicht im AdminJail.', 'error')
        return
    end

    local adminName = source == 0 and 'Console' or getDisplayName(source)
    local adminIdentifier = source == 0 and 'console' or getIdentifier(source)
    finishJail(identifier, target, adminName, adminIdentifier, false, data.id, data)
    notify(source, ('Spieler %s wurde aus dem AdminJail entlassen.'):format(getDisplayName(target)), 'success')
end, false)


AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    CreateThread(function()
        Wait(1500)
        if not waitForDatabase() then return end
        initDatabase(function()
            restoreOnlineJails()
        end)
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for src, data in pairs(jailedPlayers) do
        if GetPlayerName(src) then
            data.name = getDisplayName(src)
        end
        saveJailProgress(data, true)
    end
end)

-- Useful ACE example:
-- add_ace group.admin adminjail.use allow
