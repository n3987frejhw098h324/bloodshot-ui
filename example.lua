local Bloodshot = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/n3987frejhw098h324/bloodshot-ui/refs/heads/main/gui_lib.lua"
))()

-- window thing
local window = Bloodshot:CreateWindow({
    Title = "blood shot gui",
    Subtitle = "it has buttons ok",
    ToggleKey = Enum.KeyCode.RightShift,
    Size = UDim2.fromOffset(700, 490),
    AnimatedBackground = true,
    AnimationStyle = "Sweep",
    AnimationSpeed = 8,
    BackgroundParticles = true,
    ParticleCount = 24,
    ParticleSpeed = 12,
    SidebarSide = "Left",
    SidebarWidth = 158,
    SidebarHeight = 72,
    SidebarPadding = 10,
    TopbarHeight = 58,
    ContentPadding = 14,
    TabHeight = 36,
    TabWidth = 120,
    TabSpacing = 5,
    SectionSpacing = 14,
    ControlSpacing = 7,
    MinimumSize = Vector2.new(520, 360),
    MinimizeButton = true,
    MinimizedWidth = 320,
    ContextMenu = true,
    QuickSearch = true,
    Footer = "ctrl+k to search",
})

local mainTab = window:AddTab("stuff")
local generalSection = mainTab:AddSection("main things")

generalSection:AddParagraph({
    Title = "hello",
    Content = "this do the gui things. click whatever",
})

generalSection:AddLabel({
    Text = "this is text. ok cool",
    Color = "MutedText",
})

generalSection:AddButton({
    Name = "make popup",
    Description = "popup happen",
    Callback = function()
        Bloodshot:Notify({
            Title = "yo",
            Content = "it worked lol",
            Type = "Success",
            Duration = 4,
        })
    end,
})

local featureToggle = generalSection:AddToggle({
    Name = "do the thing",
    Description = "turn thing on probably",
    Flag = "featureEnabled",
    Default = true,
    Callback = function(enabled)
        Bloodshot:Notify({
            Title = "thing changed",
            Content = enabled and "thing is on" or "thing is off",
            Type = enabled and "Success" or "Warning",
            Duration = 2.5,
        })
    end,
})

generalSection:AddButton({
    Name = "change it with code",
    Description = "same thing but code did it",
    Callback = function()
        Bloodshot:SetFlag("featureEnabled", not Bloodshot:GetFlag("featureEnabled", false))
        print("thing:", featureToggle:Get())
    end,
})

local settingsSection = mainTab:AddSection("other stuff")

settingsSection:AddSlider({
    Name = "speed",
    Flag = "walkSpeed",
    Min = 8,
    Max = 50,
    Default = 16,
    Increment = 1,
    Suffix = " studs/s",
    Callback = function(value)
        print("speed is", value)
    end,
})

settingsSection:AddInput({
    Name = "name or whatever",
    Flag = "displayName",
    Default = "Player",
    Placeholder = "type here",
    Callback = function(value, enterPressed)
        print("name", value, "enter?", enterPressed)
    end,
})

settingsSection:AddDropdown({
    Name = "graphics",
    Flag = "quality",
    Values = { "Low", "Medium", "High", "Ultra" },
    Default = "High",
    Callback = function(value)
        print("graphics", value)
    end,
})

settingsSection:AddDropdown({
    Name = "shiny things",
    Flag = "effects",
    Values = { "Bloom", "Shadows", "Particles", "Reflections" },
    Default = {
        Bloom = true,
        Shadows = true,
    },
    Multi = true,
    Callback = function(selected)
        for effect, enabled in pairs(selected) do
            print(effect, enabled)
        end
    end,
})

local appearanceTab = window:AddTab("colors")
local themeSection = appearanceTab:AddSection("make it pretty")

themeSection:AddColorPicker({
    Name = "main color",
    Flag = "accentColor",
    Default = Bloodshot.Theme.Accent,
    Callback = function(color)
        Bloodshot:SetTheme({
            Accent = color,
        })
    end,
})

themeSection:AddButton({
    Name = "put color back",
    Callback = function()
        Bloodshot:SetTheme({
            Background = Color3.fromRGB(7, 7, 9),
            Surface = Color3.fromRGB(14, 10, 12),
            SurfaceAlt = Color3.fromRGB(24, 13, 16),
            Border = Color3.fromRGB(69, 27, 34),
            Accent = Color3.fromRGB(196, 28, 48),
            AccentDark = Color3.fromRGB(91, 12, 24),
            BackgroundGradient = Color3.fromRGB(24, 7, 11),
            SurfaceGradient = Color3.fromRGB(38, 10, 16),
            AccentGradient = Color3.fromRGB(104, 8, 22),
        })
    end,
})

