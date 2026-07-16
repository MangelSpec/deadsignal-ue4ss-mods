-- ShadowToggle: automatically enable shadows only inside the apartment's
-- open-plan living area (computer / living room / kitchen) and disable them
-- everywhere else.
--
--   Shadows OFF -> max visibility for spotting report items, navigating dark
--                  rooms, and reading the security-camera feeds.
--   Shadows ON  -> the Noir "is a killer here" tell renders.
--
-- Both inputs come from the game's own state, delivered as parameters of two
-- NoirSubsystem events. Neither is stored in a readable property, so the values
-- are captured from the events and cached here:
--
--   PlayerLocationChanged(EPlayerLocation NewLocation) -> which room
--   PlayerPawnChanged(EPlayerPawns NewPawn)            -> walking vs desk/etc
--
-- (MainPlayerState.LastPlayersLocation is a Blueprint mirror of the first event,
-- which is why it lags a room behind. It is not used.)
--
-- Hot reload is ON: press Ctrl+R in-game after changing this file.
-- Console (F10 / Caret):
--   shadow on | off | <0-5>   force a value (auto overrides it on the next event)
--   shadow auto on | off      pause/resume automatic switching
--   shadowstate               print room / pawn / decision to the log
-- F8 toggles auto on/off.

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

-- Shadow quality applied when ON (r.ShadowQuality; 1-5, higher = sharper).
-- Set this to the level you want rendered inside the apartment.
local ON_SHADOW_QUALITY = 3

-- EPlayerLocation (/Script/DeadSignal).
local LOCATION = {
    NOT_SET           = 0,
    APT_COMPUTER_AREA = 1,
    APT_LIVING_ROOM   = 2,
    APT_KITCHEN       = 3,
    APT_BATHROOM      = 4,
    APT_BEDROOM       = 5,
    APT_MAIN_HALLWAY  = 6,
    APT_ELEVATOR      = 7,
    APT_ROOF_TOP      = 8,
    FLOOR_10          = 9,
    FLOOR_8           = 10,
    FLOOR_7           = 11,
    FLOOR_6           = 12,
    FLOOR_5           = 13,
    FLOOR_4           = 14,
    FLOOR_3           = 15,
    FLOOR_2           = 16,
    FLOOR_9           = 17,
}

-- EPlayerPawns (/Script/DeadSignal). MAIN is the walking first-person pawn;
-- every other value means the player is driving something else (desk, computer,
-- elevator panel, hiding spot, ...).
local PAWN = {
    NOT_SET        = 0,
    MAIN           = 1,
    DESK           = 2,
    COMPUTER       = 3,
    KEY_PAD        = 4,
    ELEVATOR       = 5,
    SAT            = 6,
    HIDE           = 7,
    ELEVATOR_PANEL = 8,
    DOOR_BRACE     = 9,
}

local LOCATION_NAME = {}
for name, value in pairs(LOCATION) do LOCATION_NAME[value] = name end

local PAWN_NAME = {}
for name, value in pairs(PAWN) do PAWN_NAME[value] = name end

-- Rooms where shadows are ON: the apartment's open-plan area. To retune, add or
-- remove entries; every room absent from this table renders without shadows.
local SHADOW_ON_LOCATIONS = {
    [LOCATION.APT_COMPUTER_AREA] = true,
    [LOCATION.APT_LIVING_ROOM]   = true,
    [LOCATION.APT_KITCHEN]       = true,
}

-- When true, driving anything other than the walking pawn (the desk and computer
-- both sit inside APT_COMPUTER_AREA) forces shadows OFF for a clearer camera
-- feed. Set false to let the room decide alone.
local OFF_AT_DESK = true

local LOCATION_CHANGED_FN = "/Script/DeadSignal.NoirSubsystem:PlayerLocationChanged"
local PAWN_CHANGED_FN     = "/Script/DeadSignal.NoirSubsystem:PlayerPawnChanged"
local RETRY_MS = 1000
local MAX_HOOK_ATTEMPTS = 30

-------------------------------------------------------------------------------
-- UObject helpers
-------------------------------------------------------------------------------

-- The local PlayerController: the one backed by a valid ULocalPlayer. Used as
-- the world context for ExecuteConsoleCommand.
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
-- State
-------------------------------------------------------------------------------

