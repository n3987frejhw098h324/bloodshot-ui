if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Library = {
    Version = "2.1.0",
    ConfigVersion = 2,
    Flags = {},
    Theme = {
        Background = Color3.fromRGB(7, 7, 9),
        Surface = Color3.fromRGB(14, 10, 12),
        SurfaceAlt = Color3.fromRGB(24, 13, 16),
        Border = Color3.fromRGB(69, 27, 34),
        Text = Color3.fromRGB(245, 238, 239),
        MutedText = Color3.fromRGB(157, 132, 136),
        Accent = Color3.fromRGB(196, 28, 48),
        AccentDark = Color3.fromRGB(91, 12, 24),
        Success = Color3.fromRGB(68, 190, 116),
        Warning = Color3.fromRGB(230, 164, 58),
        Error = Color3.fromRGB(238, 55, 75),
        BackgroundGradient = Color3.fromRGB(24, 7, 11),
        SurfaceGradient = Color3.fromRGB(38, 10, 16),
        AccentGradient = Color3.fromRGB(104, 8, 22),
        Disabled = Color3.fromRGB(82, 72, 75),
        Focus = Color3.fromRGB(245, 92, 112),
        Overlay = Color3.fromRGB(3, 3, 4),
        CornerRadius = 6,
        ControlTransparency = 0.8,
        Font = Enum.Font.Gotham,
        FontMedium = Enum.Font.GothamMedium,
        FontBold = Enum.Font.GothamBold,
    },
    ThemePresets = {},
    Densities = {
        Compact = { ControlSpacing = 5, SectionSpacing = 10, TabHeight = 30, TabSpacing = 3, ContentPadding = 10, SidebarPadding = 8, TopbarHeight = 50 },
        Comfortable = {},
        Spacious = { ControlSpacing = 10, SectionSpacing = 18, TabHeight = 42, TabSpacing = 7, ContentPadding = 18, SidebarPadding = 12, TopbarHeight = 64 },
    },
    Strings = {
        Confirm = "Confirm",
        Cancel = "Cancel",
        Close = "Close",
        Reset = "Reset",
        Notification = "Notification",
        EnterValue = "Enter value...",
        Search = "Search",
        Loading = "Loading",
        Copied = "Copied",
        SelectAll = "All",
        SelectNone = "None",
        Clear = "Clear",
        Copy = "Copy",
        Rainbow = "Rainbow",
        SearchPlaceholder = "Search...",
        SelectPlaceholder = "Select...",
        NoOptions = "No options",
        ControlSearch = "control or section name",
        MadeWith = "Made with <3 by R",
        Unbound = "Unbound",
        PressAnyKey = "Press key...",
        SearchNothingFound = "No matches",
        AreYouSure = "Are you sure?",
    },
    _windows = {},
    _connections = {},
    _themeBindings = {},
    _flagSetters = {},
    _notifications = {},
    _destroyed = false,
    _animationSpeed = 1,
    _reducedMotion = false,
    _flagTypes = {},
    _flagListeners = {},
    _bindings = {},
    _dependencySubs = {},
    _controlDisposers = {},
    _specControls = {},
    _windowOrder = {},
    _focusedWindow = nil,
    _gamepadEnabled = true,
    _autoSave = nil,
    _geometry = nil,
    _listeners = {},
}

-- Generic subscribe/emit pair behind every Bloodshot event (tab changes,
-- visibility, geometry, spec export). Listeners are copied before dispatch so a
-- callback may unbind itself mid-emit, and errors never abort the fan-out.
-- _subscribe remembers any extra arguments given after the callback, and _emit
-- replays them before the emit-time arguments; events raised by a window already
-- pass the window as their first emit-time argument, so those subscribers store
-- nothing extra.
function Library:_subscribe(event, callback, ...)
    if type(callback) ~= "function" then
        return false, "Event handlers must be functions"
    end
    local listeners = self._listeners[event]
    if not listeners then
        listeners = {}
        self._listeners[event] = listeners
    end
    local entry = { Callback = callback, Args = table.pack(...), Alive = true }
    table.insert(listeners, entry)
    return {
        Event = event,
        Unbind = function()
            entry.Alive = false
            for index, candidate in ipairs(listeners) do
                if candidate == entry then
                    table.remove(listeners, index)
                    break
                end
            end
            return true
        end,
    }
end

-- Emits to every handler on the bus. Args captured at subscribe time are passed
-- first (this is how Window:_subscribe injects the window), followed by anything
-- supplied at emit time.
function Library:_emit(event, ...)
    local listeners = self._listeners[event]
    if not listeners then return 0 end
    local snapshot = {}
    for index, entry in ipairs(listeners) do
        snapshot[index] = entry
    end
    local fired = 0
    for _, entry in ipairs(snapshot) do
        if entry.Alive then
            fired += 1
            local emitted = table.pack(...)
            local call = {}
            local count = 0
            for index = 1, entry.Args.n do
                count += 1
                call[count] = entry.Args[index]
            end
            for index = 1, emitted.n do
                count += 1
                call[count] = emitted[index]
            end
            -- pcall inlined rather than using safeCall: _emit is defined before
            -- safeCall exists, so a safeCall call here would resolve to a global.
            local ok, err = pcall(entry.Callback, table.unpack(call, 1, count))
            if not ok then
                warn("[Bloodshot UI] " .. tostring(event) .. " listener error: " .. tostring(err))
            end
        end
    end
    return fired
end

-- Drops every handler for one event, or the whole table when event is nil.
function Library:_clearListeners(event)
    if event == nil then
        table.clear(self._listeners)
        return true
    end
    self._listeners[event] = nil
    return true
end

function Library:On(event, callback)
    return self:_subscribe(event, callback)
end

function Library:Off(handle)
    if type(handle) == "table" and type(handle.Unbind) == "function" then
        return handle:Unbind()
    end
    return false
end

-- User-facing copy lookup. Library:SetStrings overrides these per session.
local function T(key)
    local override = Library._stringOverrides
    if override and override[key] ~= nil then
        return override[key]
    end
    local strings = Library.Strings
    local value = strings[key]
    if value == nil then
        return key
    end
    return value
end

local DEFAULT_THEME
-- `seen` makes the copy cycle-safe. Options tables are copied into control.Spec
-- verbatim, and callers legitimately pass live library objects (AddSearch's
-- Target = tab, for instance), whose tab -> section -> window -> tab back
-- references would otherwise recurse until the stack ran out.
local function copyTable(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then return seen[source] end
    local result = {}
    seen[source] = result
    for key, value in pairs(source) do
        result[key] = copyTable(value, seen)
    end
    return result
end

DEFAULT_THEME = copyTable(Library.Theme)
Library.ThemePresets.Bloodshot = copyTable(DEFAULT_THEME)
Library.ThemePresets["Crimson Light"] = {
    Background = Color3.fromRGB(244, 238, 239),
    Surface = Color3.fromRGB(255, 250, 251),
    SurfaceAlt = Color3.fromRGB(237, 225, 228),
    Border = Color3.fromRGB(183, 142, 150),
    Text = Color3.fromRGB(38, 20, 24),
    MutedText = Color3.fromRGB(105, 78, 84),
    Accent = Color3.fromRGB(185, 25, 51),
    AccentDark = Color3.fromRGB(105, 14, 30),
    Success = Color3.fromRGB(36, 145, 82),
    Warning = Color3.fromRGB(184, 112, 18),
    Error = Color3.fromRGB(205, 38, 60),
    BackgroundGradient = Color3.fromRGB(231, 210, 215),
    SurfaceGradient = Color3.fromRGB(245, 224, 229),
    AccentGradient = Color3.fromRGB(223, 77, 99),
    Disabled = Color3.fromRGB(155, 143, 146),
    Focus = Color3.fromRGB(225, 44, 73),
    Overlay = Color3.fromRGB(50, 38, 41),
}
Library.ThemePresets["High Contrast"] = {
    Background = Color3.fromRGB(0, 0, 0),
    Surface = Color3.fromRGB(8, 8, 8),
    SurfaceAlt = Color3.fromRGB(20, 20, 20),
    Border = Color3.fromRGB(235, 235, 235),
    Text = Color3.fromRGB(255, 255, 255),
    MutedText = Color3.fromRGB(210, 210, 210),
    Accent = Color3.fromRGB(255, 45, 75),
    AccentDark = Color3.fromRGB(155, 0, 24),
    Success = Color3.fromRGB(40, 255, 130),
    Warning = Color3.fromRGB(255, 205, 40),
    Error = Color3.fromRGB(255, 45, 75),
    BackgroundGradient = Color3.fromRGB(16, 0, 3),
    SurfaceGradient = Color3.fromRGB(35, 0, 7),
    AccentGradient = Color3.fromRGB(255, 90, 110),
    Disabled = Color3.fromRGB(125, 125, 125),
    Focus = Color3.fromRGB(255, 235, 70),
    Overlay = Color3.fromRGB(0, 0, 0),
}

local function new(className, properties, children)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        if property ~= "Parent" then
            object[property] = value
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = object
    end
    if properties and properties.Parent then
        object.Parent = properties.Parent
    end
    return object
end

local function corner(parent, radius)
    return new("UICorner", {
        CornerRadius = UDim.new(0, radius or Library.Theme.CornerRadius or 6),
        Parent = parent,
    })
end

local function stroke(parent, color, thickness, transparency, colorKey)
    local effect = new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
    if colorKey then
        table.insert(Library._themeBindings, {
            Object = effect,
            Property = "Color",
            Key = colorKey,
        })
    end
    return effect
end

local function padding(parent, top, right, bottom, left)
    return new("UIPadding", {
        PaddingTop = UDim.new(0, top or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
        PaddingLeft = UDim.new(0, left or 0),
        Parent = parent,
    })
end

local function tween(object, duration, properties, style, direction)
    if not object or not object.Parent then
        return nil
    end
    if Library._reducedMotion then
        for property, value in pairs(properties) do
            object[property] = value
        end
        return {
            Cancel = function() end,
            Completed = {
                Connect = function(_, callback) callback(); return { Disconnect = function() end } end,
                Wait = function() end,
            },
        }
    end
    local info = TweenInfo.new(
        (duration or 0.18) / math.max(0.05, Library._animationSpeed),
        style or Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.Out
    )
    local animation = TweenService:Create(object, info, properties)
    animation:Play()
    return animation
end

local function connect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or Library._connections, connection)
    return connection
end

local function bindTheme(object, property, key)
    object[property] = Library.Theme[key]
    table.insert(Library._themeBindings, {
        Object = object,
        Property = property,
        Key = key,
    })
end

local function bindThemeState(object, update)
    table.insert(Library._themeBindings, {
        Object = object,
        Update = update,
    })
    update()
end

local function pruneThemeBindings()
    local bindings = Library._themeBindings
    for index = #bindings, 1, -1 do
        local object = bindings[index].Object
        if not object or not object.Parent then
            table.remove(bindings, index)
        end
    end
end

local function gradient(parent, firstKey, secondKey, rotation)
    local effect = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library.Theme[firstKey]),
            ColorSequenceKeypoint.new(1, Library.Theme[secondKey]),
        }),
        Rotation = rotation or 0,
        Parent = parent,
    })
    table.insert(Library._themeBindings, {
        Object = effect,
        Property = "Color",
        GradientKeys = { firstKey, secondKey },
    })
    return effect
end

local function constrainText(object, minimum, maximum)
    object.TextScaled = true
    return new("UITextSizeConstraint", {
        MinTextSize = minimum or 8,
        MaxTextSize = maximum or object.TextSize,
        Parent = object,
    })
end

local function text(parent, value, size, colorKey, properties)
    properties = properties or {}
    local textSize = size or 13
    local wrapped = properties.TextWrapped or false
    local scaled = properties.TextScaled ~= false
    local label = new("TextLabel", {
        Name = properties.Name or "Label",
        BackgroundTransparency = 1,
        Size = properties.Size or UDim2.new(1, 0, 0, 20),
        Position = properties.Position or UDim2.new(),
        AnchorPoint = properties.AnchorPoint or Vector2.zero,
        AutomaticSize = properties.AutomaticSize or Enum.AutomaticSize.None,
        Font = properties.Font or Library.Theme.Font or Enum.Font.Gotham,
        Text = tostring(value or ""),
        TextSize = textSize,
        TextScaled = scaled,
        TextTruncate = properties.TextTruncate
            or (wrapped and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd),
        TextXAlignment = properties.TextXAlignment or Enum.TextXAlignment.Left,
        TextYAlignment = properties.TextYAlignment or Enum.TextYAlignment.Center,
        TextWrapped = wrapped,
        RichText = properties.RichText or false,
        ZIndex = properties.ZIndex or 1,
        Parent = parent,
    })
    if scaled then
        constrainText(label, properties.MinTextSize or math.max(7, textSize - 4), properties.MaxTextSize or textSize)
    end
    if typeof(colorKey) == "Color3" then
        label.TextColor3 = colorKey
    elseif Library.Theme[colorKey or "Text"] ~= nil then
        bindTheme(label, "TextColor3", colorKey or "Text")
    else
        bindTheme(label, "TextColor3", "Text")
    end
    return label
end

local function expandTemplate(template, values)
    return (string.gsub(template, "{(%w+)}", function(key)
        local value = values[key]
        if value == nil then return "{" .. key .. "}" end
        return tostring(value)
    end))
end

local function resolveColor(color, fallbackKey)
    if typeof(color) == "Color3" then return color end
    if type(color) == "string" and Library.Theme[color] ~= nil then return Library.Theme[color] end
    return Library.Theme[fallbackKey or "Text"]
end

local function measureText(content, size, font, width)
    local ok, bounds = pcall(function()
        return TextService:GetTextSize(content, size, font, Vector2.new(width, 10000))
    end)
    if ok and typeof(bounds) == "Vector2" then
        return bounds
    end
    return Vector2.new(math.min(width, #content * size * 0.55), size * 1.3)
end

local function ripple(button, inputPosition)
    if not button or not button.Parent then
        return
    end
    local absolute = button.AbsolutePosition
    local point = inputPosition or (absolute + button.AbsoluteSize / 2)
    local circle = new("Frame", {
        Name = "Ripple",
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(point.X - absolute.X, point.Y - absolute.Y),
        Size = UDim2.fromOffset(0, 0),
        ZIndex = button.ZIndex + 2,
        Parent = button,
    })
    corner(circle, 999)
    local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2
    local animation = tween(circle, 0.45, {
        Size = UDim2.fromOffset(diameter, diameter),
        BackgroundTransparency = 1,
    })
    animation.Completed:Connect(function()
        circle:Destroy()
    end)
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end
    local ok, message = pcall(callback, ...)
    if not ok then
        warn("[Bloodshot UI] Callback error: " .. tostring(message))
        return nil
    end
    return message
end

local function registerFlagSetter(window, flag, setter)
    if not flag then
        return
    end
    if Library._flagSetters[flag] and Library._flagSetters[flag] ~= setter then
        warn("[Bloodshot UI] Duplicate flag '" .. tostring(flag) .. "'; newest live control wins")
    end
    Library._flagSetters[flag] = setter
    window._flagSetters[flag] = setter
end

local function commitFlag(flag, value)
    if flag == nil then
        return
    end
    Library.Flags[flag] = value
    Library:_notifyFlagChanged(flag)
end

local function makeDraggable(handle, target, bucket, window)
    local dragging = false
    local dragStart
    local startPosition
    local activeInput

    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            -- Only the topmost window at this point starts dragging, otherwise
            -- dragging the top window would also move every window stacked below.
            if window ~= nil and window._draggable == false then
                return
            end
            if window ~= nil and Library._isObscured ~= nil and Library:_isObscured(window, input.Position) then
                return
            end
            dragging = true
            dragStart = input.Position
            startPosition = target.Position
            activeInput = input
        end
    end, bucket)

    connect(UserInputService.InputChanged, function(input)
        if dragging and (input == activeInput
            or input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end, bucket)

    connect(UserInputService.InputEnded, function(input)
        if input == activeInput
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            activeInput = nil
        end
    end, bucket)
end

local function resolveParent()
    local ok, hidden = pcall(function()
        return gethui and gethui()
    end)
    if ok and hidden then
        return hidden
    end

    local protect = syn and syn.protect_gui
    local gui = new("ScreenGui", {
        Name = "BloodshotUI_" .. HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 1000,
    })

    if protect then
        pcall(protect, gui)
    end

    local parented = pcall(function()
        gui.Parent = CoreGui
    end)
    if not parented or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    return nil, gui
end

local explicitParent, preparedGui = resolveParent()
local ScreenGui = preparedGui or new("ScreenGui", {
    Name = "BloodshotUI_" .. HttpService:GenerateGUID(false),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 1000,
    Parent = explicitParent,
})
Library.Gui = ScreenGui

local NotificationHost = new("Frame", {
    Name = "Notifications",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -20, 1, -20),
    Size = UDim2.new(0, 330, 1, -40),
    ZIndex = 300,
    Parent = ScreenGui,
})
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = NotificationHost,
})

function Library:SetTheme(theme)
    if type(theme) ~= "table" then
        return
    end

    local updates = {}
    for key, value in pairs(theme) do
        updates[key] = value
    end

    local accent = updates.Accent
    if typeof(accent) == "Color3" then
        local black = Color3.new(0, 0, 0)
        updates.Background = updates.Background or accent:Lerp(black, 0.95)
        updates.Surface = updates.Surface or accent:Lerp(black, 0.91)
        updates.SurfaceAlt = updates.SurfaceAlt or accent:Lerp(black, 0.84)
        updates.Border = updates.Border or accent:Lerp(black, 0.66)
        updates.AccentDark = updates.AccentDark or accent:Lerp(black, 0.55)
        updates.BackgroundGradient = updates.BackgroundGradient or accent:Lerp(black, 0.88)
        updates.SurfaceGradient = updates.SurfaceGradient or accent:Lerp(black, 0.76)
        updates.AccentGradient = updates.AccentGradient or accent:Lerp(black, 0.48)
    end

    for key, value in pairs(updates) do
        if self.Theme[key] ~= nil and typeof(value) == typeof(self.Theme[key]) then
            self.Theme[key] = value
        end
    end
    for index = #self._themeBindings, 1, -1 do
        local binding = self._themeBindings[index]
        if binding.Object and binding.Object.Parent then
            if binding.Update then
                local ok, err = pcall(binding.Update)
                if not ok then
                    warn("[Bloodshot UI] Theme update error: " .. tostring(err))
                end
            elseif binding.GradientKeys then
                binding.Object.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, self.Theme[binding.GradientKeys[1]]),
                    ColorSequenceKeypoint.new(1, self.Theme[binding.GradientKeys[2]]),
                })
            else
                binding.Object[binding.Property] = self.Theme[binding.Key]
            end
        else
            table.remove(self._themeBindings, index)
        end
    end
    self:_emit("themeChanged", self.Theme)
end

function Library:GetTheme()
    return copyTable(self.Theme)
end

function Library:ResetTheme()
    self:SetTheme(DEFAULT_THEME)
end

function Library:SetThemePreset(name)
    local preset = self.ThemePresets[name]
    if not preset then
        return false, "Unknown theme preset: " .. tostring(name)
    end
    self:SetTheme(preset)
    return true
end

-- Overrides for Library.Strings. Pass nil to restore the built-in copy.
function Library:SetStrings(overrides)
    if overrides == nil then
        self._stringOverrides = nil
        return true
    end
    if type(overrides) ~= "table" then
        return false, "Strings override must be a table"
    end
    self._stringOverrides = overrides
    return true
end

function Library:GetStrings()
    local result = copyTable(self.Strings)
    for key, value in pairs(self._stringOverrides or {}) do
        result[key] = value
    end
    return result
end

function Library:SetReducedMotion(enabled)
    self._reducedMotion = not not enabled
    for _, window in ipairs(self._windows) do
        for _, animation in ipairs(window._backgroundTweens or {}) do
            if self._reducedMotion then
                animation:Pause()
            else
                animation:Play()
            end
        end
    end
end

function Library:SetAnimationSpeed(multiplier)
    multiplier = tonumber(multiplier)
    if not multiplier or multiplier ~= multiplier or multiplier <= 0 then
        return false, "Animation speed must be a positive finite number"
    end
    self._animationSpeed = math.clamp(multiplier, 0.05, 10)
    return true
end

function Library:SetFlag(flag, value, silent)
    if flag == nil then
        return false
    end
    local setter = self._flagSetters[flag]
    if setter then
        setter(value, silent)
    else
        self.Flags[flag] = value
        self:_notifyFlagChanged(flag)
    end
    return true
end

function Library:GetFlag(flag, fallback)
    local value = self.Flags[flag]
    if value == nil then
        return fallback
    end
    return value
end

local function flagMatches(filter, flag, control)
    if filter == nil then return true end
    if type(filter) == "function" then
        local ok, result = pcall(filter, flag, control)
        return ok and result == true
    end
    if type(filter) == "table" then
        for key, value in pairs(filter) do
            if type(key) == "number" then
                if value == flag then return true end
            elseif key == flag and value then
                return true
            end
        end
        return false
    end
    return filter == flag
end

function Library:ResetFlags(filter, silent)
    local count = 0
    local snapshot = {}
    for index, control in ipairs(self._specControls) do snapshot[index] = control end
    for _, control in ipairs(snapshot) do
        local flag = control.Flag
        if flag ~= nil and type(control.Reset) == "function" and flagMatches(filter, flag, control) then
            control:Reset(silent)
            count += 1
        end
    end
    return count
end

function Library:GetDefault(flag)
    for _, control in ipairs(self._specControls) do
        if control.Flag == flag and control._default ~= nil then
            return copyTable(control._default)
        end
    end
    return nil
end

