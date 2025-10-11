--[[
Description:
A script to save all different layers in different files.

? Personal version of Gaspi's original script by Burloe. Specifically tailored for my personal projects. Added functionality:
    * Exclusion Prefix - Does not export layers with a designated prefix as layer name. [Added as public PR]
    * Space as Group Seperator - Allows Space to be used as group seperator.
    * Settings Presets - Combobox with preset for specific files:
        * ToolSprites - a) Uses reversed layername and layergroup as filename, b) Space as group seperator, c) Export as Spritesheet turned off, d) '_' exclusion prefix.
        * NYI ItemIcons

Made by Gaspi.
   - Itch.io: https://gaspi.itch.io/
   - Twitter: @_Gaspi
Further Contributors:
    - Levy E ("StoneLabs")
    - David Höchtl ("DavidHoechtl")
    - Demonkiller8973
--]]


-- Import main.
local err = dofile("main.lua")
if err ~= 0 then return err end

-- Variable to keep track of the number of layers exported.
local n_layers = 0

-- Function to calculate the bounding box of the non-transparent pixels in a layer
local function calculateBoundingBox(layer)
    local minX, minY, maxX, maxY = nil, nil, nil, nil
    for _, cel in ipairs(layer.cels) do
        local image = cel.image
        local position = cel.position

        for y = 0, image.height - 1 do
            for x = 0, image.width - 1 do
                if image:getPixel(x, y) ~= 0 then -- Non-transparent pixel
                    local pixelX = position.x + x
                    local pixelY = position.y + y
                    if not minX or pixelX < minX then minX = pixelX end
                    if not minY or pixelY < minY then minY = pixelY end
                    if not maxX or pixelX > maxX then maxX = pixelX end
                    if not maxY or pixelY > maxY then maxY = pixelY end
                end
            end
        end
    end
    return Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1)
end

-- Utility: escape a string for Lua patterns
local function escapePattern(s)
    return s:gsub("([^%w])", "%%%1")
end

-- Remove trailing group separator immediately before the extension (e.g. "Name " + "." -> "Name.")
local function removeSepBeforeExtension(name, sep)
    if not sep or sep == "" then return name end
    local esc = escapePattern(sep)
    -- Replace occurrences of sep followed by a dot with just a dot
    return name:gsub(esc .. "%.", ".")
end

