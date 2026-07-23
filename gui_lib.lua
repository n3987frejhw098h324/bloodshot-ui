if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Library = {
    Version = "1.0.0",
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
    },
    _windows = {},
    _connections = {},
    _themeBindings = {},
    _flagSetters = {},
    _notifications = {},
    _destroyed = false,
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
        CornerRadius = UDim.new(0, radius or 6),
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
    local info = TweenInfo.new(
        duration or 0.18,
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
        Font = properties.Font or Enum.Font.Gotham,
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
    Library._flagSetters[flag] = setter
    window._flagSetters[flag] = setter
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
        if self.Theme[key] ~= nil and typeof(value) == "Color3" then
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

function Library:SetFlag(flag, value, silent)
    self.Flags[flag] = value
    local setter = self._flagSetters[flag]
    if setter then
        setter(value, silent)
    end
end

function Library:GetFlag(flag, fallback)
    local value = self.Flags[flag]
    if value == nil then
        return fallback
    end
    return value
end

function Library:SaveConfig()
    local encoded = {}
    for flag, value in pairs(self.Flags) do
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
    local ok, result = pcall(HttpService.JSONEncode, HttpService, encoded)
    if not ok then
        return nil, "Unable to encode configuration: " .. tostring(result)
    end
    return result
end

function Library:LoadConfig(json, silent)
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
    if not ok or type(decoded) ~= "table" then
        return false, "Invalid configuration"
    end
    for flag, value in pairs(decoded) do
        if type(value) == "table" and value.__type == "Color3" then
            local rgb = value.value
            if type(rgb) ~= "table"
                or type(rgb[1]) ~= "number"
                or type(rgb[2]) ~= "number"
                or type(rgb[3]) ~= "number" then
                return false, "Invalid Color3 value for flag " .. tostring(flag)
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
        self:SetFlag(flag, value, silent)
    end
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

    text(card, options.Title or "Notification", 14, "Text", {
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
    tween(holder, 0.24, { BackgroundTransparency = 0.8 })
    connect(holder.MouseEnter, function()
        tween(holder, 0.16, { BackgroundTransparency = 0.68 })
        tween(holderStroke, 0.16, { Transparency = 0.2 })
    end, section.Window._connections)
    connect(holder.MouseLeave, function()
        tween(holder, 0.16, { BackgroundTransparency = 0.8 })
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
    return holder, nameLabel, descriptionLabel
end

local Section = {}
Section.__index = Section

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
        PlaceholderText = options.Placeholder or "Enter value...",
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
    local function renderText()
        if multi then
            local names = {}
            for _, item in ipairs(values) do
                if selected[item] then
                    table.insert(names, tostring(item))
                end
            end
            display.Text = #names > 0 and table.concat(names, ", ") or (options.Placeholder or "Select...")
        else
            display.Text = selected ~= nil and tostring(selected) or (options.Placeholder or "Select...")
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
                        selected[enabled] = true
                    elseif enabled then
                        selected[key] = true
                    end
                end
            end
        else
            selected = nextValue
        end
        refreshButtons()
        local output = outputValue()
        if options.Flag then Library.Flags[options.Flag] = output end
        if not silent then safeCall(options.Callback, output) end
    end
    local function setOpen(nextOpen)
        open = not not nextOpen
        local listHeight = math.min(#values * 28 + 8, 144)
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
        values = nextValues or values
        for _, button in pairs(optionButtons) do button:Destroy() end
        table.clear(optionButtons)
        for _, item in ipairs(values) do
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
    local listening = false
    local function keyName(key)
        return key == Enum.KeyCode.Unknown and "None" or key.Name
    end
    local function set(nextValue, silent)
        if typeof(nextValue) == "EnumItem" then value = nextValue end
        keyButton.Text = keyName(value)
        if options.Flag then Library.Flags[options.Flag] = value end
        if not silent then safeCall(options.Changed, value) end
    end
    bindThemeState(keyButton, function()
        keyButton.TextColor3 = listening and Library.Theme.Accent or Library.Theme.MutedText
    end)
    connect(keyButton.Activated, function()
        listening = true
        keyButton.Text = "Press a key..."
        tween(keyButton, 0.15, { TextColor3 = Library.Theme.Accent })
    end, self.Window._connections)
    connect(UserInputService.InputBegan, function(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false
                set(input.KeyCode)
                tween(keyButton, 0.15, { TextColor3 = Library.Theme.MutedText })
            end
            return
        end
        if not processed and input.KeyCode == value then
            safeCall(options.Callback, value)
        end
    end, self.Window._connections)
    registerFlagSetter(self.Window, options.Flag, set)
    set(value, true)
    return {
        Instance = holder,
        Set = function(_, nextValue, silent) set(nextValue, silent) end,
        Get = function() return value end,
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
        Visible = false,
        Position = UDim2.fromOffset(10, 44),
        Size = UDim2.new(1, -20, 0, 140),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = holder,
    })
    bindTheme(panel, "BackgroundColor3", "Background")
    corner(panel, 5)
    padding(panel, 10, 10, 10, 10)
    local labels = { "R", "G", "B" }
    local boxes = {}
    local value = options.Default or Color3.new(1, 1, 1)
    local open = false

    local function setOpen(nextOpen)
        open = not not nextOpen
        panel.Visible = open
        holder.Size = UDim2.new(1, 0, 0, open and 192 or 44)
    end

    local closePicker = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(48, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = "Close",
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
        preview.BackgroundColor3 = value
        local rgb = {
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5),
        }
        for index, box in ipairs(boxes) do box.Text = tostring(rgb[index]) end
        if options.Flag then Library.Flags[options.Flag] = value end
        if not silent then safeCall(options.Callback, value) end
    end
    for index, channel in ipairs(labels) do
        text(panel, channel, 11, "MutedText", {
            Position = UDim2.fromOffset(0, 24 + (index - 1) * 32),
            Size = UDim2.fromOffset(18, 26),
            ZIndex = 4,
        })
        local box = new("TextBox", {
            Position = UDim2.fromOffset(24, 24 + (index - 1) * 32),
            Size = UDim2.new(1, -24, 0, 25),
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
    }
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
        Frame = sectionFrame,
        Container = container,
        Window = self.Window,
    }, Section)
    return section
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

function Window:Toggle()
    self:SetVisible(not self.Visible)
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
        self._minimizeOffsetY = math.max(0, (self.Root.AbsoluteSize.Y - self._topbarHeight) * 0.5)
        local minimizedWidth = math.min(self.Root.AbsoluteSize.X, self._minimizedWidth)
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
        local animation = tween(self.Root, 0.28, {
            Position = UDim2.new(
                self.Root.Position.X.Scale,
                self.Root.Position.X.Offset,
                self.Root.Position.Y.Scale,
                self.Root.Position.Y.Offset + self._minimizeOffsetY
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
        self.MinimizeButton.Text = minimized and "+" or "—"
    end
end

function Window:ToggleMinimized()
    self:SetMinimized(not self.Minimized)
end

function Window:SelectTab(tab)
    if type(tab) == "string" then
        tab = self._tabByName[tab]
    end
    if not tab or self.ActiveTab == tab then return end
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
    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
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
end

function Library:CreateWindow(options)
    options = options or {}
    local size = options.Size or UDim2.fromOffset(680, 470)
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
    text(topbar, options.Title or "Bloodshot", 17, "Text", {
        Position = UDim2.fromOffset(18, titleTop),
        Size = UDim2.new(1, -140, 0, 22),
        Font = Enum.Font.GothamBold,
    })
    text(topbar, options.Subtitle or ("UI Library · " .. self.Version), 10, "MutedText", {
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
        Text = "×",
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
            Text = "—",
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
            and UDim2.new(1, -(sidebarPadding * 2 + 178), 0, tabHeight)
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
    }, Window)
    table.insert(self._windows, window)

    makeDraggable(topbar, root, connections)
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

    local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
    connect(UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == toggleKey then
            window:Toggle()
        end
    end, connections)

    text(sidebar, "Made with <3 by R", 9, "MutedText", {
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
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)
    for index = #self._windows, 1, -1 do
        self._windows[index]:Destroy()
    end
    table.clear(self._themeBindings)
    table.clear(self._flagSetters)
    table.clear(self._notifications)
    if self.Gui then self.Gui:Destroy() end
end

return Library
