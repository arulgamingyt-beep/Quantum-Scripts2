local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

--------------------------------------------
-- DATABASE TABLE FOR WEAPON CUSTOMIZATIONS
--------------------------------------------
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `weapon_customizations` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) NOT NULL,
            `charname` VARCHAR(100) DEFAULT NULL,
            `weapon_serial` VARCHAR(50) NOT NULL,
            `weapon_name` VARCHAR(100) DEFAULT NULL,
            `components` LONGTEXT DEFAULT NULL,
            `component_labels` LONGTEXT DEFAULT NULL,
            `price_paid` INT DEFAULT 0,
            `shop_location` VARCHAR(100) DEFAULT 'valentine',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX `idx_citizenid` (`citizenid`),
            INDEX `idx_weapon_serial` (`weapon_serial`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    print('^2[rsg-weaponcomp]^0 Database table weapon_customizations ready')
end)

--------------------------------------------
-- REGISTER JOB (Valentine Weaponsmith)
--------------------------------------------
CreateThread(function()
    Wait(1000) -- Wait for RSGCore to be ready
    
    local valweaponsmith = {
        label = 'Valentine Weaponsmith',
        type = 'valweaponsmith',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Apprentice Smith', payment = 15 },
            ['1'] = { name = 'Gunsmith', payment = 30 },
            ['2'] = { name = 'Senior Gunsmith', payment = 50 },
            ['3'] = { name = 'Master Smith', payment = 80, isboss = true },
        },
    }
    
    -- Add job if it doesn't exist
    if not RSGCore.Shared.Jobs['valweaponsmith'] then
        RSGCore.Shared.Jobs['valweaponsmith'] = valweaponsmith
        TriggerClientEvent('RSGCore:Client:OnSharedUpdate', -1, 'Jobs', 'valweaponsmith', valweaponsmith)
        print('^2[rsg-weaponcomp]^0 Registered job: valweaponsmith')
    end
end)

-- When player uses the gunsmith item, open the prop placer
RSGCore.Functions.CreateUseableItem(Config.Gunsmithitem, function(source)
  TriggerClientEvent('rsg-weaponcomp:client:createprop', source, {
    propmodel = Config.Gunsmithprop,
    item      = Config.Gunsmithitem
  })
end)

--------------------------------------------
-- COMMAND 
--------------------------------------------
RSGCore.Commands.Add(Config.Commandinspect, locale('cl_lang_30'), {}, false, function(source)
    local src = source
    TriggerClientEvent('rsg-weaponcomp:client:InspectionWeapon', src)
end)

RSGCore.Commands.Add(Config.Commandloadweapon, locale('cl_lang_31'), {}, false, function(source)
    local src = source
    TriggerEvent('rsg-weaponcomp:server:check_comps', src)
end)

-- Helper para buscar el item de arma por serie
local function GetWeaponItemEntry(Player, serial)
    for _, item in pairs(Player.PlayerData.items) do
        if item.type == 'weapon'
        and item.info
        and item.info.serie == serial
        then
            return item
        end
    end
    return nil
end

-- EQUIPAR SCOPE
RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:equipScope', function(source, cb, serial)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end

    local weaponItem = GetWeaponItemEntry(Player, serial)
    if not weaponItem then
        return cb(false)
    end

    if weaponItem.info.equippedScope then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = locale('cl_scope_already_on') })
        return cb(false)
    end

    weaponItem.info.equippedScope = true
    Player.Functions.SetInventory(Player.PlayerData.items)
    cb(true)
end)

-- REMOVER SCOPE
RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:unequipScope', function(source, cb, serial)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end

    local weaponItem = GetWeaponItemEntry(Player, serial)
    if not weaponItem then
        return cb(false)
    end

    if not weaponItem.info.equippedScope then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = locale('cl_scope_already_off') })
        return cb(false)
    end

    weaponItem.info.equippedScope = false
    Player.Functions.SetInventory(Player.PlayerData.items)
    cb(true)
end)

