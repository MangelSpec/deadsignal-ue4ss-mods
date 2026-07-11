-- ShadowToggle: automatically enable shadows only inside the apartment's
-- open-plan living area (computer / living room / kitchen) and disable them
-- everywhere else.
--
--   Shadows OFF -> max visibility for spotting report items, navigating dark
--                  rooms, and reading the security-camera feeds.
--   Shadows ON  -> the Noir "is a killer here" tell renders.
--
-- The game only exposes MainPlayerState.LastPlayersLocation, which lags one zone
-- behind the player, so the current room is derived from the player's world
-- position with a point-in-polygon test against SHADOW_ON_POLYGON.
--
-- Iterate WITHOUT restarting: edit this file, then press Ctrl+R in-game.
-- Console (F10 / Caret):
--   shadow on | off | <0-5>   force a value (auto overrides it on the next tick)
--   shadow auto on | off      pause/resume automatic switching
--   shadowstate               print position / decision to the log
--   shadowpos [label]         append the player's world position to positions.txt
-- F8 toggles auto on/off.

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

-- Shadow quality applied when ON (r.ShadowQuality; 1-5, higher = sharper).
-- Set this to the level you want rendered inside the apartment.
local ON_SHADOW_QUALITY = 3

-- Polygon of world (X, Y) corners enclosing the open-plan area where shadows
-- should be ON, captured in order with `shadowpos`. To retune the boundary,
-- re-capture corners and replace this list, then Ctrl+R. Consecutive vertices
-- form the edges; the last vertex links back to the first automatically.
local SHADOW_ON_POLYGON = {
    { -2569, -1891 },
    { -2261, -1966 },
    { -2112, -1855 },
    { -2180, -1176 },
    { -2392, -1039 },
    { -2953, -1039 },
    { -3034, -1494 },
    { -2985, -1543 },
    { -2649, -1582 },
}

-- Height band around the apartment floor (captured at world Z ~= 2764). Guards
-- against a building floor stacked above/below that overlaps the polygon in X,Y.
local ON_Z_MIN = 2514
local ON_Z_MAX = 3014

-- When true, sitting at the desk/computer forces shadows OFF (clearer camera
-- feed) even while inside the ON polygon. Set false to let position decide alone.
local OFF_AT_DESK = true

local WALK_PAWN_CLASS = "BP_StandardPawn_C" -- view target class while walking (first-person).
local POLL_MS = 250

-------------------------------------------------------------------------------
-- UObject helpers
-------------------------------------------------------------------------------

-- The local PlayerController: the one backed by a valid ULocalPlayer. Used as
-- the world context for ExecuteConsoleCommand and to read view target / pawn.
local function getPlayerController()
    local pcs = FindAllOf("PlayerController")
    if not pcs then return nil end
    for _, pc in pairs(pcs) do
        local player = pc.Player
        if pc:IsValid() and player and player:IsValid() then
            return pc
        end
    end
    return nil
end

-- KismetSystemLibrary CDO. ExecuteConsoleCommand runs cvars through GEngine's
-- exec path; robust where the controller's own ConsoleCommand nullptr-ed.
local function getKismetSystemLibrary()
    return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
end

local function classNameOf(obj)
    if not (obj and obj:IsValid()) then return nil end
    local cls = obj:GetClass()
    if not (cls and cls:IsValid()) then return nil end
    return cls:GetFName():ToString()
end

-- The player pawn's world location, or nil while there is no walking pawn
-- (e.g. sitting at the desk). Returns x, y, z.
local function getPlayerXYZ(pc)
    local pawn = pc.Pawn
    if not (pawn and pawn:IsValid()) then return nil end
    local ok, loc = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok or not loc then return nil end
    return loc.X, loc.Y, loc.Z
end

-------------------------------------------------------------------------------
-- Apply
-------------------------------------------------------------------------------

local function setShadowQuality(value)
    local pc = getPlayerController()
    if not pc then
        print("[ShadowToggle] no PlayerController with a valid Player found\n")
        return false
    end
    local ksl = getKismetSystemLibrary()
    if not ksl or not ksl:IsValid() then
        print("[ShadowToggle] KismetSystemLibrary not found\n")
        return false
    end
    local cmd = "r.ShadowQuality " .. value
    ksl:ExecuteConsoleCommand(pc, cmd, pc)
    print("[ShadowToggle] " .. cmd .. "\n")
    return true
end

-------------------------------------------------------------------------------
-- Detect
-------------------------------------------------------------------------------

