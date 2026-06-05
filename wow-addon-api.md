# WoW Addon API & Scripting Reference

A practical reference for writing World of Warcraft addons, current as of Midnight (Patch 12.0.1, March 2026).

---

## 1. Scripting Language

WoW addons are written in **Lua 5.1** with a customized, sandboxed runtime controlled by the game client.

**Key restrictions:**
- No file I/O — all `io` and `os` functions are removed
- No `loadstring()` for arbitrary code execution in secure contexts
- Custom garbage collector tuned by Blizzard
- "Tainted" execution model — Blizzard UI code runs in a secure environment; addon code is considered "tainted" and cannot call certain protected functions (e.g., targeting, casting) without hardware events
- As of 12.0.0, a new **Secret Values** system makes certain combat data opaque to addons (see Section 8)

**UI definition** can be done in Lua, XML, or a combination of both.

---

## 2. Addon Structure

An addon lives in a folder under `Interface/AddOns/`. The folder name and `.toc` file must match exactly:

```
Interface/AddOns/MyAddon/
  MyAddon.toc        -- required: metadata and file list
  MyAddon.lua         -- your Lua code
  MyAddon.xml         -- optional: XML-based UI definitions
  Libs/               -- optional: embedded libraries (Ace3, LibStub, etc.)
```

**Loading order:**
1. WoW reads each addon's `.toc` file
2. Checks `## Interface` version — skips addon if it doesn't match
3. Resolves dependencies (`## Dependencies`, `## OptionalDeps`)
4. Loads files listed in the `.toc` in order, top to bottom
5. Fires `ADDON_LOADED` event for each addon after its files are loaded

---

## 3. TOC File Format

The `.toc` file declares metadata and lists files to load. Format: `## Directive: Value`

### Minimal Example

```toc
## Interface: 120000
## Title: My Addon
## Notes: A simple addon
## Author: YourName
## Version: 1.0.0

MyAddon.lua
```

### Core Metadata Fields

| Field | Description |
|-------|-------------|
| `Interface` | WoW client version (e.g., `120000` for Midnight). Supports comma-delimited for multi-flavor: `120001, 50503` |
| `Title` | Display name in the AddOns list. Supports localization: `Title-frFR: Mon Addon` |
| `Notes` | Tooltip text. Supports UI escape sequences for color |
| `Author` | Creator name |
| `Version` | Addon version string |
| `Category` | Collapsible group header in the addon list |
| `Group` | Groups related addons under a main addon name |

### Dependencies & Loading

| Field | Description |
|-------|-------------|
| `Dependencies` / `RequiredDeps` | Addons that must load first (comma-separated) |
| `OptionalDeps` | Addons that load first if available |
| `LoadOnDemand` | Set to `1` to delay loading until `C_AddOns.LoadAddOn()` is called |
| `LoadWith` | Auto-load when specified addons load (implies LoadOnDemand) |
| `LoadManagers` | Addons that manage this addon's LoadOnDemand behavior |
| `DefaultState` | Set to `disabled` to require explicit user opt-in |
| `AllowLoadGameType` | Restrict to client flavors: `mainline`, `classic`, `cata`, `wrath`, etc. |

### Saved Variables

| Field | Description |
|-------|-------------|
| `SavedVariables` | Global variables persisted account-wide between sessions |
| `SavedVariablesPerCharacter` | Variables persisted per-character |
| `LoadSavedVariablesFirst` | Set to `1` to load saved data before script files |

### Addon Compartment (Minimap Button)

| Field | Description |
|-------|-------------|
| `AddonCompartmentFunc` | Global function called on minimap dropdown click |
| `AddonCompartmentFuncOnEnter` | Function called on mouse enter |
| `AddonCompartmentFuncOnLeave` | Function called on mouse leave |

### Display

| Field | Description |
|-------|-------------|
| `IconTexture` | Path to addon icon texture |
| `IconAtlas` | Atlas name for addon icon (lower priority than IconTexture) |

### Other

| Field | Description |
|-------|-------------|
| `AllowAddOnTableAccess` | Set to `1` to allow namespace table retrieval via API |
| `OnlyBetaAndPTR` | Set to `1` to only load on test realms |
| `X-*` | Custom metadata (e.g., `X-Website`, `X-Feedback`) |

### Syntax Notes
- Comments: lines starting with `#` (single hash)
- File paths use backslashes: `subfolder\myFile.lua`
- Per-file conditions: `[AllowLoadGameType mainline] RetailOnly.lua`
- Client reads only the first 1024 characters per line

---

## 4. Key APIs

### Frame Creation & Widget Types

