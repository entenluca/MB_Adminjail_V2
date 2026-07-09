local ESX, QBCore = nil, nil
local tabletOpen = false
local isJailed = false
local jailData = nil
local expirationNotified = false
local lastJailCheckAt = 0

local function initFramework()
    if Config.Framework == "ESX" then
        CreateThread(function()
            while ESX == nil do
                if exports['es_extended'] and exports['es_extended'].getSharedObject then
                    ESX = exports['es_extended']:getSharedObject()
                else
                    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
                end
                Wait(500)
            end
        end)
    elseif Config.Framework == "QBCore" then
        CreateThread(function()
            while QBCore == nil do
                if exports['qb-core'] and exports['qb-core'].GetCoreObject then
                    QBCore = exports['qb-core']:GetCoreObject()
                end
                Wait(500)
            end
        end)
    end
end

local function notify(message, notifyType)
    notifyType = notifyType or 'inform'

    if Config.Notify == 'ox' then
        local oxType = notifyType
        if oxType == 'info' then oxType = 'inform' end

        if lib and lib.notify then
            lib.notify({ title = 'AdminJail', description = message, type = oxType })
            return
        end

        if GetResourceState('ox_lib') == 'started' then
            exports.ox_lib:notify({ title = 'AdminJail', description = message, type = oxType })
            return
        end
    end

    if Config.Notify == 'okok' and GetResourceState('okokNotify') == 'started' then
        exports['okokNotify']:Alert('AdminJail', message, 5000, notifyType)
        return
    end

    if Config.Notify == 'mythic' and GetResourceState('mythic_notify') == 'started' then
        exports['mythic_notify']:DoHudText(notifyType, message)
        return
    end

    if Config.Notify == 'framework' then
        if Config.Framework == 'ESX' and ESX and ESX.ShowNotification then
            ESX.ShowNotification(message)
            return
        elseif Config.Framework == 'QBCore' and QBCore and QBCore.Functions and QBCore.Functions.Notify then
            QBCore.Functions.Notify(message, notifyType)
            return
        end
    end

    if Config.Notify == 'chat' then
        TriggerEvent('chat:addMessage', {
            color = { 60, 130, 255 },
            multiline = true,
            args = { 'AdminJail', message }
        })
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function getUiConfig()
    local ui = Config.UI or {}

    return {
        brandTitle = ui.BrandTitle or 'AdminJail',
        brandSubtitle = ui.BrandSubtitle or '',
        sidebarTitle = ui.SidebarTitle or 'AdminJail',
        hudTitle = ui.HudTitle or 'AdminJail · Restzeit',
        hudTeamlerLabel = ui.HudTeamlerLabel or 'Teamler:',
        hudGrundLabel = ui.HudGrundLabel or 'Grund:',
        viewJailTitle = ui.ViewJailTitle or 'Einjailen',
        viewJailSub = ui.ViewJailSub or 'Spieler in das AdminJail versetzen',
        viewActiveTitle = ui.ViewActiveTitle or 'Aktive Jails',
        viewActiveSub = ui.ViewActiveSub or 'Laufende Strafen verwalten und entlassen',
        viewLogsTitle = ui.ViewLogsTitle or 'Verlauf',
        viewLogsSub = ui.ViewLogsSub or 'Abgeschlossene und aktive Einträge',
        navJail = ui.NavJail or 'Einjailen',
        navActive = ui.NavActive or 'Aktive Jails',
        navLogs = ui.NavLogs or 'Verlauf'
    }
end

local function sendUiConfig()
    SendNUIMessage({ action = 'setUiConfig', ui = getUiConfig() })
end

local function closeTablet()
    tabletOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })

    if isJailed and jailData then
        SetTimeout(150, showJailHud)
    end
end

local function openTablet()
    tabletOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'open',
        ui = getUiConfig(),
        keepHud = isJailed,
        timeLeft = isJailed and jailData and jailData.timeLeft or nil,
        originalTime = isJailed and jailData and jailData.originalTime or nil,
        jailedBy = isJailed and jailData and jailData.jailedBy or nil,
        reason = isJailed and jailData and jailData.reason or nil
    })
    TriggerServerEvent('mb_adminjail:server:requestPlayers')
    TriggerServerEvent('mb_adminjail:server:requestActiveJails')
