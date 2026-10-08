# Bloodshot UI

Single file Roblox UI library. `loadstring(game:HttpGet(url))()` returns `Library`.

## Current features

### Windows
- `Library:CreateWindow(options)`, multiple windows, focus stacking, `CycleWindows`
- Drag, resize, minimize, close, toggle key or chord, `OnClose` / `CloseRequest`
- Sidebar left/right/top, animated background, particles, entry animations
- Tabs with icon, badge, disable, hide, reorder; sections with collapse, reorder
- Geometry persistence (position, size, scroll) per window
- Gamepad focus navigation, reduced motion, animation speed

### Controls
- Label, Paragraph, Button, Toggle, Slider, Input, NumberInput, Dropdown (single, multi, search), Radio, Segmented, RangeSlider, Keybind (press, hold, toggle), ColorPicker (alpha, presets), Divider
- Row (compact multi column layout), Search, Summary, List
- Shared on every control: `Flag`, `Tooltip`, `DependsOn`, `DependencyMode`, `Set`, `Get`, `SetName`, `SetDescription`, `SetVisible`, `SetDisabled`, `Destroy`, drag reorder

### Flags and config
- `SetFlag`, `GetFlag`, `OnFlagChanged`, `Bind` (flag to property)
- `SaveConfig`, `LoadConfig` (typed JSON, strict mode), `ImportLegacy`
- Profiles with adapters, `UseFileStorage`, `SaveProfile`, `LoadProfile`, `DeleteProfile`, `ListProfiles`
- `AutoSave` debounced, `ConfigFingerprint`

### Theme
- `SetTheme`, `GetTheme`, `ResetTheme`, `SetThemePreset` (Bloodshot, Crimson Light, High Contrast)
- Per window theme override, `ThemeEditor`

### Misc
- `Notify` (type, duration, stack of 5), `Confirm`
- `Build` / `BuildFromJson` from specs, `ExportSpec` / `ExportSpecJson`
- `Inspect` diagnostics window
- `SetStrings` localisation, `GetHeldKeys`, `IsKeyHeld`

## Customizable options

### Window
| Group | Options |
| --- | --- |
| Identity | `Title`, `Subtitle` |
| Geometry | `Size`, `Position`, `MinimumSize`, `Resizable`, `MinimizedWidth`, `GeometryKey` |
| Behaviour | `ToggleKey`, `Closeable`, `MinimizeButton`, `OnClose`, `CloseRequest`, `DestroyOnClose`, `Reorderable` |
| Layout | `SidebarSide`, `SidebarWidth`, `SidebarHeight`, `SidebarPadding`, `TopbarHeight`, `TabHeight`, `TabWidth`, `TabSpacing`, `SectionSpacing`, `ControlSpacing`, `ContentPadding`, `CornerRadius` |
| Motion | `AnimatedBackground`, `AnimationStyle`, `AnimationSpeed`, `BackgroundParticles`, `ParticleCount`, `ParticleSpeed`, `ParticleMinSize`, `ParticleMaxSize`, `ParticleColor`, `ParticleTransparency` |

### Section
`Name`, `Collapsible`, `Collapsed`, `Reorderable`

