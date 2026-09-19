-- ============================================================================
-- 1. МЕТАДАННЫЕ И ПОДКЛЮЧЕНИЕ БИБЛИОТЕК
-- ============================================================================

local CURRENT_VERSION = '6.0.0'

script_name('DH')
script_version(CURRENT_VERSION)
script_authors('Deo')

local sampev    = require 'lib.samp.events'
local imgui     = require 'mimgui'
local encoding  = require 'encoding'
local https     = require('ssl.https')
local ffi       = require('ffi')
local faicons   = require('fAwesome6')
local ae        = require 'arizona-events'

encoding.default = 'UTF-8'
local cyr = encoding.CP1251
local u8  = encoding.UTF8

require 'sampfuncs'

-- ============================================================================
-- 2. URL СЕРВЕРА ОБНОВЛЕНИЙ
-- ============================================================================
local RAW_JSON_URL = "https://raw.githubusercontent.com/wowvww/DH-Script/refs/heads/main/update.json"

-- ============================================================================
-- 3. КОНСТАНТЫ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
-- ============================================================================
local VK_C = 0x43
local is_c_pressed = false
local window
local info_window = imgui.new.bool(true)
local feed_items           = {}
local is_checking          = false
local last_feed_update     = 0
local FEED_UPDATE_INTERVAL = 30
local latest_version = nil
local update_url     = nil
local is_updating    = false

local stats_counter = {
    autospawn      = 0,
    superstop      = 0
}

local function generate_path(p)
    return getWorkingDirectory() .. '/' .. p
end

-- ============================================================================
-- 4. РАБОТА С JSON-КОНФИГОМ
-- ============================================================================
do
    local function jsoncfg_save(data, path)
        if doesFileExist(path) then os.remove(path) end
        if type(data) ~= 'table' then return end
        local f = io.open(path, 'a+')
        if not f then return end
        f:write(encodeJson(data))
        f:close()
    end

    local function jsoncfg_load(data, path)
        if doesFileExist(path) then
            local f = io.open(path, 'r')
            if not f then return data end
            local raw = f:read('*a')
            f:close()
            local ok, decoded = pcall(decodeJson, raw)
            if ok and type(decoded) == 'table' then
                return decoded
            end
            return data
        else
            jsoncfg_save(data, path)
            return data
        end
    end

    jsoncfg = {
        save = jsoncfg_save,
        load = jsoncfg_load
    }
end

-- ============================================================================
-- 5. ЗАГРУЗКА И ВАЛИДАЦИЯ НАСТРОЕК
-- ============================================================================
local settings = jsoncfg.load({
    priority = {},
    enabled = false,
    delay = 5,
    last_spawn_dialog = {},
    reconnect_enabled     = false,
    reconnect_delay       = 3,
    reconnect_retry_delay = 5,
    reconnect_use_timeout = true,
    reconnect_timeout     = 8,
    reconnect_on_ban      = false,
    reconnect_delay_banned = 60,
    super_stop_enabled  = false,
    analytics_id = '',
    piar_profiles  = {},
    piar_enabled   = true,
    piar_last_ad   = 0,
    auto_taxes_enabled = false,
    auto_taxes_interval_hours = 1,
    auto_taxes_next_run = 0,
    auto_sport_enabled = false,
}, generate_path('config/DH.json'))

if type(settings.priority) ~= 'table' then settings.priority = {} end
if type(settings.last_spawn_dialog) ~= 'table' then settings.last_spawn_dialog = {} end
if type(settings.enabled) ~= 'boolean' then settings.enabled = false end
if type(settings.delay) ~= 'number' then settings.delay = 5 end
settings.delay = math.floor(math.max(5, math.min(20, settings.delay)))
if type(settings.reconnect_enabled) ~= 'boolean' then settings.reconnect_enabled = false end
if type(settings.reconnect_delay) ~= 'number' then settings.reconnect_delay = 3 end
if type(settings.reconnect_retry_delay) ~= 'number' then settings.reconnect_retry_delay = 5 end
if type(settings.reconnect_use_timeout) ~= 'boolean' then settings.reconnect_use_timeout = true end
if type(settings.reconnect_timeout) ~= 'number' then settings.reconnect_timeout = 8 end
if type(settings.reconnect_on_ban) ~= 'boolean' then settings.reconnect_on_ban = false end
if type(settings.reconnect_delay_banned) ~= 'number' then settings.reconnect_delay_banned = 60 end
if type(settings.super_stop_enabled) ~= 'boolean' then settings.super_stop_enabled = false end
if type(settings.piar_profiles) ~= 'table' then settings.piar_profiles = {} end
if type(settings.piar_enabled) ~= 'boolean' then settings.piar_enabled = true end
if type(settings.piar_last_ad) ~= 'number' then settings.piar_last_ad = 0 end
if type(settings.auto_taxes_enabled) ~= 'boolean' then settings.auto_taxes_enabled = false end
if type(settings.auto_taxes_interval_hours) ~= 'number' then settings.auto_taxes_interval_hours = 1 end
settings.auto_taxes_interval_hours = math.max(1, math.min(168, math.floor(settings.auto_taxes_interval_hours)))
if type(settings.auto_taxes_next_run) ~= 'number' then settings.auto_taxes_next_run = 0 end
if type(settings.auto_sport_enabled) ~= 'boolean' then settings.auto_sport_enabled = false end

local function save_settings()
    jsoncfg.save(settings, generate_path('config/DH.json'))
end

-- ============================================================================
-- 6. АВТООБНОВЛЕНИЕ СКРИПТА И ЛЕНТА НОВОСТЕЙ
-- ============================================================================
function download_update(url)
    if is_updating then return end
    if type(url) ~= 'string' or url == '' then
        sampAddChatMessage(cyr("[DH] Ссылка на обновление недоступна."), 0xFF0000)
        return
    end
    is_updating = true
    sampAddChatMessage(cyr("[DH] Скачивание обновления..."), 0xffcccccc)
    lua_thread.create(function()
        local ok_req, result, status = pcall(https.request, url)
        if not ok_req then
            sampAddChatMessage(cyr("[DH] Ошибка сети при скачивании обновления."), 0xFF0000)
            is_updating = false
            return
        end
        if status == 200 and result and #result > 0 then
            local file_path = script.this.path
            local f_dst = io.open(file_path, 'w')
            if f_dst then
                f_dst:write(result)
                f_dst:close()
                sampAddChatMessage(cyr("[DH] Скрипт успешно обновлен! Перезагрузка..."), 0x00FF00)
                is_updating = false
                reloadScript()
                return
            else
                sampAddChatMessage(cyr("[DH] Не удалось записать файл скрипта."), 0xFF0000)
            end
        else
            sampAddChatMessage(cyr("[DH] Не удалось скачать файл обновления."), 0xFF0000)
        end
        is_updating = false
    end)
end