local currentLocation = nil -- EPlayerLocation; nil until the first event
local currentPawn = nil     -- EPlayerPawns; nil until the first event
local autoEnabled = true
local currentOn = nil       -- last applied state; nil forces the next apply

-- An unknown pawn is treated as walking, so the room alone decides until the
-- first PlayerPawnChanged arrives. An unknown room yields OFF, the safe default.
local function shouldShadowsBeOn()
    if OFF_AT_DESK and currentPawn ~= nil and currentPawn ~= PAWN.MAIN then
        return false
    end
    return SHADOW_ON_LOCATIONS[currentLocation] == true
end

-- Must run on the game thread.
local function apply()
    if not autoEnabled then return end
    local desired = shouldShadowsBeOn()
    if desired == currentOn then return end
    if setShadowQuality(desired and ON_SHADOW_QUALITY or 0) then
        currentOn = desired
    end
end

-------------------------------------------------------------------------------
-- Detect
-------------------------------------------------------------------------------

-- Hook callbacks run on the game thread inside ProcessEvent, so apply() is
-- called directly rather than queued.
local function hookEvent(name, fnPath, store)
    local attempts = 0
    local function register()
        RegisterHook(fnPath, function(self, param)
            store(param:get())
            apply()
        end)
    end
    local function tryRegister()
        attempts = attempts + 1
        if pcall(register) then
            print("[ShadowToggle] hooked " .. name .. " (attempt " .. attempts .. ")\n")
            return true
        end
        if attempts >= MAX_HOOK_ATTEMPTS then
            print("[ShadowToggle] could not hook " .. name .. " after " .. attempts
                .. " attempts; retrying unguarded to surface the error\n")
            register()
            return true
        end
        return false
    end
    if not tryRegister() then LoopAsync(RETRY_MS, tryRegister) end
end

hookEvent("PlayerLocationChanged", LOCATION_CHANGED_FN,
    function(value) currentLocation = value end)
hookEvent("PlayerPawnChanged", PAWN_CHANGED_FN,
    function(value) currentPawn = value end)

-------------------------------------------------------------------------------
-- Console + keybind
-------------------------------------------------------------------------------

local function setAuto(on)
    autoEnabled = on
    currentOn = nil -- re-apply on the next evaluation when re-enabling
    print("[ShadowToggle] auto " .. (on and "on" or "off") .. "\n")
    ExecuteInGameThread(apply)
end

RegisterConsoleCommandHandler("shadow", function(FullCommand, Parameters, Ar)
    local arg = Parameters[1]
    if arg == "auto" then
        setAuto(Parameters[2] ~= "off")
    elseif arg == "on" then
        ExecuteInGameThread(function()
            setShadowQuality(ON_SHADOW_QUALITY)
            currentOn = nil
        end)
    elseif arg == "off" then
        ExecuteInGameThread(function()
            setShadowQuality(0)
            currentOn = nil
        end)
    else
        local value = tonumber(arg)
        if value and value >= 0 and value <= 5 and value % 1 == 0 then
            ExecuteInGameThread(function()
                setShadowQuality(value)
                currentOn = nil
            end)
        else
            Ar:Log("usage: shadow on | off | <0-5> | auto on|off")
        end
    end
    return true
end)

-- Prints the cached room and pawn and the resulting decision (for verifying).
RegisterConsoleCommandHandler("shadowstate", function(FullCommand, Parameters, Ar)
    print(string.format("[ShadowToggle] location=%s (%s) pawn=%s (%s) wantOn=%s\n",
        LOCATION_NAME[currentLocation] or "?", tostring(currentLocation),
        PAWN_NAME[currentPawn] or "?", tostring(currentPawn),
        tostring(shouldShadowsBeOn())))
    return true
end)

-- Keep one keybind across hot reloads, but replace its dispatcher so it always
-- controls the current script state rather than the closure from the first load.
_G.ShadowToggleF8 = function()
    setAuto(not autoEnabled)
end
if not IsKeyBindRegistered(Key.F8) then
    RegisterKeyBind(Key.F8, function()
        local handler = _G.ShadowToggleF8
        if handler then handler() end
    end)
end