local inputSection = appearanceTab:AddSection("keyboard thing")

inputSection:AddKeybind({
    Name = "popup key / mouse button",
    Flag = "notificationKey",
    Default = Enum.KeyCode.N,
    Changed = function(input)
        print("new input", input.Name)
    end,
    Callback = function()
        Bloodshot:Notify({
            Title = "key",
            Content = "you pressed it good job",
            Duration = 2,
        })
    end,
})

local configTab = window:AddTab("save stuff")
local configSection = configTab:AddSection("json stuff idk")

local configPreview = configSection:AddParagraph({
    Title = "the config",
    Content = "press button and json appear here",
})

configSection:AddButton({
    Name = "get config",
    Description = "makes the json thing",
    Callback = function()
        local json, encodeError = Bloodshot:SaveConfig()
        if not json then
            configPreview:Set(encodeError)
            Bloodshot:Notify({
                Title = "oops",
                Content = encodeError,
                Type = "Error",
            })
            return
        end
        configPreview:Set(json)

        if setclipboard then
            setclipboard(json)
            Bloodshot:Notify({
                Title = "copied",
                Content = "json is in clipboard now",
                Type = "Success",
            })
        end
    end,
})

configSection:AddButton({
    Name = "load random config",
    Description = "changes some stuff",
    Callback = function()
        local exampleConfig = game:GetService("HttpService"):JSONEncode({
            featureEnabled = false,
            walkSpeed = 24,
            displayName = "some guy",
            quality = "Ultra",
            effects = {
                Bloom = true,
                Particles = true,
                Reflections = true,
            },
        })

        local success, message = Bloodshot:LoadConfig(exampleConfig)
        Bloodshot:Notify({
            Title = success and "done" or "uh oh",
            Content = success and "stuff changed ok" or tostring(message),
            Type = success and "Success" or "Error",
        })
    end,
})

local lifecycleSection = configTab:AddSection("window buttons")

lifecycleSection:AddButton({
    Name = "make small",
    Description = "small or not small",
    Callback = function()
        window:ToggleMinimized()
    end,
})

-- v2 controls
local v2Tab = window:AddTab({ Name = "v2 extras" })
local modernSection = v2Tab:AddSection({
    Name = "modern controls",
    Collapsible = true,
})

modernSection:AddDivider({ Text = "numeric values" })

modernSection:AddNumberInput({
    Name = "maximum players",
    Flag = "maxPlayers",
    Min = 1,
    Max = 100,
    Increment = 1,
    Default = 12,
    Tooltip = "A validated numeric input.",
    Callback = function(value)
        print("maximum players", value)
    end,
})

modernSection:AddRangeSlider({
    Name = "distance",
    Flag = "distanceRange",
    Min = 0,
    Max = 1000,
    Increment = 10,
    Default = { 100, 500 },
    Suffix = " studs",
    Callback = function(low, high)
        print("range", low, high)
    end,
})

modernSection:AddSegmented({
    Name = "alignment",
    Flag = "alignment",
    Values = { "Left", "Center", "Right" },
    Default = "Center",
})

modernSection:AddRadio({
    Name = "difficulty",
    Flag = "difficulty",
    Values = { "Easy", "Normal", "Hard" },
    Default = "Normal",
    MaxVisibleRows = 3,
    Searchable = true,
})

modernSection:AddKeybind({
    Name = "hold action",
    Default = Enum.KeyCode.LeftAlt,
    Mode = "Hold",
    Callback = function(active)
        print("hold active", active)
    end,
})

modernSection:AddButton({
    Name = "confirmation dialog",
    Callback = function()
        Bloodshot:Confirm({
            Title = "Use high contrast?",
            Content = "You can restore the Bloodshot preset at any time.",
            Callback = function(confirmed)
                if confirmed then
                    Bloodshot:SetThemePreset("High Contrast")
                end
            end,
        })
    end,
})

local managementSection = v2Tab:AddSection("runtime management")
managementSection:AddInput({
    Name = "search this tab",
    Placeholder = "control or section name",
    Callback = function(query)
        v2Tab:Search(query)
    end,
})

managementSection:AddButton({
    Name = "rename window",
    Callback = function()
        window:SetTitle("blood shot gui v2", "modernized and compatible")
    end,
})