local function is_version_newer(v1, v2)
    if type(v1) ~= 'string' or type(v2) ~= 'string' then return false end
    local function split(v)
        local parts = {}
        for num in v:gmatch('%d+') do
            table.insert(parts, tonumber(num))
        end
        return parts
    end
    local p1, p2 = split(v1), split(v2)
    local len = math.max(#p1, #p2)
    for i = 1, len do
        local a, b = p1[i] or 0, p2[i] or 0
        if a > b then return true end
        if a < b then return false end
    end
    return false
end

function check_updates_and_feed()
    if is_checking then return end
    is_checking = true
    lua_thread.create(function()
        local ok_req, result, status = pcall(https.request, RAW_JSON_URL)
        is_checking = false
        if not ok_req then
            return
        end
        if status == 200 and result then
            local ok, data = pcall(decodeJson, result)
            if ok and type(data) == "table" then
                if type(data.feed_items) == "table" then
                    feed_items = data.feed_items
                end
                if type(data.latest_version) == "string" then
                    latest_version = data.latest_version
                end
                if type(data.update_url) == "string" then
                    update_url = data.update_url
                end
            end
        end
    end)
end

-- ============================================================================
-- 7. АВТОПЕРЕПОДКЛЮЧЕНИЕ К СЕРВЕРУ
-- ============================================================================
local reconnect_gen      = 0
local reconnect_attempts = 0
local start_connecting   = nil
local reconnect_ip, reconnect_port = nil, nil

local function reconnect_reset()
    reconnect_gen = reconnect_gen + 1
    reconnect_attempts = 0
    start_connecting = nil
end

local function do_connect_attempt()
    if not reconnect_ip then return end
    reconnect_attempts = reconnect_attempts + 1
    start_connecting = os.clock()
    sampConnectToServer(reconnect_ip, reconnect_port)
end

local function schedule_reconnect(reason_text, delay_s)
    if not settings.reconnect_enabled then return end
    if not reconnect_ip then
        reconnect_ip, reconnect_port = sampGetCurrentServerAddress()
    end
    if not reconnect_ip or reconnect_ip == '' or reconnect_ip == '0.0.0.0' or not reconnect_port or reconnect_port == 0 then
        return
    end
    reconnect_gen = reconnect_gen + 1
    local my_gen = reconnect_gen
    delay_s = tonumber(delay_s) or 0
    lua_thread.create(function()
        wait(math.floor(delay_s * 1000))
        if my_gen == reconnect_gen then
            do_connect_attempt()
        end
    end)
end

-- ============================================================================
-- 8. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ИНТЕРФЕЙСА (mimgui)
-- ============================================================================
local function contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

local function count_available_items()
    local count = 0
    local seen = {}
    for _, value in ipairs(settings.last_spawn_dialog) do
        if value ~= '' and not seen[value] and not contains(settings.priority, value) then
            seen[value] = true
            count = count + 1
        end
    end
    return count
end

local function list_box_height(rows, row_height, spacing, pad, max_height)
    rows = math.max(rows, 1)
    local height = rows * row_height + math.max(rows - 1, 0) * spacing + pad * 2
    if max_height and height > max_height then
        return max_height
    end
    return height
end

local function point_in_rect(pos, rect)
    return rect
    and pos.x >= rect.min.x and pos.x <= rect.max.x
    and pos.y >= rect.min.y and pos.y <= rect.max.y
end

local function make_rect(pos, width, height)
    return {
        min = imgui.ImVec2(pos.x, pos.y),
        max = imgui.ImVec2(pos.x + width, pos.y + height)
    }
end

local function rect_height(rect)
    return rect.max.y - rect.min.y
end

local function rect_width(rect)
    return rect.max.x - rect.min.x
end

local function color_u32(r, g, b, a)
    local vec = imgui.ImVec4(r, g, b, a)
    if imgui.GetColorU32Vec4 then
        return imgui.GetColorU32Vec4(vec)
    end
    return imgui.GetColorU32(vec)
end

local function draw_dashed_line(draw_list, x1, y1, x2, y2, color, dash, gap)
    dash = dash or 6
    gap  = gap or 4
    if y1 == y2 then
        local x = x1
        while x < x2 do
            local x_end = math.min(x + dash, x2)
            draw_list:AddLine(imgui.ImVec2(x, y1), imgui.ImVec2(x_end, y2), color, 1.0)
            x = x + dash + gap
        end
    elseif x1 == x2 then
        local y = y1
        while y < y2 do
            local y_end = math.min(y + dash, y2)
            draw_list:AddLine(imgui.ImVec2(x1, y), imgui.ImVec2(x2, y_end), color, 1.0)
            y = y + dash + gap
        end
    end
end

local function draw_dashed_rect(draw_list, rect, color, dash, gap)
    draw_dashed_line(draw_list, rect.min.x, rect.min.y, rect.max.x, rect.min.y, color, dash, gap)
    draw_dashed_line(draw_list, rect.min.x, rect.max.y, rect.max.x, rect.max.y, color, dash, gap)
    draw_dashed_line(draw_list, rect.min.x, rect.min.y, rect.min.x, rect.max.y, color, dash, gap)
    draw_dashed_line(draw_list, rect.max.x, rect.min.y, rect.max.x, rect.max.y, color, dash, gap)
end

local function draw_placeholder(draw_list, rect, text)
    local fill_color   = color_u32(0.40, 0.40, 0.40, 0.28)
    local border_color = color_u32(0.75, 0.75, 0.75, 0.95)
    local text_color   = color_u32(0.95, 0.95, 0.95, 1.00)
    draw_list:AddRectFilled(rect.min, rect.max, fill_color, 6)
    draw_dashed_rect(draw_list, rect, border_color, 8, 5)
    local text_size = imgui.CalcTextSize(text)
    local text_pos = imgui.ImVec2(
        rect.min.x + (rect_width(rect) - text_size.x) * 0.5,
        rect.min.y + (rect_height(rect) - text_size.y) * 0.5
    )
    draw_list:AddText(text_pos, text_color, text)
end

local function draw_drag_preview(draw_list, mouse, text)
    local pad_x, pad_y = 12, 8
    local offset_x, offset_y = 18, 18
    local text_size = imgui.CalcTextSize(text)
    local rect = {
        min = imgui.ImVec2(mouse.x + offset_x, mouse.y + offset_y),
        max = imgui.ImVec2(mouse.x + offset_x + text_size.x + pad_x * 2, mouse.y + offset_y + text_size.y + pad_y * 2)
    }
    draw_list:AddRectFilled(rect.min, rect.max, color_u32(0.16, 0.16, 0.16, 0.92), 7)
    draw_list:AddRect(rect.min, rect.max, color_u32(0.65, 0.65, 0.65, 0.98), 7, 0, 1.2)
    draw_list:AddText(imgui.ImVec2(rect.min.x + pad_x, rect.min.y + pad_y), color_u32(0.98, 0.98, 0.98, 1.00), text)
end

-- ============================================================================
-- 9. АВТОПИАР
-- ============================================================================
local PIAR_COMMANDS = {
    "/vr", "/ad", "/j", "/jb", "/r", "/rb", "/f", "/fb", "/al", "/g", "/d", "/s", "/fam"
}
local PIAR_LEGACY_COMMANDS = {
    [0] = "/vr", [1] = "/ad", [2] = "/s", [3] = "/al", [4] = "/fam"
}
local PIAR_COMMAND_INDEX = {}
for i, command in ipairs(PIAR_COMMANDS) do
    PIAR_COMMAND_INDEX[command] = i - 1
end

local PIAR_RADIO_STATIONS = { 'Автоматически', 'SF', 'LV', 'LS' }

local function piar_notify(text, color)
    if isSampAvailable() then
        sampAddChatMessage(cyr(string.format("[Автопиар] %s", tostring(text))), color or 0x55CCFF)
    end
end

local function piar_create_command_settings(command)
    local s = {
        isCounter = { count = 99, status = false }
    }
    if command == "/vr" then
        s.isADVIP = true
    elseif command == "/ad" then
        s.isRadioStation = 0
        s.isVipAd = false
        s.isRetry = { osTime = -1, retryTime = 35, status = true }
    end
    return s
end

local function piar_normalize_profile(profile)
    if type(profile) ~= "table" then
        profile = {}
    end

    if type(profile.uid) ~= "string" or not profile.uid:match("^ad_[%w_%-]+$") then
        profile.uid = "ad_" .. tostring(os.time()) .. "_" ..
            tostring(math.floor(os.clock() * 1000000)) .. "_" ..
            tostring(math.random(1000, 9999))
    end

    local legacyType = tonumber(profile.isType) or 0
    local command = profile.command
    if PIAR_COMMAND_INDEX[command] == nil then
        command = PIAR_LEGACY_COMMANDS[legacyType] or "/vr"
    end

    profile.command = command
    profile.isType = PIAR_COMMAND_INDEX[command]
    profile.isTimer = tonumber(profile.isTimer) or 0
    profile.isPiarText = type(profile.isPiarText) == "string" and profile.isPiarText or ""
    profile.osTime = tonumber(profile.osTime) or -1
    profile.isEnabled = profile.isEnabled == true

    profile.settingsAd = type(profile.settingsAd) == "table" and profile.settingsAd or {}
    profile.settingsAdByCommand =
        type(profile.settingsAdByCommand) == "table" and profile.settingsAdByCommand or {}

    for oldType, oldCommand in pairs(PIAR_LEGACY_COMMANDS) do
        if profile.settingsAdByCommand[oldCommand] == nil
            and type(profile.settingsAd[tostring(oldType)]) == "table" then
            profile.settingsAdByCommand[oldCommand] = profile.settingsAd[tostring(oldType)]
        end
    end

    for _, supportedCommand in ipairs(PIAR_COMMANDS) do
        if type(profile.settingsAdByCommand[supportedCommand]) ~= "table" then
            profile.settingsAdByCommand[supportedCommand] =
                piar_create_command_settings(supportedCommand)
        end

        local s = profile.settingsAdByCommand[supportedCommand]
        if type(s.isCounter) ~= "table" then
            s.isCounter = { count = 99, status = false }
        end
        s.isCounter.count = tonumber(s.isCounter.count) or 99
        s.isCounter.status = s.isCounter.status == true
    end

    local vrSettings = profile.settingsAdByCommand["/vr"]
    local adSettings = profile.settingsAdByCommand["/ad"]

    vrSettings.isADVIP = vrSettings.isADVIP ~= false

    adSettings.isRadioStation = tonumber(adSettings.isRadioStation) or 0
    adSettings.isVipAd = adSettings.isVipAd == true
    adSettings.isRetry =
        type(adSettings.isRetry) == "table" and adSettings.isRetry or
        { osTime = -1, retryTime = 35, status = true }
    adSettings.isRetry.osTime = tonumber(adSettings.isRetry.osTime) or -1
    adSettings.isRetry.retryTime = tonumber(adSettings.isRetry.retryTime) or 35
    adSettings.isRetry.status = adSettings.isRetry.status == true

    for commandIndex, supportedCommand in ipairs(PIAR_COMMANDS) do
        profile.settingsAd[tostring(commandIndex - 1)] =
            profile.settingsAdByCommand[supportedCommand]
    end

    return profile, profile.settingsAdByCommand[command]
end

local function piar_create_profile()
    local profile = {
        command = "/vr",
        isType = 0,
        isTimer = 0,
        isPiarText = "",
        osTime = -1,
        isEnabled = false,
        settingsAd = {},
        settingsAdByCommand = {}
    }
    piar_normalize_profile(profile)
    return profile
end

local piar_profiles = settings.piar_profiles

do
    local normalized = {}
    for _, profile in pairs(piar_profiles) do
        if type(profile) == "table" then
            local n = piar_normalize_profile(profile)
            normalized[#normalized + 1] = n
        end
    end
    piar_profiles = normalized
    settings.piar_profiles = piar_profiles
end

local piar_mode_labels = imgui.new["const char*"][#PIAR_COMMANDS]()
for i, commandLabel in ipairs(PIAR_COMMANDS) do
    piar_mode_labels[i - 1] = commandLabel
end
local piar_radio_labels = imgui.new["const char*"][#PIAR_RADIO_STATIONS]()
for i, radioLabel in ipairs(PIAR_RADIO_STATIONS) do
    piar_radio_labels[i - 1] = radioLabel
end

local piar_ad_dialog = {
    active = false,
    uid = nil,
    expiresAt = 0,
    vrConfirmAt = 0,
    vrIsVip = false
}

local function piar_find_profile_by_uid(uid)
    if uid == nil then return nil, nil end
    for i, profile in ipairs(piar_profiles) do
        if profile.uid == uid then
            return i, profile
        end
    end
    return nil, nil
end

-- Кэш FFI-буферов ввода текста для UI автопиара, чтобы не пересоздавать
-- imgui.new.char[...] (со строковым копированием) каждый кадр рендера.
local piar_ui_state = {}

local function piar_get_ui_state(uid)
    local st = piar_ui_state[uid]
    if not st then
        st = {}
        piar_ui_state[uid] = st
    end
    return st
end

local function piar_save_profiles()
    for _, profile in ipairs(piar_profiles) do
        piar_normalize_profile(profile)
    end
    settings.piar_profiles = piar_profiles
    save_settings()
end

local function piar_clear_ad_dialog()
    piar_ad_dialog.active = false
    piar_ad_dialog.uid = nil
    piar_ad_dialog.expiresAt = 0
    piar_ad_dialog.vrConfirmAt = 0
    piar_ad_dialog.vrIsVip = false
end

local function piar_send_server_command(command, text)
    local message = command .. (text ~= "" and (" " .. text) or "")
    sampProcessChatInput(message)
end

local function piar_prepare_ad_dialog(profileId, profile)
    local _, s = piar_normalize_profile(profile)
    if profile.command == "/ad" then
        piar_ad_dialog.active = true
        piar_ad_dialog.uid = profile.uid
        piar_ad_dialog.expiresAt = os.time() + 6
    elseif profile.command == "/vr" then
        piar_ad_dialog.vrConfirmAt = os.time() + 2
        piar_ad_dialog.vrIsVip = s.isADVIP == true
    end
end

local function piar_send_profile(profileId, profile)
    local normalized, s = piar_normalize_profile(profile)
    local command = normalized.command
    if profile.isTimer < 1 or profile.isPiarText == "" then
        profile.isEnabled = false
        piar_save_profiles()
        piar_notify(string.format("Профиль %s отключён: задержка должна быть больше 0, текст не должен быть пустым.", command), 0xFFFF55)
        return false
    end

    if s.isCounter.status then
        if s.isCounter.count < 1 then
            profile.isEnabled = false
            piar_save_profiles()
            piar_notify(string.format("Автопиар %s отключён: счётчик отправок исчерпан.", command), 0xFFFF55)
            return false
        end
        s.isCounter.count = s.isCounter.count - 1
    end

    profile.osTime = os.time()
    piar_save_profiles()

    piar_prepare_ad_dialog(profileId, profile)
    piar_send_server_command(command, profile.isPiarText)
    return true
end

local function piar_update()
    if not settings.piar_enabled then return end

    if piar_ad_dialog.active and os.time() > piar_ad_dialog.expiresAt then
        piar_clear_ad_dialog()
    end

    for profileId, profile in pairs(piar_profiles) do
        local normalized, s = piar_normalize_profile(profile)
        local command = normalized.command

        if not profile.isEnabled then
            profile.osTime = -1
        end

        if profile.isEnabled
            and (profile.osTime == -1 or os.time() - profile.osTime > profile.isTimer) then
            if piar_send_profile(profileId, profile) then
                break
            end
        end

        if profile.isEnabled
            and command == "/ad"
            and s.isRetry.status
            and (s.isRetry.osTime == -1
                or os.time() - s.isRetry.osTime > s.isRetry.retryTime) then

            profile.osTime = os.time()
            s.isRetry.osTime = os.time()
            piar_prepare_ad_dialog(profileId, profile)
            piar_send_server_command(command, profile.isPiarText)
            piar_save_profiles()
            break
        end
    end
end

local function piar_draw_profile(profileId, profile)
    local normalized, s = piar_normalize_profile(profile)
    local command = normalized.command

    local status_text = profile.isEnabled and 'Активен' or 'Остановлен'
    local preview = cyr:decode(profile.isPiarText)
    if preview == '' then preview = 'без текста' end
    local header_label = string.format('%s  |  %s  |  %s##piar_header_%d',
        command, status_text, preview, profileId)

    if not imgui.CollapsingHeader(header_label) then
        return
    end

    imgui.Indent(12)

    if imgui.Button((profile.isEnabled and (faicons('STOP') .. '  Остановить') or (faicons('PLAY') .. '  Запустить')) .. '##piar_toggle_' .. tostring(profileId), imgui.ImVec2(115, 28)) then
        if profile.isEnabled then
            profile.isEnabled = false
        elseif profile.isTimer > 0 and profile.isPiarText ~= "" then
            local canToggle = true
            if command == "/ad" then
                for otherId, otherProfile in pairs(piar_profiles) do
                    piar_normalize_profile(otherProfile)
                    if otherId ~= profileId and otherProfile.isEnabled
                        and otherProfile.command == "/ad" then
                        canToggle = false
                        piar_notify('Одновременно активным может быть только один профиль /ad.', 0xFFFF55)
                        break
                    end
                end
            end
            if canToggle then
                profile.isEnabled = true
                profile.osTime = -1
            end
        else
            piar_notify('Для запуска нужны текст и задержка больше 0 секунд.', 0xFFFF55)
        end
        piar_save_profiles()
    end

    imgui.SameLine()
    imgui.Text(command)

    local ui = piar_get_ui_state(profile.uid)

    imgui.SetNextItemWidth(-1)
    if not ui.textBuffer or ui.textBufferSrc ~= profile.isPiarText then
        ui.textBuffer = imgui.new.char[256](cyr:decode(profile.isPiarText))
        ui.textBufferSrc = profile.isPiarText
    end
    if imgui.InputText('Текст##piar_text_' .. tostring(profileId), ui.textBuffer, ffi.sizeof(ui.textBuffer)) then
        profile.isPiarText = cyr(ffi.string(ui.textBuffer))
        ui.textBufferSrc = profile.isPiarText
        piar_save_profiles()
    end

    imgui.SetNextItemWidth(130)
    if not ui.timerBuffer or ui.timerBufferSrc ~= profile.isTimer then
        ui.timerBuffer = imgui.new.char[64](tostring(profile.isTimer))
        ui.timerBufferSrc = profile.isTimer
    end
    if imgui.InputText('Задержка, сек##piar_timer_' .. tostring(profileId), ui.timerBuffer, ffi.sizeof(ui.timerBuffer), imgui.InputTextFlags.CharsDecimal) then
        local value = tonumber(ffi.string(ui.timerBuffer))
        if value then
            profile.isEnabled = false
            profile.isTimer = math.max(0, math.floor(value))
            ui.timerBufferSrc = profile.isTimer
            piar_save_profiles()
        end
    end

    imgui.SetNextItemWidth(180)
    local mode = imgui.new.int(profile.isType)
    if imgui.Combo('Режим##piar_mode_' .. tostring(profileId), mode, piar_mode_labels, #PIAR_COMMANDS) then
        profile.isEnabled = false
        profile.isType = mode[0]
        profile.command = PIAR_COMMANDS[mode[0] + 1]
        piar_normalize_profile(profile)
        piar_save_profiles()
    end

    if command == "/vr" then
        local vip = imgui.new.bool(s.isADVIP)
        if imgui.Checkbox('VIP-режим /vr##piar_vip_' .. tostring(profileId), vip) then
            s.isADVIP = vip[0]
            piar_save_profiles()
        end
    elseif command == "/ad" then
        local station = imgui.new.int(s.isRadioStation)
        if imgui.Combo('Радиостанция##piar_radio_' .. tostring(profileId), station, piar_radio_labels, #PIAR_RADIO_STATIONS) then
            profile.isEnabled = false
            s.isRadioStation = station[0]
            piar_save_profiles()
        end

        local vipAd = imgui.new.bool(s.isVipAd)
        if imgui.Checkbox('VIP-AD##piar_vipad_' .. tostring(profileId), vipAd) then
            s.isVipAd = vipAd[0]
            piar_save_profiles()
        end

        local retry = imgui.new.bool(s.isRetry.status)
        if imgui.Checkbox('Повторять попытки /ad##piar_retry_' .. tostring(profileId), retry) then
            s.isRetry.status = retry[0]
            piar_save_profiles()
        end

        if s.isRetry.status then
            imgui.SetNextItemWidth(120)
            if not ui.retryBuffer or ui.retryBufferSrc ~= s.isRetry.retryTime then
                ui.retryBuffer = imgui.new.char[64](tostring(s.isRetry.retryTime))
                ui.retryBufferSrc = s.isRetry.retryTime
            end
            if imgui.InputText('Интервал повтора##piar_retry_time_' .. tostring(profileId), ui.retryBuffer, ffi.sizeof(ui.retryBuffer), imgui.InputTextFlags.CharsDecimal) then
                local value = tonumber(ffi.string(ui.retryBuffer))
                if value then
                    s.isRetry.retryTime = math.max(1, math.floor(value))
                    ui.retryBufferSrc = s.isRetry.retryTime
                    piar_save_profiles()
                end
            end
        end
    end

    local counterEnabled = imgui.new.bool(s.isCounter.status)
    if imgui.Checkbox('Ограничить количество отправок##piar_counter_' .. tostring(profileId), counterEnabled) then
        s.isCounter.status = counterEnabled[0]
        piar_save_profiles()
    end

    if s.isCounter.status then
        imgui.SetNextItemWidth(120)
        if not ui.countBuffer or ui.countBufferSrc ~= s.isCounter.count then
            ui.countBuffer = imgui.new.char[64](tostring(s.isCounter.count))
            ui.countBufferSrc = s.isCounter.count
        end
        if imgui.InputText('Осталось##piar_count_' .. tostring(profileId), ui.countBuffer, ffi.sizeof(ui.countBuffer), imgui.InputTextFlags.CharsDecimal) then
            local value = tonumber(ffi.string(ui.countBuffer))
            if value then
                s.isCounter.count = math.max(0, math.floor(value))
                ui.countBufferSrc = s.isCounter.count
                piar_save_profiles()
            end
        end
    end

    if profile.isEnabled then
        imgui.Text(string.format('Следующая отправка примерно через %d сек.',
            math.max(0, profile.isTimer - (os.time() - profile.osTime))))
    end

    if imgui.Button(faicons('TRASH') .. '  Удалить профиль##piar_delete_' .. tostring(profileId), imgui.ImVec2(150, 28)) then
        piar_ui_state[profile.uid] = nil
        if piar_ad_dialog.uid == profile.uid then
            piar_clear_ad_dialog()
        end
        table.remove(piar_profiles, profileId)
        piar_save_profiles()
    end

    imgui.Unindent(12)
end

local function piar_on_show_dialog(dialogId, style, title, button1, button2, text)
    if not piar_ad_dialog.active or piar_ad_dialog.uid == nil then
        if piar_ad_dialog.vrConfirmAt > 0
            and os.time() <= piar_ad_dialog.vrConfirmAt
            and text:find("\xC2\xE0\xF8\xE5 \xF1\xEE\xEE\xE1\xF9\xE5\xED\xE8\xE5 \xFF\xE2\xEB\xFF\xE5\xF2\xF1\xFF \xF0\xE5\xEA\xEB\xE0\xEC\xEE\xE9")
            and text:find("\xF7\xF2\xEE \xE0\xE4\xEC\xE8\xED\xE8\xF1\xF2\xF0\xE0\xF6\xE8\xFF \xEC\xEE\xE6\xE5\xF2 \xED\xE0\xEA\xE0\xE7\xE0\xF2\xFC") then
            piar_ad_dialog.vrConfirmAt = 0
            sampSendDialogResponse(dialogId, piar_ad_dialog.vrIsVip and 1 or 0, 0, "")
            return false
        end
        return
    end

    local _, profile = piar_find_profile_by_uid(piar_ad_dialog.uid)
    if not profile then
        piar_clear_ad_dialog()
        return
    end

    local _, s = piar_normalize_profile(profile)

    if text:find("\xCD\xE0\xEF\xE8\xF8\xE8\xF2\xE5 \xF2\xE5\xEA\xF1\xF2 \xEE\xE1\xFA\xFF\xE2\xEB\xE5\xED\xE8\xFF")
        and title:find("\xCF\xEE\xE4\xE0\xF7\xE0 \xEE\xE1\xFA\xFF\xE2\xEB\xE5\xED\xE8\xFF") then
        sampSendDialogResponse(dialogId, 1, 1, profile.isPiarText)
        return false
    end

    if text:find("\xC2\xE0\xF8\xE5 \xEE\xE1\xFA\xFF\xE2\xEB\xE5\xED\xE8\xE5 \xE5\xF9\xE5 \xED\xE5 \xF0\xE0\xF1\xF1\xEC\xEE\xF2\xF0\xE5\xED\xEE \xF1\xEE\xF2\xF0\xF3\xE4\xED\xE8\xEA\xE0\xEC\xE8 \xD1\xCC\xC8") then
        if s.isRetry.status then
            s.isRetry.osTime = os.time()
            sampSendDialogResponse(dialogId, 1, 1, "")
        else
            sampSendDialogResponse(dialogId, 0, 0, "")
        end
        piar_clear_ad_dialog()
        return false
    end

    if title:find("\xC2\xFB\xE1\xE5\xF0\xE8\xF2\xE5 \xF0\xE0\xE4\xE8\xEE\xF1\xF2\xE0\xED\xF6\xE8\xFE")
        and text:find("\xD0\xE0\xE4\xE8\xEE\xF1\xF2\xE0\xED\xF6\xE8\xFF") then

        local dialogLines = {}
        for line in text:gmatch("[^\r\n]+") do
            if not line:find("\xD0\xE0\xE4\xE8\xEE\xF1\xF2\xE0\xED\xF6\xE8\xFF")
                and line:find("%[%d+%]") then
                table.insert(dialogLines, line)
            end
        end

        local durations = {}
        for index, line in ipairs(dialogLines) do
            local plain = line:gsub("{[A-Fa-f0-9]+}", "")
            local hours, minutes, seconds = 0, 0, 0

            local h, m, sec = plain:match("(%d+)%s*\xF7\xE0\xF1%.?%s*(%d+)%s*\xEC\xE8\xED%.?%s*(%d+)%s*\xF1\xE5\xEA%.?")
            if h then
                hours, minutes, seconds = tonumber(h) or 0, tonumber(m) or 0, tonumber(sec) or 0
            else
                local mm, ss = plain:match("(%d+)%s*\xEC\xE8\xED%.?%s*(%d+)%s*\xF1\xE5\xEA%.?")
                if mm then
                    minutes, seconds = tonumber(mm) or 0, tonumber(ss) or 0
                else
                    local onlySeconds = plain:match("(%d+)%s*\xF1\xE5\xEA%.?")
                    seconds = tonumber(onlySeconds) or 0
                end
            end

            local total = hours * 3600 + minutes * 60 + seconds
            durations[index] = total == 0 and 999999 or total
        end

        local selected = 1
        local shortest = math.huge
        for index, duration in ipairs(durations) do
            if duration < shortest then
                shortest = duration
                selected = index
            end
        end

        if s.isRadioStation == 0 then
            sampSendDialogResponse(dialogId, 1, selected - 1, "")
        elseif s.isRadioStation == 1 then
            sampSendDialogResponse(dialogId, 1, 2, "")
        elseif s.isRadioStation == 2 then
            sampSendDialogResponse(dialogId, 1, 1, "")
        elseif s.isRadioStation == 3 then
            sampSendDialogResponse(dialogId, 1, 0, "")
        end

        return false
    end

    if title:find("\xC2\xFB\xE1\xE5\xF0\xE8\xF2\xE5 \xF2\xE8\xEF \xEE\xE1\xFA\xFF\xE2\xEB\xE5\xED\xE8\xFF") then
        sampSendDialogResponse(dialogId, 1, s.isVipAd and 1 or 0, "")
        return false
    end

    if title:find("\xCF\xEE\xE4\xE0\xF7\xE0 \xEE\xE1\xFA\xFF\xE2\xEB\xE5\xED\xE8\xFF %| \xCF\xEE\xE4\xF2\xE2\xE5\xF0\xE6\xE4\xE5\xED\xE8\xE5") then
        s.isRetry.osTime = os.time()
        piar_clear_ad_dialog()
        sampSendDialogResponse(dialogId, 1, 65535, "")
        piar_save_profiles()
        return false
    end
end

function sampev.onServerMessage(color, message)
    if (color == -45846529 or color == -2686721)
        and message:find("VIP ADV")
        and message:match("%{[^}]*%}(.-)%[%d+%]")
        and message:match("%{[^}]*%}(.-)%[%d+%]")
            == sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) then
        settings.piar_last_ad = os.time()
        save_settings()
    end
end

-- ============================================================================
-- 10. СОСТОЯНИЕ И РАЗМЕТКА ОКНА MIMGUI
-- ============================================================================
window                       = imgui.new.bool(false)
local ass_enabled            = imgui.new.bool(settings.enabled)
local ass_delay              = imgui.new.int(settings.delay)
local reconnect_enabled      = imgui.new.bool(settings.reconnect_enabled == true)
local reconnect_delay        = imgui.new.float(tonumber(settings.reconnect_delay) or 3)
local reconnect_retry_delay  = imgui.new.float(tonumber(settings.reconnect_retry_delay) or 5)
local reconnect_use_timeout  = imgui.new.bool(settings.reconnect_use_timeout ~= false)
local reconnect_timeout      = imgui.new.float(tonumber(settings.reconnect_timeout) or 8)
local reconnect_on_ban       = imgui.new.bool(settings.reconnect_on_ban == true)
local reconnect_delay_banned = imgui.new.float(tonumber(settings.reconnect_delay_banned) or 60)

-- ============================================================================
-- 11. ФУНКЦИЯ АВТООПЛАТЫ НАЛОГОВ
-- ============================================================================
local auto_taxes_running = false
local auto_taxes_stage = nil
local auto_taxes_result = nil

local function tax_notify(text, color)
    if isSampAvailable() then
        sampAddChatMessage(cyr("[DH] " .. tostring(text)), color or 0xFFCCCCCC)
    end
end

local function cefSendTax(str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #str)
    raknetBitStreamWriteString(bs, str)
    raknetSendBitStreamEx(bs, 1, 7, 1)
    raknetDeleteBitStream(bs)
end

local function get_next_tax_run(now)
    now = now or os.time()
    local interval = math.max(1, math.floor(tonumber(settings.auto_taxes_interval_hours) or 1))
    return now + interval * 3600
end

local function doAutoTaxes(manual)
    if auto_taxes_running or not isSampAvailable() then return end
    if not manual and not settings.auto_taxes_enabled then return end
    auto_taxes_running = true
    lua_thread.create(function()
        auto_taxes_result = nil
        auto_taxes_stage = 'wait_bank'
        sampSendChat('/phone')
        wait(1000)
        cefSendTax('launchedApp|24')

        local deadline = os.clock() + 8
        while auto_taxes_stage and os.clock() < deadline do wait(50) end

        if auto_taxes_stage then
            auto_taxes_stage = nil
            tax_notify('Сервер не ответил вовремя.', 0xFFFF6060)
        elseif auto_taxes_result == 'paid' then
            tax_notify('Налоги оплачены!', 0xFF90EE90)
        elseif auto_taxes_result == 'none' then
            tax_notify('Налогов к оплате нет.', 0xFF90EE90)
        end

        wait(300)
        sampSendChat('/phone')
        auto_taxes_running = false
    end)
end

local function tax_on_show_dialog(id)
    if auto_taxes_stage == 'wait_bank' and id == 6565 then
        sampSendDialogResponse(id, 1, 4, '')
        auto_taxes_stage = 'wait_tax'
        return false
    end
    if auto_taxes_stage == 'wait_tax' then
        if id == 15252 then
            sampSendDialogResponse(id, 1, 0, '')
            auto_taxes_result = 'paid'
        else
            sampSendDialogResponse(id, 1, 0, '')
            auto_taxes_result = 'none'
        end
        auto_taxes_stage = nil
        return false
    end
    return nil
end

local super_stop_enabled         = imgui.new.bool(settings.super_stop_enabled == true)
local auto_sport_enabled         = imgui.new.bool(settings.auto_sport_enabled == true)
local auto_taxes_enabled         = imgui.new.bool(settings.auto_taxes_enabled == true)
local auto_taxes_interval_hours = imgui.new.int(settings.auto_taxes_interval_hours)
local drag_mode                 = nil
local drag_priority_index       = nil
local drag_available_value      = nil
local current_drop_index        = nil

imgui.OnInitialize(function()
    imgui.DarkTheme()
    imgui.GetIO().IniFilename = getWorkingDirectory() .. '/config/DH_ui.ini'

    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges)
end)

imgui.OnFrame(function() return window[0] end, function()
    local x, y = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(x / 2, y / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(1000, 650), imgui.Cond.Always)
    
    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
    imgui.Begin(faicons('GAMEPAD') .. '  DH Script v' .. CURRENT_VERSION, window, flags)

    local current_time = os.time()
    if current_time - last_feed_update >= FEED_UPDATE_INTERVAL then
        check_updates_and_feed()
        last_feed_update = current_time
    end
    local mouse = imgui.GetIO().MousePos
    local item_height = 30
    local item_spacing_y = imgui.GetStyle().ItemSpacing.y
    local child_pad_y = imgui.GetStyle().WindowPadding.y
    local main_draw_list = imgui.GetWindowDrawList()
    local avail = imgui.GetContentRegionAvail()
    local has_new_version = latest_version and is_version_newer(latest_version, CURRENT_VERSION)
    local bottom_button_height = has_new_version and (28 + item_spacing_y) or 0
    local main_content_height = avail.y - bottom_button_height
    local left_col_width = math.floor(avail.x * 0.58)
    local right_col_width = avail.x - left_col_width - imgui.GetStyle().ItemSpacing.x
    
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(10, 10))
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))

    imgui.BeginChild('##left_settings_column', imgui.ImVec2(left_col_width, main_content_height), false, imgui.WindowFlags.NoScrollbar)
    imgui.BeginTabBar('##ass_tabs')
    if imgui.BeginTabItem(faicons('LOCATION_DOT') .. '  Автоспавн') then
        imgui.Spacing()
        if imgui.Checkbox(faicons('POWER_OFF') .. '  Включить автоспавн', ass_enabled) then
            settings.enabled = ass_enabled[0]
            save_settings()
        end
        imgui.Spacing()
        imgui.SetNextItemWidth(-1)
        if imgui.SliderInt('##ass_delay', ass_delay, 5, 20, 'Задержка спавна: %d сек.') then
            settings.delay = ass_delay[0]
            save_settings()
        end
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        imgui.SectionTitle('Приоритеты спавна')
        imgui.TextDisabled('Перетаскивайте пункты мышью. ПКМ по пункту — удалить.')
        imgui.Spacing()
        local max_box_height = math.floor((main_content_height - 180) * 0.5)
        if max_box_height < 50 then max_box_height = 50 end
        local priority_height = list_box_height(#settings.priority, item_height, item_spacing_y, child_pad_y, max_box_height)
        local priority_pos = imgui.GetCursorScreenPos()
        local priority_width = imgui.GetContentRegionAvail().x
        local priority_rect = make_rect(priority_pos, priority_width, priority_height)
        local priority_draw_list = nil
        local priority_inner_pos = nil
        local priority_item_width = 0
        
        imgui.BeginChild('##priority_list', imgui.ImVec2(0, priority_height), true, imgui.WindowFlags.NoScrollbar)
        priority_draw_list = imgui.GetWindowDrawList()
        priority_inner_pos = imgui.GetCursorScreenPos()
        priority_item_width = imgui.GetContentRegionAvail().x
        local visible_priority_count = 0
        local dragging_into_priority = (drag_mode == 'available' or drag_mode == 'priority')
            and point_in_rect(mouse, priority_rect)
        local visible_total = #settings.priority
        if drag_mode == 'priority' and drag_priority_index and settings.priority[drag_priority_index] then
            visible_total = visible_total - 1
        end
        if visible_total < 0 then visible_total = 0 end
        local placeholder_insert_index = nil
        if dragging_into_priority then
            if visible_total == 0 then
                placeholder_insert_index = 1
            else
                local pitch = item_height + item_spacing_y
                local relative_y = mouse.y - priority_inner_pos.y
                placeholder_insert_index = math.floor((relative_y + item_height * 0.5) / pitch) + 1
                if placeholder_insert_index < 1 then placeholder_insert_index = 1 end
                if placeholder_insert_index > visible_total + 1 then
                    placeholder_insert_index = visible_total + 1
                end
            end
            current_drop_index = placeholder_insert_index
        end
        local placeholder_drawn = false
        local function reserve_placeholder()
            local placeholder_pos = imgui.GetCursorScreenPos()
            local placeholder_rect = make_rect(placeholder_pos, priority_item_width, item_height)
            local placeholder_text = drag_mode == 'available'
                and 'Отпустите, чтобы добавить сюда'
                or 'Отпустите, чтобы переместить сюда'
            draw_placeholder(priority_draw_list, placeholder_rect, placeholder_text)
            imgui.SetCursorPosY(imgui.GetCursorPosY() + item_height + item_spacing_y)
            placeholder_drawn = true
        end
        for i, value in ipairs(settings.priority) do
            if not (drag_mode == 'priority' and drag_priority_index == i) then
                if placeholder_insert_index
                    and not placeholder_drawn
                    and placeholder_insert_index == visible_priority_count + 1 then
                    reserve_placeholder()
                end
                visible_priority_count = visible_priority_count + 1
                local item_pos = imgui.GetCursorScreenPos()
                local item_rect = make_rect(item_pos, priority_item_width, item_height)
                imgui.Button(value .. '##priority_' .. tostring(i), imgui.ImVec2(-1, item_height))
                local hovered = imgui.IsItemHovered()
                local active = imgui.IsItemActive()
                if active and imgui.IsMouseDragging(0, 4.0) then
                    drag_mode = 'priority'
                    drag_priority_index = i
                    drag_available_value = nil
                end
                if hovered and drag_mode == nil then
                    imgui.SetTooltip('Зажмите ЛКМ и перетащите. ПКМ — удалить.')
                end
                if hovered and drag_mode == nil and imgui.IsMouseClicked(1) then
                    table.remove(settings.priority, i)
                    save_settings()
                    break
                end
            end
        end
        if placeholder_insert_index and not placeholder_drawn then
            reserve_placeholder()
        end
        if visible_priority_count == 0 and drag_mode ~= 'priority' and not placeholder_drawn then
            imgui.Spacing()
            imgui.TextDisabled('Список пуст. Перетащите сюда место спавна.')
        end
        imgui.EndChild()
        imgui.Spacing()
        imgui.SectionTitle('Последний диалог спавна')
        imgui.Spacing()
        local available_item_height = 30
        local available_height = list_box_height(count_available_items(), available_item_height, item_spacing_y, child_pad_y, max_box_height)
        local available_pos = imgui.GetCursorScreenPos()
        local available_width = imgui.GetContentRegionAvail().x
        local available_rect = make_rect(available_pos, available_width, available_height)
        local available_inner_pos = nil
        local available_item_width = 0
        
        imgui.BeginChild('##available_list', imgui.ImVec2(0, available_height), true, imgui.WindowFlags.NoScrollbar)
        available_inner_pos = imgui.GetCursorScreenPos()
        available_item_width = imgui.GetContentRegionAvail().x
        local shown = 0
        local seen = {}
        for _, value in ipairs(settings.last_spawn_dialog) do
            if value ~= '' and not seen[value] and not contains(settings.priority, value) then
                seen[value] = true
                shown = shown + 1
                local item_pos = imgui.GetCursorScreenPos()
                local item_rect = make_rect(item_pos, available_item_width, available_item_height)
                imgui.Button(value .. '##available_' .. tostring(shown), imgui.ImVec2(-1, available_item_height))
                if imgui.IsItemActive() and imgui.IsMouseDragging(0, 4.0) then
                    drag_mode = 'available'
                    drag_available_value = value
                    drag_priority_index = nil
                end
                if imgui.IsItemHovered() and drag_mode == nil then
                    imgui.SetTooltip('Зажмите ЛКМ и перетащите в приоритеты.')
                end
            end
        end
        if shown == 0 then
            imgui.Spacing()
            if #settings.last_spawn_dialog == 0 then
                imgui.TextDisabled('Данные появятся после открытия диалога спавна.')
            else
                imgui.TextDisabled('Все места из диалога уже добавлены.')
            end
        end
        imgui.EndChild()
        if not dragging_into_priority then
            current_drop_index = nil
        end
        if drag_mode == 'available' or drag_mode == 'priority' then
            local preview_text = drag_mode == 'available' and drag_available_value or settings.priority[drag_priority_index]
            local mouse_inside_available = point_in_rect(mouse, available_rect)
            if preview_text and preview_text ~= '' and not mouse_inside_available then
                draw_drag_preview(main_draw_list, mouse, preview_text)
            end
        end
        if not imgui.IsMouseDown(0) then
            if drag_mode == 'available' and drag_available_value then
                if point_in_rect(mouse, priority_rect) and not contains(settings.priority, drag_available_value) then
                    local insert_at = current_drop_index or (#settings.priority + 1)
                    if insert_at < 1 then insert_at = 1 end
                    if insert_at > #settings.priority + 1 then insert_at = #settings.priority + 1 end
                    table.insert(settings.priority, insert_at, drag_available_value)
                    save_settings()
                end
            elseif drag_mode == 'priority' and drag_priority_index and settings.priority[drag_priority_index] then
                if point_in_rect(mouse, priority_rect) then
                    local moving_value = table.remove(settings.priority, drag_priority_index)
                    local insert_at = current_drop_index or (#settings.priority + 1)
                    if insert_at < 1 then insert_at = 1 end
                    if insert_at > #settings.priority + 1 then insert_at = #settings.priority + 1 end
                    table.insert(settings.priority, insert_at, moving_value)
                    save_settings()
                end
            end
            drag_mode = nil
            drag_priority_index = nil
            drag_available_value = nil
            current_drop_index = nil
        end
        imgui.EndTabItem()
    end
    
    if imgui.BeginTabItem(faicons('PLUG') .. '  Реконнект') then
        imgui.Spacing()
        if imgui.Checkbox(faicons('PLUG') .. '  Включить автопереподключение', reconnect_enabled) then
            settings.reconnect_enabled = reconnect_enabled[0]
            save_settings()
        end
        imgui.TextDisabled('Переподключает при обрыве связи или кике.')
        if settings.reconnect_enabled then
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
            imgui.SetNextItemWidth(-1)
            if imgui.SliderFloat('##reconnect_delay', reconnect_delay, 0.0, 30.0, 'После кика/обрыва: %.1f сек.') then
                settings.reconnect_delay = reconnect_delay[0]
                save_settings()
            end
            imgui.SetNextItemWidth(-1)
            if imgui.SliderFloat('##reconnect_retry_delay', reconnect_retry_delay, 0.5, 30.0, 'Между повторами: %.1f сек.') then
                settings.reconnect_retry_delay = reconnect_retry_delay[0]
                save_settings()
            end
            imgui.Spacing()
            if imgui.Checkbox('Следить за таймаутом подключения', reconnect_use_timeout) then
                settings.reconnect_use_timeout = reconnect_use_timeout[0]
                save_settings()
            end
            if settings.reconnect_use_timeout then
                imgui.SetNextItemWidth(-1)
                if imgui.SliderFloat('##reconnect_timeout', reconnect_timeout, 2.0, 30.0, 'Таймаут: %.1f сек.') then
                    settings.reconnect_timeout = reconnect_timeout[0]
                    save_settings()
                end
            end
            imgui.Spacing()
            if imgui.Checkbox('Пробовать реконнект и при бане', reconnect_on_ban) then
                settings.reconnect_on_ban = reconnect_on_ban[0]
                save_settings()
            end
            if settings.reconnect_on_ban then
                imgui.SetNextItemWidth(-1)
                if imgui.SliderFloat('##reconnect_delay_banned', reconnect_delay_banned, 5.0, 300.0, 'Задержка при бане: %.0f сек.') then
                    settings.reconnect_delay_banned = reconnect_delay_banned[0]
                    save_settings()
                end
            end
        end
        imgui.EndTabItem()
    end
    
    if imgui.BeginTabItem(faicons('SLIDERS') .. '  Функции') then
        imgui.Spacing()

        if imgui.Checkbox(faicons('HAND') .. '  Супер стоп (Клавиша C)', super_stop_enabled) then
            settings.super_stop_enabled = super_stop_enabled[0]
            save_settings()
        end
        imgui.TextDisabled('При зажатии клавиши C в транспорте\nмгновенно останавливает его.')

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Checkbox(faicons('CAR') .. '  Авто спорт-режим', auto_sport_enabled) then
            settings.auto_sport_enabled = auto_sport_enabled[0]
            save_settings()
        end
        imgui.TextDisabled('При посадке в транспорт автоматически\nвыбирает спорт-режим в радиальном меню.')

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Checkbox(faicons('MONEY_BILL_WAVE') .. '  Включить автооплату налогов', auto_taxes_enabled) then
            settings.auto_taxes_enabled = auto_taxes_enabled[0]
            settings.auto_taxes_next_run = settings.auto_taxes_enabled and get_next_tax_run() or 0
            save_settings()
        end

        imgui.TextDisabled('Оплата выполняется через телефон.')

        imgui.SetNextItemWidth(180)
        if imgui.InputInt('Интервал, часов', auto_taxes_interval_hours) then
            auto_taxes_interval_hours[0] = math.max(1, math.min(168, auto_taxes_interval_hours[0]))
            settings.auto_taxes_interval_hours = auto_taxes_interval_hours[0]
            if settings.auto_taxes_enabled then
                settings.auto_taxes_next_run = get_next_tax_run()
            end
            save_settings()
        end

        if settings.auto_taxes_enabled then
            if settings.auto_taxes_next_run == 0 then
                settings.auto_taxes_next_run = get_next_tax_run()
                save_settings()
            end
            local remaining = math.max(0, settings.auto_taxes_next_run - os.time())
            imgui.Text(string.format('Следующая оплата через: %d ч. %d мин.',
                math.floor(remaining / 3600), math.floor((remaining % 3600) / 60)))
        else
            imgui.TextDisabled('Автооплата отключена.')
        end

        if imgui.Button(faicons('MONEY_BILL_WAVE') .. '  Оплатить налоги сейчас', imgui.ImVec2(-1, 30)) then
            doAutoTaxes(true)
        end

        imgui.EndTabItem()
    end

    if imgui.BeginTabItem(faicons('BULLHORN') .. '  Автопиар') then
        imgui.Spacing()
        local piar_enabled_cb = imgui.new.bool(settings.piar_enabled)
        if imgui.Checkbox(faicons('BULLHORN') .. '  Авто-режим рекламы', piar_enabled_cb) then
            settings.piar_enabled = piar_enabled_cb[0]
            save_settings()
        end
        imgui.SameLine()
        if imgui.Button(faicons('PLUS') .. '  Добавить профиль', imgui.ImVec2(175, 25)) then
            local newProfile = piar_create_profile()
            table.insert(piar_profiles, newProfile)
            piar_save_profiles()
        end
        do
            local active_count = 0
            for _, profile in pairs(piar_profiles) do
                if profile.isEnabled then active_count = active_count + 1 end
            end
            imgui.Text(string.format('Активно: %d/%d', active_count, #piar_profiles))
        end
        if settings.piar_last_ad and settings.piar_last_ad > 0 then
            local elapsed = math.max(0, os.time() - settings.piar_last_ad)
            imgui.TextDisabled(string.format('Последнее объявление: %s (%s назад)',
                os.date('%H:%M:%S', settings.piar_last_ad),
                os.date('!%M:%S', elapsed)))
        else
            imgui.TextDisabled('Объявлений ещё не было.')
        end
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        local piar_scroll_height = math.max(main_content_height - 130, 100)
        imgui.BeginChild('##piar_profiles_scroll', imgui.ImVec2(0, piar_scroll_height), false)
        if #piar_profiles == 0 then
            imgui.TextDisabled('Профилей ещё нет. Нажмите "Добавить профиль".')
        else
            for profileId, profile in pairs(piar_profiles) do
                piar_draw_profile(profileId, profile)
                imgui.Spacing()
            end
        end
        imgui.EndChild()
        imgui.EndTabItem()
    end

    imgui.EndTabBar()
    imgui.EndChild()
    imgui.PopStyleColor()
    imgui.SameLine()

    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.BeginChild('##right_feed_column', imgui.ImVec2(right_col_width, main_content_height), false, imgui.WindowFlags.NoScrollbar)
    
    local button_h = 28
    local style = imgui.GetStyle()
    local feed_scroll_height = main_content_height - button_h - style.ItemSpacing.y
    
    imgui.BeginChild('##feed_window_scroll', imgui.ImVec2(-1, feed_scroll_height), true)
    if #feed_items == 0 then
        imgui.TextDisabled(is_checking and 'Загрузка...' or 'Новостей и обновлений нет.')
    else
        for _, item in ipairs(feed_items) do
            if item.type == "update" then
                if imgui.CollapsingHeader(string.format("Обновление v%s##%s", tostring(item.version or "1.0"), tostring(item.date or ""))) then
                    imgui.Indent(10)
                    imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1.0), string.format("Дата: %s", tostring(item.date or '')))
                    imgui.Spacing()
                    imgui.TextWrapped(tostring(item.text or ''))
                    if type(item.changes) == "table" then
                        imgui.Spacing()
                        imgui.TextDisabled('Список изменений:')
                        for _, change in ipairs(item.changes) do
                            imgui.BulletText(tostring(change))
                        end
                    end
                    imgui.Unindent(10)
                    imgui.Spacing()
                end
            else
                imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1.0), string.format("[%s]", tostring(item.date or '')))
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), string.format("%s:", tostring(item.author or 'Dev')))
                imgui.SameLine()
                imgui.TextWrapped(tostring(item.text or ''))
                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()
            end
        end
    end
    imgui.EndChild()
    
    imgui.SetCursorPosY(main_content_height - button_h)
    if imgui.Button(faicons('ARROWS_ROTATE') .. '  Обновить ленту##feed_refresh', imgui.ImVec2(-1, button_h)) then
        check_updates_and_feed()
    end
    
    imgui.EndChild()
    imgui.PopStyleColor()

    if has_new_version then
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15, 0.45, 0.20, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.55, 0.25, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25, 0.65, 0.30, 1.00))
        local btn_text = is_updating
            and (faicons('SPINNER') .. '  Обновление...##self_update')
            or string.format(faicons('DOWNLOAD') .. '  Обновить скрипт до v%s##self_update', tostring(latest_version))
        if imgui.Button(btn_text, imgui.ImVec2(-1, 28)) and not is_updating then
            download_update(update_url)
        end
        imgui.PopStyleColor(3)
    end
    imgui.End()
