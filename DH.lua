script_name('DH')
script_version('4.2.5')
script_authors('Deo')

local sampev    = require 'lib.samp.events'
local imgui     = require 'mimgui'
local encoding  = require 'encoding'
encoding.default = 'UTF-8'
local cyr = encoding.CP1251

require 'sampfuncs'

local VK_C = 0x43
local is_c_pressed = false
local window

local graffitiFont = renderCreateFont("ShellyAllegroC", 8, 5)
local zakladkaFont  = renderCreateFont("ShellyAllegroC", 8, 5)
local nextAutoClick = 0

local gangs = {
    { name = "The Rifa", color = 0xFF6666FF },
    { name = "Grove Street", color = 0xFF009327 },
    { name = "East Side Ballas", color = 0xFFCC00CC },
    { name = "Night Wolves", color = 0xFF594F4F },
    { name = "Los Santos Vagos", color = 0xFFD1DB1C },
    { name = "Varrios Los Aztecas", color = 0xFF00FFE2 }
}

local function generate_path(p)
    return getWorkingDirectory() .. '/' .. p
end

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

local settings = jsoncfg.load({
    priority = {},
    enabled = false,
    delay = 5,
    last_spawn_dialog = {},

    reconnect_enabled      = false,
    reconnect_delay        = 3,
    reconnect_retry_delay  = 5,
    reconnect_use_timeout  = true,
    reconnect_timeout      = 8,
    reconnect_on_ban       = false,
    reconnect_delay_banned = 60,

    super_stop_enabled  = false,

    graffiti_render_enabled    = false,
    graffiti_autoclick_enabled = true,
    zakladka_render_enabled    = false,
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
if type(settings.graffiti_render_enabled) ~= 'boolean' then settings.graffiti_render_enabled = false end
if type(settings.graffiti_autoclick_enabled) ~= 'boolean' then settings.graffiti_autoclick_enabled = true end
if type(settings.zakladka_render_enabled) ~= 'boolean' then settings.zakladka_render_enabled = false end

local function save_settings()
    jsoncfg.save(settings, generate_path('config/DH.json'))
end

-- ======================= РЕКОННЕКТ =======================

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

-- Вспомогательные функции
local function isInputActive()
    return isCursorActive()
        or sampIsChatInputActive()
        or sampIsDialogActive()
        or window[0]
end

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

-- =========================== MIMGUI ИНТЕРФЕЙС ===========================

window            = imgui.new.bool(false)
local ass_enabled = imgui.new.bool(settings.enabled)
local ass_delay   = imgui.new.int(settings.delay)

local reconnect_enabled      = imgui.new.bool(settings.reconnect_enabled == true)
local reconnect_delay        = imgui.new.float(tonumber(settings.reconnect_delay) or 3)
local reconnect_retry_delay  = imgui.new.float(tonumber(settings.reconnect_retry_delay) or 5)
local reconnect_use_timeout  = imgui.new.bool(settings.reconnect_use_timeout ~= false)
local reconnect_timeout      = imgui.new.float(tonumber(settings.reconnect_timeout) or 8)
local reconnect_on_ban       = imgui.new.bool(settings.reconnect_on_ban == true)
local reconnect_delay_banned = imgui.new.float(tonumber(settings.reconnect_delay_banned) or 60)

local super_stop_enabled  = imgui.new.bool(settings.super_stop_enabled == true)

local graffiti_render_enabled    = imgui.new.bool(settings.graffiti_render_enabled == true)
local graffiti_autoclick_enabled = imgui.new.bool(settings.graffiti_autoclick_enabled == true)
local zakladka_render_enabled    = imgui.new.bool(settings.zakladka_render_enabled == true)

local drag_mode = nil
local drag_priority_index = nil
local drag_available_value = nil
local current_drop_index = nil

imgui.OnInitialize(function()
    imgui.DarkTheme()
    imgui.GetIO().IniFilename = nil
end)

local newFrame = imgui.OnFrame(
    function() return window[0] end,
    function()
        local x, y = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(x / 2, y / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(480, 0), imgui.Cond.FirstUseEver)

        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
            + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.AlwaysAutoResize
        imgui.Begin('DH', window, flags)

        local mouse = imgui.GetIO().MousePos
        local item_height = 24
        local item_spacing_y = imgui.GetStyle().ItemSpacing.y
        local child_pad_y = imgui.GetStyle().WindowPadding.y
        local max_box_height = math.max(180, y * 0.45)
        local main_draw_list = imgui.GetWindowDrawList()

        imgui.BeginTabBar('##ass_tabs')

        if imgui.BeginTabItem('Автоспавн') then

            if imgui.Checkbox('Включить автоспавн', ass_enabled) then
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
            imgui.TextDisabled('Перетаскивайте пункты мышью. ПКМ по пункту — удалить его из приоритетов.')
            imgui.Spacing()

            local priority_height = list_box_height(#settings.priority, item_height, item_spacing_y, child_pad_y, max_box_height)
            local priority_pos = imgui.GetCursorScreenPos()
            local priority_width = imgui.GetContentRegionAvail().x
            local priority_rect = make_rect(priority_pos, priority_width, priority_height)
            local priority_slots = {}
            local priority_draw_list = nil
            local priority_inner_pos = nil
            local priority_item_width = 0

            imgui.BeginChild('##priority_list', imgui.ImVec2(0, priority_height), true)
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
                    table.insert(priority_slots, {
                        rect = item_rect,
                        original_index = i,
                        value = value
                    })

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
                imgui.TextDisabled('Список пуст. Перетащите сюда место спавна из списка ниже.')
            end

            imgui.EndChild()

            imgui.Spacing()
            imgui.SectionTitle('Последний диалог спавна')
            imgui.TextDisabled('Перетащите нужное место в список приоритетов выше.')
            imgui.TextDisabled('Уже добавленные пункты здесь автоматически скрываются.')
            imgui.Spacing()

            local available_item_height = 22
            local available_height = list_box_height(count_available_items(), available_item_height, item_spacing_y, child_pad_y, max_box_height)
            local available_pos = imgui.GetCursorScreenPos()
            local available_width = imgui.GetContentRegionAvail().x
            local available_rect = make_rect(available_pos, available_width, available_height)
            local available_draw_list = nil
            local available_inner_pos = nil
            local available_item_width = 0
            local available_slots = {}

            imgui.BeginChild('##available_list', imgui.ImVec2(0, available_height), true)
            available_draw_list = imgui.GetWindowDrawList()
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
                    table.insert(available_slots, { rect = item_rect, value = value })

                    imgui.Button(value .. '##available_' .. tostring(shown), imgui.ImVec2(-1, available_item_height))

                    if imgui.IsItemActive() and imgui.IsMouseDragging(0, 4.0) then
                        drag_mode = 'available'
                        drag_available_value = value
                        drag_priority_index = nil
                    end

                    if imgui.IsItemHovered() and drag_mode == nil then
                        imgui.SetTooltip('Зажмите ЛКМ и перетащите в список приоритетов.')
                    end
                end
            end

            if shown == 0 then
                imgui.Spacing()
                if #settings.last_spawn_dialog == 0 then
                    imgui.TextDisabled('Данные появятся после открытия диалога выбора места спавна.')
                else
                    imgui.TextDisabled('Все места из последнего диалога уже добавлены в приоритеты.')
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

        if imgui.BeginTabItem('Реконнект') then
            imgui.Spacing()

            if imgui.Checkbox('Включить автопереподключение', reconnect_enabled) then
                settings.reconnect_enabled = reconnect_enabled[0]
                save_settings()
            end
            imgui.TextDisabled('Переподключает при обрыве связи, кике\nи закрытии соединения сервером (рестарт).\nПопытки бесконечны, пока сервер не поднимется.')

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
                imgui.TextDisabled('Если сервер не поднялся после рестарта,\nскрипт будет пробовать снова и снова,\nбез ограничения по числу попыток.')

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

        if imgui.BeginTabItem('Функции') then
            imgui.Spacing()

            if imgui.Checkbox('Супер стоп (Клавиша C)', super_stop_enabled) then
                settings.super_stop_enabled = super_stop_enabled[0]
                save_settings()
            end
            imgui.TextDisabled('При зажатии клавиши C в транспорте\nмгновенно останавливает его.')

            imgui.EndTabItem()
        end

        if imgui.BeginTabItem('Графити') then
            imgui.Spacing()

            if imgui.Checkbox('Отрисовка графити', graffiti_render_enabled) then
                settings.graffiti_render_enabled = graffiti_render_enabled[0]
                save_settings()
            end
            imgui.TextDisabled('Рисует линии и подписи до граффити банд на карте.')

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox('Автоклик по графити', graffiti_autoclick_enabled) then
                settings.graffiti_autoclick_enabled = graffiti_autoclick_enabled[0]
                if settings.graffiti_autoclick_enabled then nextAutoClick = 0 end
                save_settings()
            end
            imgui.TextDisabled('Автоматически кликает на текстдравы\nс граффити (particle:bloodpool_64).')

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox('Отрисовка закладок', zakladka_render_enabled) then
                settings.zakladka_render_enabled = zakladka_render_enabled[0]
                save_settings()
            end
            imgui.TextDisabled('Рисует линии и подписи до закладок на карте.')

            imgui.EndTabItem()
        end

        imgui.EndTabBar()

        imgui.End()
    end
)

function sampev.onShowDialog(id, style, title, b1, b2, text)
    title = cyr:decode(title)
    text  = cyr:decode(text)

    if title:find('Выбор места спавна') then
        local parsed = {}
        for n in text:gmatch('[^\r\n]+') do
            local line = n:match('%[%d+%] %{ffffff%}%s*(.+)')
            if line then
                if line:find('Сохраненная точка') then
                    table.insert(parsed, 'Сохраненная точка')
                else
                    table.insert(parsed, line)
                end
            else
                table.insert(parsed, '')
            end
        end

        settings.last_spawn_dialog = parsed
        save_settings()

        if settings.enabled then
            for i = 1, #settings.priority do
                local pri = settings.priority[i]
                for idx = 1, #parsed do
                    if parsed[idx] == pri then
                        local response_index = idx - 1
                        local delay_ms = settings.delay * 1000

                        lua_thread.create(function()
                            local waited = 0
                            local step = 100

                            while waited < delay_ms do
                                wait(step)
                                waited = waited + step

                                if not (sampIsDialogActive() and sampGetCurrentDialogId() == id) then
                                    return
                                end
                            end

                            sampSendDialogResponse(id, 1, response_index, '')
                            if sampIsDialogActive() then
                                sampCloseCurrentDialogWithButton(1)
                            end
                        end)

                        return
                    end
                end
            end
        end
    end
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
end

function main()
    while not isSampAvailable() do wait(0) end
    sampAddChatMessage(cyr('[DH] загружен'), 0xffcccccc)

    sampRegisterChatCommand('dh', function()
        window[0] = not window[0]
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
           and isCharInAnyCar(PLAYER_PED)
           and not isInputActive() then

            is_c_pressed = false
            sampSendChat('/limit 30')
            wait(250)
            sampSendChat('/limit 0')
        end

        local now = getGameTimer()
        if settings.graffiti_autoclick_enabled and now >= nextAutoClick then
            for id = 0, 2304 do
                if sampTextdrawIsExists(id) then
                    local text = sampTextdrawGetString(id)
                    if text and text:find("particle:bloodpool_64") then
                        sampSendClickTextdraw(id)
                        nextAutoClick = now + 100
                        break
                    end
                end
            end
        end

        if settings.graffiti_render_enabled then
            for textLabelId = 0, 2048 do
                if sampIs3dTextDefined(textLabelId) then
                    local rawText, _, graffitiX, graffitiY, graffitiZ = sampGet3dTextInfoById(textLabelId)
                    local gang

                    if rawText then
                        for _, candidate in ipairs(gangs) do
                            if rawText:find(candidate.name, 1, true) then
                                gang = candidate
                                break
                            end
                        end
                    end

                    if gang then
                        local textWithoutColorTags = rawText:gsub("{%x%x%x%x%x%x}", "")
                        local firstLine = textWithoutColorTags:match("([^\r\n]+)")
                        local hasTextOnSecondLine = textWithoutColorTags:match("[^\r\n]+[\r\n]+(.+)") ~= nil

                        if firstLine and firstLine:find(":", 1, true) and not hasTextOnSecondLine and isPointOnScreen(graffitiX, graffitiY, graffitiZ, 3.0) then
                            local playerWorldX, playerWorldY, playerWorldZ = getCharCoordinates(PLAYER_PED)
                            local graffitiScreenX, graffitiScreenY = convert3DCoordsToScreen(graffitiX, graffitiY, graffitiZ)
                            local playerScreenX, playerScreenY = convert3DCoordsToScreen(playerWorldX, playerWorldY, playerWorldZ)
                            local distance = getDistanceBetweenCoords3d(playerWorldX, playerWorldY, playerWorldZ, graffitiX, graffitiY, graffitiZ)
                            local label = firstLine:match(":%s*(.+)") or gang.name

                            renderDrawLine(graffitiScreenX, graffitiScreenY, playerScreenX, playerScreenY, 1.5, gang.color)
                            renderFontDrawText(graffitiFont, string.format("%s [%.1fm]", label, distance), graffitiScreenX + 5, graffitiScreenY - 12, gang.color)
                        end
                    end
                end
            end
        end

        if settings.zakladka_render_enabled then
            for textLabelId = 0, 2048 do
                if sampIs3dTextDefined(textLabelId) then
                    local text, _, zakladkaX, zakladkaY, zakladkaZ = sampGet3dTextInfoById(textLabelId)
                    if text and text:find("Закладка", 1, true) and isPointOnScreen(zakladkaX, zakladkaY, zakladkaZ, 3.0) then
                        local playerX, playerY, playerZ = getCharCoordinates(PLAYER_PED)
                        local zakladkaScreenX, zakladkaScreenY = convert3DCoordsToScreen(zakladkaX, zakladkaY, zakladkaZ)
                        local playerScreenX, playerScreenY = convert3DCoordsToScreen(playerX, playerY, playerZ)

                        renderDrawLine(zakladkaScreenX, zakladkaScreenY, playerScreenX, playerScreenY, 1.5, 0xFF9fd166)
                        renderFontDrawText(zakladkaFont, "{9fd166}Закладка", zakladkaScreenX, zakladkaScreenY, -1)
                    end
                end
            end
        end
    end
end

local VK_ESCAPE = 0x1B

addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    if window[0] and msg == 0x0100 and wparam == VK_ESCAPE then
        window[0] = false
        consumeWindowMessage(true, false)
    end

    if msg == 0x0100 and wparam == VK_C then
        if not isInputActive() then
            is_c_pressed = true
        end
    elseif msg == 0x0101 and wparam == VK_C then
        is_c_pressed = false
    end
end)

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
    imgui.SetCursorPosY(imgui.GetCursorPosY() + 8)
end

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