--------------------------------------------
-- Callback
--------------------------------------------
-- Count how many sites player has
RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:countprop', function(source, cb, proptype)
  local ply = RSGCore.Functions.GetPlayer(source)
  local res = MySQL.prepare.await( "SELECT COUNT(*) as count FROM player_weapons_custom WHERE citizenid = ? AND item = ?",
    { ply.PlayerData.citizenid, proptype }
  )
  cb(res or 0)
end)

RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:getItemBySerial', function(source, cb, serial)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then cb(nil); return end

    for _, item in pairs(Player.PlayerData.items) do
        if item.type == 'weapon' and item.info and item.info.serie == serial then
            cb({ components = item.info.componentshash})
            return
        end
    end

    cb(nil)
end)

RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:getPlayerWeaponComponents', function(source, cb, serial)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then cb(nil); return end

    for _, item in pairs(Player.PlayerData.items) do
        if item.type == 'weapon'
        and item.info
        and item.info.serie == serial
        then
            local comps = item.info.componentshash or {}

            if not item.info.equippedScope then
                local filtered = {}
                for cat, name in pairs(comps) do
                    if cat ~= "SCOPE" then
                        filtered[cat] = name
                    end
                end
                comps = filtered
            end

            return cb({ components = comps })
        end
    end

    cb(nil)
end)

---------------------------------------------
-- create new gunsite in database
---------------------------------------------
-- create gunsite id
local function CreategunsiteId()
    local UniqueFound = false
    local gunsiteId = nil
    while not UniqueFound do
        gunsiteId = 'CSID' .. math.random(11111111, 99999999)
        local query = "%" .. gunsiteId .. "%"
        local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM player_weapons_custom WHERE gunsiteid LIKE ?", { query })
        if result == 0 then
            UniqueFound = true
        end
    end
    return gunsiteId
end

-- create prop id
local function CreatePropId()
    local UniqueFound = false
    local PropId = nil
    while not UniqueFound do
        PropId = 'PID' .. math.random(11111111, 99999999)
        local query = "%" .. PropId .. "%"
        local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM player_weapons_custom WHERE propid LIKE ?", { query })
        if result == 0 then
            UniqueFound = true
        end
    end
    return PropId
end

RegisterServerEvent('rsg-weaponcomp:server:createnewprop')
AddEventHandler('rsg-weaponcomp:server:createnewprop', function(propmodel, item, coords, heading)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local gunsiteid = CreategunsiteId()
    local propid = CreatePropId()
    local citizenid = Player.PlayerData.citizenid

    local PropData =
    {
        gunsitename = locale('cl_lang_32'),
        gunsiteid = gunsiteid,
        propid = propid,
        item = item,
        x = coords.x,
        y = coords.y,
        z = coords.z,
        h = heading,
        propmodel = propmodel,
        citizenid = citizenid,
        buildttime = os.time()
    }

    local newpropdata = json.encode(PropData)

    -- add gunsite to database
    MySQL.Async.execute('INSERT INTO player_weapons_custom (gunsiteid, propid, citizenid, item, propdata) VALUES (@gunsiteid, @propid, @citizenid, @item, @propdata)', {
        ['@gunsiteid'] = gunsiteid,
        ['@propid'] = propid,
        ['@citizenid'] = citizenid,
        ['@item'] = item,
        ['@propdata'] = newpropdata
    })

    table.insert(Config.PlayerProps, PropData)
    Player.Functions.RemoveItem(Config.Gunsmithitem, 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[Config.Gunsmithitem], 'remove', 1)
    TriggerEvent('rsg-weaponcomp:server:updateProps', src)

end)

---------------------------------------------
-- update props
---------------------------------------------
RegisterServerEvent('rsg-weaponcomp:server:updateProps')
AddEventHandler('rsg-weaponcomp:server:updateProps', function()
    local src = source
    TriggerClientEvent('rsg-weaponcomp:client:updatePropData', src, Config.PlayerProps)
end)

-- update prop
CreateThread(function()
    while true do
        Wait(5000)
        if PropsLoaded then
            TriggerClientEvent('rsg-weaponcomp:client:updatePropData', -1, Config.PlayerProps)
        end
    end
end)

