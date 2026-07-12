-- DoorCodeMemory
--
-- Remembers the apartment door code and shows it on screen so the player can
-- read it back after walking away from the desk, instead of returning to the
-- computer to check it.
--
-- The live code is not readable as a property (it lives in a native member of
-- SecuritySubsystem and rerolls on a C++ timer, and its CodeWasUpdated delegate
-- cannot be hooked). The value only surfaces as an argument to the UFunction the
-- desktop UI calls to paint it on screen: MainDesktopWidget:UpdateKeyPadCode.
-- Hook that and keep the string it hands us.
--
-- Two layers:
--   latestCode    - private cache, updated on every UpdateKeyPadCode fire, even
--                   for a reroll issued while the player is away from the desk.
--   rememberedCode - what the player is allowed to see. In real mode it only
--                   becomes latestCode once the player is at the PC (the desk
--                   chair or actively using the computer), i.e. a code they could
--                   legitimately have read. In noob mode it always tracks latest.
--
-- "At the PC" reuses ShadowToggle's signal: NoirSubsystem:PlayerPawnChanged
-- delivers EPlayerPawns; DESK and COMPUTER are the desk chair and the computer.
--
-- Display: the game HUD (AMainGameHUD) never routes through ReceiveDrawHUD, so
-- immediate-mode Canvas drawing does nothing. Instead a UMG widget (a bare
-- TextBlock as the widget-tree root) is built at runtime and added to the
-- viewport at top-left; it shows "?????" until the code is revealed and is hidden
-- while at the PC. A watchdog re-adds/rebuilds it after level or round changes.
-- Console `doorcode` prints the same to the log.

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

-- Real mode (default) only reveals a code the player could have seen at the PC.
-- Noob mode reveals every code the moment it is issued, seen or not.
local NOOB_MODE = false

-- EPlayerPawns (/Script/DeadSignal). MAIN is the walking first-person pawn.
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

local PAWN_NAME = {}
for name, value in pairs(PAWN) do PAWN_NAME[value] = name end

-- Pawns that count as "at the PC", where the code on screen is readable and so
-- may be revealed. Add or remove entries to retune.
local REVEAL_PAWNS = {
    [PAWN.DESK]     = true, -- sitting in the desk chair
    [PAWN.COMPUTER] = true, -- actively using the computer
}

-- Overlay appearance. HUD_COLOR is an FLinearColor (components 0-1).
local HUD_TEXT       = "DOORCODE: "
local HUD_COLOR      = { R = 0.20, G = 1.0, B = 0.45, A = 1.0 }
local HUD_FONT_SIZE  = 28
local HUD_ZORDER     = 1000
-- Upper-left placement. This build can't marshal the struct args that real slot/
-- translation positioning needs, so the margins are faked: leading newlines for
-- the top gap, leading spaces for the left gap.
local HUD_LINES_DOWN = 0
local HUD_LEFT_PAD   = 1
local OVERLAY_NAME   = "DoorCodeOverlay"

local UPDATE_CODE_FN  = "/Script/DeadSignal.MainDesktopWidget:UpdateKeyPadCode"
local PAWN_CHANGED_FN = "/Script/DeadSignal.NoirSubsystem:PlayerPawnChanged"
local RETRY_MS = 1000
local MAX_ATTEMPTS = 30
local WATCHDOG_MS = 1000 -- how often to ensure the overlay exists and is on-screen

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local latestCode = nil     -- private: the true current code, revealed or not
local rememberedCode = nil -- what the player may see
local currentPawn = nil    -- EPlayerPawns; nil until the first PlayerPawnChanged

local function log(msg)
    print("[DoorCodeMemory] " .. msg .. "\n")
end

local function atPC()
    return REVEAL_PAWNS[currentPawn] == true
end

-------------------------------------------------------------------------------
-- Overlay (runtime-built UMG widget added to the viewport)
-------------------------------------------------------------------------------

local overlay = { widget = nil, text = nil }