-- Fires every listener registered for a flag, then every wildcard listener.
-- Listeners receive (value, flagName). Listeners must not throw.
function Library:_notifyFlagChanged(flag)
    if flag == nil then
        return
    end
    local key = tostring(flag)
    local specific = self._flagListeners[key]
    local wildcard = key ~= "*" and self._flagListeners["*"] or nil
    if not specific and not wildcard then
        return
    end
    local snapshot = {}
    for _, bucket in ipairs({ specific or {}, wildcard or {} }) do
        for _, entry in ipairs(bucket) do
            snapshot[#snapshot + 1] = entry
        end
    end
    local value = self.Flags[flag]
    for _, entry in ipairs(snapshot) do
        if entry.Alive then
            local ok, err = pcall(entry.Callback, value, key)
            if not ok then
                warn("[Bloodshot UI] Flag listener error for '" .. key .. "': " .. tostring(err))
            end
        end
    end
end

-- Subscribe to a flag. Returns a handle with Unbind(). Pass nil for every flag.
function Library:OnFlagChanged(flag, callback)
    if type(callback) ~= "function" then
        return false, "OnFlagChanged requires a function"
    end
    local key = flag ~= nil and tostring(flag) or "*"
    local entry = { Callback = callback, Alive = true }
    local listeners = self._flagListeners[key]
    if not listeners then
        listeners = {}
        self._flagListeners[key] = listeners
    end
    table.insert(listeners, entry)
    return {
        Flag = key,
        Unbind = function()
            entry.Alive = false
            for index, candidate in ipairs(listeners) do
                if candidate == entry then table.remove(listeners, index) break end
            end
        end,
    }
end

-- Drives an instance property from a flag.
--   Bloodshot:Bind("walkSpeed", humanoid, "WalkSpeed")
--   Bloodshot:Bind("fov", camera, "FieldOfView", { Transform = function(v) return v * 2 end })
--   Bloodshot:Bind("hum", nil, "JumpPower", { Resolve = function() return getHumanoid() end })
function Library:Bind(flag, target, property, options)
    options = type(options) == "table" and options or {}
    if flag == nil or property == nil then
        return false, "Bind requires a flag and a property name"
    end
    local binding = {
        Flag = tostring(flag),
        Property = tostring(property),
        Target = target,
        Resolve = options.Resolve,
        Transform = options.Transform,
        TransformBack = options.TransformBack,
        TwoWay = options.TwoWay == true,
        Silent = options.Silent ~= false,
        OnError = options.OnError,
        Alive = true,
        LastError = nil,
        Applied = false,
        Disposers = {},
    }
    local function resolveTarget()
        if binding.Resolve then
            local ok, result = pcall(binding.Resolve)
            return ok and result or nil
        end
        return binding.Target
    end
    local function apply()
        if not binding.Alive then return false end
        local instance = resolveTarget()
        if not instance then return false end
        local value = self.Flags[binding.Flag]
        if value == nil then return false end
        if binding.Transform then
            local ok, result = pcall(binding.Transform, value)
            if not ok then
                binding.LastError = result
                if binding.OnError then pcall(binding.OnError, result) end
                return false
            end
            value = result
        end
        local ok, err = pcall(function() instance[binding.Property] = value end)
        if not ok then
            binding.LastError = err
            if binding.OnError then pcall(binding.OnError, err) end
            return false
        end
        binding.Applied = true
        binding.LastError = nil
        return true
    end
    local function pull()
        if not (binding.TwoWay and binding.Alive) then return end
        local instance = resolveTarget()
        if not instance then return end
        local ok, raw = pcall(function() return instance[binding.Property] end)
        if not ok or raw == nil then return end
        local value = raw
        if binding.TransformBack then
            local okBack, result = pcall(binding.TransformBack, raw)
            if not okBack then return end
            value = result
        end
        self:SetFlag(binding.Flag, value, binding.Silent)
    end

    local subscription = self:OnFlagChanged(flag, apply)
    if type(subscription) == "table" then
        table.insert(binding.Disposers, function() subscription.Unbind() end)
    end
    if options.Character ~= false and (binding.Resolve or options.Character) then
        local connection = LocalPlayer.CharacterAdded:Connect(function()
            task.defer(apply)
        end)
        table.insert(binding.Disposers, function() connection:Disconnect() end)
    end
    if binding.TwoWay then
        local attached
        attached = function()
            local instance = resolveTarget()
            if not instance then return end
            -- Plain Lua tables (and some executor objects) have no change signal.
            if type(instance.GetPropertyChangedSignal) ~= "function" then return end
            local ok, connection = pcall(function()
                return instance:GetPropertyChangedSignal(binding.Property):Connect(pull)
            end)
            if not ok or connection == nil then return end
            table.insert(binding.Disposers, function()
                pcall(function() connection:Disconnect() end)
            end)
        end
        attached()
        if binding.Resolve then
            local connection = LocalPlayer.CharacterAdded:Connect(function()
                task.defer(attached)
            end)
            table.insert(binding.Disposers, function() connection:Disconnect() end)
        end
    end

    local handle
    handle = {
        Flag = binding.Flag,
        Property = binding.Property,
        IsAlive = function() return binding.Alive end,
        GetLastError = function() return binding.LastError end,
        HasApplied = function() return binding.Applied end,
        Apply = function() return apply() end,
        Unbind = function()
            if not binding.Alive then return false end
            binding.Alive = false
            for _, dispose in ipairs(binding.Disposers) do
                pcall(dispose)
            end
            table.clear(binding.Disposers)
            for index = #self._bindings, 1, -1 do
                if self._bindings[index] == handle then table.remove(self._bindings, index) end
            end
            return true
        end,
    }
    table.insert(self._bindings, handle)
    apply()
    return handle
end

-- Removes one binding (handle, or "flag:property") or every binding when given nil.
function Library:Unbind(target)
    if target == nil then
        for index = #self._bindings, 1, -1 do
            self._bindings[index]:Unbind()
        end
        return true
    end
    local removed = 0
    for index = #self._bindings, 1, -1 do
        local binding = self._bindings[index]
        local matches = binding == target
        if not matches and type(target) == "string" then
            matches = binding.Flag == target
                or (binding.Flag .. ":" .. binding.Property) == target
        end
        if matches then
            binding:Unbind()
            removed += 1
        end
    end
    return removed > 0, removed
end

local function makeFilter(values)
    if type(values) ~= "table" then return nil end
    local result = {}
    for key, value in pairs(values) do
        if type(key) == "number" then result[value] = true elseif value then result[key] = true end
    end
    return result
end

function Library:SaveConfig(options)
    options = type(options) == "table" and options or {}
    local include = makeFilter(options.Include)
    local exclude = makeFilter(options.Exclude)
    local encoded = {}
    for flag, value in pairs(self.Flags) do
        if (not include or include[flag]) and (not exclude or not exclude[flag]) then
        local kind = typeof(value)
        if kind == "Color3" then
            encoded[flag] = {
                __type = "Color3",
                value = { value.R, value.G, value.B },
            }
        elseif kind == "EnumItem" then
            encoded[flag] = {
                __type = "EnumItem",
                value = tostring(value),
            }
        elseif kind == "boolean" or kind == "number" or kind == "string" or kind == "table" then
            encoded[flag] = value
        end
        end
    end
    local payload = {
        __bloodshot = self.ConfigVersion,
        flags = encoded,
        metadata = options.Metadata,
    }
    local ok, result = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then
        return nil, "Unable to encode configuration: " .. tostring(result)
    end
    self:_emit("configSaved", result)
    return result
end

function Library:LoadConfig(json, options)
    local silent
    local strict = false
    if type(options) == "table" then
        silent = options.Silent
        strict = options.Strict == true
    else
        silent = options
    end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
    if not ok or type(decoded) ~= "table" then
        return false, "Invalid configuration"
    end
    if decoded.__bloodshot ~= nil then
        if type(decoded.flags) ~= "table" then
            return false, "Invalid versioned configuration"
        end
        decoded = decoded.flags
    end
    local pending = {}
    for flag, value in pairs(decoded) do
        if strict and not self._flagSetters[flag] then
            return false, "Unknown flag " .. tostring(flag)
        end
        if type(value) == "table" and value.__type == "Color3" then
            local rgb = value.value
            if type(rgb) ~= "table"
                or type(rgb[1]) ~= "number"
                or type(rgb[2]) ~= "number"
                or type(rgb[3]) ~= "number" then
                return false, "Invalid Color3 value for flag " .. tostring(flag)
            end
            if rgb[1] < 0 or rgb[1] > 1 or rgb[2] < 0 or rgb[2] > 1 or rgb[3] < 0 or rgb[3] > 1 then
                return false, "Color3 channels must be between 0 and 1 for flag " .. tostring(flag)
            end
            value = Color3.new(rgb[1], rgb[2], rgb[3])
        elseif type(value) == "table" and value.__type == "EnumItem" then
            if type(value.value) ~= "string" then
                return false, "Invalid EnumItem value for flag " .. tostring(flag)
            end
            local enumName, itemName = value.value:match("^Enum%.([^%.]+)%.(.+)$")
            local found, enumItem = pcall(function()
                return Enum[enumName][itemName]
            end)
            if not enumName or not found or typeof(enumItem) ~= "EnumItem" then
                return false, "Unknown EnumItem for flag " .. tostring(flag)
            end
            value = enumItem
        end
        if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            return false, "Invalid finite number for flag " .. tostring(flag)
        end
        local expected = self._flagTypes[flag]
        if strict and expected and typeof(value) ~= expected then
            return false, "Invalid type for flag " .. tostring(flag) .. "; expected " .. expected
        end
        pending[#pending + 1] = { Flag = flag, Value = value }
    end
    for _, entry in ipairs(pending) do
        self:SetFlag(entry.Flag, entry.Value, silent)
    end
    self:_emit("configLoaded", #pending)
    return true
end

-- Reads a nested legacy config (the Rain/config.json shape: grouped maps, hex
-- colour strings, key names) and flattens it onto Bloodshot flags.
--   Bloodshot:ImportLegacy(json, {
--       Sections = { CATEGORIES = "categories", VISUALS = "visuals" },
--       Colors   = { VISUALS.tint = "tint" },
--       Keys     = { KEYS.primary = "primaryBind" },
--       Prefix   = "legacy.",
--   })
-- Section and key paths use dots ("VISUALS.tint"). Anything the mapping does not
-- name is reported in the skipped list rather than silently dropped.
local function legacyLookup(root, path)
    local node = root
    for part in string.gmatch(tostring(path), "[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

local function parseHexColor(raw)
    if type(raw) ~= "string" then return nil end
    local hex = string.gsub(raw, "^#", "")
    if hex:match("^%x%x%x%x%x%x$") then
        return Color3.fromRGB(
            tonumber(hex:sub(1, 2), 16),
            tonumber(hex:sub(3, 4), 16),
            tonumber(hex:sub(5, 6), 16)
        )
    end
    if hex:match("^%x%x%x$") then
        return Color3.fromRGB(
            tonumber(hex:sub(1, 1), 16) * 17,
            tonumber(hex:sub(2, 2), 16) * 17,
            tonumber(hex:sub(3, 3), 16) * 17
        )
    end
    return nil
end

local MOUSE_BUTTON_CODES = {
    ["mouse1"] = Enum.UserInputType.MouseButton1,
    ["mouse2"] = Enum.UserInputType.MouseButton2,
    ["mouse3"] = Enum.UserInputType.MouseButton3,
    ["mousebutton1"] = Enum.UserInputType.MouseButton1,
    ["mousebutton2"] = Enum.UserInputType.MouseButton2,
    ["mousebutton3"] = Enum.UserInputType.MouseButton3,
}

local function parseKeyName(raw)
    if typeof(raw) == "EnumItem" then return raw end
    if type(raw) ~= "string" or raw == "" then return nil end
    local lower = string.lower((string.gsub(raw, "^Enum%.UserInputType%.", "")))
    if MOUSE_BUTTON_CODES[lower] then return MOUSE_BUTTON_CODES[lower] end
    local named = string.gsub(raw, "^Enum%.KeyCode%.", "")
    -- Roblox throws on an unknown member rather than returning nil.
    local ok, code = pcall(function() return Enum.KeyCode[named] end)
    if not ok or typeof(code) ~= "EnumItem" or code == Enum.KeyCode.Unknown then return nil end
    return code
end

function Library:ImportLegacy(source, mapping)
    mapping = type(mapping) == "table" and mapping or {}
    local decoded = source
    if type(source) == "string" then
        local ok, result = pcall(HttpService.JSONDecode, HttpService, source)
        if not ok or type(result) ~= "table" then
            return nil, "ImportLegacy expects valid JSON or a table"
        end
        decoded = result
    end
    if type(decoded) ~= "table" then
        return nil, "ImportLegacy expects valid JSON or a table"
    end
    local prefix = mapping.Prefix or ""
    local applied = {}
    local skipped = {}

    local function write(flag, value)
        applied[tostring(flag)] = value
    end

    for path, flag in pairs(type(mapping.Flags) == "table" and mapping.Flags or {}) do
        local raw = legacyLookup(decoded, path)
        if raw ~= nil then
            write(prefix .. tostring(flag), raw)
        else
            skipped[#skipped + 1] = tostring(path)
        end
    end

    -- Sections maps a legacy group to either:
    --   true        copy every leaf under the group, keeping the leaf name
    --   { key = flag }  copy just the named leaves, renaming each flag
    local prefixSection = mapping.SectionPrefix
    for sectionName, fields in pairs(type(mapping.Sections) == "table" and mapping.Sections or {}) do
        local group = decoded[sectionName]
        if type(group) ~= "table" then
            skipped[#skipped + 1] = sectionName
        elseif fields == true then
            for key, value in pairs(group) do
                local flag = prefix .. (prefixSection and (prefixSection .. "." .. tostring(key)) or tostring(key))
                write(flag, value)
            end
        elseif type(fields) == "table" then
            for key, flag in pairs(fields) do
                local raw = legacyLookup(decoded, sectionName .. "." .. tostring(key))
                if raw ~= nil then
                    write(prefix .. tostring(flag), raw)
                else
                    skipped[#skipped + 1] = sectionName .. "." .. tostring(key)
                end
            end
        end
    end

    for path, flag in pairs(type(mapping.Colors) == "table" and mapping.Colors or {}) do
        local raw = legacyLookup(decoded, path)
        local color = parseHexColor(raw)
        if color then
            write(prefix .. tostring(flag), color)
        else
            skipped[#skipped + 1] = tostring(path)
        end
    end

    for path, flag in pairs(type(mapping.Keys) == "table" and mapping.Keys or {}) do
        local raw = legacyLookup(decoded, path)
        local key = parseKeyName(raw)
        if key then
            write(prefix .. tostring(flag), key)
        else
            skipped[#skipped + 1] = tostring(path)
        end
    end

    -- Types coerces a copied value. The key is the target flag; the value is
    -- either a kind string or { Kind, Source, Flag } for full control.
    for flag, kind in pairs(type(mapping.Types) == "table" and mapping.Types or {}) do
        local source = flag
        local target = flag
        local wanted = kind
        if type(kind) == "table" then
            -- Read every field off the table before rebinding to the kind string,
            -- otherwise kind.Source/kind.Flag are looked up on that string.
            wanted = kind.Kind or kind.Type or kind[1]
            source = kind.Source or flag
            target = kind.Flag or flag
        end
        local raw = applied[prefix .. tostring(source)]
        if raw == nil then
            raw = applied[prefix .. tostring(target)]
        end
        if raw == nil then
            raw = legacyLookup(decoded, source)
        end
        if raw == nil then
            skipped[#skipped + 1] = tostring(source)
        else
            kind = string.lower(tostring(wanted))
            local converted
            if kind == "number" then
                converted = tonumber(raw)
            elseif kind == "boolean" then
                if type(raw) == "boolean" then
                    converted = raw
                elseif type(raw) == "string" then
                    local lowered = string.lower(raw)
                    converted = lowered == "true" or lowered == "1" or lowered == "on"
                elseif type(raw) == "number" then
                    converted = raw ~= 0
                end
            elseif kind == "string" then
                converted = tostring(raw)
            elseif kind == "color" then
                converted = parseHexColor(raw)
            elseif kind == "key" then
                converted = parseKeyName(raw)
            end
            if converted ~= nil then
                write(prefix .. tostring(target), converted)
            else
                skipped[#skipped + 1] = tostring(source)
            end
        end
    end

    local silent = mapping.Silent
    for flag, value in pairs(applied) do
        self:SetFlag(flag, value, silent)
    end
    table.sort(skipped)
    return applied, skipped
end

function Library:SetConfigAdapter(adapter)
    if adapter ~= nil and type(adapter) ~= "table" then
        return false, "Config adapter must be a table"
    end
    if adapter and (type(adapter.Read) ~= "function" or type(adapter.Write) ~= "function") then
        return false, "Config adapter requires Read(name) and Write(name, json)"
    end
    self._configAdapter = adapter
    return true
end

function Library:SaveProfile(name, options)
    if not self._configAdapter then return false, "No config adapter configured" end
    local json, message = self:SaveConfig(options)
    if not json then return false, message end
    local ok, result, detail = pcall(self._configAdapter.Write, self._configAdapter, tostring(name), json)
    if not ok then return false, tostring(result) end
    if result == false then return false, tostring(detail or "Write failed") end
    return true
end

function Library:LoadProfile(name, options)
    if not self._configAdapter then return false, "No config adapter configured" end
    local ok, json = pcall(self._configAdapter.Read, self._configAdapter, tostring(name))
    if not ok then return false, tostring(json) end
    if type(json) ~= "string" then return false, "Profile not found: " .. tostring(name) end
    return self:LoadConfig(json, options)
end

-- Order-independent serialisation of a flag value, used only for change detection.
local function stableSerialize(value, depth)
    depth = depth or 0
    if depth > 6 then
        return "<deep>"
    end
    local kind = typeof(value)
    if kind == "Color3" then
        return string.format("C3(%.6f,%.6f,%.6f)", value.R, value.G, value.B)
    elseif kind == "EnumItem" then
        return "Enum(" .. tostring(value) .. ")"
    elseif kind == "table" then
        local entries = {}
        for key, item in pairs(value) do
            entries[#entries + 1] = { Key = key, Item = item }
        end
        table.sort(entries, function(a, b) return tostring(a.Key) < tostring(b.Key) end)
        local parts = {}
        for _, entry in ipairs(entries) do
            parts[#parts + 1] = tostring(entry.Key) .. ":" .. stableSerialize(entry.Item, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif kind == "number" then
        return string.format("%.14g", value)
    end
    return tostring(value)
end

-- Stable signature of every flag; two equal signatures mean an identical config.
function Library:ConfigFingerprint()
    local flags = {}
    for flag in pairs(self.Flags) do
        flags[#flags + 1] = flag
    end
    table.sort(flags, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, flag in ipairs(flags) do
        parts[#parts + 1] = tostring(flag) .. "=" .. stableSerialize(self.Flags[flag])
    end
    return table.concat(parts, "|")
end

local function sanitizeProfileName(name)
    return (string.gsub(tostring(name), "[^%w%._-]", "_"))
end

-- Installs a writefile/readfile backed adapter when the executor exposes them.
function Library:UseFileStorage(options)
    options = type(options) == "table" and options or {}
    if type(writefile) ~= "function" or type(readfile) ~= "function" then
        return false, "This executor does not expose writefile/readfile"
    end
    local folder = options.Folder
    local function profilePath(name)
        local file = sanitizeProfileName(name) .. ".json"
        if type(folder) == "string" and folder ~= "" then
            return folder .. "/" .. file
        end
        return file
    end
    local function ensureFolder()
        if type(folder) ~= "string" or folder == "" or type(makefolder) ~= "function" then
            return
        end
        if type(isfolder) == "function" then
            local checked, exists = pcall(isfolder, folder)
            if checked and exists then
                return
            end
        end
        pcall(makefolder, folder)
    end
    local adapter = {
        Name = "file",
        Path = profilePath,
        Write = function(_, name, json)
            ensureFolder()
            local ok, err = pcall(writefile, profilePath(name), json)
            if not ok then
                return false, tostring(err)
            end
            return true
        end,
        Read = function(_, name)
            local target = profilePath(name)
            if type(isfile) == "function" and not isfile(target) then
                return nil
            end
            local ok, content = pcall(readfile, target)
            if not ok or type(content) ~= "string" then
                return nil
            end
            return content
        end,
    }
    if type(delfile) == "function" then
        adapter.Delete = function(_, name)
            local ok, err = pcall(delfile, profilePath(name))
            if not ok then
                return false, tostring(err)
            end
            return true
        end
    end
    if type(listfiles) == "function" then
        adapter.List = function()
            local ok, files = pcall(listfiles, type(folder) == "string" and folder or "")
            if not ok or type(files) ~= "table" then
                return {}
            end
            local names = {}
            for _, file in ipairs(files) do
                local stem = string.match(tostring(file), "([^/\\]+)%.json$")
                if stem and stem ~= "__geometry" then
                    names[#names + 1] = stem
                end
            end
            table.sort(names)
            return names
        end
    end
    return self:SetConfigAdapter(adapter)
end

function Library:DeleteProfile(name)
    local adapter = self._configAdapter
    if not adapter then return false, "No config adapter configured" end
    if type(adapter.Delete) ~= "function" then
        return false, "Active adapter does not support Delete"
    end
    local ok, result, detail = pcall(adapter.Delete, adapter, tostring(name))
    if not ok then
        return false, tostring(result)
    end
    if result == false then
        return false, tostring(detail or "Delete failed")
    end
    return true
end

function Library:ListProfiles()
    local adapter = self._configAdapter
    if not adapter or type(adapter.List) ~= "function" then
        return {}
    end
    local ok, result = pcall(adapter.List, adapter)
    if not ok or type(result) ~= "table" then
        return {}
    end
    return result
end

-- Debounced persistence: saves only after flags stop changing for Delay seconds.
-- Window stacking, focus and per-window theme overrides.
local function applyWindowZOrder()
    local total = #Library._windowOrder
    for position, window in ipairs(Library._windowOrder) do
        if window.Root and not window._destroyed then
            window.Root.ZIndex = total - position + 1
        end
    end
end

-- Front-to-back hit test: which visible window is on top at a screen point.
-- Used so a click on an overlapping window never focuses or activates the one
-- underneath, and so hover alone never changes focus.
function Library:_topWindowAt(position)
    if typeof(position) ~= "Vector2" then
        return nil
    end
    for _, window in ipairs(self._windowOrder) do
        if not window._destroyed and window.Visible and window.Root and window.Root.Visible then
            local ok, absPos, absSize = pcall(function()
                return window.Root.AbsolutePosition, window.Root.AbsoluteSize
            end)
            if ok and absPos and absSize then
                if position.X >= absPos.X and position.Y >= absPos.Y
                    and position.X <= absPos.X + absSize.X
                    and position.Y <= absPos.Y + absSize.Y then
                    return window
                end
            end
        end
    end
    return nil
end

-- True when a click at `position` belongs to a window above `window` and must
-- be ignored by `window`. Nil position falls back to the current mouse location.
function Library:_isObscured(window, position)
    local guard = self._clickGuard
    if guard then
        if os.clock() < guard then
            return true
        end
        self._clickGuard = nil
    end
    local pos = position
    if typeof(pos) ~= "Vector2" then
        local ok, mouse = pcall(function()
            return UserInputService:GetMouseLocation()
        end)
        if ok then
            pos = mouse
        else
            return false
        end
    end
    local top = self:_topWindowAt(pos)
    if top == nil then
        return false
    end
    return top ~= window
end

function Library:GetWindows()
    local list = {}
    for _, window in ipairs(self._windows) do
        list[#list+1] = window
    end
    return list
end

function Library:GetFocusedWindow()
    return self._focusedWindow
end

function Library:FocusWindow(target, applyTheme)
    local window = target
    if type(window) == "string" then
        for _, candidate in ipairs(self._windows) do
            if candidate._geometryKey == window then window = candidate break end
        end
    end
    if type(window) ~= "table" or window._destroyed then return false end
    if self._focusedWindow == window and self._windowOrder[1] == window then
        return true
    end
    local index = table.find(self._windowOrder, window)
    if index then table.remove(self._windowOrder, index) end
    table.insert(self._windowOrder, 1, window)
    applyWindowZOrder()

    local previous = self._focusedWindow
    self._focusedWindow = window
    if previous and previous ~= window and previous._themeRestore then
        local restore = previous._themeRestore
        previous._themeRestore = nil
        self:SetTheme(restore)
    end
    if applyTheme ~= false and window._themeOverrides then
        if not window._themeRestore then
            window._themeRestore = copyTable(self.Theme)
        end
        self:SetTheme(window._themeOverrides)
    end
    return true
end

function Library:CycleWindows()
    if #self._windowOrder < 2 then return false end
    local nextWindow = self._windowOrder[2]
    if not nextWindow or nextWindow._destroyed then return false end
    return self:FocusWindow(nextWindow)
end

function Library:SetReorderEnabled(enabled)
    enabled = not not enabled
    for _, window in ipairs(self._windows) do
        window._reorderEnabled = enabled
        for _, tab in ipairs(window.Tabs) do
            tab:EnableReorder(enabled)
        end
    end
    return enabled
end

function Library:SetGamepadEnabled(enabled)
    self._gamepadEnabled = not not enabled
    for _, window in ipairs(self._windows) do window:SetGamepadEnabled(self._gamepadEnabled) end
    return self._gamepadEnabled
end

local function encodeGeometry(geometry)
    local function encodeDim(dim)
        return { dim.Scale, dim.Offset }
    end
    local entry = {
        position = { encodeDim(geometry.Position.X), encodeDim(geometry.Position.Y) },
        size = { encodeDim(geometry.Size.X), encodeDim(geometry.Size.Y) },
        minimized = geometry.Minimized == true,
        visible = geometry.Visible ~= false,
    }
    if geometry.Tab then entry.tab = tostring(geometry.Tab) end
    if type(geometry.Scroll) == "table" then
        entry.scroll = {}
        for name, offset in pairs(geometry.Scroll) do
            if typeof(offset) == "Vector2" then
                entry.scroll[tostring(name)] = { offset.X, offset.Y }
            elseif typeof(offset) == "UDim2" then
                entry.scroll[tostring(name)] = { offset.X.Offset, offset.Y.Offset }
            end
        end
    end
    return entry
end

local function decodeGeometry(entry)
    if type(entry) ~= "table" then return nil end
    -- v2 payloads stored position/size as two flat 4-number arrays.
    if type(entry[1]) == "table" and type(entry[2]) == "table" then
        if #entry[1] == 4 and #entry[2] == 4 then
            return {
                Position = UDim2.new(entry[1][1], entry[1][2], entry[1][3], entry[1][4]),
                Size = UDim2.new(entry[2][1], entry[2][2], entry[2][3], entry[2][4]),
            }
        end
        return nil
    end
    if type(entry.position) ~= "table" or type(entry.size) ~= "table" then return nil end
    local function dim(pair)
        if type(pair) ~= "table" or type(pair[1]) ~= "table" or type(pair[2]) ~= "table" then
            return nil
        end
        return UDim2.new(pair[1][1] or 0, pair[1][2] or 0, pair[2][1] or 0, pair[2][2] or 0)
    end
    local geometry = {
        Position = dim(entry.position) or UDim2.new(0.5, 0, 0.5, 0),
        Size = dim(entry.size) or UDim2.fromOffset(680, 470),
        Minimized = entry.minimized == true,
        Visible = entry.visible ~= false,
    }
    if entry.tab then geometry.Tab = tostring(entry.tab) end
    if type(entry.scroll) == "table" then
        geometry.Scroll = {}
        for name, pair in pairs(entry.scroll) do
            if type(pair) == "table" and type(pair[1]) == "number" and type(pair[2]) == "number" then
                geometry.Scroll[tostring(name)] = Vector2.new(pair[1], pair[2])
            else
                local offset = dim(pair)
                if offset then
                    geometry.Scroll[tostring(name)] = Vector2.new(offset.X.Offset, offset.Y.Offset)
                end
            end
        end
    end
    return geometry
end

function Library:SaveGeometry()
    local adapter = self._configAdapter
    if not adapter or type(adapter.Write) ~= "function" then
        return false, "No config adapter configured"
    end
    local payload = {}
    for _, window in ipairs(self._windows) do
        local geometry = window:GetGeometry()
        if geometry then
            payload[window._geometryKey] = encodeGeometry(geometry)
        end
    end
    local encodedOk, json = pcall(HttpService.JSONEncode, HttpService, {
        version = self.ConfigVersion,
        windows = payload,
    })
    if not encodedOk then
        return false, "Unable to encode geometry: " .. tostring(json)
    end
    local ok, result, detail = pcall(adapter.Write, adapter, "__geometry", json)
    if not ok then
        return false, tostring(result)
    end
    if result == false then
        return false, tostring(detail or "Write failed")
    end
    return true
end

function Library:LoadGeometry()
    local adapter = self._configAdapter
    if not adapter or type(adapter.Read) ~= "function" then
        return false, "No config adapter configured"
    end
    local ok, json = pcall(adapter.Read, adapter, "__geometry")
    if not ok or type(json) ~= "string" then
        return false, "No saved geometry"
    end
    local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, json)
    if not decodedOk or type(decoded) ~= "table" or type(decoded.windows) ~= "table" then
        return false, "Invalid geometry payload"
    end
    local applied = 0
    for _, window in ipairs(self._windows) do
        local geometry = decodeGeometry(decoded.windows[window._geometryKey])
        if geometry and window:SetGeometry(geometry) then
            applied += 1
        end
    end
    return true, applied
end

-- Opt-in automatic persistence. windows = true covers every window that exists
-- now and any created later; a list of windows/keys applies only to those.
local function matchesGeometryTargets(targets, window)
    if targets == nil then return true end
    if type(targets) == "table" and table.find(targets, window) then return true end
    for _, key in ipairs(type(targets) == "table" and targets or { targets }) do
        if window._geometryKey == tostring(key) then return true end
    end
    return false
end

function Library:EnableGeometryPersistence(windows, options)
    if type(windows) == "table" and options == nil and (windows.Delay ~= nil or windows.Load ~= nil) then
        options = windows
        windows = true
    end
    options = type(options) == "table" and options or {}
    -- nil is the internal spelling of "every window". Written as
    -- `(cond and nil) or windows` the true branch falls through to `or` and
    -- yields `true`, which matchesGeometryTargets then reads as a single target.
    local targets
    if windows == nil or windows == true then
        targets = nil
    else
        targets = windows
    end
    local count = 0
    for _, window in ipairs(self._windows) do
        if matchesGeometryTargets(targets, window) then
            window:EnableGeometryPersistence(options)
            count += 1
        end
    end
    -- Windows built after this call opt in through the same setting.
    if not self._geometryPersistenceHandle then
        self._geometryPersistence = { Targets = targets, Options = options }
        self._geometryPersistenceHandle = self:_subscribe("windowCreated", function(window)
            local config = self._geometryPersistence
            if config and matchesGeometryTargets(config.Targets, window) then
                window:EnableGeometryPersistence(config.Options)
            end
        end)
    else
        self._geometryPersistence = { Targets = targets, Options = options }
    end
    return count
end

function Library:DisableGeometryPersistence(windows)
    if self._geometryPersistenceHandle then
        self._geometryPersistenceHandle:Unbind()
        self._geometryPersistenceHandle = nil
        self._geometryPersistence = nil
    end
    for _, window in ipairs(self._windows) do
        if windows == nil or matchesGeometryTargets(windows, window) then
            window:DisableGeometryPersistence()
        end
    end
    return true
end

function Library:AutoSave(profile, options)
    local existing = self._autoSave
    if existing and existing.Connection then
        existing.Connection:Disconnect()
    end
    self._autoSave = nil
    if profile == nil then
        return true
    end
    options = type(options) == "table" and options or {}
    local interval = tonumber(options.Interval) or 1
    local delay = tonumber(options.Delay) or 2
    if not interval or interval ~= interval or interval <= 0 then interval = 1 end
    if not delay or delay ~= delay or delay < 0 then delay = 0 end
    local state = {
        Profile = tostring(profile),
        SaveOptions = options.SaveOptions,
        Interval = interval,
        Delay = delay,
        Elapsed = 0,
        Dirty = false,
        Pending = false,
        Token = 0,
        Saves = 0,
        Snapshot = self:ConfigFingerprint(),
        Connection = nil,
    }
    self._autoSave = state
    state.Connection = RunService.Heartbeat:Connect(function(delta)
        state.Elapsed += delta
        if state.Elapsed < state.Interval then
            return
        end
        state.Elapsed = 0
        local fingerprint = self:ConfigFingerprint()
        if fingerprint ~= state.Snapshot then
            state.Snapshot = fingerprint
            state.Dirty = true
            state.Pending = false
            state.Token += 1
            return
        end
        if not state.Dirty or state.Pending then
            return
        end
        state.Pending = true
        local token = state.Token
        task.delay(delay, function()
            if self._autoSave ~= state or state.Token ~= token then return end
            state.Pending = false
            if not state.Dirty then return end
            state.Dirty = false
            if self:SaveProfile(state.Profile, state.SaveOptions) then
                state.Saves += 1
            end
        end)
    end)
    return true
end

function Library:Notify(options)
    if self._destroyed then
        return nil
    end
    options = type(options) == "table" and options or { Content = tostring(options) }
    pruneThemeBindings()
    for index = #self._notifications, 1, -1 do
        if not self._notifications[index].Parent then
            table.remove(self._notifications, index)
        end
    end
    while #self._notifications >= 5 do
        local oldest = table.remove(self._notifications, 1)
        if oldest.Parent then
            oldest:Destroy()
        end
    end

    local duration = tonumber(options.Duration) or 4
    if duration ~= duration or duration < 0 then
        duration = 0
    end
    local accentKey = options.Type == "Success" and "Success"
        or options.Type == "Warning" and "Warning"
        or options.Type == "Error" and "Error"
        or "Accent"

    local card = new("Frame", {
        Name = "Notification",
        BackgroundTransparency = 0.03,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        ClipsDescendants = true,
        Parent = NotificationHost,
    })
    bindTheme(card, "BackgroundColor3", "Surface")
    gradient(card, "Surface", "SurfaceGradient", 18)
    corner(card, 8)
    stroke(card, Library.Theme.Border, 1, 0.25, "Border")

    text(card, options.Title or T("Notification"), 14, "Text", {
        Position = UDim2.fromOffset(16, 10),
        Size = UDim2.new(1, -30, 0, 18),
        Font = Enum.Font.GothamSemibold,
    })
    text(card, options.Content or options.Description or "", 12, "MutedText", {
        Position = UDim2.fromOffset(16, 31),
        Size = UDim2.new(1, -30, 0, 34),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })

    local timer = new("Frame", {
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -5),
        Size = UDim2.new(1, -16, 0, 2),
        Parent = card,
    })
    bindTheme(timer, "BackgroundColor3", accentKey)
    table.insert(self._notifications, card)

    tween(card, 0.3, { Size = UDim2.new(1, 0, 0, 76) })
    tween(timer, duration * math.max(0.05, Library._animationSpeed), { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)

    task.delay(duration, function()
        if card.Parent then
            local animation = tween(card, 0.25, {
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundTransparency = 1,
            })
            animation.Completed:Wait()
            card:Destroy()
            for index, notification in ipairs(Library._notifications) do
                if notification == card then
                    table.remove(Library._notifications, index)
                    break
                end
            end
        end
    end)
    return card
end

function Library:Confirm(options)
    if self._destroyed then
        return nil
    end
    options = type(options) == "table" and options or {}
    pruneThemeBindings()
    local overlay = new("TextButton", {
        Name = "ConfirmationOverlay",
        BackgroundColor3 = self.Theme.Overlay,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 100,
        Parent = ScreenGui,
    })
    local card = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(360, 170),
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 101,
        Parent = overlay,
    })
    bindTheme(card, "BackgroundColor3", "Surface")
    gradient(card, "Surface", "SurfaceGradient", 18)
    corner(card, 9)
    stroke(card, self.Theme.Border, 1, 0.1, "Border")
    text(card, options.Title or T("Confirm"), 16, "Text", {
        Position = UDim2.fromOffset(18, 16), Size = UDim2.new(1, -36, 0, 24),
        Font = Enum.Font.GothamBold, ZIndex = 102,
    })
    text(card, options.Content or options.Description or T("AreYouSure"), 12, "MutedText", {
        Position = UDim2.fromOffset(18, 48), Size = UDim2.new(1, -36, 0, 50),
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 102,
    })
    local resolved = false
    local function resolve(result)
        if resolved then return end
        resolved = true
        safeCall(options.Callback, result)
        if overlay.Parent then overlay:Destroy() end
    end
    local cancel = new("TextButton", {
        Position = UDim2.new(0.5, -112, 1, -48), Size = UDim2.fromOffset(104, 32),
        BackgroundColor3 = self.Theme.SurfaceAlt, BorderSizePixel = 0,
        Text = options.CancelText or T("Cancel"), TextColor3 = self.Theme.MutedText,
        Font = Enum.Font.GothamMedium, TextSize = 12, ZIndex = 102, Parent = card,
    })
    local confirm = new("TextButton", {
        Position = UDim2.new(0.5, 8, 1, -48), Size = UDim2.fromOffset(104, 32),
        BackgroundColor3 = self.Theme.Accent, BorderSizePixel = 0,
        Text = options.ConfirmText or T("Confirm"), TextColor3 = self.Theme.Text,
        Font = Enum.Font.GothamMedium, TextSize = 12, ZIndex = 102, Parent = card,
    })
    bindTheme(cancel, "BackgroundColor3", "SurfaceAlt")
    bindTheme(cancel, "TextColor3", "MutedText")
    bindTheme(confirm, "BackgroundColor3", "Accent")
    bindTheme(confirm, "TextColor3", "Text")
    corner(cancel, 6); corner(confirm, 6)
    connect(cancel.Activated, function() resolve(false) end)
    connect(confirm.Activated, function() resolve(true) end)
    connect(overlay.Activated, function() if options.DismissOnOverlay ~= false then resolve(false) end end)
    return { Instance = overlay, Close = function(_, result) resolve(result == true) end }
end

local function createControlBase(section, height, name, description, look)
    local holder = new("Frame", {
        Name = name or "Control",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, height),
        Parent = section.Container,
    })
    local compact = section._compact == true
    local tint = not compact and look and look.Tint
    if tint then
        bindThemeState(holder, function()
            holder.BackgroundColor3 = resolveColor(tint, "Accent")
        end)
    else
        bindTheme(holder, "BackgroundColor3", "SurfaceAlt")
    end
    local holderStroke
    if compact then
        -- Row children are chrome-free: the row is already a card, so a second
        -- bordered/filled control inside it looks like a nested box. Skipping
        -- this at creation (rather than stripping it later) also avoids the
        -- entry tween re-filling the holder after a post-pass cleared it.
        holder.BackgroundTransparency = 1
        corner(holder, 6)
    else
        local function rest()
            return look and look.Rest or Library.Theme.ControlTransparency or 0.8
        end
        if not tint then gradient(holder, "SurfaceAlt", "SurfaceGradient", 12) end
        corner(holder, 6)
        if tint then
            holderStroke = stroke(holder, resolveColor(tint, "Accent"), 1, 0.35)
            bindThemeState(holderStroke, function()
                holderStroke.Color = resolveColor(tint, "Accent")
            end)
        else
            holderStroke = stroke(holder, Library.Theme.Border, 1, 0.45, "Border")
        end
        tween(holder, 0.24, { BackgroundTransparency = rest() })
        connect(holder.MouseEnter, function()
            tween(holder, 0.16, { BackgroundTransparency = look and look.Hover or 0.68 })
            tween(holderStroke, 0.16, { Transparency = 0.2 })
        end, section.Window._connections)
        connect(holder.MouseLeave, function()
            tween(holder, 0.16, { BackgroundTransparency = rest() })
            tween(holderStroke, 0.16, { Transparency = tint and 0.35 or 0.45 })
        end, section.Window._connections)
    end
    local nameLabel = text(holder, name or "Control", compact and 11 or 13, "Text", {
        Position = UDim2.fromOffset(12, description and 8 or 0),
        Size = UDim2.new(1, -24, 0, description and 18 or height),
        Font = Enum.Font.GothamMedium,
    })
    local descriptionLabel
    if description then
        descriptionLabel = text(holder, description, compact and 10 or 11, "MutedText", {
            Position = UDim2.fromOffset(12, 27),
            Size = UDim2.new(1, -24, 0, 16),
        })
    end
    holder:SetAttribute("BloodshotControl", true)
    -- Only the first TextLabel is the name; a search/description label added
    -- later must not be mistaken for one when compacting.
    holder:SetAttribute("BloodshotCompact", compact)
    holder:SetAttribute("BloodshotDisabled", false)
    holder:SetAttribute("BloodshotBaseHeight", height)
    holder:SetAttribute("BloodshotHasDescription", description ~= nil)
    holder:SetAttribute("BloodshotNameLabel", nameLabel.Name)
    return holder, nameLabel, descriptionLabel
end

-- Row children are built through a lightweight nested section, so every Add*
-- method works unchanged; this helper just post-processes the holder it produced.
-- Every direct child is vertically centred in the shorter row so names,
-- tracks, boxes and previews share one midline instead of stacking offsets
-- from their taller standalone holders.
local function compactifyControl(holder, rowHeight)
    if not holder or not holder.Parent then return end
    holder.Size = UDim2.new(1, 0, 1, 0)
    holder:SetAttribute("BloodshotCompact", true)
    -- Compact children are chrome-free: the row already provides the surface, so
    -- a second bordered card inside it reads as clutter. Drop the holder's fill,
    -- gradient and stroke; parts a control outlines on purpose keep theirs.
    holder.BackgroundTransparency = 1
    for _, effect in ipairs(holder:GetChildren()) do
        if effect:IsA("UIStroke") or effect:IsA("UIGradient") then
            effect:Destroy()
        end
    end
    local nameLabel
    local seenLabel = 0
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("TextLabel") then
            if child:GetAttribute("BloodshotKeep") then
                -- Value readouts and arrows keep the horizontal layout their
                -- control gave them; only the vertical centring is shared.
                child.AnchorPoint = Vector2.new(child.AnchorPoint.X, 0.5)
                child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0.5, 0)
            else
                seenLabel += 1
                if seenLabel == 1 then
                    nameLabel = child
                    -- Name fills the row height and centres, keeping its designed
                    -- width so it never slides under the interactive part.
                    child.AnchorPoint = Vector2.new(child.AnchorPoint.X, 0.5)
                    child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0.5, 0)
                    child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 1, 0)
                else
                    -- No room for descriptions inside a single row.
                    child.Visible = false
                end
            end
        elseif child:IsA("GuiObject") then
            local size = child.Size
            local fillsHolder = size.X.Scale == 1 and size.X.Offset == 0
                and size.Y.Scale == 1 and size.Y.Offset == 0
            if not fillsHolder then
                local height = size.Y.Offset
                if size.Y.Scale ~= 0 then
                    height = rowHeight
                elseif height <= 0 or height > rowHeight then
                    height = math.min(math.max(height, 1), rowHeight)
                end
                -- Cap interactive parts to a sane column height so a 44px control
                -- does not poke out of a 34px row.
                height = math.min(height, math.max(18, rowHeight - 8))
                child.AnchorPoint = Vector2.new(child.AnchorPoint.X, 0.5)
                child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0.5, 0)
                child.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, height)
            end
        end
    end
    return nameLabel
end

-- Dims a control while it or its section is disabled. The veil also sinks
-- input, so nothing underneath it can be clicked or dragged.
local function refreshVeil(holder)
    if not holder or not holder.Parent or not holder:IsA("GuiObject") then return end
    if holder:FindFirstChildOfClass("UIListLayout") then return end
    local disabled = holder:GetAttribute("BloodshotDisabled") == true
        or holder:GetAttribute("BloodshotSectionDisabled") == true
    local veil = holder:FindFirstChild("DisabledVeil")
    if disabled and not veil then
        veil = new("Frame", {
            Name = "DisabledVeil",
            BackgroundTransparency = 0.45,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 50,
            Parent = holder,
        })
        bindTheme(veil, "BackgroundColor3", "Background")
        corner(veil, 6)
        local inset = holder:FindFirstChildOfClass("UIPadding")
        local left = inset and inset.PaddingLeft.Offset or 0
        local top = inset and inset.PaddingTop.Offset or 0
        local right = inset and inset.PaddingRight.Offset or 0
        local bottom = inset and inset.PaddingBottom.Offset or 0
        veil.Position = UDim2.fromOffset(-left, -top)
        veil.Size = UDim2.new(1, left + right, 1, top + bottom)
    end
    if veil then veil.Visible = disabled end
end

local function ownerDisabled(object, stopAt)
    local node = object.Parent
    while node and node ~= stopAt do
        if node:GetAttribute("BloodshotDisabled") == true then return true end
        node = node.Parent
    end
    return false
end

-- LayoutOrder drives the visual order; GetChildren() keeps creation order.
local function orderedChildren(parent)
    local list = {}
    local creation = {}
    for position, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            list[#list + 1] = child
            creation[child] = position
        end
    end
    table.sort(list, function(a, b)
        if a.LayoutOrder ~= b.LayoutOrder then
            return a.LayoutOrder < b.LayoutOrder
        end
        if a.Name ~= b.Name then
            return a.Name < b.Name
        end
        return creation[a] < creation[b]
    end)
    return list
end

-- Renumbers a UIListLayout-backed container so the given item lands at index.
local function reorderList(parent, item, index)
    local children = orderedChildren(parent)
    local from = table.find(children, item)
    if not from then return false end
    local target = math.clamp(math.floor(tonumber(index) or from), 1, #children)
    if from ~= target then
        table.remove(children, from)
        table.insert(children, target, item)
    end
    for position, child in ipairs(children) do
        child.LayoutOrder = position
    end
    return true
end

-- Drag-to-reorder for anything living in a UIListLayout container.
-- A press alone never reorders: the pointer must travel past Threshold first,
-- so ordinary clicks, sliders and text entry are untouched.
local function beginReorderDrag(handle, target, container, window, vertical, threshold, onReorder)
    if not handle or not target or not container or not window then return nil end
    local state = { Dragged = false, Disconnect = nil }
    local dragging, started, startPoint = false, false, nil
    local reordered = false
    local owned = {}
    local function isDragInput(kind)
        return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
    end
    local function register(connection)
        owned[#owned + 1] = connection
        return connection
    end
    state.Disconnect = function()
        for _, connection in ipairs(owned) do
            if connection.Connected then connection:Disconnect() end
        end
        table.clear(owned)
    end
    register(connect(handle.InputBegan, function(input)
        if not isDragInput(input.UserInputType) then return end
        dragging, started, startPoint = true, false, input.Position
        reordered = false
        state.Dragged = false
    end, window._connections))
    register(connect(UserInputService.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if not started then
            if (input.Position - startPoint).Magnitude < (threshold or 6) then return end
            started = true
        end
        if reordered then
            Library._clickGuard = os.clock() + 5
        end
        -- Slot boundaries are the midpoints between neighbouring centres rather
        -- than the centres themselves, so the row lands under the pointer the
        -- moment the gap opens instead of half an item late.
        local probe = vertical and input.Position.Y or input.Position.X
        local centres = {}
        local current = 1
        for slot, sibling in ipairs(orderedChildren(container)) do
            centres[slot] = vertical
                and (sibling.AbsolutePosition.Y + sibling.AbsoluteSize.Y / 2)
                or (sibling.AbsolutePosition.X + sibling.AbsoluteSize.X / 2)
            if sibling == target then current = slot end
        end
        local best = current
        for slot = 1, #centres do
            local boundary = slot < #centres and (centres[slot] + centres[slot + 1]) / 2 or math.huge
            if probe < boundary then
                best = slot
                break
            end
        end
        if best ~= current then
            reorderList(container, target, best)
            state.Dragged = true
            reordered = true
            Library._clickGuard = os.clock() + 5
            if onReorder then onReorder(best) end
        end
    end, window._connections))
    register(connect(UserInputService.InputEnded, function(input)
        if dragging and isDragInput(input.UserInputType) then
            if reordered then
                Library._clickGuard = os.clock() + 0.3
            end
            dragging, started, reordered = false, false, false
        end
    end, window._connections))
    return state
end

-- Controls whose own interaction already relies on dragging.
local DRAG_CONSUMING_CONTROLS = {
    AddSlider = true,
    AddRangeSlider = true,
    AddInput = true,
    AddNumberInput = true,
    AddColorPicker = true,
    AddTextArea = true,
    AddLog = true,
}

-- Control specs may name a control either way round: hand-written specs usually
-- say "Toggle", while ExportSpec records the Section method name ("AddToggle")
-- so that a spec it produced can be handed straight back to Build or AddRow.
local function controlMethodName(controlType)
    return string.sub(controlType, 1, 3) == "Add" and controlType or ("Add" .. controlType)
end

local Section = {}
Section.__index = Section

-- Disabling stops existing drag handles; re-enabling applies to new controls.
function Section:EnableReorder(enabled)
    enabled = not not enabled
    self._reorderEnabled = enabled
    for _, control in ipairs(self.Controls) do
        if not enabled and control._dragState and control._dragState.Disconnect then
            control._dragState.Disconnect()
            control._dragState = nil
        end
    end
    return enabled
end

function Section:GetControlOrder()
    local names = {}
    for _, child in ipairs(orderedChildren(self.Container)) do
        names[#names + 1] = child.Name
    end
    return names
end

function Section:MoveControl(control, index)
    local instance = type(control) == "table" and control.Instance or control
    if not instance then return false end
    return reorderList(self.Container, instance, index)
end

function Section:GetIndex()
    if not self.Tab or not self.Frame then return nil end
    for position, child in ipairs(orderedChildren(self.Tab.Page)) do
        if child == self.Frame then return position end
    end
    return nil
end

function Section:MoveTo(index)
    if not self.Tab or not self.Frame then return false end
    if not reorderList(self.Tab.Page, self.Frame, index) then return false end
    self.Tab:SyncSectionOrder()
    return true
end

-- Compact multi-widget row. One section entry that lays several controls out
-- side by side instead of stacking each one full width, which is what turns a
-- 23-row catalogue into 23 rows instead of 92 stacked controls.
--   section:AddRow({ Controls = {
--       { Type = "Label", Name = "cloud" },
--       { Type = "ColorPicker", Name = "tint" },
--       { Type = "Toggle", Name = "icons" },
--   } })
-- Width accepts a number of pixels or a UDim2; the remainder is shared evenly.
local ROW_NAME_MIN_WIDTH = 150
local COMPACT_MARGIN = 4
local ROW_REJECTED = {
    AddList = true, AddRow = true, AddImage = true, AddTextArea = true, AddLog = true, AddSpacer = true,
}

local function setWidth(object, scale, offset)
    object.Size = UDim2.new(scale, offset, object.Size.Y.Scale, object.Size.Y.Offset)
end

function Section:AddRow(options)
    options = type(options) == "table" and options or { Controls = options }
    local rowHeight = math.clamp(tonumber(options.Height) or 34, 24, 120)
    local holder = new("Frame", {
        Name = options.Name or "Row",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, rowHeight),
        Parent = self.Container,
    })
    bindTheme(holder, "BackgroundColor3", "SurfaceAlt")
    gradient(holder, "SurfaceAlt", "SurfaceGradient", 12)
    corner(holder, 6)
    local rowStroke = stroke(holder, Library.Theme.Border, 1, 0.45, "Border")
    connect(holder.MouseEnter, function()
        tween(holder, 0.16, { BackgroundTransparency = 0.68 })
        tween(rowStroke, 0.16, { Transparency = 0.2 })
    end, self.Window._connections)
    connect(holder.MouseLeave, function()
        tween(holder, 0.16, { BackgroundTransparency = Library.Theme.ControlTransparency or 0.8 })
        tween(rowStroke, 0.16, { Transparency = 0.45 })
    end, self.Window._connections)
    holder:SetAttribute("BloodshotControl", true)
    holder:SetAttribute("BloodshotRow", true)
    holder:SetAttribute("BloodshotCompact", true)
    holder:SetAttribute("BloodshotDisabled", false)
    holder:SetAttribute("BloodshotBaseHeight", rowHeight)
    holder:SetAttribute("BloodshotHasDescription", false)
    tween(holder, 0.24, { BackgroundTransparency = Library.Theme.ControlTransparency or 0.8 })

    local paddingLeft = options.Padding or 8
    local strip = new("Frame", {
        Name = "Strip",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -(paddingLeft * 2), 1, 0),
        Position = UDim2.fromOffset(paddingLeft, 0),
        Parent = holder,
    })
    local rowSpacing = tonumber(options.Spacing) or 6
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, rowSpacing),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = strip,
    })
    self._overlays = self._overlays or {}

    local specs = type(options.Controls) == "table" and options.Controls or {}
    local fixedTotal, weightTotal, childCount = 0, 0, 0
    for _, spec in ipairs(specs) do
        if type(spec) == "table" then
            childCount += 1
            local fixedWidth = tonumber(spec.Width)
            if fixedWidth then
                fixedTotal += fixedWidth
            else
                weightTotal += math.max(0.01, tonumber(spec.Weight) or 1)
            end
        end
    end
    local gapTotal = math.max(0, childCount - 1) * rowSpacing

    -- Builds a child against its own slot frame. The slot is sized to the width
    -- the caller asked for and full row height, and every control's holder is
    -- rebuilt inside it, so a compact control can never escape its column.
    local function buildRowChild(index, childOptions, window)
        local childType = childOptions.Type or childOptions.type or childOptions.Control
        childOptions.Type, childOptions.type, childOptions.Control = nil, nil, nil
        local methodKey = childType and controlMethodName(tostring(childType))
        local method = methodKey and Section[methodKey]
        if type(method) ~= "function" then
            warn("[Bloodshot UI] AddRow: unknown control type " .. tostring(childType))
            return nil
        end
        if ROW_REJECTED[methodKey] then
            warn("[Bloodshot UI] AddRow: " .. tostring(childType) .. " does not fit in a row")
            return nil
        end
        local weight = math.max(0.01, tonumber(childOptions.Weight) or 1)
        local width = tonumber(childOptions.Width)
        local share = weight / math.max(0.01, weightTotal)
        local slot = new("Frame", {
            Name = "Slot" .. index,
            BackgroundTransparency = 1,
            Size = width and UDim2.fromOffset(width, rowHeight)
                or UDim2.new(share, -(fixedTotal + gapTotal) * share, 1, 0),
            LayoutOrder = index,
            Parent = strip,
        })
        -- Nested section: children delegate to the real Section metatable so
        -- composite controls (NumberInput -> Input) keep working.
        local child = setmetatable({
            Container = slot,
            Window = self.Window,
            Tab = self.Tab,
            _compact = true,
            Controls = {},
            _overlays = self._overlays,
            Slot = slot,
        }, { __index = Section })
        local ok, result = pcall(method, child, childOptions)
        if not ok or type(result) ~= "table" then
            warn("[Bloodshot UI] AddRow: " .. tostring(result))
            slot:Destroy()
            return nil
        end
        compactifyControl(result.Instance, rowHeight)
        -- Names only show once the column is wide enough to hold them next to the
        -- control; the control lays itself out for either case. Slot widths are
        -- not known until the first layout pass, so this runs again on resize.
        local function refreshColumn()
            if not slot.Parent or type(result.CompactLayout) ~= "function" then return end
            local available = slot.AbsoluteSize.X
            if available <= 0 then available = width or 0 end
            result:CompactLayout(available <= 0 or available >= ROW_NAME_MIN_WIDTH, available > 0 and available or nil)
        end
        refreshColumn()
        connect(slot:GetPropertyChangedSignal("AbsoluteSize"), refreshColumn, window._connections)
        result.Window = window
        -- Section.Add* is the enriched wrapper, so the child already carries the full
        -- control contract. It does not join section.Controls (those are the
        -- direct children of the section container); row children are reached
        -- through row.Children, and search walks the instance tree.
        local childDestroy = result.Destroy
        if type(childDestroy) == "function" then
            result.Destroy = function(self, ...)
                local ok, message = pcall(childDestroy, self, ...)
                if slot.Parent then slot:Destroy() end
                if not ok then error(message, 0) end
            end
        end
        result.Slot = slot
        if result.Type == nil then
            result.Type = "Add" .. tostring(childType)
            result.Spec = copyTable(childOptions)
            result.Spec.Type = result.Type
        end
        return result
    end

    local children = {}
    for index, spec in ipairs(specs) do
        if type(spec) == "table" then
            local childOptions = copyTable(spec)
            childOptions.ReorderDrag = false
            local child = buildRowChild(index, childOptions, self.Window)
            if child then table.insert(children, child) end
        end
    end
    -- Slots stay parented to the strip so fixed pixel widths and weight-based
    -- shares are preserved; each child holder fills its own slot.

    local row = {
        Instance = holder,
        Children = children,
        RowHeight = rowHeight,
        -- Row children carry their own specs, so a row round-trips through
        -- ExportSpec/Build as one nested control.
        Spec = copyTable(options),
    }
    row.Spec.Type = "AddRow"
    row.Type = "AddRow"
    row.Get = function(_, index)
        return children[index or 1]
    end
    row.GetChild = row.Get
    row.GetChildren = function() return children end
    row.Set = function(_, index, value, silent)
        local child = children[index]
        if child and child.Set then child:Set(value, silent) end
        return row
    end
    return row
end

function Section:AddLabel(options)
    options = type(options) == "table" and options or { Text = tostring(options) }
    local compact = self._compact == true
    local colorSpec = options.Color or (compact and "Text" or "MutedText")
    local label = text(self.Container, options.Text or options.Name or "Label", options.TextSize or 12, colorSpec, {
        Size = UDim2.new(1, 0, 0, options.Height or 24),
        TextWrapped = options.Wrap == true,
        TextXAlignment = options.Alignment or Enum.TextXAlignment.Left,
        Font = compact and Library.Theme.FontMedium or nil,
    })
    if options.RichText == true then label.RichText = true end
    if compact then
        padding(label, 0, 0, 0, COMPACT_MARGIN)
    end
    if options.Copyable == true then
        connect(label.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if Library:_isObscured(self.Window, input.Position) then return end
            if type(setclipboard) == "function" then
                pcall(setclipboard, label.Text)
                if options.CopyNotify ~= false then
                    Library:Notify({ Title = T("Copied"), Content = label.Text, Duration = 1.5 })
                end
            end
        end, self.Window._connections)
    end
    return {
        Instance = label,
        Set = function(_, value)
            label.Text = tostring(value)
        end,
        Get = function() return label.Text end,
        SetColor = function(_, color)
            local resolved = resolveColor(color, "Text")
            label.TextColor3 = resolved
        end,
    }
end

function Section:AddParagraph(options)
    options = options or {}
    local automaticHeight = options.Height == nil
    local holder, titleLabel = createControlBase(
        self,
        options.Height or 0,
        options.Title or options.Name or "Paragraph"
    )
    if automaticHeight then
        holder.AutomaticSize = Enum.AutomaticSize.Y
        padding(holder, 0, 0, 9, 0)
    end
    titleLabel.Position = UDim2.fromOffset(12, 8)
    titleLabel.Size = UDim2.new(1, -24, 0, 18)
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    if options.RichText == true then
        titleLabel.RichText = true
    end
    local body = text(holder, options.Content or options.Text or "", 11, "MutedText", {
        Font = options.Font,
        Position = UDim2.fromOffset(12, 29),
        Size = automaticHeight and UDim2.new(1, -24, 0, 9) or UDim2.new(1, -24, 1, -38),
        AutomaticSize = automaticHeight and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        TextScaled = not automaticHeight,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    if options.RichText == true then body.RichText = true end
    if options.Copyable == true then
        connect(holder.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if Library:_isObscured(self.Window, input.Position) then return end
            if type(setclipboard) == "function" then
                pcall(setclipboard, body.Text)
                if options.CopyNotify ~= false then
                    Library:Notify({ Title = T("Copied"), Content = titleLabel.Text, Duration = 1.5 })
                end
            end
        end, self.Window._connections)
    end
    return {
        Instance = holder,
        Set = function(_, value)
            body.Text = tostring(value)
        end,
        Get = function() return body.Text end,
        SetTitle = function(_, value)
            titleLabel.Text = tostring(value)
        end,
    }
end

local KEY_LABELS = {
    [Enum.UserInputType.MouseButton1] = "M1",
    [Enum.UserInputType.MouseButton2] = "M2",
    [Enum.UserInputType.MouseButton3] = "M3",
}

local function createKeyChip(section, parent, config)
    local window = section.Window
    local blocked = {}
    for _, key in ipairs(config.Blacklist or {}) do blocked[key] = true end
    local value = Enum.KeyCode.Unknown
    local listening = false
    local skipActivation = false
    local chip = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = config.Position,
        Size = config.Size or UDim2.fromOffset(56, 22),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = "",
        TextSize = 10,
        ZIndex = 5,
        Parent = parent,
    })
    constrainText(chip, 7, 10)
    bindTheme(chip, "BackgroundColor3", "Background")
    corner(chip, 5)
    local function nameOf(key)
        if key == nil or key == Enum.KeyCode.Unknown then return T("Unbound") end
        return KEY_LABELS[key] or key.Name
    end
    local function render()
        chip.Text = listening and "..." or nameOf(value)
        chip.TextColor3 = listening and Library.Theme.Accent or Library.Theme.MutedText
    end
    bindThemeState(chip, render)
    local function set(nextValue, silent)
        if nextValue == nil or nextValue == Enum.KeyCode.Unknown then
            value = Enum.KeyCode.Unknown
        elseif typeof(nextValue) == "EnumItem"
            and (nextValue.EnumType == Enum.KeyCode or KEY_LABELS[nextValue]) and not blocked[nextValue] then
            value = nextValue
        else
            return
        end
        listening = false
        render()
        if not silent and config.OnChanged then safeCall(config.OnChanged, value) end
    end
    local function matches(input)
        if value == Enum.KeyCode.Unknown then return false end
        if value.EnumType == Enum.KeyCode then
            return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == value
        end
        return input.UserInputType == value
    end
    connect(chip.Activated, function(input)
        if Library:_isObscured(window, input and input.Position) then return end
        if skipActivation then
            skipActivation = false
            return
        end
        listening = true
        render()
    end, window._connections)
    connect(UserInputService.InputBegan, function(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.Escape then
                    listening = false
                    render()
                elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                    set(Enum.KeyCode.Unknown)
                else
                    set(input.KeyCode)
                end
            elseif KEY_LABELS[input.UserInputType] then
                local topLeft, size = chip.AbsolutePosition, chip.AbsoluteSize
                skipActivation = input.UserInputType == Enum.UserInputType.MouseButton1
                    and input.Position.X >= topLeft.X and input.Position.X <= topLeft.X + size.X
                    and input.Position.Y >= topLeft.Y and input.Position.Y <= topLeft.Y + size.Y
                set(input.UserInputType)
            end
            return
        end
        if processed then return end
        if matches(input) and config.OnPress then safeCall(config.OnPress, input) end
    end, window._connections)
    connect(UserInputService.InputEnded, function(input)
        if listening then return end
        if matches(input) and config.OnRelease then safeCall(config.OnRelease, input) end
    end, window._connections)
    set(config.Default, true)
    return {
        Button = chip,
        Set = set,
        Get = function() return value end,
        IsListening = function() return listening end,
        Clear = function() set(Enum.KeyCode.Unknown) end,
    }
end

local BUTTON_STYLES = {
    accent = { Tint = "Accent", Rest = 0.6, Hover = 0.4 },
    danger = { Tint = "Error", Rest = 0.6, Hover = 0.4 },
    success = { Tint = "Success", Rest = 0.6, Hover = 0.4 },
    warning = { Tint = "Warning", Rest = 0.6, Hover = 0.4 },
    ghost = { Rest = 1, Hover = 0.82 },
}

local function buttonLook(options)
    local look = BUTTON_STYLES[string.lower(tostring(options.Style or ""))]
    if options.Color ~= nil then
        look = { Tint = options.Color, Rest = look and look.Rest or 0.6, Hover = look and look.Hover or 0.4 }
    end
    return look
end

function Section:AddButton(options)
    options = type(options) == "table" and options or { Name = tostring(options) }
    local compact = self._compact == true
    local look = not compact and buttonLook(options) or nil
    local hasKey = not compact and options.Keybind ~= nil and options.Keybind ~= false
    local reserve = 52 + (hasKey and 64 or 0)
    local holder, nameLabel, descriptionLabel = createControlBase(self, options.Description and 52 or 40, options.Name or "Button", options.Description, look)
    local buttonScale = new("UIScale", {
        Scale = 1,
        Parent = holder,
    })
    nameLabel.Size = UDim2.new(1, -reserve, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    if descriptionLabel then
        descriptionLabel.Size = UDim2.new(1, -reserve, 0, 16)
    end
    local arrow = text(holder, "\u{203A}", 22, "MutedText", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(20, 24),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local button = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = holder,
    })
    local pill
    if compact then
        pill = new("Frame", {
            Name = "Pill",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, 0, 1, -8),
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            ZIndex = 0,
            Parent = holder,
        })
        bindTheme(pill, "BackgroundColor3", "Border")
        corner(pill, 5)
        nameLabel.Position = UDim2.new()
        nameLabel.Size = UDim2.fromScale(1, 1)
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        arrow.Visible = false
    end
    local displayName = tostring(options.Name or "Button")
    local cooldown = math.max(0, tonumber(options.Cooldown) or 0)
    local holdTime = math.max(0, tonumber(options.Hold) or 0)
    local progress
    if cooldown > 0 or holdTime > 0 then
        progress = new("Frame", {
            Name = "Progress",
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(0, 1),
            ZIndex = 0,
            Parent = holder,
        })
        bindTheme(progress, "BackgroundColor3", "Accent")
        corner(progress, 6)
    end
    local armed = false
    local armTimer
    local loading = false
    local coolingDown = false
    local function restore()
        nameLabel.Text = displayName
        nameLabel.TextColor3 = Library.Theme.Text
        arrow.Text = "\u{203A}"
        arrow.TextColor3 = Library.Theme.MutedText
    end
    local function disarm()
        if armTimer then
            task.cancel(armTimer)
            armTimer = nil
        end
        if not armed then return end
        armed = false
        restore()
        if not look then tween(holder, 0.15, { BackgroundColor3 = Library.Theme.SurfaceAlt }) end
    end
    local function arm()
        armed = true
        nameLabel.Text = tostring(options.ConfirmText or (T("Confirm")))
        nameLabel.TextColor3 = Library.Theme.Error
        arrow.Text = "!"
        if not look then tween(holder, 0.15, { BackgroundColor3 = Library.Theme.SurfaceAlt }) end
        if armTimer then task.cancel(armTimer) end
        armTimer = task.delay(options.ConfirmTimeout or 3, function()
            armTimer = nil
            disarm()
        end)
    end
    local function startCooldown()
        if cooldown <= 0 then return end
        coolingDown = true
        progress.Size = UDim2.fromScale(1, 1)
        tween(progress, cooldown, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
        task.delay(cooldown, function()
            coolingDown = false
            if progress.Parent then progress.Size = UDim2.fromScale(0, 1) end
        end)
    end
    local function run()
        if loading or coolingDown then return false end
        if options.Confirm == true then
            if not armed then
                arm()
                return false
            end
            disarm()
        end
        safeCall(options.Callback)
        startCooldown()
        return true
    end
    connect(button.MouseEnter, function()
        if not armed then
            if pill then
                tween(pill, 0.15, { BackgroundTransparency = 0.3 })
            elseif look then
                tween(arrow, 0.15, { Position = UDim2.new(1, -8, 0.5, 0) })
            else
                tween(holder, 0.15, { BackgroundColor3 = Library.Theme.Border })
                tween(arrow, 0.15, { Position = UDim2.new(1, -8, 0.5, 0) })
            end
        end
    end, self.Window._connections)
    connect(button.MouseLeave, function()
        if not armed then
            if pill then
                tween(pill, 0.15, { BackgroundTransparency = 0.55 })
            elseif look then
                tween(arrow, 0.15, { Position = UDim2.new(1, -12, 0.5, 0) })
            else
                tween(holder, 0.15, { BackgroundColor3 = Library.Theme.SurfaceAlt })
                tween(arrow, 0.15, { Position = UDim2.new(1, -12, 0.5, 0) })
            end
        end
    end, self.Window._connections)
    local function feedback(position)
        ripple(holder, position)
        tween(buttonScale, 0.08, { Scale = 0.97 }, Enum.EasingStyle.Sine).Completed:Connect(function()
            if holder.Parent then
                tween(buttonScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
            end
        end)
    end
    if holdTime > 0 then
        local holding = false
        local token = 0
        local function release()
            if not holding then return end
            holding = false
            token += 1
            tween(progress, 0.12, { Size = UDim2.fromScale(0, 1) })
        end
        connect(button.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if loading or coolingDown or Library:_isObscured(self.Window, input.Position) then return end
            holding = true
            token += 1
            local mine = token
            progress.Size = UDim2.fromScale(0, 1)
            tween(progress, holdTime, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
            task.delay(holdTime, function()
                if holding and token == mine then
                    holding = false
                    progress.Size = UDim2.fromScale(0, 1)
                    feedback(input.Position)
                    run()
                end
            end)
        end, self.Window._connections)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                release()
            end
        end, self.Window._connections)
        connect(button.MouseLeave, release, self.Window._connections)
    else
        connect(button.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then
                return
            end
            feedback(input and input.Position)
            run()
        end, self.Window._connections)
    end
    local control = {
        Instance = holder,
        Fire = function() return run() end,
        IsArmed = function() return armed end,
        Disarm = disarm,
        IsLoading = function() return loading end,
        IsCoolingDown = function() return coolingDown end,
        SetText = function(_, value)
            displayName = tostring(value)
            if not armed and not loading then nameLabel.Text = displayName end
        end,
        SetLoading = function(_, state, caption)
            loading = not not state
            disarm()
            if loading then
                nameLabel.Text = tostring(caption or T("Loading"))
                nameLabel.TextColor3 = Library.Theme.MutedText
                arrow.Text = "..."
            else
                restore()
            end
        end,
    }
    control.Arm = arm
    if hasKey then
        local keyFlag = options.KeybindFlag or (options.Flag and (tostring(options.Flag) .. "_Key") or nil)
        local keyControl = createKeyChip(self, holder, {
            Default = options.Keybind == true and Enum.KeyCode.Unknown or parseKeyName(options.Keybind),
            Position = UDim2.new(1, -40, 0.5, 0),
            Blacklist = options.KeybindBlacklist,
            OnChanged = function(key)
                commitFlag(keyFlag, key)
                safeCall(options.KeybindChanged, key)
            end,
            OnPress = function()
                if holder:GetAttribute("BloodshotDisabled") == true then return end
                run()
            end,
        })
        if keyFlag then
            registerFlagSetter(self.Window, keyFlag, function(value, silent)
                keyControl.Set(value, true)
                commitFlag(keyFlag, keyControl.Get())
                if not silent then safeCall(options.KeybindChanged, keyControl.Get()) end
            end)
            Library._flagTypes[keyFlag] = "EnumItem"
            commitFlag(keyFlag, keyControl.Get())
        end
        control.Keybind = keyControl
        control.SetKeybind = function(_, key) keyControl.Set(key) end
        control.GetKeybind = function() return keyControl.Get() end
    end
    return control
end

function Section:AddToggle(options)
    options = options or {}
    local compact = self._compact == true
    local checkbox = string.lower(tostring(options.Style or "")) == "checkbox"
    local hasKey = not compact and options.Keybind ~= nil and options.Keybind ~= false
    local controlWidth = checkbox and 20 or 38
    local reserve = controlWidth + 30 + (hasKey and 64 or 0)
    local holder, nameLabel, descriptionLabel = createControlBase(self, options.Description and 52 or 40, options.Name or "Toggle", options.Description)
    nameLabel.Size = UDim2.new(1, -reserve, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    if descriptionLabel then
        descriptionLabel.Size = UDim2.new(1, -reserve, 0, 16)
    end
    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(controlWidth, 20),
        BorderSizePixel = 0,
        Parent = holder,
    })
    corner(track, checkbox and 5 or 999)
    local knob
    if checkbox then
        stroke(track, Library.Theme.Border, 1, 0, "Border")
        knob = text(track, "\u{2713}", 14, "Text", {
            Size = UDim2.fromScale(1, 1),
            TextXAlignment = Enum.TextXAlignment.Center,
            Font = Enum.Font.GothamBold,
            TextScaled = false,
        })
        knob.TextTransparency = 1
    else
        knob = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundColor3 = Color3.fromRGB(235, 238, 245),
            BorderSizePixel = 0,
            Parent = track,
        })
        corner(knob, 999)
    end
    local button = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = holder,
    })
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(1, -(COMPACT_MARGIN * 2 + controlWidth + 8), 1, 0)
        track.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
    end

    local value = options.Default == true
    local function accent()
        return resolveColor(options.Color, "Accent")
    end
    local function paint(animate)
        local fillColor
        if checkbox then
            fillColor = value and accent() or Library.Theme.Background
        else
            fillColor = value and accent() or Library.Theme.Border
        end
        local marker = checkbox and { TextTransparency = value and 0 or 1 }
            or { Position = value and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }
        if animate then
            tween(track, 0.16, { BackgroundColor3 = fillColor })
            tween(knob, 0.16, marker)
        else
            track.BackgroundColor3 = fillColor
            for property, target in pairs(marker) do knob[property] = target end
        end
    end
    local function set(nextValue, silent)
        value = not not nextValue
        paint(true)
        commitFlag(options.Flag, value)
        if not silent then
            safeCall(options.Callback, value)
        end
    end
    bindThemeState(track, function() paint(false) end)
    connect(button.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then
            return
        end
        set(not value)
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    if options.FireOnLoad then
        safeCall(options.Callback, value)
    end
    local control = {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        SetColor = function(_, color)
            options.Color = color
            paint(false)
        end,
    }
    if hasKey then
        local keyFlag = options.KeybindFlag or (options.Flag and (tostring(options.Flag) .. "_Key") or nil)
        local keyMode = string.lower(tostring(options.KeybindMode or "Toggle"))
        local keyControl = createKeyChip(self, holder, {
            Default = options.Keybind == true and Enum.KeyCode.Unknown or parseKeyName(options.Keybind),
            Position = UDim2.new(1, -(12 + controlWidth + 8), 0.5, 0),
            Blacklist = options.KeybindBlacklist,
            OnChanged = function(key)
                commitFlag(keyFlag, key)
                safeCall(options.KeybindChanged, key)
            end,
            OnPress = function()
                if holder:GetAttribute("BloodshotDisabled") == true then return end
                if keyMode == "hold" then set(true) else set(not value) end
            end,
            OnRelease = function()
                if keyMode == "hold" and holder:GetAttribute("BloodshotDisabled") ~= true then set(false) end
            end,
        })
        if keyFlag then
            registerFlagSetter(self.Window, keyFlag, function(key, silent)
                keyControl.Set(key, true)
                commitFlag(keyFlag, keyControl.Get())
                if not silent then safeCall(options.KeybindChanged, keyControl.Get()) end
            end)
            Library._flagTypes[keyFlag] = "EnumItem"
            commitFlag(keyFlag, keyControl.Get())
        end
        control.Keybind = keyControl
        control.SetKeybind = function(_, key) keyControl.Set(key) end
        control.GetKeybind = function() return keyControl.Get() end
        control.SetKeybindMode = function(_, mode)
            mode = string.lower(tostring(mode))
            if mode == "toggle" or mode == "hold" then keyMode = mode end
        end
    end
    return control
end

function Section:AddSlider(options)
    options = options or {}
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    local increment = tonumber(options.Increment) or 1
    if minimum ~= minimum then minimum = 0 end
    if maximum ~= maximum then maximum = 100 end
    if increment ~= increment or increment <= 0 then
        increment = 1
    end
    if maximum <= minimum then
        maximum = minimum + 1
    end
    local compact = self._compact == true
    local showValue = options.ShowValue ~= false
    local editable = options.Editable == true and showValue and not compact
    local holder, nameLabel = createControlBase(self, 58, options.Name or "Slider")
    local valueWidth = options.Format ~= nil and 112 or 64
    nameLabel.Size = UDim2.new(1, showValue and -(valueWidth + 28) or -24, 0, 30)
    local valueLabel = text(holder, "", 12, "MutedText", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 0),
        Size = UDim2.fromOffset(valueWidth, 30),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    valueLabel.Visible = showValue
    local track = new("Frame", {
        Position = UDim2.fromOffset(12, 41),
        Size = UDim2.new(1, -24, 0, 5),
        BorderSizePixel = 0,
        Parent = holder,
    })
    bindTheme(track, "BackgroundColor3", "Border")
    corner(track, 999)
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BorderSizePixel = 0,
        Parent = track,
    })
    local fillGradient
    if options.Color ~= nil then
        bindThemeState(fill, function()
            fill.BackgroundColor3 = resolveColor(options.Color, "Accent")
        end)
    else
        bindTheme(fill, "BackgroundColor3", "Accent")
        fillGradient = gradient(fill, "Accent", "AccentGradient", 0)
    end
    corner(fill, 999)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = track,
    })
    bindTheme(knob, "BackgroundColor3", "Text")
    corner(knob, 999)
    local hitbox = new("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, -8),
        Size = UDim2.new(1, 0, 1, 16),
        Text = "",
        ZIndex = 5,
        Parent = track,
    })
    local span = maximum - minimum
    local function addTick(ratio)
        local tick = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(math.clamp(ratio, 0, 1), 0.5),
            Size = UDim2.fromOffset(2, 9),
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = track,
        })
        bindTheme(tick, "BackgroundColor3", "MutedText")
    end
    if type(options.Marks) == "table" then
        for _, mark in ipairs(options.Marks) do
            if tonumber(mark) then addTick((tonumber(mark) - minimum) / span) end
        end
    elseif (tonumber(options.Ticks) or 0) >= 2 then
        local count = math.min(math.floor(tonumber(options.Ticks)), 41)
        for index = 0, count - 1 do addTick(index / (count - 1)) end
    end
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.3, -COMPACT_MARGIN, 1, 0)
        valueLabel:SetAttribute("BloodshotKeep", true)
        valueLabel.AnchorPoint = Vector2.new(1, 0.5)
        valueLabel.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
        valueLabel.Size = UDim2.new(0, 56, 1, 0)
    end

    local value = minimum
    local dragging = false
    local decimals = math.max(0, #(tostring(increment):match("%.(%d+)") or ""))
    local function round(number)
        return math.floor((number / increment) + 0.5) * increment
    end
    local function formatValue(number)
        local numeric = string.format("%." .. decimals .. "f", number)
        local ratio = (number - minimum) / span
        if type(options.Format) == "function" then
            local ok, result = pcall(options.Format, number, ratio)
            if ok and result ~= nil then return tostring(result) end
        elseif type(options.Format) == "string" then
            return expandTemplate(options.Format, {
                value = numeric, percent = math.floor(ratio * 100 + 0.5), min = minimum, max = maximum,
                prefix = options.Prefix or "", suffix = options.Suffix or "",
            })
        end
        return (options.Prefix or "") .. numeric .. (options.Suffix or "")
    end
    local function set(nextValue, silent)
        local snapped = round(tonumber(nextValue) or minimum)
        snapped = tonumber(string.format("%." .. decimals .. "f", snapped)) or snapped
        value = math.clamp(snapped, minimum, maximum)
        local ratio = (value - minimum) / span
        fill.Size = UDim2.fromScale(ratio, 1)
        knob.Position = UDim2.fromScale(ratio, 0.5)
        valueLabel.Text = formatValue(value)
        commitFlag(options.Flag, value)
        if not silent then
            safeCall(options.Callback, value)
        end
    end
    local function updateFromInput(input)
        local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        set(minimum + span * ratio)
    end
    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if Library:_isObscured(self.Window, input.Position) then
                return
            end
            dragging = true
            updateFromInput(input)
        end
    end, self.Window._connections)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end, self.Window._connections)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end, self.Window._connections)
    if editable then
        local valueBox = new("TextBox", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -12, 0, 4),
            Size = UDim2.fromOffset(valueWidth + 8, 22),
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            Text = "",
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
            Visible = false,
            ZIndex = 7,
            Parent = holder,
        })
        bindTheme(valueBox, "BackgroundColor3", "Background")
        bindTheme(valueBox, "TextColor3", "Text")
        corner(valueBox, 4)
        padding(valueBox, 0, 6, 0, 6)
        local valueButton = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -12, 0, 0),
            Size = UDim2.fromOffset(valueWidth + 8, 30),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 6,
            Parent = holder,
        })
        connect(valueButton.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            valueBox.Text = string.format("%." .. decimals .. "f", value)
            valueBox.Visible = true
            valueBox:CaptureFocus()
        end, self.Window._connections)
        connect(valueBox.FocusLost, function()
            valueBox.Visible = false
            local parsed = tonumber((string.gsub(valueBox.Text, "[^%d%.%-eE+]", "")))
            if parsed then set(parsed) end
        end, self.Window._connections)
    end
    registerFlagSetter(self.Window, options.Flag, set)
    set(options.Default or minimum, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        SetColor = function(_, color)
            options.Color = color
            if fillGradient then
                fillGradient:Destroy()
                fillGradient = nil
            end
            fill.BackgroundColor3 = resolveColor(color, "Accent")
        end,
        CompactLayout = function(_, showName, available)
            nameLabel.Visible = showName
            local valueWidth = showValue and (available and math.clamp(math.floor(available * 0.36), 32, 56) or 56) or 0
            valueLabel.Size = UDim2.new(0, valueWidth, 1, 0)
            local reserve = valueWidth + (showValue and 12 or 0)
            track.Position = showName and UDim2.new(0.34, 0, 0.5, 0) or UDim2.new(0, COMPACT_MARGIN, 0.5, 0)
            setWidth(track, showName and 0.66 or 1, -(showName and COMPACT_MARGIN + reserve or COMPACT_MARGIN * 2 + reserve))
        end,
    }