### Controls
| Control | Options |
| --- | --- |
| Button | `Name`, `Description`, `Callback`, `Confirm`, `ConfirmText`, `ConfirmTimeout` |
| Toggle | `Name`, `Description`, `Default`, `Callback`, `Flag`, `FireOnLoad` |
| Slider | `Min`, `Max`, `Default`, `Increment`, `Prefix`, `Suffix`, `Callback`, `Flag` |
| Input | `Default`, `Placeholder`, `Numeric`, `Normalize`, `Callback`, `Flag` |
| Dropdown | `Values`, `Default`, `Multi`, `Searchable`, `Placeholder`, `EmptyText`, `MaxVisibleRows`, `SearchPlaceholder` |
| Keybind | `Default`, `Mode`, `AllowMouse`, `AllowProcessed`, `KeyboardOnly`, `CancelKey`, `ClearKeys`, `CaptureText`, `UnboundText`, `Changed` |
| ColorPicker | `Default`, `Alpha`, `DefaultAlpha`, `Presets`, `PresetColumns`, `ResetButton`, `ResetText` |
| Label | `Text`, `Color`, `Alignment`, `Wrap`, `TextSize`, `Height` |
| Paragraph | `Title`, `Content`, `Font`, `Height` |
| NumberInput | `Min`, `Max`, `Increment`, `Prefix`, `Suffix` |
| Segmented | `Values`, `Default` |
| RangeSlider | `Min`, `Max`, `Increment`, `Default` (`{low, high}`), `Suffix` |
| Row | `Controls`, `Height`, `Padding`, `Spacing`; child `Width` or `Weight` |
| Search | `Target`, `Placeholder`, `Width` |
| Summary | `Template`, `Values`, `Alignment`, `Color`, `Height` |
| List | `Title`, `MaxRows`, `RowHeight`, `Removable`, `ShowIcon`, `ShowIndex`, `EmptyText` |
| Every control | `Flag`, `Tooltip`, `DependsOn`, `DependencyMode`, `ReorderDrag` |

### Theme keys
Colors: `Background`, `Surface`, `SurfaceAlt`, `Border`, `Text`, `MutedText`, `Accent`, `AccentDark`, `Success`, `Warning`, `Error`, `BackgroundGradient`, `SurfaceGradient`, `AccentGradient`, `Disabled`, `Focus`, `Overlay`
Numbers: `CornerRadius`, `ControlTransparency`
Fonts: `Font`, `FontMedium`, `FontBold`

## Added

### Window options
- `Footer`, `Icon`, `Opacity`, `Blur`, `Draggable`
- `Density` (`Compact`, `Comfortable`, `Spacious`)
- `ToggleButton` floating show/hide button (`Text`, `Icon`, `Size`, `Position`, `Round`, `Draggable`, `HideWhenOpen`)
- `ContextMenu` right click menu on controls
- `QuickSearch` palette (`true` = Ctrl+K, key, or `{ Key, Ctrl, Shift, Alt }`)
- `Commands` list of `{ Name, Description, Keywords, Callback }`

### Window methods
`SetIcon`, `SetFooter`, `SetDraggable`, `SetOpacity`, `GetOpacity`, `SetBlur`, `SetToggleButton`, `SetToggleButtonVisible`, `AddTabGroup`, `ResetAll`, `SetContextMenu`, `OpenControlMenu`, `OpenSearch`, `CloseSearch`, `SetQuickSearch`, `AddCommand`, `GetCommands`, `Find`, `GetSearchEntries`, `Reveal`

### Tab and section
- `Tab:SetName`, `Tab:SetIcon`
- `Section:SetTitle`, `Section:SetDescription`
- Section options `Description`, `Disabled`, `Visible`; controls added to a disabled section inherit it

### Control options on every control
`Disabled`, `Visible`, `Icon`, `Tag`, `TagColor`, `ContextMenu` (`false`, item list, `{ Items, Replace }`, or function), methods `Reset`, `SetTag`

### Control options per control
| Control | Added |
| --- | --- |
| Button | `Style` (`Accent`, `Danger`, `Success`, `Warning`, `Ghost`), `Color`, `Cooldown`, `Hold`, `Keybind`, `KeybindFlag`, `KeybindBlacklist`, `KeybindChanged`; methods `SetLoading`, `IsLoading` |
| Toggle | `Style` (`Checkbox`), `Color`, `Keybind`, `KeybindMode`, `KeybindFlag`, `KeybindBlacklist`, `KeybindChanged` |
| Slider | `Color`, `Editable`, `Format`, `ShowValue`, `Marks`, `Ticks` |
| Input | `Clearable`, `Filter` (`number`, `integer`, `digits`, `alpha`, `alphanumeric`, `hex`, `word`, custom class or function), `MaxLength`, `OnlyEnter`, `ReadOnly` |
| NumberInput | `Stepper` |
| Dropdown | `Clearable`, `Sorted`, `MaxDisplay`, `MaxSelected`, `ReplaceOldest`, `SelectAll` |
| Keybind | `Blacklist`, `ModeSwitch` (right click cycles mode), `ModeChanged`, `ModeFlag` |
| ColorPicker | `Rainbow`, `RainbowEnabled`, `RainbowFlag`, `RainbowRate`, `RainbowSpeed`, `RainbowSaturation`, `RainbowBrightness`, `RainbowChanged` |
| Label, Paragraph | `Copyable`, `CopyNotify`, `RichText` |