-- Hidden at the PC (DESK/COMPUTER), where the desktop already shows the code;
-- visible everywhere else. SelfHitTestInvisible(4) draws without eating input.
local function applyOverlayVisibility()
    if not (overlay.widget and overlay.widget:IsValid()) then return end
    overlay.widget:SetVisibility(atPC() and 1 or 4) -- Collapsed / SelfHitTestInvisible
end

-- UE4SS exposes a global FText constructor; some builds lack it, so fall back to
-- KismetTextLibrary. SetText needs an FText (a plain string does not marshal).
local function toFText(str)
    if FText then return FText(str) end
    local ktl = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    return ktl:Conv_StringToText(str)
end

local function displayText()
    return string.rep("\n", HUD_LINES_DOWN) .. string.rep(" ", HUD_LEFT_PAD)
        .. HUD_TEXT .. (rememberedCode or "?????")
end

-- A TextBlock built from scratch usually has no usable FontObject, so its glyphs
-- never render. Find a real UFont: the engine Roboto if resident, else any font
-- already loaded by the game.
local function getFont()
    local candidates = { "/Engine/EngineFonts/Roboto.Roboto", "/Engine/EngineFonts/Roboto" }
    for _, path in ipairs(candidates) do
        local f = StaticFindObject(path)
        if f and f:IsValid() then return f end
    end
    local any = FindFirstOf("Font")
    if any and any:IsValid() then return any end
    return nil
end

-- A hot reload leaves the previous widget orphaned on the viewport (the Lua
-- reference is gone but the widget lives on). Remove any by our name first so
-- reloads do not stack overlays.
local function destroyExistingOverlays()
    local all = FindAllOf("UserWidget")
    if not all then return end
    for _, w in ipairs(all) do
        local ok, fn = pcall(function() return w:GetFullName() end)
        if ok and fn and string.find(fn, OVERLAY_NAME, 1, true) then
            pcall(function() w:RemoveFromParent() end)
        end
    end
end