-- get props
CreateThread(function()
    TriggerEvent('rsg-weaponcomp:server:getProps', source)
    PropsLoaded = true
end)

RegisterServerEvent('rsg-weaponcomp:server:getProps')
AddEventHandler('rsg-weaponcomp:server:getProps', function()
    local result = MySQL.query.await('SELECT * FROM player_weapons_custom')
    if not result[1] then return end
    for i = 1, #result do
        local propData = json.decode(result[i].propdata)
        if Config.LoadNotification then print(locale('sv_lang_1')..propData.item..locale('sv_lang_2')..propData.propid) end
        table.insert(Config.PlayerProps, propData)
    end
end)

---------------------------------------------
-- items
---------------------------------------------
-- add item
RegisterServerEvent('rsg-weaponcomp:server:additem')
AddEventHandler('rsg-weaponcomp:server:additem', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local item, amount = Config.Gunsmithitem, 1
    Player.Functions.AddItem(item, amount)
    TriggerClientEvent('rNotify:ShowAdvancedRightNotification', src, amount .." x "..RSGCore.Shared.Items[item].label, "generic_textures" , "tick" , "COLOR_PURE_WHITE", 4000)
end)

-- remove
RegisterServerEvent('rsg-weaponcomp:server:removeitem')
AddEventHandler('rsg-weaponcomp:server:removeitem', function(item, amount)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    Player.Functions.RemoveItem(item, amount)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[item], 'remove', amount)
end)

-- remove gunsite props
RegisterServerEvent('rsg-weaponcomp:server:removegunsiteprops')
AddEventHandler('rsg-weaponcomp:server:removegunsiteprops', function(propid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    local result = MySQL.query.await('SELECT * FROM player_weapons_custom WHERE propid = ?', { propid })
    if not result or not result[1] then return end
    local propData = json.decode(result[1].propdata)

    if propData.citizenid ~= citizenid then print(locale('sv_lang_3')) return end

    MySQL.Async.execute('DELETE FROM player_weapons_custom WHERE propid = @propid', { ['@propid'] = propid })

    for k, v in pairs(Config.PlayerProps) do
        if v.propid == propid then
            table.remove(Config.PlayerProps, k)
            break
        end
    end

    -- print((locale('sv_lang_4').. " %s ".. locale('sv_lang_5') .." %s"):format(citizenid, propid))

    TriggerClientEvent('rsg-weaponcomp:client:updatePropData', -1, Config.PlayerProps)
    TriggerClientEvent('rsg-weaponcomp:client:ExitCam', src)
end)

-------------------------------------------
-- Save / Payment
-------------------------------------------
local function saveWeaponComponents(serial, comps, compslabel, Player, weaponName, pricePaid)
    local weaponLabel = weaponName or 'Unknown'
    
    -- Find and update weapon in inventory
    for _, item in pairs(Player.PlayerData.items) do
        if item.type == 'weapon' and item.info.serie == serial then
            item.info.componentshash = (type(comps) == "table" and next(comps)) and comps or nil
            item.info.components = (type(compslabel) == "table" and next(compslabel)) and compslabel or nil
            weaponLabel = item.name or item.label or weaponName or 'Unknown'
            break
        end
    end

    Player.Functions.SetInventory(Player.PlayerData.items)
    
    -- Save to dedicated database table
    local citizenid = Player.PlayerData.citizenid
    local charname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    local componentsJson = comps and json.encode(comps) or nil
    local labelsJson = compslabel and json.encode(compslabel) or nil
    
    -- Check if record exists
    local existing = MySQL.query.await('SELECT id FROM weapon_customizations WHERE weapon_serial = ?', { serial })
    
    if existing and existing[1] then
        -- Update existing record
        MySQL.update.await([[
            UPDATE weapon_customizations 
            SET components = ?, component_labels = ?, price_paid = price_paid + ?, updated_at = NOW()
            WHERE weapon_serial = ?
        ]], { componentsJson, labelsJson, pricePaid or 0, serial })
    else
        -- Insert new record
        MySQL.insert.await([[
            INSERT INTO weapon_customizations (citizenid, charname, weapon_serial, weapon_name, components, component_labels, price_paid)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], { citizenid, charname, serial, weaponLabel, componentsJson, labelsJson, pricePaid or 0 })
    end
    
    -- Update shop stats
    if pricePaid and pricePaid > 0 then
        TriggerEvent('rsg-weaponcomp:server:trackSale', pricePaid)
    end

    -- Logging
    local msg = table.concat({
        locale('sv_lang_6') .. ':** '..Player.PlayerData.citizenid..'**',
        locale('sv_lang_7') .. ':** '..Player.PlayerData.cid..'**',
        locale('sv_lang_8') .. ':** '..serial..'**',
        locale('sv_lang_9') .. ':** '..json.encode(comps)
    }, '\n')
    TriggerEvent('rsg-log:server:CreateLog', Config.WebhookName, Config.WebhookTitle, Config.WebhookColour, msg)
    
    print('^2[rsg-weaponcomp]^0 Saved customization for weapon: ' .. serial .. ' | Player: ' .. charname)
end

local function CalculatePrice(selection)
    local total = 0
    for cat, _ in pairs(selection or {}) do
        total = total + (Config.price[cat] or 0)
    end
    return total
end

RegisterServerEvent('rsg-weaponcomp:server:setComponents', function(objecthash, serial, selectedCache, selectedLabels)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local currentCash = Player.Functions.GetMoney(Config.PaymentType)
    local price = CalculatePrice(selectedCache)
    
    if currentCash < price then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('sv_lang_10', price),
            description = locale('sv_lang_11'),
            type = 'error'
        })
        TriggerClientEvent('rsg-weaponcomp:client:ExitCam', src)
        return
    end
    
    Player.Functions.RemoveMoney(Config.PaymentType, price)
    local weaponName = Citizen.InvokeNative(0x89CF5FF3D363311E, objecthash, Citizen.ResultAsString()) or 'Unknown'
    saveWeaponComponents(serial, selectedCache, selectedLabels, Player, weaponName, price)
    TriggerClientEvent('rsg-weaponcomp:client:animationSaved', src, objecthash, serial)
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('cl_notify_9'),
        description = '$' .. price,
        type = 'success',
        duration = 5000,
    })
