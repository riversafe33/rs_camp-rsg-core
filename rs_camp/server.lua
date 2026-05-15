local RSGCore = exports['rsg-core']:GetCoreObject()
local loadedCamps = {}

local function registerStorage(stashId, label, slots, maxweight)
    exports['rsg-inventory']:CreateInventory(stashId, {
        label     = label,
        slots     = slots,
        maxweight = maxweight
    })
end

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() ~= resource then return end

    exports.oxmysql:execute('SELECT * FROM rs_camp', {}, function(results)
        if not results then return end
        loadedCamps = {}
        for _, row in pairs(results) do
            table.insert(loadedCamps, {
                id       = row.id,
                x        = row.x,
                y        = row.y,
                z        = row.z,
                rotation = { x = row.rot_x, y = row.rot_y, z = row.rot_z },
                item     = { name = row.item_name, model = row.item_model }
            })
        end
    end)
end)

RegisterNetEvent('rs_camp:server:requestCamps')
AddEventHandler('rs_camp:server:requestCamps', function()
    TriggerClientEvent('rs_camp:client:receiveCamps', source, loadedCamps)
end)

RegisterNetEvent('rs_camp:server:savecampOwner')
AddEventHandler('rs_camp:server:savecampOwner', function(coords, rotation, itemName)
    local src       = source
    local Player    = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.Items[itemName] then return end

    local citizenid  = Player.PlayerData.citizenid
    local charId     = Player.PlayerData.cid
    local itemModel  = Config.Items[itemName].model
    local rotX, rotY, rotZ = rotation.x, rotation.y, rotation.z

    local query = [[
        INSERT INTO rs_camp
            (owner_identifier, owner_charid, x, y, z, rot_x, rot_y, rot_z, item_name, item_model)
        VALUES
            (@identifier, @charid, @x, @y, @z, @rot_x, @rot_y, @rot_z, @item_name, @item_model)
    ]]

    exports.oxmysql:execute(query, {
        ['@identifier'] = citizenid,
        ['@charid']     = charId,
        ['@x']          = coords.x,
        ['@y']          = coords.y,
        ['@z']          = coords.z,
        ['@rot_x']      = rotX,
        ['@rot_y']      = rotY,
        ['@rot_z']      = rotZ,
        ['@item_name']  = itemName,
        ['@item_model'] = itemModel
    }, function(result)
        if not (result and result.insertId) then return end

        local campData = {
            id       = result.insertId,
            x        = coords.x,
            y        = coords.y,
            z        = coords.z,
            rotation = { x = rotX, y = rotY, z = rotZ },
            item     = { name = itemName, model = itemModel }
        }
        table.insert(loadedCamps, campData)
        TriggerClientEvent('rs_camp:client:spawnCamps', -1, campData)
    end)
end)

RegisterNetEvent('rs_camp:server:pickUpByOwner')
AddEventHandler('rs_camp:server:pickUpByOwner', function(uniqueId)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid      = Player.PlayerData.citizenid
    local charId         = Player.PlayerData.cid
    local characterGroup = Player.PlayerData.job.name

    local function IsAuthorizedGroup(group)
        for _, allowed in ipairs(Config.AdminGroups) do
            if group == allowed then return true end
        end
        return false
    end

    local function IsChest(objectModel)
        for _, chest in ipairs(Config.Chests) do
            if chest.object == objectModel then return true end
        end
        return false
    end

    local function RemoveCamp(row)
        TriggerClientEvent('rs_camp:client:removeCamp', -1, uniqueId)

        for i, camp in ipairs(loadedCamps) do
            if camp.id == uniqueId then
                table.remove(loadedCamps, i)
                break
            end
        end

        exports.oxmysql:execute('DELETE FROM rs_camp WHERE id = ?', { uniqueId }, function(result)

            if IsChest(row.item_model) then
                local stashId = 'camp_storage_' .. uniqueId

                Wait(500)

                exports.oxmysql:execute(
                    'DELETE FROM inventories WHERE identifier = ?',
                    { stashId }
                )
            end

            local affected = result and (result.affectedRows or result.affected_rows or result.changes)

            if affected and affected > 0 then
                if row.item_name then
                    exports['rsg-inventory']:AddItem(src, row.item_name, 1, nil, nil, 'camp-pickup')
                end
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Picked, "generic_textures", "tick", "COLOR_GREEN", 4000)
            end
        end)
    end

    exports.oxmysql:execute('SELECT * FROM rs_camp WHERE id = ?', { uniqueId }, function(results)
        if not results or #results == 0 then
            TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Dont, "menu_textures", "cross", "COLOR_RED", 3000)
            return
        end

        local row = results[1]

        local isOwner = (row.owner_identifier == citizenid and row.owner_charid == charId)
        if not (isOwner or IsAuthorizedGroup(characterGroup)) then
            TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Dont, "menu_textures", "cross", "COLOR_RED", 3000)
            return
        end

        if not IsChest(row.item_model) then
            RemoveCamp(row)
            return
        end

        local stashId = 'camp_storage_' .. uniqueId
        local stash   = exports['rsg-inventory']:GetInventory(stashId)

        if stash and stash.items and next(stash.items) then
            TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src,  Config.Text.chestfull, "menu_textures", "cross", "COLOR_RED", 3000)
        else
            RemoveCamp(row)
        end
    end)