managementSection:AddButton({
    Name = "toggle reduced motion",
    Callback = function()
        local enabled = not Bloodshot._reducedMotion
        Bloodshot:SetReducedMotion(enabled)
        Bloodshot:Notify({
            Title = "Reduced motion",
            Content = enabled and "Enabled" or "Disabled",
        })
    end,
})

local extrasTab = window:AddTab("more stuff")
local readoutSection = extrasTab:AddSection({
    Name = "readouts",
    Description = "live values",
})

local pingStat = readoutSection:AddStat({
    Name = "ping",
    Default = 0,
    Suffix = " ms",
    Color = "Success",
    Copyable = true,
})

local loadBar = readoutSection:AddProgress({
    Name = "loading",
    Default = 0,
})

local consoleLog = readoutSection:AddLog({
    Name = "console",
    Height = 110,
    Timestamps = true,
})

readoutSection:AddSpacer({ Height = 4 })

readoutSection:AddButton({
    Name = "fake load",
    Description = "fills the bar",
    Style = "Accent",
    Cooldown = 3,
    Callback = function()
        loadBar:Set(0)
        consoleLog:Info("loading started")
        task.spawn(function()
            for step = 1, 10 do
                task.wait(0.15)
                loadBar:Set(step * 10)
                pingStat:Set(math.random(20, 90))
            end
            consoleLog:Success("loading done")
        end)
    end,
})

local inputSection = extrasTab:AddSection({
    Name = "better inputs",
    Collapsible = true,
})

inputSection:AddInput({
    Name = "digits only",
    Filter = "digits",
    MaxLength = 6,
    Clearable = true,
    Placeholder = "123456",
})

inputSection:AddDropdown({
    Name = "pick two",
    Values = { "Red", "Green", "Blue", "Gold" },
    Multi = true,
    MaxSelected = 2,
    SelectAll = true,
})

inputSection:AddTextArea({
    Name = "notes",
    Flag = "notes",
    Height = 80,
    MaxLength = 200,
    Placeholder = "write stuff",
})

inputSection:AddToggle({
    Name = "bound toggle",
    Flag = "boundToggle",
    Keybind = Enum.KeyCode.G,
    Tag = "new",
})

inputSection:AddSlider({
    Name = "marked slider",
    Flag = "markedSlider",
    Min = 0,
    Max = 100,
    Default = 50,
    Editable = true,
    Marks = { 0, 25, 50, 75, 100 },
})

local systemSection = extrasTab:AddSection("system stuff")

systemSection:AddButton({
    Name = "ask for a name",
    Callback = function()
        Bloodshot:Prompt({
            Title = "name?",
            Content = "type something",
            Callback = function(value)
                if value then
                    Bloodshot:Notify({
                        Title = "hi",
                        Content = value,
                    })
                end
            end,
        })
    end,
})

systemSection:AddButton({
    Name = "undo",
    Callback = function()
        Bloodshot:Undo()
    end,
})

systemSection:AddButton({
    Name = "redo",
    Callback = function()
        Bloodshot:Redo()
    end,
})

systemSection:AddButton({
    Name = "reset every value",
    Style = "Danger",
    Confirm = true,
    Callback = function()
        window:ResetAll()
    end,
})

local managerTab = window:AddTab("managers")
managerTab:AddSection("configs"):AddConfigManager({
    Folder = "bloodshot",
    AutoSave = true,
})
managerTab:AddSection("theme"):AddThemeManager({
    Flag = "theme",
})

Bloodshot:EnableHistory()
Bloodshot:Watermark({
    Text = "{title} | {fps} fps | {ping} ms",
    Title = "bloodshot",
})
Bloodshot:KeybindList({
    Position = "TopRight",
})
window:AddCommand({
    Name = "toggle rainbow",
    Description = "accent cycles colors",
    Callback = function()
        Bloodshot:SetRainbow(not Bloodshot:IsRainbow())
    end,
})

lifecycleSection:AddButton({
    Name = "hide it",
    Description = "right shift bring it back probably",
    Callback = function()
        window:SetVisible(false)
    end,
})

lifecycleSection:AddButton({
    Name = "delete the whole thing",
    Description = "bye gui",
    Callback = function()
        Bloodshot:Destroy()
    end,
})

Bloodshot:Notify({
    Title = "loaded",
    Content = "gui is here. right shift hide/show",
    Type = "Success",
    Duration = 5,
})

return Bloodshot