-- Build the widget tree by hand: UserWidget -> WidgetTree -> TextBlock root. The
-- tree must be assigned before AddToViewport so the Slate rebuild has content.
-- Idempotent: returns true immediately if already built. Must run on the game
-- thread. Returns false (to be retried) until the classes and GameInstance exist.
local function buildOverlay()
    if overlay.widget and overlay.widget:IsValid() then return true end

    local C_UserWidget = StaticFindObject("/Script/UMG.UserWidget")
    local C_WidgetTree = StaticFindObject("/Script/UMG.WidgetTree")
    local C_TextBlock  = StaticFindObject("/Script/UMG.TextBlock")
    if not (C_UserWidget and C_WidgetTree and C_TextBlock) then
        return false
    end
    local outer = FindFirstOf("GameInstance")
    if not outer or not outer:IsValid() then return false end

    destroyExistingOverlays()

    local widget = StaticConstructObject(C_UserWidget, outer, FName(OVERLAY_NAME))
    if not widget or not widget:IsValid() then return false end
    local tree = StaticConstructObject(C_WidgetTree, widget, FName(OVERLAY_NAME .. "_Tree"))
    widget.WidgetTree = tree
    local text = StaticConstructObject(C_TextBlock, tree, FName(OVERLAY_NAME .. "_Text"))
    -- TextBlock as the direct root. This build fails to marshal struct-by-value
    -- arguments (SetFont/SetColorAndOpacity both failed as calls but worked as
    -- property writes), so a CanvasPanelSlot's SetAnchors/SetPosition/SetAlignment
    -- would silently no-op and leave the child unsized/off-screen. No slot needed:
    -- the root TextBlock fills the viewport and draws at the top-left.
    tree.RootWidget = text

    -- Render but never eat mouse input, and centre the line horizontally.
    text:SetVisibility(3) -- ESlateVisibility.HitTestInvisible
    pcall(function() text:SetJustification(0) end) -- ETextJustify::Left

    -- Font: write the struct members directly on the property. Passing a whole
    -- FSlateFontInfo to SetFont fails to marshal its nested FFontOutlineSettings;
    -- direct member writes are what the working community mods do. A from-scratch
    -- TextBlock also tends to have Size 0 (invisible), so this is the real fix.
    local font = getFont()
    if not font then log("no usable UFont found - text will likely be invisible") end
    local okFont = pcall(function()
        if font then text.Font.FontObject = font end
        text.Font.Size = HUD_FONT_SIZE
    end)
    if not okFont then log("font member write failed") end

    -- Colour: a from-scratch TextBlock can default to black, invisible on the
    -- dark game. Try the setter, then a direct property assign as a fallback.
    -- Colour: a from-scratch TextBlock defaults to transparent, so it is present
    -- but never paints. Struct marshalling is unreliable here, so set it two ways
    -- (whole-property assign, then per-field writes); the build log reads the
    -- value back to confirm which stuck.
    local okColor = pcall(function()
        text.ColorAndOpacity = { SpecifiedColor = HUD_COLOR, ColorUseRule = 0 }
    end)
    pcall(function()
        local sc = text.ColorAndOpacity.SpecifiedColor
        sc.R, sc.G, sc.B, sc.A = HUD_COLOR.R, HUD_COLOR.G, HUD_COLOR.B, HUD_COLOR.A
    end)
    if not okColor then log("colour property assign threw") end

    text:SetText(toFText(displayText()))
    widget:AddToViewport(HUD_ZORDER)
    widget:SetVisibility(4) -- ESlateVisibility.SelfHitTestInvisible (still drawn)
    -- A from-scratch widget can carry RenderOpacity 0 (fully transparent); force it.
    pcall(function() widget:SetRenderOpacity(1.0) end)
    pcall(function() text:SetRenderOpacity(1.0) end)

    local colorStr = "?"
    pcall(function()
        local c = text.ColorAndOpacity.SpecifiedColor
        colorStr = string.format("%.2f,%.2f,%.2f,%.2f", c.R, c.G, c.B, c.A)
    end)
    overlay.widget, overlay.text = widget, text
    applyOverlayVisibility()
    log(string.format("overlay built (okFont=%s okColor=%s color=%s)",
        tostring(okFont), tostring(okColor), colorStr))
    return true
end

-- Push the current text to the overlay, building it lazily if needed. Safe to
-- call from any thread (hook callbacks are on the game thread; LoopAsync is not).
local function refreshOverlay()
    ExecuteInGameThread(function()
        if not (overlay.widget and overlay.widget:IsValid()) then
            if not buildOverlay() then return end
        end
        overlay.text:SetText(toFText(displayText()))
    end)
end

-- Promote the private code to the remembered code and update the overlay. Called
-- when a new code is captured at the PC, and when the player arrives at the PC.
local function reveal()
    if latestCode and latestCode ~= rememberedCode then
        rememberedCode = latestCode
        log("revealed code " .. rememberedCode)
        refreshOverlay()
    end
end

-------------------------------------------------------------------------------
-- Detect + capture (hook callbacks run on the game thread inside ProcessEvent)
-------------------------------------------------------------------------------

local function onUpdateKeyPadCode(_, NewCode)
    local ok, code = pcall(function()
        local v = NewCode:get()
        if type(v) == "string" then return v end
        return v:ToString()
    end)
    if not ok or not code or code == "" then
        log("UpdateKeyPadCode fired but its code param was unreadable")
        return
    end
    latestCode = code
    if NOOB_MODE or atPC() then
        reveal()
    else
        log("cached code " .. code .. " privately (not at the PC yet)")
    end
end

local function onPawnChanged(_, NewPawn)
    local ok, value = pcall(function() return NewPawn:get() end)
    if not ok then return end
    currentPawn = value
    if atPC() then reveal() end
    applyOverlayVisibility()
end