end)

RegisterNetEvent('rsg-weaponcomp:server:removeComponents', function(objecthash, serial)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local item = GetWeaponItemEntry(Player, serial)
    if not item then
        return
    end

    local currentCash = Player.Functions.GetMoney(Config.PaymentType)
    local price = CalculatePrice(item.info?.componentshash) * Config.RemovePrice
    
    if currentCash < price then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('sv_lang_10', price),
            description = locale('sv_lang_11'),
            type = 'error'
        })
        TriggerClientEvent('rsg-weaponcomp:client:ExitCam', src)
        return
    end
    
    Player.Functions.RemoveMoney(Config.PaymentType, price)
    saveWeaponComponents(serial, nil, nil, Player, nil, price)
    TriggerClientEvent('rsg-weaponcomp:client:animationSaved', src, objecthash, serial)
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('cl_notify_11'),
        description = '$' .. price,
        type = 'success',
        duration = 5000,
    })
end)

--------------------------------------------
-- CHECK COMPONENTS SQL
--------------------------------------------
RegisterNetEvent('rsg-weaponcomp:server:check_comps') -- EQUIPED
AddEventHandler('rsg-weaponcomp:server:check_comps', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    TriggerClientEvent('rsg-weaponcomp:client:reloadWeapon', src)
end)


