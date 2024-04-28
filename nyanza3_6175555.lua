_DEBUG = true
local color = color
local gradient = require("neverlose/gradient")
local pui = require("neverlose/pui")
local base64 = require("neverlose/base64")
local clipboard = require("neverlose/clipboard")
local ease = require("neverlose/easing")
local vmt_hook = require("neverlose/vmt_hook")
local file = require("neverlose/file")
local ffi = require("ffi")
local callbacks = {}
local them_color = color(255, 255, 255, 255)

local safecall = function(name, report, f)
    return function(...)
        local success, ret = pcall(f, ...)
        if not success then
            local retmessage = "safe call failed [" .. name .. "] -> " .. ret
            if report then
                print(retmessage)
            end
            return false, retmessage
        else
            return ret, success
        end
    end
end

ffi.cdef [[
    typedef int(__fastcall* clantag_t)(const char*, const char*);

    typedef void*(__thiscall* get_client_entity_t)(void*, int);

    typedef struct
    {
        float x;
        float y;
        float z;
    } Vector_t;
    
    typedef struct {
        char  pad_0000[20];
        int m_nOrder; //0x0014
        int m_nSequence; //0x0018
        float m_flPrevCycle; //0x001C
        float m_flWeight; //0x0020
        float m_flWeightDeltaRate; //0x0024
        float m_flPlaybackRate; //0x0028
        float m_flCycle; //0x002C
        void *m_pOwner; //0x0030
        char  pad_0038[4]; //0x0034
    } CAnimationLayer;

    typedef struct
    {
        char    pad0[0x60]; // 0x00
        void* pEntity; // 0x60
        void* pActiveWeapon; // 0x64
        void* pLastActiveWeapon; // 0x68
        float        flLastUpdateTime; // 0x6C
        int            iLastUpdateFrame; // 0x70
        float        flLastUpdateIncrement; // 0x74
        float        flEyeYaw; // 0x78
        float        flEyePitch; // 0x7C
        float        flGoalFeetYaw; // 0x80
        float        flLastFeetYaw; // 0x84
        float        flMoveYaw; // 0x88
        float        flLastMoveYaw; // 0x8C // changes when moving/jumping/hitting ground
        float        flLeanAmount; // 0x90
        char         pad1[0x4]; // 0x94
        float        flFeetCycle; // 0x98 0 to 1
        float        flMoveWeight; // 0x9C 0 to 1
        float        flMoveWeightSmoothed; // 0xA0
        float        flDuckAmount; // 0xA4
        float        flHitGroundCycle; // 0xA8
        float        flRecrouchWeight; // 0xAC
        Vector_t        vecOrigin; // 0xB0
        Vector_t        vecLastOrigin;// 0xBC
        Vector_t        vecVelocity; // 0xC8
        Vector_t        vecVelocityNormalized; // 0xD4
        Vector_t        vecVelocityNormalizedNonZero; // 0xE0
        float        flVelocityLenght2D; // 0xEC
        float        flJumpFallVelocity; // 0xF0
        float        flSpeedNormalized; // 0xF4 // clamped velocity from 0 to 1
        float        flRunningSpeed; // 0xF8
        float        flDuckingSpeed; // 0xFC
        float        flDurationMoving; // 0x100
        float        flDurationStill; // 0x104
        bool        bOnGround; // 0x108
        bool        bHitGroundAnimation; // 0x109
        char    pad2[0x2]; // 0x10A
        float        flNextLowerBodyYawUpdateTime; // 0x10C
        float        flDurationInAir; // 0x110
        float        flLeftGroundHeight; // 0x114
        float        flHitGroundWeight; // 0x118 // from 0 to 1, is 1 when standing
        float        flWalkToRunTransition; // 0x11C // from 0 to 1, doesnt change when walking or crouching, only running
        char    pad3[0x4]; // 0x120
        float        flAffectedFraction; // 0x124 // affected while jumping and running, or when just jumping, 0 to 1
        char    pad4[0x208]; // 0x128
        float        flMinBodyYaw; // 0x330
        float        flMaxBodyYaw; // 0x334
        float        flMinPitch; //0x338
        float        flMaxPitch; // 0x33C
        int            iAnimsetVersion; // 0x340
    } CCSGOPlayerAnimationState_534535_t;
]]

local ffi_handler = {}
ffi_handler.bind_argument = function(fn, arg)
    return function(...)
        return fn(arg, ...)
    end
end

ffi_handler.sigs = {
    set_clantag = {"engine.dll", "53 56 57 8B DA 8B F9 FF 15"}
}

ffi_handler.engine_client = ffi.cast(ffi.typeof("void***"), utils.create_interface("engine.dll", "VEngineClient014"))
ffi_handler.entity_list_003 =
    ffi.cast(ffi.typeof("uintptr_t**"), utils.create_interface("client.dll", "VClientEntityList003"))
ffi_handler.get_entity_address =
    ffi_handler.bind_argument(
    ffi.cast("get_client_entity_t", ffi_handler.entity_list_003[0][3]),
    ffi_handler.entity_list_003
)

ffi_handler.console_is_visible =
    ffi_handler.bind_argument(
    ffi.cast("bool(__thiscall*)(void*)", ffi_handler.engine_client[0][11]),
    ffi_handler.engine_client
)

ffi_handler.raw_hwnd = utils.opcode_scan("engine.dll", "8B 0D ?? ?? ?? ?? 85 C9 74 16 8B 01 8B")
ffi_handler.raw_FlashWindow = utils.opcode_scan("gameoverlayrenderer.dll", "55 8B EC 83 EC 14 8B 45 0C F7")
ffi_handler.raw_insn_jmp_ecx = utils.opcode_scan("gameoverlayrenderer.dll", "FF E1")
ffi_handler.raw_GetForegroundWindow = utils.opcode_scan("gameoverlayrenderer.dll", "FF 15 ?? ?? ?? ?? 3B C6 74")

ffi_handler.hwnd_ptr = ((ffi.cast("uintptr_t***", ffi.cast("uintptr_t", ffi_handler.raw_hwnd) + 2)[0])[0] + 2)
ffi_handler.flash_window = ffi.cast("int(__stdcall*)(uintptr_t, int)", ffi_handler.raw_FlashWindow)
ffi_handler.insn_jmp_ecx = ffi.cast("int(__thiscall*)(uintptr_t)", ffi_handler.raw_insn_jmp_ecx)
ffi_handler.GetForegroundWindow =
    (ffi.cast("uintptr_t**", ffi.cast("uintptr_t", ffi_handler.raw_GetForegroundWindow) + 2)[0])[0]

ffi_handler.set_clantag =
    ffi.cast(
    "int(__fastcall*)(const char*, const char*)",
    utils.opcode_scan(ffi_handler.sigs.set_clantag[1], ffi_handler.sigs.set_clantag[2])
)

callbacks.register = function(event, name, fn)
    events[event]:set(safecall(name, event ~= "shutdown", fn))
end

local ref = {
    doubletap = ui.find("aimbot", "ragebot", "main", "double tap"),
    hideshots = ui.find("Aimbot", "Ragebot", "Main", "Hide Shots"),
    fakeduck = ui.find("Aimbot", "Anti Aim", "Misc", "Fake Duck"),
    delayshot = ui.find("Aimbot", "Ragebot", "Selection", "Global", "Min. Damage", "Delay Shot"),
    pitch = ui.find("Aimbot", "Anti Aim", "Angles", "Pitch"),
    offset = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Offset"),
    yaw = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw"),
    modifier = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw Modifier"),
    moffset = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw Modifier", "Offset"),
    limit1 = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"),
    limit2 = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"),
    freestand = ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding"),
    antistab = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Avoid Backstab"),
    bodyyaw = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"),
    roll = ui.find("Aimbot", "Anti Aim", "Angles", "Extended Angles"),
    rollval = ui.find("Aimbot", "Anti Aim", "Angles", "Extended Angles", "Extended Roll"),
    airstrafe = ui.find("Miscellaneous", "Main", "Movement", "Air Strafe"),
    legmov = ui.find("Aimbot", "Anti Aim", "Misc", "Leg Movement"),
    slowwalk = ui.find("Aimbot", "Anti Aim", "Misc", "Slow Walk"),
    lagoptions = ui.find("Aimbot", "Ragebot", "Main", "Double Tap", "Lag Options"),
    fakelag = ui.find("Aimbot", "Anti Aim", "Fake Lag", "Limit"),
    asoptions = ui.find("Aimbot", "Ragebot", "Accuracy", "Auto Stop", "Options"),
    asdtoptions = ui.find("Aimbot", "Ragebot", "Accuracy", "Auto Stop", "Double Tap")
}

local function color_as_string(r, g, b, a)
    return ("\a%02X%02X%02X%02X"):format(r, g, b, a)
end

-- @locals
local cheat = {
    username = common.get_username(),
    time = "%02d:%02d",
    script = "nyanza :3"
}
-- @region: end

-- @load animation
local loadlua = false
local alpha = 0
local alpha2 = 200
local rendered = false

local script = {
    load = function()
        events.render:set(function()
            if not loadlua then
                if not rendered then
                    alpha = math.min(alpha + 1.7, 200)
                end

                if rendered and math.floor(globals.realtime * 100) - alpha > 700 then
                    alpha = math.max(alpha - 4, 0)
                    alpha2 = math.max(alpha2 - 4, 0)
                end

                if not rendered and alpha == 200 then  -- Добавляем условие для установки rendered в true
                    rendered = true
                end

                if rendered and alpha == 0 then
                    loadlua = true
                end

                local screen_size = render.screen_size()
                render.rect(vector(0, 0), vector(screen_size.x, screen_size.y), color(9, 9, 10, alpha2))
                render.text(1, vector(screen_size.x / 2, screen_size.y / 2 + 35), color(255, 255, 255, alpha), "c", cheat.script)
                render.text(1, vector(screen_size.x / 2, screen_size.y / 2 + 55), color(255, 255, 255, alpha), "c", "Welcome back, " .. cheat.username .. "!")
            end
        end)
    end
}
script.load()
-- @endregion

local element = ""

local aa_lol = {
    delta = 0,
    builder = {
        conditions = {"Standing", "Running", "Slowmotion", "Crouching", "Crouching [CT]", "Sneaking", "Sneaking [CT]", "Air", "Air Duck", "Air Duck [CT]"}
    },
    manual_state = 0,
    state = "NONE"
}

-- @ui
local create_ui = ui["create"]
local get_icon = ui["get_icon"]
local get_style = ui["get_style"]

local house_icon = get_icon("house")
local paw_icon = get_icon("paw")
local link_style = get_style("Link Active"):to_hex()

local create_ui_with_icon = function(icon, text)
    return create_ui(icon .. " Main", "\a" .. link_style .. "" .. get_icon(text))
end

local welcome_main = create_ui_with_icon(house_icon, "heart")
local welcome_main3 = create_ui_with_icon(house_icon, "folder-gear")
local welcome_main2 = create_ui_with_icon(house_icon, "sun")
local functions_tabs = create_ui_with_icon(paw_icon, "moon")
local functions_other = create_ui_with_icon(paw_icon, "feather-pointed")
local functions_extra = create_ui_with_icon(paw_icon, "layer-group")

local active_color = ui.get_style("Link Active"):to_hex()
local color_link = ui.get_style("Link"):to_hex()

local pic_url = "https://i.imgur.com/fbdrvzj.png"
local pic_data = network.get(pic_url)
local pic = render.load_image(pic_data, vector(270, 350))
local welcome_png1 = welcome_main:texture(pic)

function theme_color()
    return "\a" .. ui.get_style("Link Active"):to_hex()
