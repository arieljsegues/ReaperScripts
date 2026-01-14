-- Script: Verificar Teclas Ocupadas y Disponibles (ImGui)
-- Lenguaje: Lua para REAPER + ImGui
-- Descripción: Interfaz gráfica amigable para visualizar atajos disponibles y ocupados

local r = reaper

-- Crear contexto ImGui
local ctx = r.ImGui_CreateContext('REAPER Shortcut Analyzer')
local FLT_MIN, FLT_MAX = r.ImGui_NumericLimits_Float()

-- Variables de estado
local report_data = {}
local total_occupied = 0
local total_free = 0
local is_report_generated = false
local is_generating = false
local search_filter = ""
local show_only_available = false
local selected_group = 0  -- 0 = Todas, 1-6 = grupos específicos

-- Colores personalizados
local COLOR_AVAILABLE = 0x00FF00FF  -- Verde
local COLOR_OCCUPIED = 0xFF5050FF   -- Rojo
local COLOR_HEADER = 0x66DDFFFF     -- Azul claro
local COLOR_SUMMARY = 0xFFFF00FF    -- Amarillo

-- Función para generar el reporte
function generate_report()
    report_data = {}
    total_occupied = 0
    total_free = 0
    
    local section = r.SectionFromUniqueID(0)
    
    -- Obtener atajos ocupados
    local occupied_map = {}
    local action_idx = 0
    
    while true do
        local cmdID = r.kbd_enumerateActions(section, action_idx)
        if cmdID == 0 or cmdID == nil then break end
        
        local shortcut_count = r.CountActionShortcuts(section, cmdID)
        if shortcut_count > 0 then
            for j = 0, shortcut_count - 1 do
                local retval, desc = r.GetActionShortcutDesc(section, cmdID, j)
                if retval then
                    occupied_map[desc:upper()] = true
                end
            end
        end
        action_idx = action_idx + 1
    end
    
    -- Definir teclas a comprobar
    local keys = {}
    for i = 65, 90 do table.insert(keys, string.char(i)) end
    for i = 0, 9 do table.insert(keys, tostring(i)) end
    for i = 1, 12 do table.insert(keys, "F" .. i) end
    
    -- Definir combinaciones
    local combinations = {
        { label = "No Modifier", prefix = "" },
        { label = "Ctrl +", prefix = "Ctrl+" },
        { label = "Shift +", prefix = "Shift+" },
        { label = "Alt +", prefix = "Alt+" },
        { label = "Ctrl + Shift +", prefix = "Ctrl+Shift+" },
        { label = "Ctrl + Alt +", prefix = "Ctrl+Alt+" }
    }
    
    -- Generar reporte por grupo
    for idx, combo in ipairs(combinations) do
        local group = {
            label = combo.label,
            entries = {},
            available_count = 0,
            occupied_count = 0
        }
        
        for _, key in ipairs(keys) do
            local check_str = combo.prefix .. key
            local is_occupied = occupied_map[check_str:upper()]
            
            if is_occupied then
                group.occupied_count = group.occupied_count + 1
                total_occupied = total_occupied + 1
            else
                group.available_count = group.available_count + 1
                total_free = total_free + 1
            end
            
            table.insert(group.entries, {
                shortcut = check_str,
                key = key,
                occupied = is_occupied
            })
        end
        
        table.insert(report_data, group)
    end
    
    is_report_generated = true
end

-- Función para filtrar entradas
function filter_entry(entry)
    if search_filter ~= "" then
        if not string.find(entry.shortcut:upper(), search_filter:upper()) then
            return false
        end
    end
    
    if show_only_available and entry.occupied then
        return false
    end
    
    return true
end

-- Loop principal de ImGui
function loop()
    -- Generar reporte automáticamente al iniciar
    if not is_report_generated and not is_generating then
        is_generating = true
        generate_report()
    end
    
    local visible, open = r.ImGui_Begin(ctx, 'REAPER Shortcut Analyzer', true)
    if visible then
        
        -- Panel superior: Resumen y controles
        draw_header()
        
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        -- Contenido principal
        if not is_report_generated then
            draw_loading()
        else
            draw_report()
        end
        
        r.ImGui_End(ctx)
    end
    
    if open and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        open = false
    end
    
    if open then
        r.defer(loop)
    end
