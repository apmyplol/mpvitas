local msg = require "mp.msg"
local utils = require "mp.utils"
local options = require "mp.options"

package.path = mp.command_native { "expand-path", "~~/script-modules/?.lua;" } .. package.path
local ui = require "user-input-module"

local cut_pos = nil
local copy_audio = true
local o = {
    target_dir = "~",
    vcodec = "rawvideo",
    acodec = "pcm_s16le",
    prevf = "",
    vf = "format=yuv444p16$hqvf,scale=in_color_matrix=$matrix,format=bgr24",
    hqvf = "",
    postvf = "",
    opts = "",
    ext = "mp4",
    command_template = [[
        ffmpeg -v warning -y -stats
        -ss $shift -i "$in" -t $duration
        -vf eq=brightness=$br:saturation=$sat:contrast=$con:gamma=$gam
        -c:a copy "$out.$ext"
    ]],
}
options.read_options(o)

local function timestamp(duration)
    local hours = duration / 3600
    local minutes = duration % 3600 / 60
    local seconds = duration % 60
    return string.format("%02d:%02d:%02.03f", hours, minutes, seconds)
end

local function osd(str)
    return mp.osd_message(str, 3)
end

local function get_homedir()
    -- It would be better to do platform detection instead of fallback but
    -- it's not that easy in Lua.
    return os.getenv "HOME" or os.getenv "USERPROFILE" or ""
end

local function log(str)
    local logpath = utils.join_path(o.target_dir:gsub("~", get_homedir()), "mpv_slicing.log")
    f = io.open(logpath, "a")
    f:write(string.format("# %s\n%s\n", os.date "%Y-%m-%d %H:%M:%S", str))
    f:close()
end

local function escape(str)
    -- FIXME(Kagami): This escaping is NOT enough, see e.g.
    -- https://stackoverflow.com/a/31413730
    -- Consider using `utils.subprocess` instead.
    return str:gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function trim(str)
    return str:gsub("^%s+", ""):gsub("%s+$", "")
end

local function get_csp()
    local csp = mp.get_property "colormatrix"
    if csp == "bt.601" then
        return "bt601"
    elseif csp == "bt.709" then
        return "bt709"
    elseif csp == "smpte-240m" then
        return "smpte240m"
    else
        local err = "Unknown colorspace: " .. csp
        osd(err)
        error(err)
    end
end

local fname_input = ""

local function cut(shift, endpos)
    local cmd = trim(o.command_template:gsub("%s+", " "))
    local inpath = escape(utils.join_path(utils.getcwd(), mp.get_property "stream-path"))
    -- local outpath = escape(utils.join_path(
    --     o.target_dir:gsub("~", get_homedir()),
    --     "mpv_tmp/",
    --     fname_input))
    local outpath = os.getenv "HOME" .. "/mpv_tmp/" .. fname_input
    osd(outpath)

    -- local con = mp.get_property_native("contrast")
    local br = mp.get_property_native("brightness")/100
    local con = 1
    local sat = 1
    local gam = 1
    -- TODO: gamma ∈[0.1, 10] standart ist 1 und sat ∈[0, 3] default ist 1
    -- sind sehr weird
    -- local sat = mp.get_property_native("saturation")/300
    -- local gam = mp.get_property_native("gamma")/100
    print(con, br, sat, gam)

    cmd = cmd:gsub("$shift", shift)
    cmd = cmd:gsub("$duration", endpos - shift)
    cmd = cmd:gsub("$vcodec", o.vcodec)
    cmd = cmd:gsub("$acodec", o.acodec)
    cmd = cmd:gsub("$audio", copy_audio and "" or "-an")
    cmd = cmd:gsub("$prevf", o.prevf)
    cmd = cmd:gsub("$vf", o.vf)
    -- use same contrast, brightness, saturation and gamma as in mpv
    cmd = cmd:gsub("$con", con)
    cmd = cmd:gsub("$br", br)
    cmd = cmd:gsub("$sat", sat)
    cmd = cmd:gsub("$gam", gam)

    cmd = cmd:gsub("$hqvf", o.hqvf)
    cmd = cmd:gsub("$postvf", o.postvf)
    cmd = cmd:gsub("$matrix", get_csp())
    cmd = cmd:gsub("$opts", o.opts)
    -- Beware that input/out filename may contain replacing patterns.
    cmd = cmd:gsub("$ext", o.ext)
    cmd = cmd:gsub("$out", outpath)
    cmd = cmd:gsub("$in", inpath, 1)

    msg.info(cmd)
    log(cmd)
    os.execute(cmd)
end

local function get_input(shift, endpos)
    local get_user_input = ui.get_user_input

    get_user_input(function(inp)
        if inp == nil then
          return
        end
        fname_input = inp
        cut(shift, endpos)
    end, {
        text = "filename",
        replace = true,
    })
end

local function toggle_mark()
    local pos = mp.get_property_number "time-pos"
    if cut_pos then
        local shift, endpos = cut_pos, pos
        if shift > endpos then
            shift, endpos = endpos, shift
        end
        if shift == endpos then
            osd "Cut fragment is empty"
        else
            cut_pos = nil
            osd(string.format("Cut fragment: %s - %s", timestamp(shift), timestamp(endpos)))
            get_input(shift, endpos)
        end
    else
        cut_pos = pos
        osd(string.format("Marked %s as start position", timestamp(pos)))
    end
end

local function toggle_audio()
    copy_audio = not copy_audio
    osd("Audio capturing is " .. (copy_audio and "enabled" or "disabled"))
end

mp.add_key_binding(nil, "slicing_mark", toggle_mark)
mp.add_key_binding(nil, "slicing_audio", toggle_audio)