end

local function teleportToCoords(coords)
    if not coords then return end

    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    Wait(250)
    SetEntityCoordsNoOffset(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    Wait(250)
    DoScreenFadeIn(250)
end

local function secondsToClock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local rest = seconds % 60

    if hours > 0 then
        return ('%02d:%02d:%02d'):format(hours, minutes, rest)
    end

    return ('%02d:%02d'):format(minutes, rest)
end

local function updateJailHud()
    if Config.ShowJailTimerHud == false or not jailData then return end

    SendNUIMessage({
        action = 'updateJailHud',
        timeLeft = tonumber(jailData.timeLeft) or 0,
        originalTime = tonumber(jailData.originalTime) or tonumber(jailData.timeLeft) or 1,
        reason = jailData.reason or 'Kein Grund',
        jailedBy = jailData.jailedBy or 'Unbekannt'
    })
end

local function showJailHud()
    if Config.ShowJailTimerHud == false or not jailData then return end

    SendNUIMessage({
        action = 'enterJailHud',
        ui = getUiConfig(),
        timeLeft = tonumber(jailData.timeLeft) or 0,
        originalTime = tonumber(jailData.originalTime) or tonumber(jailData.timeLeft) or 1,
        reason = jailData.reason or 'Kein Grund',
        jailedBy = jailData.jailedBy or 'Unbekannt'
    })
end

local function hideJailHud()
    SendNUIMessage({ action = 'exitJailHud' })
end

local function ensureJailHudVisible()
    if not isJailed or not jailData or Config.ShowJailTimerHud == false then return end
    showJailHud()
end

local function startJail(data)
    tabletOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    jailData = data or {}
    jailData.timeLeft = tonumber(jailData.timeLeft) or 0
    jailData.originalTime = tonumber(jailData.originalTime) or jailData.timeLeft
    jailData.radius = tonumber(jailData.radius) or Config.JailRadius
    jailData.jailCoords = jailData.jailCoords or { x = Config.JailCoords.x, y = Config.JailCoords.y, z = Config.JailCoords.z, w = Config.JailCoords.w }
    isJailed = true
    expirationNotified = false

    CreateThread(function()
        for _ = 1, 12 do
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            Wait(50)
        end
    end)

    local ped = PlayerPedId()

    if jailData.forceLeaveVehicle and IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
        Wait(900)
    end

    if jailData.removeWeapons then
        RemoveAllPedWeapons(ped, true)
    end

    FreezeEntityPosition(ped, jailData.freezePlayer == true)
    teleportToCoords(jailData.jailCoords)
    showJailHud()

    CreateThread(function()
        for attempt = 1, 6 do
            Wait(1000)
            if not isJailed or not jailData then break end
            ensureJailHudVisible()
        end
    end)
end

local function endJail(data)
    local ped = PlayerPedId()
    isJailed = false
    jailData = nil
    expirationNotified = false
    tabletOpen = false
    hideJailHud()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    FreezeEntityPosition(ped, false)

    if data and data.releaseCoords then
        teleportToCoords(data.releaseCoords)
    end
end

initFramework()

CreateThread(function()
    Wait(1500)
    sendUiConfig()
end)

RegisterNetEvent('mb_adminjail:client:notify', function(message, notifyType)
    notify(message, notifyType)
end)

RegisterNetEvent('mb_adminjail:client:openTablet', function()
    openTablet()
end)

RegisterNetEvent('mb_adminjail:client:setPlayers', function(players)
    SendNUIMessage({ action = 'setPlayers', players = players or {} })
end)

RegisterNetEvent('mb_adminjail:client:setActiveJails', function(activeJails)
    SendNUIMessage({ action = 'setActiveJails', activeJails = activeJails or {} })
end)

RegisterNetEvent('mb_adminjail:client:setLogs', function(logs)
    SendNUIMessage({ action = 'setLogs', logs = logs or {} })
end)

RegisterNetEvent('mb_adminjail:client:startJail', function(data)
    startJail(data)
end)

RegisterNetEvent('mb_adminjail:client:updateTime', function(seconds)
    if jailData then
        jailData.timeLeft = tonumber(seconds) or jailData.timeLeft
        updateJailHud()
    end
end)

RegisterNetEvent('mb_adminjail:client:endJail', function(data)
    endJail(data)
end)

RegisterNUICallback('close', function(_, cb)
    closeTablet()
    cb({ ok = true })
end)

RegisterNUICallback('getPlayers', function(_, cb)
    TriggerServerEvent('mb_adminjail:server:requestPlayers')
    cb({ ok = true })
end)

RegisterNUICallback('getActiveJails', function(_, cb)
    TriggerServerEvent('mb_adminjail:server:requestActiveJails')
    cb({ ok = true })
end)

RegisterNUICallback('getLogs', function(_, cb)
    TriggerServerEvent('mb_adminjail:server:requestLogs')
    cb({ ok = true })
end)

RegisterNUICallback('jailPlayer', function(data, cb)
    local playerId = tonumber(data.playerId)
    local minutes = tonumber(data.minutes)
    local reason = tostring(data.reason or '')

    TriggerServerEvent('mb_adminjail:server:jailPlayer', playerId, minutes, reason)
    cb({ ok = true })
end)

RegisterNUICallback('unjailPlayer', function(data, cb)
    TriggerServerEvent('mb_adminjail:server:unjailPlayer', tonumber(data.rowId))
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        if isJailed then
            Wait(1000)

            -- jailData kann durch Entlassung/Rejoin während Wait() nil werden.
            -- Deshalb nach jedem Wait() lokal und sicher neu prüfen.
            local data = jailData
            if data then
                data.timeLeft = math.max(0, (tonumber(data.timeLeft) or 0) - 1)
                updateJailHud()

                if data.timeLeft <= 0 and not expirationNotified then
                    expirationNotified = true
                    TriggerServerEvent('mb_adminjail:server:clientTimeExpired')
                end

                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local jailCoords = data.jailCoords or {
                    x = Config.JailCoords.x,
                    y = Config.JailCoords.y,
                    z = Config.JailCoords.z,
                    w = Config.JailCoords.w
                }

                local center = vector3(jailCoords.x, jailCoords.y, jailCoords.z)
                local distance = #(coords - center)

                if data.forceLeaveVehicle and IsPedInAnyVehicle(ped, false) then
                    TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
                end

                if data.removeWeapons then
                    RemoveAllPedWeapons(ped, true)
                end

                if data.freezePlayer then
                    FreezeEntityPosition(ped, true)
                end

                if distance > (data.radius or Config.JailRadius) then
                    SetEntityCoordsNoOffset(ped, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false)
                    SetEntityHeading(ped, jailCoords.w or 0.0)
                    notify('Du darfst den AdminJail-Bereich nicht verlassen.', 'error')
                end
            end
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        if isJailed then
            Wait(0)

            local data = jailData
            if data and data.disableCombatControls then
                DisableControlAction(0, 24, true)  -- Attack
                DisableControlAction(0, 25, true)  -- Aim
                DisableControlAction(0, 37, true)  -- Weapon wheel
                DisableControlAction(0, 47, true)  -- Detonate
                DisableControlAction(0, 58, true)  -- Throw grenade
                DisableControlAction(0, 140, true) -- Melee
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisablePlayerFiring(PlayerId(), true)
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if isJailed and jailData and Config.ShowJailTimerHud then
            ensureJailHudVisible()
            Wait(15000)
        else
            Wait(3000)
        end
    end
end)

local function requestJailCheck(force)
    local now = GetGameTimer()
    if not force and now - lastJailCheckAt < 1500 then return end
    lastJailCheckAt = now
    TriggerServerEvent('mb_adminjail:server:playerReady')
end

AddEventHandler('playerSpawned', function()
    requestJailCheck(true)
    SetTimeout(1500, function() requestJailCheck(true) end)
end)

CreateThread(function()
    Wait(2000)
    requestJailCheck(true)
end)

if Config.Framework == 'ESX' then
    RegisterNetEvent('esx:playerLoaded', function()
        requestJailCheck(true)
        SetTimeout(1500, function() requestJailCheck(true) end)
    end)
elseif Config.Framework == 'QBCore' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        requestJailCheck(true)
        SetTimeout(1500, function() requestJailCheck(true) end)
    end)
end
CreateThread(function()
    while true do
        if tabletOpen and IsControlJustReleased(0, 322) then
            closeTablet()
        end
        Wait(0)
    end
end)