end)

-- ============================================================================
-- 12. ОБРАБОТКА СЕТЕВЫХ ПАКЕТОВ И СОБЫТИЙ СПАВНА
-- ============================================================================
function arizonaSendSelectSpawn(id)
    local s = 'authSpawn|' .. id
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt32(bs, #s)
    raknetBitStreamWriteString(bs, s)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStreamEx(bs, 1, 7, 1)
    raknetDeleteBitStream(bs)
end

function bitStreamStructure(bs)
    local text, array = '', {}
    for i = 1, raknetBitStreamGetNumberOfBytesUsed(bs) do
        local byte = raknetBitStreamReadInt8(bs)
        if byte >= 32 and byte <= 255 and byte ~= 37 then
            text = text .. string.char(byte)
        end
        table.insert(array, byte)
    end
    raknetBitStreamResetReadPointer(bs)
    return text, array
end

function onReceivePacket(id, bs)
    if id == PACKET_DISCONNECTION_NOTIFICATION then
        start_connecting = nil
        schedule_reconnect('Соединение закрыто сервером (кик/рестарт)', tonumber(settings.reconnect_delay) or 3)
    elseif id == PACKET_CONNECTION_LOST then
        start_connecting = nil
        schedule_reconnect('Потеряно соединение', tonumber(settings.reconnect_delay) or 3)
    elseif id == PACKET_CONNECTION_ATTEMPT_FAILED then
        schedule_reconnect('Сервер не отвечает', tonumber(settings.reconnect_retry_delay) or 5)
    elseif id == PACKET_CONNECTION_BANNED then
        start_connecting = nil
        if settings.reconnect_on_ban then
            schedule_reconnect('Забанен по IP', tonumber(settings.reconnect_delay_banned) or 60)
        end
    elseif id == PACKET_RECEIVED_STATIC_DATA then
        reconnect_reset()
    end

    if id == 239 then
        local text = bitStreamStructure(bs)
        local event, data = tostring(text):match("window%.executeEvent%('([%w%.]+)',%s*'(.+)'%)")

        if event == 'event.auth.initializeSpawnPoints' then
            local decoded = decodeJson(data)
            local points = decoded and decoded[1]

            if type(points) == 'table' then
                local parsed = {}
                for _, p in ipairs(points) do
                    table.insert(parsed, cyr:decode(p.spawn))
                end

                settings.last_spawn_dialog = parsed
                save_settings()
                stats_counter.autospawn = stats_counter.autospawn + 1

                if settings.enabled then
                    lua_thread.create(function()
                        wait((settings.delay or 5) * 1000)
                        for i = 1, #settings.priority do
                            local pri = settings.priority[i]
                            for _, p in ipairs(points) do
                                if cyr:decode(p.spawn) == pri then
                                    arizonaSendSelectSpawn(p.id)
                                    return
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    local tax_handled = tax_on_show_dialog(dialogId)
    if tax_handled ~= nil then return tax_handled end

    -- [Автоспавн] диалог выбора места спавна
    if settings.enabled and title then
        local decoded_title = cyr:decode(title)
        if decoded_title:find('Выбор места спавна') and text then
            local decoded_text = cyr:decode(text)
            local lines = {}
            for line in decoded_text:gmatch("[^\r\n]+") do
                line = line:gsub("{%x%x%x%x%x%x}", "")
                line = line:gsub("^%[%d+%]%s*", "")
                line = line:match("^%s*(.-)%s*$")
                if line ~= '' then
                    table.insert(lines, line)
                end
            end
            settings.last_spawn_dialog = lines
            save_settings()
            stats_counter.autospawn = stats_counter.autospawn + 1

            lua_thread.create(function()
                wait((settings.delay or 5) * 1000)
                for i = 1, #settings.priority do
                    local pri = settings.priority[i]
                    for idx, line in ipairs(lines) do
                        if line == pri then
                            sampSendDialogResponse(dialogId, 1, idx - 1, '')
                            return
                        end
                    end
                end
            end)
            return true 
        end
    end

    -- [Автопиар] диалоги подачи объявлений
    return piar_on_show_dialog(dialogId, style, title, button1, button2, text)
end

-- ============================================================================
-- 12.1 АВТО-СПОРТ (авто-выбор спорт-режима в радиальном меню)
-- ============================================================================
local autoSportAutomating   = false
local autoSportKeyAction    = false
local autoSportLastServerId = 0
local autoSportLastVehicle  = -1

ae.onArizonaDisplay = function(packet)
    if not settings.auto_sport_enabled then return end

    autoSportLastServerId = packet.server_id or 0
    local decodedStatus = ae.decode(packet)
    if not decodedStatus then return end

    local eventName = packet.event
    local blockEvents = {
        ["event.radialMenu.items"] = true,
        ["event.setActiveView"] = true,
        ["cef.toggleServerCursor"] = true
    }

    if autoSportAutomating and blockEvents[eventName] then
        if eventName == "event.radialMenu.items" then
            local data = packet.json
            local items = data[1] or data.items or data
            if type(items) ~= "table" then items = {} end

            local sportId = nil
            local comfortId = nil
            local nextId = nil

            for _, item in ipairs(items) do
                local title = item.title or ""
                local lowerTitle = title:lower()
                if lowerTitle:find("sport") or lowerTitle:find(u8:encode("спорт")) then
                    sportId = item.id or item.uid
                elseif lowerTitle:find("comfort") or lowerTitle:find(u8:encode("комфорт")) then
                    comfortId = item.id or item.uid
                elseif lowerTitle:find(u8:encode("вперед")) or lowerTitle:find("vpered") or lowerTitle:find("forward") then
                    nextId = item.id or item.uid
                end
            end

            if sportId then
                ae.send("onArizonaSend", { id = 18, text = "radialMenu.useAction | " .. sportId, server_id = autoSportLastServerId })
                lua_thread.create(function()
                    wait(200)
                    ae.send("onArizonaSendKey", { key = 27, _unknown = 0 })
                    autoSportAutomating = false
                end)
                return false
            elseif comfortId then
                lua_thread.create(function()
                    wait(100)
                    ae.send("onArizonaSendKey", { key = 27, _unknown = 0 })
                    autoSportAutomating = false
                end)
                return false
            elseif nextId then
                ae.send("onArizonaSend", { id = 18, text = "radialMenu.useAction | " .. nextId, server_id = autoSportLastServerId })
                return false
            else
                ae.send("onArizonaSendKey", { key = 27, _unknown = 0 })
                autoSportAutomating = false
                return false
            end
        end
        return false
    end
end

ae.onArizonaSendKey = function(packet)
    if settings.auto_sport_enabled and autoSportAutomating and packet.key == 82 and not autoSportKeyAction then return false end
end

local function auto_sport_thread()
    while true do
        wait(0)
        if settings.auto_sport_enabled then
            if isCharInAnyCar(PLAYER_PED) then
                local veh = storeCarCharIsInNoSave(PLAYER_PED)
                if getDriverOfCar(veh) == PLAYER_PED then
                    if veh ~= autoSportLastVehicle then
                        autoSportLastVehicle = veh
                        lua_thread.create(function()
                            autoSportAutomating = true
                            wait(1200)
                            if isCharInAnyCar(PLAYER_PED) then
                                autoSportKeyAction = true
                                ae.send("onArizonaSendKey", { key = 82, _unknown = 0 }) -- R
                                autoSportKeyAction = false
                                wait(3000)
                                autoSportAutomating = false
                            else
                                autoSportAutomating = false
                            end
                        end)
                    end
                end
            else
                autoSportLastVehicle = -1
                autoSportAutomating = false
            end
        else
            autoSportLastVehicle = -1
            autoSportAutomating = false
        end
    end
end

-- ============================================================================
-- 12.2 УВЕДОМЛЕНИЯ СКРИПТА (крупные тосты-«странички» внизу экрана)
-- ============================================================================
-- this.HideCursor = true (this — первый параметр draw-функции OnFrame)
-- запрещает показ игрового курсора мыши, плюс окну задан флаг NoInputs.
--
-- Если уведомлений в очереди несколько — они показываются ПО ОДНОМУ, как
-- странички, друг за другом, с точками-индикаторами внизу карточки и плавным
-- перелистыванием (slide + fade), а не наваливаются друг на друга.
--
-- text передавайте ОБЫЧНОЙ UTF-8 строкой, БЕЗ cyr(...) — cyr() нужен только
-- для sampAddChatMessage/диалогов SAMP (CP1251).
-- kind: 'info' (по умолчанию) | 'success' | 'warning' | 'error'
local dh_notifications  = {}
local dh_active         = nil
local dh_shown_in_batch = 0

local DH_NOTIFY_COLORS = {
    info    = imgui.ImVec4(0.55, 0.78, 1.00, 1.00),
    success = imgui.ImVec4(0.50, 0.92, 0.55, 1.00),
    warning = imgui.ImVec4(0.98, 0.80, 0.30, 1.00),
    error   = imgui.ImVec4(0.98, 0.42, 0.42, 1.00),
}

local DH_ENTER_TIME = 0.30 -- сек, появление (slide-up + fade-in, ease-out)
local DH_EXIT_TIME  = 0.22 -- сек, исчезновение (fade-out, ease-in)

local function dh_ease_out_cubic(t)
    t = t - 1
    return t * t * t + 1
end

local function dh_ease_in_cubic(t)
    return t * t * t
end

-- лёгкий "пружинистый" выезд с небольшим перелётом (как у баннеров iOS)
local function dh_ease_out_back(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local p = t - 1
    return 1 + c3 * p * p * p + c1 * p * p
end

local DH_ICON_GLYPH = {
    info    = faicons('CIRCLE_INFO'),
    success = faicons('CIRCLE_CHECK'),
    warning = faicons('TRIANGLE_EXCLAMATION'),
    error   = faicons('CIRCLE_XMARK'),
}

-- text: строка; kind: 'info'|'success'|'warning'|'error' (необязательно);
-- duration: сколько секунд держать на экране (по умолчанию 3.5)
function dh_notify(text, kind, duration)
    if not DH_NOTIFY_COLORS[kind] then kind = 'info' end
    table.insert(dh_notifications, {
        text = tostring(text),
        kind = kind,
        duration = tonumber(duration) or 3.5
    })
end

local DH_TOAST_FLAGS =
    imgui.WindowFlags.NoResize +
    imgui.WindowFlags.NoTitleBar +
    imgui.WindowFlags.NoCollapse +
    imgui.WindowFlags.NoMove +
    imgui.WindowFlags.NoScrollbar +
    imgui.WindowFlags.NoScrollWithMouse +
    imgui.WindowFlags.NoSavedSettings +
    imgui.WindowFlags.NoFocusOnAppearing +
    imgui.WindowFlags.NoBringToFrontOnFocus +
    imgui.WindowFlags.NoInputs +
    imgui.WindowFlags.AlwaysAutoResize

imgui.OnFrame(function()
    return dh_active ~= nil or #dh_notifications > 0
end, function(this)
    this.HideCursor = true
    local now = os.clock()

    -- если ничего не показывается сейчас — берём следующее из очереди
    if not dh_active and #dh_notifications > 0 then
        local item = table.remove(dh_notifications, 1)
        dh_shown_in_batch = dh_shown_in_batch + 1
        dh_active = {
            text        = item.text,
            kind        = item.kind,
            color       = DH_NOTIFY_COLORS[item.kind],
            duration    = item.duration,
            phase       = 'enter',
            phase_start = now,
            batch_index = dh_shown_in_batch,
        }
    end

    if not dh_active then return true end

    local elapsed = now - dh_active.phase_start
    local alpha, slide

    if dh_active.phase == 'enter' then
        local progress = math.min(elapsed / DH_ENTER_TIME, 1.0)
        alpha = dh_ease_out_cubic(progress)
        slide = (1 - dh_ease_out_back(progress)) * 46
        if progress >= 1.0 then
            dh_active.phase = 'hold'
            dh_active.phase_start = now
        end
    elseif dh_active.phase == 'hold' then
        alpha = 1.0
        slide = 0
        if elapsed >= dh_active.duration then
            dh_active.phase = 'exit'
            dh_active.phase_start = now
        end
    else -- exit
        local progress = math.min(elapsed / DH_EXIT_TIME, 1.0)
        local eased = dh_ease_in_cubic(progress)
        alpha = 1.0 - eased
        slide = -eased * 26
        if progress >= 1.0 then
            dh_active = nil
            if #dh_notifications == 0 then
                dh_shown_in_batch = 0
            end
            return true
        end
    end

    local color = dh_active.color
    local screen_x, screen_y = getScreenResolution()
    local bottom_margin = 70

    imgui.SetNextWindowBgAlpha(0.92 * alpha)
    imgui.SetNextWindowPos(
        imgui.ImVec2(screen_x / 2, screen_y - bottom_margin + slide),
        imgui.Cond.Always, imgui.ImVec2(0.5, 1.0))
    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(320, 0), imgui.ImVec2(680, 200))

    -- та же тема, что и у главного меню (DarkTheme) — просто с затуханием по alpha
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.30, 0.30, 0.30, 0.75 * alpha))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.95, 0.95, alpha))

    imgui.Begin('##dh_toast', nil, DH_TOAST_FLAGS)

    local glyph = DH_ICON_GLYPH[dh_active.kind] or DH_ICON_GLYPH.info
    imgui.TextColored(imgui.ImVec4(color.x, color.y, color.z, alpha), glyph)
    imgui.SameLine()
    imgui.TextWrapped(dh_active.text)

    -- точки-странички, если в очереди есть/было больше одного уведомления
    local batch_total = math.max(dh_active.batch_index + #dh_notifications, dh_active.batch_index)
    if batch_total > 1 then
        imgui.Spacing()
        local draw_list = imgui.GetWindowDrawList()
        local win_pos = imgui.GetWindowPos()
        local win_size = imgui.GetWindowSize()
        local dot_r = 2.6
        local dot_gap = 11
        local count = math.min(batch_total, 8)
        local display_index = math.min(dh_active.batch_index, count)
        local start_x = win_pos.x + win_size.x * 0.5 - ((count - 1) * dot_gap) / 2
        local dot_y = imgui.GetCursorScreenPos().y + 3
        for d = 1, count do
            local dot_color
            if d == display_index then
                dot_color = color_u32(color.x, color.y, color.z, alpha)
            else
                dot_color = color_u32(1.0, 1.0, 1.0, 0.18 * alpha)
            end
            draw_list:AddCircleFilled(imgui.ImVec2(start_x + (d - 1) * dot_gap, dot_y), dot_r, dot_color, 12)
        end
        imgui.Dummy(imgui.ImVec2(0, dot_r * 2))
    end

    imgui.End()
    imgui.PopStyleColor(2)

    return true
end)