### New controls
| Control | Purpose | Options |
| --- | --- | --- |
| Spacer | vertical gap | `Height` |
| Stat | live value readout | `Default`, `Prefix`, `Suffix`, `Format`, `Decimals`, `Color`, `Copyable`, `Flag` |
| Progress | bar, indeterminate | `Min`, `Max`, `Default`, `Format`, `Decimals`, `Color`, `Indeterminate`, `Animate`, `Flag` |
| Image | image with caption | `Image`, `Height`, `ScaleType`, `Tint`, `Transparency`, `CornerRadius`, `Caption`, `CaptionAlignment` |
| TextArea | multi line input | `Height`, `Placeholder`, `MaxLength`, `ReadOnly`, `Live`, `Flag` |
| Log | console | `Height`, `MaxLines`, `Timestamps`, `AutoScroll`, `Lines`; methods `Add`, `Info`, `Success`, `Warning`, `Error`, `Debug`, `Clear`, `Copy`, `GetText` |
| ConfigManager | profile UI: name, list, Save, Load, Delete, Refresh, Autoload, AutoSave, Export, Import | `Folder`, `Adapter`, `Include`, `Exclude`, `Metadata`, `Confirm`, `Notify`, `Autoload`, `AutoSave`, `Clipboard`, `LoadOnStart`, `Default`, `Callback` |
| ThemeManager | theme UI: preset, accent, rainbow, radius, transparency, opacity, export, import, save preset, reset | `Flag` prefix, `Presets`, `Accent`, `Rainbow`, `Radius`, `Transparency`, `Opacity`, `Actions`, `Derive`, `Notify`, `RainbowOptions` |

### Library
- Events: `On`, `Off`
- Flags: `ResetFlags`, `GetDefault`
- Notifications: `Id` (update in place), `Progress`, `Icon`, `Actions`, `Sticky`, `Closable`, `Position`, `Sound`, `OnClick`, `SetNotificationPosition`, `ClearNotifications`
- Dialogs: `Dialog` (custom buttons, input), `Prompt`, `Confirm` (danger style), stacked, Enter and Escape
- Context menu: `ContextMenu` (items, icon, shortcut, checked, danger, disabled, separators, keyboard)
- HUD: `Watermark` (template `{fps}`, `{ping}`, `{time}`, `{name}`, `{title}`, custom `Values`), `KeybindList` (live bound keys)
- History: `EnableHistory`, `Undo`, `Redo`, `CanUndo`, `CanRedo`, `GetHistory`, `ClearHistory`, Ctrl+Z, Ctrl+Y, batched config loads
- Sounds: `SetSounds` (`Click`, `Toggle`, `Select`, `Tab`, `Open`, `Close`, `Notify`, `Volume`), `SetSoundsEnabled`, `PlaySound`
- Themes: `CreateTheme(accent)`, `RegisterThemePreset`, `SaveThemePreset`, `RemoveThemePreset`, `GetThemePresetNames`, `ExportTheme`, `ExportThemeJson`, `ImportTheme`, `SetRainbow`, `IsRainbow`
- 7 more presets: Midnight, Emerald, Violet, Amber, Rose, Ocean, Mono
- `CornerRadius` and `ControlTransparency` apply live to existing controls

### Misc behaviour
- Right click control menu: reset, copy value, copy flag, custom items
- Quick search palette: tabs, controls, row children, commands; fuzzy match, keyboard, jump, scroll, highlight
- Profile names starting with `__` are internal and hidden from `ListProfiles`
- Controls created by manager builders are excluded from `ExportSpec`