-- The hooked UFunctions may not exist at mod load (the desktop widget class loads
-- later), so retry until each hook takes. UE4SS drops a mod's hooks on reload, so
-- Ctrl+R does not stack them. pcall hides the real UE4SS error, so on the final
-- attempt call RegisterHook unguarded to surface the true message + traceback.
local function installHook(name, fnPath, callback)
    local attempts = 0
    LoopAsync(RETRY_MS, function()
        attempts = attempts + 1
        if pcall(RegisterHook, fnPath, callback) then
            log("hooked " .. name .. " (attempt " .. attempts .. ")")
            return true
        end
        if attempts >= MAX_ATTEMPTS then
            log("could not hook " .. name .. " after " .. attempts
                .. " attempts; retrying unguarded to surface the error")
            RegisterHook(fnPath, callback)
            return true
        end
        return false
    end)
end

installHook("UpdateKeyPadCode", UPDATE_CODE_FN, onUpdateKeyPadCode)
installHook("PlayerPawnChanged", PAWN_CHANGED_FN, onPawnChanged)

-- Keep the overlay alive for the whole session: build it once the game world
-- exists, rebuild it if the widget is destroyed, and re-add it to the viewport
-- when a level/round change removes it - all without a hot reload and without
-- touching the captured code. buildOverlay is idempotent so this cannot stack.
local function ensureOverlay()
    if overlay.widget and overlay.widget:IsValid() then
        if not overlay.widget:IsInViewport() then
            pcall(function() overlay.widget:RemoveFromParent() end)
            overlay.widget:AddToViewport(HUD_ZORDER)
        end
    else
        overlay.widget, overlay.text = nil, nil
        if not buildOverlay() then return end
    end
    applyOverlayVisibility()
end

LoopAsync(WATCHDOG_MS, function()
    ExecuteInGameThread(ensureOverlay)
    return false
end)

-------------------------------------------------------------------------------
-- Console
-------------------------------------------------------------------------------

RegisterConsoleCommandHandler("doorcode", function(_, _, _)
    if rememberedCode then
        log("remembered code: " .. rememberedCode)
    else
        log("no code remembered yet - be at the PC once to reveal it")
    end
    log(string.format("latest(private)=%s pawn=%s atPC=%s",
        tostring(latestCode), PAWN_NAME[currentPawn] or "?", tostring(atPC())))
    return true
end)

-- Dump the live overlay's actual on-screen state, so an invisible-but-built
-- widget can be diagnosed without seeing the game.
RegisterConsoleCommandHandler("doordump", function(_, _, _)
    local function safe(fn) local ok, v = pcall(fn); return ok and tostring(v) or "?" end
    local w = overlay.widget
    if not (w and w:IsValid()) then log("overlay widget invalid / not built"); return true end
    log(string.format("widget: inViewport=%s vis=%s opacity=%s",
        safe(function() return w:IsInViewport() end),
        safe(function() return w:GetVisibility() end),
        safe(function() return w:GetRenderOpacity() end)))
    local t = overlay.text
    if t and t:IsValid() then
        log(string.format("text: vis=%s opacity=%s fontSize=%s fontObj=%s text='%s'",
            safe(function() return t:GetVisibility() end),
            safe(function() return t:GetRenderOpacity() end),
            safe(function() return t.Font.Size end),
            safe(function() return t.Font.FontObject:GetFullName() end),
            safe(function() return t.Text:ToString() end)))
        log(string.format("tree: widgetTree=%s root=%s textParent=%s desiredSize=%s",
            safe(function() return w.WidgetTree:GetFullName() end),
            safe(function() return w.WidgetTree.RootWidget:GetFullName() end),
            safe(function() return t:GetParent():GetFullName() end),
            safe(function() local s = t:GetDesiredSize(); return s.X .. "," .. s.Y end)))
    end
    return true
end)

log("loaded in " .. (NOOB_MODE and "NOOB mode (reveals every code immediately)"
    or "REAL mode (reveals only at the PC)") .. " - overlay on screen, 'doorcode' to log")
