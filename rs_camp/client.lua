local campsEntities = {}
local dynamicDoors = {}
local campsData = {}
local doorStates = {}
local renderDistance = Config.RenderDistace
local closestDoorEntity, closestDoorId = nil, nil
local closestCampEntity, closestCampId = nil, nil
local closestChestEntity, closestChestId = nil, nil
local targetEnabled = false

local campPromptGroup = UipromptGroup:new(Config.Promp.Controls)
local campPickUpPrompt = Uiprompt:new(Config.Promp.Key.Pickut, Config.Promp.Collect, campPromptGroup)
campPickUpPrompt:setHoldMode(true)

local chestPromptGroup = UipromptGroup:new(Config.Promp.Chest)
local chestPrompt = Uiprompt:new(Config.Promp.Key.Chest, Config.Promp.Chestopen, chestPromptGroup)
chestPrompt:setStandardMode(true)

local doorPromptGroup = UipromptGroup:new(Config.Promp.Door)
local doorPrompt = Uiprompt:new(Config.Promp.Key.Door, Config.Promp.Dooropen, doorPromptGroup)
doorPrompt:setStandardMode(true)

local function RotationToDirection(rot)
    local radX = math.rad(rot.x)
    local radZ = math.rad(rot.z)
    local cosX = math.cos(radX)
    return vector3(-math.sin(radZ) * cosX, math.cos(radZ) * cosX, math.sin(radX))
end

local function RaycastFromCamera(distance)
    local playerPed = PlayerPedId()
    local coords = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local forwardVector = RotationToDirection(rotation)
    local dest = coords + (forwardVector * distance)

    local rayHandle = StartShapeTestRay(coords.x, coords.y, coords.z, dest.x, dest.y, dest.z, 1572865 + 16 + 32, playerPed, 0)
    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 and DoesEntityExist(entityHit) then
        return entityHit
    end
    return nil
end

local function hideCampPrompt()
    campPromptGroup:setActive(false)
    campPickUpPrompt:setVisible(false)
    campPickUpPrompt:setEnabled(false)
    closestCampEntity, closestCampId = nil, nil
end

local function DrawCrosshair(isTarget)
    local dict = "blips"
    local name = "blip_ambient_eyewitness"

    if not HasStreamedTextureDictLoaded(dict) then
        RequestStreamedTextureDict(dict)
        while not HasStreamedTextureDictLoaded(dict) do
            Wait(0)
        end
    end

    local r, g, b = 255, 255, 255
    if isTarget then r, g, b = 0, 255, 0 end
    DrawSprite(dict, name, 0.5, 0.5, 0.02, 0.03, 0.0, r, g, b, 255)
end

local function isChestObject(model)
    for _, v in pairs(Config.Chests) do
        if GetHashKey(v.object) == model then
            return true
        end
    end
    return false
end

local AllVegetation = 1+2+4+8+16+32+64+128+256
local VMT_Cull = 1+2+4+8+16+32

local ActiveVegZones = {}

local function AddVegModifierSphere(x, y, z, radius)
    return Citizen.InvokeNative(0xFA50F79257745E74, x, y, z, radius, VMT_Cull, AllVegetation, 0)
end

local function RemoveVegModifierSphere(sphere, p1)
    return Citizen.InvokeNative(0x9CF1836C03FB67A2, Citizen.PointerValueIntInitialized(sphere), p1)
end

RegisterNetEvent('rs_camp:client:spawnCamps')
AddEventHandler('rs_camp:client:spawnCamps', function(data)
    campsData[data.id] = data
end)

CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local activeCamps = {}

        for id, data in pairs(campsData) do
            local pos = vector3(data.x, data.y, data.z)
            local dist = #(playerCoords - pos)

            if dist < renderDistance and not campsEntities[id] then
                local modelHash = GetHashKey(data.item.model)
                local isDynamic = false
                local modelName = data.item.model
                for _, door in pairs(Config.Doors or {}) do
                    if door.modelDoor == modelName then
                        isDynamic = true
                        dynamicDoors[id] = GetHashKey(modelName)
                        break
                    end
                end
                local object = CreateObjectNoOffset(modelHash, data.x, data.y, data.z, false, false, isDynamic)

                SetEntityRotation(object,
                    tonumber(data.rotation.x or 0.0) % 360.0,
                    tonumber(data.rotation.y or 0.0) % 360.0,
                    tonumber(data.rotation.z or 0.0) % 360.0
                )
                FreezeEntityPosition(object, true)
                SetEntityAsMissionEntity(object, true)

                campsEntities[id] = object

                for _, item in pairs(Config.Items or {}) do
                    if item.model == data.item.model and item.veg then
                        ActiveVegZones[id] = AddVegModifierSphere(data.x, data.y, data.z, item.veg)
                        break
                    end
                end
            end

            local isDoor = false
            for _, door in pairs(Config.Doors or {}) do
                if door.modelDoor == data.item.model then
                    isDoor = true
                    break
                end
            end

            if dist > renderDistance and campsEntities[id] and not isDoor then
                DeleteEntity(campsEntities[id])
                campsEntities[id] = nil

                if ActiveVegZones[id] then
                    RemoveVegModifierSphere(ActiveVegZones[id], 0)
                    ActiveVegZones[id] = nil
                end
                dynamicDoors[id] = nil
            end

            if dist < renderDistance then
                activeCamps[id] = true
            end
        end

        for id, sphere in pairs(ActiveVegZones) do
            if not activeCamps[id] then
                RemoveVegModifierSphere(sphere, 0)
                ActiveVegZones[id] = nil
            end
        end

        Wait(1000)
    end
end)

RegisterNetEvent('rs_camp:client:removeCamp')
AddEventHandler('rs_camp:client:removeCamp', function(uniqueId)

    if ActiveVegZones[uniqueId] then
        RemoveVegModifierSphere(ActiveVegZones[uniqueId], 0)
        ActiveVegZones[uniqueId] = nil
    end

    local entity = campsEntities[uniqueId]
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end

    campsEntities[uniqueId] = nil
    campsData[uniqueId] = nil
    dynamicDoors[uniqueId] = nil
end)

Citizen.CreateThread(function()
    TriggerServerEvent('rs_camp:server:requestCamps')
end)

RegisterNetEvent('rs_camp:client:receiveCamps')
AddEventHandler('rs_camp:client:receiveCamps', function(camps)
    if camps then
        for _, data in pairs(camps) do
            TriggerEvent('rs_camp:client:spawnCamps', data)
        end
    end
end)

RegisterCommand(Config.Commands.Camp, function()
    targetEnabled = not targetEnabled

    if targetEnabled then
        TriggerEvent('rs_camp:ShowAdvancedRightNotification', Config.Text.Targeton, "generic_textures", "tick", "COLOR_GREEN", 4000)
        SendNUIMessage({
            action = "showtarget",
            text = Config.Text.TargetActiveText .. Config.Commands.Camp .. Config.Text.TargetActiveText1
        })
    else
        TriggerEvent('rs_camp:ShowAdvancedRightNotification', Config.Text.Targetoff, "menu_textures", "cross", "COLOR_RED", 2500)
        hideCampPrompt()
        SendNUIMessage({ action = "hidetarget" })
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if targetEnabled then
            local entityHit = RaycastFromCamera(10.0)
            local found = false
            closestCampEntity, closestCampId = nil, nil

            if entityHit then
                for uniqueId, entity in pairs(campsEntities) do
                    if entityHit == entity then
                        closestCampEntity = entity
                        closestCampId = uniqueId
                        found = true
                        break
                    end
                end
            end

            DrawCrosshair(found)

            if found then
                campPromptGroup:setActive(true)
                campPickUpPrompt:setVisible(true)
                campPickUpPrompt:setEnabled(true)
            else
                hideCampPrompt()
            end
        else
            hideCampPrompt()
        end
    end
end)

local function updateChestPrompts()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    closestChestEntity, closestChestId = nil, nil
    local closestDistance = 2.0

    for uniqueId, entity in pairs(campsEntities or {}) do
        if DoesEntityExist(entity) and isChestObject(GetEntityModel(entity)) then
            local entCoords = GetEntityCoords(entity)
            local distance = #(playerCoords - entCoords)
            if distance <= closestDistance then
                closestDistance = distance
                closestChestEntity = entity
                closestChestId = uniqueId
            end
        end
    end

    local foundChest = (closestChestEntity ~= nil)

    chestPromptGroup:setActive(foundChest)

    if foundChest and closestChestId then
        chestPrompt:setText(Config.Promp.Chestopen .. " ID - " .. tostring(closestChestId) .. " ")
    end

    chestPrompt:setVisible(foundChest)
    chestPrompt:setEnabled(foundChest)
end