end

local changelog_text = 
    theme_color() ..
    "Last changelog: " ..
    "\aEB6161FF28.04 " ..
    theme_color() ..
    ui.get_icon("caret-down") ..
    " \aEB6161FF[MEOW]\n" ..
    "\aDEFAULT- Now tabs & sidebar are synchronised with the supplied theme in cheat\n" ..
    "- Improved perfomance\n" ..
    "- Added body lean slider\n" ..
    "- Added static legs switch\n" ..
    "- Fixed tabs visibility bugs"

local welc_text = welcome_main3:label(changelog_text)

local icons = {
    ui["get_icon"]("skull"),
    ui["get_icon"]("eye"),
    ui["get_icon"]("screwdriver-wrench")
}

local tabs_select =
    functions_tabs:list(
    "",
    {
        icons[1] .. " Anti Aim",
        icons[2] .. " Visuals",
        icons[3] .. " Miscellaneous"
    }
):set_callback(
    function(tabs)
        tabs:update(element)
        local selected_tab = tabs:get()
        local tab_names = { "Anti Aim", "Visuals", "Miscellaneous" }
        element_color = { "", "", "" }
    
        for i = 1, 3 do
            if selected_tab == i then
                element_color[i] = "\a" .. ui.get_style("Link Active"):to_hex() ..
                                    ui.get_icon("angle-right") .. " " .. icons[i] .. " " .. theme_color() .. tab_names[i]
            else
                element_color[i] = icons[i] .. " " .. tab_names[i]
            end
        end
    
        tabs:update(element_color)
    end)
    
-- antiaim
local presets_list = functions_other:switch(theme_color() .. ui.get_icon("toggle-on") .. " \aDEFAULTEnable", false):set_callback(
    function(boolean_enable)
        antiaim_condition = functions_other
    end
)

elements = {welcome_main = {}, antiaim = {}, visuals = {}, misc = {}}
do
    local function create(element, icon, text)
        return element:switch(theme_color() .. ui.get_icon(icon) .. " \aDEFAULT" .. text, false)
    end

    elements.welcome_main.watermark_opt = welcome_main:combo(theme_color() .. ui.get_icon("align-left") .. " \aDEFAULTWatermark", "LuaSense", "Nyanza", "Nyanza Static")
    elements.welcome_main.coloregele = elements.welcome_main.watermark_opt:create():color_picker("Accent Color", color(255, 0, 0, 255))
    elements.welcome_main.water_pos = welcome_main:combo(theme_color() .. ui.get_icon("angle-right") .. " \aDEFAULTPosition", "Bottom", "Left", "Right")

    elements.antiaim.state_list = functions_other:combo(theme_color() .. ui.get_icon("bars-staggered") .. " \aDEFAULTAA State", aa_lol.builder.conditions)
    elements.antiaim.select_text_fs = create(functions_extra, "google-wallet", "Freestanding")
    elements.antiaim.fs_static = elements.antiaim.select_text_fs:create():listable("Freestand Options:", "Disable Yaw Jitter On Edge", "Static On Edge")
    elements.antiaim.select_text_manual = functions_extra:combo(theme_color() .. ui.get_icon("location-arrow") .. " \aDEFAULTManuals", "At Target", "Left", "Right", "Forward")
    elements.antiaim.manual_aa_static = elements.antiaim.select_text_manual:create():listable("Manual AA Options:", {"Static", "Freestanding Body"}, 2)
    elements.antiaim.select_text_df = functions_extra:selectable(theme_color() .. ui.get_icon("bolt") .. " \aDEFAULTForce Defensive", aa_lol.builder.conditions, #aa_lol.builder.conditions)

    elements.antiaim.anim_changer = functions_extra:switch(theme_color() .. ui.get_icon("lines-leaning") .. " \aDEFAULTAnimations")
    elements.antiaim.anim_options = elements.antiaim.anim_changer:create():listable("Old elements", {"Break legs while in air", "Break legs while landing", "Adjust body lean"}, 3)
    elements.antiaim.anim_slide_opt = elements.antiaim.anim_changer:create():switch("Static")
    elements.antiaim.anim_lean_opt = elements.antiaim.anim_changer:create():slider("Body lean value", 0, 100, 0, 0.01)

    elements.antiaim.select_text_ak = functions_extra:switch(theme_color() .. ui.get_icon("retweet") .. " \aDEFAULTAnti-Backstab")
    elements.antiaim.select_safe_head = functions_extra:selectable(theme_color() .. ui.get_icon("gears") .. " \aDEFAULTSafe-Head", "Air Knife", "High Ground")

    elements.visuals.aspect_ratio = create(functions_other, "desktop", "Aspect Ratio Manager")
    elements.visuals.aspect_ratio_val = elements.visuals.aspect_ratio:create():slider("Aspect Ratio", 50, 300, 0, 0.01)

    elements.visuals.viewmodel_manager = create(functions_other, "expand", "Viewmodel Manager")
    elements.visuals.viewmodel_fov = elements.visuals.viewmodel_manager:create():slider("Viewmodel FOV", -100, 100, 60, 1)
    elements.visuals.viewmodel_x = elements.visuals.viewmodel_manager:create():slider("Viewmodel X", -100, 100, 0, 1)
    elements.visuals.viewmodel_y = elements.visuals.viewmodel_manager:create():slider("Viewmodel Y", -100, 100, 0, 1)
    elements.visuals.viewmodel_z = elements.visuals.viewmodel_manager:create():slider("Viewmodel Z", -100, 100, 0, 1)
    elements.visuals.defbutton = elements.visuals.viewmodel_manager:create():button("Default Viewmodel Config", function()
        elements.visuals.viewmodel_fov:set(56)
        elements.visuals.viewmodel_x:set(1)
        elements.visuals.viewmodel_y:set(0)
        elements.visuals.viewmodel_z:set(1)
    end)

    elements.visuals.scope_overlayceo = create(functions_other, "crosshairs", "Scope overlay")
    elements.visuals.scope_settings = elements.visuals.scope_overlayceo:create():selectable("Settings", {"Spread Dependency", "Inverted", "Rotated", "Disable Animation"})
    elements.visuals.scope_size = elements.visuals.scope_overlayceo:create():slider("Size", 0, 300, 100, 1)
    elements.visuals.scope_gap = elements.visuals.scope_overlayceo:create():slider("Gap", 0, 300, 5, 1)
    elements.visuals.scope_color = elements.visuals.scope_overlayceo:create():color_picker("Accent Color", color(134, 134, 134, 255))

    elements.visuals.min_damage_indikus = create(functions_other, "unity", "Minimum Damage Indicator")

    elements.misc.logencio = create(functions_other, "person-rifle", "Aimbot Logging")
    elements.misc.logenciocolorencio = elements.misc.logencio:create():color_picker("Accent Color", color(255, 0, 0, 255))
    elements.misc.no_fall_dmg = create(functions_other, "person-falling", "No fall damage")
    elements.misc.fast_ladderencio = create(functions_other, "water-ladder", "Fast Ladder")
    elements.misc.fake_latency1 = functions_other:slider(theme_color() .. ui.get_icon("timeline") .. " \aDEFAULTFake Latency", 0, 200, 0, 1)
end

menu_handler = function()
    local element_handling = {}

    -- Функция для создания элементов управления
    local function createSwitch(icon, text, defaultValue)
        return functions_other:switch(theme_color() .. ui.get_icon(icon) .. " \aDEFAULT" .. text, defaultValue)
    end

    local function createCombo(icon, text, options)
        return functions_other:combo(theme_color() .. ui.get_icon(icon) .. " \aDEFAULT" .. text, options)
    end

    local function createSlider(icon, text, min, max, defaultValue)
        return functions_other:slider(theme_color() .. ui.get_icon(icon) .. " \aDEFAULT" .. text, min, max, defaultValue)
    end

    local function createSelectable(icon, text, options)
        return functions_other:selectable(theme_color() .. ui.get_icon(icon) .. " \aDEFAULT" .. text, options)
    end

    for _, v in pairs(aa_lol.builder.conditions) do
        element_handling[v] = {
            enable = createSwitch("gear", "Enable " .. v, false),
            yaw_mode = createCombo("align-left", "Yaw base\n" .. v, {"Static", "Left & Right", "Delayed Yaw"}),
            yaw_center = createSlider("right-left", "Yaw°\n" .. v, -180, 180, 0),
            yaw_left = createSlider("left-long", "Left Yaw°\n" .. v, -180, 180, 0),
            yaw_right = createSlider("right-long", "Right Yaw°\n" .. v, -180, 180, 0),
            aa_speed = createSlider("slack", "Delay Ticks°\n" .. v, 1, 24, 8),
            jitter = createCombo("diagram-project", "Yaw Jitter\n" .. v, {"Disabled", "Center", "Offset", "Spin", "Gravity"}),
            yaw_jitter_ovr = createSlider("right-left", "Jitter°\n" .. v, -180, 180, 0),
            body_yaw = createSwitch("shield", "Body Yaw\n" .. v, false),
            fake_left = createSlider("angle-left", "Left Limit°\n" .. v, 0, 60, 0),
            fake_right = createSlider("angle-right", "Right Limit°\n" .. v, 0, 60, 0),
            fake_options = createSelectable("diagram-successor", "Body Tweaks\n" .. v, {"Avoid Overlap", "Jitter", "Randomize Jitter", "Anti Bruteforce"})
        }
    end

    builder_elements = element_handling
end
menu_handler()

aa_hand_gui = function()
    if presets_list:get() == true then
        ui.find("Aimbot", "Anti Aim", "Angles", "Enabled"):set(true)
    else
        ui.find("Aimbot", "Anti Aim", "Angles", "Enabled"):set(false)
    end
end

function fast_ladder(cmd)
    if elements.misc.fast_ladderencio:get() == true then
        self = entity.get_local_player()

        if self == nil then
            return
        end

        if self.m_MoveType == 9 then
            cmd.view_angles.y = math.floor(cmd.view_angles.y + 0.5)

            if cmd.forwardmove > 0 then
                if cmd.view_angles.x < 45 then
                    cmd.view_angles.x = 89
                    cmd.in_moveright = 1
                    cmd.in_moveleft = 0
                    cmd.in_forward = 0
                    cmd.in_back = 1

                    if cmd.sidemove == 0 then
                        cmd.view_angles.y = cmd.view_angles.y + 90
                    end

                    if cmd.sidemove < 0 then
                        cmd.view_angles.y = cmd.view_angles.y + 150
                    end

                    if cmd.sidemove > 0 then
                        cmd.view_angles.y = cmd.view_angles.y + 30
                    end
                end
            elseif cmd.forwardmove < 0 then
                cmd.view_angles.x = 89
                cmd.in_moveleft = 1
                cmd.in_moveright = 0
                cmd.in_forward = 1
                cmd.in_back = 0

                if cmd.sidemove == 0 then
                    cmd.view_angles.y = cmd.view_angles.y + 90
                end

                if cmd.sidemove > 0 then
                    cmd.view_angles.y = cmd.view_angles.y + 150
                end

                if cmd.sidemove < 0 then
                    cmd.view_angles.y = cmd.view_angles.y + 30
                end
            end
        end
    end
end
fast_ladder(arg)

local animation = {data = {}}

animation.lerp = function(start, end_pos, time)
    if type(start) == "userdata" then
        local color_data = {0, 0, 0, 0}

        for i, color_key in ipairs({"r", "g", "b", "a"}) do
            color_data[i] = animation.lerp(start[color_key], end_pos[color_key], time)
        end

        return color(unpack(color_data))
    end

    return (end_pos - start) * (globals.frametime * time * 175) + start
end

animation.new = function(name, value, time)
    if animation.data[name] == nil then
        animation.data[name] = value
    end

    animation.data[name] = animation.lerp(animation.data[name], value, time)

    return animation.data[name]
end

events.createmove_run:set(
    function(e)
        local lp = entity.get_local_player()

        if elements.visuals.viewmodel_manager:get() then
            local x1, x2, x3, x4 =
                elements.visuals.viewmodel_x:get(),
                elements.visuals.viewmodel_y:get(),
                elements.visuals.viewmodel_z:get(),
                elements.visuals.viewmodel_fov:get()
            cvar.viewmodel_offset_x:float(x1, true)
            cvar.viewmodel_offset_y:float(x2, true)
            cvar.viewmodel_offset_z:float(x3, true)
            cvar.viewmodel_fov:float(x4, true)
        else
            cvar.viewmodel_offset_x:float(1, true)
            cvar.viewmodel_offset_y:float(0, true)
            cvar.viewmodel_offset_z:float(0, true)
            cvar.viewmodel_fov:float(68, true)
        end
    end
)

local aspect = {
    cvar = cvar.r_aspectratio,
    cvar_float_raw = cvar.r_aspectratio.float
}

local function handle_aspect(init)
    local desired_value = animation.new("aspect_ratio", elements.visuals.aspect_ratio_val:get() / 100, 0.1)
    if elements.visuals.aspect_ratio_val:get() == 50 or not elements.visuals.aspect_ratio:get() then
        desired_value = 0
    end
    local actual_value = aspect.cvar_float_raw(aspect.cvar)
    if desired_value ~= actual_value then
        aspect.cvar_float_raw(aspect.cvar, desired_value)
    end
end

aspect_ratio_destroy = function()
    aspect.cvar_float_raw(aspect.cvar, 0)
end

aspect_ratio_ratios = {
    [177] = "16:9",
    [161] = "16:10",
    [150] = "3:2",
    [133] = "4:3",
    [125] = "5:4"
}

for k, v in pairs(aspect_ratio_ratios) do
    elements.visuals.aspect_ratio:create():button(
        v,
        function()
            elements.visuals.aspect_ratio_val:set(k)
        end
    )
end

local animation = {data = {}}

math.difference = function(num1, num2)
    return math.abs(num1 - num2)
end

math.color_lerp = function(start, end_pos, time)
    local frametime = globals.frametime * 100
    time = time * math.min(frametime, (1 / 45) * 100)
    return start:lerp(end_pos, time)
end

math.lerp = function(start, end_pos, time)
    if start == end_pos then
        return end_pos
    end
    local frametime = globals.frametime * 170
    time = time * frametime
    local val = start + (end_pos - start) * time
    if (math.abs(val - end_pos) < 0.01) then
        return end_pos
    end
    return val
end

local animations = {_list = {}}
animations.new = function(name, new_value, speed, init)
    speed = elements.visuals.scope_settings:get("Disable Animation") and (speed or 1) or (speed or 0.095)
    local is_color = type(new_value) == "userdata"
    animations._list[name] = animations._list[name] or (init and init) or (is_color and colors.white or 0)
    local interp_func = is_color and math.color_lerp or math.lerp
    animations._list[name] = interp_func(animations._list[name], new_value, speed)
    return animations._list[name]
end

getmetatable(color()).override = function(c, k, n)
    local cl = c:clone()
    cl[k] = n
    return cl
end

local function scope_overlay_handle()
    local neverlose_refs_scope_overlay = ui.find("Visuals", "World", "Main", "Override Zoom", "Scope Overlay")
    local scope_overlay_enable = elements.visuals.scope_overlayceo:get()
    local spread_dependensy = elements.visuals.scope_settings:get(1)
    local inverted = elements.visuals.scope_settings:get(2)
    local rotated = elements.visuals.scope_settings:get(3)
    local scope_overlay_size = elements.visuals.scope_size:get()
    local scope_overlay_gap = elements.visuals.scope_gap:get()
    local scope_overlay_accent_color = elements.visuals.scope_color:get()

    if scope_overlay_enable then
        neverlose_refs_scope_overlay:override("Remove All")
    else
        neverlose_refs_scope_overlay:override("Remove Overlay")
    end

    local player = entity.get_local_player()
    if player == nil then
        return
    end

    local weapon = player:get_player_weapon()
    if weapon == nil then
        return
    end

    local m_bIsScoped = player.m_bIsScoped

    local main_alpha = scope_overlay_enable and m_bIsScoped and 1 or 0
    local default_alpha = scope_overlay_enable and m_bIsScoped and not inverted and 255 or 0
    local inverted_alpha = scope_overlay_enable and m_bIsScoped and inverted and 255 or 0
    local rotated_alpha = rotated and 45 or 0
    local spread_alpha = spread_dependensy and weapon:get_inaccuracy() * 75 + scope_overlay_gap or scope_overlay_gap
    
    local anim = {
        main = animations.new("scope_overlay", main_alpha),
        default = animations.new("scope_overlay_default", default_alpha),
        inverted = animations.new("scope_overlay_inverted", inverted_alpha),
        rotated = animations.new("scope_overlay_rotated", rotated_alpha),
        spread = animations.new("scope_overlay_spread_dependensy", spread_alpha)
    }    

    local clr = {
        scope_overlay_accent_color:override("a", anim.default),
        scope_overlay_accent_color:override("a", anim.inverted)
    }

    scope_overlay_size = scope_overlay_size * anim.main
    local position = render.screen_size() / 2

    if anim.rotated ~= 0 then
        render.push_rotation(anim.rotated, render.screen_size() / 2)
    end

    local offset = scope_overlay_size + anim.spread

    render.gradient(position - vector(-1, offset), position - vector(0, anim.spread), clr[2], clr[2], clr[1], clr[1])
    render.gradient(position + vector(1, offset), position + vector(0, anim.spread), clr[2], clr[2], clr[1], clr[1])
    render.gradient(position + vector(offset, 1), position + vector(anim.spread, 0), clr[2], clr[1], clr[2], clr[1])
    render.gradient(position - vector(offset, -1), position - vector(anim.spread, 0), clr[2], clr[1], clr[2], clr[1])    

    if anim.rotated ~= 0 then
        render.pop_rotation()
    end
end

events.render:set(
    function(ctx)
        scope_overlay_handle()
    end
)

-- antiaim module
local is_invert = false

local timer = 0
local yaw_1 = 0
local yaw_2 = 0
local destination = 0

local states = {ground_timer = 0, lag_timer = 0}

local function normalize_yaw(yaw)
    return (yaw + 180) % 360 - 180
end

local function calc_angle(local_pos, enemy_pos)
    local ydelta = local_pos.y - enemy_pos.y
    local xdelta = local_pos.x - enemy_pos.x  
    local relativeyaw = math.deg(math.atan2(ydelta, xdelta))
    relativeyaw = (relativeyaw + 180) % 360 - 180 
    if xdelta >= 0 then
        relativeyaw = (relativeyaw + 180) % 360 - 180
    end
    return relativeyaw
end

local jitter = true
local desync = true
local counter = 0

n_cache = {nade = 0, on_ladder = false, holding_nade = false}

local run_command_check = function()
    local me = entity.get_local_player()
    if me == nil then
        return
    end
    n_cache.on_ladder = me.m_MoveType == 9
end

local can_desync = function(cmd, ent, count, vel)
    if ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding"):get() then
        return
    end

    local weapon = ent:get_player_weapon(false)
    if weapon == nil then
        return
    end
    local srv_time = ent.m_nTickBase * globals.tickinterval
    local wpnclass = weapon:get_classname()

    local rules = entity.get_game_rules()

    if rules.m_bFreezePeriod then
        return false
    end

    if n_cache.on_ladder then
        return false
    end
    if cmd.in_use == 1 then
        return false
    end

    return true
end

events.createmove_run:set(
    function()
        run_command_check()
        aa_hand_gui()
    end
)

function aa_lol:custom_desync(left, right, fake, cmd)
    cmd.send_packet = false
    local me = entity.get_local_player()
    local local_player_pos = me:get_origin()
    local enemy = entity.get_threat(false)
    local enemy_pos = enemy and enemy:get_origin() or vector()
    local yaw = calc_angle(local_player_pos, enemy_pos) + 180

    local widefix = false
    if desync and not jitter and cmd.chokedcommands == 1 then
        counter = 4
    end
    if counter > 0 then
        counter = counter - 1
        widefix = true
    end
    if cmd.choked_commands % 2 == 1 then
        jitter = not jitter
        cmd.yaw = jitter and (yaw - left) or (yaw + right)
    else
        desync = not desync
        if cmd.choked_commands > 1 then
            cmd.yaw = jitter and (yaw - left) or (yaw + right)
        else
            cmd.yaw =
                desync and (widefix and (yaw + fake) or (yaw - fake)) or (widefix and (yaw - fake) or (yaw + fake))
        end
    end
    cmd.pitch = 89
end

function states:in_air(a)
    if not a then
        return false
    end

    local b = a.m_fFlags

    local c = bit.band(b, 1) ~= 0

    if c then
        if self.ground_timer == 6 then
            return false
        end

        self.ground_timer = self.ground_timer + 1
    else
        self.ground_timer = 0
    end

    return true
end

function states:is_moving(ent)
    local velocity = ent.m_vecVelocity
    return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) > 2
