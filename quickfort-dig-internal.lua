-- dig-related logic for the quickfort script
--[[
This file designates tiles with the same rules as the in-game UI. For example,
if the tile is hidden, we designate blindly to avoid spoilers. If it's visible,
the shape and material of the target tile affects whether the designation has
any effect.
]]

local _ENV = mkmodule('hack.scripts.quickfort-dig-internal')

local utils = require('utils')
local quickfort_common = require('hack.scripts.quickfort-common-internal')
local log = quickfort_common.log

local function is_construction(tileattrs)
    return tileattrs.material == df.tiletype_material.CONSTRUCTION
end

local function is_floor(tileattrs)
    return tileattrs.shape == df.tiletype_shape.FLOOR or
            tileattrs.shape == df.tiletype_shape.BOULDER or
            tileattrs.shape == df.tiletype_shape.PEBBLES
end

local function is_wall(tileattrs)
    return tileattrs.shape == df.tiletype_shape.WALL
end

local function is_up_stair(tileattrs)
    return tileattrs.shape == df.tiletype_shape.STAIR_UP
end

local function is_removable_shape(tileattrs)
    return tileattrs.shape == df.tiletype_shape.RAMP or
            tileattrs.shape == df.tiletype_shape.STAIR_UP or
            tileattrs.shape == df.tiletype_shape.STAIR_UPDOWN
end

local function is_gatherable(tileattrs)
    return tileattrs.shape == df.tiletype_shape.SHRUB
end

local hard_natural_materials = utils.invert({
    df.tiletype_material.STONE,
    df.tiletype_material.FEATURE,
    df.tiletype_material.LAVA_STONE,
    df.tiletype_material.MINERAL,
    df.tiletype_material.FROZEN_LIQUID,
})

local function is_smoothable_material(tileattrs)
    return hard_natural_materials[tileattrs.material]
end

local function is_markable(flags, occupancy)
    return flags.dig ~= df.tile_dig_designation.No or
            flags.smooth ~= 0 or
            occupancy.carve_track_north ~= 0 or
            occupancy.carve_track_east ~= 0 or
            occupancy.carve_track_south ~= or
            occupancy.carve_track_west ~= 0
end

local values = nil

local values_run = {
    designation_default=df.tile_dig_designation.Default,
    designation_channel=df.tile_dig_designation.Channel,
    designation_upstair=df.tile_dig_designation.UpStair,
    designation_downstair=df.tile_dig_designation.DownStair,
    designation_updownstair=df.tile_dig_designation.UpDownStair,
    designation_ramp=df.tile_dig_designation.Ramp,
    designation_no=df.tile_dig_designation.No,
    smooth=1,
    engrave=2,
    track=1,
}

local values_undo = {
    designation_default=df.tile_dig_designation.No,
    designation_channel=df.tile_dig_designation.No,
    designation_upstair=df.tile_dig_designation.No,
    designation_downstair=df.tile_dig_designation.No,
    designation_updownstair=df.tile_dig_designation.No,
    designation_ramp=df.tile_dig_designation.No,
    designation_no=df.tile_dig_designation.No,
    smooth=0,
    engrave=0,
    track=0,
}

-- these functions return whether a designation was made
local function do_mine(flags, tileattrs)
    if not flags.hidden then
        if is_construction(tileattrs) or not is_wall(tileattrs) then
            return false
        end
    end
    flags.dig = values.designation_default
    return true
end

local function do_channel(flags, tileattrs)
    if not flags.hidden then
        if is_construction(tileattrs) or
                (not is_wall(tileattrs) and not is_floor(tileattrs)) then
            return false
        end
    end
    flags.dig = values.designation_channel
    return true
end

local function do_up_stair(flags, tileattrs)
    if not flags.hidden then
        if is_construction(tileattrs) or not is_wall(tileattrs) then
            return false
        end
    end
    flags.dig = values.designation_upstair
    return true
end

local function do_down_stair(flags, tileattrs)
    if not flags.hidden then
        if is_construction(tileattrs) or
                (not is_wall(tileattrs) and not is_floor(tileattrs)) then
            return false
        end
    end
    flags.dig = values.designation_downstair
    return true
end

local function do_up_down_stair(flags, tileattrs)
    if not flags.hidden then
        if is_construction(tileattrs) or
                (not is_wall(tileattrs) and not is_up_stair(tileattrs)) then
            return false
        end
    end
    if is_up_stair(tileattrs) then
        flags.dig = values.designation_downstair
    else
        flags.dig = values.designation_updownstair
    end
    return true
end

local function do_ramp(flags, tileattrs)
    if not flags.hidden then
        if is_construction(tileattrs) or not is_wall(tileattrs) then
            return false
        end
    end
    flags.dig = values.designation_ramp
    return true
end

local function do_remove_ramps(flags, tileattrs)
    if flags.hidden then return false end
    if is_construction(tileattrs) or not is_removable_shape(tileattrs) then
        return false
    end
    flags.dig = values.designation_default
    return true
end

local function do_gather(flags, tileattrs)
    if flags.hidden then return false end
    if not is_gatherable(tileattrs) then return false end
    flags.dig = values.designation_default
    return true
end

local function do_smooth(flags, tileattrs)
    if flags.hidden then return false end
    if is_construction(tileattrs) or
            (not is_floor(tileattrs) and not is_wall(tileattrs)) or
            not is_smoothable_material(tileattrs) then
        return false
    end
    flags.smooth = values.smooth
    return true
end

local function do_engrave(flags, tileattrs)
    if flags.hidden or
            is_construction(tileattrs) or not is_smooth(tileattrs) then
        return false
    end
    flags.smooth = values.engrave
    return true
end