end

local INPUT_FILTERS = {
    number = "%d%.%-", integer = "%d%-", digits = "%d", alpha = "%a", letters = "%a",
    alphanumeric = "%w", hex = "%x#", word = "%w_",
}

function Section:AddInput(options)
    options = options or {}
    local holder, nameLabel, descriptionLabel = createControlBase(self, options.Description and 58 or 46, options.Name or "Input", options.Description)
    nameLabel.Size = UDim2.new(0.4, -12, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    if descriptionLabel then
        descriptionLabel.Size = UDim2.new(0.4, -12, 0, 16)
    end
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0.52, 0, 0, 28),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        Text = tostring(options.Default or ""),
        PlaceholderText = options.Placeholder or T("EnterValue"),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })
    constrainText(box, 8, 12)
    bindTheme(box, "BackgroundColor3", "Background")
    bindTheme(box, "TextColor3", "Text")
    bindTheme(box, "PlaceholderColor3", "MutedText")
    corner(box, 5)
    local boxPadding = padding(box, 0, 8, 0, 8)
    if self._compact == true then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.4, -COMPACT_MARGIN, 1, 0)
        box.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
    end
    local maxLength = tonumber(options.MaxLength)
    local filterSpec = options.Filter
    local clearButton
    if options.ReadOnly == true then box.TextEditable = false end
    if options.Clearable == true and not options.Numeric then
        boxPadding.PaddingRight = UDim.new(0, 26)
        clearButton = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 20, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = "x",
            TextSize = 12,
            Visible = false,
            ZIndex = 3,
            Parent = box,
        })
        bindTheme(clearButton, "TextColor3", "MutedText")
        connect(clearButton.MouseEnter, function()
            tween(clearButton, 0.12, { TextColor3 = Library.Theme.Error })
        end, self.Window._connections)
        connect(clearButton.MouseLeave, function()
            tween(clearButton, 0.12, { TextColor3 = Library.Theme.MutedText })
        end, self.Window._connections)
    end
    local function applyFilter(raw)
        local result = raw
        if type(filterSpec) == "function" then
            local ok, mapped = pcall(filterSpec, raw)
            if ok and type(mapped) == "string" then result = mapped end
        elseif type(filterSpec) == "string" then
            local class = INPUT_FILTERS[string.lower(filterSpec)] or filterSpec
            local ok, mapped = pcall(string.gsub, raw, "[^" .. class .. "]", "")
            if ok then result = mapped end
        end
        if maxLength and #result > maxLength then
            result = string.sub(result, 1, maxLength)
        end
        return result
    end
    local filtering = false
    connect(box:GetPropertyChangedSignal("Text"), function()
        if not filtering and not options.Numeric then
            local filtered = applyFilter(box.Text)
            if filtered ~= box.Text then
                filtering = true
                box.Text = filtered
                filtering = false
            end
        end
        if clearButton then clearButton.Visible = box.Text ~= "" end
    end, self.Window._connections)
    if clearButton then clearButton.Visible = box.Text ~= "" end

    local value = box.Text
    local normalize = type(options.Normalize) == "function" and options.Normalize or nil
    local function validNumber(numeric)
        return numeric ~= nil and numeric == numeric and numeric ~= math.huge and numeric ~= -math.huge
    end
    local function set(nextValue, silent)
        if options.Numeric then
            local numeric = tonumber(nextValue)
            if not validNumber(numeric) then
                return
            end
            if normalize then
                numeric = normalize(numeric)
            end
            value = numeric
        else
            value = tostring(nextValue or "")
        end
        box.Text = tostring(value)
        commitFlag(options.Flag, value)
        if not silent then
            safeCall(options.Callback, value)
        end
    end
    connect(box.Focused, function()
        tween(box, 0.15, { BackgroundColor3 = Library.Theme.Surface })
    end, self.Window._connections)
    connect(box.FocusLost, function(enterPressed)
        tween(box, 0.15, { BackgroundColor3 = Library.Theme.Background })
        if options.Numeric then
            local numeric = tonumber(box.Text)
            if not validNumber(numeric) then
                box.Text = tostring(value)
                return
            end
            if normalize then
                numeric = normalize(numeric)
            end
            value = numeric
            box.Text = tostring(numeric)
        else
            if options.OnlyEnter == true and not enterPressed then
                box.Text = tostring(value)
                return
            end
            value = box.Text
        end
        commitFlag(options.Flag, value)
        safeCall(options.Callback, value, enterPressed)
    end, self.Window._connections)
    if clearButton then
        connect(clearButton.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            set("")
            box:CaptureFocus()
        end, self.Window._connections)
    end
    registerFlagSetter(self.Window, options.Flag, set)
    if options.Numeric then
        set(options.Default or 0, true)
    else
        set(options.Default or "", true)
    end
    return {
        Instance = holder,
        Box = box,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        Focus = function() box:CaptureFocus() end,
        SetReadOnly = function(_, enabled) box.TextEditable = not enabled end,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
            box.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
            setWidth(box, showName and 0.56 or 1, showName and -COMPACT_MARGIN or -COMPACT_MARGIN * 2)
        end,
    }
end