local function updateDoorPrompts()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    closestDoorEntity, closestDoorId = nil, nil
    local closestDistance = 2.0

    for uniqueId, entity in pairs(campsEntities or {}) do
        if DoesEntityExist(entity) and dynamicDoors[uniqueId] then
            local entCoords = GetEntityCoords(entity)
            local distance = #(playerCoords - entCoords)
            if distance <= closestDistance then
                closestDistance = distance
                closestDoorEntity = entity
                closestDoorId = uniqueId
            end
        end
    end

    local foundDoor = (closestDoorEntity ~= nil)
    doorPromptGroup:setActive(foundDoor)

    if foundDoor and closestDoorId then
        doorPrompt:setText(Config.Promp.Dooropen .. " ID - " .. tostring(closestDoorId))
    end

    doorPrompt:setVisible(foundDoor)
    doorPrompt:setEnabled(foundDoor)
end

CreateThread(function()
    while true do
        Wait(500)
        updateDoorPrompts()
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        updateChestPrompts()
    end
end)

campPromptGroup:setOnHoldModeJustCompleted(function(group, prompt)
    if closestCampEntity and DoesEntityExist(closestCampEntity) then
        if prompt == campPickUpPrompt and closestCampId then
            TriggerServerEvent('rs_camp:server:pickUpByOwner', closestCampId)
            hideCampPrompt()
        end
    end
end)

chestPromptGroup:setOnStandardModeJustCompleted(function(group, prompt)
    if closestChestEntity and DoesEntityExist(closestChestEntity) then
        if prompt == chestPrompt and closestChestId then
            TriggerServerEvent('rs_camp:server:openChest', closestChestId)
        end
    end
end)

doorPromptGroup:setOnStandardModeJustCompleted(function(group, prompt)
    if closestDoorEntity and DoesEntityExist(closestDoorEntity) and closestDoorId then
        TriggerServerEvent('rs_camp:server:toggleDoor', closestDoorId)
    end
end)

UipromptManager:startEventThread()

RegisterNetEvent('rs_camp:client:toggleDoor')
AddEventHandler('rs_camp:client:toggleDoor', function(campId)
    local door = campsEntities[campId]
    if door and DoesEntityExist(door) then
        local rot = GetEntityRotation(door, 2)
        local open = doorStates[campId] or false

        if not open then
            SetEntityRotation(door, rot.x, rot.y, rot.z + 90.0, 2, true)
            doorStates[campId] = true
        else
            SetEntityRotation(door, rot.x, rot.y, rot.z - 90.0, 2, true)
            doorStates[campId] = false
        end
    end
end)

local function GetModelRadius(modelHash)
    local minDim, maxDim = GetModelDimensions(modelHash)
    if minDim and maxDim then
        local sizeX = math.abs(maxDim.x - minDim.x)
        local sizeY = math.abs(maxDim.y - minDim.y)
        local sizeZ = math.abs(maxDim.z - minDim.z)
        local maxSize = math.max(sizeX, sizeY, sizeZ)
        return maxSize * 1.0
    else
        return 5.0
    end
end

local placing = false
local tempObj = nil
local tempVegSphere = nil
local dynamicRadius = 0.0

local posX, posY, posZ = 0.0, 0.0, 0.0
local rotX, rotY, rotZ = 0.0, 0.0, 0.0

local actionQueue = nil
local actionSpeed = 0.05
local menuOpen = false
local lastItemName = nil

function drawtext(text, x, y, scaleX, scaleY, center, r, g, b, a)
    SetTextScale(scaleX, scaleY)
    SetTextColor(r, g, b, a)
    SetTextCentre(center)
    SetTextDropshadow(1, 0, 0, 0, 255)
    SetTextFontForCurrentCommand(1)
    DisplayText(CreateVarString(10, "LITERAL_STRING", text), x, y)
end

function SafeDeleteObject(entity)
    if entity and DoesEntityExist(entity) then
        FreezeEntityPosition(entity, false)
        SetEntityCollision(entity, true, true)
        SetEntityAlpha(entity, 255, false)
        Wait(0)
        DeleteObject(entity)
        DeleteEntity(entity)
    end
end

RegisterNUICallback("campAction", function(data, cb)
    actionQueue = data.action
    actionSpeed = tonumber(data.speed) or actionSpeed
    cb("ok")
end)

local function OpenCampMenu()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({
        show = true,
        txt = Config.NUI
    })
    menuOpen = true
end

local function CloseCampMenu()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ show = false })
    menuOpen = false
end