-- ============================================================================
-- 13. ГЛАВНЫЙ ЦИКЛ СКРИПТА
-- ============================================================================
function main()
    while not isSampAvailable() do wait(0) end

    dh_notify(string.format('DH Script v%s запущен', CURRENT_VERSION), 'success', 4)

    check_updates_and_feed()
    sampRegisterChatCommand('dhtest', function()
        dh_notify('Тестовое уведомление DH', 'success', 3)
        dh_notify('Пример предупреждения', 'warning', 3)
        dh_notify('Пример ошибки', 'error', 3)
    end)
    sampRegisterChatCommand('dh', function()
        window[0] = not window[0]
        if window[0] then
            info_window[0] = true
        end
    end)

    lua_thread.create(function()
        while true do
            wait(100)
            piar_update()
        end
    end)

    lua_thread.create(auto_sport_thread)

    lua_thread.create(function()
        while true do
            wait(1000)
            if settings.auto_taxes_enabled and not auto_taxes_running then
                if settings.auto_taxes_next_run == 0 then
                    settings.auto_taxes_next_run = get_next_tax_run()
                    save_settings()
                elseif os.time() >= settings.auto_taxes_next_run then
                    settings.auto_taxes_next_run = get_next_tax_run(os.time())
                    save_settings()
                    doAutoTaxes(false)
                end
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(500)
            if settings.reconnect_enabled and settings.reconnect_use_timeout and start_connecting then
                local timeout_s = tonumber(settings.reconnect_timeout) or 8
                if (os.clock() - start_connecting) > timeout_s then
                    start_connecting = nil
                    schedule_reconnect('Таймаут подключения', tonumber(settings.reconnect_retry_delay) or 5)
                end
            end
        end
    end)

    while true do
        wait(0)
        if settings.super_stop_enabled
           and is_c_pressed
           and isCharInAnyCar(PLAYER_PED) then
            is_c_pressed = false
            stats_counter.superstop = stats_counter.superstop + 1
            sampSendChat('/limit 30')
            wait(250)
            sampSendChat('/limit 0')
        end
    end
