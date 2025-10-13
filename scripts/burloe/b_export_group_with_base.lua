--[[
Export Base Combination

Description:
Exports every layer in groups with a selected base layer.

Usage: For each top-level group, choose one layer as base. The script will
save one file per other layer in the same group with both base+layer visible.
REQUIRES top-level groups to function.

? Personal version of Gaspi's original script by Burloe. Specifically tailored for my personal projects. Added functionality:
    * Settings Presets - Combobox with preset for specific files:
        * Seeds: 
            * Path: assets/items/seeds
            * Output filename format: '{{layername}} Seeds'
            * Format: .png
            * Scale: 1
            * Exclude layers: true _
            * Ignore Empty Layer: true
        * NYI ItemIcons
-- ]]

-- Import main helpers (Dirname, HideLayers, RestoreLayersVisibility, etc.)
local err = dofile("b_main.lua")
if err ~= 0 then return err end

-- Collect top-level groups
local groups = {}
for _, l in ipairs(Sprite.layers) do
    if l.isGroup then table.insert(groups, l) end
end

if #groups == 0 then
    local dlg = MsgDialog("No groups", "No top-level groups found in the sprite.")
    dlg:show()
    return 0
end

-- Reverse table in-place so groups iterate in the opposite order
local function reverseTable(t)
    for i = 1, math.floor(#t / 2) do
        t[i], t[#t - i + 1] = t[#t - i + 1], t[i]
    end
end
reverseTable(groups)

-- Build dialog
local dlg = Dialog("Export Group with Base Layer")
dlg:file{
    id = "directory",
    label = "Output directory:",
    filename = Sprite.filename,
    open = false
}
dlg:entry{
    id = "out_filename",
    label = "Output filename format:",
    text = "{groupname}_{layername}"
}
dlg:combobox{
    id = "format",
    label = "Format:",
    options = {"png","gif","jpg"},
    option = "png"
}
dlg:slider{
    id = "scale",
    label = "Scale:",
    min = 1,
    max = 10,
    value = 1
}
dlg:check{
    id = "save", 
    label = "Save Sprite", 
    selected = false
}

-- Exclude layers option + prefix entry (entry hidden initially)
dlg:check{
    id = "exclude",
    label = "Exclude layers",
    selected = false,
    onclick = function()
        dlg:modify{ id = "prefix_info", visible = dlg.data.exclude }
        dlg:modify{ id = "exclude_prefix", visible = dlg.data.exclude }
    end
}
dlg:label{
    id = "prefix_info",
    text = "Layers named with prefix are excluded when exporting.",
    visible = false
}
dlg:entry{
    id = "exclude_prefix",
    label = "Exclude prefix:",
    text = "_",
    visible = false
}
dlg:check{
    id = "ignore_empty", 
    label = "Ignore empty layers", 
    selected = true
}

dlg:separator{}
-- Add Presets combobox (placed after all other fields so onclick can modify them)
dlg:combobox{
    id = "presets",
    label = "Preset:",
    options = { "None", "Crops", "Seeds" },
    option = "None",
    onchange = function()
        local p = dlg.data.presets
        if p == "Seeds" then
            dlg:modify{ id = "directory", filename = "C:\\users\\Tomni\\OneDrive\\1. Godot\\eldergrowth\\Assets\\Items\\item_Icons\\seeds" }
            dlg:modify{ id = "out_filename", text = "{layername} Seeds" }
            dlg:modify{ id = "format", option = "png" }
            dlg:modify{ id = "scale", value = 1 }
            dlg:modify{ id = "exclude", selected = true }
            dlg:modify{ id = "prefix_info", visible = true }
            dlg:modify{ id = "exclude_prefix", visible = true, text = "_" }
            dlg:modify{ id = "ignore_empty", selected = true }
        elseif p == "Crops" then
            dlg:modify{ id = "directory", filename = "C:\\users\\Tomni\\OneDrive\\1. Godot\\eldergrowth\\Assets\\Items\\item_Icons\\crops" }
            dlg:modify{ id = "out_filename", text = "{layername}" }
            dlg:modify{ id = "format", option = "png" }
            dlg:modify{ id = "scale", value = 1 }
            dlg:modify{ id = "exclude", selected = true }
            dlg:modify{ id = "prefix_info", visible = true }
            dlg:modify{ id = "exclude_prefix", visible = true, text = "_" }
            dlg:modify{ id = "ignore_empty", selected = true }
        else
            -- None: do not change fields
        end
    end
}
dlg:separator{}
dlg:label{ id = "base_label", text = "Choose Base Layer" }

-- For each group add a combobox of its immediate children (non-group and group layers)
local combo_ids = {}
for i, g in ipairs(groups) do
    local options = {"None - Ignored"}
    for _, child in ipairs(g.layers) do
        table.insert(options, child.name)
    end
    local id = "base_group_" .. i
    combo_ids[i] = {id=id, group=g}
    dlg:combobox{
        id = id,
        label = ("Group: %s"):format(g.name),
        options = options,
        option = "None"
    }
end

dlg:button{id = "ok", text = "Export"}
dlg:button{id = "cancel", text = "Cancel", onclick = function() dlg:close() end}
dlg:show()

if not dlg.data.ok then return 0 end

-- resolve output path
local output_path = Dirname(dlg.data.directory)
if not output_path then
    local d = MsgDialog("Error", "No output directory specified.")
    d:show()
    return 1
end

-- prepare scale
Sprite:resize(Sprite.width * dlg.data.scale, Sprite.height * dlg.data.scale)
local saved_vis = HideLayers(Sprite)

local exported = 0
local ignored_groups = 0
local ignored_group_names = {}
local fmt = dlg.data.format

-- Build filename-safe string
local function safeName(s) return s:gsub("[/\\:%%\"%?%*<>|]", "_") end

-- Return true if a layer has no non-transparent pixels
local function layerIsEmpty(layer)
    for _, cel in ipairs(layer.cels) do
        local img = cel.image
        if img then
            for y = 0, img.height - 1 do
                for x = 0, img.width - 1 do
                    if img:getPixel(x, y) ~= 0 then
                        return false
                    end
                end
            end
        end
    end
    return true
end

local function hasPrefix(name, prefix)
    if not prefix or prefix == "" then return false end
    return string.sub(name, 1, #prefix) == prefix
end

for _, info in ipairs(combo_ids) do
    local g = info.group
    local sel = dlg.data[info.id]

    -- If user selected 'None' -> ignore this group and record its name
    if not sel or sel == "None" then
        ignored_groups = ignored_groups + 1
        table.insert(ignored_group_names, g.name)
        goto continue_group
    end

    -- find base layer object in group
    local base = nil
    for _, child in ipairs(g.layers) do
        if child.name == sel then base = child; break end
    end
    if not base then
        ignored_groups = ignored_groups + 1
        table.insert(ignored_group_names, g.name)
        goto continue_group
    end

    -- if base is empty and user wants to ignore empty layers, skip this group
    if dlg.data.ignore_empty and layerIsEmpty(base) then
        ignored_groups = ignored_groups + 1
        table.insert(ignored_group_names, g.name)
        goto continue_group
    end

    -- if exclude is enabled and base has exclude prefix -> skip this group (don't count as None)
    local exclude_prefix = dlg.data.exclude_prefix or "_"
    if dlg.data.exclude and hasPrefix(base.name, exclude_prefix) then
        ignored_groups = ignored_groups + 1
        table.insert(ignored_group_names, g.name)
        goto continue_group
    end

    -- for each other child in group that is not the base (skip nested groups)
    for _, target in ipairs(g.layers) do
        if target ~= base and not target.isGroup then
            -- skip excluded targets
            if dlg.data.exclude and hasPrefix(target.name, exclude_prefix) then goto continue_target end

            if dlg.data.ignore_empty and layerIsEmpty(target) then goto continue_target end

            -- hide everything in group first
            for _, ch in ipairs(g.layers) do ch.isVisible = false end

            -- make sure the parent group is visible (otherwise children remain hidden)
            g.isVisible = true

            base.isVisible = true
            target.isVisible = true

            -- ensure output dir exists and build filename from format
            local fmt_pattern = dlg.data.out_filename or "{groupname}_{layername}"
            local name_body = fmt_pattern
                :gsub("{groupname}", g.name)
                :gsub("{group}", g.name)
                :gsub("{baselayer}", base.name)
                :gsub("{base}", base.name)
                :gsub("{layername}", target.name)
                :gsub("{target}", target.name)

            local fname = output_path .. "/" .. safeName(name_body) .. "." .. fmt
            os.execute('mkdir "' .. Dirname(fname) .. '"')

            -- save copy
            Sprite:saveCopyAs(fname)
            exported = exported + 1

            -- restore those two to hidden (we'll set vis next loop)
            base.isVisible = false
            target.isVisible = false
            -- hide the group again so subsequent exports start from the same state
            g.isVisible = false
        end
        ::continue_target::
    end

    ::continue_group::
end

-- restore
RestoreLayersVisibility(Sprite, saved_vis)
Sprite:resize(Sprite.width / dlg.data.scale, Sprite.height / dlg.data.scale)

if dlg.data.save then Sprite:saveAs(dlg.data.directory) end

if ignored_groups == 0 then
    MsgDialog("Done", "Exported " .. exported .. " images."):show()
else
    local _h_msg = "Exported " .. exported .. " images."
    local _msg1 = "Groups ignored(no base layer selected):"
    local _msg2 = "    " .. table.concat(ignored_group_names, " - ") .. "."
    CompleteMsg("Done", _h_msg, _msg1, _msg2):show()
end

return 0