end)

RegisterNetEvent('rs_camp:server:openChest')
AddEventHandler('rs_camp:server:openChest', function(campId)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    exports.oxmysql:execute('SELECT * FROM rs_camp WHERE id = ?', { campId }, function(results)
        if not results or #results == 0 then return end

        local row = results[1]
        local hasAccess = false

        if row.owner_identifier == Player.PlayerData.citizenid
        and row.owner_charid    == Player.PlayerData.cid then
            hasAccess = true
        else
            local sharedWith = json.decode(row.shared_with or '[]') or {}
            for _, data in ipairs(sharedWith) do
                if data and data.charIdentifier == Player.PlayerData.cid then
                    hasAccess = true
                    break
                end
            end
        end

        if not hasAccess then
            TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Dontchest, "menu_textures", "cross", "COLOR_RED", 2000)
            return
        end

        local capacity = 1000
        local slots    = 50
        for _, v in pairs(Config.Chests) do
            if v.object == row.item_model then
                capacity = v.capacity or 1000
                slots    = v.slots    or 50
                break
            end
        end

        local stashId = 'camp_storage_' .. campId
        registerStorage(stashId, Config.Text.StorageName, slots, capacity)
        exports['rsg-inventory']:OpenInventory(src, stashId, {
            label     = Config.Text.StorageName,
            slots     = slots,
            maxweight = capacity
        })
    end)
end)

RegisterNetEvent('rs_camp:server:toggleDoor')
AddEventHandler('rs_camp:server:toggleDoor', function(campId)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    exports.oxmysql:execute('SELECT * FROM rs_camp WHERE id = ?', { campId }, function(results)
        if not results or #results == 0 then return end

        local row        = results[1]
        local hasAccess  = false

        if row.owner_identifier == Player.PlayerData.citizenid
        and row.owner_charid    == Player.PlayerData.cid then
            hasAccess = true
        else
            local sharedWith = json.decode(row.shared_with or '[]') or {}
            for _, data in ipairs(sharedWith) do
                if data and data.charIdentifier == Player.PlayerData.cid then
                    hasAccess = true
                    break
                end
            end
        end

        if not hasAccess then
            TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Dontdoor, "menu_textures", "cross", "COLOR_RED", 2000)
            return
        end

        TriggerClientEvent('rs_camp:client:toggleDoor', -1, campId)
    end)
end)