end

function states:is_crouching(ent)
    local ducked = ent.m_bDucked
    return ducked
end

function states:team_number(ent)
    local team_num = ent.m_iTeamNum
    return team_num
end

local aa = {
    enabled = ui.find("Aimbot", "Anti Aim", "Angles", "Enabled"),
    pitch = ui.find("Aimbot", "Anti Aim", "Angles", "Pitch"),
    yaw = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw"),
    base = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Base"),
    offset = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Offset"),
    backstab = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Avoid Backstab"),
    jitter = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw Modifier"),
    jitter_val = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw Modifier", "Offset"),
    body_yaw = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Inverter"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Freestanding"),
    freestand = ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding", "Disable Yaw Modifiers"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding", "Body Freestanding"),
    def = ui.find("Aimbot", "Ragebot", "Main", "Double Tap", "Lag Options"),
    rolls = ui.find("Aimbot", "Anti Aim", "Angles", "Extended Angles"),
    leg_move = ui.find("Aimbot", "Anti Aim", "Misc", "Leg Movement"),
    slow = ui.find("Aimbot", "Anti Aim", "Misc", "Slow Walk")
}

local distance = function(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
end

local extrapolate = function(player, ticks, x, y, z)
    local vel = player.m_vecVelocity
    local new_x = x + globals.tickinterval * vel.x * ticks
    local new_y = y + globals.tickinterval * vel.y * ticks
    local new_z = z + globals.tickinterval * vel.z * ticks
    return new_x, new_y, new_z
end

local function antibackstabnew()
    local myself = entity.get_local_player()
    local enemy = entity.get_threat(false)
    
    if not myself or not enemy then
        return false
    end
    
    local weapon = enemy:get_player_weapon(false)
    
    if myself and weapon and weapon:get_classname() == "CKnife" then
        local enemyOrigin = enemy:get_origin()
        local myOrigin = myself:get_origin()
        
        if enemyOrigin and myOrigin then
            for ticks = 1, 9 do
                local tex, tey, tez = extrapolate(myself, ticks, myOrigin.x, myOrigin.y, myOrigin.z)
                local distance = distance(enemyOrigin.x, enemyOrigin.y, enemyOrigin.z, tex, tey, tez)
                
                if math.abs(distance) < 230 then
                    return true
                end
            end
        end
    end
    
    return false
end

local hotkeys = {manual_last_pressed = globals.realtime}

function hotkeys:run()
    local fs_value = elements.antiaim.fs_static:get(1)
    local body_fs_value = elements.antiaim.fs_static:get(2)
    
    aa.freestand:set(elements.antiaim.select_text_fs:get())
    ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding", "Disable Yaw Modifiers"):set(fs_value)
    ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding", "Body Freestanding"):set(body_fs_value)
    ui.find("Aimbot", "Anti Aim", "Angles", "Yaw"):set("Backward")
    aa.backstab:set(elements.antiaim.select_text_ak:get())    

    local curtime = globals.realtime

    if hotkeys.manual_last_pressed + 0.2 > curtime then
        return
    end

    if aa_lol.manual_state == 1 or aa_lol.manual_state == 2 or aa_lol.manual_state == 3 then
        aa_lol.manual_state = aa_lol.manual_state
    else
        aa_lol.manual_state = 1
    end
    hotkeys.manual_last_pressed = curtime    
end  

events.createmove:set(hotkeys.run)

local check1, defensive1 = 0, 0

events.createmove_run:set(
    function()
        local tickbase = entity.get_local_player().m_nTickBase
        defensive1 = math.abs(tickbase - check1)
        check1 = math.max(tickbase, check1 or 0)
    end
)

local swap = false

local function preset_manager(left, right, jitter_val, jitter_type)
    local lp = entity.get_local_player()
    local lp_bodyyaw = lp.m_flPoseParameter[11] * 120 - 60
    local yaw = 0

    yaw = lp_bodyyaw <= 0 and right or left

    aa.offset:set(yaw)
    aa.base:set("at target")
    aa.jitter:set(jitter_type ~= nil and jitter_type or "center")
    aa.jitter_val:set(jitter_val)
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"):set(true)
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"):set(58)
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"):set(58)
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options"):set("jitter")
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Freestanding"):disabled(true)
end

local count_ticks = 0

local function split(str, arg)
    local result = {}
    for loop in string.gmatch(str, "([^" .. arg .. "]+)") do
        result[#result + 1] = loop
    end
    return result
end

local function time_to_ticks(val)
    return math.floor(0.5 + (val / globals.tickinterval))
end

local ram = {
    prev_simulation_time = 0,
    defensive = {},
    jit_yaw = 0,
    yaw_add = 0,
    set_lby = false,
    jitter = false,
    jit_add = 0
}

function sim_diff()
    local current_simulation_time = time_to_ticks(entity.get_local_player().m_flSimulationTime)
    local diff = current_simulation_time - ram.prev_simulation_time
    ram.prev_simulation_time = current_simulation_time
    diff_sim = diff
    return diff_sim
end

states = {ground_timer = 0, lag_timer = 0}

function states:in_air(a)
    if not a then
        return false
    end

    local b = a.m_fFlags

    local c = bit.band(b, 1) ~= 0

    if c then
        if self.ground_timer == 6 then
            return false
        end

        self.ground_timer = self.ground_timer + 1
    else
        self.ground_timer = 0
    end

    return true
end

function states:is_moving(ent)
    local velocity = ent.m_vecVelocity
    return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) > 2
end

function states:is_crouching(ent)
    local ducked = ent.m_bDucked
    return ducked
end

function states:team_number(ent)
    local team_num = ent.m_iTeamNum
    return team_num
end

function states:get_state(ent)
    local is_moving = self:is_moving(ent)
    local is_crouching = self:is_crouching(ent)
    local in_air = self:in_air(ent)
    local team_num = ent.m_iTeamNum

    if aa.slow:get() then
        return "Slowmotion"
    end

    if in_air then
        return is_crouching and (team_num == 3 and "Air Duck [CT]" or "Air Duck") or "Air"
    end
    
    if is_crouching and not in_air then
        return is_moving and (team_num == 3 and "Sneaking [CT]" or "Sneaking") or (team_num == 3 and "Crouching [CT]" or "Crouching")
    end
    
    return is_moving and "Running" or "Standing"
end  

events.render:set(
    function(ctx)
        if not globals.is_in_game then
            return
        end
        local watermark_pos = 943
        local lp = entity.get_local_player()
        local screen = render.screen_size()
        local hello2 = ui.get_style("Active Text")
        local clr = elements.welcome_main.coloregele:get()
        local x, y = screen.x / 8, screen.y / 4

        if elements.welcome_main.watermark_opt:get() == "Nyanza" then
            local gradient_animation2 = gradient.text_animate("[meow]", 1, {clr, color(255, 255, 255)})
            local avatar = lp:get_steam_avatar()
            render.texture(avatar, vector(x + 200, y + 775), vector(35, 35), clr)
            local animated_text = gradient_animation2:get_animated_text()
            render.text(1, vector(x + 240, y + 783), clr, "", "build: " .. animated_text .. "↓")            
            render.text(1, vector(x + 240, y + 793), clr, "", (common.get_username() .. ""))
            gradient_animation2:animate()
        elseif elements.welcome_main.watermark_opt:get() == "LuaSense" then
            local gradient_animation = gradient.text_animate("N Y A N Z A", -1, {clr, color(255, 255, 255)})
            local text2 = "[MEOW]"
            local pos_offset =
                elements.welcome_main.water_pos:get() == "Left" and -900 or
                (elements.welcome_main.water_pos:get() == "Right" and 900 or 0)
            local y_offset = elements.welcome_main.water_pos:get() == "Bottom" and screen.y * 0.99 or screen.y * 0.5
            render.text(1, vector(watermark_pos + pos_offset, y_offset), hello2, "cs", gradient_animation:get_animated_text())
            render.text(1, vector(watermark_pos + pos_offset + 50, y_offset), hello2, "cs", " \aEB6161FF" .. text2)
            gradient_animation:animate()
        elseif elements.welcome_main.watermark_opt:get() == "Nyanza Static" then
            render.text(1, vector(x + 687, y + 797), color(255, 255, 255), "", "nyanza.meow")
        end
    end
)

events.render:set(
    function()
        local dmg_override = ui.find("Aimbot", "Ragebot", "Selection", "Min. Damage")
        local screensize = render.screen_size()
        local localplayer = entity.get_local_player()
        if not localplayer or localplayer.m_iHealth <= 0 or not elements.visuals.min_damage_indikus:get() then
            return
        end

        for _, bind in pairs(ui.get_binds()) do
            if bind.name == "Min. Damage" and bind.active then
                render.text(1, vector(screensize.x / 2 + 4, screensize.y / 2 - 15), color(), "", bind.value)
                break
            end
        end
    end
)

local function antiaim(arg)
    local lp = entity.get_local_player()
    if lp == nil then
        return
    end
    
    local state = states:get_state(lp)
    states.state = state
    
    local vel = lp.m_vecVelocity
    local count = globals.tickcount

    if state == "none" then
        return
    end

    local builder = builder_elements[state]

    local manual_state_map = {
        ["Left"] = -90,
        ["Right"] = 90,
        ["Forward"] = 180
    }

    local manual_state = manual_state_map[elements.antiaim.select_text_manual:get()] or 0

    if manual_state ~= 0 then
        elements.antiaim.select_text_fs:set(false)
    end

    hotkeys.manual_state = manual_state
    aa.base:set(manual_state == 0 and "at target" or "local view")

    local lp_pose_param_11 = lp.m_flPoseParameter[11]
    local lp_bodyyaw = lp_pose_param_11 * 120 - 60
    local yaw_left, yaw_right, jit_a = builder.yaw_left:get(), builder.yaw_right:get(), builder.yaw_jitter_ovr:get()    

if globals.choked_commands == 0 then
    count_ticks = (count_ticks + 1) % 8
end

local yaw_mode = builder.yaw_mode:get()

if yaw_mode == "Static" then
    yaw = builder.yaw_center:get()
elseif yaw_mode == "Left & Right" then
    if globals.choked_commands ~= 0 then
        yaw = lp_bodyyaw <= 0 and yaw_right or yaw_left
    elseif globals.choked_commands == 0 and rage.exploit:get() < 1 then
        yaw = lp_bodyyaw <= 0 and yaw_right or yaw_left
    else
        local invert_yaw = globals.commandack % builder.aa_speed:get() < (builder.aa_speed:get() / 2)
        yaw = invert_yaw and yaw_left or yaw_right
        ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Inverter"):set(not invert_yaw)
    end
elseif yaw_mode == "Delayed Yaw" and globals.choked_commands == 0 then
    if rage.exploit:get() <= 1 then
        local invert_yaw = globals.commandack % builder.aa_speed:get() < (builder.aa_speed:get() / 2)
        yaw = invert_yaw and yaw_left or yaw_right
        ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options"):set(" ")
        ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Inverter"):set(not invert_yaw)
    end
end

local sign = lp_bodyyaw <= 0 and 1 or -1
local yaw2 = 28 * sign
local yaw3 = 9 * sign
local jitter = jit_a

    local team_num = lp.m_iTeamNum

    local is_fd = ui.find("Aimbot", "Anti Aim", "Misc", "Fake Duck")

    local weapon = lp:get_player_weapon(false)
    if weapon == nil then
        return
    end
    local wpnclass = weapon:get_classname()

    local function height()
        local me = entity.get_local_player()
        local x, y, z = me:get_origin()
        local enemy = entity.get_threat(false)
        local enemy_pos = enemy ~= nil and enemy:get_origin() or vector()
        local lv = me:get_origin().z
        local ov = enemy_pos.z
        return ((lv - 45) > (ov + 0))
    end

    local tickbasee = lp.m_nTickBase

    if presets_list:get() then
        local select_text_df = elements.antiaim.select_text_df
    
        if (select_text_df:get(1) and state == "Standing") or
           (select_text_df:get(2) and state == "Running") or
           (select_text_df:get(3) and state == "Slowmotion") or
           (select_text_df:get(4) and state == "Crouching") or
           (select_text_df:get(5) and state == "Crouching [CT]") or
           (select_text_df:get(6) and state == "Sneaking") or
           (select_text_df:get(7) and state == "Sneaking [CT]") or
           (select_text_df:get(8) and state == "Air") or
           (select_text_df:get(9) and state == "Air Duck") or
           (select_text_df:get(10) and state == "Air Duck [CT]") then
            aa.def:disabled(true)
            aa.def:override("Always on")
        else
            aa.def:override("On peek")
        end

        local weapon = lp:get_player_weapon(false)
        if not weapon then return end
        local wpnclass = weapon:get_classname()
        
        local function set_aa_defaults()
            local aimbot_aa_yaw = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw")
            aa.base:set("at target")
            aa.jitter:set("disabled")
            aa.jitter_val:set(0)
            aimbot_aa_yaw:set(false)
            ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"):set(0)
            ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"):set(0)
        end               
        if antibackstabnew() and elements.antiaim.select_text_ak:get() then
            aa.offset:set(180)
            ref.pitch:set("Down")
            set_aa_defaults()
        elseif elements.antiaim.select_safe_head:get(1) and state == "Air Duck" and wpnclass:find("Knife") or
               elements.antiaim.select_safe_head:get(2) and height() and state == "Air Duck" or
               elements.antiaim.select_safe_head:get(1) and state == "Air Duck [CT]" and wpnclass:find("Knife") or
               elements.antiaim.select_safe_head:get(2) and height() and state == "Air Duck [CT]" then
            aa.offset:set(hotkeys.manual_state)
            ref.pitch:set("Down")
            set_aa_defaults()
        elseif elements.antiaim.select_text_manual:get() ~= "At Target" then
            if elements.antiaim.manual_aa_static:get(1) then
                aa.offset:set(hotkeys.manual_state)
                ref.pitch:set("Down")
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"):set(true)
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"):set(58)
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"):set(58)
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options"):set("disabled")
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Inverter"):set(false)
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"):disabled(true)
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Freestanding"):set("peek fake")         
            else
                aa.offset:set(hotkeys.manual_state)
                aa.jitter:set(builder.jitter:get())
                aa.jitter_val:set(builder.yaw_jitter_ovr:get())
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"):set(builder.body_yaw:get())
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"):set(builder.fake_left:get())
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"):set(builder.fake_right:get())
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options"):set(builder.fake_options:get())
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"):disabled(true)
                ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Freestanding"):set("Off") 
            end
        else
            ref.pitch:set("Down")
            -- fakelag
            aa.base:set("at target")
            aa.offset:set(yaw or (yaw_right and yaw_left))
            if builder.jitter:get() == "Gravity" then
                aa.jitter:set("offset")
                -- Генерация случайного значения в диапазоне от 0 до 5
                local randomValue = math.random(0, 5)
                -- Умножение случайного значения на 1.1
                local scaledRandomValue = randomValue * 1.1
                -- Проверка типа jitter и добавление случайного значения
                if type(jitter) == "number" then
                    aa.jitter_val:set(jitter + scaledRandomValue)
                else
                    -- Обработка случая, когда jitter не является числом
                    print("Ошибка: jitter не является числом.")
                end          
            else
                aa.jitter:set(builder.jitter:get())
                aa.jitter_val:set(builder.yaw_jitter_ovr:get())
            end
            local body_yaw_value = builder.body_yaw:get()
            aa.body_yaw:set(body_yaw_value)
            
            local left_limit_element = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit")
            left_limit_element:set(builder.fake_left:get())
            
            local right_limit_element = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit")
            right_limit_element:set(builder.fake_right:get())
            
            local options_element = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options")
            local yaw_mode = builder.yaw_mode:get()
            if yaw_mode == "Delayed Yaw" then
                options_element:set(rage.exploit:get() < 1 and "" or " ")
            else           
                options_element:set(builder.fake_options:get())
            end           
            local freestanding_element = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Freestanding")
            freestanding_element:set("Off")            
        end
    end
end        

events.createmove:set(antiaim)

no_fall_damage = false

local function trace(length)

    local local_player = entity.get_local_player() -- Получаем локального игрока

    if not local_player then -- Если локальный игрок не найден, возвращаем false (нет препятствий)
        return false
    end

    -- Получаем координаты текущего положения игрока
    local origin = local_player:get_origin()
    local x, y, z = origin.x, origin.y, origin.z

    local fraction_threshold = 1 / 128 -- Устанавливаем пороговое значение для длины луча

    local end_pos = vector() -- Создаем вектор конечной точки луча

    for angle = 0, math.pi * 2, math.pi / 4 do -- Проходим по окружности вокруг игрока и проверяем каждую точку на препятствия
        -- Вычисляем координаты конечной точки луча
        end_pos.x = x + 10 * math.cos(angle)
        end_pos.y = y + 10 * math.sin(angle)
        end_pos.z = z - length

        local trace_result = utils.trace_line(vector(x, y, z), end_pos, self) -- Проверяем луч на пересечение с препятствиями

        if trace_result.fraction < 1 - fraction_threshold then -- Если луч пересекается с препятствием, возвращаем true (есть препятствия)
            return true
        end
    end

    return false -- Если ни одна из точек не встретила препятствий, возвращаем false (нет препятствий)
end

local last_no_fall_damage_state = false

events.createmove_run:set(function()
    local self = entity.get_local_player() -- Получаем локального игрока

    if not self then -- Если игрок не найден, выходим из функции
        return
    end

    local new_no_fall_damage_state = self.m_vecVelocity.z < -500 and not trace(15) -- Определяем, является ли падение игрока потенциально безопасным
    
    if new_no_fall_damage_state ~= last_no_fall_damage_state then -- Если состояние no_fall_damage изменилось, обновляем его
        no_fall_damage = new_no_fall_damage_state
    end
    
    last_no_fall_damage_state = new_no_fall_damage_state -- Обновляем последнее состояние no_fall_damage
end)

events.createmove:set(function(cmd)

    local self = entity.get_local_player() -- Получаем локального игрока

    if not self or self.m_vecVelocity.z >= -500 then -- Проверяем, существует ли локальный игрок или его вертикальная скорость выше -500
        return -- Если игрок не существует или находится в прыжке или падении, выходим из функции
    end

    -- Устанавливаем состояние приседания (duck) в зависимости от состояния no_fall_damage
    cmd.in_duck = (no_fall_damage and elements.misc.no_fall_dmg:get()) and 1 or 0 -- Если no_fall_damage активирован и соответствующий флаг в интерфейсе включен, устанавливаем приседание (duck) в 1, иначе - в 0
end)


local function is_on_ground(cmd)
    return cmd.in_jump == 0
end

local function is_in_air(player)
    return player and bit.band(player.m_fFlags or 0, 1) == 0 or false
end

local function is_crouching(ent)
    return ent and ent.m_bDucked or false
end

local function update_model_breaker(updatePlayer, edx)
    if not elements.antiaim.anim_changer:get() then
        return
    end
    local player = entity.get_local_player()
    if not (player and updatePlayer == player) then
        return
    end
    local state = states:get_state(player)
    local in_air = state == "Air Duck" or state == "Air"
    local localplayer = entity.get_local_player()
    if not localplayer then
        return
    end
    local flags = localplayer.m_fFlags or 0
    local is_crouching = bit.band(flags, bit.lshift(1, 1)) ~= 0
    if elements.antiaim.anim_options:get(1) and is_in_air(localplayer) then
        player.m_flPoseParameter[6] = 1
    end
    local slidewalk_directory = ui.find("aimbot", "anti aim", "misc", "leg movement")
    if elements.antiaim.anim_options:get(2) then
        if slidewalk_directory:get(2) and not is_crouching then
            if elements.antiaim.anim_slide_opt:get() == true then
                player.m_flPoseParameter[0] = 0
            else
                player.m_flPoseParameter[10] = globals.tickcount % 8 > 1 and 1 or 0
            end
        end
    end
    if elements.antiaim.anim_options:get(3) and player.m_vecVelocity:length() > 3 then
        ffi.cast("CAnimationLayer**", ffi.cast("uintptr_t", player[0]) + 0x2990)[0][12].m_flWeight =
            elements.antiaim.anim_lean_opt:get() / 100
    end
end

local function on_createmove(cmd)
    local slidewalk_directory = ui.find("aimbot", "anti aim", "misc", "leg movement")
    if elements.antiaim.anim_options:get(2) then
        slidewalk_directory:set(cmd.command_number % 3 == 0 and "default" or "sliding")
    end
end

local function pre_render()
    local player = entity.get_local_player()
    if player then
        player.m_flPoseParameter[0] = 0
    end
end

local function animate_move_lean(cmd)
    cmd.animate_move_lean = elements.antiaim.anim_options:get(3)
end

events.createmove:set(on_createmove)
events.pre_render:set(pre_render)
callbacks.register("post_update_clientside_animation", "model_breaker", update_model_breaker)
callbacks.register("createmove", "animate_move_lean", animate_move_lean)

local aa = {
    enabled = ui.find("Aimbot", "Anti Aim", "Angles", "Enabled"),
    pitch = ui.find("Aimbot", "Anti Aim", "Angles", "Pitch"),
    yaw = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw"),
    base = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Base"),
    offset = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Offset"),
    backstab = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw", "Avoid Backstab"),
    jitter = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw Modifier"),
    jitter_val = ui.find("Aimbot", "Anti Aim", "Angles", "Yaw Modifier", "Offset"),
    body_yaw = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Inverter"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Left Limit"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Right Limit"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Options"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw", "Freestanding"),
    freestand = ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding", "Disable Yaw Modifiers"),
    ui.find("Aimbot", "Anti Aim", "Angles", "Freestanding", "Body Freestanding"),
    def = ui.find("Aimbot", "Ragebot", "Main", "Double Tap", "Lag Options"),
    rolls = ui.find("Aimbot", "Anti Aim", "Angles", "Extended Angles"),
    leg_move = ui.find("Aimbot", "Anti Aim", "Misc", "Leg Movement"),
    slow = ui.find("Aimbot", "Anti Aim", "Misc", "Slow Walk")
}

local f, int, lerp = string.format, math.floor, function(a, b, w)
        return math.abs(b - a) < 0.01 and b or a + (b - a) * w
    end
local notify, aimbot_logs = {}, {}

-- notify
do
    local items, font, flags, thickness, screen = {}, 1, "cs", 1, render.screen_size()

    function notify:add(text, color, sec)
        sec = sec or 4.0
        table.insert(items, 1, {text = text, time = globals.realtime + sec, color = color, alpha = 0.0})
    end
end

local time = 0

local glob_clr

local reasons = {}
local gui = {}

local hitgroups = {"head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "gear"}

local wpn2act = {
    hegrenade = "Naded",
    inferno = "Burned",
    knife = "Knifed"
}

local function push_notify(text, clr, sec)
    if not elements.misc.logencio:get() == true then
        return
    end

    notify:add(text, clr or elements.welcome_main.coloregele:get(), sec)
end

glob_clr = elements.misc.logenciocolorencio:get():to_hex()

local function console_print(s)
    if not elements.misc.logencio:get() then
        return
    end
    local color2 = elements.misc.logenciocolorencio:get()
    print_raw(f("[%s] %s", "\a" .. color2:to_hex() .. "Nyan\aDEFAULTza", s))
    print_dev(f("[%s] %s", "\a" .. color2:to_hex() .. "Nyan\aDEFAULTza", s))
end

function aimbot_logs:aim_ack(e)
    local ent, reason = e.target, e.state
    if not ent then
        return
    end

    local name, health, spread, backtrack, hitchance = ent:get_name(), ent.m_iHealth, e.spread, e.backtrack, e.hitchance
    local damage, wanted_damage = e.damage, e.wanted_damage
    local hitgroup, wanted_hitgroup = hitgroups[e.hitgroup] or "?", hitgroups[e.wanted_hitgroup] or "?"

    local hex_version = elements.misc.logenciocolorencio:get():to_hex()

    local glob_clr = hex_version

-- hit
if not reason then
    console_print(f("\a%sRegistered \aDEFAULTshot in %s's %s for \a%s%d(%d) \aDEFAULTdamage ( hp: \a%s%d\aDEFAULT | aimed: \a%s%s\aDEFAULT | bt: \a%s%s\aDEFAULT | spread: \a%s%.1f°\aDEFAULT )", glob_clr, name, hitgroup, glob_clr, damage, wanted_damage, glob_clr, health, glob_clr, wanted_hitgroup, glob_clr, backtrack, glob_clr, spread or 0))
    if not reason then
        push_notify(f("Hit \a%s%s\aDEFAULT's %s for \a%s%d\aDEFAULT(%d) [bt: \a%s%s \aDEFAULT- hp: \a%s%d\aDEFAULT]", hex_version, name, hitgroup, glob_clr, damage, wanted_damage, glob_clr, backtrack, glob_clr, health))
        return
    end
end

if reason then
    reason = reasons[reason] or (reason == "prediction error" and "pred.error") or reason
    local con = f("\a%sMissed \aDEFAULTshot in %s's %s due to \a%s%s \aDEFAULT( hc: \a%s%d%%\aDEFAULT | damage: \a%s%d\aDEFAULT | bt: \a%s%s\aDEFAULT", hex_version, name, wanted_hitgroup, glob_clr, reason, glob_clr, hitchance, glob_clr, wanted_damage, glob_clr, backtrack)
    local note = f("\a%sMissed \aDEFAULTshot in \a%s%s\aDEFAULT's %s due to \a%s%s\aDEFAULT(%d%%) [damage: \a%s%d \aDEFAULT bt: \a%s%s\aDEFAULT", hex_version, hex_version, name, wanted_hitgroup, glob_clr, reason, hitchance, glob_clr, wanted_damage, glob_clr, backtrack)
    if spread then con = f("%s | [spread: %.1f\aDEFAULT] )", con, spread) end
        note = f("%s%s", note, spread and f(" spread: \a%s%.1f°\aDEFAULT]", glob_clr, spread) or "]")
        console_print(con)
        push_notify(note)
        return
    end
end

function aimbot_logs:player_hurt(e)
    local me = entity.get_local_player()
    local userid = entity.get(e.userid, true)
    local attacker = entity.get(e.attacker, true)

    local color2 = elements.misc.logenciocolorencio:get()
    glob_clr = color2:to_hex()

    if userid == me or attacker ~= me or wpn2act[e.weapon] == nil then
        return
    end

    local text = f("%s \a%s \aDEFAULTfor \a%s \aDEFAULTdamage (%d health remaining)", wpn2act[e.weapon], userid:get_name():lower(), e.dmg_health, e.health)

    console_print(text)
    push_notify(text)
end

aimbot_logs.gui = gui

local text = ("Welcome to \a" .. glob_clr .. "Nyan \aDEFAULTZa, \a" .. glob_clr .. common.get_username())
push_notify(text)

events.aim_ack:set(
    function(e)
        aimbot_logs:aim_ack(e)
    end
)

events.player_hurt:set(
    function(e)
        aimbot_logs:player_hurt(e)
    end
)

local ctx = {
    clipboard = require("neverlose/clipboard"),
    base64 = require("neverlose/base64"),
    tabs = {["Ragebot"] = functions_other, ["aa"] = functions_extra},
    all_tabs = {},
    create_menu = function(self)
        for k, _ in pairs(self.tabs) do
            table.insert(self.all_tabs, k)
        end
        table.sort(self.all_tabs)

        local group = welcome_main
        self.list = welcome_main2:listable("Tabs", self.all_tabs)
        self.list:set(1, 2)

        local function make_button(icon, text, callback)
            group:button(icon .. " " .. text, callback)
        end

        make_button(
            ui.get_icon("file-export"),
            "Export",
            function()
                local data = {}
                for i = 1, #self.all_tabs do
                    local selected_tabs = self.all_tabs[self.list:get()[i]]
                    if selected_tabs then
                        data[selected_tabs] = self.tabs[selected_tabs]:export()
                    end
                end
                self.clipboard.set(self.base64.encode(json.stringify(data)))
            end
        )

        make_button(
            ui.get_icon("file-import"),
            "Import",
            function()
                local success, converted_data =
                    pcall(
                    function()
                        local data = self.clipboard.get()
                        return json.parse(self.base64.decode(data))
                    end
                )

                if not success then
                    print_error("Your config is broken! Try to copy config again!")
                    print_dev("Your config is broken! Try to copy config again!")
                    return
                end

                for k, v in pairs(converted_data) do
                    local elements = self.tabs[k]
                    for i = 1, #self.all_tabs do
                        if self.all_tabs[self.list:get()[i]] == k then
                            elements:import(v)
                        end
                    end
                end
            end
        )

        make_button(
            ui.get_icon("cloud"),
            "Default Config",
            function()
                local success, converted_data = pcall(function()
                    return json.parse(self.base64.decode("eyJSYWdlYm90Ijoie1wiMTAyMjM5MzQzOFwiOntcIjI3NzY5ODM3MFwiOjU4fSxcIjEwMjY3MDM1NFwiOntcIjI3NzY5ODM3MFwiOjB9LFwiMTA4MjM1NjkyNlwiOntcIjI3NzY5ODM3MFwiOjh9LFwiMTEyOTQzMzEyMFwiOntcIjI1NDI2OTA3N1wiOlt7XCIxNDI3ODU1ODM2XCI6ZmFsc2UsXCIxNzM1NzA2MTgyXCI6MCxcIjE5MjgyMjk2MVwiOjE0MyxcIjE5MzQ5Njk3NFwiOjExMyxcIjIwOTA1MTUwMThcIjowLFwiMjM5OTQ0MDkwNVwiOjAsXCIzMzA3MDY4MzYzXCI6dHJ1ZX1dLFwiMjc3Njk4MzcwXCI6MH0sXCIxMTQ3MjcwNjY3XCI6e1wiMjc3Njk4MzcwXCI6OH0sXCIxMjM2OTEwOTk3XCI6e1wiMjc3Njk4MzcwXCI6NTl9LFwiMTI4NTkzMTc3MVwiOntcIjI3NzY5ODM3MFwiOjR9LFwiMTI5NTU1MTU4OVwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiMTMwMjMyNDAzOFwiOntcIjI3NzY5ODM3MFwiOjJ9LFwiMTMzMjY3NjdcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjEzNTA4NDU1MTJcIjp7XCIyNzc2OTgzNzBcIjo0fSxcIjE0MDUzNjQwNjZcIjp7XCIyNzc2OTgzNzBcIjotMjZ9LFwiMTQxNDExMzgwMFwiOntcIjI3NzY5ODM3MFwiOjJ9LFwiMTQ0MDM2MDMyXCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCIxNDk3NDMwNThcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjE1MDUyMTM3NTBcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjE1MjcwMjU0NzBcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjE1NDMwMTM2MDFcIjp7XCIyNzc2OTgzNzBcIjp0cnVlLFwiNDA1MDQ4MjE1MFwiOntcIjE0Njc0MDc3MjRcIjpudWxsLFwiMzA4MzYwNDIyMFwiOntcIjI3NzY5ODM3MFwiOjQxfSxcIjQxODM0MjQyMDFcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjQxODM0MjQyMDJcIjp7XCIyNzc2OTgzNzBcIjozfSxcIjQxODM0MjQyMDNcIjp7XCIyNzc2OTgzNzBcIjoyfX19LFwiMTU1MjUwNjI0MVwiOntcIjI3NzY5ODM3MFwiOjJ9LFwiMTU3NzAxODE2NVwiOntcIjI3NzY5ODM3MFwiOjQxfSxcIjE1ODQ4MDY0NzdcIjp7XCIyNzc2OTgzNzBcIjo4fSxcIjE2NDc2NzczMVwiOntcIjI3NzY5ODM3MFwiOjh9LFwiMTY2MTkzMDg4NFwiOntcIjI3NzY5ODM3MFwiOi0zMX0sXCIxNzA3NTY1MTMwXCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCIxNzc0MDAyODQ1XCI6e1wiMjc3Njk4MzcwXCI6OH0sXCIxNzg2MDQxMTg3XCI6e1wiMjc3Njk4MzcwXCI6LTI2fSxcIjE3ODkwNjY5MzVcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjE3OTk0MDM5ODVcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjE4MzU4MDA1MzRcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjE4Nzk1NDc1NTJcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjE5MDA3MTQyNzVcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjE5MjAwMjgyOTBcIjp7XCIyNzc2OTgzNzBcIjoxfSxcIjE5OTQwODkzMzFcIjp7XCIyNzc2OTgzNzBcIjo0fSxcIjE5OTkzODMwNzFcIjp7XCIyNzc2OTgzNzBcIjoxfSxcIjIwMjQ2OTI5MzdcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjIwNzU2MzY2MTdcIjp7XCIyNzc2OTgzNzBcIjo0fSxcIjIxNzY0NjE0NDZcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjIxOTAzNDQ3MzNcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjIxOTY3MTU5NTZcIjp7XCIyNzc2OTgzNzBcIjo0fSxcIjIyMDgyMTExMjNcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjIyNTQ1MTQ3OTFcIjp7XCIyNzc2OTgzNzBcIjo0MX0sXCIyMzMxNzAyOTk1XCI6e1wiMjc3Njk4MzcwXCI6MH0sXCIyMzMzNDE1NTUyXCI6e1wiMjc3Njk4MzcwXCI6ZmFsc2V9LFwiMjM1MjUwMDc1OVwiOntcIjI3NzY5ODM3MFwiOjR9LFwiMjM4MjcxOTUyOFwiOntcIjI3NzY5ODM3MFwiOjU1fSxcIjIzODI5MDEwNzRcIjp7XCIyNzc2OTgzNzBcIjo0MX0sXCIyMzk2NjE2NzM2XCI6e1wiMjc3Njk4MzcwXCI6MH0sXCIyMzk5MDc2NTE2XCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCIyNDYyNTYyMjkxXCI6e1wiMjc3Njk4MzcwXCI6NTV9LFwiMjQ3ODk4MTg3MFwiOntcIjI3NzY5ODM3MFwiOjU5fSxcIjI0ODI0MjUzMzVcIjp7XCIyNzc2OTgzNzBcIjo1OX0sXCIyNTEwNzkzNjAzXCI6e1wiMjc3Njk4MzcwXCI6LTJ9LFwiMjU1ODA5OTEyNVwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiMjYyMDU4OTQ2M1wiOntcIjI3NzY5ODM3MFwiOjh9LFwiMjY3MjYxODgyN1wiOntcIjI3NzY5ODM3MFwiOjB9LFwiMjY3Mjc3NzEzN1wiOntcIjI3NzY5ODM3MFwiOjU5fSxcIjI3MjI4MjY2OTZcIjp7XCIyNzc2OTgzNzBcIjozNn0sXCIyNzIzNTI5NDM3XCI6e1wiMjc3Njk4MzcwXCI6NTl9LFwiMjkxMjY1MTE2MVwiOntcIjI3NzY5ODM3MFwiOnRydWUsXCI0MDUwNDgyMTUwXCI6e1wiMjQ3OTA2MjQ1MFwiOntcIjI3NzY5ODM3MFwiOntcIjIwOTAxNTU5MjZcIjp7XCIwXCI6e1wiMjA5MDE1NTkyNlwiOlt7XCIxNzc2NzBcIjoxLjAsXCIxNzc2NzFcIjowLjczNzk5MTI3MzQwMzE2NzcsXCIxNzc2NzZcIjowLjU1MDM3MTQ2ODA2NzE2OTIsXCIxNzc2ODdcIjowLjQ3Njk1NTA1NjE5MDQ5MDd9XX19LFwiMjA5MDUxNTAxOFwiOjB9fX19LFwiMjkzOTA2ODY2NVwiOntcIjI3NzY5ODM3MFwiOjR9LFwiMzA1Mzc2ODc5OVwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiMzA5NDA1MDY0MVwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiMzEwNzkzMzkyOFwiOntcIjI3NzY5ODM3MFwiOjJ9LFwiMzExNDAwNTI3NFwiOntcIjI3NzY5ODM3MFwiOjU5fSxcIjMxNDUxOTE2MDJcIjp7XCIyNzc2OTgzNzBcIjoxfSxcIjMxNDU5Mzk1NlwiOntcIjI3NzY5ODM3MFwiOjU5fSxcIjMxNTg5NjQzODJcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjMxNzI4NDc2NjlcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjMyMjk0NTgwNjJcIjp7XCIyNzc2OTgzNzBcIjo0MX0sXCIzMjYzMjYxMTE2XCI6e1wiMjc3Njk4MzcwXCI6MX0sXCIzMjkzMTk0Nzk3XCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCIzMzA3NjU0ODAxXCI6e1wiMjc3Njk4MzcwXCI6MX0sXCIzMzU0NTUzMjI4XCI6e1wiMjc3Njk4MzcwXCI6OH0sXCIzMzk2NTcxMDY1XCI6e1wiMjc3Njk4MzcwXCI6NTV9LFwiMzQxNTEzNDcxNFwiOntcIjI3NzY5ODM3MFwiOi0yMn0sXCIzNDM3ODYwMDk3XCI6e1wiMjc3Njk4MzcwXCI6MX0sXCIzNDYxNDg0ODA2XCI6e1wiMjc3Njk4MzcwXCI6NTh9LFwiMzQ5ODMwOTI5MFwiOntcIjI3NzY5ODM3MFwiOjR9LFwiMzU2MjgzNzkzOFwiOntcIjI3NzY5ODM3MFwiOjU4fSxcIjM2MDc3NjMzMlwiOntcIjI3NzY5ODM3MFwiOnRydWUsXCI0MDUwNDgyMTUwXCI6e1wiMTkzNDM0NTAwXCI6bnVsbCxcIjE5MzQzNTU5MFwiOm51bGwsXCIxOTM0MzY2ODBcIjpudWxsLFwiMTk0MjY3NzgzXCI6bnVsbCxcIjIwODgyOTUyOTVcIjpudWxsLFwiNDE2NTcyNTc2NFwiOntcIjI3NzY5ODM3MFwiOjEzM319fSxcIjM2MzkzODI1MThcIjp7XCIyNzc2OTgzNzBcIjo4fSxcIjM2ODM0MjU3NlwiOntcIjI3NzY5ODM3MFwiOjB9LFwiMzczNTM4NjAwMFwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiMzc0OTA1NTE4MFwiOntcIjI3NzY5ODM3MFwiOnRydWUsXCI0MDUwNDgyMTUwXCI6e1wiMTkzNDU3NjI5XCI6e1wiMjc3Njk4MzcwXCI6NX0sXCIyMDg5NTc0ODQ4XCI6e1wiMjc3Njk4MzcwXCI6MTk3fSxcIjIzMjg1MTA0NTRcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjI0NzkwNjI0NTBcIjp7XCIyNzc2OTgzNzBcIjp7XCIyMDkwMTU1OTI2XCI6e1wiMFwiOntcIjIwOTAxNTU5MjZcIjpbe1wiMTc3NjcwXCI6MS4wLFwiMTc3NjcxXCI6MC41MjU0OTAyMjQzNjE0MTk3LFwiMTc3Njc2XCI6MC41MjU0OTAyMjQzNjE0MTk3LFwiMTc3Njg3XCI6MC41MjU0OTAyMjQzNjE0MTk3fV19fSxcIjIwOTA1MTUwMThcIjowfX19fSxcIjM3NzU2NjEzXCI6e1wiMjc3Njk4MzcwXCI6MH0sXCIzODAwNzE4MDk0XCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCIzODA2NjcyMjc5XCI6e1wiMjc3Njk4MzcwXCI6NDB9LFwiMzgyMjE0MDIzM1wiOntcIjI3NzY5ODM3MFwiOjB9LFwiMzg5NzU2Mzk4NVwiOntcIjI3NzY5ODM3MFwiOjQ2fSxcIjM5MTU4ODAxMzVcIjp7XCIyNzc2OTgzNzBcIjo1NX0sXCIzOTI0MjA3MjQ0XCI6e1wiMjc3Njk4MzcwXCI6MH0sXCIzOTQwNTE3MTkzXCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCIzOTQzNTU3OTQ0XCI6e1wiMjc3Njk4MzcwXCI6MX0sXCI0MDA0ODc4ODgxXCI6e1wiMjc3Njk4MzcwXCI6MH0sXCI0MDMxNTk0NDY5XCI6e1wiMjc3Njk4MzcwXCI6NTV9LFwiNDA1NjE4MjU5M1wiOntcIjI3NzY5ODM3MFwiOjU5fSxcIjQwOTY1MDgyMTBcIjp7XCIyNzc2OTgzNzBcIjo1OH0sXCI0MTI0NTM1OTYwXCI6e1wiMjc3Njk4MzcwXCI6NDZ9LFwiNDEzNzY1OTExOVwiOntcIjI3NzY5ODM3MFwiOjB9LFwiNDE0NzA0NzI1N1wiOntcIjI3NzY5ODM3MFwiOjQxfSxcIjQxNjMyNTQ5MDdcIjp7XCIyNzc2OTgzNzBcIjoxfSxcIjQxNjUyMTQ4NjNcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjQxOTM1MzQ0NzFcIjp7XCIyNzc2OTgzNzBcIjoyfSxcIjQxOTcwMDU0MzRcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjQyMDg2NzI2OTZcIjp7XCIyNzc2OTgzNzBcIjpmYWxzZX0sXCI0MjExOTYwOTk4XCI6e1wiMjc3Njk4MzcwXCI6MzZ9LFwiNDIzNTk3NTEwMVwiOntcIjI3NzY5ODM3MFwiOjB9LFwiNDI1NzIzNjU5NlwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiNDI3Mjc2NTA4NFwiOntcIjI3NzY5ODM3MFwiOjh9LFwiNDM4OTk3OTQ2XCI6e1wiMjc3Njk4MzcwXCI6OH0sXCI0NDQ3NjIxMzJcIjp7XCIyNzc2OTgzNzBcIjotMjJ9LFwiNDU2OTc4MDI0XCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCI0NjAwMzk3NzJcIjp7XCIyNzc2OTgzNzBcIjo4fSxcIjQ4OTQ5OTQzN1wiOntcIjI3NzY5ODM3MFwiOi0yNn0sXCI1MDk2NzU4NzNcIjp7XCIyNzc2OTgzNzBcIjotMzF9LFwiNTI3NTAxNjJcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjU2NjE3OTg0M1wiOntcIjI3NzY5ODM3MFwiOjF9LFwiNjMxMDkzNTg0XCI6e1wiMjc3Njk4MzcwXCI6MX0sXCI2NDAyMzI2NTZcIjp7XCIyNzc2OTgzNzBcIjotMjJ9LFwiNjQzMjU4NDA0XCI6e1wiMjc3Njk4MzcwXCI6Mn0sXCI2ODAxNzQ4MjZcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjc2OTUzOTc5NVwiOntcIjI3NzY5ODM3MFwiOjB9LFwiNzg4Mzg2NTA4XCI6e1wiMjc3Njk4MzcwXCI6LTM2fSxcIjgzMTE3MDI5MFwiOntcIjI3NzY5ODM3MFwiOi0zMX0sXCI4MzM2NTgxMDRcIjp7XCIyNzc2OTgzNzBcIjo1OX0sXCI4NTU3MjAxMTZcIjp7XCIyNzc2OTgzNzBcIjowfSxcIjg1NjMyMDM1M1wiOntcIjI3NzY5ODM3MFwiOjB9LFwiODY3ODM4MTMzXCI6e1wiMjc3Njk4MzcwXCI6dHJ1ZX0sXCI5MDcwMjM4MjhcIjp7XCIyNzc2OTgzNzBcIjo1NX0sXCI5MTgyMTEzMzlcIjp7XCIyNzc2OTgzNzBcIjp0cnVlfSxcIjkzOTg2MjE3OVwiOntcIjI3NzY5ODM3MFwiOjU5fSxcIjk4ODUwMDM1NFwiOntcIjI3NzY5ODM3MFwiOjB9fSIsImFhIjoie1wiMTAzMTQ1ODRcIjp7XCIyNzc2OTgzNzBcIjp0cnVlLFwiNDA1MDQ4MjE1MFwiOntcIjIxMDcxOTMzNzdcIjp7XCIyNzc2OTgzNzBcIjo2fSxcIjMzNDQ4OTA2NDBcIjp7XCIyNzc2OTgzNzBcIjoxMDB9LFwiMzUyMTQ3NjQ5M1wiOntcIjI3NzY5ODM3MFwiOmZhbHNlfX19LFwiMTYzNzQ3MjU2OVwiOntcIjI3NzY5ODM3MFwiOjB9LFwiMjMxNjQ1NDQ5OFwiOntcIjI3NzY5ODM3MFwiOnRydWV9LFwiMzYyNzQ0ODM2NVwiOntcIjI1NDI2OTA3N1wiOlt7XCIxNDI3ODU1ODM2XCI6ZmFsc2UsXCIxNzM1NzA2MTgyXCI6MCxcIjE5MjgyMjk2MVwiOjEsXCIxOTM0OTY5NzRcIjozNyxcIjIwOTA1MTUwMThcIjowLFwiMjM5OTQ0MDkwNVwiOjAsXCIzMzA3MDY4MzYzXCI6dHJ1ZX0se1wiMTQyNzg1NTgzNlwiOmZhbHNlLFwiMTczNTcwNjE4MlwiOjAsXCIxOTI4MjI5NjFcIjoyLFwiMTkzNDk2OTc0XCI6MzksXCIyMDkwNTE1MDE4XCI6MCxcIjIzOTk0NDA5MDVcIjowLFwiMzMwNzA2ODM2M1wiOnRydWV9LHtcIjE0Mjc4NTU4MzZcIjpmYWxzZSxcIjE3MzU3MDYxODJcIjowLFwiMTkyODIyOTYxXCI6MyxcIjE5MzQ5Njk3NFwiOjM4LFwiMjA5MDUxNTAxOFwiOjAsXCIyMzk5NDQwOTA1XCI6MCxcIjMzMDcwNjgzNjNcIjp0cnVlfV0sXCIyNzc2OTgzNzBcIjowLFwiNDA1MDQ4MjE1MFwiOntcIjI4NjkzNDA4NzVcIjp7XCIyNzc2OTgzNzBcIjozfX19LFwiNDA3OTA2ODI1OVwiOntcIjI1NDI2OTA3N1wiOlt7XCIxNDI3ODU1ODM2XCI6ZmFsc2UsXCIxNzM1NzA2MTgyXCI6ZmFsc2UsXCIxOTI4MjI5NjFcIjp0cnVlLFwiMTkzNDk2OTc0XCI6NCxcIjIwOTA1MTUwMThcIjowLFwiMjM5OTQ0MDkwNVwiOjAsXCIzMzA3MDY4MzYzXCI6dHJ1ZX1dLFwiMjc3Njk4MzcwXCI6ZmFsc2UsXCI0MDUwNDgyMTUwXCI6e1wiMTQ4NjA0OTI1NVwiOntcIjI3NzY5ODM3MFwiOjN9fX0sXCI3OTIyNzc4MzBcIjp7XCIyNzc2OTgzNzBcIjoxMDIxfX0ifQ=="))
                end)
                
                if success then
                    local json_data = converted_data
                    for key, value in pairs(json_data) do
                    end
                else
                    print("Failed to decode and parse JSON data.")
                end                

                if not success then
                    print_error("Your config is broken! Try to copy config again!")
                    print_dev("Your config is broken! Try to copy config again!")
                    return
                end

                for k, v in pairs(converted_data) do
                    local elements = self.tabs[k]
                    for i = 1, #self.all_tabs do
                        if self.all_tabs[self.list:get()[i]] == k then
                            elements:import(v)
                        end
                    end
                end
            end
        )
    end
}

ctx:create_menu()

callbacks.register("render", "aspect_ratio", handle_aspect)
callbacks.register("shutdown", "aspect_ratio", aspect_ratio_destroy)

events.render:set(
    function(ctx)
        local gradient_animation =
            gradient.text_animate("Nyanza :3", -1, {ui.get_style("Link Active"), color(0, 0, 0, 100)})
        ui.sidebar(gradient_animation:get_animated_text(), "" .. theme_color() .. "" .. ui.get_icon("paw"))
        gradient_animation:animate()
    end
)

events.createmove_run:set(
    function(e)
        utils.console_exec("sv_maxunlag 0.400")
        local ping = ui.find("Miscellaneous", "Main", "Other", "Fake Latency")
        ping:disabled(true):override(elements.misc.fake_latency1:get())
    end
)

local cvars_to_disable = {
    r_3dsky = 0, r_shadows = 0, cl_csm_static_prop_shadows = 0, cl_csm_shadows = 0,
    cl_csm_world_shadows = 0, cl_foot_contact_shadows = 0, cl_csm_viewmodel_shadows = 0,
    cl_csm_rope_shadows = 0, cl_csm_sprite_shadows = 0, cl_disablefreezecam = 1,
    cl_freezecampanel_position_dynamic = 0, cl_freezecameffects_showholiday = 0,
    cl_showhelp = 0, cl_autohelp = 0, cl_disablehtmlmotd = 1, fog_enable_water_fog = 0,
    gameinstructor_enable = 0, cl_csm_world_shadows_in_viewmodelcascade = 0,
    cl_disable_ragdolls = 1, mod_forcedata = 1, cl_csm_translucent_shadows = 0,
    cl_csm_entity_shadows = 0, violence_hblood = 0, r_drawdecals = 0, r_drawrain = 0,
    r_drawropes = 0, r_drawsprites = 0, dsp_slow_cpu = 1, mat_disable_bloom = 1,
    cl_showerror = 0, r_eyegloss = 0, r_eyemove = 0, r_dynamiclighting = 0,
    r_dynamic = 0, func_break_max_pieces = 0
}

local function set_cvars(fps)
    local value = fps:get() and 0 or 1
    for cvar_name, cvar_value in pairs(cvars_to_disable) do
        cvar[cvar_name]:int(fps:get() and cvar_value or value)
    end
end

local framerate_boost = functions_other:switch("" .. theme_color() .. "" .. ui.get_icon("cat") .. " \aDEFAULTHocok")
framerate_boost:set_callback(set_cvars)
framerate_boost:tooltip("Disabling useless game cvars to make game feel smoother")

local trashtalk = {
    phrases = {
        kill = {
            {text = {{delay = 2,text = "..."}, {delay = 4,text = "фига ты быстрый"}}},
            {text = {{delay = 1,text = "?"}, {delay = 4,text = "представим что я ничего не видел XDDD"}}},
            {text = {{delay = 3,text = "агрессив?))))"}, {delay = 6,text = "не трясись"}}},
            {text = {{delay = 1,text = "1"}}},
            {text = {{delay = 2,text = "nice aa"}, {delay = 4,text = "u sell?"}}},
            {text = {{delay = 1,text = "1"}, {delay = 2,text = "долбоёб"}}},
            {text = {{delay = 2,text = "ХАВХЫАХЫАХВЫХАЫВАХХАХА"}, {delay = 4,text = "ЭТО ПИЗДЕЦ"}, {delay = 7,text = "ТЫ ЖЕ ГВОРИЛ НЕ БАЙТИШЬСЯ"}}},
            {text = {{delay = 2,text = "1"}, {delay = 4,text = "ну зато со скитом"}, {delay = 7,text = "долбоёбка слабая"}}}
        },
        death = {
            {text = {{delay = 3,text = "агрессив))))"}, {delay = 9,text = "бля я надеюсь ты не думаешь что круто байтишь"}}},
            {text = {{delay = 1,text = "?"}, {delay = 5,text = "ты как убил меня опарыш ебанный"}}},
            {text = {{delay = 2,text = "мдааа"}, {delay = 5,text = "интересно пиздец играть"}, {8,text ="вс фаршмаков ебанных"}}},
            {text = {{delay = 1,text = "ХААХАХАХАХХАХ"}, {delay = 5,text = "еблан?"}}},
            {text = {{delay = 1,text = "ЭТО ПИЗДЕЦ ХХХАВЫХАХЫ"}, {delay = 4,text = "куда ты БЛЯДЬ ОТТЕПАЛСЯ ОПЯТЬ"}}}
        },
        revenge = {
            {text = {{delay = 1.5,text = "1"}, {delay = 3.5,text = "чё щас то не оттепался?"}}},
            {text = {{delay = 1.5,text = "1"}, {delay = 3.5,text = "неудача дружок)))"}}},
            {text = {{delay = 1,text = "1"}}}
        }
    }
}

local previous_number = nil

local function trash_say(event)
    local group = trashtalk.phrases[event]
    if not group then return end

    local number = math.random(#group)
    while number == previous_number and #group > 1 do
        number = math.random(#group)
    end
    previous_number = number

    local selected_group = group[number]
    for _, text_data in ipairs(selected_group.text) do
        if type(text_data.delay) == "number" then
            utils.execute_after(
                text_data.delay,
                function()
                    utils.console_exec('say "' .. text_data.text .. '"')
                end
            )
        else
            print("Invalid delay value:", text_data.delay)
        end
    end
end

local revenge_guy = nil

events.player_death:set(
    function(e)
        if not menu.trashtalk:get() then return end
        
        local me = entity.get_local_player()
        local userid = entity.get(e.userid, true)
        local killer = entity.get(e.attacker, true)
        
        if userid ~= killer and killer == me then
            trash_say("kill")
        elseif userid == me and me ~= killer then
            trash_say("death")
            revenge_guy = killer
        elseif userid == revenge_guy then
            trash_say("revenge")
        end
    end
)

events.round_start:set(
    function()
        revenge_guy = nil
    end
)

menu = {
    trashtalk = functions_other:switch("" .. theme_color() .. "" .. ui.get_icon("comment") .. " \aDEFAULTTrashTalk")
}

local function updateVisibility(alpha, tabs_select_value, presets_list_value, anim_changer_value, scope_overlayceo_value)
    local watermark_visible = alpha == 1
    local presets_list_visible = tabs_select_value == 1 and alpha == 1
    local visuals_visible = tabs_select_value == 2 and alpha == 1
    local misc_visible = tabs_select_value == 3 and alpha == 1
    local watermark_opt_value = elements.welcome_main.watermark_opt:get()
    local watermark_pos_visible = watermark_opt_value == "LuaSense" and alpha == 1

    local aa_elements = {aa.enabled, aa.pitch, aa.jitter, aa.yaw, aa.base, aa.body_yaw, aa.freestand, aa.rolls}
    for _, element in ipairs(aa_elements) do
        element:disabled(true)
    end    

    welcome_png1:visibility(watermark_visible)
    welcome_main2:visibility(false)
    elements.welcome_main.water_pos:visibility(watermark_pos_visible)

    local visual_elements = {
        elements.visuals.min_damage_indikus,
        elements.visuals.viewmodel_manager,
        elements.visuals.viewmodel_fov,
        elements.visuals.viewmodel_x,
        elements.visuals.viewmodel_y,
        elements.visuals.viewmodel_z,
        elements.visuals.defbutton,
        elements.visuals.scope_overlayceo,
        elements.visuals.scope_color,
        elements.visuals.scope_gap,
        elements.visuals.scope_size,
    }

    for _, element in ipairs(visual_elements) do
        element:visibility(visuals_visible)
    end

    local misc_elements = {
        elements.visuals.aspect_ratio,
        elements.misc.logencio,
        elements.misc.logenciocolorencio,
        elements.misc.no_fall_dmg,
        elements.misc.fast_ladderencio,
        elements.misc.fake_latency1,
        menu.trashtalk,
        framerate_boost,
    }

    for _, element in ipairs(misc_elements) do
        element:visibility(misc_visible)
    end

    for _, v in pairs(aa_lol.builder.conditions) do
        local selected = elements.antiaim.state_list:get() == v
        local elements_aa = builder_elements[v]
        presets_list:visibility(presets_list_visible)
        elements.antiaim.select_text_fs:visibility(presets_list_visible and presets_list_value)
        elements.antiaim.state_list:visibility(presets_list_visible and presets_list_value)
        elements.antiaim.select_text_manual:visibility(presets_list_visible and presets_list_value)
        elements.antiaim.select_text_df:visibility(presets_list_visible and presets_list_value)
        elements.antiaim.anim_changer:visibility(presets_list_visible and presets_list_value)
        elements.antiaim.anim_options:visibility(anim_changer_value and presets_list_visible and presets_list_value)
        elements.antiaim.anim_slide_opt:visibility(anim_changer_value and elements.antiaim.anim_options:get(2) and presets_list_visible and presets_list_value)
        elements.antiaim.anim_lean_opt:visibility(anim_changer_value and elements.antiaim.anim_options:get(3) and presets_list_visible and presets_list_value)
        elements.antiaim.select_text_ak:visibility(presets_list_visible and presets_list_value)
        elements.antiaim.select_safe_head:visibility(presets_list_visible and presets_list_value)

        if presets_list_value then
            elements_aa.enable:visibility(tabs_select_value == 1 and selected and alpha == 1)
            elements_aa.yaw_mode:visibility(tabs_select_value == 1 and selected and alpha == 1 and elements_aa.enable:get())
            elements_aa.yaw_center:visibility(tabs_select_value == 1 and selected and elements_aa.yaw_mode:get() == "Static" and alpha == 1 and elements_aa.enable:get())
            elements_aa.yaw_left:visibility(tabs_select_value == 1 and selected and elements_aa.yaw_mode:get() ~= "Static" and alpha == 1 and elements_aa.enable:get())
            elements_aa.yaw_right:visibility(tabs_select_value == 1 and selected and elements_aa.yaw_mode:get() ~= "Static" and alpha == 1 and elements_aa.enable:get())
            elements_aa.aa_speed:visibility(tabs_select_value == 1 and selected and elements_aa.yaw_mode:get() == "Delayed Yaw" and alpha == 1 and elements_aa.enable:get())
            elements_aa.jitter:visibility(tabs_select_value == 1 and selected and alpha == 1 and elements_aa.enable:get())
            elements_aa.yaw_jitter_ovr:visibility(tabs_select_value == 1 and selected and elements_aa.jitter:get() ~= "Disabled" and alpha == 1 and elements_aa.enable:get())
            elements_aa.body_yaw:visibility(tabs_select_value == 1 and selected and alpha == 1 and elements_aa.enable:get())
            elements_aa.fake_left:visibility(elements_aa.body_yaw:get() and tabs_select_value == 1 and selected and alpha == 1 and elements_aa.enable:get())
            elements_aa.fake_right:visibility(elements_aa.body_yaw:get() and tabs_select_value == 1 and selected and alpha == 1 and elements_aa.enable:get())
            elements_aa.fake_options:visibility(tabs_select_value == 1 and selected and alpha == 1 and elements_aa.enable:get())
        else
            local aa_elements = {
                elements_aa.enable,
                elements_aa.yaw_mode,
                elements_aa.yaw_center,
                elements_aa.yaw_left,
                elements_aa.yaw_right,
                elements_aa.aa_speed,
                elements_aa.fake_left,
                elements_aa.fake_right,
                elements_aa.jitter,
                elements_aa.yaw_jitter_ovr,
                elements_aa.body_yaw,
                elements_aa.fake_options
            }         
            for _, element in ipairs(aa_elements) do
                element:visibility(false)
            end            
        end
    end
end

events["render"]:set(
    function()
        local alpha = ui.get_alpha()
        local tabs_select_value = tabs_select:get()
        local presets_list_value = presets_list:get()
        local anim_changer_value = elements.antiaim.anim_changer:get()
        local scope_overlayceo_value = elements.visuals.scope_overlayceo:get()
        updateVisibility(alpha, tabs_select_value, presets_list_value, anim_changer_value, scope_overlayceo_value)
    end
)