function Section:AddDropdown(options)
    options = options or {}
    local values = options.Values or options.Options or {}
    local function sortedCopy(source)
        local copy = {}
        for index, item in ipairs(source) do copy[index] = item end
        table.sort(copy, function(a, b) return tostring(a) < tostring(b) end)
        return copy
    end
    if options.Sorted == true then values = sortedCopy(values) end
    local multi = options.Multi == true
    local selected = multi and {} or nil
    local chosen = {}
    local maxSelected = multi and tonumber(options.MaxSelected) or nil
    local maxDisplay = tonumber(options.MaxDisplay)
    local clearable = options.Clearable == true and not multi
    local open = false
    local baseHeight = 46
    local compact = self._compact == true
    local holder, nameLabel = createControlBase(self, baseHeight, options.Name or "Dropdown")
    nameLabel.Size = UDim2.new(0.4, -12, 0, baseHeight)
    local display = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 9),
        Size = UDim2.new(0.52, 0, 0, 28),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Gotham,
        Text = "",
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })
    constrainText(display, 8, 11)
    bindTheme(display, "BackgroundColor3", "Background")
    bindTheme(display, "TextColor3", "MutedText")
    corner(display, 5)
    padding(display, 0, clearable and 44 or 26, 0, 8)
    local displayScale = new("UIScale", {
        Scale = 1,
        Parent = display,
    })
    local clearButton
    if clearable then
        clearButton = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 20, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = "x",
            TextSize = 12,
            Visible = false,
            ZIndex = 4,
            Parent = display,
        })
        bindTheme(clearButton, "TextColor3", "MutedText")
        connect(clearButton.MouseEnter, function()
            tween(clearButton, 0.12, { TextColor3 = Library.Theme.Error })
        end, self.Window._connections)
        connect(clearButton.MouseLeave, function()
            tween(clearButton, 0.12, { TextColor3 = Library.Theme.MutedText })
        end, self.Window._connections)
    end
    local arrow = text(holder, "▼", 11, "MutedText", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0, 23),
        Size = UDim2.fromOffset(16, 18),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 3,
    })
    -- A row clips everything it holds, so a row child opens its list on the
    -- window root instead of growing its own holder.
    local list = new("ScrollingFrame", {
        Visible = false,
        Position = UDim2.fromOffset(12, baseHeight),
        Size = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Active = compact,
        ZIndex = compact and 60 or 1,
        Parent = compact and self.Window.Root or holder,
    })
    bindTheme(list, "BackgroundColor3", "Background")
    bindTheme(list, "ScrollBarImageColor3", "Accent")
    corner(list, 5)
    padding(list, 4, 4, 4, 4)
    if compact then
        self._overlays = self._overlays or {}
        table.insert(self._overlays, list)
        stroke(list, Library.Theme.Border, 1, 0.25, "Border")
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.4, -COMPACT_MARGIN, 1, 0)
        display.Position = UDim2.new(1, -COMPACT_MARGIN, 0, 9)
        arrow:SetAttribute("BloodshotKeep", true)
        arrow.Position = UDim2.new(1, -(COMPACT_MARGIN + 12), 0.5, 0)
    end
    local listWidth = 0
    local listHeightNow = 0
    local function listSize(height)
        if compact then return UDim2.fromOffset(listWidth, height) end
        return UDim2.new(1, -24, 0, height)
    end
    local function placeList()
        if not compact or not open then return end
        local rootFrame = self.Window.Root
        local rootSize = rootFrame.AbsoluteSize
        if rootSize.X <= 0 or rootSize.Y <= 0 then return end
        local width = math.clamp(display.AbsoluteSize.X, 120, math.max(120, rootSize.X - 12))
        local origin = display.AbsolutePosition - rootFrame.AbsolutePosition
        local x = math.clamp(origin.X + display.AbsoluteSize.X - width, 6, math.max(6, rootSize.X - width - 6))
        local below = origin.Y + display.AbsoluteSize.Y + 4
        local above = origin.Y - 4
        local flip = below + listHeightNow > rootSize.Y - 6 and above - listHeightNow >= 6
        listWidth = width
        list.AnchorPoint = Vector2.new(0, flip and 1 or 0)
        list.Position = UDim2.fromOffset(x, flip and above or below)
        list.Size = UDim2.new(0, width, 0, list.Size.Y.Offset)
    end
    local layout = new("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })

    local optionButtons = {}
    local maxVisibleRows = math.clamp(math.floor(tonumber(options.MaxVisibleRows) or 5), 1, 12)
    local searchBox
    if options.Searchable == true then
        searchBox = new("TextBox", {
            Name = "Search",
            LayoutOrder = -2,
            BackgroundColor3 = Library.Theme.SurfaceAlt,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 26),
            ClearTextOnFocus = false,
            PlaceholderText = options.SearchPlaceholder or T("SearchPlaceholder"),
            PlaceholderColor3 = Library.Theme.MutedText,
            Text = "",
            TextColor3 = Library.Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = list,
        })
        corner(searchBox, 4)
        padding(searchBox, 0, 8, 0, 8)
        bindTheme(searchBox, "BackgroundColor3", "SurfaceAlt")
        bindTheme(searchBox, "PlaceholderColor3", "MutedText")
        bindTheme(searchBox, "TextColor3", "Text")
    end
    local actions
    if multi and options.SelectAll == true then
        actions = new("Frame", {
            Name = "Actions",
            LayoutOrder = -3,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 24),
            Parent = list,
        })
    end
    local function chrome()
        return (searchBox and 29 or 0) + (actions and 27 or 0)
    end
    local emptyLabel = text(list, options.EmptyText or T("NoOptions"), 11, "MutedText", {
        Size = UDim2.new(1, 0, 0, 26),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    emptyLabel.LayoutOrder = -1
    emptyLabel.Visible = false
    local function filterOptions(query)
        query = string.lower(tostring(query or ""))
        local count = 0
        for item, button in pairs(optionButtons) do
            local visible = query == "" or string.find(string.lower(tostring(item)), query, 1, true) ~= nil
            button.Visible = visible
            if visible then count += 1 end
        end
        emptyLabel.Visible = count == 0
        if open then
            local height = (count == 0 and 36 or math.min(count, maxVisibleRows) * 28 + 8) + chrome()
            listHeightNow = height
            list.Size = listSize(height)
            if compact then
                placeList()
            else
                holder.Size = UDim2.new(1, 0, 0, baseHeight + height + 8)
            end
        end
        return count
    end
    if searchBox then
        connect(searchBox:GetPropertyChangedSignal("Text"), function()
            filterOptions(searchBox.Text)
        end, self.Window._connections)
    end
    local function renderText()
        if multi then
            local names = {}
            for _, item in ipairs(values) do
                if selected[item] then
                    table.insert(names, tostring(item))
                end
            end
            if maxDisplay and maxDisplay >= 1 and #names > maxDisplay then
                local head = {}
                for index = 1, maxDisplay do head[index] = names[index] end
                display.Text = table.concat(head, ", ") .. " +" .. (#names - maxDisplay)
            else
                display.Text = #names > 0 and table.concat(names, ", ") or (options.Placeholder or T("SelectPlaceholder"))
            end
        else
            display.Text = selected ~= nil and tostring(selected) or (options.Placeholder or T("SelectPlaceholder"))
        end
    end
    local function outputValue()
        if not multi then
            return selected
        end
        local copy = {}
        for key, enabled in pairs(selected) do
            if enabled then copy[key] = true end
        end
        return copy
    end
    local function refreshButtons()
        for item, button in pairs(optionButtons) do
            local active = multi and selected[item] or selected == item
            button.TextColor3 = active and Library.Theme.Accent or Library.Theme.MutedText
            button.BackgroundTransparency = active and 0.25 or 1
        end
        if clearButton then clearButton.Visible = selected ~= nil end
        renderText()
    end
    local function set(nextValue, silent)
        if multi then
            selected = {}
            if type(nextValue) == "table" then
                for key, enabled in pairs(nextValue) do
                    if type(key) == "number" then
                        if table.find(values, enabled) then selected[enabled] = true end
                    elseif enabled and table.find(values, key) then
                        selected[key] = true
                    end
                end
            end
            if maxSelected then
                local count = 0
                for _, item in ipairs(values) do
                    if selected[item] then
                        count += 1
                        if count > maxSelected then selected[item] = nil end
                    end
                end
            end
            local kept = {}
            for _, item in ipairs(chosen) do
                if selected[item] then kept[#kept + 1] = item end
            end
            for _, item in ipairs(values) do
                if selected[item] and not table.find(kept, item) then kept[#kept + 1] = item end
            end
            chosen = kept
        else
            selected = nextValue ~= nil and table.find(values, nextValue) and nextValue or nil
        end
        refreshButtons()
        local output = outputValue()
        commitFlag(options.Flag, output)
        if not silent then safeCall(options.Callback, output) end
    end
    local function setOpen(nextOpen)
        open = not not nextOpen
        local listHeight = math.min(#values, maxVisibleRows) * 28 + 8 + chrome()
        if #values == 0 then listHeight = 36 + chrome() end
        if open then
            listHeightNow = listHeight
            list.Visible = true
            placeList()
            list.Size = listSize(0)
            list.BackgroundTransparency = 1
            for _, option in pairs(optionButtons) do
                option.TextTransparency = 0.55
                tween(option, 0.2, { TextTransparency = 0 })
            end
            tween(list, 0.2, {
                Size = listSize(listHeight),
                BackgroundTransparency = compact and 0 or 0.06,
            })
            if not compact then
                tween(holder, 0.22, {
                    Size = UDim2.new(1, 0, 0, baseHeight + listHeight + 8),
                }, Enum.EasingStyle.Quint)
            end
        else
            local animation = tween(list, 0.16, {
                Size = listSize(0),
                BackgroundTransparency = 1,
            })
            if not compact then
                tween(holder, 0.18, { Size = UDim2.new(1, 0, 0, baseHeight) })
            end
            animation.Completed:Connect(function()
                if not open then list.Visible = false end
            end)
        end
        tween(arrow, 0.18, { Rotation = open and 180 or 0 }, Enum.EasingStyle.Back)
    end
    local function rebuild(nextValues)
        values = type(nextValues) == "table" and nextValues or values
        if options.Sorted == true then values = sortedCopy(values) end
        for _, button in pairs(optionButtons) do button:Destroy() end
        table.clear(optionButtons)
        for index, item in ipairs(values) do
            local option = new("TextButton", {
                BackgroundTransparency = 1,
                BackgroundColor3 = Library.Theme.SurfaceAlt,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 25),
                AutoButtonColor = false,
                Font = Enum.Font.Gotham,
                Text = tostring(item),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = index,
                Parent = list,
            })
            constrainText(option, 8, 11)
            corner(option, 4)
            padding(option, 0, 8, 0, 8)
            local optionScale = new("UIScale", {
                Scale = 1,
                Parent = option,
            })
            optionButtons[item] = option
            bindThemeState(option, function()
                local active = multi and selected[item] or selected == item
                option.BackgroundColor3 = Library.Theme.SurfaceAlt
                option.TextColor3 = active and Library.Theme.Accent or Library.Theme.MutedText
            end)
            connect(option.MouseEnter, function()
                tween(optionScale, 0.12, { Scale = 1.018 })
                tween(option, 0.12, {
                    BackgroundTransparency = 0.38,
                    TextColor3 = Library.Theme.Accent,
                })
            end, self.Window._connections)
            connect(option.MouseLeave, function()
                tween(optionScale, 0.12, { Scale = 1 })
                local active = multi and selected[item] or selected == item
                tween(option, 0.12, {
                    BackgroundTransparency = active and 0.25 or 1,
                    TextColor3 = active and Library.Theme.Accent or Library.Theme.MutedText,
                })
            end, self.Window._connections)
            connect(option.Activated, function(input)
                if Library:_isObscured(self.Window, input and input.Position) then
                    return
                end
                tween(displayScale, 0.08, { Scale = 0.97 }).Completed:Connect(function()
                    if display.Parent then tween(displayScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back) end
                end)
                if multi then
                    if not selected[item] and maxSelected then
                        local count = 0
                        for _, on in pairs(selected) do
                            if on then count += 1 end
                        end
                        if count >= maxSelected then
                            if options.ReplaceOldest == true and #chosen > 0 then
                                selected[table.remove(chosen, 1)] = nil
                            else
                                return
                            end
                        end
                    end
                    selected[item] = not selected[item]
                    set(selected)
                else
                    set(item)
                    setOpen(false)
                end
            end, self.Window._connections)
        end
        emptyLabel.Visible = #values == 0
        refreshButtons()
    end
    if actions then
        local function actionButton(label, anchor, handler)
            local button = new("TextButton", {
                AnchorPoint = Vector2.new(anchor, 0),
                Position = UDim2.new(anchor, 0, 0, 0),
                Size = UDim2.new(0.5, -2, 1, 0),
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Font = Enum.Font.GothamMedium,
                Text = label,
                TextSize = 10,
                Parent = actions,
            })
            bindTheme(button, "BackgroundColor3", "SurfaceAlt")
            bindTheme(button, "TextColor3", "MutedText")
            corner(button, 4)
            connect(button.Activated, function(input)
                if Library:_isObscured(self.Window, input and input.Position) then return end
                handler()
            end, self.Window._connections)
        end
        actionButton(T("SelectAll"), 0, function()
            local all = {}
            local count = 0
            for _, item in ipairs(values) do
                if maxSelected and count >= maxSelected then break end
                all[item] = true
                count += 1
            end
            set(all)
        end)
        actionButton(T("SelectNone"), 1, function()
            set({})
        end)
    end
    if clearButton then
        connect(clearButton.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            set(nil)
        end, self.Window._connections)
    end
    connect(display.MouseEnter, function()
        tween(displayScale, 0.14, { Scale = 1.015 })
        tween(display, 0.14, { BackgroundColor3 = Library.Theme.Surface })
    end, self.Window._connections)
    connect(display.MouseLeave, function()
        tween(displayScale, 0.14, { Scale = 1 })
        tween(display, 0.14, { BackgroundColor3 = Library.Theme.Background })
    end, self.Window._connections)
    connect(display.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then
            return
        end
        tween(displayScale, 0.08, { Scale = 0.97 }).Completed:Connect(function()
            if display.Parent then tween(displayScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back) end
        end)
        setOpen(not open)
    end, self.Window._connections)
    connect(UserInputService.InputBegan, function(input)
        if not open then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local point = input.Position
        local function within(object)
            local topLeft = object.AbsolutePosition
            local bottomRight = topLeft + object.AbsoluteSize
            return point.X >= topLeft.X and point.X <= bottomRight.X
                and point.Y >= topLeft.Y and point.Y <= bottomRight.Y
        end
        if not within(holder) and not (compact and within(list)) then
            setOpen(false)
        end
    end, self.Window._connections)
    if compact then
        local page = self.Tab and self.Tab.Page
        if page then
            connect(page:GetPropertyChangedSignal("CanvasPosition"), placeList, self.Window._connections)
            connect(page:GetPropertyChangedSignal("Visible"), function()
                if not page.Visible then setOpen(false) end
            end, self.Window._connections)
        end
        connect(self.Window.Root:GetPropertyChangedSignal("AbsoluteSize"), placeList, self.Window._connections)
        connect(self.Window.Pages:GetPropertyChangedSignal("Visible"), function()
            if not self.Window.Pages.Visible then setOpen(false) end
        end, self.Window._connections)
    end
    rebuild(values)
    set(options.Default, true)
    registerFlagSetter(self.Window, options.Flag, set)
    return {
        Instance = holder,
        Panel = compact and list or nil,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
            display.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
            setWidth(display, showName and 0.56 or 1, showName and -COMPACT_MARGIN or -COMPACT_MARGIN * 2)
        end,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = outputValue,
        Refresh = function(_, nextValues, keepSelection)
            if not keepSelection then selected = multi and {} or nil end
            rebuild(nextValues)
            set(selected, true)
            if open then setOpen(true) end
        end,
        SetValues = function(self, nextValues, keepSelection)
            self:Refresh(nextValues, keepSelection)
        end,
        Search = function(_, query)
            if searchBox then searchBox.Text = tostring(query or "") end
            return filterOptions(query)
        end,
        SetOpen = function(_, nextOpen) setOpen(nextOpen) end,
    }
end

function Section:AddKeybind(options)
    options = options or {}
    local holder, nameLabel = createControlBase(self, 46, options.Name or "Keybind")
    nameLabel.Size = UDim2.new(1, -124, 1, 0)
    local keyButton = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(92, 28),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        Parent = holder,
    })
    constrainText(keyButton, 8, 11)
    bindTheme(keyButton, "BackgroundColor3", "Background")
    corner(keyButton, 5)
    if self._compact == true then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(1, -(COMPACT_MARGIN * 2 + 80 + 8), 1, 0)
        keyButton.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
    end
    -- A key *name* is accepted as well as a KeyCode so a spec that came out of
    -- ExportSpec (which stores enums as strings) can go straight back into Build.
    local defaultKey = options.Default
    if type(defaultKey) == "string" then
        defaultKey = parseKeyName(defaultKey) or Enum.KeyCode.Unknown
    end
    local value = defaultKey or Enum.KeyCode.Unknown
    local mode = string.lower(tostring(options.Mode or "Press"))
    if mode ~= "press" and mode ~= "hold" and mode ~= "toggle" then mode = "press" end
    local modeSwitch = options.ModeSwitch == true and self._compact ~= true
    local modeFlag = options.ModeFlag or (options.Flag and (tostring(options.Flag) .. "_Mode") or nil)
    local blocked = {}
    for _, key in ipairs(options.Blacklist or {}) do blocked[key] = true end
    local modeLabel
    local function modeName()
        return string.upper(string.sub(mode, 1, 1)) .. string.sub(mode, 2)
    end
    if modeSwitch then
        nameLabel.Size = UDim2.new(1, -178, 1, 0)
        modeLabel = text(holder, modeName(), 10, "MutedText", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -108, 0.5, 0),
            Size = UDim2.fromOffset(52, 18),
            TextXAlignment = Enum.TextXAlignment.Right,
        })
    end
    local active = false
    local listening = false
    local ignoreNextActivation = false
    -- Declared before set()/keyName() below, which is where Default is captured.
    local mouseButtonNames = {
        [Enum.UserInputType.MouseButton1] = "Mouse 1",
        [Enum.UserInputType.MouseButton2] = "Mouse 2",
        [Enum.UserInputType.MouseButton3] = "Mouse 3",
    }
    local function isGamepadInput(kind)
        return string.sub(kind.Name, 1, 7) == "Gamepad"
    end
    local function isSupported(nextValue)
        return typeof(nextValue) == "EnumItem"
            and (nextValue.EnumType == Enum.KeyCode or mouseButtonNames[nextValue] ~= nil)
            and not blocked[nextValue]
    end
    local keyboardOnly = options.KeyboardOnly == true
    local allowMouse = not keyboardOnly and options.AllowMouse ~= false
    local cancelKey = options.CancelKey or Enum.KeyCode.Escape
    local clearKeys = options.ClearKeys
    if clearKeys == nil then
        clearKeys = { Enum.KeyCode.Backspace, Enum.KeyCode.Delete }
    elseif typeof(clearKeys) == "EnumItem" then
        clearKeys = { clearKeys }
    elseif type(clearKeys) ~= "table" then
        clearKeys = {}
    end
    local unboundText = options.UnboundText or T("Unbound")
    local captureText = options.CaptureText or T("PressAnyKey")

    local function keyName(key)
        if key == nil or key == Enum.KeyCode.Unknown then
            return unboundText
        end
        return mouseButtonNames[key] or key.Name or tostring(key)
    end
    local function set(nextValue, silent)
        if nextValue == nil or nextValue == Enum.KeyCode.Unknown then
            value = Enum.KeyCode.Unknown
        elseif isSupported(nextValue) then
            value = nextValue
        end
        keyButton.Text = keyName(value)
        commitFlag(options.Flag, value)
        if not silent then safeCall(options.Changed, value) end
    end
    local function inputMatches(input)
        if value == nil or value == Enum.KeyCode.Unknown then
            return false
        end
        if value.EnumType == Enum.KeyCode then
            return input.KeyCode == value
                and (input.UserInputType == Enum.UserInputType.Keyboard
                    or isGamepadInput(input.UserInputType))
        end
        return mouseButtonNames[value] ~= nil and input.UserInputType == value
    end
    local function stopListening()
        listening = false
        keyButton.Text = keyName(value)
        tween(keyButton, 0.15, { TextColor3 = Library.Theme.MutedText })
    end
    bindThemeState(keyButton, function()
        keyButton.TextColor3 = listening and Library.Theme.Accent or Library.Theme.MutedText
    end)
    connect(keyButton.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then
            return
        end
        if ignoreNextActivation then
            ignoreNextActivation = false
            return
        end
        listening = true
        keyButton.Text = captureText
        tween(keyButton, 0.15, { TextColor3 = Library.Theme.Accent })
    end, self.Window._connections)
    local function applyMode(nextMode)
        nextMode = string.lower(tostring(nextMode))
        if nextMode ~= "press" and nextMode ~= "hold" and nextMode ~= "toggle" then
            return false
        end
        mode = nextMode
        active = false
        if modeLabel then modeLabel.Text = modeName() end
        commitFlag(modeFlag, modeName())
        return true
    end
    if modeSwitch then
        connect(keyButton.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton2 or listening then return end
            if Library:_isObscured(self.Window, input.Position) then return end
            local order = { press = "hold", hold = "toggle", toggle = "press" }
            applyMode(order[mode])
            safeCall(options.ModeChanged, modeName())
        end, self.Window._connections)
        if modeFlag then
            registerFlagSetter(self.Window, modeFlag, function(value, silent)
                if applyMode(value) and not silent then safeCall(options.ModeChanged, modeName()) end
            end)
            Library._flagTypes[modeFlag] = "string"
            commitFlag(modeFlag, modeName())
        end
    end
    local function handleInput(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                -- Cancel first: without this Escape would silently become the
                -- binding, leaving no way out of capture.
                if cancelKey and input.KeyCode == cancelKey then
                    stopListening()
                    return
                end
                if table.find(clearKeys, input.KeyCode) then
                    listening = false
                    set(Enum.KeyCode.Unknown)
                    stopListening()
                    return
                end
                listening = false
                set(input.KeyCode)
                tween(keyButton, 0.15, { TextColor3 = Library.Theme.MutedText })
            elseif allowMouse and isGamepadInput(input.UserInputType)
                and input.KeyCode ~= Enum.KeyCode.Unknown then
                listening = false
                set(input.KeyCode)
                tween(keyButton, 0.15, { TextColor3 = Library.Theme.MutedText })
            elseif allowMouse and mouseButtonNames[input.UserInputType] then
                listening = false
                local point = input.Position
                local topLeft = keyButton.AbsolutePosition
                local bottomRight = topLeft + keyButton.AbsoluteSize
                ignoreNextActivation = input.UserInputType == Enum.UserInputType.MouseButton1
                    and point.X >= topLeft.X and point.X <= bottomRight.X
                    and point.Y >= topLeft.Y and point.Y <= bottomRight.Y
                set(input.UserInputType)
                tween(keyButton, 0.15, { TextColor3 = Library.Theme.MutedText })
            end
            return
        end
        if value == Enum.KeyCode.Unknown then return end
        local matches = inputMatches(input)
        if (not processed or options.AllowProcessed == true) and matches then
            if mode == "toggle" then
                active = not active
                safeCall(options.Callback, active, value)
            elseif mode == "hold" then
                if not active then active = true; safeCall(options.Callback, true, value) end
            else
                safeCall(options.Callback, value)
            end
        end
    end
    connect(UserInputService.InputBegan, handleInput, self.Window._connections)
    connect(UserInputService.InputEnded, function(input)
        if mode ~= "hold" or not active then return end
        if value == Enum.KeyCode.Unknown then return end
        if inputMatches(input) then
            active = false
            safeCall(options.Callback, false, value)
        end
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    local control = {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
            setWidth(keyButton, showName and 0 or 1, showName and 80 or -COMPACT_MARGIN * 2)
        end,
        -- Method form: HandleInput is called as control:HandleInput(input, processed),
        -- so the leading self has to be dropped.
        HandleInput = function(_, input, processed)
            return handleInput(input, processed)
        end,
        IsActive = function() return active end,
        IsListening = function() return listening end,
        IsBound = function() return value ~= Enum.KeyCode.Unknown end,
        Clear = function()
            listening = false
            set(Enum.KeyCode.Unknown)
            stopListening()
        end,
        StartCapture = function()
            listening = true
            keyButton.Text = captureText
            tween(keyButton, 0.15, { TextColor3 = Library.Theme.Accent })
        end,
        StopCapture = function() stopListening() end,
        SetMode = function(_, nextMode)
            return applyMode(nextMode)
        end,
        GetMode = function() return modeName() end,
    }
    control.Unbind = control.Clear
    return control
end

function Section:AddColorPicker(options)
    options = options or {}
    local holder, nameLabel = createControlBase(self, 46, options.Name or "Color")
    nameLabel.Size = UDim2.new(1, -78, 1, 0)
    local initialColor = typeof(options.Default) == "Color3" and options.Default or Color3.new(1, 1, 1)
    local compact = self._compact == true
    local preview = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(46, 28),
        BackgroundColor3 = initialColor,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = holder,
    })
    corner(preview, 5)
    stroke(preview, Color3.new(1, 1, 1), 1, 0.7)
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(1, -(COMPACT_MARGIN * 2 + 46 + 8), 1, 0)
        preview.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
    end
    local PANEL_PADDING = 10
    local panel = new("Frame", {
        -- Lives on the window root, not inside the control: the row clips its
        -- own descendants and every later row draws over it, so an in-row panel
        -- ends up cut off and half hidden behind the controls below.
        Visible = false,
        Size = UDim2.fromOffset(280, 196),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 60,
        Parent = self.Window.Root,
    })
    self._overlays = self._overlays or {}
    table.insert(self._overlays, panel)
    bindTheme(panel, "BackgroundColor3", "Surface")
    corner(panel, 6)
    stroke(panel, Library.Theme.Border, 1, 0.25, "Border")
    padding(panel, PANEL_PADDING, PANEL_PADDING, PANEL_PADDING, PANEL_PADDING)
    text(panel, options.Name or "Color", 11, "Text", {
        Size = UDim2.new(1, options.Rainbow == true and -124 or -56, 0, 20),
        Font = Enum.Font.GothamMedium,
        ZIndex = 4,
    })
    local labels = { "R", "G", "B" }
    local boxes = {}
    local value = initialColor
    local defaultColor = value
    local alpha = math.clamp(tonumber(options.DefaultAlpha) or 1, 0, 1)
    local hue, saturation, brightness = value:ToHSV()
    local open = false

    local presets = {}
    if type(options.Presets) == "table" then
        for _, candidate in ipairs(options.Presets) do
            if typeof(candidate) == "Color3" then
                presets[#presets + 1] = candidate
            end
        end
    end
    local presetColumns = math.clamp(math.floor(tonumber(options.PresetColumns) or 8), 1, 16)
    local presetSwatches = {}
    local SWATCH_SIZE = 20
    local SWATCH_GAP = 5
    local swatchRows = #presets > 0 and math.ceil(#presets / presetColumns) or 0
    local SWATCH_HEIGHT = swatchRows > 0 and (swatchRows * SWATCH_SIZE + (swatchRows - 1) * SWATCH_GAP) or 0
    -- Header (0..20), RGB labels (24..38), boxes (40..65), SV square
    -- (72..144) and the footer row below it, all inside the panel padding. The
    -- footer is laid out from the bottom edge so it can never overlap the
    -- SV square.
    local SV_TOP = 72
    local SV_HEIGHT = 72
    local FOOTER_HEIGHT = 24
    local FOOTER_GAP = 8
    local SWATCH_TOP = SV_TOP + SV_HEIGHT + 8
    local PANEL_HEIGHT = PANEL_PADDING * 2 + SV_TOP + SV_HEIGHT
        + (SWATCH_HEIGHT > 0 and (8 + SWATCH_HEIGHT) or 0) + FOOTER_GAP + FOOTER_HEIGHT
    local function placePanel()
        if not open then return end
        local rootFrame = self.Window.Root
        local rootSize = rootFrame.AbsoluteSize
        if rootSize.X <= 0 or rootSize.Y <= 0 then return end
        local origin = holder.AbsolutePosition - rootFrame.AbsolutePosition
        local width, x
        if compact then
            width = math.clamp(240, 200, math.max(200, rootSize.X - 12))
            x = preview.AbsolutePosition.X + preview.AbsoluteSize.X - rootFrame.AbsolutePosition.X - width
        else
            width = math.clamp(holder.AbsoluteSize.X - 24, 220, math.max(220, rootSize.X - 12))
            x = origin.X + 12
        end
        local y = origin.Y + holder.AbsoluteSize.Y + 4
        -- Flip above the control when the row sits too low in the page.
        if y + PANEL_HEIGHT > rootSize.Y - 6 then
            y = origin.Y - PANEL_HEIGHT - 4
        end
        panel.Size = UDim2.fromOffset(width, PANEL_HEIGHT)
        panel.Position = UDim2.fromOffset(
            math.clamp(x, 6, math.max(6, rootSize.X - width - 6)),
            math.clamp(y, 6, math.max(6, rootSize.Y - PANEL_HEIGHT - 6))
        )
    end

    local function setOpen(nextOpen)
        open = not not nextOpen
        panel.Visible = open
        if open then placePanel() end
    end
    -- Stay anchored to the row while the page scrolls or the window resizes.
    -- Pages is a plain Frame; the ScrollingFrame that moves is the tab's page.
    local page = self.Tab and self.Tab.Page
    if page then
        connect(page:GetPropertyChangedSignal("CanvasPosition"), placePanel, self.Window._connections)
        connect(page:GetPropertyChangedSignal("Visible"), function()
            if not page.Visible then setOpen(false) end
        end, self.Window._connections)
    end
    connect(self.Window.Root:GetPropertyChangedSignal("AbsoluteSize"), placePanel, self.Window._connections)
    connect(self.Window.Pages:GetPropertyChangedSignal("Visible"), function()
        if not self.Window.Pages.Visible then setOpen(false) end
    end, self.Window._connections)
    -- Clicking anywhere outside the panel and its preview closes the picker.
    connect(UserInputService.InputBegan, function(input)
        if not open then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local point = input.Position
        local function inside(object)
            if not object or not object.Visible then return false end
            local ok, pos, size = pcall(function()
                return object.AbsolutePosition, object.AbsoluteSize
            end)
            if not ok or not pos or not size then return false end
            return point.X >= pos.X and point.Y >= pos.Y
                and point.X <= pos.X + size.X and point.Y <= pos.Y + size.Y
        end
        if not inside(panel) and not inside(preview) and not inside(holder) then
            setOpen(false)
        end
    end, self.Window._connections)

    -- Forward declaration: set() below writes the hex readout, and it is defined
    -- before the label exists.
    local hexLabel
    local svGradient
    local stopRainbow
    local closePicker = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(48, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = T("Close"),
        TextColor3 = Library.Theme.MutedText,
        TextSize = 10,
        ZIndex = 5,
        Parent = panel,
    })
    constrainText(closePicker, 8, 10)
    bindTheme(closePicker, "TextColor3", "MutedText")

    local function set(nextValue, silent, keepHSV)
        if typeof(nextValue) ~= "Color3" then return end
        value = nextValue
        if not keepHSV then
            local h, s, v = value:ToHSV()
            if s > 0 and v > 0 then
                hue = h
            end
            saturation, brightness = s, v
        end
        preview.BackgroundColor3 = value
        if svGradient then
            svGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
        end
        local rgb = {
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5),
        }
        for index, box in ipairs(boxes) do box.Text = tostring(rgb[index]) end
        -- Read-only hex readout (was an editable TextBox, which duplicated the
        -- R/G/B fields and had no room in the footer).
        hexLabel.Text = string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3])
        commitFlag(options.Flag, value)
        if not silent then safeCall(options.Callback, value, alpha) end
    end
    for index, channel in ipairs(labels) do
        text(panel, channel, 11, "MutedText", {
            Position = UDim2.new((index - 1) / 3, (index - 1) * 5 / 3, 0, 24),
            Size = UDim2.new(1 / 3, -10 / 3, 0, 14),
            ZIndex = 4,
        })
        local box = new("TextBox", {
            Position = UDim2.new((index - 1) / 3, (index - 1) * 5 / 3, 0, 40),
            Size = UDim2.new(1 / 3, -10 / 3, 0, 25),
            BackgroundColor3 = Library.Theme.SurfaceAlt,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextColor3 = Library.Theme.Text,
            TextSize = 11,
            ZIndex = 4,
            Parent = panel,
        })
        constrainText(box, 8, 11)
        bindTheme(box, "BackgroundColor3", "SurfaceAlt")
        bindTheme(box, "TextColor3", "Text")
        corner(box, 4)
        boxes[index] = box
        connect(box.FocusLost, function()
            stopRainbow()
            local rgb = {}
            for i, input in ipairs(boxes) do
                rgb[i] = math.clamp(tonumber(input.Text) or 0, 0, 255)
            end
            set(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
        end, self.Window._connections)
    end
    local sv = new("TextButton", {
        Position = UDim2.fromOffset(0, SV_TOP),
        Size = UDim2.new(1, -42, 0, SV_HEIGHT),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = panel,
    })
    corner(sv, 4)
    svGradient = new("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1)),
        Transparency = NumberSequence.new(0),
        Parent = sv,
    })
    local dark = new("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = sv,
    })
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90, Parent = dark,
    })
    corner(dark, 4)
    local hueBar = new("TextButton", {
        Position = UDim2.new(1, -32, 0, SV_TOP), Size = UDim2.fromOffset(32, SV_HEIGHT),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        Text = "", AutoButtonColor = false, ZIndex = 4, Parent = panel,
    })
    new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
            ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
            ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
            ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
            ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
            ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
        }),
        Rotation = 90, Parent = hueBar,
    })
    corner(hueBar, 4)
    local function inputHSV(target, input)
        local relative = Vector2.new(input.Position.X, input.Position.Y) - target.AbsolutePosition
        if target == hueBar then
            hue = math.clamp(relative.Y / math.max(1, target.AbsoluteSize.Y), 0, 1)
        else
            saturation = math.clamp(relative.X / math.max(1, target.AbsoluteSize.X), 0, 1)
            brightness = 1 - math.clamp(relative.Y / math.max(1, target.AbsoluteSize.Y), 0, 1)
        end
        set(Color3.fromHSV(hue, saturation, brightness), nil, true)
    end
    local hsvDragTarget
    connect(sv.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if Library:_isObscured(self.Window, input.Position) then
                return
            end
            stopRainbow()
            hsvDragTarget = sv; inputHSV(sv, input)
        end
    end, self.Window._connections)
    connect(hueBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if Library:_isObscured(self.Window, input.Position) then
                return
            end
            stopRainbow()
            hsvDragTarget = hueBar; inputHSV(hueBar, input)
        end
    end, self.Window._connections)
    connect(UserInputService.InputChanged, function(input)
        if hsvDragTarget and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            inputHSV(hsvDragTarget, input)
        end
    end, self.Window._connections)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then hsvDragTarget = nil end
    end, self.Window._connections)
    -- Footer row: hex readout + optional alpha on the left, Reset on the right.
    -- Anchored to the bottom edge so it always sits below the SV square
    -- instead of on top of the colour area.
    local footerY = FOOTER_HEIGHT / 2
    hexLabel = new("TextBox", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 1, -footerY),
        Size = UDim2.fromOffset(84, FOOTER_HEIGHT),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Code,
        Text = "",
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
        Parent = panel,
    })
    bindTheme(hexLabel, "TextColor3", "MutedText")
    bindTheme(hexLabel, "BackgroundColor3", "SurfaceAlt")
    corner(hexLabel, 4)
    padding(hexLabel, 0, 4, 0, 4)
    connect(hexLabel.Focused, function()
        hexLabel.BackgroundTransparency = 0
        hexLabel.TextColor3 = Library.Theme.Text
    end, self.Window._connections)
    connect(hexLabel.FocusLost, function()
        hexLabel.BackgroundTransparency = 1
        hexLabel.TextColor3 = Library.Theme.MutedText
        local parsed = parseHexColor(hexLabel.Text)
        stopRainbow()
        if parsed then
            set(parsed)
        else
            set(value, true, true)
        end
    end, self.Window._connections)
    for index, preset in ipairs(presets) do
        local column = (index - 1) % presetColumns
        local row = math.floor((index - 1) / presetColumns)
        local swatch = new("TextButton", {
            Position = UDim2.fromOffset(column * (SWATCH_SIZE + SWATCH_GAP), SWATCH_TOP + row * (SWATCH_SIZE + SWATCH_GAP)),
            Size = UDim2.fromOffset(SWATCH_SIZE, SWATCH_SIZE),
            BackgroundColor3 = preset,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 4,
            Parent = panel,
        })
        corner(swatch, 4)
        local swatchStroke = stroke(swatch, Color3.new(1, 1, 1), 1, 0.8)
        connect(swatch.MouseEnter, function()
            tween(swatchStroke, 0.12, { Transparency = 0.2 })
        end, self.Window._connections)
        connect(swatch.MouseLeave, function()
            tween(swatchStroke, 0.12, { Transparency = 0.8 })
        end, self.Window._connections)
        connect(swatch.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            stopRainbow()
            set(preset)
        end, self.Window._connections)
        presetSwatches[index] = swatch
    end
    local alphaBox
    if options.Alpha == true then
        alphaBox = new("TextBox", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -80, 1, -footerY), Size = UDim2.fromOffset(64, FOOTER_HEIGHT),
            BackgroundColor3 = Library.Theme.SurfaceAlt, BorderSizePixel = 0,
            ClearTextOnFocus = false, Font = Enum.Font.Code, TextColor3 = Library.Theme.Text,
            Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%", PlaceholderText = "Alpha",
            TextSize = 10, ZIndex = 5, Parent = panel,
        })
        corner(alphaBox, 4)
        bindTheme(alphaBox, "BackgroundColor3", "SurfaceAlt")
        bindTheme(alphaBox, "TextColor3", "Text")
        connect(alphaBox.FocusLost, function()
            alpha = math.clamp((tonumber((string.gsub(alphaBox.Text, "%%", ""))) or (alpha * 100)) / 100, 0, 1)
            alphaBox.Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%"
            safeCall(options.Callback, value, alpha)
        end, self.Window._connections)
    end
    local reset
    local control_Reset
    if options.ResetButton ~= false then
        reset = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 1, -footerY), Size = UDim2.fromOffset(72, FOOTER_HEIGHT),
            BackgroundColor3 = Library.Theme.SurfaceAlt, BorderSizePixel = 0,
            Text = options.ResetText or T("Reset"), TextColor3 = Library.Theme.MutedText,
            Font = Enum.Font.GothamMedium,
            TextSize = 10, ZIndex = 4, Parent = panel,
        })
        corner(reset, 4)
        bindTheme(reset, "BackgroundColor3", "SurfaceAlt")
        bindTheme(reset, "TextColor3", "MutedText")
        connect(reset.MouseEnter, function()
            tween(reset, 0.12, { TextColor3 = Library.Theme.Error })
        end, self.Window._connections)
        connect(reset.MouseLeave, function()
            tween(reset, 0.12, { TextColor3 = Library.Theme.MutedText })
        end, self.Window._connections)
        connect(reset.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            stopRainbow()
            set(defaultColor)
        end, self.Window._connections)
        control_Reset = reset
    end
    connect(preview.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then
            return
        end
        setOpen(not open)
    end, self.Window._connections)
    connect(closePicker.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then
            return
        end
        setOpen(false)
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    panel.Size = UDim2.fromOffset(panel.Size.X.Offset, PANEL_HEIGHT)
    local rainbowOn = false
    local rainbowChip
    local rainbowConnection
    local rainbowFlag = options.RainbowFlag or (options.Flag and (tostring(options.Flag) .. "_Rainbow") or nil)
    local rainbowSpeed = math.clamp(tonumber(options.RainbowSpeed) or 0.2, 0.01, 4)
    local rainbowSaturation = math.clamp(tonumber(options.RainbowSaturation) or 0.85, 0, 1)
    local rainbowBrightness = math.clamp(tonumber(options.RainbowBrightness) or 1, 0, 1)
    local rainbowInterval = 1 / math.clamp(tonumber(options.RainbowRate) or 20, 2, 60)
    local function paintRainbow()
        if not rainbowChip then return end
        rainbowChip.TextColor3 = rainbowOn and Library.Theme.Accent or Library.Theme.MutedText
        rainbowChip.BackgroundTransparency = rainbowOn and 0.55 or 1
    end
    stopRainbow = function()
        if not rainbowOn then return end
        rainbowOn = false
        if rainbowConnection then
            rainbowConnection:Disconnect()
            rainbowConnection = nil
        end
        paintRainbow()
        commitFlag(rainbowFlag, false)
        safeCall(options.RainbowChanged, false)
    end
    local function startRainbow()
        if rainbowOn then return end
        rainbowOn = true
        local elapsed = 0
        rainbowConnection = RunService.Heartbeat:Connect(function(delta)
            elapsed += delta
            if elapsed < rainbowInterval then return end
            hue = (hue + elapsed * rainbowSpeed) % 1
            elapsed = 0
            saturation, brightness = rainbowSaturation, rainbowBrightness
            set(Color3.fromHSV(hue, saturation, brightness), nil, true)
        end)
        table.insert(self.Window._connections, rainbowConnection)
        paintRainbow()
        commitFlag(rainbowFlag, true)
        safeCall(options.RainbowChanged, true)
    end
    connect(holder.Destroying, function()
        if rainbowConnection then
            rainbowConnection:Disconnect()
            rainbowConnection = nil
        end
        rainbowOn = false
    end, self.Window._connections)
    if options.Rainbow == true then
        rainbowChip = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -52, 0, 1),
            Size = UDim2.fromOffset(64, 18),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = T("Rainbow"),
            TextSize = 10,
            ZIndex = 5,
            Parent = panel,
        })
        bindTheme(rainbowChip, "BackgroundColor3", "Accent")
        constrainText(rainbowChip, 8, 10)
        corner(rainbowChip, 5)
        bindThemeState(rainbowChip, paintRainbow)
        connect(rainbowChip.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            if rainbowOn then stopRainbow() else startRainbow() end
        end, self.Window._connections)
    end
    if rainbowFlag then
        registerFlagSetter(self.Window, rainbowFlag, function(enabled, silent)
            if enabled then startRainbow() else stopRainbow() end
        end)
        Library._flagTypes[rainbowFlag] = "boolean"
        commitFlag(rainbowFlag, rainbowOn)
    end
    if options.RainbowEnabled == true then startRainbow() end
    local control = {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        CompactLayout = function(_, showName, available)
            if available then showName = available >= 100 end
            nameLabel.Visible = showName
            setWidth(preview, showName and 0 or 1, showName and 46 or -COMPACT_MARGIN * 2)
        end,
        GetHSV = function() return hue, saturation, brightness end,
        SetHSV = function(_, h, s, v, silent)
            hue = math.clamp(h, 0, 1)
            saturation = math.clamp(s, 0, 1)
            brightness = math.clamp(v, 0, 1)
            set(Color3.fromHSV(hue, saturation, brightness), silent, true)
        end,
        GetAlpha = function() return alpha end,
        SetAlpha = function(_, nextAlpha, silent)
            alpha = math.clamp(tonumber(nextAlpha) or alpha, 0, 1)
            if alphaBox then alphaBox.Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%" end
            if not silent then safeCall(options.Callback, value, alpha) end
        end,
        GetDefault = function() return defaultColor end,
        Reset = function() set(defaultColor) end,
        IsOpen = function() return open end,
        SetOpen = function(_, nextOpen) setOpen(nextOpen) end,
        SetRainbow = function(_, enabled)
            if enabled then startRainbow() else stopRainbow() end
        end,
        IsRainbow = function() return rainbowOn end,
        Presets = presets,
        PresetColumns = presetColumns,
        Swatches = presetSwatches,
        Panel = panel,
        -- The Reset button instance, under a distinct name: Reset itself is the
        -- method that restores the default colour.
        ResetButton = control_Reset,
        GetPresets = function()
            return presets
        end,
    }
    -- Set here rather than in the literal above: a closure written inside a table
    -- constructor cannot see the local being constructed on this Luau build, so
    -- `return control` from inside the literal would come back nil.
    control.SetDefault = function(self, nextDefault)
        if typeof(nextDefault) == "Color3" then defaultColor = nextDefault end
        return self
    end
    -- Same code path a swatch click runs, so a script can drive the palette from a
    -- hotkey or a randomiser without reaching into the panel.
    control.SetPreset = function(self, index)
        local color = presets[index]
        if typeof(color) == "Color3" then set(color) end
        return self
    end
    return control
end

function Section:AddDivider(options)
    options = type(options) == "table" and options or { Text = options }
    local holder = new("Frame", {
        Name = options.Text or "Divider",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, options.Text and 28 or 17),
        Parent = self.Container,
    })
    local function addLine(anchorX, width)
        local line = new("Frame", {
            AnchorPoint = Vector2.new(anchorX, 0.5),
            Position = UDim2.new(anchorX, 0, 0.5, 0),
            Size = width,
            BorderSizePixel = 0,
            Parent = holder,
        })
        bindTheme(line, "BackgroundColor3", "Border")
        return line
    end
    if options.Text then
        local caption = tostring(options.Text)
        local captionWidth = math.ceil(measureText(caption, 10, Library.Theme.Font or Enum.Font.Gotham, 1000).X) + 2
        local side = UDim2.new(0.5, -(captionWidth / 2 + 10), 0, 1)
        addLine(0, side)
        addLine(1, side)
        text(holder, caption, 10, "MutedText", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(captionWidth, 20),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    else
        addLine(0, UDim2.new(1, 0, 0, 1))
    end
    return { Instance = holder }
end

function Section:AddNumberInput(options)
    options = options or {}
    local minimum = tonumber(options.Min) or -math.huge
    local maximum = tonumber(options.Max) or math.huge
    if minimum > maximum then minimum, maximum = maximum, minimum end
    local increment = math.abs(tonumber(options.Increment) or 1)
    if increment == 0 or increment ~= increment then increment = 1 end
    local prefix = options.Prefix
    local suffix = options.Suffix
    local callback = options.Callback
    local minimumScaled = math.floor(minimum / increment + 0.5) * increment
    local maximumScaled = math.floor(maximum / increment + 0.5) * increment
    local function normalize(raw)
        local number = tonumber(raw)
        if not number or number ~= number then return nil end
        if number == math.huge or number == -math.huge then return nil end
        if minimum == -math.huge then number = math.max(number, -1e15) end
        if maximum == math.huge then number = math.min(number, 1e15) end
        return math.clamp(math.floor(number / increment + 0.5) * increment, minimumScaled, maximumScaled)
    end
    local function snap(number)
        local snapped = math.floor(number / increment + 0.5) * increment
        snapped = tonumber(string.format("%.14g", snapped)) or snapped
        return math.clamp(snapped, minimum, maximum)
    end
    local mapped = copyTable(options)
    mapped.Numeric = true
    mapped.Normalize = snap
    mapped.Default = normalize(options.Default) or 0
    mapped.Callback = function(raw, enterPressed)
        local number = tonumber(raw)
        if not number or number ~= number then return end
        safeCall(callback, snap(number), enterPressed)
    end
    local input = self:AddInput(mapped)
    local originalSet = input.Set
    function input:Set(value, silent)
        local number = tonumber(value)
        if not number or number ~= number or number == math.huge or number == -math.huge then
            -- Revert-on-invalid: anything unparseable puts the last good value
            -- back in the box instead of leaving the bad text on screen.
            originalSet(self, tostring(input:Get() or 0), true)
            return self
        end
        originalSet(self, tostring(snap(number)), silent)
        return self
    end
    local originalGet = input.Get
    function input:Get()
        return tonumber(originalGet(self))
    end
    local box = input.Instance and input.Instance:FindFirstChildWhichIsA("TextBox")
    if box then
        -- A number needs its affixes visible but must not have them typed into
        -- the box, so they live in their own label beside it.
        local stepper = options.Stepper == true and self._compact ~= true
        if stepper then
            box.AnchorPoint = Vector2.new(0, 0.5)
            box.Position = UDim2.new(0.48, 16, 0.5, 0)
            box.Size = UDim2.new(0.52, -56, 0, 28)
            local function stepButton(symbol, anchorX, position)
                local button = new("TextButton", {
                    AnchorPoint = Vector2.new(anchorX, 0.5),
                    Position = position,
                    Size = UDim2.fromOffset(24, 28),
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Font = Enum.Font.GothamMedium,
                    Text = symbol,
                    TextSize = 14,
                    ZIndex = 3,
                    Parent = input.Instance,
                })
                bindTheme(button, "BackgroundColor3", "Background")
                bindTheme(button, "TextColor3", "MutedText")
                corner(button, 5)
                connect(button.MouseEnter, function()
                    tween(button, 0.12, { TextColor3 = Library.Theme.Text })
                end, self.Window._connections)
                connect(button.MouseLeave, function()
                    tween(button, 0.12, { TextColor3 = Library.Theme.MutedText })
                end, self.Window._connections)
                return button
            end
            local function attach(button, direction)
                local token = 0
                local function stepOnce()
                    input:Set((tonumber(input:Get()) or 0) + direction * increment)
                end
                connect(button.InputBegan, function(pointer)
                    if pointer.UserInputType ~= Enum.UserInputType.MouseButton1
                        and pointer.UserInputType ~= Enum.UserInputType.Touch then
                        return
                    end
                    if Library:_isObscured(self.Window, pointer.Position) then return end
                    token += 1
                    local mine = token
                    stepOnce()
                    task.delay(0.4, function()
                        local function repeatStep()
                            if token ~= mine then return end
                            stepOnce()
                            task.delay(0.06, repeatStep)
                        end
                        repeatStep()
                    end)
                end, self.Window._connections)
                connect(UserInputService.InputEnded, function(pointer)
                    if pointer.UserInputType == Enum.UserInputType.MouseButton1
                        or pointer.UserInputType == Enum.UserInputType.Touch then
                        token += 1
                    end
                end, self.Window._connections)
                connect(button.MouseLeave, function()
                    token += 1
                end, self.Window._connections)
            end
            attach(stepButton("-", 0, UDim2.new(0.48, -12, 0.5, 0)), -1)
            attach(stepButton("+", 1, UDim2.new(1, -12, 0.5, 0)), 1)
        end
        if (prefix or suffix) and not stepper then
            local compact = self._compact == true
            local affix = text(input.Instance, "", 11, "MutedText", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, compact and -COMPACT_MARGIN or -12, 0.5, 0),
                Size = compact and UDim2.new(0, 56, 1, 0) or UDim2.fromOffset(76, 26),
                TextXAlignment = Enum.TextXAlignment.Right,
            })
            if compact then
                affix:SetAttribute("BloodshotKeep", true)
                local nameLabel = input.Instance:FindFirstChildWhichIsA("TextLabel")
                nameLabel.Size = UDim2.new(0.3, -COMPACT_MARGIN, 1, 0)
                box.Position = UDim2.new(1, -(COMPACT_MARGIN + 62), 0.5, 0)
                input.CompactLayout = function(_, showName)
                    nameLabel.Visible = showName
                    setWidth(box, showName and 0.68 or 1, -(showName and COMPACT_MARGIN + 62 or COMPACT_MARGIN * 2 + 62))
                end
            else
                box.Position = UDim2.new(1, -94, 0.5, 0)
                box.Size = UDim2.fromOffset(84, 28)
            end
            local adorn = function()
                affix.Text = tostring(prefix or "") .. (box.Text or "") .. tostring(suffix or "")
            end
            adorn()
            connect(box:GetPropertyChangedSignal("Text"), adorn, self.Window._connections)
            connect(box.Focused, function() affix.TextTransparency = 0.6 end, self.Window._connections)
            connect(box.FocusLost, function() affix.TextTransparency = 0 end, self.Window._connections)
        end
    end
    input:Set(tonumber(options.Default) or 0, true)
    return input