RegisterNetEvent('rs_camp:client:placePropCamp')
AddEventHandler('rs_camp:client:placePropCamp', function(itemName)

    if placing then return end
    if not Config.Items[itemName] then return end

    local modelName = Config.Items[itemName].model
    local modelHash = GetHashKey(modelName)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(0) end

    local ped = PlayerPedId()
    local ox, oy, oz = table.unpack(GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.5, 0.3))

    tempObj = CreateObject(modelHash, ox, oy, oz, true, true, true)

    posX, posY, posZ = ox, oy, oz
    rotX, rotY, rotZ = 0.0, 0.0, 0.0

    SetEntityCoords(tempObj, posX, posY, posZ, true, true, true, false)
    SetEntityRotation(tempObj, rotX, rotY, rotZ, 2, true)
    FreezeEntityPosition(tempObj, true)
    SetEntityCollision(tempObj, false, false)
    SetEntityAlpha(tempObj, 180, false)

    dynamicRadius = GetModelRadius(modelHash)
    tempVegSphere = AddVegModifierSphere(posX, posY, posZ, dynamicRadius)

    placing = true
    lastItemName = itemName

    OpenCampMenu()
end)

CreateThread(function()
    while true do
        Wait(0)

        if menuOpen then
            drawtext(Config.Text.Click, 0.50, 0.05, 0.35, 0.35, true, 0,255,0,255)

            if not IsControlPressed(0, 0x07CE1E61) then
                DisableControlAction(0, 0xA987235F, true)
                DisableControlAction(0, 0xD2047988, true)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)

        if placing and tempObj and menuOpen then

            DisableControlAction(0, 0xF84FA74F, true)
            DisableControlAction(0, 0x4AF4D473, true)

            if actionQueue ~= nil then
                local sp = actionSpeed

                if actionQueue == "forward" then posY = posY + sp end
                if actionQueue == "backward" then posY = posY - sp end
                if actionQueue == "left" then posX = posX - sp end
                if actionQueue == "right" then posX = posX + sp end
                if actionQueue == "up" then posZ = posZ + sp end
                if actionQueue == "down" then posZ = posZ - sp end

                if actionQueue == "rot_x_plus" then rotX = rotX + sp * 10 end
                if actionQueue == "rot_x_minus" then rotX = rotX - sp * 10 end

                if actionQueue == "rot_y_plus" then rotY = rotY + sp * 10 end
                if actionQueue == "rot_y_minus" then rotY = rotY - sp * 10 end

                if actionQueue == "rot_z_plus" then rotZ = rotZ + sp * 10 end
                if actionQueue == "rot_z_minus" then rotZ = rotZ - sp * 10 end

                if actionQueue == "confirm" then
                    placing = false
                    CloseCampMenu()

                    if tempVegSphere then
                        RemoveVegModifierSphere(tempVegSphere, 0)
                        tempVegSphere = nil
                    end

                    SafeDeleteObject(tempObj)
                    tempObj = nil

                    TriggerServerEvent('rs_camp:server:savecampOwner',
                        vector3(posX, posY, posZ),
                        vector3(rotX, rotY, rotZ),
                        lastItemName
                    )

                    TriggerServerEvent("rs_camp:removeItem", lastItemName)
                    TriggerEvent('rs_camp:ShowAdvancedRightNotification', Config.Text.Place, "generic_textures", "tick", "COLOR_GREEN", 4000)

                    lastItemName = nil
                    actionQueue = nil
                    goto continue
                end

                if actionQueue == "cancel" then
                    placing = false
                    CloseCampMenu()

                    if tempVegSphere then
                        RemoveVegModifierSphere(tempVegSphere, 0)
                        tempVegSphere = nil
                    end

                    SafeDeleteObject(tempObj)
                    tempObj = nil

                    TriggerEvent('rs_camp:ShowAdvancedRightNotification', Config.Text.Cancel, "menu_textures", "cross",  "COLOR_RED", 4000)

                    lastItemName = nil
                    actionQueue = nil
                    goto continue
                end

                actionQueue = nil
            end

            SetEntityCoords(tempObj, posX, posY, posZ, true, true, true, false)
            SetEntityRotation(tempObj, rotX, rotY, rotZ, 2, true)

            if tempVegSphere then
                RemoveVegModifierSphere(tempVegSphere, 0)
            end
            tempVegSphere = AddVegModifierSphere(posX, posY, posZ, dynamicRadius)
        end

        ::continue::
    end
end)

Citizen.CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.Shareperms, Config.Text.Shared, {
        { name = Config.Text.Corret, help = Config.Text.Corret },
        { name = Config.Text.Sharecorret, help = Config.Text.Playerpermi}
    })

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.Unshareperms, Config.Text.Remove, {
        { name = Config.Text.Corret, help = Config.Text.Corret }
    })
end)