--------------------------------------------
-- WEAPON SHOP STASH
--------------------------------------------
RegisterServerEvent('rsg-weaponcomp:server:openStash')
AddEventHandler('rsg-weaponcomp:server:openStash', function(shopId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local shopData = Config.WeaponShops[shopId]
    if not shopData or not shopData.stash or not shopData.stash.enabled then return end
    
    -- Check job if required
    if shopData.job then
        local playerJob = Player.PlayerData.job.name
        if playerJob ~= shopData.job then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Access Denied',
                description = 'You do not have access to this storage',
                type = 'error'
            })
            return
        end
    end
    
    local stashName = 'weaponshop_' .. shopId
    local stashConfig = {
        maxweight = shopData.stash.weight or 100000,
        slots = shopData.stash.slots or 50,
    }
    
    -- Try different inventory export methods
    local success = pcall(function()
        exports['rsg-inventory']:OpenInventory(src, stashName, stashConfig)
    end)
    
    if not success then
        -- Fallback: trigger client event for stash
        TriggerClientEvent('rsg-inventory:client:openInventory', src, stashName, stashConfig)
    end
end)

--------------------------------------------
-- BOSS MENU FUNCTIONS
--------------------------------------------

-- Shop statistics tracking
local ShopStats = {
    salesToday = 0,
    totalRevenue = 0,
    weaponsCustomized = 0,
}

-- Get all employees for a job
RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:getEmployees', function(source, cb, jobName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return cb(nil) end
    
    -- Check if player is boss
    local playerJob = Player.PlayerData.job
    if playerJob.name ~= jobName or (not playerJob.isboss and not playerJob.isBoss and playerJob.grade.level < 3) then
        return cb(nil)
    end
    
    local employees = {}
    local players = RSGCore.Functions.GetRSGPlayers()
    
    -- Get online players with this job
    for _, targetPlayer in pairs(players) do
        if targetPlayer.PlayerData.job.name == jobName then
            local gradeData = RSGCore.Shared.Jobs[jobName].grades[tostring(targetPlayer.PlayerData.job.grade.level)]
            table.insert(employees, {
                identifier = targetPlayer.PlayerData.citizenid,
                name = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname,
                grade = targetPlayer.PlayerData.job.grade.level,
                gradeName = gradeData and gradeData.name or 'Unknown',
                payment = gradeData and gradeData.payment or 0,
                online = true,
            })
        end
    end
    
    -- Get offline players from database
    local result = MySQL.query.await('SELECT citizenid, charinfo, job FROM players WHERE JSON_EXTRACT(job, "$.name") = ?', { jobName })
    if result then
        for _, row in ipairs(result) do
            local charinfo = json.decode(row.charinfo)
            local job = json.decode(row.job)
            local isOnline = false
            
            -- Check if already in online list
            for _, emp in ipairs(employees) do
                if emp.identifier == row.citizenid then
                    isOnline = true
                    break
                end
            end
            
            if not isOnline then
                local gradeData = RSGCore.Shared.Jobs[jobName].grades[tostring(job.grade.level)]
                table.insert(employees, {
                    identifier = row.citizenid,
                    name = charinfo.firstname .. ' ' .. charinfo.lastname,
                    grade = job.grade.level,
                    gradeName = gradeData and gradeData.name or 'Unknown',
                    payment = gradeData and gradeData.payment or 0,
                    online = false,
                })
            end
        end
    end
    
    cb(employees)
end)

-- Get shop analysis data
RSGCore.Functions.CreateCallback('rsg-weaponcomp:server:getShopAnalysis', function(source, cb, jobName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return cb(nil) end
    
    -- Count employees
    local employeeCount = 0
    local result = MySQL.query.await('SELECT COUNT(*) as count FROM players WHERE JSON_EXTRACT(job, "$.name") = ?', { jobName })
    if result and result[1] then
        employeeCount = result[1].count
    end
    
    cb({
        totalEmployees = employeeCount,
        salesToday = ShopStats.salesToday,
        totalRevenue = ShopStats.totalRevenue,
        weaponsCustomized = ShopStats.weaponsCustomized,
    })
end)

-- Hire employee
RegisterServerEvent('rsg-weaponcomp:server:hireEmployee')
AddEventHandler('rsg-weaponcomp:server:hireEmployee', function(jobName, targetId, grade)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Check if player is boss
    local playerJob = Player.PlayerData.job
    if playerJob.name ~= jobName or (not playerJob.isboss and not playerJob.isBoss and playerJob.grade.level < 3) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'You are not authorized', type = 'error' })
        return
    end
    
    local Target = RSGCore.Functions.GetPlayer(targetId)
    if not Target then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'Player not found', type = 'error' })
        return
    end
    
    -- Set job
    Target.Functions.SetJob(jobName, grade or 0)
    
    local gradeData = RSGCore.Shared.Jobs[jobName].grades[tostring(grade or 0)]
    local gradeName = gradeData and gradeData.name or 'Employee'
    
    TriggerClientEvent('ox_lib:notify', src, { 
        title = 'Employee Hired', 
        description = Target.PlayerData.charinfo.firstname .. ' hired as ' .. gradeName, 
        type = 'success' 
    })
    TriggerClientEvent('ox_lib:notify', targetId, { 
        title = 'New Job', 
        description = 'You have been hired as ' .. gradeName .. ' at Valentine Weaponsmith', 
        type = 'success' 
    })