```lua
-- Create a basic frame
local frame = CreateFrame("Frame", "MyAddonFrame", UIParent)

-- Create a button
local btn = CreateFrame("Button", "MyButton", UIParent, "UIPanelButtonTemplate")
btn:SetSize(100, 30)
btn:SetPoint("CENTER")
btn:SetText("Click Me")
btn:SetScript("OnClick", function(self)
    print("Button clicked!")
end)
```

**Common frame types:**

| Type | Description |
|------|-------------|
| `Frame` | Base container, can register events |
| `Button` | Clickable button |
| `EditBox` | Text input field |
| `ScrollFrame` | Scrollable container |
| `Slider` | Draggable slider |
| `StatusBar` | Progress/health bar |
| `GameTooltip` | Tooltip frame |
| `CheckButton` | Checkbox |

**Common widget methods:**
- `frame:SetSize(width, height)`
- `frame:SetPoint(anchor, relativeFrame, relativePoint, offsetX, offsetY)`
- `frame:Show()` / `frame:Hide()`
- `frame:SetAlpha(alpha)`

**Child elements:**
```lua
-- Add text to a frame
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER")
text:SetText("Hello!")

-- Add a texture
local tex = frame:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints(frame)
tex:SetColorTexture(0, 0, 0, 0.5)  -- semi-transparent black
```

### Event Handling

```lua
local frame = CreateFrame("Frame")

-- Register for specific events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Set the event handler
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "MyAddon" then
            print("MyAddon loaded!")
        end
    elseif event == "PLAYER_LOGIN" then
        print("Player logged in!")
    end
end)
```

**Important events:**

| Event | When it fires |
|-------|--------------|
| `ADDON_LOADED` | After an addon's files are loaded. Arg1 = addon name |
| `PLAYER_LOGIN` | After the player logs in (fires once) |
| `PLAYER_ENTERING_WORLD` | On login, reload, and zone transitions |
| `PLAYER_LOGOUT` | When the player logs out |
| `COMBAT_LOG_EVENT_UNFILTERED` | Combat log updates (**restricted in 12.0.0**) |
| `CHAT_MSG_SAY` / `CHAT_MSG_PARTY` / etc. | Chat messages |
| `UNIT_HEALTH` | Unit health changes |
| `BAG_UPDATE` | Inventory changes |

**Event methods:**
- `frame:RegisterEvent("EVENT_NAME")` — subscribe
- `frame:UnregisterEvent("EVENT_NAME")` — unsubscribe
- `frame:UnregisterAllEvents()` — unsubscribe from all
- `frame:RegisterUnitEvent("EVENT", "unit")` — unit-specific events

### Slash Commands

```lua
-- Define a slash command
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"  -- optional alias

SlashCmdList["MYADDON"] = function(msg)
    print("You typed: " .. msg)
    -- msg contains everything after the slash command
end
```

The naming convention: `SLASH_COMMANDNAME1` (and optionally `2`, `3`, etc.) defines the trigger strings. The handler goes in `SlashCmdList["COMMANDNAME"]`.

### Chat & Print Output

```lua
-- Simple output (appears in default chat frame)
print("Hello world!")

-- Colored output using format strings
print("|cFF00FF00Green text!|r")

-- Send to a specific chat frame
DEFAULT_CHAT_FRAME:AddMessage("Hello!", 1.0, 1.0, 0.0)  -- yellow text

-- System-style message in the error frame (center screen)
UIErrorsFrame:AddMessage("Important message!", 1.0, 0.0, 0.0, 1.0, 3)
```

### Saved Variables (Persistence)

Declare in your `.toc`:
```toc
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
```

Use in your Lua:
```lua
-- These globals are automatically loaded from disk before ADDON_LOADED fires
-- (or after, depending on LoadSavedVariablesFirst)

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "MyAddon" then
        -- Initialize defaults if first run
        if not MyAddonDB then
            MyAddonDB = { enabled = true, scale = 1.0 }
        end
        print("Settings loaded! Enabled: " .. tostring(MyAddonDB.enabled))

    elseif event == "PLAYER_LOGOUT" then
        -- SavedVariables are automatically written on logout
        -- Just make sure your global variable has the data you want saved
    end
end)
```

**Key points:**
- The variable name in `.toc` must match a global Lua variable exactly
- Data is saved automatically on logout/reload as a Lua table serialized to `WTF/Account/.../SavedVariables/MyAddon.lua`
- `SavedVariables` are shared across all characters; `SavedVariablesPerCharacter` are per-character
- Data is available when `ADDON_LOADED` fires for your addon

---

## 5. XML vs Pure Lua

