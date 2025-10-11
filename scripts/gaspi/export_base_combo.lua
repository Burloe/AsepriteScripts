-- Exports each layer in a group combined with a chosen "base" layer.
-- Usage: For each top-level group, choose one layer as base. The script will
-- save one file per other layer in the same group with both base+layer visible.

-- Import main helpers (Dirname, HideLayers, RestoreLayersVisibility, etc.)
local err = dofile("main.lua")
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

-- Build dialog
local dlg = Dialog("Export with base layers")
dlg:file{
    id = "directory",
    label = "Output directory:",
    filename = Sprite.filename,
    open = false
}
dlg:combobox{
    id = "format",
    label = "Format:",
    options = {"png","gif","jpg"},
    option = "png"
}
dlg:slider{id = "scale", label = "Scale:", min = 1, max = 10, value = 1}
dlg:check{id = "save", label = "Save Sprite", selected = false}
dlg:separator{}
dlg:label{ id = "base_label", text = "Choose Base Layer" }

-- For each group add a combobox of its immediate children (non-group and group layers)
local combo_ids = {}
for i, g in ipairs(groups) do
    local options = {"None"}
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
local fmt = dlg.data.format

-- Helper to build filename-safe string (simple)
local function safeName(s) return s:gsub("[/\\:%%\"%?%*<>|]", "_") end

for _, info in ipairs(combo_ids) do
    local g = info.group
    local sel = dlg.data[info.id]
    if sel and sel ~= "None" then
        -- find base layer object in group
        local base = nil
        for _, child in ipairs(g.layers) do
            if child.name == sel then base = child; break end
        end
        if not base then goto continue_group end

        -- for each other child in group that is not the base (skip nested groups)
        for _, target in ipairs(g.layers) do
            if target ~= base and not target.isGroup then
                -- hide everything in group first
                for _, ch in ipairs(g.layers) do ch.isVisible = false end

                base.isVisible = true
                target.isVisible = true

                -- ensure output dir exists
                local fname = output_path .. "/" .. safeName(g.name) .. "_" .. safeName(base.name) .. "_" .. safeName(target.name) .. "." .. fmt
                os.execute('mkdir "' .. Dirname(fname) .. '"')

                -- save copy
                Sprite:saveCopyAs(fname)
                exported = exported + 1

                -- restore those two to hidden (we'll set vis next loop)
                base.isVisible = false
                target.isVisible = false
            end
        end
    end
    ::continue_group::
end

-- restore
RestoreLayersVisibility(Sprite, saved_vis)
Sprite:resize(Sprite.width / dlg.data.scale, Sprite.height / dlg.data.scale)

if dlg.data.save then Sprite:saveAs(dlg.data.directory) end

local dlg2 = MsgDialog("Done", "Exported " .. exported .. " images.")
dlg2:show()
return 0