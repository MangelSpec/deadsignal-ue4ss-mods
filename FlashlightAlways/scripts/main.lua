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

-- True when this InventoryItemCheck call is asking about the flashlight.
local function isFlashlightQuery(...)
    if select("#", ...) < 1 then return false end
    local first = select(1, ...)
    local ok, v = pcall(function() return first:get() end)
    return ok and v == FLASHLIGHT_ITEM_ID
end

-- Install the override. The native function must exist in memory to hook it, so
-- retry until it does (returning true from LoopAsync stops the loop).
local installed = false
local function tryInstall()
    if installed then return true end
    local ok = pcall(function()
        RegisterHook(INVENTORY_CHECK,
            function(Context, ...) if isFlashlightQuery(...) then return true end end,
            function(Context, ...) if isFlashlightQuery(...) then return true end end)
    end)
    if ok then
        installed = true
        print("[FlashlightAlways] flashlight unlocked (item " .. FLASHLIGHT_ITEM_ID .. ")\n")
    end
    return installed
end

if not tryInstall() then
    LoopAsync(1000, tryInstall)
end