end

function Section:AddRadio(options)
    options = options or {}
    local mapped = copyTable(options)
    mapped.Multi = false
    return self:AddDropdown(mapped)
end

function Section:AddSegmented(options)
    options = options or {}
    local values = type(options.Values) == "table" and options.Values or {}
    local compact = self._compact == true
    local holder, nameLabel = createControlBase(self, options.Description and 78 or 66, options.Name or "Segmented", options.Description)
    if options.Description then
        nameLabel.Size = UDim2.new(1, -24, 0, 18)
    else
        nameLabel.Position = UDim2.fromOffset(12, 7)
        nameLabel.Size = UDim2.new(1, -24, 0, 20)
    end
    local row = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 1, -32),
        Size = UDim2.new(1, -24, 0, 24),
        Parent = holder,
    })
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.36, -COMPACT_MARGIN, 1, 0)
        row.AnchorPoint = Vector2.new(1, 0)
        row.Position = UDim2.new(1, -COMPACT_MARGIN, 0, 0)
    end
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = row,
    })
    local value = options.Default or values[1]
    local buttons = {}
    local disabled = false
    local function render()
        for item, button in pairs(buttons) do
            button.BackgroundColor3 = Library.Theme.Accent
            button.BackgroundTransparency = item == value and 0.05 or 0.72
            button.TextColor3 = item == value and Library.Theme.Text or Library.Theme.MutedText
        end
    end
    local function set(nextValue, silent)
        if not table.find(values, nextValue) then return end
        value = nextValue
        commitFlag(options.Flag, value)
        render()
        if not silent then safeCall(options.Callback, value) end
    end
    local segmentCount = math.max(1, #values)
    for _, item in ipairs(values) do
        local button = new("TextButton", {
            BackgroundColor3 = Library.Theme.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(1 / segmentCount, -5 * (segmentCount - 1) / segmentCount, 1, 0),
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = tostring(item),
            TextSize = 10,
            Parent = row,
        })
        constrainText(button, 7, 10)
        corner(button, 5)
        buttons[item] = button
        connect(button.Activated, function(input) if not disabled then if Library:_isObscured(self.Window, input and input.Position) then return end set(item) end end, self.Window._connections)
    end
    bindThemeState(holder, render)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
            setWidth(row, showName and 0.64 or 1, showName and -COMPACT_MARGIN or -COMPACT_MARGIN * 2)
        end,
        SetDisabled = function(_, nextDisabled)
            disabled = not not nextDisabled
            for _, button in pairs(buttons) do button.Active = not disabled end
        end,
    }
end

-- Single-line form of the range slider for AddRow: one track, two knobs.
local function buildCompactRange(section, options, minimum, maximum, default)
    local increment = tonumber(options.Increment) or 1
    if increment ~= increment or increment <= 0 then increment = 1 end
    if maximum <= minimum then maximum = minimum + 1 end
    local decimals = math.max(0, #(tostring(increment):match("%.(%d+)") or ""))
    local holder, nameLabel = createControlBase(section, 34, options.Name or "RangeSlider")
    nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
    nameLabel.Size = UDim2.new(0.3, -COMPACT_MARGIN, 1, 0)
    local valueLabel = text(holder, "", 11, "MutedText", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0),
        Size = UDim2.new(0, 72, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    valueLabel:SetAttribute("BloodshotKeep", true)
    local track = new("Frame", {
        Position = UDim2.new(0.34, 0, 0, 14),
        Size = UDim2.new(0.66, -(COMPACT_MARGIN + 84), 0, 5),
        BorderSizePixel = 0,
        Parent = holder,
    })
    bindTheme(track, "BackgroundColor3", "Border")
    corner(track, 999)
    local fill = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        Parent = track,
    })
    bindTheme(fill, "BackgroundColor3", "Accent")
    gradient(fill, "Accent", "AccentGradient", 0)
    corner(fill, 999)
    local function makeKnob()
        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(12, 12),
            BorderSizePixel = 0,
            Parent = track,
        })
        bindTheme(knob, "BackgroundColor3", "Text")
        corner(knob, 999)
        return knob
    end
    local lowKnob, highKnob = makeKnob(), makeKnob()
    local hitbox = new("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, -8),
        Size = UDim2.new(1, 0, 1, 16),
        Text = "",
        ZIndex = 5,
        Parent = track,
    })

    local lowValue, highValue = minimum, maximum
    local function snap(number)
        local snapped = math.floor(number / increment + 0.5) * increment
        snapped = tonumber(string.format("%." .. decimals .. "f", snapped)) or snapped
        return math.clamp(snapped, minimum, maximum)
    end
    local function format(number)
        return string.format("%." .. decimals .. "f", number)
    end
    local function render()
        local first = (lowValue - minimum) / (maximum - minimum)
        local second = (highValue - minimum) / (maximum - minimum)
        fill.Position = UDim2.fromScale(first, 0)
        fill.Size = UDim2.fromScale(second - first, 1)
        lowKnob.Position = UDim2.fromScale(first, 0.5)
        highKnob.Position = UDim2.fromScale(second, 0.5)
        valueLabel.Text = (options.Prefix or "") .. format(lowValue) .. " - " .. format(highValue) .. (options.Suffix or "")
    end
    local function publish(silent)
        local result = { lowValue, highValue }
        commitFlag(options.Flag, result)
        if not silent then safeCall(options.Callback, lowValue, highValue, result) end
    end
    local function set(nextValue, silent)
        if type(nextValue) ~= "table" then return end
        local first = snap(tonumber(nextValue[1]) or minimum)
        local second = snap(tonumber(nextValue[2]) or maximum)
        if first > second then first, second = second, first end
        lowValue, highValue = first, second
        render()
        publish(silent)
    end

    local dragging
    local function valueAt(input)
        local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        return snap(minimum + (maximum - minimum) * ratio)
    end
    local function drag(input)
        local target = valueAt(input)
        if dragging == "low" then
            lowValue = math.min(target, highValue)
        else
            highValue = math.max(target, lowValue)
        end
        render()
        publish(false)
    end
    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if Library:_isObscured(section.Window, input.Position) then
                return
            end
            local target = valueAt(input)
            if math.abs(target - lowValue) < math.abs(target - highValue) or (target <= lowValue and lowValue == highValue) then
                dragging = "low"
            else
                dragging = "high"
            end
            drag(input)
        end
    end, section.Window._connections)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            drag(input)
        end
    end, section.Window._connections)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = nil
        end
    end, section.Window._connections)
    registerFlagSetter(section.Window, options.Flag, set)
    set(default, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return { lowValue, highValue } end,
        CompactLayout = function(_, showName, available)
            nameLabel.Visible = showName
            local valueWidth = available and math.clamp(math.floor(available * 0.5), 40, 72) or 72
            valueLabel.Size = UDim2.new(0, valueWidth, 1, 0)
            local reserve = valueWidth + 12
            track.Position = showName and UDim2.new(0.34, 0, 0.5, 0) or UDim2.new(0, COMPACT_MARGIN, 0.5, 0)
            setWidth(track, showName and 0.66 or 1, -(showName and COMPACT_MARGIN + reserve or COMPACT_MARGIN * 2 + reserve))
        end,
    }
end

function Section:AddRangeSlider(options)
    options = options or {}
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    local default = type(options.Default) == "table" and options.Default or { minimum, maximum }
    if self._compact == true then
        return buildCompactRange(self, options, minimum, maximum, default)
    end
    local holder = new("Frame", {
        Name = options.Name or "RangeSlider",
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        Parent = self.Container,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, self.Window._layout.ControlSpacing),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = holder,
    })
    -- The two sliders are children of the holder, not of the section, but they still
    -- go through the enriched Section.Add* wrapper, which needs the same fields a
    -- real section has.
    local nested = { Container = holder, Window = self.Window, Tab = self.Tab, Controls = {} }
    local low, high
    local function publish(silent)
        local result = { low:Get(), high:Get() }
        commitFlag(options.Flag, result)
        if not silent then safeCall(options.Callback, result[1], result[2], result) end
    end
    local base = {
        Min = minimum, Max = maximum, Increment = options.Increment, Suffix = options.Suffix,
    }
    low = Section.AddSlider(nested, {
        Name = (options.Name or "Range") .. " minimum",
        Min = base.Min, Max = base.Max, Increment = base.Increment, Suffix = base.Suffix,
        Default = default[1] or minimum,
        Callback = function(value)
            if high and value > high:Get() then high:Set(value, true) end
            publish(false)
        end,
    })
    high = Section.AddSlider(nested, {
        Name = (options.Name or "Range") .. " maximum",
        Min = base.Min, Max = base.Max, Increment = base.Increment, Suffix = base.Suffix,
        Default = default[2] or maximum,
        Callback = function(value)
            if low and value < low:Get() then low:Set(value, true) end
            publish(false)
        end,
    })
    -- The nested container also sorts by LayoutOrder, so pin low above high
    -- instead of letting "maximum" sort before "minimum".
    low.Instance.LayoutOrder = 1
    high.Instance.LayoutOrder = 2
    local function set(nextValue, silent)
        if type(nextValue) ~= "table" then return end
        local a = math.clamp(tonumber(nextValue[1]) or minimum, minimum, maximum)
        local b = math.clamp(tonumber(nextValue[2]) or maximum, minimum, maximum)
        if a > b then a, b = b, a end
        low:Set(a, true); high:Set(b, true); publish(silent)
    end
    registerFlagSetter(self.Window, options.Flag, set)
    set(default, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return { low:Get(), high:Get() } end,
        SetDisabled = function(_, disabled) low:SetDisabled(disabled); high:SetDisabled(disabled) end,
    }
end

-- Shared v2 control contract. Wrapping the original constructors keeps every v1
-- return value and behavior intact while making lifecycle methods consistent.
local function iconAsset(value)
    if type(value) == "number" then return "rbxassetid://" .. value end
    value = tostring(value)
    if value:match("^%d+$") then return "rbxassetid://" .. value end
    if value:match("^rbxassetid://") or value:match("^rbxasset://") or value:match("^https?://") then return value end
    return nil
end

local function enrichControl(control, section, options, ownedConnections, methodName)
    if type(control) ~= "table" or not control.Instance then return control end
    options = type(options) == "table" and options or {}
    if control._owned then
        -- Composite controls (NumberInput -> Input, Radio -> Dropdown) come
        -- through here twice for one control table: the inner pass installed
        -- everything, so the outer pass only relabels it and takes over the
        -- connections it created.
        control.Type = methodName or control.Type
        control.Spec = copyTable(options)
        control.Spec.Type = control.Type
        for _, connection in ipairs(ownedConnections or {}) do
            table.insert(control._owned, connection)
        end
        return control
    end
    local instance = control.Instance
    local destroyed = false
    local flag = options.Flag
    local setter = flag and section.Window._flagSetters[flag]
    control._owned = ownedConnections or {}
    -- Remembered so ExportSpec can rebuild a spec table from a live window.
    -- AddRow children go through the same enriched Add* wrappers, so they land
    -- here like every other control.
    control.Type = methodName or control.Type
    control.Flag = flag
    control.Spec = copyTable(options or control.Spec)
    control.Spec.Type = control.Type
    control._window = section.Window
    table.insert(Library._specControls, control)
    if type(control.Get) == "function" and type(control.Set) == "function" and control.Reset == nil then
        local ok, initial = pcall(control.Get, control)
        if ok and initial ~= nil then
            local snapshot = copyTable(initial)
            control._default = snapshot
            function control:Reset(silent)
                if destroyed then return self end
                self:Set(copyTable(snapshot), silent)
                return self
            end
        end
    end
    local function restingTransparency()
        if instance:GetAttribute("BloodshotCompact") == true and instance:GetAttribute("BloodshotRow") ~= true then
            return 1
        end
        return Library.Theme.ControlTransparency or 0.8
    end
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            descendant.Selectable = Library._gamepadEnabled ~= false
            connect(descendant.SelectionGained, function()
                if instance and instance.Parent then tween(instance, 0.12, { BackgroundTransparency = 0.58 }) end
            end, section.Window._connections)
            connect(descendant.SelectionLost, function()
                if instance and instance.Parent then tween(instance, 0.12, { BackgroundTransparency = restingTransparency() }) end
            end, section.Window._connections)
        end
    end
    for _, methodName in ipairs({ "Set", "Get", "Fire", "Refresh", "SetValues", "Search", "SetOpen" }) do
        local original = control[methodName]
        if type(original) == "function" then
            control[methodName] = function(self, ...)
                if destroyed then return nil end
                if self.Disabled and (methodName == "Fire" or methodName == "SetOpen") then return nil end
                return original(self, ...)
            end
        end
    end

    if options.Tooltip and instance:IsA("GuiObject") then
        local tooltip
        local function hideTooltip()
            if tooltip then tooltip:Destroy(); tooltip = nil end
        end
        connect(instance.Destroying, hideTooltip, section.Window._connections)
        connect(instance.MouseEnter, function()
            if destroyed or tooltip then return end
            local content = tostring(options.Tooltip)
            local bounds = measureText(content, 11, Enum.Font.Gotham, 162)
            local width = math.clamp(math.ceil(bounds.X) + 20, 60, 180)
            local height = math.ceil(bounds.Y) + 14
            tooltip = new("TextLabel", {
                Name = "Tooltip",
                BackgroundColor3 = Library.Theme.Surface,
                BackgroundTransparency = 0.02,
                BorderSizePixel = 0,
                AutomaticSize = Enum.AutomaticSize.Y,
                Text = content,
                TextColor3 = Library.Theme.Text,
                TextSize = 11,
                Font = Enum.Font.Gotham,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                Size = UDim2.fromOffset(width, 0),
                ZIndex = 200,
                Parent = ScreenGui,
            })
            padding(tooltip, 7, 9, 7, 9); corner(tooltip, 5)
            stroke(tooltip, Library.Theme.Border, 1, 0.3)
            local mouse = UserInputService:GetMouseLocation()
            local viewport = ScreenGui.AbsoluteSize
            local x = mouse.X + 14
            local y = mouse.Y + 16
            if x + width > viewport.X - 6 then x = mouse.X - width - 10 end
            if y + height > viewport.Y - 6 then y = mouse.Y - height - 10 end
            tooltip.Position = UDim2.fromOffset(math.max(6, x), math.max(6, y))
        end, section.Window._connections)
        connect(instance.MouseLeave, hideTooltip, section.Window._connections)
    end

    -- Optional dependency gating. DependsOn accepts a flag or list of flags (all
    -- must be truthy), { Any = { ... } } for OR, { Predicate = fn } for arbitrary
    -- logic, and { Not = true } to invert. Mode = "Disable" greys the control out
    -- instead of hiding it.
    local dependency
    if options.DependsOn ~= nil then
        local deps = options.DependsOn
        if type(deps) == "string" then deps = { deps } end
        if type(deps) == "table" and (#deps > 0 or deps.Any or deps.Predicate or deps.Not) then
            dependency = {
                Deps = deps,
                Handles = {},
                Met = true,
                Mode = options.DependencyMode == "Disable" and "Disable" or "Hide",
            }
            local function satisfied()
                if type(dependency.Deps.Predicate) == "function" then
                    -- The predicate receives a getter for flag values, so it can
                    -- express arbitrary logic.
                    local ok, result = pcall(dependency.Deps.Predicate, function(flag)
                        return Library:GetFlag(flag, false)
                    end)
                    if not ok then return false end
                    local met = not not result
                    if dependency.Deps.Not then met = not met end
                    return met
                end
                local function any(flags)
                    for _, dep in ipairs(flags) do
                        if Library:GetFlag(dep, false) then return true end
                    end
                    return false
                end
                local met
                if dependency.Deps.Any then
                    met = any(dependency.Deps.Any)
                else
                    met = true
                    for _, dep in ipairs(dependency.Deps) do
                        if not Library:GetFlag(dep, false) then
                            met = false
                            break
                        end
                    end
                end
                if dependency.Deps.Not then met = not met end
                return met
            end
            local function update()
                if destroyed or not instance then return end
                local met = satisfied()
                dependency.Met = met
                instance:SetAttribute("BloodshotDependencyMet", met)
                if dependency.Mode == "Disable" then
                    instance.Visible = not dependency.HiddenBySearch
                    control.Disabled = not met
                    instance:SetAttribute("BloodshotDisabled", not met)
                    refreshVeil(instance)
                    for _, descendant in ipairs(instance:GetDescendants()) do
                        if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                            descendant.Active = met
                            descendant.Selectable = met
                        end
                    end
                else
                    instance.Visible = met and not dependency.HiddenBySearch
                    for _, descendant in ipairs(instance:GetDescendants()) do
                        if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                            descendant.Selectable = met
                        end
                    end
                end
            end
            dependency.Update = update
            local function subscribe(list)
                if type(list) ~= "table" then return end
                for _, dep in ipairs(list) do
                    if type(dep) == "string" then
                        table.insert(dependency.Handles, Library:OnFlagChanged(dep, update))
                    end
                end
            end
            local function subscribeAll()
                subscribe(dependency.Deps)
                subscribe(dependency.Deps.Any)
                if type(dependency.Deps.Predicate) == "function" then
                    local handle = Library:OnFlagChanged(nil, update)
                    if type(handle) == "table" then
                        table.insert(dependency.Handles, handle)
                    end
                end
            end
            subscribeAll()
            update()
            control.SetDependency = function(_, newDependency)
                for _, handle in ipairs(dependency.Handles) do handle:Unbind() end
                table.clear(dependency.Handles)
                local list = newDependency
                if type(list) == "string" then list = { list } end
                if type(list) ~= "table" then
                    dependency.Deps = {}
                    dependency.Met = true
                else
                    dependency.Deps = list
                    subscribeAll()
                end
                update()
                return control
            end
            control.SetDependencyMode = function(_, mode)
                dependency.Mode = mode == "Disable" and "Disable" or "Hide"
                update()
                return control
            end
            control.IsDependencyMet = function() return dependency.Met end
        end
    end
    if dependency then
        table.insert(Library._dependencySubs, dependency)
    end
    -- Reorder handle lives on the control's clickable overlay so plain clicks
    -- still work; sliders and other drag-consuming controls opt out.
    if section.Window._reorderEnabled ~= false and options.ReorderDrag ~= false
        and not DRAG_CONSUMING_CONTROLS[methodName] then
        local overlay
        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("GuiButton") then
                overlay = descendant
                break
            end
        end
        if overlay then
            control._dragState = beginReorderDrag(overlay, instance, section.Container, section.Window, true, 6)
        end
    end
    local function disposeDependency()
        if not dependency then return end
        for _, handle in ipairs(dependency.Handles) do handle:Unbind() end
        table.clear(dependency.Handles)
        for index = #Library._dependencySubs, 1, -1 do
            if Library._dependencySubs[index] == dependency then
                table.remove(Library._dependencySubs, index)
            end
        end
        dependency = nil
    end

    local function findNameLabel()
        if not instance or not instance.Parent then return nil end
        for _, child in ipairs(instance:GetChildren()) do
            if child:IsA("TextLabel") then return child end
        end
    end

    local function nameCenter(label)
        local base = instance:GetAttribute("BloodshotBaseHeight") or 0
        if label.Size.Y.Scale > 0 then
            return base * label.Size.Y.Scale / 2 + label.Position.Y.Offset
        end
        return label.Position.Y.Offset + label.Size.Y.Offset / 2
    end

    local decorated = instance:IsA("GuiObject") and instance:GetAttribute("BloodshotCompact") ~= true
    if decorated and options.Icon ~= nil and options.Icon ~= "" then
        local label = findNameLabel()
        if label then
            local center = nameCenter(label)
            local asset = iconAsset(options.Icon)
            local glyph
            if asset then
                glyph = new("ImageLabel", {
                    Name = "Icon",
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 12, 0, center),
                    Size = UDim2.fromOffset(16, 16),
                    Image = asset,
                    Parent = instance,
                })
                bindTheme(glyph, "ImageColor3", "MutedText")
            else
                glyph = text(instance, tostring(options.Icon), 13, "MutedText", {
                    Name = "Icon",
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 12, 0, center),
                    Size = UDim2.fromOffset(16, 18),
                    TextXAlignment = Enum.TextXAlignment.Center,
                })
            end
            for _, child in ipairs(instance:GetChildren()) do
                if child:IsA("TextLabel") and child ~= glyph
                    and child.Position.X.Scale == 0 and child.Position.X.Offset == 12 then
                    child.Position = UDim2.new(0, 36, child.Position.Y.Scale, child.Position.Y.Offset)
                    child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset - 24, child.Size.Y.Scale, child.Size.Y.Offset)
                end
            end
            control.IconInstance = glyph
        end
    end

    local tagPill, tagLabel, tagColor, tagWidth
    local function placeTag()
        if not tagPill or not tagPill.Parent then return end
        local label = findNameLabel()
        if not label then return end
        local used = label.TextBounds.X
        local available = label.AbsoluteSize.X
        tagPill.Position = UDim2.new(0, label.Position.X.Offset + used + 8, 0, nameCenter(label))
        tagPill.Visible = available <= 0 or used + 8 + tagWidth <= available
    end
    local function tagFill()
        if not tagPill then return end
        if typeof(tagColor) == "Color3" then
            tagPill.BackgroundColor3 = tagColor
        else
            tagPill.BackgroundColor3 = Library.Theme[tagColor] or Library.Theme.Accent
        end
    end
    local function setTag(value, color)
        if destroyed or not instance or not decorated then return control end
        tagColor = color or tagColor or "Accent"
        if value == nil or value == "" then
            if tagPill then tagPill:Destroy() end
            tagPill, tagLabel = nil, nil
            return control
        end
        local caption = string.upper(tostring(value))
        tagWidth = math.ceil(measureText(caption, 9, Enum.Font.GothamBold, 1000).X) + 14
        if not tagPill then
            local label = findNameLabel()
            if not label then return control end
            tagPill = new("Frame", {
                Name = "Tag",
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                ZIndex = 3,
                Parent = instance,
            })
            corner(tagPill, 999)
            tagLabel = text(tagPill, caption, 9, "Text", {
                Size = UDim2.fromScale(1, 1),
                TextScaled = false,
                TextXAlignment = Enum.TextXAlignment.Center,
                Font = Enum.Font.GothamBold,
            })
            bindThemeState(tagPill, tagFill)
            connect(label:GetPropertyChangedSignal("Text"), placeTag, section.Window._connections)
            connect(label:GetPropertyChangedSignal("AbsoluteSize"), placeTag, section.Window._connections)
        end
        tagLabel.Text = caption
        tagPill.Size = UDim2.fromOffset(tagWidth, 15)
        tagFill()
        placeTag()
        return control
    end
    control.SetTag = function(_, value, color) return setTag(value, color) end
    if options.Tag ~= nil and options.Tag ~= "" then
        setTag(options.Tag, options.TagColor)
    end

    if not control.SetVisible then
        function control:SetVisible(visible)
            if destroyed or not instance then return self end
            instance.Visible = not not visible
            return self
        end
    end
    if not control.SetDisabled then
        function control:SetDisabled(disabled)
            if destroyed or not instance then return self end
            disabled = not not disabled
            self.Disabled = disabled
            instance:SetAttribute("BloodshotDisabled", disabled)
            refreshVeil(instance)
            local locked = disabled or instance:GetAttribute("BloodshotSectionDisabled") == true
            for _, descendant in ipairs(instance:GetDescendants()) do
                if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                    descendant.Active = not locked
                    descendant.Selectable = not locked
                end
            end
            return self
        end
    else
        local ownDisable = control.SetDisabled
        function control:SetDisabled(disabled, ...)
            if destroyed or not instance then return self end
            disabled = not not disabled
            self.Disabled = disabled
            instance:SetAttribute("BloodshotDisabled", disabled)
            refreshVeil(instance)
            ownDisable(self, disabled, ...)
            return self
        end
    end
    if not control.SetName then
        function control:SetName(name)
            if destroyed or not instance then return self end
            local label = findNameLabel()
            if label then label.Text = tostring(name) end
            instance.Name = tostring(name)
            return self
        end
    end
    if not control.SetDescription then
        function control:SetDescription(description)
            if destroyed or not instance then return self end
            local labels = {}
            for _, child in ipairs(instance:GetChildren()) do
                if child:IsA("TextLabel") then table.insert(labels, child) end
            end
            local body = instance:GetAttribute("BloodshotHasDescription") and labels[2] or nil
            if body then
                body.Text = tostring(description or "")
            elseif description ~= nil and instance:GetAttribute("BloodshotControl") and labels[1] then
                labels[1].Position = UDim2.fromOffset(12, 6)
                labels[1].Size = UDim2.new(labels[1].Size.X.Scale, labels[1].Size.X.Offset, 0, 18)
                body = text(instance, tostring(description), 11, "MutedText", {
                    Position = UDim2.fromOffset(12, 25),
                    Size = UDim2.new(1, -24, 0, 16),
                })
                instance:SetAttribute("BloodshotHasDescription", true)
                instance.Size = UDim2.new(instance.Size.X.Scale, instance.Size.X.Offset, 0, instance.Size.Y.Offset + 12)
            end
            return self
        end
    end
    if not control.Destroy then
        function control:Destroy()
            if destroyed then return end
            destroyed = true
            disposeDependency()
            for _, connection in ipairs(control._owned or {}) do
                if connection.Connected then connection:Disconnect() end
            end
            if flag and Library._flagSetters[flag] == setter then
                Library._flagSetters[flag] = nil
                section.Window._flagSetters[flag] = nil
                Library._flagTypes[flag] = nil
            end
            for index = #Library._specControls, 1, -1 do
                if Library._specControls[index] == control then
                    table.remove(Library._specControls, index)
                end
            end
            local siblings = section.Controls
            local slot = type(siblings) == "table" and table.find(siblings, control) or nil
            if slot then table.remove(siblings, slot) end
            local panel = control.Panel
            if typeof(panel) == "Instance" then
                local overlays = section._overlays
                local position = overlays and table.find(overlays, panel)
                if position then table.remove(overlays, position) end
                panel:Destroy()
            end
            if instance then instance:Destroy(); instance = nil end
            self.Instance = nil
        end
    end
    if flag and control.Get then
        local ok, value = pcall(control.Get, control)
        if ok then Library._flagTypes[flag] = typeof(value) end
    end
    if options.Disabled == true then control:SetDisabled(true) end
    if options.Visible == false then control:SetVisible(false) end
    return control
end

-- NOTE: installControlWrappers must be invoked *after* every Section:Add* method
-- is defined. A `function Section:AddFoo` assignment written later in the file
-- replaces whatever wrapper this loop installed, and that control then silently
-- skips the shared contract (no Destroy, no flag fan-out, not in Section.Controls).

local Tab = {}
Tab.__index = Tab

function Tab:AddSection(options)
    options = type(options) == "table" and options or { Name = tostring(options) }
    local sectionFrame = new("Frame", {
        Name = options.Name or "Section",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        -- Seeded from creation order: UIListLayout breaks LayoutOrder ties by
        -- Name, so leaving this at 0 would silently alphabetise the tab.
        LayoutOrder = #self.Sections + 1,
        Parent = self.Page,
    })
    local heading = text(sectionFrame, string.upper(options.Name or "SECTION"), 10, "MutedText", {
        Size = UDim2.new(1, 0, 0, 24),
        Font = Enum.Font.GothamBold,
    })
    heading.TextTransparency = 0.1
    local descriptionLabel
    if options.Description ~= nil and options.Description ~= "" then
        heading.Size = UDim2.new(0.55, 0, 0, 24)
        descriptionLabel = text(sectionFrame, tostring(options.Description), 10, "MutedText", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0.45, 0, 0, 24),
            TextXAlignment = Enum.TextXAlignment.Right,
        })
    end
    local container = new("Frame", {
        Name = "Controls",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 24),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = sectionFrame,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, self.Window._layout.ControlSpacing),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = container,
    })
    local section = setmetatable({
        Name = options.Name or "Section",
        Frame = sectionFrame,
        Heading = heading,
        Container = container,
        Window = self.Window,
        Tab = self,
        Collapsed = false,
        Disabled = false,
        Controls = {},
        DescriptionLabel = descriptionLabel,
    }, Section)
    table.insert(self.Sections, section)
    if self.Window._reorderEnabled ~= false and options.Reorderable ~= false then
        section._dragState = beginReorderDrag(sectionFrame, sectionFrame, self.Page, self.Window, true, 6,
            function() self:SyncSectionOrder() end)
    end
    -- Every section gets the toggle, but it only reacts once the section is
    -- collapsible or already collapsed: a SetCollapsed() from code can always be
    -- undone by clicking the heading again, and plain sections look untouched.
    local collapseButton = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 24),
        Text = "",
        AutoButtonColor = false,
        Active = false,
        Parent = sectionFrame,
    })
    section.Collapsible = options.Collapsible == true
    if options.Visible == false then section:SetVisible(false) end
    connect(collapseButton.Activated, function(input)
        if section._dragState and section._dragState.Dragged then
            section._dragState.Dragged = false
            return
        end
        if Library:_isObscured(self.Window, input and input.Position) then
            return
        end
        section:ToggleCollapsed()
    end, self.Window._connections)
    section.CollapseButton = collapseButton
    section:SetCollapsed(options.Collapsed == true)
    return section
end