end

-- Dibujar encabezado con resumen
function draw_header()
    if is_report_generated then
        -- Resumen estadístico
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR_SUMMARY)
        r.ImGui_Text(ctx, "SUMMARY")
        r.ImGui_PopStyleColor(ctx)
        
        r.ImGui_Indent(ctx, 20)
        r.ImGui_Text(ctx, string.format("✓ Available: %d", total_free))
        r.ImGui_SameLine(ctx, 200)
        r.ImGui_Text(ctx, string.format("x Occupied: %d", total_occupied))
        r.ImGui_SameLine(ctx, 380)
        local total = total_free + total_occupied
        r.ImGui_Text(ctx, string.format("Total: %d", total))
        r.ImGui_Unindent(ctx, 20)
        
        r.ImGui_Spacing(ctx)
        
        -- Barra de búsqueda
        r.ImGui_SetNextItemWidth(ctx, 300)
        local retval, new_filter = r.ImGui_InputTextWithHint(ctx, '##search', 'Search shortcut...', search_filter)
        if retval then
            search_filter = new_filter
        end
        
        r.ImGui_SameLine(ctx)
        local clicked, new_toggle = r.ImGui_Checkbox(ctx, 'Available only', show_only_available)
        if clicked then
            show_only_available = new_toggle
        end
        
        r.ImGui_SameLine(ctx, 520)
        if r.ImGui_Button(ctx, 'Refresh') then
            generate_report()
        end
    end
end

-- Dibujar pantalla de carga
function draw_loading()
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Analyzing Action List...")
    r.ImGui_Text(ctx, "Please wait...")
end

-- Dibujar reporte completo
function draw_report()
    if r.ImGui_BeginChild(ctx, 'ReportContent') then
        
        for group_idx, group in ipairs(report_data) do
            -- Encabezado del grupo (collapsible)
            local header_text = string.format("%s   [%d available / %d occupied]", 
                group.label, group.available_count, group.occupied_count)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x334455FF)
            local is_open = r.ImGui_CollapsingHeader(ctx, header_text, r.ImGui_TreeNodeFlags_DefaultOpen())
            r.ImGui_PopStyleColor(ctx)
            
            if is_open then
                r.ImGui_Indent(ctx, 15)
                
                -- Tabla de atajos
                if r.ImGui_BeginTable(ctx, 'shortcuts_' .. group_idx, 2, r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_BordersInnerV()) then
                    r.ImGui_TableSetupColumn(ctx, 'Shortcut', r.ImGui_TableColumnFlags_WidthFixed(), 180)
                    r.ImGui_TableSetupColumn(ctx, 'Status', r.ImGui_TableColumnFlags_WidthStretch())
                    
                    for _, entry in ipairs(group.entries) do
                        if filter_entry(entry) then
                            r.ImGui_TableNextRow(ctx)
                            
                            -- Columna: Atajo
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_Text(ctx, entry.shortcut)
                            
                            -- Columna: Estado
                            r.ImGui_TableNextColumn(ctx)
                            if entry.occupied then
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR_OCCUPIED)
                                r.ImGui_Text(ctx, 'OCCUPIED')
                                r.ImGui_PopStyleColor(ctx)
                            else
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR_AVAILABLE)
                                r.ImGui_Text(ctx, 'AVAILABLE')
                                r.ImGui_PopStyleColor(ctx)
                            end
                        end
                    end
                    
                    r.ImGui_EndTable(ctx)
                end
                
                r.ImGui_Unindent(ctx, 15)
                r.ImGui_Spacing(ctx)
            end
        end
        
        r.ImGui_EndChild(ctx)
    end
end

-- Iniciar el script
r.defer(loop)