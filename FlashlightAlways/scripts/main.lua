-- FlashlightAlways: use the flashlight from the start, without the mandatory
-- pickup.
--
-- The flashlight is gated by an inventory item, and TurnFlashLightOn checks
-- possession internally. The check is MainPlayerState.InventoryItemCheck (native
-- on the C++ parent), which the game calls with the flashlight's item id when you
-- press the flashlight key. We hook it and override the return to true for that
-- id, so the game behaves as if the flashlight is in inventory.

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

-- Item id the game passes to InventoryItemCheck for the flashlight. Found by
-- logging the check while pressing the flashlight key; see dev.md.
local FLASHLIGHT_ITEM_ID = 62

-------------------------------------------------------------------------------

local INVENTORY_CHECK = "/Script/DeadSignal.MainPlayerState:InventoryItemCheck"
local RETRY_MS = 1000
local MAX_HOOK_ATTEMPTS = 30

-- True when this InventoryItemCheck call is asking about the flashlight.
local function isFlashlightQuery(...)
    if select("#", ...) < 1 then return false end
    local first = select(1, ...)
    local ok, v = pcall(function() return first:get() end)
    return ok and v == FLASHLIGHT_ITEM_ID
end

-- Install the override. The native function must exist in memory to hook it, so
-- retry for a bounded period and surface the real error if it never appears.
local installed = false
local attempts = 0
local function registerHook()
    RegisterHook(INVENTORY_CHECK,
        function(Context, ...) if isFlashlightQuery(...) then return true end end,
        function(Context, ...) if isFlashlightQuery(...) then return true end end)
end

local function tryInstall()
    if installed then return true end
    attempts = attempts + 1
    local ok = pcall(registerHook)
    if ok then
        installed = true
        print("[FlashlightAlways] flashlight unlocked (item " .. FLASHLIGHT_ITEM_ID .. ")\n")
    elseif attempts >= MAX_HOOK_ATTEMPTS then
        print("[FlashlightAlways] could not hook InventoryItemCheck after " .. attempts
            .. " attempts; retrying unguarded to surface the error\n")
        registerHook()
        installed = true
    end
    return installed
end

if not tryInstall() then
    LoopAsync(RETRY_MS, tryInstall)
end