-- Collects everything a search should consider: whole controls, plus the
-- children of AddRow holders, which are nested one level below a slot frame.
local function collectSearchable(section)
    local list = {}
    local rows = {}
    local function walk(node)
        for _, child in ipairs(node:GetChildren()) do
            if child:IsA("GuiObject") then
                if child:GetAttribute("BloodshotControl")
                    or child:GetAttribute("BloodshotList")
                    or child:GetAttribute("BloodshotRow") then
                    list[#list + 1] = child
                    if child:GetAttribute("BloodshotRow") then
                        rows[#rows + 1] = child
                        walk(child)
                    end
                else
                    walk(child)
                end
            end
        end
    end
    walk(section.Container)
    return list, rows
end

-- Filters one section in place. Returns the number of visible controls, or
-- nil when nothing matched so callers can hide the whole section heading.
-- Search bars (BloodshotSearch) are never hidden by filtering.
local function filterSection(section, query)
    local visible = 0
    local all, rows = collectSearchable(section)
    local matched = {}
    for _, control in ipairs(all) do
        if control:GetAttribute("BloodshotSearch") == true then
            matched[control] = true
        elseif string.find(string.lower(control.Name), query, 1, true) ~= nil then
            matched[control] = true
        end
    end
    local function blocked(control)
        if control:GetAttribute("BloodshotDependencyMet") == false then return true end
        local parent = control.Parent
        while parent and parent ~= section.Container do
            if parent:GetAttribute("BloodshotDependencyMet") == false then return true end
            parent = parent.Parent
        end
        return false
    end
    for _, control in ipairs(all) do
        if control:GetAttribute("BloodshotSearch") == true then
            control.Visible = true
            visible += 1
        else
            local isRow = control:GetAttribute("BloodshotRow") == true
            local show
            if isRow then
                -- A row stays visible when its own name matches or any child does.
                local anyChild = false
                for _, child in ipairs(control:GetDescendants()) do
                    if child:IsA("GuiObject") and matched[child] then anyChild = true break end
                end
                show = matched[control] or anyChild
            else
                show = matched[control]
            end
            control.Visible = show and not blocked(control)
            if control.Visible then visible += 1 end
        end
    end
    return visible
end

local function snapshotSearch(section)
    if section._searchSnapshot then
        return
    end
    local controls = {}
    for _, control in ipairs(collectSearchable(section)) do
        controls[#controls + 1] = { instance = control, visible = control.Visible }
    end
    section._searchSnapshot = { controls = controls }
end

-- Live search over one section's controls.
function Section:Search(query)
    query = string.lower(tostring(query or ""))
    if not self.Container then return 0 end
    -- Counts controls that pass the filter; on the restore path the snapshot is
    -- authoritative, so only re-hide the ones a dependency still blocks.
    if query == "" then
        local snapshot = self._searchSnapshot
        self._searchSnapshot = nil
        if snapshot then
            for _, entry in ipairs(snapshot.controls) do
                if entry.instance.Parent then entry.instance.Visible = entry.visible end
            end
        end
        local count = 0
        for _, control in ipairs(collectSearchable(self)) do
            local blocked = control:GetAttribute("BloodshotDependencyMet") == false
                or (control.Parent and control.Parent.Parent
                    and control.Parent.Parent:GetAttribute("BloodshotDependencyMet") == false)
            if blocked then
                control.Visible = false
            elseif control.Visible then
                count += 1
            end
        end
        return count
    end
    snapshotSearch(self)
    return filterSection(self, query)
end

function Section:AddSearch(options)
    options = type(options) == "table" and options or {}
    -- Defaults to the containing section. Pass Target = "Tab" (or a tab) to
    -- filter the whole tab instead.
    local target = self
    if options.Target == "Tab" then
        target = self.Tab
    elseif options.Target ~= nil and options.Target ~= "Section" then
        target = options.Target
    end
    local compact = self._compact == true
    local holder, nameLabel, descriptionLabel = createControlBase(
        self,
        options.Description and 58 or 46,
        options.Name or T("Search"),
        options.Description
    )
    nameLabel.Size = UDim2.new(0.4, -12, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    if descriptionLabel then
        descriptionLabel.Size = UDim2.new(0.4, -12, 0, 16)
    end
    local fixedWidth = not compact and tonumber(options.Width) or nil
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = fixedWidth and UDim2.fromOffset(fixedWidth, 28) or UDim2.new(0.52, 0, 0, 28),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        Text = "",
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        PlaceholderText = options.Placeholder or T("SearchPlaceholder"),
        Parent = holder,
    })
    constrainText(box, 8, 12)
    bindTheme(box, "BackgroundColor3", "Background")
    bindTheme(box, "TextColor3", "Text")
    bindTheme(box, "PlaceholderColor3", "MutedText")
    corner(box, 5)
    padding(box, 0, 8, 0, 8)
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.4, -COMPACT_MARGIN, 1, 0)
        box.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
    end
    local matches = 0
    local function run(query)
        query = tostring(query or "")
        -- An empty query still has to go through Search: that is the restore path
        -- which puts the controls the last filter hid back on screen. It returns
        -- a visible count rather than a match count, so it is not kept.
        if target and target.Search then
            if query == "" then
                target:Search("")
                matches = 0
            else
                -- Re-apply the current query to pick up controls added since the
                -- last keystroke; the snapshot keeps every match visible.
                matches = target:Search(query) or 0
            end
        end
        if matches == 0 and string.lower(query) ~= "" then
            nameLabel.Text = T("SearchNothingFound")
            nameLabel.TextColor3 = Library.Theme.Warning
        else
            nameLabel.Text = options.Name or T("Search")
            nameLabel.TextColor3 = Library.Theme.Text
        end
        commitFlag(options.Flag, query)
    end
    connect(box:GetPropertyChangedSignal("Text"), function()
        run(box.Text)
        if not options.Nofire then safeCall(options.Callback, box.Text, matches) end
    end, self.Window._connections)
    connect(box.Focused, function()
        tween(box, 0.15, { BackgroundColor3 = Library.Theme.Surface })
    end, self.Window._connections)
    connect(box.FocusLost, function()
        tween(box, 0.15, { BackgroundColor3 = Library.Theme.Background })
    end, self.Window._connections)
    holder:SetAttribute("BloodshotSearch", true)
    return {
        Instance = holder,
        Set = function(_, query) box.Text = tostring(query or "") end,
        Get = function() return box.Text end,
        SetQuery = function(_, query)
            box.Text = tostring(query or "")
            run(box.Text)
        end,
        Clear = function() box.Text = "" end,
        GetMatches = function() return matches end,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
            setWidth(box, showName and 0.56 or 1, showName and -COMPACT_MARGIN or -COMPACT_MARGIN * 2)
        end,
    }
end

-- Live label whose text binds to flags. Placeholders {flag} in the template are
-- replaced with the current value, so a callback does not have to call Set().
--   section:AddSummary({ Template = "Icons {on}/23 | Outlines {out}/23" })
-- Flags not named in the template can drive it through Values instead.
function Section:AddSummary(options)
    options = type(options) == "table" and options or {}
    local template = options.Template or options.Text or ""
    local holder, nameLabel = createControlBase(self, options.Height or 34, options.Name or "Summary")
    -- The template body is the visible text; the base name label would sit
    -- directly underneath it and overlap, so hide it.
    if nameLabel then
        nameLabel.Visible = false
    end
    local body = text(holder, "", options.TextSize or 12, options.Color or "Text", {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextXAlignment = options.Alignment or Enum.TextXAlignment.Left,
    })
    if self._compact == true then
        body:SetAttribute("BloodshotKeep", true)
        body.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        body.Size = UDim2.new(1, -COMPACT_MARGIN * 2, 1, 0)
    end
    local values = type(options.Values) == "table" and options.Values or {}
    local handles = {}
    local rendered = ""

    local function render()
        local function substitute(flag)
            -- Values wins over a same-named flag so a placeholder can be
            -- pointed at a different flag without renaming the template.
            local mapped = values[flag]
            if mapped ~= nil then flag = mapped end
            local raw = Library:GetFlag(flag, nil)
            if raw == nil then
                return "?"
            end
            if typeof(raw) == "number" and math.floor(raw) ~= raw then
                return tostring(math.floor(raw * 100 + 0.5) / 100)
            end
            return tostring(raw)
        end
        -- One pass: every {name} resolves through Values or falls back to being
        -- a flag name. Two passes would double-substitute rendered values.
        rendered = string.gsub(template, "{(%w[%w_%.]*)}", substitute)
        body.Text = rendered
    end

    local function watch(flag)
        if handles[flag] then return end
        handles[flag] = Library:OnFlagChanged(flag, function()
            render()
            safeCall(options.Changed, rendered)
        end)
    end

    local function collect()
        for flag in string.gmatch(template, "{(%w[%w_%.]*)}") do
            watch(flag)
        end
        for _, flag in pairs(values) do
            watch(tostring(flag))
        end
    end
    collect()

    local entry = { Dispose = function()
        for _, handle in pairs(handles) do handle:Unbind() end
        table.clear(handles)
    end }
    table.insert(Library._controlDisposers, entry)
    render()
    return {
        Instance = holder,
        Set = function(_, value)
            template = tostring(value)
            collect()
            render()
        end,
        Get = function() return rendered end,
        Refresh = render,
        Watch = function(_, flag, placeholder)
            values[tostring(placeholder or flag)] = flag
            watch(flag)
            render()
        end,
        Unwatch = function(_, flag)
            if handles[flag] then
                handles[flag]:Unbind()
                handles[flag] = nil
                render()
            end
        end,
    }
end

-- Runtime list of rows. Unlike the other controls this one owns no row specs up
-- front: AddRow/Remove/Update drive it as data arrives, which is what effects
-- managers and report previews need.
--   local list = section:AddList({ MaxRows = 8 })
--   list:AddRow({ Name = "Rain", Detail = "storm", Enabled = true })
--   list:SetRows({ {Name = "a"}, {Name = "b"} })
function Section:AddList(options)
    options = type(options) == "table" and options or {}
    local maxRows = math.clamp(math.floor(tonumber(options.MaxRows) or 8), 1, 200)
    local rowHeight = math.clamp(tonumber(options.RowHeight) or 32, 20, 90)
    local showIndex = options.ShowIndex == true
    local holder = new("Frame", {
        Name = options.Name or "List",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = self.Container,
    })
    bindTheme(holder, "BackgroundColor3", "SurfaceAlt")
    gradient(holder, "SurfaceAlt", "SurfaceGradient", 12)
    corner(holder, 6)
    stroke(holder, Library.Theme.Border, 1, 0.45, "Border")
    holder:SetAttribute("BloodshotControl", true)
    holder:SetAttribute("BloodshotList", true)
    holder:SetAttribute("BloodshotDisabled", false)
    holder:SetAttribute("BloodshotBaseHeight", rowHeight)
    holder:SetAttribute("BloodshotHasDescription", false)
    padding(holder, 6, 6, 6, 6)
    tween(holder, 0.24, { BackgroundTransparency = Library.Theme.ControlTransparency or 0.8 })

    local heading
    local rowHost = new("Frame", {
        Name = "Rows",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = holder,
    })
    if options.Title or options.Name then
        heading = text(holder, options.Title or options.Name or "List", 12, "Text", {
            Position = UDim2.fromOffset(6, 2),
            Size = UDim2.new(1, -12, 0, 18),
            Font = Enum.Font.GothamMedium,
        })
        rowHost.Position = UDim2.fromOffset(0, 24)
    end
    new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = rowHost,
    })

    local emptyLabel = text(rowHost, options.EmptyText or T("NoOptions"), 11, "MutedText", {
        Size = UDim2.new(1, 0, 0, 24),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    emptyLabel.Visible = true

    local rows = {}

    local function refreshEmpty()
        emptyLabel.Visible = #rows == 0
        holder:SetAttribute("BloodshotRowCount", #rows)
        holder:SetAttribute("BloodshotRowCountText", tostring(#rows))
        commitFlag(options.Flag, #rows)
    end

    local function renderRow(entry, data, index)
        entry.Data = data
        entry.Label.Text = tostring(data.Name or data.Text or data.Title or "Row")
        entry.Detail.Text = tostring(data.Detail or data.Description or "")
        entry.Detail.Visible = entry.Detail.Text ~= ""
        entry.Accent.BackgroundColor3 = data.Color or Library.Theme.Accent
        entry.Accent.Visible = data.Color ~= nil or data.Dot == true
        if showIndex then
            entry.Index.Text = tostring(index)
        end
        if entry.Icon then
            entry.Icon.Visible = data.Icon ~= nil
            entry.Icon.Image = data.Icon and tostring(data.Icon) or ""
        end
        if entry.Remove then
            entry.Remove.Visible = options.Removable ~= false
        end
    end

    -- Forward declaration: makeRow's remove handler and SetRows both need the
    -- finished control, and they are defined before it is assigned.
    local list
    local function makeRow(data, index)
        local frame = new("Frame", {
            Name = tostring(data.Key or data.Name or "Row"),
            BackgroundTransparency = 0,
            Size = UDim2.new(1, 0, 0, rowHeight),
            BackgroundColor3 = Library.Theme.Background,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Parent = rowHost,
        })
        bindTheme(frame, "BackgroundColor3", "Background")
        corner(frame, 5)
        local accent = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.fromOffset(3, rowHeight - 10),
            BorderSizePixel = 0,
            Visible = false,
            Parent = frame,
        })
        corner(accent, 999)
        local icon
        local offset = 8
        if options.ShowIcon == true then
            icon = new("ImageLabel", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, offset, 0.5, 0),
                Size = UDim2.fromOffset(18, 18),
                Visible = false,
                Parent = frame,
            })
            bindTheme(icon, "ImageColor3", "MutedText")
            offset += 24
        end
        -- UDim2.fromOffset(x, y) sets *both* axes as pixel offsets, so the 0.5
        -- centre below has to be a scale component (UDim2.new(0, x, 0.5, 0)).
        -- Using fromOffset(offset, 0.5) pinned these labels half a pixel from
        -- the top, which put the row text visibly above the middle.
        local indexLabel
        if showIndex then
            indexLabel = text(frame, "", 10, "MutedText", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, offset, 0.5, 0),
                Size = UDim2.fromOffset(18, rowHeight),
                TextXAlignment = Enum.TextXAlignment.Left,
            })
            offset += 22
        end
        local label = text(frame, "", 11, "Text", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, offset, 0.5, 0),
            Size = UDim2.new(1, -(offset + 112), 0, rowHeight),
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        local detail = text(frame, "", 10, "MutedText", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -30, 0.5, 0),
            Size = UDim2.fromOffset(76, rowHeight),
            TextXAlignment = Enum.TextXAlignment.Right,
        })
        local remove
        local entry
        if options.Removable ~= false then
            remove = new("TextButton", {
                Name = "Remove",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -6, 0.5, 0),
                Size = UDim2.fromOffset(20, 20),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Font = Enum.Font.GothamMedium,
                Text = "x",
                TextSize = 13,
                TextColor3 = Library.Theme.MutedText,
                ZIndex = 6,
                Parent = frame,
            })
            bindTheme(remove, "TextColor3", "MutedText")
            corner(remove, 4)
            connect(remove.MouseEnter, function()
                tween(remove, 0.12, { TextColor3 = Library.Theme.Error })
            end, self.Window._connections)
            connect(remove.MouseLeave, function()
                tween(remove, 0.12, { TextColor3 = Library.Theme.MutedText })
            end, self.Window._connections)
            connect(remove.Activated, function(input)
                if Library:_isObscured(self.Window, input and input.Position) then
                    return
                end
                list:RemoveRow(entry)
            end, self.Window._connections)
        end
        entry = {
            Instance = frame,
            Label = label,
            Detail = detail,
            Accent = accent,
            Icon = icon,
            Index = indexLabel,
            Remove = remove,
            Data = data,
            Key = data.Key,
        }
        renderRow(entry, data, index)
        return entry
    end

    local function indexOf(key)
        if key == nil then return nil end
        for position, entry in ipairs(rows) do
            if entry == key or entry.Data == key or (entry.Data.Key ~= nil and entry.Data.Key == key) then
                return position
            end
        end
        return nil
    end

    list = {
        Instance = holder,
        Rows = rowHost,
        MaxRows = maxRows,
        RowHeight = rowHeight,
        AddRow = function(self, data)
            if type(data) ~= "table" then
                return nil, "AddRow expects a table"
            end
            if #rows >= maxRows then
                return nil, "List is full (" .. maxRows .. " rows)"
            end
            if data.Key ~= nil and indexOf(data.Key) then
                return nil, "Duplicate row key"
            end
            local entry = makeRow(data, #rows + 1)
            table.insert(rows, entry)
            refreshEmpty()
            local ok, message = pcall(function() safeCall(options.Callback, #rows, entry.Data, "add") end)
            if not ok then warn("[Bloodshot UI] AddList callback: " .. tostring(message)) end
            return entry
        end,
        Add = nil,
        RemoveRow = function(self, key)
            local position = indexOf(key)
            if not position then return false end
            local entry = table.remove(rows, position)
            if entry and entry.Instance then entry.Instance:Destroy() end
            for index, remaining in ipairs(rows) do
                remaining.Instance.LayoutOrder = index
                if remaining.Index then remaining.Index.Text = tostring(index) end
            end
            refreshEmpty()
            safeCall(options.Callback, #rows, entry.Data, "remove")
            return true
        end,
        UpdateRow = function(self, key, data)
            if type(data) ~= "table" then return false end
            local position = indexOf(key)
            local entry = position and rows[position] or nil
            if not entry then return false end
            local merged = {}
            for field, value in pairs(entry.Data) do merged[field] = value end
            for field, value in pairs(data) do merged[field] = value end
            entry.Data = merged
            renderRow(entry, merged, position)
            safeCall(options.Callback, #rows, merged, "update")
            return true
        end,
        GetRow = function(self, key)
            local position = indexOf(key)
            return position and rows[position] or nil
        end,
        GetRows = function() return rows end,
        GetCount = function() return #rows end,
        Clear = function(self)
            for _, entry in ipairs(rows) do
                if entry.Instance then entry.Instance:Destroy() end
            end
            table.clear(rows)
            refreshEmpty()
            safeCall(options.Callback, 0, nil, "clear")
            return self
        end,
        SetRows = function(self, data)
            -- Rebuild from scratch: keys, ordering and contents can all change.
            local previous = self
            list:Clear()
            if type(data) == "table" then
                for _, item in ipairs(data) do
                    if type(item) == "table" then
                        local ok = list:AddRow(item)
                        if not ok then break end
                    end
                end
            end
            return previous
        end,
        Disposer = nil,
    }
    list.Add = list.AddRow
    list.Remove = list.RemoveRow
    list.Update = list.UpdateRow

    list.Disposer = { Dispose = function()
        for _, entry in ipairs(rows) do
            if entry.Instance then entry.Instance:Destroy() end
        end
        table.clear(rows)
    end }
    table.insert(Library._controlDisposers, list.Disposer)
    refreshEmpty()
    return list
end

function Section:AddSpacer(options)
    options = type(options) == "table" and options or { Height = options }
    local height = math.clamp(tonumber(options.Height) or 12, 0, 240)
    local holder = new("Frame", {
        Name = "Spacer",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height),
        Parent = self.Container,
    })
    return {
        Instance = holder,
        Set = function(_, value)
            height = math.clamp(tonumber(value) or height, 0, 240)
            holder.Size = UDim2.new(1, 0, 0, height)
        end,
        Get = function() return height end,
    }
end

function Section:AddStat(options)
    options = options or {}
    local compact = self._compact == true
    local holder, nameLabel = createControlBase(self, options.Description and 52 or 40, options.Name or "Stat", options.Description)
    nameLabel.Size = UDim2.new(0.45, -12, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    local colorSpec = options.Color
    local valueLabel = text(holder, "", compact and 11 or 13, Library.Theme.Text, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0.5, -12, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
        Font = Enum.Font.GothamMedium,
    })
    bindThemeState(valueLabel, function()
        valueLabel.TextColor3 = resolveColor(colorSpec, "Text")
    end)
    local copyable = options.Copyable == true
    if copyable then
        local button = new("TextButton", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            AutoButtonColor = false,
            ZIndex = 4,
            Parent = holder,
        })
        connect(button.Activated, function(input)
            if Library:_isObscured(self.Window, input and input.Position) then return end
            if type(setclipboard) == "function" then
                pcall(setclipboard, tostring(valueLabel.Text))
                if options.CopyNotify ~= false then
                    Library:Notify({ Title = T("Copied"), Content = tostring(valueLabel.Text), Duration = 1.5 })
                end
            end
        end, self.Window._connections)
    end
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.5, -COMPACT_MARGIN, 1, 0)
        valueLabel:SetAttribute("BloodshotKeep", true)
        valueLabel.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
        valueLabel.Size = UDim2.new(0.5, -COMPACT_MARGIN, 1, 0)
    end
    local value = options.Default
    if value == nil then value = options.Value end
    local function render()
        local shown = value
        if type(options.Format) == "function" then
            local ok, result = pcall(options.Format, value)
            shown = ok and result or value
        elseif type(options.Format) == "string" then
            shown = expandTemplate(options.Format, { value = value })
        elseif type(value) == "number" and options.Decimals then
            shown = string.format("%." .. math.clamp(math.floor(options.Decimals), 0, 8) .. "f", value)
        end
        valueLabel.Text = (options.Prefix or "") .. tostring(shown == nil and "" or shown) .. (options.Suffix or "")
    end
    local function set(nextValue, silent)
        value = nextValue
        render()
        commitFlag(options.Flag, value)
        if not silent then safeCall(options.Callback, value) end
    end
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        SetColor = function(_, color)
            colorSpec = color
            valueLabel.TextColor3 = resolveColor(colorSpec, "Text")
        end,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
        end,
    }
end

function Section:AddProgress(options)
    options = options or {}
    local compact = self._compact == true
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    if maximum <= minimum then maximum = minimum + 1 end
    local holder, nameLabel = createControlBase(self, 48, options.Name or "Progress")
    nameLabel.Size = UDim2.new(1, -96, 0, 28)
    local valueLabel = text(holder, "", 12, "MutedText", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 0),
        Size = UDim2.fromOffset(76, 28),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local track = new("Frame", {
        Position = UDim2.fromOffset(12, 33),
        Size = UDim2.new(1, -24, 0, 6),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = holder,
    })
    bindTheme(track, "BackgroundColor3", "Border")
    corner(track, 999)
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, 999)
    local colorSpec = options.Color
    local fillGradient
    if colorSpec == nil then
        fillGradient = gradient(fill, "Accent", "AccentGradient", 0)
    end
    bindThemeState(fill, function()
        fill.BackgroundColor3 = resolveColor(colorSpec, "Accent")
    end)
    if compact then
        nameLabel.Position = UDim2.fromOffset(COMPACT_MARGIN, 0)
        nameLabel.Size = UDim2.new(0.3, -COMPACT_MARGIN, 1, 0)
        valueLabel:SetAttribute("BloodshotKeep", true)
        valueLabel.AnchorPoint = Vector2.new(1, 0.5)
        valueLabel.Position = UDim2.new(1, -COMPACT_MARGIN, 0.5, 0)
        valueLabel.Size = UDim2.new(0, 56, 1, 0)
        valueLabel.TextSize = 11
    end
    local value = minimum
    local customText
    local indeterminate = false
    local sweep
    local function ratioOf(number)
        return math.clamp((number - minimum) / (maximum - minimum), 0, 1)
    end
    local function describe()
        if customText ~= nil then return customText end
        if indeterminate then return "" end
        local ratio = ratioOf(value)
        local shown = value
        if options.Decimals then
            shown = string.format("%." .. math.clamp(math.floor(options.Decimals), 0, 8) .. "f", value)
        else
            shown = math.floor(value * 100 + 0.5) / 100
        end
        if type(options.Format) == "function" then
            local ok, result = pcall(options.Format, value, ratio)
            return ok and tostring(result) or tostring(shown)
        end
        return expandTemplate(options.Format or "{percent}%", {
            value = shown, percent = math.floor(ratio * 100 + 0.5), min = minimum, max = maximum,
        })
    end
    local function stopSweep()
        if sweep then
            sweep:Cancel()
            sweep = nil
        end
    end
    local function render(animate)
        valueLabel.Text = describe()
        if indeterminate then return end
        local target = UDim2.fromScale(ratioOf(value), 1)
        if animate and options.Animate ~= false then
            tween(fill, 0.25, { Size = target, Position = UDim2.fromScale(0, 0) })
        else
            fill.Size = target
            fill.Position = UDim2.fromScale(0, 0)
        end
    end
    local function set(nextValue, silent)
        local number = tonumber(nextValue)
        if number == nil or number ~= number then return end
        value = math.clamp(number, minimum, maximum)
        render(true)
        commitFlag(options.Flag, value)
        if not silent then safeCall(options.Callback, value) end
    end
    local function setIndeterminate(enabled)
        indeterminate = not not enabled
        stopSweep()
        if indeterminate then
            fill.Size = UDim2.fromScale(0.32, 1)
            fill.Position = UDim2.fromScale(0, 0)
            if not Library._reducedMotion then
                local ok, animation = pcall(function()
                    return TweenService:Create(fill, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                        Position = UDim2.fromScale(0.68, 0),
                    })
                end)
                if ok and animation then
                    sweep = animation
                    animation:Play()
                end
            else
                fill.Position = UDim2.fromScale(0.34, 0)
            end
            valueLabel.Text = describe()
        else
            render(false)
        end
    end
    connect(holder.Destroying, stopSweep, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    local initial = options.Default
    if initial == nil then initial = options.Value end
    set(initial or minimum, true)
    if options.Indeterminate == true then setIndeterminate(true) end
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        GetRatio = function() return ratioOf(value) end,
        SetText = function(_, caption)
            customText = caption ~= nil and tostring(caption) or nil
            valueLabel.Text = describe()
        end,
        SetColor = function(_, color)
            colorSpec = color
            if fillGradient and color ~= nil then
                fillGradient:Destroy()
                fillGradient = nil
            end
            fill.BackgroundColor3 = resolveColor(colorSpec, "Accent")
        end,
        SetIndeterminate = function(_, enabled) setIndeterminate(enabled) end,
        IsIndeterminate = function() return indeterminate end,
        CompactLayout = function(_, showName)
            nameLabel.Visible = showName
            track.Position = showName and UDim2.new(0.34, 0, 0.5, 0) or UDim2.new(0, COMPACT_MARGIN, 0.5, 0)
            setWidth(track, showName and 0.66 or 1, -(showName and COMPACT_MARGIN + 68 or COMPACT_MARGIN * 2 + 68))
        end,
    }
end

function Section:AddImage(options)
    options = options or {}
    local height = math.clamp(tonumber(options.Height) or 120, 40, 480)
    local top = options.Name and 28 or 8
    local bottom = options.Caption and 24 or 8
    local holder, nameLabel = createControlBase(self, top + height + bottom, options.Name or "Image")
    if options.Name then
        nameLabel.Size = UDim2.new(1, -24, 0, 28)
    else
        nameLabel.Visible = false
    end
    local scaleTypes = {
        fit = Enum.ScaleType.Fit,
        crop = Enum.ScaleType.Crop,
        stretch = Enum.ScaleType.Stretch,
    }
    local picture = new("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, top),
        Size = UDim2.new(1, -16, 0, height),
        ScaleType = scaleTypes[string.lower(tostring(options.ScaleType or "Fit"))] or Enum.ScaleType.Fit,
        ImageTransparency = math.clamp(tonumber(options.Transparency) or 0, 0, 1),
        Parent = holder,
    })
    if typeof(options.Tint) == "Color3" then picture.ImageColor3 = options.Tint end
    corner(picture, tonumber(options.CornerRadius) or 6)
    local caption
    if options.Caption then
        caption = text(holder, tostring(options.Caption), 11, "MutedText", {
            Position = UDim2.new(0, 12, 1, -22),
            Size = UDim2.new(1, -24, 0, 18),
            TextXAlignment = options.CaptionAlignment or Enum.TextXAlignment.Left,
        })
    end
    local image = options.Image or options.Default or ""
    local function set(nextImage, silent)
        image = nextImage == nil and "" or nextImage
        picture.Image = iconAsset(image) or tostring(image)
        commitFlag(options.Flag, image)
        if not silent then safeCall(options.Callback, image) end
    end
    registerFlagSetter(self.Window, options.Flag, set)
    set(image, true)
    return {
        Instance = holder,
        Image = picture,
        Set = function(_, nextImage, silent) set(nextImage, silent) end,
        Get = function() return image end,
        SetCaption = function(_, value)
            if caption then caption.Text = tostring(value or "") end
        end,
    }
end