-- Ray-casting point-in-polygon test on the X,Y plane.
local function pointInPolygon(x, y, poly)
    local inside = false
    local n = #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i][1], poly[i][2]
        local xj, yj = poly[j][1], poly[j][2]
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- True when the player stands inside the ON polygon at apartment-floor height.
local function isInOnZone(pc)
    local x, y, z = getPlayerXYZ(pc)
    if not x then return false end
    if z < ON_Z_MIN or z > ON_Z_MAX then return false end
    return pointInPolygon(x, y, SHADOW_ON_POLYGON)
end

-- At the desk when the view target is anything other than the walking pawn
-- (BP_DeskPawn_C when sitting, BP_SpyCameraLocation_C on the active camera).
local function isAtPC(pc)
    return classNameOf(pc:GetViewTarget()) ~= WALK_PAWN_CLASS
end

local function shouldShadowsBeOn(pc)
    if OFF_AT_DESK and isAtPC(pc) then return false end
    return isInOnZone(pc)
end

-------------------------------------------------------------------------------
-- Auto loop
-------------------------------------------------------------------------------

local autoEnabled = true
local currentOn = nil -- last applied state; nil forces the first apply

LoopAsync(POLL_MS, function()
    if autoEnabled then
        ExecuteInGameThread(function()
            local pc = getPlayerController()
            if not pc then return end
            local desired = shouldShadowsBeOn(pc)
            if desired ~= currentOn then
                currentOn = desired
                setShadowQuality(desired and ON_SHADOW_QUALITY or 0)
            end
        end)
    end
    return false -- keep looping
end)

-------------------------------------------------------------------------------
-- Console + keybind
-------------------------------------------------------------------------------

local function setAuto(on)
    autoEnabled = on
    currentOn = nil -- re-apply on the next tick when re-enabling
    print("[ShadowToggle] auto " .. (on and "on" or "off") .. "\n")
end

RegisterConsoleCommandHandler("shadow", function(FullCommand, Parameters, Ar)
    local arg = Parameters[1]
    if arg == "auto" then
        setAuto(Parameters[2] ~= "off")
    elseif arg == "on" then
        ExecuteInGameThread(function() setShadowQuality(ON_SHADOW_QUALITY) end)
    elseif arg == "off" then
        ExecuteInGameThread(function() setShadowQuality(0) end)
    elseif arg and tonumber(arg) then
        ExecuteInGameThread(function() setShadowQuality(tonumber(arg)) end)
    else
        Ar:Log("usage: shadow on | off | <0-5> | auto on|off")
    end
    return true
end)

-- Prints the player's position and the current decision (for verifying / tuning).
RegisterConsoleCommandHandler("shadowstate", function(FullCommand, Parameters, Ar)
    ExecuteInGameThread(function()
        local pc = getPlayerController()
        if not pc then
            print("[ShadowToggle] no PlayerController\n")
            return
        end
        local x, y, z = getPlayerXYZ(pc)
        print(string.format("[ShadowToggle] pos=(%s, %s, %s) inZone=%s atPC=%s wantOn=%s\n",
            x and string.format("%.0f", x) or "?",
            y and string.format("%.0f", y) or "?",
            z and string.format("%.0f", z) or "?",
            tostring(isInOnZone(pc)), tostring(isAtPC(pc)), tostring(shouldShadowsBeOn(pc))))
    end)
    return true
end)

-- Appends the player's world position to positions.txt, for capturing / editing
-- the SHADOW_ON_POLYGON corners in-game.
RegisterConsoleCommandHandler("shadowpos", function(FullCommand, Parameters, Ar)
    ExecuteInGameThread(function()
        local pc = getPlayerController()
        local x, y, z
        if pc then x, y, z = getPlayerXYZ(pc) end
        if not x then
            print("[ShadowToggle] no pawn (are you walking?)\n")
            return
        end
        local label = Parameters[1] or "?"
        local line = string.format("%-14s X=%.0f Y=%.0f Z=%.0f", label, x, y, z)
        print("[ShadowToggle] " .. line .. "\n")
        local f = io.open("Mods/ShadowToggle/positions.txt", "a+")
        if f then
            f:write(line .. "\n"); f:close()
        end
    end)
    return true
end)

-- F8 toggles auto on/off. Guarded so a hot reload won't double-bind.
if not IsKeyBindRegistered(Key.F8) then
    RegisterKeyBind(Key.F8, function()
        ExecuteInGameThread(function() setAuto(not autoEnabled) end)
    end)
end