RegisterCommand(Config.Commands.Shareperms, function(source, args)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local campId         = tonumber(args[1])
    local targetPlayerId = tonumber(args[2])
    if not campId or not targetPlayerId then return end

    exports.oxmysql:execute(
        'SELECT shared_with, owner_identifier, owner_charid FROM rs_camp WHERE id = ?',
        { campId },
        function(results)
            if not results or #results == 0 then
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Permsdont, "menu_textures", "cross", "COLOR_RED", 3000)
                return
            end

            local row = results[1]

            if row.owner_identifier ~= Player.PlayerData.citizenid
            or row.owner_charid     ~= Player.PlayerData.cid then
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Dontowner, "menu_textures", "cross", "COLOR_RED", 3000)
                return
            end

            local Target = RSGCore.Functions.GetPlayer(targetPlayerId)
            if not Target then
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Playerno, "menu_textures", "cross", "COLOR_RED", 3000)
                return
            end

            local targetCitizenid = Target.PlayerData.citizenid
            local targetCharId    = Target.PlayerData.cid

            local sharedWith  = json.decode(row.shared_with or '[]') or {}
            local cleanArray  = {}
            local alreadyExists = false

            for _, v in ipairs(sharedWith) do
                if v ~= nil then
                    if v.charIdentifier == targetCharId then
                        alreadyExists = true
                    end
                    table.insert(cleanArray, v)
                end
            end

            if alreadyExists then
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Already, "menu_textures", "cross", "COLOR_RED", 3000)
                return
            end

            table.insert(cleanArray, { identifier = targetCitizenid, charIdentifier = targetCharId })

            exports.oxmysql:execute(
                'UPDATE rs_camp SET shared_with = ? WHERE id = ?',
                { json.encode(cleanArray), campId },
                function()
                    TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Permsyes, "generic_textures", "tick", "COLOR_GREEN", 3000)
                end
            )
        end
    )
end, false)

RegisterCommand(Config.Commands.Unshareperms, function(source, args)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local campId = tonumber(args[1])
    if not campId then return end

    exports.oxmysql:execute(
        'SELECT shared_with, owner_identifier, owner_charid FROM rs_camp WHERE id = ?',
        { campId },
        function(results)
            if not results or #results == 0 then
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Permsdont, "menu_textures", "cross", "COLOR_RED", 3000)
                return
            end

            local row = results[1]

            if row.owner_identifier ~= Player.PlayerData.citizenid
            or row.owner_charid     ~= Player.PlayerData.cid then
                TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Dontowner, "menu_textures", "cross", "COLOR_RED", 3000)
                return
            end

            exports.oxmysql:execute(
                'UPDATE rs_camp SET shared_with = ? WHERE id = ?',
                { json.encode({}), campId },
                function()
                    TriggerClientEvent('rs_camp:ShowAdvancedRightNotification', src, Config.Text.Allpermission, "generic_textures", "tick", "COLOR_GREEN", 3000)
                end
            )
        end
    )
end, false)

local MAX_ITEMS_PER_PLAYER = Config.MaxObject

for itemName, _ in pairs(Config.Items) do
    RSGCore.Functions.CreateUseableItem(itemName, function(source, item)
        local src    = source
        local Player = RSGCore.Functions.GetPlayer(src)
        if not Player then return end

        TriggerClientEvent('rs_camp:client:sendTownToServer', src, itemName)
    end)
end

RegisterNetEvent('rs_camp:server:checkTownAndPlace')
AddEventHandler('rs_camp:server:checkTownAndPlace', function(itemName, town)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local allowed = Config.AllowedTowns[town]
    if allowed == false then
        exports['rsg-inventory']:CloseInventory(src)
        TriggerClientEvent('rs_camp:ShowTopNotification', src, Config.Text.Camp, Config.Text.NotInTown, 4000)
        return
    end

    exports.oxmysql:execute(
        'SELECT COUNT(*) as count FROM rs_camp WHERE owner_identifier = @identifier AND owner_charid = @charid',
        {
            ['@identifier'] = Player.PlayerData.citizenid,
            ['@charid']     = Player.PlayerData.cid
        },
        function(result)
            local count = result[1] and result[1].count or 0

            if count >= MAX_ITEMS_PER_PLAYER then
                exports['rsg-inventory']:CloseInventory(src)
                TriggerClientEvent('rs_camp:ShowTopNotification', src, Config.Text.Camp, Config.Text.MaxItems, 4000)
                return
            end

            exports['rsg-inventory']:CloseInventory(src)
            TriggerClientEvent('rs_camp:client:placePropCamp', src, itemName)
        end
    )
end)

RegisterNetEvent('rs_camp:removeItem')
AddEventHandler('rs_camp:removeItem', function(itemName)
    local src = source
    if Config.Items[itemName] then
        exports['rsg-inventory']:RemoveItem(src, itemName, 1, nil, 'camp-placed')
    end
end)