function GetCurentTownName()
    local pedCoords = GetEntityCoords(PlayerPedId())
    local town_hash = Citizen.InvokeNative(0x43AD8FC02B429D33, pedCoords, 1)

    local townNames = {
        [GetHashKey("Annesburg")] = "Annesburg",
        [GetHashKey("Armadillo")] = "Armadillo",
        [GetHashKey("Blackwater")] = "Blackwater",
        [GetHashKey("Rhodes")] = "Rhodes",
        [GetHashKey("StDenis")] = "StDenis",
        [GetHashKey("Strawberry")] = "Strawberry",
        [GetHashKey("Tumbleweed")] = "Tumbleweed",
        [GetHashKey("Valentine")] = "Valentine"
    }

    return townNames[town_hash]
end

RegisterNetEvent('rs_camp:client:sendTownToServer', function(itemName)
    local town = GetCurentTownName()
    TriggerServerEvent('rs_camp:server:checkTownAndPlace', itemName, town)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for uniqueId, _ in pairs(campsEntities) do

        if ActiveVegZones[uniqueId] then
            RemoveVegModifierSphere(ActiveVegZones[uniqueId], 0)
            ActiveVegZones[uniqueId] = nil
        end

        local entity = campsEntities[uniqueId]
        if entity and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end

        campsEntities[uniqueId] = nil
        campsData[uniqueId] = nil
        dynamicDoors[uniqueId] = nil
    end
end)

RegisterNetEvent('rs_camp:ShowTopNotification')
AddEventHandler('rs_camp:ShowTopNotification',
                function(tittle, subtitle, duration)
    exports.rs_camp:ShowTopNotification(tostring(tittle),
                                                    tostring(subtitle),
                                                    tonumber(duration))
end)

RegisterNetEvent('rs_camp:ShowAdvancedRightNotification')
AddEventHandler('rs_camp:ShowAdvancedRightNotification',
                function(text, dict, icon, text_color, duration)
    local _dict = dict
    local _icon = icon
    if not LoadTexture(_dict) then
        _dict = "honor_display "
        LoadTexture(_dict)
        _icon = "honor_bad"
    end
    exports.rs_camp:ShowAdvancedRightNotification(tostring(text),
                                                              tostring(_dict),
                                                              tostring(_icon),
                                                              tostring(
                                                                  text_color),
                                                              tonumber(duration))
end)

function LoadTexture(dict)
    if Citizen.InvokeNative(0x7332461FC59EB7EC, dict) then
        RequestStreamedTextureDict(dict, true)
        while not HasStreamedTextureDictLoaded(dict) do Wait(1) end
        return true
    else
        return false
    end
end

function bigInt(text)
    local string1 = DataView.ArrayBuffer(16)
    string1:SetInt64(0, text)
    return string1:GetInt64(0)
end

exports("ShowTopNotification", function(title, subtext, duration)
    local struct1 = DataView.ArrayBuffer(8 * 7)
    struct1:SetInt32(8 * 0, duration)
    local string1 = CreateVarString(10, "LITERAL_STRING", title)
    local string2 = CreateVarString(10, "LITERAL_STRING", subtext)
    local struct2 = DataView.ArrayBuffer(8 * 7)
    struct2:SetInt64(8 * 1, bigInt(string1))
    struct2:SetInt64(8 * 2, bigInt(string2))
    Citizen.InvokeNative(0xA6F4216AB10EB08E, struct1:Buffer(), struct2:Buffer(),
                         1, 1)
end)

exports("ShowAdvancedRightNotification",
        function(_text, _dict, icon, text_color, duration, quality)
    local text = CreateVarString(10, "LITERAL_STRING", _text)
    local dict = CreateVarString(10, "LITERAL_STRING", _dict)
    local sdict = CreateVarString(10, "LITERAL_STRING",
                                  "Transaction_Feed_Sounds")
    local sound = CreateVarString(10, "LITERAL_STRING", "Transaction_Positive")

    local struct1 = DataView.ArrayBuffer(8 * 7)
    struct1:SetInt32(8 * 0, duration)
    struct1:SetInt64(8 * 1, bigInt(sdict))
    struct1:SetInt64(8 * 2, bigInt(sound))

    local struct2 = DataView.ArrayBuffer(8 * 10)
    struct2:SetInt64(8 * 1, bigInt(text))
    struct2:SetInt64(8 * 2, bigInt(dict))
    struct2:SetInt64(8 * 3, bigInt(GetHashKey(icon)))
    struct2:SetInt64(8 * 5, bigInt(GetHashKey(text_color or "COLOR_ENEMY")))

    Citizen.InvokeNative(0xB249EBCB30DD88E0, struct1:Buffer(), struct2:Buffer(),
                         1)
end)
