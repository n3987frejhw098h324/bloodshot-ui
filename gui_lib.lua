if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Library = {
    Version = "2.0.0",
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
    Strings = {
        Confirm = "Confirm",
        Cancel = "Cancel",
        Close = "Close",
        Reset = "Reset",
        Notification = "Notification",
        EnterValue = "Enter value...",
        SearchPlaceholder = "Search...",
        SelectPlaceholder = "Select...",
        NoOptions = "No options",
        ControlSearch = "control or section name",
        MadeWith = "Made with <3 by R",
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
    _hooked = {},
    _bindings = {},
    _dependencySubs = {},
    _windowOrder = {},
    _focusedWindow = nil,
    _gamepadEnabled = true,
    _autoSave = nil,
    _geometry = nil,
}

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
local function copyTable(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and copyTable(value) or value
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
    bindTheme(label, "TextColor3", colorKey or "Text")
    return label
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
        return
    end
    local ok, message = pcall(callback, ...)
    if not ok then
        warn("[Bloodshot UI] Callback error: " .. tostring(message))
    end
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
    -- Fan out to any listener/binding that subscribed before this control existed.
    Library:_hookFlag(flag)
end

local function makeDraggable(handle, target, bucket)
    local dragging = false
    local dragStart
    local startPosition
    local activeInput

    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
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
                binding.Update()
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
    self.Flags[flag] = value
    local setter = self._flagSetters[flag]
    if setter then
        setter(value, silent)
    else
        self:_notifyFlagChanged(flag)
    end
end

function Library:GetFlag(flag, fallback)
    local value = self.Flags[flag]
    if value == nil then
        return fallback
    end
    return value
end

-- Fires every listener registered for a flag. Listeners must not throw.
function Library:_notifyFlagChanged(flag)
    local listeners = self._flagListeners[flag]
    if not listeners then
        return
    end
    local snapshot = {}
    for index, entry in ipairs(listeners) do snapshot[index] = entry end
    for _, entry in ipairs(snapshot) do
        if entry.Alive then
            local ok, err = pcall(entry.Callback, self.Flags[flag])
            if not ok then
                warn("[Bloodshot UI] Flag listener error for '" .. tostring(flag) .. "': " .. tostring(err))
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

-- Wraps a control's registered setter so flag writes fan out to listeners.
-- Re-wraps when a new control claims the same flag.
function Library:_hookFlag(flag)
    local key = tostring(flag)
    if not self._flagListeners[key] and not self._flagListeners["*"] then
        return nil
    end
    local setter = self._flagSetters[key]
    -- Setters are plain functions; indexing a function to tag it is an error in
    -- Luau, so wrapped originals are tracked in a side table instead.
    if type(setter) ~= "function" then
        return nil
    end
    if self._hooked[key] == setter then
        return self._flagSetters[key]
    end
    local hook = function(value, silent)
        setter(value, silent)
        Library:_notifyFlagChanged(key)
    end
    self._hooked[key] = setter
    self._flagSetters[key] = hook
    return hook
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

    -- Register the listener first: _hookFlag only wraps setters when somebody
    -- is actually subscribed to the flag.
    table.insert(binding.Disposers, self:OnFlagChanged(flag, apply))
    self:_hookFlag(flag)
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
            local enumType = enumName and Enum[enumName]
            local enumItem = enumType and enumType[itemName]
            if not enumItem then
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
        self:SetFlag(flag, value, silent)
    end
    return true
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
    local ok, result = pcall(self._configAdapter.Write, self._configAdapter, tostring(name), json)
    if not ok or result == false then return false, tostring(result) end
    return true
end

function Library:LoadProfile(name, options)
    if not self._configAdapter then return false, "No config adapter configured" end
    local ok, json = pcall(self._configAdapter.Read, self._configAdapter, tostring(name))
    if not ok or type(json) ~= "string" then return false, tostring(json) end
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
    local adapter = {
        Name = "file",
        Path = profilePath,
        Write = function(_, name, json)
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
                if stem then
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
    local ok, result = pcall(adapter.Delete, adapter, tostring(name))
    if not ok or result == false then
        return false, tostring(result)
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
    if previous and previous ~= window and previous._themeOverrides then
        self:SetTheme(previous._themeRestore or DEFAULT_THEME)
        previous._themeRestore = nil
    end
    if applyTheme ~= false and window._themeOverrides then
        window._themeRestore = copyTable(self.Theme)
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

function Library:SaveGeometry()
    local adapter = self._configAdapter
    if not adapter or type(adapter.Write) ~= "function" then
        return false, "No config adapter configured"
    end
    local payload = {}
    for _, window in ipairs(self._windows) do
        local geometry = window:GetGeometry()
        if geometry then
            payload[window._geometryKey] = {
                {
                    geometry.Position.X.Scale, geometry.Position.X.Offset,
                    geometry.Position.Y.Scale, geometry.Position.Y.Offset,
                },
                {
                    geometry.Size.X.Scale, geometry.Size.X.Offset,
                    geometry.Size.Y.Scale, geometry.Size.Y.Offset,
                },
            }
        end
    end
    local ok, result = pcall(adapter.Write, adapter, "__geometry",
        HttpService:JSONEncode({ version = self.ConfigVersion, windows = payload }))
    if not ok or result == false then
        return false, tostring(result)
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
        local entry = decoded.windows[window._geometryKey]
        if type(entry) == "table" and type(entry[1]) == "table" and type(entry[2]) == "table"
            and #entry[1] == 4 and #entry[2] == 4 then
            if window:SetGeometry({
                Position = UDim2.new(entry[1][1], entry[1][2], entry[1][3], entry[1][4]),
                Size = UDim2.new(entry[2][1], entry[2][2], entry[2][3], entry[2][4]),
            }) then
                applied += 1
            end
        end
    end
    return true, applied
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
            return
        end
        if not state.Dirty or state.Pending then
            return
        end
        state.Pending = true
        task.delay(delay, function()
            state.Pending = false
            if self._autoSave ~= state then return end
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
    options = type(options) == "table" and options or { Content = tostring(options) }
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
    tween(timer, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)

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
    options = options or {}
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
        ZIndex = 101,
        Parent = overlay,
    })
    bindTheme(card, "BackgroundColor3", "Surface")
    corner(card, 9)
    stroke(card, self.Theme.Border, 1, 0.1, "Border")
    text(card, options.Title or T("Confirm"), 16, "Text", {
        Position = UDim2.fromOffset(18, 16), Size = UDim2.new(1, -36, 0, 24),
        Font = Enum.Font.GothamBold, ZIndex = 102,
    })
    text(card, options.Content or options.Description or "Are you sure?", 12, "MutedText", {
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
    corner(cancel, 6); corner(confirm, 6)
    connect(cancel.Activated, function() resolve(false) end)
    connect(confirm.Activated, function() resolve(true) end)
    connect(overlay.Activated, function() if options.DismissOnOverlay ~= false then resolve(false) end end)
    return { Instance = overlay, Close = function(_, result) resolve(result == true) end }
end

local function createControlBase(section, height, name, description)
    local holder = new("Frame", {
        Name = name or "Control",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, height),
        Parent = section.Container,
    })
    bindTheme(holder, "BackgroundColor3", "SurfaceAlt")
    gradient(holder, "SurfaceAlt", "SurfaceGradient", 12)
    corner(holder, 6)
    local holderStroke = stroke(holder, Library.Theme.Border, 1, 0.45, "Border")
    tween(holder, 0.24, { BackgroundTransparency = Library.Theme.ControlTransparency or 0.8 })
    connect(holder.MouseEnter, function()
        tween(holder, 0.16, { BackgroundTransparency = 0.68 })
        tween(holderStroke, 0.16, { Transparency = 0.2 })
    end, section.Window._connections)
    connect(holder.MouseLeave, function()
        tween(holder, 0.16, { BackgroundTransparency = Library.Theme.ControlTransparency or 0.8 })
        tween(holderStroke, 0.16, { Transparency = 0.45 })
    end, section.Window._connections)

    local nameLabel = text(holder, name or "Control", 13, "Text", {
        Position = UDim2.fromOffset(12, description and 8 or 0),
        Size = UDim2.new(1, -24, 0, description and 18 or height),
        Font = Enum.Font.GothamMedium,
    })
    local descriptionLabel
    if description then
        descriptionLabel = text(holder, description, 11, "MutedText", {
            Position = UDim2.fromOffset(12, 27),
            Size = UDim2.new(1, -24, 0, 16),
        })
    end
    holder:SetAttribute("BloodshotControl", true)
    holder:SetAttribute("BloodshotDisabled", false)
    holder:SetAttribute("BloodshotBaseHeight", height)
    holder:SetAttribute("BloodshotHasDescription", description ~= nil)
    holder:SetAttribute("BloodshotNameLabel", nameLabel.Name)
    return holder, nameLabel, descriptionLabel
end

-- Renumbers a UIListLayout-backed container so the given item lands at index.
local function reorderList(parent, item, index)
    local children = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            children[#children + 1] = child
        end
    end
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

-- LayoutOrder drives the visual order; GetChildren() keeps creation order.
local function orderedChildren(parent)
    local list = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            list[#list + 1] = child
        end
    end
    table.sort(list, function(a, b)
        if a.LayoutOrder == b.LayoutOrder then
            return a.Name < b.Name
        end
        return a.LayoutOrder < b.LayoutOrder
    end)
    return list
end

-- Drag-to-reorder for anything living in a UIListLayout container.
-- A press alone never reorders: the pointer must travel past Threshold first,
-- so ordinary clicks, sliders and text entry are untouched.
local function beginReorderDrag(handle, target, container, window, vertical, threshold, onReorder)
    if not handle or not target or not container or not window then return nil end
    local state = { Dragged = false, Disconnect = nil }
    local dragging, started, startPoint = false, false, nil
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
            if onReorder then onReorder(best) end
        end
    end, window._connections))
    register(connect(UserInputService.InputEnded, function(input)
        if dragging and isDragInput(input.UserInputType) then
            dragging, started = false, false
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
}

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

function Section:AddLabel(options)
    options = type(options) == "table" and options or { Text = tostring(options) }
    local label = text(self.Container, options.Text or options.Name or "Label", options.TextSize or 12, options.Color or "MutedText", {
        Size = UDim2.new(1, 0, 0, options.Height or 24),
        TextWrapped = options.Wrap == true,
        TextXAlignment = options.Alignment or Enum.TextXAlignment.Left,
    })
    return {
        Instance = label,
        Set = function(_, value)
            label.Text = tostring(value)
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
    local body = text(holder, options.Content or options.Text or "", 11, "MutedText", {
        Position = UDim2.fromOffset(12, 29),
        Size = automaticHeight and UDim2.new(1, -24, 0, 9) or UDim2.new(1, -24, 1, -38),
        AutomaticSize = automaticHeight and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        TextScaled = not automaticHeight,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    return {
        Instance = holder,
        Set = function(_, value)
            body.Text = tostring(value)
        end,
    }
end

function Section:AddButton(options)
    options = type(options) == "table" and options or { Name = tostring(options) }
    local holder, nameLabel = createControlBase(self, options.Description and 52 or 40, options.Name or "Button", options.Description)
    local buttonScale = new("UIScale", {
        Scale = 1,
        Parent = holder,
    })
    nameLabel.Size = UDim2.new(1, -52, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    local arrow = text(holder, "›", 22, "MutedText", {
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
    connect(button.MouseEnter, function()
        tween(holder, 0.15, { BackgroundColor3 = Library.Theme.Border })
        tween(arrow, 0.15, { Position = UDim2.new(1, -8, 0.5, 0) })
    end, self.Window._connections)
    connect(button.MouseLeave, function()
        tween(holder, 0.15, { BackgroundColor3 = Library.Theme.SurfaceAlt })
        tween(arrow, 0.15, { Position = UDim2.new(1, -12, 0.5, 0) })
    end, self.Window._connections)
    connect(button.Activated, function(input)
        ripple(holder, input and input.Position)
        tween(buttonScale, 0.08, { Scale = 0.97 }, Enum.EasingStyle.Sine).Completed:Connect(function()
            if holder.Parent then
                tween(buttonScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
            end
        end)
        safeCall(options.Callback)
    end, self.Window._connections)
    return {
        Instance = holder,
        Fire = function()
            safeCall(options.Callback)
        end,
    }
end

function Section:AddToggle(options)
    options = options or {}
    local holder, nameLabel = createControlBase(self, options.Description and 52 or 40, options.Name or "Toggle", options.Description)
    nameLabel.Size = UDim2.new(1, -68, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(38, 20),
        BorderSizePixel = 0,
        Parent = holder,
    })
    corner(track, 999)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Color3.fromRGB(235, 238, 245),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(knob, 999)
    local button = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = holder,
    })

    local value = options.Default == true
    local function set(nextValue, silent)
        value = not not nextValue
        tween(track, 0.16, {
            BackgroundColor3 = value and Library.Theme.Accent or Library.Theme.Border,
        })
        tween(knob, 0.16, {
            Position = value and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        })
        if options.Flag then
            Library.Flags[options.Flag] = value
        end
        if not silent then
            safeCall(options.Callback, value)
        end
    end
    bindThemeState(track, function()
        track.BackgroundColor3 = value and Library.Theme.Accent or Library.Theme.Border
    end)
    connect(button.Activated, function()
        set(not value)
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    if options.FireOnLoad then
        safeCall(options.Callback, value)
    end
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
    }
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
    local holder, nameLabel = createControlBase(self, 58, options.Name or "Slider")
    nameLabel.Size = UDim2.new(1, -80, 0, 30)
    local valueLabel = text(holder, "", 12, "MutedText", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 0),
        Size = UDim2.fromOffset(64, 30),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
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
    bindTheme(fill, "BackgroundColor3", "Accent")
    gradient(fill, "Accent", "AccentGradient", 0)
    corner(fill, 999)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BorderSizePixel = 0,
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

    local value = minimum
    local dragging = false
    local decimals = math.max(0, #(tostring(increment):match("%.(%d+)") or ""))
    local function round(number)
        return math.floor((number / increment) + 0.5) * increment
    end
    local function set(nextValue, silent)
        value = math.clamp(round(tonumber(nextValue) or minimum), minimum, maximum)
        local ratio = (value - minimum) / (maximum - minimum)
        fill.Size = UDim2.fromScale(ratio, 1)
        knob.Position = UDim2.fromScale(ratio, 0.5)
        valueLabel.Text = (options.Prefix or "") .. string.format("%." .. decimals .. "f", value) .. (options.Suffix or "")
        if options.Flag then
            Library.Flags[options.Flag] = value
        end
        if not silent then
            safeCall(options.Callback, value)
        end
    end
    local function updateFromInput(input)
        local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        set(minimum + (maximum - minimum) * ratio)
    end
    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
    registerFlagSetter(self.Window, options.Flag, set)
    set(options.Default or minimum, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
    }
end

function Section:AddInput(options)
    options = options or {}
    local holder, nameLabel = createControlBase(self, options.Description and 58 or 46, options.Name or "Input", options.Description)
    nameLabel.Size = UDim2.new(0.42, -12, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset)
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
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
    padding(box, 0, 8, 0, 8)

    local value = box.Text
    local function set(nextValue, silent)
        if options.Numeric then
            local numeric = tonumber(nextValue)
            if not numeric or numeric ~= numeric then
                return
            end
            value = numeric
        else
            value = tostring(nextValue or "")
        end
        box.Text = tostring(value)
        if options.Flag then
            Library.Flags[options.Flag] = value
        end
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
            if not numeric then
                box.Text = value
                return
            end
            value = numeric
            box.Text = tostring(numeric)
        else
            value = box.Text
        end
        if options.Flag then
            Library.Flags[options.Flag] = value
        end
        safeCall(options.Callback, value, enterPressed)
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    if options.Numeric then
        set(options.Default or 0, true)
    else
        set(options.Default or "", true)
    end
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
    }
end

function Section:AddDropdown(options)
    options = options or {}
    local values = options.Values or options.Options or {}
    local multi = options.Multi == true
    local selected = multi and {} or nil
    local open = false
    local baseHeight = 46
    local holder, nameLabel = createControlBase(self, baseHeight, options.Name or "Dropdown")
    nameLabel.Size = UDim2.new(0.42, -12, 0, baseHeight)
    local display = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 9),
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
    padding(display, 0, 26, 0, 8)
    local displayScale = new("UIScale", {
        Scale = 1,
        Parent = display,
    })
    local arrow = text(holder, "▼", 11, "MutedText", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0, 23),
        Size = UDim2.fromOffset(16, 18),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 3,
    })
    local list = new("ScrollingFrame", {
        Visible = false,
        Position = UDim2.fromOffset(10, baseHeight),
        Size = UDim2.new(1, -20, 0, 0),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = holder,
    })
    bindTheme(list, "BackgroundColor3", "Background")
    bindTheme(list, "ScrollBarImageColor3", "Accent")
    corner(list, 5)
    padding(list, 4, 4, 4, 4)
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
            Parent = list,
        })
        corner(searchBox, 4)
        bindTheme(searchBox, "BackgroundColor3", "SurfaceAlt")
        bindTheme(searchBox, "PlaceholderColor3", "MutedText")
        bindTheme(searchBox, "TextColor3", "Text")
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
            local searchHeight = searchBox and 29 or 0
            local height = (count == 0 and 36 or math.min(count, maxVisibleRows) * 28 + 8) + searchHeight
            list.Size = UDim2.new(1, -20, 0, height)
            holder.Size = UDim2.new(1, 0, 0, baseHeight + height + 8)
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
            display.Text = #names > 0 and table.concat(names, ", ") or (options.Placeholder or T("SelectPlaceholder"))
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
        else
            selected = table.find(values, nextValue) and nextValue or nil
        end
        refreshButtons()
        local output = outputValue()
        if options.Flag then Library.Flags[options.Flag] = output end
        if not silent then safeCall(options.Callback, output) end
    end
    local function setOpen(nextOpen)
        open = not not nextOpen
        local listHeight = math.min(#values, maxVisibleRows) * 28 + 8 + (searchBox and 29 or 0)
        if #values == 0 then listHeight = 36 + (searchBox and 29 or 0) end
        if open then
            list.Visible = true
            list.Size = UDim2.new(1, -20, 0, 0)
            list.BackgroundTransparency = 1
            for _, option in pairs(optionButtons) do
                option.TextTransparency = 0.55
                tween(option, 0.2, { TextTransparency = 0 })
            end
            tween(list, 0.2, {
                Size = UDim2.new(1, -20, 0, listHeight),
                BackgroundTransparency = 0.06,
            })
            tween(holder, 0.22, {
                Size = UDim2.new(1, 0, 0, baseHeight + listHeight + 8),
            }, Enum.EasingStyle.Quint)
        else
            local animation = tween(list, 0.16, {
                Size = UDim2.new(1, -20, 0, 0),
                BackgroundTransparency = 1,
            })
            tween(holder, 0.18, { Size = UDim2.new(1, 0, 0, baseHeight) })
            animation.Completed:Connect(function()
                if not open then list.Visible = false end
            end)
        end
        tween(arrow, 0.18, { Rotation = open and 180 or 0 }, Enum.EasingStyle.Back)
    end
    local function rebuild(nextValues)
        values = type(nextValues) == "table" and nextValues or values
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
                Text = "  " .. tostring(item),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = index,
                Parent = list,
            })
            constrainText(option, 8, 11)
            corner(option, 4)
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
            connect(option.Activated, function()
                tween(displayScale, 0.08, { Scale = 0.97 }).Completed:Connect(function()
                    if display.Parent then tween(displayScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back) end
                end)
                if multi then
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
    connect(display.MouseEnter, function()
        tween(displayScale, 0.14, { Scale = 1.015 })
        tween(display, 0.14, { BackgroundColor3 = Library.Theme.Surface })
    end, self.Window._connections)
    connect(display.MouseLeave, function()
        tween(displayScale, 0.14, { Scale = 1 })
        tween(display, 0.14, { BackgroundColor3 = Library.Theme.Background })
    end, self.Window._connections)
    connect(display.Activated, function()
        tween(displayScale, 0.08, { Scale = 0.97 }).Completed:Connect(function()
            if display.Parent then tween(displayScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back) end
        end)
        setOpen(not open)
    end, self.Window._connections)
    connect(UserInputService.InputBegan, function(input)
        if not open or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local point = input.Position
        local topLeft = holder.AbsolutePosition
        local bottomRight = topLeft + holder.AbsoluteSize
        if point.X < topLeft.X or point.X > bottomRight.X or point.Y < topLeft.Y or point.Y > bottomRight.Y then
            setOpen(false)
        end
    end, self.Window._connections)
    rebuild(values)
    set(options.Default, true)
    registerFlagSetter(self.Window, options.Flag, set)
    return {
        Instance = holder,
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
    local holder, nameLabel = createControlBase(self, 42, options.Name or "Keybind")
    nameLabel.Size = UDim2.new(1, -120, 1, 0)
    local keyButton = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(92, 26),
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
    local value = options.Default or Enum.KeyCode.Unknown
    local mode = string.lower(tostring(options.Mode or "Press"))
    if mode ~= "press" and mode ~= "hold" and mode ~= "toggle" then mode = "press" end
    local active = false
    local listening = false
    local ignoreNextActivation = false
    local mouseButtonNames = {
        [Enum.UserInputType.MouseButton1] = "Mouse 1",
        [Enum.UserInputType.MouseButton2] = "Mouse 2",
        [Enum.UserInputType.MouseButton3] = "Mouse 3",
        [Enum.UserInputType.Gamepad1] = "Pad A",
        [Enum.UserInputType.Gamepad2] = "Pad B",
        [Enum.UserInputType.Gamepad3] = "Pad X",
        [Enum.UserInputType.Gamepad4] = "Pad Y",
        [Enum.UserInputType.Gamepad5] = "Pad LB",
        [Enum.UserInputType.Gamepad6] = "Pad RB",
        [Enum.UserInputType.Gamepad7] = "Pad LT",
        [Enum.UserInputType.Gamepad8] = "Pad RT",
    }
    local function isSupported(nextValue)
        return typeof(nextValue) == "EnumItem"
            and (nextValue.EnumType == Enum.KeyCode or mouseButtonNames[nextValue] ~= nil)
    end
    local function keyName(key)
        if key == Enum.KeyCode.Unknown then
            return "None"
        end
        return mouseButtonNames[key] or key.Name
    end
    local function set(nextValue, silent)
        if isSupported(nextValue) then value = nextValue end
        keyButton.Text = keyName(value)
        if options.Flag then Library.Flags[options.Flag] = value end
        if not silent then safeCall(options.Changed, value) end
    end
    bindThemeState(keyButton, function()
        keyButton.TextColor3 = listening and Library.Theme.Accent or Library.Theme.MutedText
    end)
    connect(keyButton.Activated, function()
        if ignoreNextActivation then
            ignoreNextActivation = false
            return
        end
        listening = true
        keyButton.Text = "Press key/mouse..."
        tween(keyButton, 0.15, { TextColor3 = Library.Theme.Accent })
    end, self.Window._connections)
    connect(UserInputService.InputBegan, function(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false
                set(input.KeyCode)
                tween(keyButton, 0.15, { TextColor3 = Library.Theme.MutedText })
            elseif mouseButtonNames[input.UserInputType] then
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
        local matches = value.EnumType == Enum.KeyCode
            and input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == value
            or (mouseButtonNames[value] ~= nil and input.UserInputType == value)
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
    end, self.Window._connections)
    connect(UserInputService.InputEnded, function(input)
        if mode ~= "hold" or not active then return end
        local matches = value.EnumType == Enum.KeyCode
            and input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == value
            or (mouseButtonNames[value] ~= nil and input.UserInputType == value)
        if matches then
            active = false
            safeCall(options.Callback, false, value)
        end
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        IsActive = function() return active end,
        SetMode = function(_, nextMode)
            nextMode = string.lower(tostring(nextMode))
            if nextMode == "press" or nextMode == "hold" or nextMode == "toggle" then
                mode = nextMode
                active = false
                return true
            end
            return false
        end,
    }
end

function Section:AddColorPicker(options)
    options = options or {}
    local holder, nameLabel = createControlBase(self, 44, options.Name or "Color")
    nameLabel.Size = UDim2.new(1, -70, 1, 0)
    local preview = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0, 22),
        Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = options.Default or Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = holder,
    })
    corner(preview, 5)
    stroke(preview, Color3.new(1, 1, 1), 1, 0.7)
    local panel = new("Frame", {
        -- Lives on the window root, not inside the control: the row clips its
        -- own descendants and every later row draws over it, so an in-row panel
        -- ends up cut off and half hidden behind the controls below.
        Visible = false,
        Size = UDim2.fromOffset(280, 186),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 60,
        Parent = self.Window.Root,
    })
    self._overlays = self._overlays or {}
    table.insert(self._overlays, panel)
    bindTheme(panel, "BackgroundColor3", "Background")
    corner(panel, 5)
    padding(panel, 10, 10, 10, 10)
    local labels = { "R", "G", "B" }
    local boxes = {}
    local value = options.Default or Color3.new(1, 1, 1)
    local defaultColor = value
    local alpha = math.clamp(tonumber(options.DefaultAlpha) or 1, 0, 1)
    local hexBox
    local hue, saturation, brightness = value:ToHSV()
    local open = false

    local PANEL_HEIGHT = 186
    local function placePanel()
        if not open then return end
        local rootFrame = self.Window.Root
        local rootSize = rootFrame.AbsoluteSize
        if rootSize.X <= 0 or rootSize.Y <= 0 then return end
        local width = math.clamp(holder.AbsoluteSize.X - 20, 200, math.max(200, rootSize.X - 16))
        local x = holder.AbsolutePosition.X - rootFrame.AbsolutePosition.X + 10
        local y = holder.AbsolutePosition.Y - rootFrame.AbsolutePosition.Y + 44
        -- Flip above the control when the row sits too low in the page.
        if y + PANEL_HEIGHT > rootSize.Y - 6 then
            y = holder.AbsolutePosition.Y - rootFrame.AbsolutePosition.Y - PANEL_HEIGHT
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
    end
    connect(self.Window.Root:GetPropertyChangedSignal("AbsoluteSize"), placePanel, self.Window._connections)
    connect(self.Window.Pages:GetPropertyChangedSignal("Visible"), function()
        if not self.Window.Pages.Visible then setOpen(false) end
    end, self.Window._connections)

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

    local function set(nextValue, silent)
        if typeof(nextValue) ~= "Color3" then return end
        value = nextValue
        hue, saturation, brightness = value:ToHSV()
        preview.BackgroundColor3 = value
        local rgb = {
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5),
        }
        for index, box in ipairs(boxes) do box.Text = tostring(rgb[index]) end
        if hexBox then
            hexBox.Text = string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3])
        end
        if options.Flag then Library.Flags[options.Flag] = value end
        if not silent then safeCall(options.Callback, value, alpha) end
    end
    for index, channel in ipairs(labels) do
        text(panel, channel, 11, "MutedText", {
            Position = UDim2.new((index - 1) / 3, 0, 0, 24),
            Size = UDim2.new(1 / 3, -4, 0, 18),
            ZIndex = 4,
        })
        local box = new("TextBox", {
            Position = UDim2.new((index - 1) / 3, 0, 0, 42),
            Size = UDim2.new(1 / 3, -5, 0, 25),
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
            local rgb = {}
            for i, input in ipairs(boxes) do
                rgb[i] = math.clamp(tonumber(input.Text) or 0, 0, 255)
            end
            set(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
        end, self.Window._connections)
    end
    local sv = new("TextButton", {
        Position = UDim2.fromOffset(0, 76),
        Size = UDim2.new(1, -42, 0, 72),
        BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = panel,
    })
    corner(sv, 4)
    new("UIGradient", {
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
        Position = UDim2.new(1, -32, 0, 76), Size = UDim2.fromOffset(32, 72),
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
        sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        set(Color3.fromHSV(hue, saturation, brightness))
    end
    local hsvDragTarget
    connect(sv.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            hsvDragTarget = sv; inputHSV(sv, input)
        end
    end, self.Window._connections)
    connect(hueBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
    hexBox = new("TextBox", {
        Position = UDim2.new(0, 0, 1, -26),
        Size = options.Alpha == true and UDim2.new(0.5, -4, 0, 24) or UDim2.new(1, -80, 0, 24),
        BackgroundColor3 = Library.Theme.SurfaceAlt, BorderSizePixel = 0,
        ClearTextOnFocus = false, Font = Enum.Font.Code, TextColor3 = Library.Theme.Text,
        TextSize = 11, ZIndex = 4, Parent = panel,
    })
    corner(hexBox, 4)
    bindTheme(hexBox, "BackgroundColor3", "SurfaceAlt")
    bindTheme(hexBox, "TextColor3", "Text")
    local alphaBox
    if options.Alpha == true then
        alphaBox = new("TextBox", {
            Position = UDim2.new(0.5, 4, 1, -26), Size = UDim2.new(0.5, -84, 0, 24),
            BackgroundColor3 = Library.Theme.SurfaceAlt, BorderSizePixel = 0,
            ClearTextOnFocus = false, Font = Enum.Font.Code, TextColor3 = Library.Theme.Text,
            Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%", PlaceholderText = "Alpha",
            TextSize = 10, ZIndex = 4, Parent = panel,
        })
        corner(alphaBox, 4)
        bindTheme(alphaBox, "BackgroundColor3", "SurfaceAlt")
        bindTheme(alphaBox, "TextColor3", "Text")
        connect(alphaBox.FocusLost, function()
            alpha = math.clamp((tonumber(alphaBox.Text:gsub("%%", "")) or (alpha * 100)) / 100, 0, 1)
            alphaBox.Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%"
            safeCall(options.Callback, value, alpha)
        end, self.Window._connections)
    end
    local reset = new("TextButton", {
        Position = UDim2.new(1, -72, 1, -26), Size = UDim2.fromOffset(72, 24),
        BackgroundColor3 = Library.Theme.SurfaceAlt, BorderSizePixel = 0,
        Text = T("Reset"), TextColor3 = Library.Theme.MutedText, Font = Enum.Font.GothamMedium,
        TextSize = 10, ZIndex = 4, Parent = panel,
    })
    corner(reset, 4)
    bindTheme(reset, "BackgroundColor3", "SurfaceAlt")
    bindTheme(reset, "TextColor3", "MutedText")
    connect(hexBox.FocusLost, function()
        local raw = hexBox.Text:gsub("#", "")
        if raw:match("^%x%x%x%x%x%x$") then
            set(Color3.fromRGB(tonumber(raw:sub(1, 2), 16), tonumber(raw:sub(3, 4), 16), tonumber(raw:sub(5, 6), 16)))
        else
            set(value, true)
        end
    end, self.Window._connections)
    connect(reset.Activated, function() set(defaultColor) end, self.Window._connections)
    connect(preview.Activated, function()
        setOpen(not open)
    end, self.Window._connections)
    connect(closePicker.Activated, function()
        setOpen(false)
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        GetHSV = function() return hue, saturation, brightness end,
        SetHSV = function(_, h, s, v, silent)
            set(Color3.fromHSV(math.clamp(h, 0, 1), math.clamp(s, 0, 1), math.clamp(v, 0, 1)), silent)
        end,
        GetAlpha = function() return alpha end,
        SetAlpha = function(_, nextAlpha, silent)
            alpha = math.clamp(tonumber(nextAlpha) or alpha, 0, 1)
            if alphaBox then alphaBox.Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%" end
            if not silent then safeCall(options.Callback, value, alpha) end
        end,
        Reset = function() set(defaultColor) end,
    }
end

function Section:AddDivider(options)
    options = type(options) == "table" and options or { Text = options }
    local holder = new("Frame", {
        Name = options.Text or "Divider",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, options.Text and 28 or 17),
        Parent = self.Container,
    })
    local line = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = holder,
    })
    bindTheme(line, "BackgroundColor3", "Border")
    if options.Text then
        local caption = text(holder, options.Text, 10, "MutedText", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(math.max(70, #tostring(options.Text) * 7 + 18), 20),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
        bindTheme(caption, "BackgroundColor3", "Background")
        caption.BackgroundTransparency = 0
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
    local callback = options.Callback
    local mapped = copyTable(options)
    mapped.Numeric = true
    mapped.Default = math.clamp(tonumber(options.Default) or 0, minimum, maximum)
    mapped.Callback = function(raw, enterPressed)
        local number = tonumber(raw)
        if not number or number ~= number then return end
        number = math.clamp(math.floor(number / increment + 0.5) * increment, minimum, maximum)
        if options.Flag then Library.Flags[options.Flag] = number end
        safeCall(callback, number, enterPressed)
    end
    local input = self:AddInput(mapped)
    local originalSet = input.Set
    function input:Set(value, silent)
        local number = tonumber(value)
        if not number or number ~= number then return self end
        number = math.clamp(math.floor(number / increment + 0.5) * increment, minimum, maximum)
        originalSet(self, tostring(number), silent)
        if options.Flag then Library.Flags[options.Flag] = number end
        return self
    end
    local originalGet = input.Get
    function input:Get()
        return tonumber(originalGet(self))
    end
    local box = input.Instance and input.Instance:FindFirstChildWhichIsA("TextBox")
    if box then
        connect(box.FocusLost, function()
            input:Set(box.Text, true)
        end, self.Window._connections)
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
    local holder, nameLabel = createControlBase(self, options.Description and 78 or 66, options.Name or "Segmented", options.Description)
    nameLabel.Size = UDim2.new(1, -24, 0, 18)
    local row = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 1, -32),
        Size = UDim2.new(1, -20, 0, 24),
        Parent = holder,
    })
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
            button.BackgroundTransparency = item == value and 0.05 or 0.72
            button.TextColor3 = item == value and Library.Theme.Text or Library.Theme.MutedText
        end
    end
    local function set(nextValue, silent)
        if not table.find(values, nextValue) then return end
        value = nextValue
        if options.Flag then Library.Flags[options.Flag] = value end
        render()
        if not silent then safeCall(options.Callback, value) end
    end
    for _, item in ipairs(values) do
        local button = new("TextButton", {
            BackgroundColor3 = Library.Theme.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(1 / math.max(1, #values), -5, 1, 0),
            AutoButtonColor = false,
            Font = Enum.Font.GothamMedium,
            Text = tostring(item),
            TextSize = 10,
            Parent = row,
        })
        corner(button, 5)
        buttons[item] = button
        connect(button.Activated, function() if not disabled then set(item) end end, self.Window._connections)
    end
    bindThemeState(holder, render)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
        SetDisabled = function(_, nextDisabled)
            disabled = not not nextDisabled
            for _, button in pairs(buttons) do button.Active = not disabled end
        end,
    }
end

function Section:AddRangeSlider(options)
    options = options or {}
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    local default = type(options.Default) == "table" and options.Default or { minimum, maximum }
    local holder = new("Frame", {
        Name = options.Name or "RangeSlider",
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        Parent = self.Container,
    })
    new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
    local nested = { Container = holder, Window = self.Window }
    local low, high
    local function publish(silent)
        local result = { low:Get(), high:Get() }
        if options.Flag then Library.Flags[options.Flag] = result end
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
local function enrichControl(control, section, options, ownedConnections, methodName)
    if type(control) ~= "table" or not control.Instance then return control end
    options = type(options) == "table" and options or {}
    local instance = control.Instance
    local destroyed = false
    local flag = options.Flag
    local setter = flag and section.Window._flagSetters[flag]
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            descendant.Selectable = Library._gamepadEnabled ~= false
            connect(descendant.SelectionGained, function()
                if instance and instance.Parent then tween(instance, 0.12, { BackgroundTransparency = 0.58 }) end
            end, section.Window._connections)
            connect(descendant.SelectionLost, function()
                if instance and instance.Parent then tween(instance, 0.12, { BackgroundTransparency = Library.Theme.ControlTransparency or 0.8 }) end
            end, section.Window._connections)
        end
    end
    -- Controls write Library.Flags directly rather than through SetFlag, so a
    -- raw registry hook cannot see control:Set(). Fan out here instead.
    local VALUE_METHODS = { Set = true, Refresh = true, SetValues = true }
    for _, methodName in ipairs({ "Set", "Get", "Fire", "Refresh", "SetValues", "Search", "SetOpen" }) do
        local original = control[methodName]
        if type(original) == "function" then
            control[methodName] = function(self, ...)
                if destroyed then return nil end
                if self.Disabled and (methodName == "Fire" or methodName == "SetOpen") then return nil end
                local result = original(self, ...)
                if flag and VALUE_METHODS[methodName] then
                    Library:_notifyFlagChanged(flag)
                end
                return result
            end
        end
    end

    if options.Tooltip and instance:IsA("GuiObject") then
        local tooltip
        local function hideTooltip()
            if tooltip then tooltip:Destroy(); tooltip = nil end
        end
        connect(instance.MouseEnter, function()
            if destroyed or tooltip then return end
            tooltip = new("TextLabel", {
                Name = "Tooltip",
                BackgroundColor3 = Library.Theme.Surface,
                BackgroundTransparency = 0.02,
                BorderSizePixel = 0,
                AutomaticSize = Enum.AutomaticSize.XY,
                Text = tostring(options.Tooltip),
                TextColor3 = Library.Theme.Text,
                TextSize = 11,
                Font = Enum.Font.Gotham,
                TextWrapped = true,
                Size = UDim2.fromOffset(180, 0),
                ZIndex = 200,
                Parent = ScreenGui,
            })
            padding(tooltip, 7, 9, 7, 9); corner(tooltip, 5)
            local mouse = UserInputService:GetMouseLocation()
            tooltip.Position = UDim2.fromOffset(mouse.X + 12, mouse.Y + 12)
        end, section.Window._connections)
        connect(instance.MouseLeave, hideTooltip, section.Window._connections)
    end

    -- Optional dependency gating: the control only shows while every listed
    -- flag is truthy. Search and Destroy both respect the result.
    local dependency
    if options.DependsOn ~= nil then
        local deps = options.DependsOn
        if type(deps) == "string" then deps = { deps } end
        if type(deps) == "table" and #deps > 0 then
            dependency = { Deps = deps, Handles = {}, Met = true }
            local function satisfied()
                for _, dep in ipairs(dependency.Deps) do
                    if not Library:GetFlag(dep, false) then
                        return false
                    end
                end
                return true
            end
            local function update()
                if destroyed or not instance then return end
                local met = satisfied()
                dependency.Met = met
                instance:SetAttribute("BloodshotDependencyMet", met)
                if not met then
                    instance.Visible = false
                elseif not dependency.HiddenBySearch then
                    instance.Visible = true
                end
                for _, descendant in ipairs(instance:GetDescendants()) do
                    if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                        descendant.Selectable = met
                    end
                end
            end
            dependency.Update = update
            for _, dep in ipairs(deps) do
                table.insert(dependency.Handles, Library:OnFlagChanged(dep, update))
            end
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
                    for _, dep in ipairs(list) do
                        table.insert(dependency.Handles, Library:OnFlagChanged(dep, update))
                    end
                end
                update()
                return self
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
            for _, descendant in ipairs(instance:GetDescendants()) do
                if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                    descendant.Active = not disabled
                    descendant.Selectable = not disabled
                end
            end
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
            for _, connection in ipairs(ownedConnections or {}) do
                if connection.Connected then connection:Disconnect() end
            end
            if flag and Library._flagSetters[flag] == setter then
                Library._flagSetters[flag] = nil
                section.Window._flagSetters[flag] = nil
                Library._flagTypes[flag] = nil
            end
            if instance then instance:Destroy(); instance = nil end
            self.Instance = nil
        end
    end
    if flag and control.Get then
        local ok, value = pcall(control.Get, control)
        if ok then Library._flagTypes[flag] = typeof(value) end
    end
    return control
end

for _, methodName in ipairs({
    "AddLabel", "AddParagraph", "AddButton", "AddToggle", "AddSlider",
    "AddInput", "AddDropdown", "AddKeybind", "AddColorPicker", "AddDivider",
    "AddNumberInput", "AddRadio", "AddSegmented", "AddRangeSlider",
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
        if self.Controls and not table.find(self.Controls, control) then
            table.insert(self.Controls, control)
            -- Same reasoning as tabs/sections: without an explicit LayoutOrder
            -- the section's UIListLayout would sort controls by Name.
            if control.Instance then
                control.Instance.LayoutOrder = #self.Controls
            end
        end
        return control
    end
end

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
    connect(collapseButton.Activated, function()
        if section._dragState and section._dragState.Dragged then
            section._dragState.Dragged = false
            return
        end
        section:ToggleCollapsed()
    end, self.Window._connections)
    section.CollapseButton = collapseButton
    section:SetCollapsed(options.Collapsed == true)
    return section
end

function Section:SetVisible(visible)
    if self.Frame then self.Frame.Visible = not not visible end
    return self
end

function Section:SetDisabled(disabled)
    self.Disabled = not not disabled
    if self.Container then
        for _, descendant in ipairs(self.Container:GetDescendants()) do
            if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
                descendant.Active = not self.Disabled
                descendant.Selectable = not self.Disabled
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
    return self
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
            for _, entry in ipairs(snapshot.controls) do
                if entry.instance.Parent then entry.instance.Visible = entry.visible end
            end
            for _, section in ipairs(self.Sections) do
                for _, control in ipairs(section.Container:GetChildren()) do
                    if control:IsA("GuiObject")
                        and control:GetAttribute("BloodshotDependencyMet") == false then
                        control.Visible = false
                    end
                end
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
        local controls = {}
        local sections = {}
        for _, section in ipairs(self.Sections) do
            sections[#sections + 1] = { frame = section.Frame, visible = section.Frame.Visible }
            for _, control in ipairs(section.Container:GetChildren()) do
                if control:IsA("GuiObject") then
                    controls[#controls + 1] = { instance = control, visible = control.Visible }
                end
            end
        end
        self._searchSnapshot = { controls = controls, sections = sections }
    end

    local visibleCount = 0
    for _, section in ipairs(self.Sections) do
        local sectionMatch = string.find(string.lower(section.Name), query, 1, true) ~= nil
        local sectionVisible = sectionMatch
        for _, control in ipairs(section.Container:GetChildren()) do
            if control:IsA("GuiObject") then
                local matches = sectionMatch
                    or string.find(string.lower(control.Name), query, 1, true) ~= nil
                local blocked = control:GetAttribute("BloodshotDependencyMet") == false
                control.Visible = matches and not blocked
                sectionVisible = sectionVisible or matches
            end
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
    if window.ActiveTab == self then window.ActiveTab = nil end
    window._tabByName[self.Name] = nil
    local index = table.find(window.Tabs, self)
    if index then table.remove(window.Tabs, index) end
    self.Button:Destroy()
    self.Page:Destroy()
    self.Button = nil
    self.Page = nil
    for _, candidate in ipairs(window.Tabs) do
        if candidate.Button and candidate.Button.Visible then window:SelectTab(candidate); break end
    end
end

local Window = {}
Window.__index = Window

function Window:SetVisible(visible)
    if self._destroyed then return end
    self.Visible = not not visible
    if self.Visible then
        self.Root.Visible = true
        self._scale.Scale = 0.9
        self.Root.BackgroundTransparency = 1
        tween(self._scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
        tween(self.Root, 0.2, { BackgroundTransparency = 0 })
    else
        local animation = tween(self._scale, 0.2, { Scale = 0.94 })
        tween(self.Root, 0.2, { BackgroundTransparency = 1 })
        animation.Completed:Connect(function()
            if not self.Visible and self.Root then self.Root.Visible = false end
        end)
    end
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
    self._tabsReorderable = not not enabled
    return self._tabsReorderable
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

function Window:SetToggleKey(input)
    if typeof(input) ~= "EnumItem" then return false, "Toggle key must be an EnumItem" end
    self._toggleKey = input
    return true
end

function Window:SetTitle(title, subtitle)
    if self._titleLabel then self._titleLabel.Text = tostring(title or "") end
    if subtitle ~= nil and self._subtitleLabel then self._subtitleLabel.Text = tostring(subtitle) end
    return self
end

-- Persistence helpers used by SaveGeometry/LoadGeometry.
function Window:GetGeometry()
    if self._destroyed or not self.Root then return nil end
    return {
        Position = self.Root.Position,
        Size = self._size,
        Minimized = self.Minimized,
        Visible = self.Visible,
    }
end

function Window:SetGeometry(geometry)
    if self._destroyed or type(geometry) ~= "table" then return false end
    if typeof(geometry.Size) == "UDim2" then
        self:SetSize(geometry.Size)
    end
    if typeof(geometry.Position) == "UDim2" then
        self.Root.Position = geometry.Position
    end
    return true
end

function Window:Toggle()
    self:SetVisible(not self.Visible)
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
            end
            if not self._destroyed then
                self._minimizeAnimating = false
            end
        end)
    end

    if self.MinimizeButton then
        self.MinimizeButton.Text = minimized and "+" or "-"
    end
end

function Window:ToggleMinimized()
    self:SetMinimized(not self.Minimized)
end

function Window:SelectTab(tab)
    if type(tab) == "string" then
        tab = self._tabByName[tab]
    end
    if not tab or tab.Disabled or self.ActiveTab == tab then return end
    if self.ActiveTab then
        self.ActiveTab.Page.Visible = false
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
end

function Window:AddTab(name, icon)
    if type(name) == "table" then
        icon = name.Icon
        name = name.Name or name.Title
    end
    name = tostring(name or "Tab")
    local button = new("TextButton", {
        Name = name,
        -- See Tab:AddSection: creation order must win over alphabetical order.
        LayoutOrder = #self.Tabs + 1,
        BackgroundColor3 = Library.Theme.SurfaceAlt,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = self._layout.SidebarHorizontal
            and UDim2.fromOffset(self._layout.TabWidth, self._layout.TabHeight)
            or UDim2.new(1, 0, 0, self._layout.TabHeight),
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = icon and ("      " .. name) or ("   " .. name),
        TextColor3 = Library.Theme.MutedText,
        TextTransparency = 0.45,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = self.TabList,
    })
    constrainText(button, 9, 12)
    corner(button, 5)
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
            Parent = button,
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
        Parent = button,
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
    connect(button.Activated, function() self:SelectTab(tab) end, self._connections)
    if self._tabsReorderable then
        local dragging, started, startPoint = false, false, nil
        connect(button.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            dragging, started, startPoint = true, false, input.Position
        end, self._connections)
        connect(UserInputService.InputChanged, function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if not started then
                if (input.Position - startPoint).Magnitude < 6 then return end
                started = true
            end
            local vertical = not self._layout.SidebarHorizontal
            local probe = vertical and input.Position.Y or input.Position.X
            local best, bestDistance = 1, math.huge
            for slot, sibling in ipairs(self.TabList:GetChildren()) do
                if sibling:IsA("GuiButton") and sibling ~= button then
                    local centre = vertical
                        and (sibling.AbsolutePosition.Y + sibling.AbsoluteSize.Y / 2)
                        or (sibling.AbsolutePosition.X + sibling.AbsoluteSize.X / 2)
                    local distance = math.abs(probe - centre)
                    if distance < bestDistance then
                        best, bestDistance = slot, distance
                    end
                end
            end
            local current = 1
            for slot, sibling in ipairs(self.TabList:GetChildren()) do
                if sibling == button then current = slot break end
            end
            if best ~= current then
                reorderList(self.TabList, button, best)
            end
        end, self._connections)
        connect(UserInputService.InputEnded, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                dragging, started = false, false
            end
        end, self._connections)
    end
    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
end

function Window:BringToFront()
    return Library:FocusWindow(self, false)
end

function Window:SetTheme(overrides)
    if overrides == nil then
        self._themeOverrides = nil
        self._themeRestore = nil
        if Library._focusedWindow == self then Library:SetTheme(DEFAULT_THEME) end
        return true
    end
    if type(overrides) ~= "table" then
        return false, "Theme overrides must be a table"
    end
    self._themeOverrides = copyTable(overrides)
    if Library._focusedWindow == self then
        self._themeRestore = copyTable(Library.Theme)
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
    local target = ((index - 1 + (direction or 1)) % #list) + 1
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
        end
    end
    table.clear(self._flagSetters)
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
    if Library._focusedWindow == self then
        Library._focusedWindow = nil
    end
end

function Library:CreateWindow(options)
    options = options or {}
    local size = options.Size or UDim2.fromOffset(680, 470)
    if typeof(size) ~= "UDim2"
        or (size.X.Scale == 0 and size.X.Offset <= 0)
        or (size.Y.Scale == 0 and size.Y.Offset <= 0) then
        size = UDim2.fromOffset(680, 470)
    end
    local sidebarWidth = math.clamp(tonumber(options.SidebarWidth) or 158, 110, 280)
    local sidebarHeight = math.clamp(tonumber(options.SidebarHeight) or 72, 52, 130)
    local topbarHeight = math.clamp(tonumber(options.TopbarHeight) or 58, 44, 96)
    local contentPadding = math.clamp(tonumber(options.ContentPadding) or 14, 6, 40)
    local sidebarPadding = math.clamp(tonumber(options.SidebarPadding) or 10, 4, 28)
    local tabHeight = math.clamp(tonumber(options.TabHeight) or 36, 28, 56)
    local tabWidth = math.clamp(tonumber(options.TabWidth) or 120, 72, 220)
    local tabSpacing = math.clamp(tonumber(options.TabSpacing) or 5, 0, 20)
    local sectionSpacing = math.clamp(tonumber(options.SectionSpacing) or 14, 0, 32)
    local controlSpacing = math.clamp(tonumber(options.ControlSpacing) or 7, 0, 24)
    local sidebarSide = string.lower(tostring(options.SidebarSide or "Left"))
    local sidebarOnRight = sidebarSide == "right"
    local sidebarOnBottom = sidebarSide == "bottom"
    local sidebarOnTop = sidebarSide == "top"
    local sidebarHorizontal = sidebarOnBottom or sidebarOnTop
    local minimumSize = typeof(options.MinimumSize) == "Vector2"
        and options.MinimumSize
        or Vector2.new(520, 360)
    minimumSize = Vector2.new(
        math.clamp(minimumSize.X, 240, 4096),
        math.clamp(minimumSize.Y, 180, 2160)
    )
    local minimizedWidth = math.clamp(tonumber(options.MinimizedWidth) or 320, 220, 480)
    local connections = {}
    local root = new("Frame", {
        Name = options.Title or "Bloodshot",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = options.Position or UDim2.fromScale(0.5, 0.5),
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
            backgroundTween:Play()
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
            animation:Play()
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
    local close = new("TextButton", {
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
    bindTheme(close, "BackgroundColor3", "SurfaceAlt")
    bindTheme(close, "TextColor3", "MutedText")
    corner(close, 6)
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
        },
        _connections = connections,
        _flagSetters = {},
        _backgroundTweens = backgroundTweens,
        _tabByName = {},
        _titleLabel = titleLabel,
        _subtitleLabel = subtitleLabel,
        _toggleKey = options.ToggleKey or Enum.KeyCode.RightShift,
        _tabsReorderable = options.ReorderableTabs ~= false,
        _reorderEnabled = options.Reorderable ~= false,
        _themeOverrides = nil,
        _geometryKey = tostring(options.GeometryKey or sanitizeProfileName(options.Title or ("window" .. #self._windows))),
    }, Window)
    table.insert(self._windows, window)
    table.insert(self._windowOrder, window)
    -- A new window opens in front, otherwise it lands behind every window that
    -- already exists and the one you just made looks like it vanished.
    self:FocusWindow(window, false)

    makeDraggable(topbar, root, connections)
    connect(root.InputBegan, function()
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
        connect(resizeHandle.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                resizeStart = input.Position
                startSize = root.AbsoluteSize
            end
        end, connections)
        connect(UserInputService.InputChanged, function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - resizeStart
                window:SetSize(UDim2.fromOffset(startSize.X + delta.X, startSize.Y + delta.Y))
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
    connect(close.MouseEnter, function()
        tween(close, 0.15, {
            BackgroundTransparency = 0,
            TextColor3 = Library.Theme.Error,
        })
    end, connections)
    connect(close.MouseLeave, function()
        tween(close, 0.15, {
            BackgroundTransparency = 1,
            TextColor3 = Library.Theme.MutedText,
        })
    end, connections)
    connect(close.Activated, function()
        if options.DestroyOnClose then window:Destroy() else window:SetVisible(false) end
    end, connections)
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
        connect(minimize.Activated, function()
            window:ToggleMinimized()
        end, connections)
    end

    connect(UserInputService.InputBegan, function(input, processed)
        if not processed and (input.KeyCode == window._toggleKey or input.UserInputType == window._toggleKey) then
            window:Toggle()
        end
    end, connections)

    text(sidebar, T("MadeWith"), 9, "MutedText", {
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
    return window
end

function Library:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self:AutoSave(nil)
    for _, binding in ipairs(self._bindings or {}) do
        if binding.Unbind then binding.Unbind() end
    end
    table.clear(self._bindings or {})
    table.clear(self._dependencySubs or {})
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)
    for index = #self._windows, 1, -1 do
        self._windows[index]:Destroy()
    end
    for index = #self._windowOrder, 1, -1 do
        self._windowOrder[index]:Disconnect()
    end
    table.clear(self._windowOrder)
    self._focusedWindow = nil
    table.clear(self._themeBindings)
    table.clear(self._flagSetters)
    table.clear(self._flagListeners)
    table.clear(self._hooked)
    table.clear(self._notifications)
    self._configAdapter = nil
    if self.Gui then self.Gui:Destroy() end
end

-- Declarative UI construction. Defined at the end of the file so the
-- Section/Window tables are already in scope.
local function buildControl(section, controlSpec, result)
    if type(controlSpec) ~= "table" then
        return nil
    end
    local options = copyTable(controlSpec)
    local controlType = options.Type or options.type or options.Control
    options.Type, options.type, options.Control = nil, nil, nil
    local children = options.Controls or options.controls
    options.Controls, options.controls = nil, nil
    if type(controlType) ~= "string" then
        return nil, "Control spec needs a Type"
    end
    local method = Section["Add" .. controlType]
    if type(method) ~= "function" then
        return nil, "Unknown control type: " .. tostring(controlType)
    end
    local control = method(section, options)
    local key = options.Flag or options.Name
    if key ~= nil then
        result.Controls[key] = control
    end
    if type(children) == "table" then
        for _, childSpec in ipairs(children) do
            buildControl(section, childSpec, result)
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
    for flag, value in pairs(spec.Flags or {}) do
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
    local summary = summarySection:AddParagraph({ Title = "Runtime", Content = "..." })
    local flagBody = flagSection:AddParagraph({ Title = "Flag values", Content = "" })

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