**XML approach** (older/traditional):
```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
  <Frame name="MyAddonFrame" parent="UIParent">
    <Size x="200" y="100"/>
    <Anchors>
      <Anchor point="CENTER"/>
    </Anchors>
    <Layers>
      <Layer level="BACKGROUND">
        <FontString name="$parentText" inherits="GameFontNormal" text="Hello!">
          <Anchor point="CENTER"/>
        </FontString>
      </Layer>
    </Layers>
    <Scripts>
      <OnLoad>self:RegisterEvent("PLAYER_LOGIN")</OnLoad>
      <OnEvent>print("event: " .. event)</OnEvent>
    </Scripts>
  </Frame>
</Ui>
```

**Pure Lua approach** (modern convention):
```lua
local frame = CreateFrame("Frame", "MyAddonFrame", UIParent)
frame:SetSize(200, 100)
frame:SetPoint("CENTER")

local text = frame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
text:SetPoint("CENTER")
text:SetText("Hello!")

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    print("event: " .. event)
end)
```

**Modern convention:** Most new addons use **pure Lua**. XML is still used for templates (inheritable frame definitions) and by Blizzard's own UI code, but Lua-only addons are simpler to write, debug, and maintain.

---

## 6. Midnight 12.0.0 API Changes

The Midnight expansion introduced significant addon restrictions:

- **Interface version `120000`** is required — addons without it will not load at all (no player override)
- **Combat Log Events** are no longer available to addons during encounters
- **Cooldowns & Auras** return secret (opaque) values during combat
- **Unit Identity** — creature names and GUIDs are restricted in instances
- **Chat in instances** — messages sent as secrets; addon communication restricted during encounters
- **New APIs**: `C_Secrets` and `C_RestrictedActions` namespaces for testing restriction states
- **Secondary resources** (Combo Points, Runes, Soul Shards, etc.) remain non-secret

**Philosophy:** "Addons should not be able to provide a competitive advantage in combat." Cosmetic customization is still fully supported.

---

## 7. Hello World Addon

### File: `Interface/AddOns/HelloWorld/HelloWorld.toc`

```toc
## Interface: 120000
## Title: Hello World
## Notes: A simple hello world addon
## Author: YourName
## Version: 1.0.0
## SavedVariables: HelloWorldDB

HelloWorld.lua
```

### File: `Interface/AddOns/HelloWorld/HelloWorld.lua`

```lua
-- Saved variables (persisted between sessions)
-- HelloWorldDB will be loaded from disk automatically

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "HelloWorld" then
            -- Initialize saved variables
            if not HelloWorldDB then
                HelloWorldDB = { timesLoaded = 0 }
            end
            HelloWorldDB.timesLoaded = HelloWorldDB.timesLoaded + 1
        end

    elseif event == "PLAYER_LOGIN" then
        print("|cFF00FF00Hello World!|r You've loaded this addon " ..
              HelloWorldDB.timesLoaded .. " time(s).")
    end
end)

-- Slash command
SLASH_HELLOWORLD1 = "/hw"
SlashCmdList["HELLOWORLD"] = function(msg)
    if msg == "reset" then
        HelloWorldDB.timesLoaded = 0
        print("HelloWorld: Counter reset!")
    else
        print("HelloWorld: Loaded " .. HelloWorldDB.timesLoaded .. " time(s). Use '/hw reset' to reset.")
    end
end
```

---

## 8. Useful Resources

- **Warcraft Wiki (API reference):** https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- **Warcraft Wiki (Events list):** https://warcraft.wiki.gg/wiki/Events
- **Warcraft Wiki (Widget API):** https://warcraft.wiki.gg/wiki/Widget_API
- **Warcraft Wiki (TOC format):** https://warcraft.wiki.gg/wiki/TOC_format
- **Wowhead Beginner Guide:** https://www.wowhead.com/guide/comprehensive-beginners-guide-for-wow-addon-coding-in-lua-5338
- **In-game API docs:** Type `/api` in-game to browse Blizzard's official API documentation
- **WoW Bundle (VS Code extension):** Lua language support with WoW API autocomplete
- **WowLua (in-game addon):** Interactive Lua interpreter for testing code in-game
- **Ace3 library:** Popular addon framework providing config UI, slash commands, database management — https://www.wowace.com/projects/ace3

---

## 9. Current Interface Versions

| Flavor | Version |
|--------|---------|
| Retail (Midnight 12.0.x) | `120000` |
| Cataclysm Classic | `40402` |
| Wrath Classic | `30403` |
| Classic Era | `11501` |

Get the current version in-game: `/dump select(4, GetBuildInfo())`