-- Exports every layer individually.
local function exportLayers(sprite, root_layer, filename, group_sep, data)
    for _, layer in ipairs(root_layer.layers) do
        local prefix = data.exclusion_prefix or "_"
        -- Skip layer with specified prefix and prefix is not empty
        if data.exclude_prefix and prefix ~= "" and string.sub(layer.name, 1, #prefix) == prefix then
            goto continue
        end
        local filename = filename
        if layer.isGroup then
            -- Recursive for groups.
            local previousVisibility = layer.isVisible
            layer.isVisible = true
            filename = filename:gsub("{layergroups}",
                                     layer.name .. group_sep .. "{layergroups}")
            exportLayers(sprite, layer, filename, group_sep, data)
            layer.isVisible = previousVisibility
        else
            -- Individual layer. Export it.
            layer.isVisible = true
            filename = filename:gsub("{layergroups}", "")
            filename = filename:gsub("{layername}", layer.name)
            filename = removeSepBeforeExtension(filename, group_sep)
            os.execute("mkdir \"" .. Dirname(filename) .. "\"")
            if data.spritesheet then
                local sheettype=SpriteSheetType.HORIZONTAL
                if (data.tagsplit == "To Rows") then
                    sheettype=SpriteSheetType.ROWS
                elseif (data.tagsplit == "To Columns") then
                    sheettype=SpriteSheetType.COLUMNS
                end
                app.command.ExportSpriteSheet{
                    ui=false,
                    askOverwrite=false,
                    type=sheettype,
                    columns=0,
                    rows=0,
                    width=0,
                    height=0,
                    bestFit=false,
                    textureFilename=filename,
                    dataFilename="",
                    dataFormat=SpriteSheetDataFormat.JSON_HASH,
                    borderPadding=0,
                    shapePadding=0,
                    innerPadding=0,
                    trimSprite=data.trimSprite,
                    trim=data.trimCells,
                    trimByGrid=data.trimByGrid,
                    mergeDuplicates=data.mergeDuplicates,
                    extrude=false,
                    openGenerated=false,
                    layer="",
                    tag="",
                    splitLayers=false,
                    splitTags=(data.tagsplit ~= "No"),
                    listLayers=layer,
                    listTags=true,
                    listSlices=true,
                }
            elseif data.trim then -- Trim the layer
                local boundingRect = calculateBoundingBox(layer)
                -- make a selection on the active layer
                app.activeLayer = layer;
                sprite.selection = Selection(boundingRect);
                
                -- create a new sprite from that selection
                app.command.NewSpriteFromSelection()
                
                -- save it as png
                app.command.SaveFile {
                    ui=false,
                    filename=filename
                }
                app.command.CloseFile()
                
                app.activeSprite = layer.sprite  -- Set the active sprite to the current layer's sprite
                sprite.selection = Selection();
            else
                sprite:saveCopyAs(filename)
            end
            layer.isVisible = false
            n_layers = n_layers + 1
        end
        ::continue::
    end
end

-- Exports every layer individually using preset settings.
local function exportWithPreset(sprite, root_layer, preset, filename, group_sep, data)
    for _, layer in ipairs(root_layer.layers) do
        local prefix = data.exclusion_prefix or "_"
        -- Skip layer with specified prefix and prefix is not empty
        if data.exclude_prefix and prefix ~= "" and string.sub(layer.name, 1, #prefix) == prefix then
            goto continue
        end

        local fname = filename
        if layer.isGroup then
            -- Recursive for groups.
            local previousVisibility = layer.isVisible
            layer.isVisible = true
            fname = fname:gsub("{layergroups}", layer.name .. group_sep .. "{layergroups}")
            -- recurse with the same preset and data
            exportWithPreset(sprite, layer, preset, fname, group_sep, data)
            layer.isVisible = previousVisibility
        else
            -- Individual layer. Export it.
            layer.isVisible = true
            fname = fname:gsub("{layergroups}", "")
            fname = fname:gsub("{layername}", layer.name)
            fname = removeSepBeforeExtension(fname, group_sep)
            os.execute("mkdir \"" .. Dirname(fname) .. "\"")

            if data.spritesheet then
                local sheettype = SpriteSheetType.HORIZONTAL
                if (data.tagsplit == "To Rows") then
                    sheettype = SpriteSheetType.ROWS
                elseif (data.tagsplit == "To Columns") then
                    sheettype = SpriteSheetType.COLUMNS
                end
                app.command.ExportSpriteSheet{
                    ui=false,
                    askOverwrite=false,
                    type=sheettype,
                    columns=0,
                    rows=0,
                    width=0,
                    height=0,
                    bestFit=false,
                    textureFilename=fname,
                    dataFilename="",
                    dataFormat=SpriteSheetDataFormat.JSON_HASH,
                    borderPadding=0,
                    shapePadding=0,
                    innerPadding=0,
                    trimSprite=data.trimSprite,
                    trim=data.trimCells,
                    trimByGrid=data.trimByGrid,
                    mergeDuplicates=data.mergeDuplicates,
                    extrude=false,
                    openGenerated=false,
                    layer="",
                    tag="",
                    splitLayers=false,
                    splitTags=(data.tagsplit ~= "No"),
                    listLayers=layer,
                    listTags=true,
                    listSlices=true,
                }
            elseif data.trim then -- Trim the layer
                local boundingRect = calculateBoundingBox(layer)
                if not boundingRect then
                    -- nothing to export for this layer
                    layer.isVisible = false
                    goto continue
                end

                -- make a selection on the active layer
                app.activeLayer = layer
                sprite.selection = Selection(boundingRect)

                -- create a new sprite from that selection
                app.command.NewSpriteFromSelection()

                -- save it as png
                app.command.SaveFile {
                    ui=false,
                    filename=fname
                }
                app.command.CloseFile()

                app.activeSprite = layer.sprite  -- restore active sprite context
                sprite.selection = Selection()
            else
                sprite:saveCopyAs(fname)
            end

            layer.isVisible = false
            n_layers = n_layers + 1
        end
        ::continue::
    end
end



-- Open main dialog.
local dlg = Dialog("Export layers")
dlg:file{
    id = "directory",
    label = "Output directory:",
    filename = Sprite.filename,
    open = false
}
dlg:combobox{
    id = "presets",
    label = 'Presets',
    option = 'None',
    options = {'None', 'ToolSprites'}
}
dlg:entry{
    id = "filename",
    label = "File name format:",
    text = "{layergroups}{layername}"
}
dlg:combobox{
    id = 'format',
    label = 'Export Format:',
    option = 'png',
    options = {'png', 'gif', 'jpg'}
}
dlg:combobox{
    id = 'group_sep',
    label = 'Group separator:',
    option = Sep,
    options = {Sep, '-', '_', " "}
}
dlg:slider{id = 'scale', label = 'Export Scale:', min = 1, max = 10, value = 1}
dlg:check{
    id = "spritesheet",
    label = "Export as spritesheet:",
    selected = true,
    onclick = function()
        dlg:modify{
            id = "trim",
            visible = not dlg.data.spritesheet
        }
        -- Show these options when spritesheet is checked.
        dlg:modify{
            id = "trimSprite",
            visible = dlg.data.spritesheet
        }
        dlg:modify{
            id = "trimCells",
            visible = dlg.data.spritesheet
        }
        dlg:modify{
         id = "mergeDuplicates",
         visible = dlg.data.spritesheet
      }
      dlg:modify{
         id = "tagsplit",
         visible = dlg.data.spritesheet
      }
    end
}
dlg:check{
    id = "trim",
    label = "Trim:",
    selected = false
}
dlg:check{
    id = "trimSprite",
    label = "  Trim Sprite:",
    selected = false,
    visible = false,
    onclick = function()
        dlg:modify{
            id = "trimByGrid",
            visible = dlg.data.trimSprite or dlg.data.trimCells,
        }
    end
}
dlg:check{
    id = "trimCells",
    label = "  Trim Cells:",
    selected = false,
    visible = false,
    onclick = function()
        dlg:modify{
            id = "trimByGrid",
            visible = dlg.data.trimSprite or dlg.data.trimCells,
        }
    end
}
dlg:check{
    id = "trimByGrid",
    label = "  Trim Grid:",
    selected = false,
    visible = false
}
dlg:combobox{ -- Spritesheet export only option
    id = "tagsplit",
    label = "  Split Tags:",
    visible = false,
    option = 'No',
    options = {'No', 'To Rows', 'To Columns'}
}
dlg:check{ -- Spritesheet export only option
    id = "mergeDuplicates",
    label = "  Merge duplicates:",
    selected = false,
    visible = false
}
dlg:check{
    id = "exclude_prefix",
    label = "Exclude layers with prefix",
    selected = true,
    onclick = function()
        dlg:modify{
            id = "exclusion_prefix",
            visible = dlg.data.exclude_prefix
        }
    end
}
dlg:entry{
    id = "exclusion_prefix",
    label = "  Prefix:",
    text = "_",
    visible = true
}
dlg:check{id = "save", label = "Save sprite:", selected = true}
dlg:button{id = "ok", text = "Export"}
dlg:button{id = "cancel", text = "Cancel"}
dlg:show()

if not dlg.data.ok then return 0 end

-- Get path and filename
local output_path = Dirname(dlg.data.directory)
local filename = dlg.data.filename .. "." .. dlg.data.format

if output_path == nil then
    local dlg = MsgDialog("Error", "No output directory was specified.")
    dlg:show()
    return 1
end

local group_sep = dlg.data.group_sep
filename = filename:gsub("{spritename}",
                         RemoveExtension(Basename(Sprite.filename)))
filename = filename:gsub("{groupseparator}", group_sep)

-- Finally, perform everything.
Sprite:resize(Sprite.width * dlg.data.scale, Sprite.height * dlg.data.scale)
local layers_visibility_data = HideLayers(Sprite)

-- Preset settings handling.
if dlg.data.presets == 'None' then
    exportLayers(Sprite, Sprite, output_path .. filename, group_sep, dlg.data)
elseif dlg.data.presets == "ToolSprites" then
    local preset_data = {}
    for k,v in pairs(dlg.data) do preset_data[k] = v end
    preset_data.spritesheet = false
    local preset_filename = output_path .. "{layername} {layergroups}." .. dlg.data.format
    exportWithPreset(Sprite, Sprite, dlg.data.presets, preset_filename, " ", preset_data)
else
    exportLayers(Sprite, Sprite, output_path .. filename, group_sep, dlg.data)
end

RestoreLayersVisibility(Sprite, layers_visibility_data)
Sprite:resize(Sprite.width / dlg.data.scale, Sprite.height / dlg.data.scale)

-- Save the original file if specified
if dlg.data.save then Sprite:saveAs(dlg.data.directory) end

-- Success dialog.
local dlg = MsgDialog("Success!", "Exported " .. n_layers .. " layers.")
dlg:show()

return 0