local function do_fortification(flags, tileattrs)
    if flags.hidden then return false end
    if not is_wall(tileattrs) or not is_smooth(tileattrs) then return false end
    flags.smooth = values.smooth
    return true
end

local function do_track(flags, tileattrs, ctx)
    if flags.hidden or
            not is_floor(tileattrs) or
            is_construction(tileattrs) then
        return false
    end
    local extent_adjacent = ctx.extent_adjacent
    if not extent_adjacent.north and not  extent_adjacent.south and
            not extent_adjacent.east and not extent_adjacent.west then
        print('ambiguous direction for track; please use T(width x height)' ..
              ' syntax (specify both width > 1 and height > 1 for a' ..
              ' track that extends both South and East from this corner')
        return false
    end
    if extent_adjacent.north and extent_adjacent.west then
        -- we're in the "empty" interior of a track extent - tracks can only be
        -- built in lines along the top or left of an extent.
        return false
    end
    -- don't overwrite all directions, only 'or' in the new bits. we could be
    -- adding to a previously-designated track.
    local occupancy = ctx.occupancy
    if extent_adjacent.north then occupancy.carve_track_north = values.track end
    if extent_adjacent.east then occupancy.carve_track_east = values.track end
    if extent_adjacent.south then occupancy.carve_track_south = values.track end
    if extent_adjacent.west then occupancy.carve_track_west = values.track end
    return true
end

local function do_toggle_marker(flags, tileattrs, ctx)
    local occupancy = ctx.occupancy
    if not is_markable(flags, occupancy) then return false end
    occupancy.dig_marked = not occupancy.dig_marked
    return true
end

local function do_remove_designation(flags, tileattrs)
    if flags.dig == df.tile_dig_designation.No then return false end
    flags.dig = values.designation_no
    return true
end

-- add on the 'd' prefix to avoid spelling out reserved words (like 'or')
local designate_switch = {
    dd=do_mine,
    dh=do_channel,
    du=do_up_stair,
    dj=do_down_stair,
    di=do_up_down_stair,
    dr=do_ramp,
    dz=do_remove_ramps,
    dt=do_mine,
    dp=do_gather,
    ds=do_smooth,
    de=do_engrave,
    dF=do_fortification,
    dT=do_track,
    --dv=nil,
    dM=do_toggle_marker,
    --dn=nil,
    dx=do_remove_designation,
    --dbc=nil,
    --dbf=nil,
    --dbm=nil,
    --dbM=nil,
    --dbd=nil,
    --dbD=nil,
    --dbh=nil,
    --dbH=nil,
    --doh=nil,
    --don=nil,
    --dol=nil,
    --dor=nil,
}

local function dig_tile(ctx, code, marker_mode)
    local flags, occupancy = dfhack.maps.getTileFlags(ctx.pos)
    local tileattrs = df.tiletype.attrs[dfhack.maps.getTileType(ctx.pos)]
    ctx.occupancy = occupancy
    if designate_switch[code](flags, tileattrs, ctx) then
        if not is_markable(flags, occupancy) then
            occupancy.dig_marked = false
        elseif code == "dM"
            -- the semantics are a little unclear if the code is M (toggle
            -- marker mode) but m or force_marker_mode is also specified.
            -- for now, or them together and let either turn marker mode on
            occupancy.dig_marked = occupancy.dig_marked or marker_mode
        else
            occupancy.dig_marked = marker_mode
        end
        return true
    end
    return false
end

local function do_run_impl(zlevel, grid)
    local stats = {
        designated={label='Tiles designated', value=0, always=true},
        out_of_bounds={label='Tiles skipped (outside map boundary)', value=0},
        invalid_keys={label='Invalid key sequence', value=0},
    }

    for y, row in pairs(grid) do
        for x, text in pairs(row) do
            local pos = xyz2pos(x, y, zlevel)
            log('designating (%d, %d, %d)="%s"', pos.x, pos.y, pos.z, text)
            -- TODO: we *can* smooth and carve fortifications for map edge tiles
            if not quickfort_common.is_within_bounds(pos) then
                log('coordinates out of bounds; skipping')
                stats.out_of_bounds.value = stats.out_of_bounds.value + 1
                goto continue
            end
            local keys, extent = quickfort_common.parse_cell(text)
            log('parsed cell text: keys="%s", width=%d, height=%d',
                keys, extent.width, extent.height)
            local marker_mode = quickfort_common.settings['force_marker_mode']
            if keys:startswith('m') then
                keys = string.sub(keys, 2)
                marker_mode = true
            end
            local code = 'd'..keys
            if not designate_switch[code] then
                print(string.format('invalid key sequence: "%s"', text))
                stats.invalid_keys.value = stats.invalid_keys.value + 1
                goto continue
            end
            for extent_x=1,extent.width do
                for extent_y=1,extent.height do
                    local extent_pos = xyz2pos(
                        pos.x+extent_x-1,
                        pos.y+extent_y-1,
                        pos.z)
                    local extent_adjacent = {
                        north=extent_y>1,
                        east=extent_x>1,
                        south=extent_y<extent.height,
                        west=extent_x<extent.width,
                    }
                    local ctx = {
                        pos=extent_pos,
                        extent_adjacent=extent_adjacent,
                    }
                    if dig_tile(ctx, code, marker_mode) then
                        stats.designated.value = stats.designated.value + 1
                    end
                end
            end
            ::continue::
        end
    end
    return stats
end

function do_run(zlevel, grid)
    values = values_run
    return do_run_impl(zlevel, grid)
end

function do_orders(zlevel, grid)
    log('nothing to do for blueprints in mode: dig')
    return nil
end

function do_undo(zlevel, grid)
    values = values_undo
    return do_run_impl(zlevel, grid)
end

return _ENV