function Section:AddTextArea(options)
    options = options or {}
    local height = math.clamp(tonumber(options.Height) or 96, 64, 400)
    local holder, nameLabel = createControlBase(self, height, options.Name or "Text")
    nameLabel.Size = UDim2.new(1, -90, 0, 28)
    local maxLength = tonumber(options.MaxLength)
    local readOnly = options.ReadOnly == true
    local box = new("TextBox", {
        Position = UDim2.fromOffset(12, 28),
        Size = UDim2.new(1, -24, 1, -38),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        MultiLine = true,
        TextEditable = not readOnly,
        Font = Enum.Font.Gotham,
        Text = "",
        PlaceholderText = options.Placeholder or T("EnterValue"),
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = holder,
    })
    bindTheme(box, "BackgroundColor3", "Background")
    bindTheme(box, "TextColor3", "Text")
    bindTheme(box, "PlaceholderColor3", "MutedText")
    corner(box, 5)
    padding(box, 6, 8, 6, 8)
    local counter
    if maxLength then
        counter = text(holder, "", 10, "MutedText", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -12, 0, 0),
            Size = UDim2.fromOffset(80, 28),
            TextXAlignment = Enum.TextXAlignment.Right,
        })
    end
    local value = ""
    local function refreshCounter()
        if counter then counter.Text = #box.Text .. "/" .. maxLength end
    end
    local function set(nextValue, silent)
        local raw = tostring(nextValue == nil and "" or nextValue)
        if maxLength and #raw > maxLength then raw = string.sub(raw, 1, maxLength) end
        value = raw
        if box.Text ~= raw then box.Text = raw end
        refreshCounter()
        commitFlag(options.Flag, value)
        if not silent then safeCall(options.Callback, value) end
    end
    connect(box:GetPropertyChangedSignal("Text"), function()
        if maxLength and #box.Text > maxLength then
            box.Text = string.sub(box.Text, 1, maxLength)
            return
        end
        refreshCounter()
        if options.Live == true and box.Text ~= value then
            value = box.Text
            commitFlag(options.Flag, value)
            safeCall(options.Callback, value, false)
        end
    end, self.Window._connections)
    connect(box.Focused, function()
        tween(box, 0.15, { BackgroundColor3 = Library.Theme.Surface })
    end, self.Window._connections)
    connect(box.FocusLost, function(enterPressed)
        tween(box, 0.15, { BackgroundColor3 = Library.Theme.Background })
        if box.Text ~= value or options.Live ~= true then
            value = box.Text
            commitFlag(options.Flag, value)
            safeCall(options.Callback, value, enterPressed)
        end
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(options.Default or "", true)
    return {
        Instance = holder,
        Box = box,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        Append = function(_, extra)
            set(box.Text .. tostring(extra or ""))
        end,
        Clear = function() set("") end,
        Focus = function() box:CaptureFocus() end,
        SetReadOnly = function(_, enabled)
            readOnly = not not enabled
            box.TextEditable = not readOnly
        end,
    }
end

local LOG_LEVELS = {
    Info = "Text", Success = "Success", Warning = "Warning", Warn = "Warning",
    Error = "Error", Debug = "MutedText",
}

function Section:AddLog(options)
    options = options or {}
    local height = math.clamp(tonumber(options.Height) or 160, 80, 520)
    local holder, nameLabel = createControlBase(self, height, options.Name or "Log")
    nameLabel.Size = UDim2.new(1, -150, 0, 28)
    local maxLines = math.clamp(math.floor(tonumber(options.MaxLines) or 200), 10, 2000)
    local stamps = options.Timestamps ~= false
    local autoScroll = options.AutoScroll ~= false
    local function chip(label, offset)
        local button = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -offset, 0, 4),
            Size = UDim2.fromOffset(52, 20),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = label,
            TextSize = 10,
            ZIndex = 5,
            Parent = holder,
        })
        bindTheme(button, "BackgroundColor3", "Background")
        bindTheme(button, "TextColor3", "MutedText")
        corner(button, 5)
        connect(button.MouseEnter, function()
            tween(button, 0.12, { TextColor3 = Library.Theme.Text })
        end, self.Window._connections)
        connect(button.MouseLeave, function()
            tween(button, 0.12, { TextColor3 = Library.Theme.MutedText })
        end, self.Window._connections)
        return button
    end
    local clearButton = chip(T("Clear"), 12)
    local copyButton = chip(T("Copy"), 70)
    local scroller = new("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 30),
        Size = UDim2.new(1, -16, 1, -38),
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = holder,
    })
    bindTheme(scroller, "BackgroundColor3", "Background")
    bindTheme(scroller, "ScrollBarImageColor3", "Accent")
    corner(scroller, 5)
    padding(scroller, 4, 6, 4, 6)
    new("UIListLayout", {
        Padding = UDim.new(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroller,
    })
    local entries = {}
    local sequence = 0
    local function scrollToEnd()
        if not autoScroll then return end
        task.defer(function()
            if scroller.Parent then
                scroller.CanvasPosition = Vector2.new(0, math.max(0, scroller.AbsoluteCanvasSize.Y))
            end
        end)
    end
    local function trim()
        while #entries > maxLines do
            local oldest = table.remove(entries, 1)
            if oldest.Label then oldest.Label:Destroy() end
        end
    end
    local log = {}
    function log.Add(_, message, level)
        sequence += 1
        level = LOG_LEVELS[tostring(level or "Info")] and tostring(level or "Info") or "Info"
        local stamp = stamps and os.date("%H:%M:%S") or nil
        local line = (stamp and ("[" .. stamp .. "] ") or "") .. tostring(message)
        local label = text(scroller, line, 11, LOG_LEVELS[level], {
            Font = Enum.Font.Code,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextScaled = false,
        })
        label.LayoutOrder = sequence
        local entry = { Text = line, Message = tostring(message), Level = level, Time = stamp, Label = label }
        entries[#entries + 1] = entry
        trim()
        scrollToEnd()
        safeCall(options.Callback, entry)
        return entry
    end
    log.Log = log.Add
    for _, level in ipairs({ "Info", "Success", "Warning", "Error", "Debug" }) do
        log[level] = function(self, message) return self:Add(message, level) end
    end
    log.Warn = log.Warning
    function log.Clear()
        for _, entry in ipairs(entries) do
            if entry.Label then entry.Label:Destroy() end
        end
        table.clear(entries)
    end
    function log.GetText()
        local lines = {}
        for _, entry in ipairs(entries) do lines[#lines + 1] = entry.Text end
        return table.concat(lines, "\n")
    end
    function log.GetLines()
        local copy = {}
        for index, entry in ipairs(entries) do copy[index] = entry end
        return copy
    end
    function log.Copy()
        if type(setclipboard) == "function" then
            return pcall(setclipboard, log.GetText())
        end
        return false
    end
    function log.SetMaxLines(_, count)
        maxLines = math.clamp(math.floor(tonumber(count) or maxLines), 10, 2000)
        trim()
    end
    function log.SetAutoScroll(_, enabled)
        autoScroll = not not enabled
    end
    log.Instance = holder
    log.Scroller = scroller
    connect(clearButton.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then return end
        log.Clear()
    end, self.Window._connections)
    connect(copyButton.Activated, function(input)
        if Library:_isObscured(self.Window, input and input.Position) then return end
        log.Copy()
    end, self.Window._connections)
    for _, initial in ipairs(type(options.Lines) == "table" and options.Lines or {}) do
        log:Add(type(initial) == "table" and initial.Text or initial, type(initial) == "table" and initial.Level or nil)
    end
    return log
end

-- Last of the Section:Add* definitions, so the shared v2 contract wrapper can be
-- installed now (see the note above installControlWrappers).
for _, methodName in ipairs({
    "AddLabel", "AddParagraph", "AddButton", "AddToggle", "AddSlider",
    "AddInput", "AddDropdown", "AddKeybind", "AddColorPicker", "AddDivider",
    "AddNumberInput", "AddRadio", "AddSegmented", "AddRangeSlider",
    "AddRow", "AddSearch", "AddSummary", "AddList",
    "AddSpacer", "AddStat", "AddProgress", "AddImage", "AddTextArea", "AddLog",
}) do
    local original = Section[methodName]
    Section[methodName] = function(self, options)
        local firstConnection = #self.Window._connections + 1
        local control = original(self, options)
        local ownedConnections = {}
        for index = firstConnection, #self.Window._connections do
            table.insert(ownedConnections, self.Window._connections[index])
        end
        control = enrichControl(control, self, options, ownedConnections, methodName)
        if control then
            -- Composite controls build their children against a partial section
            -- that only carries Container/Window; the list is created on demand so
            -- those nested controls land somewhere harmless.
            if type(self.Controls) ~= "table" then self.Controls = {} end
            if not table.find(self.Controls, control) then
                table.insert(self.Controls, control)
            end
            if not control._layoutOrder then
                self._nextOrder = (self._nextOrder or 0) + 1
                control._layoutOrder = self._nextOrder
            end
            -- Same reasoning as tabs/sections: without an explicit LayoutOrder
            -- the section's UIListLayout would sort controls by Name.
            if control.Instance then
                control.Instance.LayoutOrder = control._layoutOrder
            end
            Library:_emit("controlCreated", control)
        end
        return control
    end
end

function Section:SetVisible(visible)
    if self.Frame then self.Frame.Visible = not not visible end
    return self
end

function Section:SetDisabled(disabled)
    self.Disabled = not not disabled
    if self.Container then
        for _, child in ipairs(self.Container:GetChildren()) do
            if child:IsA("GuiObject") and child:GetAttribute("BloodshotControl") then
                child:SetAttribute("BloodshotSectionDisabled", self.Disabled)
                refreshVeil(child)
            end
        end
        for _, descendant in ipairs(self.Container:GetDescendants()) do
            if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                local locked = self.Disabled or ownerDisabled(descendant, self.Container)
                descendant.Active = not locked
                descendant.Selectable = not locked
            end
        end
        for _, overlay in ipairs(self._overlays or {}) do
            for _, descendant in ipairs(overlay:GetDescendants()) do
                if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                    descendant.Active = not self.Disabled
                    descendant.Selectable = not self.Disabled
                end
            end
        end
    end
    return self
end

function Section:SetCollapsed(collapsed)
    self.Collapsed = not not collapsed
    if self.Container then self.Container.Visible = not self.Collapsed end
    -- Marker and clickability follow the state, so a collapsed section is never
    -- a dead end: the heading itself brings it back.
    local marker = (self.Collapsible or self.Collapsed) and (self.Collapsed and "+ " or "- ") or ""
    if self.Heading then self.Heading.Text = marker .. string.upper(self.Name) end
    if self.CollapseButton then
        self.CollapseButton.Active = self.Collapsible or self.Collapsed
        self.CollapseButton.Selectable = self.CollapseButton.Active
    end
    return self
end

function Section:ToggleCollapsed()
    return self:SetCollapsed(not self.Collapsed)
end

function Section:SetTitle(name)
    if not self.Frame then return self end
    self.Name = tostring(name or "")
    self.Frame.Name = self.Name
    local marker = (self.Collapsible or self.Collapsed) and (self.Collapsed and "+ " or "- ") or ""
    if self.Heading then self.Heading.Text = marker .. string.upper(self.Name) end
    return self
end

function Section:SetDescription(value)
    if not self.Frame then return self end
    if value == nil or value == "" then
        if self.DescriptionLabel then self.DescriptionLabel.Visible = false end
        if self.Heading then self.Heading.Size = UDim2.new(1, 0, 0, 24) end
        return self
    end
    if not self.DescriptionLabel then
        self.DescriptionLabel = text(self.Frame, tostring(value), 10, "MutedText", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0.45, 0, 0, 24),
            TextXAlignment = Enum.TextXAlignment.Right,
        })
        if self.CollapseButton then self.DescriptionLabel.ZIndex = 1 end
    end
    self.DescriptionLabel.Visible = true
    self.DescriptionLabel.Text = tostring(value)
    if self.Heading then self.Heading.Size = UDim2.new(0.55, 0, 0, 24) end
    return self
end

function Section:Destroy()
    if not self.Frame then return end
    for _, overlay in ipairs(self._overlays or {}) do
        if overlay and overlay.Parent then overlay:Destroy() end
    end
    self._overlays = nil
    for index = #self.Controls, 1, -1 do
        local control = self.Controls[index]
        if control and control.Destroy then control:Destroy() end
    end
    table.clear(self.Controls)
    if self.Tab then
        local index = table.find(self.Tab.Sections, self)
        if index then table.remove(self.Tab.Sections, index) end
    end
    self.Frame:Destroy()
    self.Frame = nil
    self.Container = nil
end

function Tab:SetVisible(visible)
    visible = not not visible
    self.Button.Visible = visible
    if not visible and self.Window.ActiveTab == self then
        for _, candidate in ipairs(self.Window.Tabs) do
            if candidate ~= self and candidate.Button.Visible then
                self.Window:SelectTab(candidate)
                break
            end
        end
    end
    return self
end

function Tab:SetDisabled(disabled)
    self.Disabled = not not disabled
    self.Button.Active = not self.Disabled
    self.Button.Selectable = not self.Disabled
    self.Button.TextTransparency = self.Disabled and 0.6 or 0
    if self.Badge then
        self.Badge.BackgroundTransparency = self.Disabled and 0.75 or 0.15
    end
    return self
end

-- Live count on the tab button, e.g. Tab:SetBadge("17 on"). nil or "" clears it.
function Tab:SetBadge(value)
    -- `value == nil and nil or tostring(value)` would yield the *string* "nil":
    -- the `and nil` branch falls through to the `or` fallback.
    if value == nil or value == "" then
        value = nil
    else
        value = tostring(value)
    end
    self.BadgeValue = value
    if not self.Badge then
        if not value then return self end
        local badge = new("Frame", {
            Name = "Badge",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Parent = self.Decor,
        })
        bindTheme(badge, "BackgroundColor3", "Accent")
        corner(badge, 999)
        local inner = new("UIPadding", {
            PaddingLeft = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            PaddingTop = UDim.new(0, 1),
            PaddingBottom = UDim.new(0, 1),
            Parent = badge,
        })
        local label = text(badge, "", 9, "Text", {
            Size = UDim2.fromOffset(0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            TextScaled = false,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextSize = 9,
        })
        self.Badge = badge
        self.BadgePadding = inner
        self.BadgeLabel = label
    end
    self.Badge.Visible = value ~= nil
    if value ~= nil then self.BadgeLabel.Text = value end
    -- The badge sits over the right edge, so the label's text area has to give
    -- up that space or a long tab name runs underneath it.
    local reserve = 0
    if value ~= nil then
        reserve = math.ceil(measureText(value, 9, Library.Theme.Font or Enum.Font.Gotham, 1000).X) + 12 + 10 + 6
        self.Badge.BackgroundTransparency = self.Disabled and 0.75 or 0.15
    end
    self.ButtonPadding.PaddingRight = UDim.new(0, reserve)
    self.Decor.Size = UDim2.new(1, self.PadLeft + reserve, 1, 0)
    return self
end

function Tab:GetBadge()
    return self.BadgeValue
end

function Tab:SetName(name)
    if not self.Button then return self end
    name = tostring(name or "")
    local window = self.Window
    if window._tabByName[self.Name] == self then window._tabByName[self.Name] = nil end
    self.Name = name
    window._tabByName[name] = self
    self.Button.Name = name
    self.Button.Text = name
    self.Page.Name = name
    return self
end

function Tab:SetIcon(icon)
    if not self.Button then return self end
    local asset
    if icon ~= nil and icon ~= false and icon ~= "" then
        asset = iconAsset(icon) or tostring(icon)
    end
    if self.Image then
        self.Image:Destroy()
        self.Image = nil
    end
    local padLeft = asset and 34 or 10
    if asset then
        local image = new("ImageLabel", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 10, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            Image = asset,
            Parent = self.Decor,
        })
        bindThemeState(image, function()
            image.ImageColor3 = self.Window.ActiveTab == self and Library.Theme.Accent or Library.Theme.MutedText
        end)
        self.Image = image
    end
    self.Icon = asset
    self.PadLeft = padLeft
    self.ButtonPadding.PaddingLeft = UDim.new(0, padLeft)
    self.Decor.Position = UDim2.fromOffset(-padLeft, 0)
    self.Decor.Size = UDim2.new(1, padLeft + self.ButtonPadding.PaddingRight.Offset, 1, 0)
    return self
end

function Tab:ClearBadge()
    return self:SetBadge(nil)
end

function Tab:Search(query)
    query = string.lower(tostring(query or ""))
    if query == "" then
        -- Put back exactly what was on screen when the search started; sections
        -- hidden or rows cleared by hand earlier stay hidden.
        local snapshot = self._searchSnapshot
        self._searchSnapshot = nil
        local visibleCount = 0
        if snapshot then
            for _, entry in ipairs(snapshot.sections) do
                if entry.frame.Parent then entry.frame.Visible = entry.visible end
            end
            for _, section in ipairs(self.Sections) do
                section:Search("")
            end
            for _, section in ipairs(self.Sections) do
                if section.Frame.Visible then visibleCount += 1 end
            end
        else
            for _, section in ipairs(self.Sections) do
                if section.Frame.Visible then visibleCount += 1 end
            end
        end
        return visibleCount
    end

    if not self._searchSnapshot then
        local sections = {}
        for _, section in ipairs(self.Sections) do
            sections[#sections + 1] = { frame = section.Frame, visible = section.Frame.Visible }
        end
        self._searchSnapshot = { sections = sections }
    end

    local visibleCount = 0
    for _, section in ipairs(self.Sections) do
        snapshotSearch(section)
        local sectionMatch = string.find(string.lower(section.Name), query, 1, true) ~= nil
        local sectionVisible = sectionMatch
        local hasSearch = false
        for _, control in ipairs(collectSearchable(section)) do
            if control:GetAttribute("BloodshotSearch") == true then
                hasSearch = true
                break
            end
        end
        if not sectionMatch then
            -- Section name alone is not enough: a matching control anywhere in
            -- the section keeps that section on screen with just its hits.
            for _, control in ipairs(collectSearchable(section)) do
                if control:GetAttribute("BloodshotSearch") ~= true then
                    if string.find(string.lower(control.Name), query, 1, true) ~= nil then
                        sectionVisible = true
                        break
                    end
                end
            end
        end
        -- A section hosting a search bar never hides while searching, so the
        -- bar itself stays on screen.
        if hasSearch then
            sectionVisible = true
        end
        if sectionMatch then
            for _, control in ipairs(collectSearchable(section)) do
                if control:GetAttribute("BloodshotSearch") == true then
                    control.Visible = true
                else
                    local blocked = control:GetAttribute("BloodshotDependencyMet") == false
                        or (control.Parent and control.Parent.Parent
                            and control.Parent.Parent:GetAttribute("BloodshotDependencyMet") == false)
                    control.Visible = not blocked
                end
            end
        else
            filterSection(section, query)
        end
        section.Frame.Visible = sectionVisible
        if sectionVisible then visibleCount += 1 end
    end
    return visibleCount
end

function Tab:EnableReorder(enabled)
    enabled = not not enabled
    self.Window._reorderEnabled = enabled
    for _, section in ipairs(self.Sections) do
        section:EnableReorder(enabled)
    end
    return enabled
end

-- LayoutOrder on the section frames is the source of truth; keep the array in step.
function Tab:SyncSectionOrder()
    local list = {}
    for _, section in ipairs(self.Sections) do
        list[#list + 1] = section
    end
    table.sort(list, function(a, b)
        local left = (a.Frame and a.Frame.LayoutOrder) or 0
        local right = (b.Frame and b.Frame.LayoutOrder) or 0
        if left == right then return a.Name < b.Name end
        return left < right
    end)
    for position, section in ipairs(list) do
        self.Sections[position] = section
    end
    return self.Sections
end

function Tab:GetSectionOrder()
    local names = {}
    for _, section in ipairs(self.Sections) do
        names[#names + 1] = section.Name
    end
    return names
end

function Tab:MoveSection(section, index)
    if type(section) == "string" then
        for _, candidate in ipairs(self.Sections) do
            if candidate.Name == section then section = candidate break end
        end
    end
    if type(section) ~= "table" or not section.MoveTo then return false end
    return section:MoveTo(index)
end

function Tab:Destroy()
    if not self.Button then return end
    local window = self.Window
    for index = #self.Sections, 1, -1 do self.Sections[index]:Destroy() end
    local wasActive = window.ActiveTab == self
    if wasActive then window.ActiveTab = nil end
    if window._tabByName[self.Name] == self then window._tabByName[self.Name] = nil end
    local index = table.find(window.Tabs, self)
    if index then table.remove(window.Tabs, index) end
    self.Button:Destroy()
    self.Page:Destroy()
    self.Button = nil
    self.Page = nil
    if wasActive then
        for _, candidate in ipairs(window.Tabs) do
            if candidate.Button and candidate.Button.Visible then window:SelectTab(candidate); break end
        end
    end
end

local Window = {}
Window.__index = Window

-- Per-window convenience wrapper. Handlers always receive the window as their
-- first argument, so the same handler can serve several windows.
-- No extra subscribe-time args are stored: every event this window raises goes
-- through Window:_emit / Library:_emit("...", self, ...), so the emitter already
-- supplies the window. Storing `self` here as well would hand handlers
-- (window, window, payload).
function Window:_subscribe(event, callback)
    return Library:_subscribe(event, callback)
end

function Window:_emit(event, ...)
    return Library:_emit(event, self, ...)
end

function Window:On(event, callback)
    return self:_subscribe(event, callback)
end

function Window:SetVisible(visible)
    if self._destroyed then return end
    visible = not not visible
    if self.Visible == visible then return end
    self.Visible = visible
    if self.Visible then
        self.Root.Visible = true
        self._scale.Scale = 0.9
        self.Root.BackgroundTransparency = 1
        tween(self._scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
        tween(self.Root, 0.2, { BackgroundTransparency = self._bgTransparency })
    else
        local animation = tween(self._scale, 0.2, { Scale = 0.94 })
        tween(self.Root, 0.2, { BackgroundTransparency = 1 })
        animation.Completed:Connect(function()
            if not self.Visible and self.Root then self.Root.Visible = false end
        end)
    end
    if self._geometryWatcher then self._geometryWatcher.Dirty = true end
    self:_applyBlur()
    Library:_emit("windowVisibility", self, visible)
end

-- Fires whenever the active tab changes. Replaces polling window.ActiveTab.
-- Handlers get (window, tab, previousTab).
function Window:OnTabChanged(callback)
    return self:_subscribe("tabChanged", callback)
end

-- Fires when the window is shown or hidden, so overlays can mirror its state.
-- Handlers get (window, visible).
function Window:OnVisibilityChanged(callback)
    return self:_subscribe("windowVisibility", callback)
end

function Window:GetSelectedTab()
    return self.ActiveTab
end

function Window:GetTab(name)
    return self._tabByName[tostring(name)]
end

function Window:GetTabOrder()
    local names = {}
    for _, child in ipairs(orderedChildren(self.TabList)) do
        if child:IsA("GuiButton") then
            names[#names + 1] = child.Name
        end
    end
    return names
end

function Window:MoveTab(tab, index)
    if type(tab) == "string" then tab = self._tabByName[tab] end
    if not tab then return false end
    return reorderList(self.TabList, tab.Button, index)
end

function Window:SetTabsReorderable(enabled)
    -- Drag-to-reorder tabs was removed; kept as a no-op so existing scripts
    -- calling SetTabsReorderable(true) do not error. Index reordering via
    -- MoveTab still works.
    self._tabsReorderable = false
    return false
end

function Window:SetPosition(position)
    if self._destroyed or typeof(position) ~= "UDim2" then return false end
    self.Root.Position = position
    return true
end

function Window:SetSize(size)
    if self._destroyed or typeof(size) ~= "UDim2" then return false end
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
    local width = math.max(self._minimumSize.X, viewport.X * size.X.Scale + size.X.Offset)
    local height = math.max(self._minimumSize.Y, viewport.Y * size.Y.Scale + size.Y.Offset)
    self._size = UDim2.fromOffset(width, height)
    if not self.Minimized then self.Root.Size = self._size end
    return true
end

-- Accepts a single EnumItem (old behaviour), a string like "LeftShift", or a
-- combo descriptor so Shift+P-style toggles no longer need a hand-rolled
-- UserInputService handler.
--   window:SetToggleKey("LeftShift+P")            -- chord
--   window:SetToggleKey({ "LeftControl", "M" })   -- any-of-modifier chord
--   window:SetToggleKey({ Key = "P", Modifiers = {"LeftShift"}, Exact = true })
local function normalizeModifier(key)
    if type(key) == "string" then
        local match = key:match("^Enum%.KeyCode%.(.+)$")
        key = match or key
        -- Unknown names must not throw out of window creation.
        local ok, code = pcall(function() return Enum.KeyCode[key] end)
        if not ok then return Enum.KeyCode.Unknown end
        return code or Enum.KeyCode.Unknown
    end
    if typeof(key) == "EnumItem" then return key end
    return Enum.KeyCode.Unknown
end

-- `combo` rather than `spec`: a parameter named spec would shadow the global
-- type() used throughout this function.
local function parseComboKey(combo)
    if combo == nil then return nil end
    if typeof(combo) == "EnumItem" then
        return { Keys = { combo }, Modifiers = {}, RequireAll = true }
    end
    if type(combo) == "string" then
        local parts = {}
        for part in string.gmatch(combo, "[^+]+") do
            local resolved = normalizeModifier((string.gsub(part, "^%s*(.-)%s*$", "%1")))
            if resolved == Enum.KeyCode.Unknown then return nil end
            parts[#parts + 1] = resolved
        end
        if #parts == 0 then return nil end
        return { Keys = parts, Modifiers = {}, RequireAll = true, Label = combo }
    end
    if type(combo) ~= "table" then return nil end
    local modifiers = {}
    for _, modifier in ipairs(type(combo.Modifiers) == "table" and combo.Modifiers or {}) do
        local resolved = normalizeModifier(modifier)
        if resolved ~= Enum.KeyCode.Unknown then modifiers[#modifiers + 1] = resolved end
    end
    local keys = {}
    local rawKeys = combo.Keys
    if rawKeys == nil then rawKeys = combo.Key or combo.KeyCode end
    if rawKeys == nil and combo[1] ~= nil then
        -- A bare array is a chord: { "LeftControl", "M" }.
        rawKeys = combo
    end
    if rawKeys ~= nil then
        for _, entry in ipairs(type(rawKeys) == "table" and rawKeys or { rawKeys }) do
            local resolved = normalizeModifier(entry)
            if resolved ~= Enum.KeyCode.Unknown then keys[#keys + 1] = resolved end
        end
    end
    if #keys == 0 then return nil end
    return {
        Keys = keys,
        Modifiers = modifiers,
        -- Any = true means holding one of the listed keys toggles; the default
        -- requires the whole set pressed together as a chord.
        RequireAll = combo.Any ~= true,
        Exact = combo.Exact == true,
        Label = combo.Label,
    }
end

local function comboLabel(combo)
    if not combo then return nil end
    if combo.Label then return combo.Label end
    local parts = {}
    for _, modifier in ipairs(combo.Modifiers) do parts[#parts + 1] = modifier.Name end
    for _, key in ipairs(combo.Keys) do parts[#parts + 1] = key.Name end
    return table.concat(parts, "+")
end

local function comboMatches(combo, input, held)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return false end
    local pressed = input.KeyCode
    local matched = false
    for _, key in ipairs(combo.Keys) do
        if pressed == key then matched = true break end
    end
    if not matched then return false end
    -- The key being pressed counts as held even if the tracker has not seen it
    -- yet, so a chord never depends on which InputBegan handler runs first.
    local function isDown(key)
        return key == pressed or held[key] == true
    end
    if #combo.Keys > 1 and combo.RequireAll then
        for _, key in ipairs(combo.Keys) do
            if not isDown(key) then return false end
        end
    end
    -- Modifiers are alternatives: holding any one of them satisfies the chord.
    if #combo.Modifiers > 0 then
        local satisfied = false
        for _, modifier in ipairs(combo.Modifiers) do
            if isDown(modifier) then satisfied = true break end
        end
        if not satisfied then return false end
    end
    if combo.Exact then
        for other, down in pairs(held) do
            if down and other ~= pressed then
                local allowed = false
                for _, key in ipairs(combo.Keys) do
                    if other == key then allowed = true break end
                end
                if not allowed then
                    for _, modifier in ipairs(combo.Modifiers) do
                        if other == modifier then allowed = true break end
                    end
                end
                if not allowed then return false end
            end
        end
    end
    return true
end

-- Tracks which keyboard keys are down so chord matching has state to read.
local heldKeys = {}

-- Holds a chord state so SetToggleKey combos can be matched without the
-- signal. Same logic comboMatches uses on a real InputBegan.
local function withHeldKeys(combo, key, modifiers, input)
    local snapshot = {}
    for held in pairs(heldKeys) do snapshot[held] = true end
    for _, modifier in ipairs(modifiers or {}) do
        local resolved = normalizeModifier(modifier)
        heldKeys[resolved] = true
    end
    if key ~= nil then
        local resolved = normalizeModifier(key)
        if resolved == Enum.KeyCode.Unknown then
            heldKeys = snapshot
            return false
        end
        heldKeys[resolved] = true
    end
    local ok, matched = pcall(comboMatches, combo,
        input or { UserInputType = Enum.UserInputType.Keyboard,
                   KeyCode = normalizeModifier(key) },
        heldKeys)
    heldKeys = snapshot
    return ok and matched or false
end

function Library:IsKeyHeld(key)
    return heldKeys[normalizeModifier(key)] == true
end

function Library:GetHeldKeys()
    local list = {}
    for key, down in pairs(heldKeys) do
        if down then list[#list + 1] = key end
    end
    table.sort(list, function(a, b) return a.Name < b.Name end)
    return list
end

function Window:SetToggleKey(input)
    local combo = parseComboKey(input)
    if not combo then
        return false, "Toggle key must be an EnumItem, a key name, or a combo descriptor"
    end
    self._toggleCombo = combo
    self._toggleKey = combo.Keys[1]
    return true, comboLabel(combo)
end

function Window:GetToggleKey()
    return self._toggleCombo and comboLabel(self._toggleCombo) or nil
end

function Window:IsToggleCombo()
    return self._toggleCombo ~= nil
end

-- Would this combo fire right now, given the keys/mods currently held? Lets a
-- script (or a test) check a chord without waiting for a real key press.
function Window:MatchesToggleKey(key, modifiers)
    if not self._toggleCombo then return false end
    return withHeldKeys(self._toggleCombo, key, modifiers)
end

function Window:SetTitle(title, subtitle)
    if self._titleLabel then self._titleLabel.Text = tostring(title or "") end
    if subtitle ~= nil and self._subtitleLabel then self._subtitleLabel.Text = tostring(subtitle) end
    return self
end

function Window:SetIcon(icon)
    if self._destroyed then return self end
    self._iconSource = (icon ~= nil and icon ~= false and icon ~= "") and icon or nil
    if self._iconInstance then
        self._iconInstance:Destroy()
        self._iconInstance = nil
    end
    local shift = 0
    if icon ~= nil and icon ~= false and icon ~= "" then
        local asset = iconAsset(icon)
        if asset then
            self._iconInstance = new("ImageLabel", {
                Name = "Icon",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 18, 0, self._topbarHeight / 2),
                Size = UDim2.fromOffset(26, 26),
                Image = asset,
                Parent = self.Topbar,
            })
        else
            self._iconInstance = text(self.Topbar, tostring(icon), 20, "Accent", {
                Name = "Icon",
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 18, 0, self._topbarHeight / 2),
                Size = UDim2.fromOffset(26, 26),
                TextXAlignment = Enum.TextXAlignment.Center,
                Font = Enum.Font.GothamBold,
            })
        end
        shift = 36
    end
    self._titleLabel.Position = UDim2.fromOffset(18 + shift, self._titleTop)
    self._titleLabel.Size = UDim2.new(1, -(140 + shift), 0, 22)
    self._subtitleLabel.Position = UDim2.fromOffset(18 + shift, self._titleTop + 22)
    self._subtitleLabel.Size = UDim2.new(1, -(140 + shift), 0, 16)
    return self
end

function Window:SetFooter(value)
    local label = self._footerLabel
    if self._destroyed or not label then return self end
    local horizontal = self._layout.SidebarHorizontal
    if value == false then
        label.Visible = false
        self._footerText = false
        if not horizontal then
            self.TabList.Size = UDim2.new(1, -(self._layout.SidebarPadding * 2), 1, -24)
        end
    else
        label.Visible = true
        if value ~= nil then
            label.Text = tostring(value)
            self._footerText = tostring(value)
        end
        if not horizontal then
            self.TabList.Size = UDim2.new(1, -(self._layout.SidebarPadding * 2), 1, -60)
        end
    end
    return self
end

function Window:SetDraggable(enabled)
    self._draggable = enabled ~= false
    return self._draggable
end

function Window:SetOpacity(value)
    value = tonumber(value)
    if self._destroyed or not value or value ~= value then return false end
    self._opacity = math.clamp(value, 0.05, 1)
    self._bgTransparency = 1 - self._opacity
    if self.Visible and self.Root then
        self.Root.BackgroundTransparency = self._bgTransparency
    end
    return true
end

function Window:GetOpacity()
    return self._opacity
end

function Window:_applyBlur()
    if self._destroyed then return end
    local active = self._blurSize > 0 and self.Visible and not self.Minimized
    if active then
        if not self._blur then
            local ok, effect = pcall(function()
                return new("BlurEffect", {
                    Name = "BloodshotBlur",
                    Size = 0,
                    Parent = game:GetService("Lighting"),
                })
            end)
            if ok then self._blur = effect end
        end
        if self._blur then
            self._blur.Enabled = true
            tween(self._blur, 0.25, { Size = self._blurSize })
        end
    elseif self._blur then
        local effect = self._blur
        local animation = tween(effect, 0.2, { Size = 0 })
        if animation then
            animation.Completed:Connect(function()
                if self._blur == effect and not (self._blurSize > 0 and self.Visible and not self.Minimized) then
                    effect.Enabled = false
                end
            end)
        else
            effect.Enabled = false
        end
    end
end

function Window:SetBlur(size)
    if size == true then size = 12 end
    size = tonumber(size) or 0
    if size ~= size then size = 0 end
    self._blurSize = math.clamp(size, 0, 56)
    self:_applyBlur()
    return self._blurSize
end

function Window:SetToggleButton(config)
    local previous = self._toggleButton
    if previous then
        for _, connection in ipairs(previous.Connections) do
            if connection.Connected then connection:Disconnect() end
        end
        previous.Instance:Destroy()
        self._toggleButton = nil
    end
    if self._destroyed or not config then return false end
    if type(config) ~= "table" then config = {} end
    local size = math.clamp(tonumber(config.Size) or 44, 28, 96)
    local button = new("TextButton", {
        Name = "ToggleButton",
        Position = typeof(config.Position) == "UDim2" and config.Position or UDim2.new(0, 14, 0.5, -size / 2),
        Size = UDim2.fromOffset(size, size),
        AutoButtonColor = false,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = config.Icon and "" or tostring(config.Text or "UI"),
        TextSize = 14,
        ZIndex = 150,
        Parent = ScreenGui,
    })
    bindTheme(button, "BackgroundColor3", "Surface")
    bindTheme(button, "TextColor3", "Accent")
    corner(button, config.Round == true and size / 2 or 12)
    stroke(button, Library.Theme.Border, 1, 0.1, "Border")
    local asset = config.Icon and iconAsset(config.Icon)
    if asset then
        new("ImageLabel", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(size * 0.55, size * 0.55),
            Image = asset,
            Parent = button,
        })
    end
    local connections = {}
    local function track(connection)
        connections[#connections + 1] = connection
        return connection
    end
    local dragging, moved = false, false
    local origin, startAbsolute, startPosition
    track(button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            origin = input.Position
            startAbsolute = button.AbsolutePosition
            startPosition = button.Position
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = input.Position - origin
        if not moved and delta.Magnitude > 6 then moved = true end
        if moved and config.Draggable ~= false then
            local viewport = ScreenGui.AbsoluteSize
            local x = math.clamp(startAbsolute.X + delta.X, 0, math.max(0, viewport.X - size))
            local y = math.clamp(startAbsolute.Y + delta.Y, 0, math.max(0, viewport.Y - size))
            button.Position = UDim2.new(
                startPosition.X.Scale, x - startPosition.X.Scale * viewport.X,
                startPosition.Y.Scale, y - startPosition.Y.Scale * viewport.Y
            )
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(button.Activated:Connect(function()
        if moved then
            moved = false
            return
        end
        self:Toggle()
    end))
    local state = { Instance = button, Connections = connections }
    if config.HideWhenOpen == true then
        button.Visible = not self.Visible
        local handle = self:OnVisibilityChanged(function(window, visible)
            if window == self and button.Parent then button.Visible = not visible end
        end)
        track({ Connected = true, Disconnect = function(connection)
            connection.Connected = false
            handle:Unbind()
        end })
    end
    self._toggleButton = state
    return true
end

function Window:SetToggleButtonVisible(visible)
    if self._toggleButton then
        self._toggleButton.Instance.Visible = not not visible
        return true
    end
    return false
end

-- Persistence helpers used by SaveGeometry/LoadGeometry.
function Window:GetGeometry()
    if self._destroyed or not self.Root then return nil end
    local geometry = {
        Position = self.Root.Position,
        Size = self._size,
        Minimized = self.Minimized,
        Visible = self.Visible,
        Tab = self.ActiveTab and self.ActiveTab.Name or nil,
    }
    for _, tab in ipairs(self.Tabs) do
        if tab.Scroll and tab.Page then
            geometry.Scroll = geometry.Scroll or {}
            geometry.Scroll[tab.Name] = tab.Page.CanvasPosition
        end
    end
    return geometry
end

function Window:SetGeometry(geometry)
    if self._destroyed or type(geometry) ~= "table" then return false end
    if typeof(geometry.Size) == "UDim2" then
        self:SetSize(geometry.Size)
    end
    if typeof(geometry.Position) == "UDim2" then
        self.Root.Position = geometry.Position
    end
    if geometry.Tab then
        local tab = self._tabByName[tostring(geometry.Tab)]
        if tab then self:SelectTab(tab) end
    end
    if geometry.Minimized == true then
        self:SetMinimized(true)
    elseif geometry.Minimized == false and self.Minimized then
        self:SetMinimized(false)
    end
    if geometry.Visible ~= nil then
        self:SetVisible(geometry.Visible == true)
    end
    if type(geometry.Scroll) == "table" then
        for name, offset in pairs(geometry.Scroll) do
            local tab = self._tabByName[tostring(name)]
            if tab and tab.Page then
                if typeof(offset) == "UDim2" then
                    offset = Vector2.new(offset.X.Offset, offset.Y.Offset)
                end
                if typeof(offset) == "Vector2" then
                    tab.Page.CanvasPosition = offset
                end
            end
        end
    end
    return true
end

-- Opt-in automatic persistence. Marks the window dirty whenever its geometry,
-- active tab, minimize state or visibility changes, then writes once the user
-- stops interacting, so no polling loop over ActiveTab is needed.
function Window:EnableGeometryPersistence(options)
    options = type(options) == "table" and options or {}
    if self._geometryWatcher then
        self._geometryWatcher.Disconnect()
        self._geometryWatcher = nil
    end
    if options == false or options.Enabled == false then
        return false, "Geometry persistence disabled"
    end
    local delay = tonumber(options.Delay) or 1.5
    if not delay or delay ~= delay or delay < 0 then delay = 1.5 end
    local pending
    local function flush()
        pending = nil
        Library:SaveGeometry()
    end
    local function markDirty()
        if not self._geometryWatcher then return end
        self._geometryWatcher.Dirty = true
        if pending then task.cancel(pending) end
        pending = task.delay(delay, flush)
    end
    local connections = {}
    local function watch(object, property)
        local connection = object:GetPropertyChangedSignal(property):Connect(markDirty)
        table.insert(connections, connection)
    end
    watch(self.Root, "Position")
    watch(self.Root, "Size")
    -- Held on the watcher so Disable can drop them: these live on the library-wide
    -- bus, so an enable/disable cycle that did not unbind would leave a dead
    -- handler behind forever.
    local busHandles = {
        self:_subscribe("tabChanged", markDirty),
        self:_subscribe("windowVisibility", markDirty),
    }
    self._geometryWatcher = {
        Dirty = false,
        MarkDirty = markDirty,
        Flush = function()
            if pending then
                task.cancel(pending)
                pending = nil
            end
            flush()
        end,
        Disconnect = function()
            if pending then
                task.cancel(pending)
                pending = nil
            end
            for _, handle in ipairs(busHandles) do handle:Unbind() end
            table.clear(busHandles)
            for _, connection in ipairs(connections) do
                if connection.Connected then connection:Disconnect() end
            end
            table.clear(connections)
        end,
    }
    if options.Load ~= false then
        Library:LoadGeometry()
    end
    return true
end

function Window:DisableGeometryPersistence()
    if not self._geometryWatcher then return false end
    self._geometryWatcher.Disconnect()
    self._geometryWatcher = nil
    return true
end

function Window:IsGeometryPersistenceEnabled()
    return self._geometryWatcher ~= nil
end

function Window:SaveGeometryNow()
    if self._geometryWatcher then
        return self._geometryWatcher.Flush()
    end
    return Library:SaveGeometry()
end

function Window:Toggle()
    self:SetVisible(not self.Visible)
end

-- Installs (or with nil, removes) the close handler. Returning false from it
-- keeps the window open, which is what a "Keep Raining?" confirmation needs.
function Window:SetOnClose(callback)
    if callback ~= nil and type(callback) ~= "function" then
        return false, "OnClose must be a function"
    end
    self._onClose = callback
    return true
end

-- Runs the close flow. CloseRequest decides *whether* to close (a confirmation
-- dialog that resolves later calls RequestClose again); OnClose decides what
-- closing means and runs after the window has actually closed.
function Window:RequestClose()
    if self._destroyed then return false end
    if self._closeRequest then
        local handled = safeCall(self._closeRequest, self)
        if handled ~= false and handled ~= true then
            -- The handler took ownership and will call RequestClose again.
            return false
        end
        if handled == false then
            return false
        end
    end
    self:_finishClose()
    return true
end

function Window:_finishClose()
    if self._destroyed then return end
    local onClose = self._onClose
    if self._destroyOnClose then
        self:Destroy()
    else
        self:SetVisible(false)
    end
    if onClose then
        safeCall(onClose, self)
    end
    Library:_emit("windowClosed", self)
end

-- The window's intended pixel size, independent of any in-flight scale tween.
function Window:_TargetSize()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.zero
    local size = self._size or UDim2.fromOffset(0, 0)
    return Vector2.new(
        viewport.X * size.X.Scale + size.X.Offset,
        viewport.Y * size.Y.Scale + size.Y.Offset
    )
end

function Window:SetMinimized(minimized)
    if self._destroyed or self._minimizeAnimating then return end
    minimized = not not minimized
    if self.Minimized == minimized then return end
    self.Minimized = minimized
    self._minimizeAnimating = true

    if minimized then
        self.Sidebar.Visible = false
        self.Pages.Visible = false
        self.TopbarSeparator.Visible = false
        if self.ResizeHandle then self.ResizeHandle.Visible = false end
        -- Target size resolved from the viewport, not the live AbsoluteSize: a
        -- window still playing its open tween reports a scaled size and would
        -- settle off-centre.
        local target = self:_TargetSize()
        self._minimizeOffsetY = math.max(0, (target.Y - self._topbarHeight) * 0.5)
        local minimizedWidth = math.min(target.X, self._minimizedWidth)
        self._sizeConstraint.MinSize = Vector2.new(minimizedWidth, self._topbarHeight)
        local animation = tween(self.Root, 0.24, {
            Position = UDim2.new(
                self.Root.Position.X.Scale,
                self.Root.Position.X.Offset,
                self.Root.Position.Y.Scale,
                self.Root.Position.Y.Offset - self._minimizeOffsetY
            ),
            Size = UDim2.fromOffset(minimizedWidth, self._topbarHeight),
        })
        animation.Completed:Connect(function()
            if not self._destroyed then
                self._minimizeAnimating = false
            end
        end)
    else
        local restoreOffset = math.max(0, (self:_TargetSize().Y - self._topbarHeight) * 0.5)
        local animation = tween(self.Root, 0.28, {
            Position = UDim2.new(
                self.Root.Position.X.Scale,
                self.Root.Position.X.Offset,
                self.Root.Position.Y.Scale,
                self.Root.Position.Y.Offset + restoreOffset
            ),
            Size = self._size,
        }, Enum.EasingStyle.Back)
        animation.Completed:Connect(function()
            if not self._destroyed and not self.Minimized then
                self._sizeConstraint.MinSize = self._minimumSize
                self.Sidebar.Visible = true
                self.Pages.Visible = true
                self.TopbarSeparator.Visible = true
                if self.ResizeHandle then self.ResizeHandle.Visible = true end
            end
            if not self._destroyed then
                self._minimizeAnimating = false
            end
        end)
    end

    if self.MinimizeButton then
        self.MinimizeButton.Text = minimized and "+" or "-"
    end
    self:_applyBlur()
end

function Window:ToggleMinimized()
    self:SetMinimized(not self.Minimized)
end

function Window:SelectTab(tab)
    if type(tab) == "string" then
        tab = self._tabByName[tab]
    end
    if not tab or tab.Disabled or self.ActiveTab == tab then return end
    local previous = self.ActiveTab
    if previous then
        previous.Page.Visible = false
        tween(self.ActiveTab.Button, 0.15, {
            BackgroundTransparency = 1,
            TextColor3 = Library.Theme.MutedText,
        })
        if self.ActiveTab.Image then
            tween(self.ActiveTab.Image, 0.15, { ImageColor3 = Library.Theme.MutedText })
        end
        self.ActiveTab.Indicator.Visible = false
    end
    self.ActiveTab = tab
    tab.Page.Visible = true
    tab.Page.Position = UDim2.fromOffset(8, 0)
    tween(tab.Page, 0.2, { Position = UDim2.fromOffset(0, 0) })
    tab.Indicator.Visible = true
    if self._layout.SidebarHorizontal then
        tab.Indicator.Size = UDim2.fromOffset(0, 3)
        tween(tab.Indicator, 0.2, { Size = UDim2.fromOffset(18, 3) }, Enum.EasingStyle.Back)
    else
        tab.Indicator.Size = UDim2.fromOffset(3, 0)
        tween(tab.Indicator, 0.2, { Size = UDim2.fromOffset(3, 18) }, Enum.EasingStyle.Back)
    end
    tween(tab.Button, 0.15, {
        BackgroundTransparency = 0.35,
        TextColor3 = Library.Theme.Text,
    })
    if tab.Image then
        tween(tab.Image, 0.15, { ImageColor3 = Library.Theme.Accent })
    end
    if self._geometryWatcher then self._geometryWatcher.Dirty = true end
    Library:_emit("tabChanged", self, tab, previous)
end

function Window:AddTab(name, icon)
    if type(name) == "table" then
        icon = name.Icon
        name = name.Name or name.Title
    end
    name = tostring(name or "Tab")
    local padLeft = icon and 34 or 10
    self._tabSeq += 1
    local button = new("TextButton", {
        Name = name,
        -- See Tab:AddSection: creation order must win over alphabetical order.
        LayoutOrder = self._tabSeq,
        BackgroundColor3 = Library.Theme.SurfaceAlt,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = self._layout.SidebarHorizontal
            and UDim2.fromOffset(self._layout.TabWidth, self._layout.TabHeight)
            or UDim2.new(1, 0, 0, self._layout.TabHeight),
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextColor3 = Library.Theme.MutedText,
        TextTransparency = 0.45,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.TabList,
    })
    constrainText(button, 9, 12)
    corner(button, 5)
    -- The label text is padded in from the left (and from the right while a
    -- badge is showing). Decor spans the whole button regardless, so the icon,
    -- indicator and badge keep positions measured from the button's own edges.
    local buttonPadding = new("UIPadding", {
        PaddingLeft = UDim.new(0, padLeft),
        Parent = button,
    })
    local decor = new("Frame", {
        Name = "Decor",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(-padLeft, 0),
        Size = UDim2.new(1, padLeft, 1, 0),
        Parent = button,
    })
    local buttonScale = new("UIScale", {
        Scale = 0.94,
        Parent = button,
    })
    local image
    if icon then
        image = new("ImageLabel", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 10, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            Image = icon,
            ImageColor3 = Library.Theme.MutedText,
            Parent = decor,
        })
    end
    local indicator = new("Frame", {
        Visible = false,
        AnchorPoint = self._layout.SidebarHorizontal and Vector2.new(0.5, 1) or Vector2.new(0, 0.5),
        Position = self._layout.SidebarHorizontal
            and UDim2.new(0.5, 0, 1, 0)
            or UDim2.new(0, 0, 0.5, 0),
        Size = self._layout.SidebarHorizontal and UDim2.fromOffset(18, 3) or UDim2.fromOffset(3, 18),
        BorderSizePixel = 0,
        Parent = decor,
    })
    bindTheme(indicator, "BackgroundColor3", "Accent")
    corner(indicator, 999)
    local page = new("ScrollingFrame", {
        Name = name,
        Visible = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.3,
        Parent = self.Pages,
    })
    bindTheme(page, "ScrollBarImageColor3", "Accent")
    padding(page, 0, 8, 12, 2)
    new("UIListLayout", {
        Padding = UDim.new(0, self._layout.SectionSpacing),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page,
    })
    local tab = setmetatable({
        Name = name,
        Button = button,
        Image = image,
        Indicator = indicator,
        Page = page,
        Window = self,
        Sections = {},
        Disabled = false,
        Icon = icon,
        Badge = nil,
        BadgeValue = nil,
        ButtonPadding = buttonPadding,
        Decor = decor,
        PadLeft = padLeft,
    }, Tab)
    bindThemeState(button, function()
        button.BackgroundColor3 = Library.Theme.SurfaceAlt
        button.TextColor3 = self.ActiveTab == tab and Library.Theme.Text or Library.Theme.MutedText
    end)
    if image then
        bindThemeState(image, function()
            image.ImageColor3 = self.ActiveTab == tab and Library.Theme.Accent or Library.Theme.MutedText
        end)
    end
    table.insert(self.Tabs, tab)
    self._tabByName[name] = tab
    tween(buttonScale, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
    tween(button, 0.24, { TextTransparency = 0 })
    connect(button.MouseEnter, function()
        tween(buttonScale, 0.14, { Scale = 1.025 })
        if self.ActiveTab ~= tab then
            tween(button, 0.14, {
                BackgroundTransparency = 0.72,
                TextColor3 = Library.Theme.Text,
            })
            if image then tween(image, 0.14, { ImageColor3 = Library.Theme.Accent }) end
        end
    end, self._connections)
    connect(button.MouseLeave, function()
        tween(buttonScale, 0.14, { Scale = 1 })
        if self.ActiveTab ~= tab then
            tween(button, 0.14, {
                BackgroundTransparency = 1,
                TextColor3 = Library.Theme.MutedText,
            })
            if image then tween(image, 0.14, { ImageColor3 = Library.Theme.MutedText }) end
        end
    end, self._connections)
    connect(button.Activated, function(input)
        if Library:_isObscured(self, input and input.Position) then
            return
        end
        self:SelectTab(tab)
    end, self._connections)
    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
end

function Window:AddTabGroup(name)
    if self._destroyed then return nil end
    self._tabSeq += 1
    local horizontal = self._layout.SidebarHorizontal
    local caption = string.upper(tostring(name or ""))
    local width = math.ceil(measureText(caption, 9, Enum.Font.GothamBold, 1000).X)
    local holder = new("Frame", {
        Name = "TabGroup",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = self._tabSeq,
        Size = horizontal and UDim2.fromOffset(width + 28, self._layout.TabHeight) or UDim2.new(1, 0, 0, 26),
        Parent = self.TabList,
    })
    local label = text(holder, caption, 9, "MutedText", {
        Position = UDim2.fromOffset(horizontal and 14 or 10, 0),
        Size = UDim2.new(1, horizontal and -14 or -10, 1, 0),
        Font = Enum.Font.GothamBold,
        TextYAlignment = horizontal and Enum.TextYAlignment.Center or Enum.TextYAlignment.Bottom,
    })
    label.TextTransparency = 0.1
    if horizontal then
        local line = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.new(0, 1, 0.5, 0),
            BorderSizePixel = 0,
            Parent = holder,
        })
        bindTheme(line, "BackgroundColor3", "Border")
    end
    return {
        Instance = holder,
        SetText = function(_, value)
            label.Text = string.upper(tostring(value or ""))
        end,
        Destroy = function()
            holder:Destroy()
        end,
    }
end

function Window:BringToFront()
    return Library:FocusWindow(self, false)
end

function Window:SetTheme(overrides)
    if overrides == nil then
        local restore = self._themeRestore
        self._themeOverrides = nil
        self._themeRestore = nil
        if restore and Library._focusedWindow == self then Library:SetTheme(restore) end
        return true
    end
    if type(overrides) ~= "table" then
        return false, "Theme overrides must be a table"
    end
    self._themeOverrides = copyTable(overrides)
    if Library._focusedWindow == self then
        if not self._themeRestore then
            self._themeRestore = copyTable(Library.Theme)
        end
        Library:SetTheme(self._themeOverrides)
    end
    return true
end

function Window:GetTheme()
    return copyTable(self._themeOverrides or Library.Theme)
end

function Window:GetSections()
    local list = {}
    for _, tab in ipairs(self.Tabs) do
        for _, section in ipairs(tab.Sections) do
            list[#list+1] = section
        end
    end
    return list
end

-- Walks every control holder in the window, descending into AddRow children, so
-- the counts behind #19 can be checked at any window size.
local function collectWindowControls(window)
    local controls = {}
    local function walk(node)
        for _, child in ipairs(node:GetChildren()) do
            if child:IsA("GuiObject") then
                if child:GetAttribute("BloodshotControl")
                    or child:GetAttribute("BloodshotList")
                    or child:GetAttribute("BloodshotRow") then
                    controls[#controls + 1] = child
                    -- Row children are real controls too, so they count
                    -- separately from the row that holds them.
                    if child:GetAttribute("BloodshotRow") then walk(child) end
                else
                    walk(child)
                end
            end
        end
    end
    for _, tab in ipairs(window.Tabs) do
        if tab.Page then walk(tab.Page) end
    end
    return controls
end

-- Per-window control statistics. ~130 controls in one window is the documented
-- supported ceiling, so this is how a script confirms it is under it.
function Window:ResetAll(filter, silent)
    local count = 0
    local snapshot = {}
    for index, control in ipairs(Library._specControls) do snapshot[index] = control end
    for _, control in ipairs(snapshot) do
        local flag = control.Flag
        if control._window == self and type(control.Reset) == "function"
            and (flag ~= nil or filter == nil) and flagMatches(filter, flag, control) then
            control:Reset(silent)
            count += 1
        end
    end
    return count
end

function Window:GetControlCount()
    if self._destroyed then return 0 end
    return #collectWindowControls(self)
end

function Window:GetStats()
    if self._destroyed then return nil end
    local controls = collectWindowControls(self)
    local perType = {}
    local function bump(name)
        perType[name] = (perType[name] or 0) + 1
    end
    for _, control in ipairs(controls) do
        bump(control:GetAttribute("BloodshotList") and "List"
            or control:GetAttribute("BloodshotRow") and "Row"
            or control:GetAttribute("BloodshotBaseHeight") and "Control"
            or "Other")
    end
    return {
        Controls = #controls,
        Focusables = #self:GetFocusables(),
        Tabs = #self.Tabs,
        Sections = #self:GetSections(),
        PerType = perType,
        -- Counted with # rather than select(2, ...): Roblox hands back a
        -- GetDescendants() table whose index 2 is nil, so skipping the first
        -- entry that way silently produced 0.
        Instances = self.Root and #self.Root:GetDescendants() or 0,
    }
end

function Window:GetFocusables()
    if self._destroyed then return {} end
    local list = {}
    for _, tab in ipairs(self.Tabs) do
        if tab.Button and tab.Button.Visible and tab.Button.Selectable then
            list[#list+1] = tab.Button
        end
    end
    for _, section in ipairs(self:GetSections()) do
        if section.Frame and section.Frame.Visible and not section.Collapsed then
            for _, child in ipairs(section.Container:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    for _, descendant in ipairs(child:GetDescendants()) do
                        if descendant:IsA("GuiButton") and descendant.Selectable
                            and descendant.Visible then
                            list[#list+1] = descendant
                        end
                    end
                end
            end
        end
    end
    return list
end

function Window:FocusStep(direction)
    if self._destroyed or not GuiService then return false end
    local list = self:GetFocusables()
    if #list == 0 then return false end
    local current = GuiService.SelectedObject
    local index = 0
    if current then index = table.find(list, current) or 0 end
    local step = direction or 1
    local target
    if index == 0 then
        target = step < 0 and #list or 1
    else
        target = ((index - 1 + step) % #list) + 1
    end
    local object = list[target]
    GuiService.SelectedObject = object
    return object
end

function Window:FocusNext()
    return self:FocusStep(1)
end

function Window:FocusPrevious()
    return self:FocusStep(-1)
end

function Window:SetGamepadEnabled(enabled)
    enabled = not not enabled
    for _, tab in ipairs(self.Tabs) do
        if tab.Button then tab.Button.Selectable = enabled end
    end
    for _, section in ipairs(self:GetSections()) do
        for _, child in ipairs(section.Container:GetChildren()) do
            for _, descendant in ipairs(child:GetDescendants()) do
                if descendant:IsA("GuiButton") then descendant.Selectable = enabled end
            end
        end
    end
    return enabled
end

function Window:Destroy()
    if self._destroyed then return end
    self:DisableGeometryPersistence()
    self._destroyed = true
    for _, animation in ipairs(self._backgroundTweens) do
        animation:Cancel()
    end
    table.clear(self._backgroundTweens)
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)
    for flag, setter in pairs(self._flagSetters) do
        if Library._flagSetters[flag] == setter then
            Library._flagSetters[flag] = nil
            Library._flagTypes[flag] = nil
        end
    end
    table.clear(self._flagSetters)
    if self._blur then
        self._blur:Destroy()
        self._blur = nil
    end
    self:SetToggleButton(false)
    if self.Root then
        self.Root:Destroy()
        self.Root = nil
    end
    for index, window in ipairs(Library._windows) do
        if window == self then
            table.remove(Library._windows, index)
            break
        end
    end
    for index = #Library._windowOrder, 1, -1 do
        if Library._windowOrder[index] == self then
            table.remove(Library._windowOrder, index)
        end
    end
    local wasFocused = Library._focusedWindow == self
    if wasFocused then
        Library._focusedWindow = nil
    end
    if self._themeRestore then
        local restore = self._themeRestore
        self._themeRestore = nil
        Library:SetTheme(restore)
    end
    for index = #Library._specControls, 1, -1 do
        local instance = Library._specControls[index].Instance
        if not instance or not instance.Parent then
            table.remove(Library._specControls, index)
        end
    end
    pruneThemeBindings()
    local nextWindow = Library._windowOrder[1]
    if wasFocused and nextWindow and not Library._destroyed then
        Library:FocusWindow(nextWindow)
    end
end

local function coerceUDim2(value)
    if typeof(value) == "UDim2" then
        return value
    end
    if type(value) == "table" and #value == 4 then
        local a, b, c, d = tonumber(value[1]), tonumber(value[2]), tonumber(value[3]), tonumber(value[4])
        if a and b and c and d then
            return UDim2.new(a, b, c, d)
        end
    end
    return nil
end

function Library:CreateWindow(options)
    options = options or {}
    local size = coerceUDim2(options.Size) or UDim2.fromOffset(680, 470)
    if typeof(size) ~= "UDim2"
        or (size.X.Scale == 0 and size.X.Offset <= 0)
        or (size.Y.Scale == 0 and size.Y.Offset <= 0) then
        size = UDim2.fromOffset(680, 470)
    end
    local density = self.Densities[tostring(options.Density or "Comfortable")] or {}
    local sidebarWidth = math.clamp(tonumber(options.SidebarWidth) or 158, 110, 280)
    local sidebarHeight = math.clamp(tonumber(options.SidebarHeight) or 72, 52, 130)
    local topbarHeight = math.clamp(tonumber(options.TopbarHeight) or density.TopbarHeight or 58, 44, 96)
    local contentPadding = math.clamp(tonumber(options.ContentPadding) or density.ContentPadding or 14, 6, 40)
    local sidebarPadding = math.clamp(tonumber(options.SidebarPadding) or density.SidebarPadding or 10, 4, 28)
    local tabHeight = math.clamp(tonumber(options.TabHeight) or density.TabHeight or 36, 28, 56)
    local tabWidth = math.clamp(tonumber(options.TabWidth) or 120, 72, 220)
    local tabSpacing = math.clamp(tonumber(options.TabSpacing) or density.TabSpacing or 5, 0, 20)
    local sectionSpacing = math.clamp(tonumber(options.SectionSpacing) or density.SectionSpacing or 14, 0, 32)
    local controlSpacing = math.clamp(tonumber(options.ControlSpacing) or density.ControlSpacing or 7, 0, 24)
    local sidebarSide = string.lower(tostring(options.SidebarSide or "Left"))
    local sidebarOnRight = sidebarSide == "right"
    local sidebarOnBottom = sidebarSide == "bottom"
    local sidebarOnTop = sidebarSide == "top"
    local sidebarHorizontal = sidebarOnBottom or sidebarOnTop
    local minimumInput = options.MinimumSize
    if type(minimumInput) == "table" and tonumber(minimumInput[1]) and tonumber(minimumInput[2]) then
        minimumInput = Vector2.new(tonumber(minimumInput[1]), tonumber(minimumInput[2]))
    end
    local minimumSize = typeof(minimumInput) == "Vector2"
        and minimumInput
        or Vector2.new(520, 360)
    minimumSize = Vector2.new(
        math.clamp(minimumSize.X, 240, 4096),
        math.clamp(minimumSize.Y, 180, 2160)
    )
    local minimizedWidth = math.clamp(tonumber(options.MinimizedWidth) or 320, 220, 480)
    local toggleCombo = parseComboKey(options.ToggleKey or Enum.KeyCode.Insert)
        or parseComboKey(Enum.KeyCode.Insert)
    local connections = {}
    local root = new("Frame", {
        Name = options.Title or "Bloodshot",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = coerceUDim2(options.Position) or UDim2.fromScale(0.5, 0.5),
        Size = size,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        -- A Frame with Active = false never consumes input: every click fell
        -- through to the window behind it, raising that one instead of this.
        Active = true,
        Parent = ScreenGui,
    })
    local sizeConstraint = new("UISizeConstraint", {
        MinSize = minimumSize,
        Parent = root,
    })
    bindTheme(root, "BackgroundColor3", "Background")
    gradient(root, "Background", "BackgroundGradient", 32)
    corner(root, options.CornerRadius or 10)
    stroke(root, Library.Theme.Border, 1, 0.1, "Border")
    local windowScale = new("UIScale", {
        Scale = 0.94,
        Parent = root,
    })

    local backgroundTweens = {}
    if options.AnimatedBackground == true then
        local speed = tonumber(options.AnimationSpeed) or 8
        if speed ~= speed or speed <= 0 then
            speed = 8
        end

        local shading = new("Frame", {
            Name = "AnimatedShading",
            BackgroundTransparency = 0.58,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 1,
            Parent = root,
        })
        bindTheme(shading, "BackgroundColor3", "Accent")
        corner(shading, options.CornerRadius or 10)

        local shadingGradient = new("UIGradient", {
            Color = ColorSequence.new(Color3.new(1, 1, 1)),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.35, 0.92),
                NumberSequenceKeypoint.new(0.5, 0.15),
                NumberSequenceKeypoint.new(0.65, 0.92),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Rotation = 18,
            Parent = shading,
        })

        local style = string.lower(tostring(options.AnimationStyle or "Sweep"))
        local tweenInfo
        local target
        local tweenTarget = shadingGradient
        if style == "rotate" then
            shadingGradient.Rotation = 0
            tweenInfo = TweenInfo.new(
                speed,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.InOut,
                -1,
                false
            )
            target = { Rotation = 360 }
        elseif style == "pulse" then
            shading.BackgroundTransparency = 0.78
            shadingGradient.Rotation = 90
            shadingGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.48, 0.98),
                NumberSequenceKeypoint.new(0.78, 0.72),
                NumberSequenceKeypoint.new(1, 0.08),
            })
            tweenTarget = shading
            tweenInfo = TweenInfo.new(
                speed,
                Enum.EasingStyle.Sine,
                Enum.EasingDirection.InOut,
                -1,
                true
            )
            target = { BackgroundTransparency = 0.48 }
        elseif style == "glow" then
            shading.BackgroundTransparency = 0.5
            shadingGradient.Rotation = 90
            shadingGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.48, 0.98),
                NumberSequenceKeypoint.new(0.78, 0.72),
                NumberSequenceKeypoint.new(1, 0.08),
            })
        elseif style == "vertical" then
            shadingGradient.Rotation = 90
            shadingGradient.Offset = Vector2.new(-1.1, 0)
            tweenInfo = TweenInfo.new(
                speed,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.InOut,
                -1,
                false
            )
            target = { Offset = Vector2.new(1.1, 0) }
        elseif style == "diagonal" then
            shadingGradient.Rotation = 45
            shadingGradient.Offset = Vector2.new(-1.1, 0)
            tweenInfo = TweenInfo.new(
                speed,
                Enum.EasingStyle.Sine,
                Enum.EasingDirection.InOut,
                -1,
                true
            )
            target = { Offset = Vector2.new(1.1, 0) }
        else
            shadingGradient.Offset = Vector2.new(-1.1, 0)
            tweenInfo = TweenInfo.new(
                speed,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.InOut,
                -1,
                false
            )
            target = { Offset = Vector2.new(1.1, 0) }
        end

        if tweenInfo and target then
            local backgroundTween = TweenService:Create(tweenTarget, tweenInfo, target)
            table.insert(backgroundTweens, backgroundTween)
            if not Library._reducedMotion then
                backgroundTween:Play()
            end
        end
    end

    if options.BackgroundParticles == true then
        local count = math.clamp(math.floor(tonumber(options.ParticleCount) or 24), 1, 80)
        local particleSpeed = tonumber(options.ParticleSpeed) or 12
        if particleSpeed ~= particleSpeed or particleSpeed <= 0 then
            particleSpeed = 12
        end
        local particleTransparency = math.clamp(tonumber(options.ParticleTransparency) or 0.62, 0, 1)
        local minimumSize = math.clamp(tonumber(options.ParticleMinSize) or 2, 1, 12)
        local maximumSize = math.clamp(tonumber(options.ParticleMaxSize) or 5, minimumSize, 18)
        local particleColor = typeof(options.ParticleColor) == "Color3" and options.ParticleColor or nil
        local random = Random.new()
        local particleHost = new("Frame", {
            Name = "BackgroundParticles",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 1,
            Parent = root,
        })
        corner(particleHost, options.CornerRadius or 10)

        for index = 1, count do
            local size = random:NextNumber(minimumSize, maximumSize)
            local startX = random:NextNumber(0.02, 0.98)
            local endX = math.clamp(startX + random:NextNumber(-0.12, 0.12), 0.02, 0.98)
            local particle = new("Frame", {
                Name = "Particle",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(startX, random:NextNumber(0.08, 1.08)),
                Size = UDim2.fromOffset(size, size),
                BackgroundColor3 = particleColor or Library.Theme.Accent,
                BackgroundTransparency = math.clamp(
                    particleTransparency + random:NextNumber(-0.12, 0.18),
                    0,
                    0.95
                ),
                BorderSizePixel = 0,
                ZIndex = 1,
                Parent = particleHost,
            })
            if not particleColor then
                bindTheme(particle, "BackgroundColor3", "Accent")
            end
            corner(particle, 999)

            local animation = TweenService:Create(
                particle,
                TweenInfo.new(
                    particleSpeed * random:NextNumber(0.72, 1.35),
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.InOut,
                    -1,
                    false,
                    0
                ),
                {
                    Position = UDim2.fromScale(endX, -0.08),
                    BackgroundTransparency = math.clamp(particleTransparency + 0.25, 0, 1),
                }
            )
            table.insert(backgroundTweens, animation)
            if not Library._reducedMotion then
                animation:Play()
            end
        end
    end

    local shadow = new("ImageLabel", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 46, 1, 46),
        BackgroundTransparency = 1,
        Image = "rbxassetid://6014261993",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.35,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = root,
    })

    local topbar = new("Frame", {
        Name = "Topbar",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, topbarHeight),
        Parent = root,
    })
    local titleTop = math.max(4, (topbarHeight - 40) * 0.5)
    local titleLabel = text(topbar, options.Title or "Bloodshot", 17, "Text", {
        Position = UDim2.fromOffset(18, titleTop),
        Size = UDim2.new(1, -140, 0, 22),
        Font = Enum.Font.GothamBold,
    })
    local subtitleLabel = text(topbar, options.Subtitle or ("UI Library - " .. self.Version), 10, "MutedText", {
        Position = UDim2.fromOffset(18, titleTop + 22),
        Size = UDim2.new(1, -140, 0, 16),
    })
    local closeButton
    if options.Closeable ~= false then
        closeButton = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(30, 30),
            BackgroundColor3 = Library.Theme.SurfaceAlt,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = "X",
            TextColor3 = Library.Theme.MutedText,
            TextSize = 20,
            Parent = topbar,
        })
    end
    if closeButton then
        bindTheme(closeButton, "BackgroundColor3", "SurfaceAlt")
        bindTheme(closeButton, "TextColor3", "MutedText")
        corner(closeButton, 6)
    end
    local minimize
    if options.MinimizeButton ~= false then
        minimize = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -50, 0.5, 0),
            Size = UDim2.fromOffset(30, 30),
            BackgroundColor3 = Library.Theme.SurfaceAlt,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = "-",
            TextColor3 = Library.Theme.MutedText,
            TextSize = 18,
            Parent = topbar,
        })
        bindTheme(minimize, "BackgroundColor3", "SurfaceAlt")
        bindTheme(minimize, "TextColor3", "MutedText")
        corner(minimize, 6)
    end
    local separator = new("Frame", {
        Position = UDim2.new(0, 0, 0, topbarHeight - 1),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = root,
    })
    bindTheme(separator, "BackgroundColor3", "Border")

    local sidebar = new("Frame", {
        Name = "Sidebar",
        Position = sidebarHorizontal
            and (sidebarOnBottom
                and UDim2.new(0, 0, 1, -sidebarHeight)
                or UDim2.fromOffset(0, topbarHeight))
            or (sidebarOnRight
                and UDim2.new(1, -sidebarWidth, 0, topbarHeight)
                or UDim2.fromOffset(0, topbarHeight)),
        Size = sidebarHorizontal
            and UDim2.new(1, 0, 0, sidebarHeight)
            or UDim2.new(0, sidebarWidth, 1, -topbarHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = root,
    })
    local sidebarScale = new("UIScale", {
        Scale = 0.96,
        Parent = sidebar,
    })
    local sideSeparator = new("Frame", {
        AnchorPoint = sidebarHorizontal
            and Vector2.new(0, 0)
            or (sidebarOnRight and Vector2.new(0, 0) or Vector2.new(1, 0)),
        Position = sidebarHorizontal
            and (sidebarOnBottom and UDim2.new() or UDim2.new(0, 0, 1, -1))
            or (sidebarOnRight and UDim2.new() or UDim2.new(1, 0, 0, 0)),
        Size = sidebarHorizontal and UDim2.new(1, 0, 0, 1) or UDim2.new(0, 1, 1, 0),
        BorderSizePixel = 0,
        Parent = sidebar,
    })
    bindTheme(sideSeparator, "BackgroundColor3", "Border")
    local tabList = new("ScrollingFrame", {
        Name = "Tabs",
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Position = sidebarHorizontal
            and UDim2.fromOffset(sidebarPadding, math.max(8, (sidebarHeight - tabHeight) * 0.5))
            or UDim2.fromOffset(sidebarPadding, 12),
        Size = sidebarHorizontal
            and UDim2.new(1, -(sidebarPadding * 2 + tabWidth), 0, tabHeight)
            or UDim2.new(1, -(sidebarPadding * 2), 1, -24),
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = sidebarHorizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
        ScrollingDirection = sidebarHorizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
        ScrollBarThickness = 0,
        Parent = sidebar,
    })
    new("UIListLayout", {
        FillDirection = sidebarHorizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        Padding = UDim.new(0, tabSpacing),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabList,
    })
    local pages = new("Frame", {
        Name = "Pages",
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Position = sidebarHorizontal
            and UDim2.fromOffset(
                contentPadding,
                topbarHeight + contentPadding + (sidebarOnTop and sidebarHeight or 0)
            )
            or (sidebarOnRight
                and UDim2.fromOffset(contentPadding, topbarHeight + contentPadding)
                or UDim2.fromOffset(sidebarWidth + contentPadding, topbarHeight + contentPadding)),
        Size = sidebarHorizontal
            and UDim2.new(
                1,
                -(contentPadding * 2),
                1,
                -(topbarHeight + sidebarHeight + contentPadding * 2)
            )
            or UDim2.new(
                1,
                -(sidebarWidth + contentPadding * 2),
                1,
                -(topbarHeight + contentPadding * 2)
            ),
        Parent = root,
    })

    local window = setmetatable({
        Root = root,
        Topbar = topbar,
        TopbarSeparator = separator,
        Sidebar = sidebar,
        TabList = tabList,
        Pages = pages,
        MinimizeButton = minimize,
        CloseButton = closeButton,
        Tabs = {},
        ActiveTab = nil,
        Visible = true,
        Minimized = false,
        _destroyed = false,
        _size = size,
        _scale = windowScale,
        _sizeConstraint = sizeConstraint,
        _minimumSize = minimumSize,
        _minimizedWidth = minimizedWidth,
        _minimizeOffsetY = 0,
        _minimizeAnimating = false,
        _topbarHeight = topbarHeight,
        _layout = {
            TabHeight = tabHeight,
            TabWidth = tabWidth,
            SidebarHorizontal = sidebarHorizontal,
            SectionSpacing = sectionSpacing,
            ControlSpacing = controlSpacing,
            SidebarWidth = sidebarWidth,
            SidebarHeight = sidebarHeight,
            TopbarHeight = topbarHeight,
            ContentPadding = contentPadding,
            SidebarPadding = sidebarPadding,
            TabSpacing = tabSpacing,
            MinimumSize = minimumSize,
            MinimizedWidth = minimizedWidth,
            SidebarSide = sidebarOnRight and "Right"
                or sidebarOnBottom and "Bottom"
                or sidebarOnTop and "Top"
                or "Left",
            Resizable = options.Resizable ~= false,
            CornerRadius = options.CornerRadius or 10,
            AnimatedBackground = options.AnimatedBackground == true,
            BackgroundParticles = options.BackgroundParticles == true,
        },
        _connections = connections,
        _flagSetters = {},
        _backgroundTweens = backgroundTweens,
        _tabByName = {},
        _titleLabel = titleLabel,
        _subtitleLabel = subtitleLabel,
        _titleTop = titleTop,
        _tabsReorderable = false,
        _reorderEnabled = options.Reorderable ~= false,
        _themeOverrides = nil,
        _onClose = type(options.OnClose) == "function" and options.OnClose or nil,
        _closeRequest = type(options.CloseRequest) == "function" and options.CloseRequest or nil,
        _destroyOnClose = options.DestroyOnClose == true,
        _draggable = options.Draggable ~= false,
        _opacity = 1,
        _bgTransparency = 0,
        _blurSize = 0,
        _tabSeq = 0,
        _toggleCombo = toggleCombo,
        _toggleKey = toggleCombo.Keys[1],
        _geometryKey = tostring(options.GeometryKey or sanitizeProfileName(options.Title or ("window" .. #self._windows))),
    }, Window)
    table.insert(self._windows, window)
    table.insert(self._windowOrder, window)
    Library:_emit("windowCreated", window)
    -- A new window opens in front, otherwise it lands behind every window that
    -- already exists and the one you just made looks like it vanished.
    self:FocusWindow(window, false)

    makeDraggable(topbar, root, connections, window)
    -- Empty edge spots also drag: thin strips along the window border that sit
    -- behind controls (ZIndex 2 vs buttons at 4+) and cover only the padding
    -- area, so they never overlap interactive parts. Each has the same
    -- topmost-only guard as the topbar via makeDraggable.
    do
        local edgeProps = { BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, ZIndex = 2 }
        local function edge(name, anchor, position, size)
            local strip = new("Frame", {
                Name = name,
                AnchorPoint = anchor,
                Position = position,
                Size = size,
                BackgroundTransparency = edgeProps.BackgroundTransparency,
                BorderSizePixel = 0,
                Active = true,
                ZIndex = 2,
                Parent = root,
            })
            makeDraggable(strip, root, connections, window)
            return strip
        end
        -- Left / right leave 24px at the bottom for the resize handle.
        window._edgeLeft = edge("EdgeLeft", Vector2.new(0, 0), UDim2.fromOffset(0, 0), UDim2.new(0, 10, 1, -24))
        window._edgeRight = edge("EdgeRight", Vector2.new(1, 0), UDim2.new(1, -10, 0, 0), UDim2.new(0, 10, 1, -24))
        -- Bottom leaves room for the side strips and the resize corner.
        window._edgeBottom = edge("EdgeBottom", Vector2.new(0, 1), UDim2.new(0, 10, 1, -10), UDim2.new(1, -34, 0, 10))
    end
    connect(root.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        -- Click-to-focus only: hover (MouseMovement) never changes focus, and a
        -- click that lands on a higher overlapping window must not steal focus.
        if Library:_isObscured(window, input.Position) then
            return
        end
        Library:FocusWindow(window)
    end, connections)
    if options.Resizable ~= false then
        local resizeHandle = new("TextButton", {
            Name = "ResizeHandle",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.fromScale(1, 1),
            Size = UDim2.fromOffset(22, 22),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "//",
            Font = Enum.Font.Code,
            TextSize = 11,
            TextColor3 = Library.Theme.MutedText,
            ZIndex = 12,
            Parent = root,
        })
        bindTheme(resizeHandle, "TextColor3", "MutedText")
        local resizing = false
        local resizeStart
        local startSize
        local startPosition
        connect(resizeHandle.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                if Library:_isObscured(window, input.Position) then
                    return
                end
                resizing = true
                resizeStart = input.Position
                startSize = root.AbsoluteSize
                startPosition = root.Position
                Library:FocusWindow(window)
            end
        end, connections)
        connect(UserInputService.InputChanged, function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - resizeStart
                -- Root is anchored at 0.5,0.5, so growing Size alone moves the
                -- bottom-right corner by only half the delta. Shift Position by
                -- half the applied growth to keep the top-left fixed, which keeps
                -- the handle itself under the cursor. When clamped at the minimum
                -- size the handle legitimately stops following.
                local desiredW = startSize.X + delta.X
                local desiredH = startSize.Y + delta.Y
                local clampedW = math.max(window._minimumSize.X, desiredW)
                local clampedH = math.max(window._minimumSize.Y, desiredH)
                local appliedX = clampedW - startSize.X
                local appliedY = clampedH - startSize.Y
                window:SetSize(UDim2.fromOffset(clampedW, clampedH))
                root.Position = UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset + appliedX / 2,
                    startPosition.Y.Scale,
                    startPosition.Y.Offset + appliedY / 2
                )
            end
        end, connections)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                resizing = false
            end
        end, connections)
        window.ResizeHandle = resizeHandle
    end
    if closeButton then
        connect(closeButton.MouseEnter, function()
            tween(closeButton, 0.15, {
                BackgroundTransparency = 0,
                TextColor3 = Library.Theme.Error,
            })
        end, connections)
        connect(closeButton.MouseLeave, function()
            tween(closeButton, 0.15, {
                BackgroundTransparency = 1,
                TextColor3 = Library.Theme.MutedText,
            })
        end, connections)
        connect(closeButton.Activated, function(input)
            if Library:_isObscured(window, input and input.Position) then
                return
            end
            window:RequestClose()
        end, connections)
    end
    if minimize then
        connect(minimize.MouseEnter, function()
            tween(minimize, 0.15, {
                BackgroundTransparency = 0,
                TextColor3 = Library.Theme.Accent,
            })
        end, connections)
        connect(minimize.MouseLeave, function()
            tween(minimize, 0.15, {
                BackgroundTransparency = 1,
                TextColor3 = Library.Theme.MutedText,
            })
        end, connections)
        connect(minimize.Activated, function(input)
            if Library:_isObscured(window, input and input.Position) then
                return
            end
            window:ToggleMinimized()
        end, connections)
    end

    connect(UserInputService.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            heldKeys[input.KeyCode] = true
        end
    end, connections)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            heldKeys[input.KeyCode] = nil
        end
    end, connections)
    connect(UserInputService.WindowFocusReleased, function()
        table.clear(heldKeys)
    end, connections)
    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end
        local combo = window._toggleCombo
        if combo and comboMatches(combo, input, heldKeys) then
            window:Toggle()
        end
    end, connections)

    window._footerLabel = text(sidebar, T("MadeWith"), 9, "MutedText", {
        AnchorPoint = sidebarHorizontal and Vector2.new(1, 0.5) or Vector2.new(0, 1),
        Position = sidebarHorizontal
            and UDim2.new(1, -12, 0.5, 0)
            or UDim2.new(0, 12, 1, -8),
        Size = sidebarHorizontal and UDim2.fromOffset(158, 28) or UDim2.new(1, -24, 0, 28),
        TextWrapped = true,
        TextXAlignment = sidebarHorizontal and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center,
        TextYAlignment = sidebarHorizontal and Enum.TextYAlignment.Center or Enum.TextYAlignment.Bottom,
    })
    if not sidebarHorizontal then
        tabList.Size = UDim2.new(1, -(sidebarPadding * 2), 1, -60)
    end
    tween(sidebarScale, 0.38, { Scale = 1 }, Enum.EasingStyle.Back)
    tween(windowScale, 0.38, { Scale = 1 }, Enum.EasingStyle.Back)
    if options.Footer == false then
        window:SetFooter(false)
    elseif type(options.Footer) == "string" then
        window:SetFooter(options.Footer)
    end
    if options.Icon ~= nil then window:SetIcon(options.Icon) end
    if options.Opacity ~= nil then window:SetOpacity(options.Opacity) end
    if options.Blur ~= nil and options.Blur ~= false then window:SetBlur(options.Blur) end
    local toggleButton = options.ToggleButton
    if toggleButton == nil then
        toggleButton = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    end
    if toggleButton then window:SetToggleButton(toggleButton) end
    return window