end)

-- Fire employee
RegisterServerEvent('rsg-weaponcomp:server:fireEmployee')
AddEventHandler('rsg-weaponcomp:server:fireEmployee', function(citizenid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local playerJob = Player.PlayerData.job
    if not playerJob.isboss and not playerJob.isBoss and playerJob.grade.level < 3 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'You are not authorized', type = 'error' })
        return
    end
    
    -- Find target player (online)
    local Target = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if Target then
        Target.Functions.SetJob('unemployed', 0)
        TriggerClientEvent('ox_lib:notify', Target.PlayerData.source, { 
            title = 'Fired', 
            description = 'You have been fired from your job', 
            type = 'error' 
        })
    else
        -- Update offline player
        MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', {
            json.encode({ name = 'unemployed', label = 'Unemployed', payment = 0, onduty = false, isboss = false, grade = { name = 'Unemployed', level = 0 } }),
            citizenid
        })
    end
    
    TriggerClientEvent('ox_lib:notify', src, { title = 'Success', description = 'Employee has been fired', type = 'success' })
end)

-- Change employee grade
RegisterServerEvent('rsg-weaponcomp:server:changeGrade')
AddEventHandler('rsg-weaponcomp:server:changeGrade', function(citizenid, newGrade)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local playerJob = Player.PlayerData.job
    if not playerJob.isboss and not playerJob.isBoss and playerJob.grade.level < 3 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'You are not authorized', type = 'error' })
        return
    end
    
    local Target = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if Target then
        Target.Functions.SetJob(playerJob.name, newGrade)
        local gradeData = RSGCore.Shared.Jobs[playerJob.name].grades[tostring(newGrade)]
        TriggerClientEvent('ox_lib:notify', Target.PlayerData.source, { 
            title = 'Grade Changed', 
            description = 'Your grade has been changed to ' .. (gradeData and gradeData.name or 'Unknown'), 
            type = 'info' 
        })
    else
        -- Update offline player
        local gradeData = RSGCore.Shared.Jobs[playerJob.name].grades[tostring(newGrade)]
        local jobData = {
            name = playerJob.name,
            label = RSGCore.Shared.Jobs[playerJob.name].label,
            payment = gradeData and gradeData.payment or 0,
            onduty = true,
            isboss = gradeData and gradeData.isboss or false,
            grade = {
                name = gradeData and gradeData.name or 'Unknown',
                level = newGrade
            }
        }
        MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(jobData), citizenid })
    end
    
    TriggerClientEvent('ox_lib:notify', src, { title = 'Success', description = 'Employee grade updated', type = 'success' })
end)

-- Track sales for analysis
AddEventHandler('rsg-weaponcomp:server:trackSale', function(amount)
    ShopStats.salesToday = ShopStats.salesToday + amount
    ShopStats.totalRevenue = ShopStats.totalRevenue + amount
    ShopStats.weaponsCustomized = ShopStats.weaponsCustomized + 1
end)

-- Reset daily stats at midnight
CreateThread(function()
    while true do
        Wait(3600000) -- Check every hour
        local hour = tonumber(os.date('%H'))
        if hour == 0 then
            ShopStats.salesToday = 0
        end
    end
end)
