local lib = require "__FARL__/lib_control"
local saveVar = lib.saveVar
local debugDump = lib.debugDump
local startsWith = lib.startsWith
local mod_gui = require '__core__/lualib/mod-gui'

local isValidSlot = function(slot, state)
    if not slot or not slot.valid_for_read then return false end

    --if state then
    if state == "empty" then
        return not slot.is_blueprint_setup()
    elseif state == "setup" then
        return slot.is_blueprint_setup()
    end
    --end
    return true
end

local getBlueprints = function(book, state)
    local main = book.get_inventory(defines.inventory.item_main)
    local count = 0
    local bps = {}
    for i=1, #main do
        if isValidSlot(main[i], state) then
            count = count + 1
            table.insert(bps, main[i])
        end
    end
    return bps, count
end

GUI = {

    ccWires = {
        {"stg-ccNetWire-red"},
        {"stg-ccNetWire-green"},
        {"stg-ccNetWire-both"}
    },

    styleprefix = "farl_",

    defaultStyles = {
        label = "label",
        button = "button",
        checkbox = "checkbox"
    },

    bindings = {},

    new = function()
        local new = {}
        setmetatable(new, {__index=GUI})
        return new
    end,

    init = function(player)
        local settings = Settings.loadByPlayer(player)
        GUI.bindings = {
            signals = settings.signals,
            poles = settings.poles,
            medium = settings.medium,
            ccNet = settings.ccNet,
            bridge = settings.bridge,
            collectWood = settings.collectWood,
            dropWood = settings.dropWood,
        }
    end,

    add = function(parent, e, bind)
        local gtype = e.type
        if not e.style and GUI.defaultStyles[gtype] then
            e.style = GUI.styleprefix..gtype
        end
        if bind then
            if e.type == "checkbox" then
                if e.state == nil then
                    e.state = false
                end
                if type(bind) == "string" then
                    e.state = Settings.loadByPlayer(parent.gui.player)[e.name]
                else
                    e.state = false
                    GUI.callbacks[e.name] = bind
                end
            end
        end
        if e.type == "checkbox" and not e.state then
            e.state = false
        end
        local ret = parent.add(e)
        if bind and e.type == "textfield" then
            ret.text = bind
        end
        if e.type == "checkbox" and e.state == nil then
            e.state = false
        end
        return ret
    end,

    addButton = function(parent, e, bind)
        e.type = e.type or "button"
        if bind then
            GUI.callbacks[e.name] = bind
        end
        return GUI.add(parent, e, bind)
    end,

    addLabel = function(parent, e, bind)
        if type(e) == "string" or type(e) == "number" or (type(e) == "table" and e[1]) then
            e = {caption=e}
        end
        e.type="label"
        return GUI.add(parent,e,bind)
    end,

    addTextfield = function(parent, e, bind)
        e.type="textfield"
        return GUI.add(parent, e, bind)
    end,

    addPlaceHolder = function(parent, count)
        local c = count or 1
        for _=1,c do
            GUI.add(parent, {type="label", caption=""})
        end
    end,

    createGui = function(player)
        if mod_gui.get_frame_flow(player).farl ~= nil then return end
        local psettings = Settings.loadByPlayer(player)
        --GUI.init(player)
        local farl = GUI.add(mod_gui.get_frame_flow(player), {type="frame", direction="vertical", name="farl"})
        local rows = GUI.add(farl, {type="table", name="rows", column_count=1})
        local span = 3

        local buttons = GUI.add(rows, {type="table", name="buttons", column_count=span})
        GUI.addButton(buttons, {name="start"}, GUI.toggleStart)
        GUI.addButton(buttons, {name="cc"}, GUI.toggleCC)
        GUI.create_settings_button(player, true)

        local progressBar = GUI.add(rows,{type = "progressbar", name = "pathProgress", size = 200, value = 0.5, style = "production_progressbar"})
        progressBar.style.maximal_width = 150
        progressBar.visible = false
        local progressLabel = GUI.addLabel(rows,{caption="", name = "pathLabel"})
        progressLabel.visible = false
        GUI.add(rows, {type = "flow", direction="vertical", name = "farlConfirm"})

        GUI.add(rows, {type="checkbox", name="signals", caption={"tgl-signal"}}, "signals")
        GUI.add(rows, {type="checkbox", name="poles", caption={"tgl-poles"}}, "poles")
        GUI.add(rows, {type="checkbox", name="concrete", caption={"tgl-concrete"}}, "concrete")
        GUI.add(rows,{type="checkbox", name="bulldozer", caption={"tgl-bulldozer"}, state=psettings.bulldozer, tooltip={"farl_tooltip_bulldozer"}})
        GUI.add(rows,{type="checkbox", name="maintenance", caption={"tgl-maintenance"}, state=psettings.maintenance, tooltip={"farl_tooltip_maintenance"}})
        GUI.add(rows, {type="checkbox", name="bridge", caption={"tgl-bridge"}, tooltip={"farl_tooltip_bridge"}}, "bridge")
    end,

    --  createAutopilotGui = function(entity, player)
    --
    --  end,
    --
    --  destroyAutopilotGui = function(entity, player)
    --
    --  end,

    createPopup = function(player)
        if mod_gui.get_frame_flow(player).farl then
            local gui = GUI.add(mod_gui.get_frame_flow(player).farl.rows.farlConfirm, {type = "frame", direction="vertical", name = "farlConfirmFlow"})
            GUI.addLabel(gui, {caption="Ghost rails detected, start Autopilot?"})
            GUI.add(gui, {type = "checkbox", name = "autoPilot", caption="Drive without me", state = false})
            local flow = GUI.add(gui, {type="flow", direction="horizontal", name="buttonFlow"})
            GUI.addButton(flow, {name="confirmYes", caption="Yes"}, GUI.confirmYes)
            GUI.addButton(flow, {name="confirmNo", caption="No"}, GUI.confirmNo)
        end
    end,

    destroyGui = function(player)
        if player.valid then
            if mod_gui.get_frame_flow(player).farl == nil then return end
            mod_gui.get_frame_flow(player).farl.destroy()
        end
    end,

    onGuiClick = function(event, farl, player)
        local name = event.element.name
        if GUI.callbacks[name] then
            return GUI.callbacks[name](event, farl, player)
        end
        if name == "debug" then
            saveVar(global,"debug")
            farl:debugInfo()
        elseif startsWith(name,"load_bp_") then
            local i = name:match("load_bp_(%w*)")
            GUI.load_bp(event,farl, player,tonumber(i))
        elseif startsWith(name,"save_bp_") then
            local i = name:match("save_bp_(%w*)")
            GUI.save_bp(event,farl, player,tonumber(i))
        end
    end,

    on_gui_checked_state_changed = function(event, farl, player)
        local name = event.element.name
        if name == "bulldozer" then
            return GUI.toggleBulldozer(event, farl, player)
        end
        if name == "maintenance" then
            return GUI.toggleMaintenance(event, farl, player)
        end
        local psettings = Settings.loadByPlayer(player)
        if name == "signals" or name == "poles" or name == "ccNet" or name == "flipPoles" or name == "collectWood" or name == "dropWood"
            or name == "poleEntities" or name == "parallelTracks" or name == "concrete" or name == "railEntities" or name == "mirrorConcrete"
            or name == "signalEveryPole" or name == "place_ghosts" or name == "remove_cliffs" then
            psettings[name] = not psettings[name]
            if name == "poles" then
                if psettings[name] and farl.active then
                    farl:findLastPole()
                end
            end
        elseif name == "bridge" then
            psettings.bridge = not psettings.bridge
        end
    end,

    toggleStart = function(_, farl, _)
        farl:toggleActive(true)
    end,

    debugInfo = function(_, farl, _)
        farl:debugInfo()
    end,

    confirmYes = function(event, farl, player)
        farl.confirmed = true

        --kick player out and insert farl_player
        if event.element.parent.parent.autoPilot.state then
            local loco = player.vehicle
            local farlLoco = farl.locomotive
            --        if not loco or not isFARLLocomotive(loco) then
            --          farl:deactivate()
            --          GUI.destroyGui(player)
            --          return
            --        end
            if player.vehicle and farlLoco == player.vehicle then
                player.driving = false
            end
            GUI.destroyGui(player)
            local ghostPlayer = player.surface.create_entity({name="farl_player", position=player.position, force=player.force})
            loco.set_driver(ghostPlayer)

            farl.driver = ghostPlayer
            farl.settings = util.table.deepcopy(Settings.loadByPlayer(player))
            farl.startedBy = player
            farl.cheat_mode = player.cheat_mode
            global.activeFarls[FARL.getIdFromTrain(farl.train)] = farl
            farl.direction = farl:calcTrainDir()
            farl.lastrail = farl:findLastRail()
            farl.ghostPath = farl:getGhostPath()
        end
        farl:activate()
        if farl.active then
            farl:toggleCruiseControl()
        end
        farl.confirmed = nil
        if mod_gui.get_frame_flow(player).farl then
            mod_gui.get_frame_flow(player).farl.rows.farlConfirm.farlConfirmFlow.destroy()
        end
    end,

    confirmNo = function(_, farl, player)
        farl.confirmed = false
        farl:activate()
        farl.ghostPath = nil
        farl.confirmed = nil
        mod_gui.get_frame_flow(player).farl.rows.farlConfirm.farlConfirmFlow.destroy()
    end,

    toggleBulldozer = function(_, farl, _)
        farl:toggleBulldozer()
        GUI.updateGui(farl)
    end,

    toggleMaintenance = function(_, farl, _)
        farl:toggleMaintenance()
        GUI.updateGui(farl)
    end,

    load_bp = function(event, farl, player, i)
        local index = player.index
        if global.savedBlueprints[index][i] then
            local bps = global.savedBlueprints[index][i]
            local psettings = Settings.loadByPlayer(player)
            local lanes = #bps.straight.lanes + 1
            local pole = game.entity_prototypes[bps.straight.pole.name].localised_name
            psettings.activeBP = table.deepcopy(global.savedBlueprints[index][i])
            if farl.active then
                farl:deactivate()
                farl:activate()
            end
            player.print({"", {"text-blueprint-loaded"}, " ",{"text-blueprint-description", lanes, pole}})
            GUI.toggleSettingsWindow(event,farl,player)
        end
    end,

    save_bp = function(event, farl, player, i)
        local index = player.index
        local psettings = Settings.loadByPlayer(player)
        global.savedBlueprints[index][i] = table.deepcopy(psettings.activeBP)
        player.print({"text-blueprint-saved"})
        GUI.toggleSettingsWindow(event,farl,player)
        GUI.toggleSettingsWindow(event,farl,player)
    end,

    toggleSide = function(event, _, player)
        local psettings = Settings.loadByPlayer(player)
        if psettings.poleSide == 1 then
            psettings.poleSide = -1
            event.element.caption = {"stg-side-left"}
            return
        else
            psettings.poleSide = 1
            event.element.caption = {"stg-side-right"}
            return
        end
    end,

    toggleCC = function(_, farl, _)
        farl:toggleCruiseControl()
    end,

    create_settings_button = function(player, sprite)
        local buttons = mod_gui.get_frame_flow(player).farl.rows.buttons
        if buttons.settings and buttons.settings.valid then buttons.settings.destroy() end
        if sprite then
            return GUI.addButton(buttons, {type = "sprite-button", name = "settings", sprite = "farl_settings", style = "farl_button" }, GUI.toggleSettingsWindow)
        else
            return GUI.addButton(buttons, {name = "settings", caption = {"text-save"}}, GUI.toggleSettingsWindow)
        end
    end,

    toggleSettingsWindow = function(_, farl, player)
        local row = mod_gui.get_frame_flow(player).farl.rows
        local psettings = Settings.loadByPlayer(player)
        if row.settings ~= nil then
            local s = row.settings
            local sDistance = tonumber(s.signalDistance.text) or psettings.signalDistance
            local railType = tonumber(s.railType.selected_index) or 1
            local wire = tonumber(s.row3.ccNetWires.selected_index)
            sDistance = sDistance < 0 and 0 or sDistance
            GUI.create_settings_button(player, true)
            GUI.saveSettings({ signalDistance = sDistance, railType = railType, ccWires = wire }, player, farl)
            row.settings.destroy()
        else
            local settings = row.add({type="table", name="settings", column_count=2})
            GUI.create_settings_button(player)

            GUI.add(settings,{type="checkbox", name="dropWood", caption={"stg-dropWood"}}, "dropWood")
            GUI.add(settings,{type="checkbox", name="collectWood", caption={"stg-collectWood"}}, "collectWood")

            GUI.add(settings, {type="label", caption={"stg-signalDistance"}})
            GUI.add(settings, {type="textfield", name="signalDistance", style="farl_textfield_small"}, psettings.signalDistance)

            --GUI.add(settings, {type="checkbox", name="signalEveryPole", caption={"stg-signalEveryPole"}, tooltip={"farl_tooltip_signalEveryPole"}}, "signalEveryPole")
            --GUI.add(settings, {type="label", caption=""})

            GUI.add(settings, {type="label", caption={"stg-railType"}})
            if not psettings.railType or not global.rails_localised[psettings.railType] then
                psettings.railType = 1
                psettings.rail = global.rails_by_index[1]
            end
            GUI.add(settings,{type="drop-down", name="railType", items=global.rails_localised, selected_index=psettings.railType})

            GUI.add(settings, {type="label", caption={"stg-poleSide"}})
            GUI.add(settings, {type="checkbox", name="flipPoles", caption={"stg-flipPoles"}, state=psettings.flipPoles})

            GUI.add(settings,{type="checkbox", name="poleEntities", caption={"stg-poleEntities"}, tooltip={"farl_tooltip_place_pole_entities"}},"poleEntities")
            GUI.add(settings, {type="checkbox", name="remove_cliffs", caption={"stg-remove-cliffs"}, tooltip={ "farl_tooltip_remove_cliffs", {"item-name.cliff-explosives"}}}, "remove_cliffs")

            GUI.add(settings,{type="checkbox", name="railEntities", caption={"stg-rail-entities"}, tooltip={"farl_tooltip_place_walls"}}, "railEntities")
            GUI.add(settings, { type = "checkbox", name="place_ghosts", caption = {"stg-place-ghosts"}, tooltip={"farl_tooltip_place_ghosts"}}, "place_ghosts")

            GUI.add(settings, {type="checkbox", name="mirrorConcrete", caption= {"stg-mirror-concrete"}, "mirrorConcrete"})
            GUI.addPlaceHolder(settings)

            --GUI.add(settings,{type="checkbox", name="parallelTracks", caption={"stg-parallel-tracks"}}, "parallelTracks")
            --GUI.addPlaceHolder(settings)

            GUI.add(settings, {type="checkbox", name="ccNet", caption={"stg-ccNet"}, state=psettings.ccNet})
            local row2 = GUI.add(settings, {type="table", name="row3", column_count=2})
            GUI.add(row2, {type="label", caption={"stg-ccNetWire"}})
            GUI.add(row2, { type = "drop-down", name = "ccNetWires", items = GUI.ccWires, selected_index = psettings.ccWires } )

            GUI.addLabel(settings, {caption={"stg-stored-blueprints"}})
            local stored_bp = GUI.add(settings,{type="table", column_count=3})

            local bps = global.savedBlueprints[player.index]
            for i=1,3 do
                if bps and bps[i] then
                    local lanes = #bps[i].straight.lanes + 1
                    local pole = game.entity_prototypes[bps[i].straight.pole.name].localised_name
                    GUI.addButton(stored_bp,{name="load_bp_"..i, caption="L"})
                    GUI.addButton(stored_bp,{name="save_bp_"..i, caption="S"})
                    GUI.addLabel(stored_bp, {caption={"text-blueprint-description", lanes, pole}})
                else
                    GUI.addLabel(stored_bp,{caption="L"})
                    GUI.addButton(stored_bp,{name="save_bp_"..i, caption="S"})
                    GUI.addLabel(stored_bp, {caption="--"})
                end
            end

            GUI.add(settings, {type="label", caption={"stg-blueprint"}})
            local row3 = GUI.add(settings, {type="table", name="row4", column_count=2})
            GUI.addButton(row3, {name="blueprint", caption={"stg-blueprint-read"}}, GUI.readBlueprint)
            GUI.addButton(row3, {name="bpClear", caption={"stg-blueprint-clear"}}, GUI.clearBlueprints)
            GUI.add(settings, {type="label", caption={"stg-blueprint-write"}})
            local row4 = GUI.add(settings, {type="flow", name="row5", direction="horizontal"})
            GUI.addButton(row4, {name="blueprint_concrete_vertical", caption={"stg-blueprint-vertical"}}, GUI.create_concrete_vertical)
            GUI.addButton(row4,{name="blueprint_concrete_diagonal", caption={"stg-blueprint-diagonal"}},GUI.create_concrete_diagonal)
            local row6 = GUI.add(settings, {type="flow", name="row6", direction="horizontal"})
            GUI.addButton(row6,{name="print_statistics", caption={"stg-statistics"}}, GUI.print_statistics)
        end
    end,

    findBlueprintsInHotbar = function(player)
        player.print("Cant read from the quickbar currently. Click the Read button with a blueprint or a blueprint book.")
        player.print("(Reading from the quickbar will be reenabled as soon as the API allows it")
        local blueprints = {}
        return blueprints
            --        if player ~= nil then
            --            local hotbar = player.get_main_inventory())
            --            if hotbar ~= nil then
            --                for i=1,#hotbar do
            --                    local itemStack = hotbar[i]
            --                    if itemStack and itemStack.valid_for_read and itemStack.type == "blueprint" then
            --                        if  ( type and type == 'empty' and not itemStack.is_blueprint_setup() )
            --                            or  ( type and type == 'setup' and itemStack.is_blueprint_setup() )
            --                            or  not type then
            --                            table.insert(blueprints, itemStack)
            --                        end
            --                    end
            --                end
            --            end
            --        end
            --        return blueprints
    end,

    readBlueprint = function(_, farl, player)
        local status, err = pcall(function()
            local bp = {}
            local cursor = player.cursor_stack.valid_for_read and player.cursor_stack
            local read_from_cursor, count
            local read_blueprints = farl.read_blueprints
            if cursor and cursor.is_blueprint and cursor.is_blueprint_setup() then
                table.insert(bp, cursor)
                read_from_cursor = true
                read_blueprints = read_blueprints + 1
            elseif cursor and cursor.is_blueprint_book then
                bp, count =  getBlueprints(cursor, 'setup')
                read_from_cursor = true
                read_blueprints = read_blueprints + count
            else
                farl:print("Cant read from the quickbar currently. Click the Read button with a blueprint or a blueprint book.")
                farl:print("(Reading from the quickbar will be reenabled as soon as the API allows it")
                return
                --bp = GUI.findBlueprintsInHotbar(player, 'setup')
            end
            if #bp > 2 then
                farl:print({"msg-error-too-many-bps"})
                return
            end
            if #bp == 0 then
                farl:print({ "msg-error-no-blueprint" })
                return
            end
            local was_active = farl.active
            farl:deactivate()
            farl:parseBlueprints(bp)
            if not read_from_cursor or read_blueprints == 2 then
                read_blueprints = 0
                GUI.destroyGui(player)
                GUI.createGui(player)
            end
            if was_active then
                farl:activate()
            end
            farl.read_blueprints = read_blueprints
            return
        end)
        if not status then
            debugDump("Error: "..err,true)
        end
    end,

    clearBlueprints = function(_, farl, player)
        local psettings = Settings.loadByPlayer(player)
        psettings.bp = {diagonal=defaultsDiagonal, straight=defaultsStraight}
        psettings.activeBP = psettings.bp
        farl:print({"msg-bp-cleared"})
        GUI.destroyGui(player)
        GUI.createGui(player)
    end,

    create_concrete_vertical = function(_, farl, player)
        GUI.createBlueprint(defaults_concrete_vert,farl,player)
    end,

    create_concrete_diagonal = function(_, farl, player)
        GUI.createBlueprint(defaults_concrete_diag,farl,player)
    end,

    print_statistics = function(event, farl, player)
        if player.valid then
            local stats = global.statistics[player.force.name]
            player.print({"stg-statistics"})
            player.print({"text-created-entities"})
            for n,c in pairs(stats.created) do
                local proto = game.entity_prototypes[n] or game.item_prototypes[n] or false
                if proto then
                    player.print({"",proto.localised_name, ": "..c})
                else
                    player.print(n..": "..c)
                end
            end
            player.print({"text-removed-entities"})
            for n,c in pairs(stats.removed) do
                local proto = game.entity_prototypes[n] or game.item_prototypes[n] or false
                if proto then
                    player.print({"",proto.localised_name, ": "..c})
                else
                    player.print(n..": "..c)
                end
            end
            GUI.toggleSettingsWindow(event, farl, player)
        end
    end,

    createBlueprint = function(bp_table, farl, player)
        local cursor = player.cursor_stack.valid_for_read and player.cursor_stack
        local blueprints = {}
        if cursor and cursor.type == "blueprint" then
            table.insert(blueprints, cursor)
        else
            farl:print("Click this button with an empty blueprint")
            --blueprints = GUI.findBlueprintsInHotbar(player, 'empty')
            return
        end
        if #blueprints > 0 then
            local bp = blueprints[1]
            bp.set_blueprint_entities(bp_table.entities)
            bp.set_blueprint_tiles(bp_table.tiles)
            local icons = {[1]={index = 1, signal={name = "rail", type="item"}},[2]={index = 2, signal={name = "farl", type="item"}}}
            bp.blueprint_icons = icons
        else
            farl:print({"msg-no-empty-blueprint"})
        end
    end,

    saveSettings = function(s, player, farl)
        local psettings = Settings.loadByPlayer(player)
        for i,p in pairs(s) do
            if psettings[i] ~= nil then
                if i == "railType" and p ~= psettings[i] then
                    psettings[i] = p
                    psettings.rail = global.rails_by_index[p]
                    farl:deactivate()
                else
                    psettings[i] = p
                end
            end
        end
    end,

    updateGui = function(farl)
        local guiPlayer = (farl.driver and farl.driver.name ~= "farl_player") and farl.driver or false
        if guiPlayer and mod_gui.get_frame_flow(guiPlayer).farl then
            --GUI.init(farl.driver)
            local farlGui = mod_gui.get_frame_flow(guiPlayer).farl.rows
            farlGui.buttons.start.caption = farl.active and {"text-stop"} or {"text-start"}
            farlGui.buttons.cc.caption = farl.cruise and {"text-stopCC"} or {"text-startCC"}
            if farl.ghostProgress then
                farlGui.pathProgress.visible = true
                farlGui.pathProgress.value = farl.ghostProgress / farl.ghostProgressStart
                farlGui.pathLabel.visible = true
                farlGui.pathLabel.caption = farl.ghostProgress .. "/" .. farl.ghostProgressStart
            else
                farlGui.pathProgress.visible = false
                farlGui.pathLabel.visible = false
                farlGui.pathProgress.value = 0
                farlGui.pathLabel.caption = "-/-"
            end

            if not farl.settings then
                farl.settings = Settings.loadByPlayer(guiPlayer)
            end
            farlGui.bulldozer.state = farl.settings.bulldozer
            farlGui.maintenance.state = farl.settings.maintenance
        end
    end,
}

GUI.callbacks = {
    start = GUI.toggleStart,
    cc = GUI.toggleCC,
    settings = GUI.toggleSettingsWindow,
    debug = GUI.debugInfo,
    blueprint = GUI.readBlueprint,
    bpClear = GUI.clearBlueprints,
    blueprint_concrete_vertical = GUI.create_concrete_vertical,
    blueprint_concrete_diagonal = GUI.create_concrete_diagonal,
    print_statistics = GUI.print_statistics,
    confirmYes = GUI.confirmYes,
    confirmNo = GUI.confirmNo
}