end

function Library:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self:AutoSave(nil)
    self:Unbind()
    for _, entry in ipairs(self._controlDisposers) do
        if type(entry.Dispose) == "function" then
            pcall(entry.Dispose)
        end
    end
    table.clear(self._controlDisposers)
    table.clear(self._dependencySubs)
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)
    for index = #self._windows, 1, -1 do
        self._windows[index]:Destroy()
    end
    -- Windows are torn down above, which also empties _windowOrder; sweep any
    -- stragglers and clear the list. Windows have no Disconnect method.
    for index = #self._windowOrder, 1, -1 do
        local window = self._windowOrder[index]
        if table.find(self._windows, window) then
            window:Destroy()
        end
    end
    table.clear(self._windowOrder)
    self._focusedWindow = nil
    self._clickGuard = nil
    table.clear(self._themeBindings)
    table.clear(self._flagSetters)
    table.clear(self._flagListeners)
    table.clear(self._flagTypes)
    table.clear(self._specControls)
    table.clear(self._notifications)
    self._configAdapter = nil
    self:_clearListeners()
    if self.Gui then self.Gui:Destroy() end
end

-- Declarative UI construction. Defined at the end of the file so the
-- Section/Window tables are already in scope.

-- ExportSpec renders Color3 values as "#RRGGBB" so a spec stays JSON-friendly, so
-- Build has to turn them back or a round-trip loses every colour.
local function restoreColors(options, methodName)
    if methodName == "AddColorPicker" then
        local default = type(options.Default) == "string" and parseHexColor(options.Default) or nil
        if default then options.Default = default end
        if type(options.Presets) == "table" then
            for index, preset in ipairs(options.Presets) do
                if type(preset) == "string" then
                    local color = parseHexColor(preset)
                    if color then options.Presets[index] = color end
                end
            end
        end
    elseif methodName == "AddRow" and type(options.Controls) == "table" then
        -- Row children are built by AddRow itself, so they are fixed up here
        -- rather than by the recursive buildControl call.
        for _, child in ipairs(options.Controls) do
            if type(child) == "table" then
                local childType = child.Type or child.type or child.Control
                if type(childType) == "string" then
                    restoreColors(child, controlMethodName(childType))
                end
            end
        end
    end
    return options
end

local function buildControl(section, controlSpec, result)
    if type(controlSpec) ~= "table" then
        return nil
    end
    local options = copyTable(controlSpec)
    local controlType = options.Type or options.type or options.Control
    options.Type, options.type, options.Control = nil, nil, nil
    if type(controlType) ~= "string" then
        return nil, "Control spec needs a Type"
    end
    local methodName = controlMethodName(controlType)
    local method = Section[methodName]
    if type(method) ~= "function" then
        return nil, "Unknown control type: " .. tostring(controlType)
    end
    restoreColors(options, methodName)
    -- AddRow builds its own compact slots from the child specs. Recursing with
    -- Section:Add* instead would stack full-width controls in the section and
    -- lose the row layout, so those specs go straight to AddRow instead.
    local nested = methodName ~= "AddRow"
    local children = options.Controls or options.controls
    if nested then options.Controls, options.controls = nil, nil end
    local control = method(section, options)
    local key = options.Flag or options.Name
    if key ~= nil then
        result.Controls[key] = control
    end
    if type(children) == "table" then
        if nested then
            for _, childSpec in ipairs(children) do
                local child, err = buildControl(section, childSpec, result)
                if not child then
                    warn("[Bloodshot UI] Build: " .. tostring(err or "skipped a control"))
                end
            end
        else
            for _, child in ipairs(control.Children or {}) do
                local childKey = child.Flag or child.Name
                if childKey ~= nil then result.Controls[childKey] = child end
            end
        end
    end
    return control
end

-- spec = { Window = <CreateWindow options>,
--          Tabs = { { Name = "x", Sections = { { Name = "y", Controls = { { Type = "Toggle" } } } } } },
--          Flags = { someFlag = true } }
function Library:Build(spec)
    if type(spec) ~= "table" then
        return nil, "Build expects a table"
    end
    local window = self:CreateWindow(type(spec.Window) == "table" and spec.Window or {})
    local result = { Window = window, Tabs = {}, Sections = {}, Controls = {} }
    local tabs = type(spec.Tabs) == "table" and spec.Tabs or {}
    for _, tabSpec in ipairs(tabs) do
        if type(tabSpec) == "table" then
            local tab = window:AddTab(tabSpec.Name or tabSpec.Title or "Tab", tabSpec.Icon)
            result.Tabs[#result.Tabs + 1] = tab
            for _, sectionSpec in ipairs(tabSpec.Sections or {}) do
                if type(sectionSpec) == "table" then
                    local sectionOptions = copyTable(sectionSpec)
                    local controlSpecs = sectionOptions.Controls or sectionOptions.controls
                    sectionOptions.Controls, sectionOptions.controls = nil, nil
                    local section = tab:AddSection(sectionOptions)
                    result.Sections[#result.Sections + 1] = section
                    for _, controlSpec in ipairs(controlSpecs or {}) do
                        local control, err = buildControl(section, controlSpec, result)
                        if not control then
                            warn("[Bloodshot UI] Build: " .. tostring(err or "skipped a control"))
                        end
                    end
                end
            end
        end
    end
    for flag, value in pairs(type(spec.Flags) == "table" and spec.Flags or {}) do
        local expected = self._flagTypes[flag]
        if type(value) == "string" and expected == "Color3" then
            value = parseHexColor(value) or value
        elseif type(value) == "string" and expected == "EnumItem" then
            value = parseKeyName(value) or value
        end
        self:SetFlag(flag, value, true)
    end
    return result
end

function Library:BuildFromJson(json, windowOptions)
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
    if not ok or type(decoded) ~= "table" then
        return nil, "BuildFromJson expects valid JSON"
    end
    if type(windowOptions) == "table" then
        decoded.Window = decoded.Window or windowOptions
    end
    return self:Build(decoded)
end

-- Serialisable stand-in for anything a spec cannot carry (callbacks, instances,
-- functions). Keeps exported specs JSON-encodable without silently dropping data.
local function exportableValue(value, depth)
    if depth > 6 then return nil end
    local kind = typeof(value)
    if kind == "Color3" then
        return string.format("#%02X%02X%02X",
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5))
    elseif kind == "EnumItem" then
        return tostring(value)
    elseif kind == "UDim2" then
        return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
    elseif kind == "number" or kind == "string" or kind == "boolean" then
        return value
    elseif kind == "table" then
        local result = {}
        for key, item in pairs(value) do
            local converted = exportableValue(item, depth + 1)
            if converted ~= nil then
                result[type(key) == "number" and #result + 1 or key] = converted
            end
        end
        return result
    end
    return nil
end

local SPEC_DROP = {
    Callback = true, Changed = true, Clear = true, Predicate = true,
    Resolve = true, Transform = true, TransformBack = true, OnError = true,
    Controls = true, OnClose = true, CloseRequest = true,
    -- Live library references rather than spec data: AddSearch's Target points at
    -- the tab/section it filters, which means nothing to whoever replays the spec.
    Target = true,
}

-- Window -> spec, the inverse of Build. Lets an external tool mirror the exact
-- layout from one source of truth.
--   local spec = Bloodshot:ExportSpec(window)
--   local json = Bloodshot:ExportSpecJson(window)
function Library:ExportSpec(target, options)
    options = type(options) == "table" and options or {}
    local window = target
    if type(window) == "string" then
        for _, candidate in ipairs(self._windows) do
            if candidate._geometryKey == window then window = candidate break end
        end
    end
    if type(window) ~= "table" or not window.Tabs then
        return nil, "ExportSpec expects a window"
    end
    if window._destroyed or not window.Root then
        return nil, "ExportSpec cannot read a destroyed window"
    end
    local function clean(entry, extra)
        local result = {}
        for key, value in pairs(entry) do
            if not SPEC_DROP[key] and key ~= "Type" then
                local converted = exportableValue(value, 0)
                if converted ~= nil then result[key] = converted end
            end
        end
        for key, value in pairs(extra or {}) do
            result[key] = value
        end
        return result
    end

    local spec = { Window = {}, Tabs = {} }
    local windowSpec = clean({
        Title = window._titleLabel and window._titleLabel.Text or nil,
        Subtitle = window._subtitleLabel and window._subtitleLabel.Text or nil,
        Size = exportableValue(window._size, 0),
        Position = exportableValue(window.Root.Position, 0),
        GeometryKey = window._geometryKey,
        Closeable = window.CloseButton ~= nil,
        ToggleKey = comboLabel(window._toggleCombo),
    })
    for _, key in ipairs({
        "SidebarSide", "SidebarWidth", "SidebarHeight", "TopbarHeight",
        "ContentPadding", "SidebarPadding", "TabHeight", "TabWidth",
        "TabSpacing", "SectionSpacing", "ControlSpacing", "MinimizedWidth",
        "CornerRadius", "Resizable", "AnimatedBackground", "BackgroundParticles",
    }) do
        local value = window._layout[key]
        if value ~= nil then
            local converted = exportableValue(value, 0)
            if converted ~= nil then windowSpec[key] = converted end
        end
    end
    if window._opacity ~= 1 then windowSpec.Opacity = window._opacity end
    if window._blurSize > 0 then windowSpec.Blur = window._blurSize end
    if window._draggable == false then windowSpec.Draggable = false end
    if window._iconSource ~= nil then windowSpec.Icon = window._iconSource end
    if window._footerText ~= nil then windowSpec.Footer = window._footerText end
    if window._layout.MinimumSize then
        windowSpec.MinimumSize = {
            window._layout.MinimumSize.X,
            window._layout.MinimumSize.Y,
        }
    end
    spec.Window = windowSpec

    for _, tab in ipairs(window.Tabs) do
        local tabSpec = {
            Name = tab.Name,
            Icon = tab.Icon,
            Sections = {},
        }
        for _, section in ipairs(tab.Sections) do
            local sectionSpec = {
                Name = section.Name,
                Collapsible = section.Collapsible == true,
                Collapsed = section.Collapsed == true,
                Controls = {},
            }
            for _, control in ipairs(section.Controls or {}) do
                if control and control.Spec then
                    -- Type is stripped from the copied options by clean(), so the
                    -- control's own type is re-attached explicitly.
                    local controlSpec = clean(control.Spec, {
                        Type = control.Type,
                        Name = control.Instance and control.Instance.Name or control.Spec.Name,
                    })
                    if options.IncludeValues ~= false and control.Flag then
                        local ok, value = pcall(control.Get, control)
                        local converted = ok and exportableValue(value, 0) or nil
                        if converted ~= nil then controlSpec.Value = converted end
                    end
                    if control.Children then
                        local nested = {}
                        for _, child in ipairs(control.Children) do
                            local childSpec = clean(child.Spec or {}, {
                                Type = child.Type,
                                Name = child.Instance and child.Instance.Name or child.Name,
                            })
                            if options.IncludeValues ~= false and child.Flag then
                                local ok, value = pcall(child.Get, child)
                                local converted = ok and exportableValue(value, 0) or nil
                                if converted ~= nil then childSpec.Value = converted end
                            end
                            nested[#nested + 1] = childSpec
                        end
                        controlSpec.Controls = nested
                    end
                    sectionSpec.Controls[#sectionSpec.Controls + 1] = controlSpec
                end
            end
            tabSpec.Sections[#tabSpec.Sections + 1] = sectionSpec
        end
        spec.Tabs[#spec.Tabs + 1] = tabSpec
    end

    if options.Flags ~= false then
        spec.Flags = {}
        for flag, value in pairs(self.Flags) do
            local converted = exportableValue(value, 0)
            if converted ~= nil then spec.Flags[tostring(flag)] = converted end
        end
    end
    return spec
end

function Library:ExportSpecJson(target, options)
    local spec, message = self:ExportSpec(target, options)
    if not spec then return nil, message end
    local ok, json = pcall(HttpService.JSONEncode, HttpService, spec)
    if not ok then
        return nil, "Unable to encode spec: " .. tostring(json)
    end
    return json
end

local THEME_COLOR_KEYS = {
    "Background", "Surface", "SurfaceAlt", "Border", "Text", "MutedText",
    "Accent", "AccentDark", "Success", "Warning", "Error",
    "BackgroundGradient", "SurfaceGradient", "AccentGradient",
    "Disabled", "Focus", "Overlay",
}
local THEME_NUMBER_KEYS = { "CornerRadius", "ControlTransparency" }

-- Live diagnostics: flag inventory plus the internal counters behind the leaks.
function Library:Inspect()
    local window = self:CreateWindow({
        Title = "Inspector",
        Subtitle = "runtime diagnostics",
        AnimatedBackground = false,
        BackgroundParticles = false,
        ToggleKey = Enum.KeyCode.F8,
    })
    local tab = window:AddTab("Diagnostics")
    local summarySection = tab:AddSection("Summary")
    local flagSection = tab:AddSection("Flags")
    local summary = summarySection:AddParagraph({ Title = "Runtime", Content = "...", Font = Enum.Font.Code })
    local flagBody = flagSection:AddParagraph({ Title = "Flag values", Content = "", Font = Enum.Font.Code })

    local function refresh()
        local names = {}
        for flag in pairs(self.Flags) do names[#names + 1] = flag end
        table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
        local lines = {}
        for _, flag in ipairs(names) do
            local value = self.Flags[flag]
            local rendered = typeof(value) == "table" and "<table>" or tostring(value)
            lines[#lines + 1] = string.format("%-22s %-9s %s", tostring(flag), typeof(value), rendered)
        end
        flagBody:Set(#lines > 0 and table.concat(lines, "\n") or "(no flags set)")
        local setters = 0
        for _ in pairs(self._flagSetters) do setters = setters + 1 end
        local listeners = 0
        for _, list in pairs(self._flagListeners or {}) do listeners = listeners + #list end
        summary:Set(string.format(
            "Windows      %d\nFocused      %s\nFlags        %d\nFlag setters %d\n"
            .. "Theme binds  %d\nBindings     %d\nListeners    %d\nConnections  %d\n"
            .. "AutoSave     %s\nAdapter      %s",
            #self._windows, tostring(self._focusedWindow ~= nil), #names, setters,
            #self._themeBindings, #(self._bindings or {}), listeners, #self._connections,
            self._autoSave and (self._autoSave.Profile .. " (" .. tostring(self._autoSave.Saves) .. " saves)") or "off",
            self._configAdapter and tostring(self._configAdapter.Name or "custom") or "none"))
    end
    summarySection:AddButton({ Name = "Refresh", Callback = refresh })
    flagSection:AddButton({
        Name = "Copy config JSON",
        Callback = function()
            local json = self:SaveConfig()
            if json and setclipboard then setclipboard(json) end
        end,
    })
    refresh()
    return window
end

-- Live editor for every key SetTheme accepts.
function Library:ThemeEditor()
    local window = self:CreateWindow({
        Title = "Theme Editor",
        Subtitle = "changes apply live",
        AnimatedBackground = false,
        BackgroundParticles = false,
        ToggleKey = Enum.KeyCode.F9,
    })
    local tab = window:AddTab("Theme")
    local colours = tab:AddSection("Colours")
    for _, key in ipairs(THEME_COLOR_KEYS) do
        colours:AddColorPicker({
            Name = key,
            Default = self.Theme[key],
            Callback = function(color)
                self:SetTheme({ [key] = color })
            end,
        })
    end
    local numbers = tab:AddSection("Metrics")
    for _, key in ipairs(THEME_NUMBER_KEYS) do
        numbers:AddSlider({
            Name = key,
            Min = 0,
            Max = key == "CornerRadius" and 20 or 1,
            Increment = key == "CornerRadius" and 1 or 0.05,
            Default = tonumber(self.Theme[key]) or 0,
            Callback = function(value)
                self:SetTheme({ [key] = value })
            end,
        })
    end
    local actions = tab:AddSection("Presets")
    local presetNames = {}
    for name in pairs(self.ThemePresets) do presetNames[#presetNames + 1] = name end
    table.sort(presetNames)
    if #presetNames > 0 then
        actions:AddDropdown({
            Name = "Apply preset",
            Values = presetNames,
            Callback = function(value)
                self:SetThemePreset(value)
            end,
        })
    end
    actions:AddButton({
        Name = "Reset to defaults",
        Callback = function()
            self:ResetTheme()
        end,
    })
    return window
end

return Library