end

-- ============================================================================
-- 14. ГОРЯЧИЕ КЛАВИШИ
-- ============================================================================
local VK_ESCAPE = 0x1B
addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    if (window[0] or info_window[0]) and msg == 0x0100 and wparam == VK_ESCAPE then
        window[0] = false
        info_window[0] = false
        consumeWindowMessage(true, false)
    end
    if msg == 0x0100 and wparam == VK_C then
        is_c_pressed = true
    elseif msg == 0x0101 and wparam == VK_C then
        is_c_pressed = false
    end
end)

-- ============================================================================
-- 15. ТЕМА И ХЕЛПЕРЫ ОФОРМЛЕНИЯ IMGUI
-- ============================================================================
function imgui.SectionTitle(text)
    imgui.TextColored(imgui.ImVec4(0.82, 0.82, 0.82, 1.00), text)
end

function imgui.DarkTheme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    style.WindowPadding = imgui.ImVec2(14, 12)
    style.FramePadding = imgui.ImVec2(8, 6)
    style.ItemSpacing = imgui.ImVec2(7, 7)
    style.ItemInnerSpacing = imgui.ImVec2(5, 5)
    style.TouchExtraPadding = imgui.ImVec2(0, 0)
    style.IndentSpacing = 0
    style.ScrollbarSize = 10
    style.GrabMinSize = 10
    style.WindowBorderSize = 1
    style.ChildBorderSize = 1
    style.PopupBorderSize = 1
    style.FrameBorderSize = 1
    style.TabBorderSize = 1
    style.WindowRounding = 8
    style.ChildRounding = 7
    style.FrameRounding = 6
    style.PopupRounding = 7
    style.ScrollbarRounding = 7
    style.GrabRounding = 6
    style.TabRounding = 6
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
    style.SelectableTextAlign = imgui.ImVec2(0.0, 0.5)
    local colors = style.Colors
    colors[imgui.Col.Text]                  = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
    colors[imgui.Col.TextDisabled]          = imgui.ImVec4(0.58, 0.58, 0.58, 1.00)
    colors[imgui.Col.WindowBg]              = imgui.ImVec4(0.070, 0.070, 0.070, 1.00)
    colors[imgui.Col.ChildBg]               = imgui.ImVec4(0.090, 0.090, 0.090, 1.00)
    colors[imgui.Col.PopupBg]               = imgui.ImVec4(0.095, 0.095, 0.095, 0.98)
    colors[imgui.Col.Border]                = imgui.ImVec4(0.30, 0.30, 0.30, 0.75)
    colors[imgui.Col.BorderShadow]          = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.FrameBg]               = imgui.ImVec4(0.16, 0.16, 0.16, 1.00)
    colors[imgui.Col.FrameBgHovered]        = imgui.ImVec4(0.24, 0.24, 0.24, 1.00)
    colors[imgui.Col.FrameBgActive]         = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
    colors[imgui.Col.TitleBg]               = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
    colors[imgui.Col.TitleBgActive]         = imgui.ImVec4(0.16, 0.16, 0.16, 1.00)
    colors[imgui.Col.TitleBgCollapsed]      = imgui.ImVec4(0.08, 0.08, 0.08, 1.00)
    colors[imgui.Col.MenuBarBg]             = imgui.ImVec4(0.11, 0.11, 0.11, 1.00)
    colors[imgui.Col.ScrollbarBg]           = imgui.ImVec4(0.08, 0.08, 0.08, 1.00)
    colors[imgui.Col.ScrollbarGrab]         = imgui.ImVec4(0.28, 0.28, 0.28, 1.00)
    colors[imgui.Col.ScrollbarGrabHovered]  = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.ScrollbarGrabActive]   = imgui.ImVec4(0.48, 0.48, 0.48, 1.00)
    colors[imgui.Col.CheckMark]             = imgui.ImVec4(0.85, 0.85, 0.85, 1.00)
    colors[imgui.Col.SliderGrab]            = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[imgui.Col.SliderGrabActive]      = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)
    colors[imgui.Col.Button]                = imgui.ImVec4(0.18, 0.18, 0.18, 1.00)
    colors[imgui.Col.ButtonHovered]         = imgui.ImVec4(0.28, 0.28, 0.28, 1.00)
    colors[imgui.Col.ButtonActive]          = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.Header]                = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
    colors[imgui.Col.HeaderHovered]         = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
    colors[imgui.Col.HeaderActive]          = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
    colors[imgui.Col.Separator]             = imgui.ImVec4(0.28, 0.28, 0.28, 0.85)
    colors[imgui.Col.SeparatorHovered]      = imgui.ImVec4(0.45, 0.45, 0.45, 1.00)
    colors[imgui.Col.SeparatorActive]       = imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
    colors[imgui.Col.ResizeGrip]            = imgui.ImVec4(0.50, 0.50, 0.50, 0.25)
    colors[imgui.Col.ResizeGripHovered]     = imgui.ImVec4(0.60, 0.60, 0.60, 0.67)
    colors[imgui.Col.ResizeGripActive]      = imgui.ImVec4(0.70, 0.70, 0.70, 0.95)
    colors[imgui.Col.Tab]                   = imgui.ImVec4(0.14, 0.14, 0.14, 1.00)
    colors[imgui.Col.TabHovered]            = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
    colors[imgui.Col.TabActive]             = imgui.ImVec4(0.24, 0.24, 0.24, 1.00)
    colors[imgui.Col.TabUnfocused]          = imgui.ImVec4(0.09, 0.09, 0.09, 1.00)
    colors[imgui.Col.TabUnfocusedActive]    = imgui.ImVec4(0.17, 0.17, 0.17, 1.00)
    colors[imgui.Col.TextSelectedBg]        = imgui.ImVec4(0.45, 0.45, 0.45, 0.45)
    colors[imgui.Col.DragDropTarget]        = imgui.ImVec4(0.80, 0.80, 0.80, 0.95)
    colors[imgui.Col.NavHighlight]          = imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
    colors[imgui.Col.NavWindowingHighlight] = imgui.ImVec4(0.90, 0.90, 0.90, 0.70)
    colors[imgui.Col.NavWindowingDimBg]     = imgui.ImVec4(0.20, 0.20, 0.20, 0.20)
    colors[imgui.Col.ModalWindowDimBg]      = imgui.ImVec4(0.02, 0.02, 0.02, 0.72)
end
