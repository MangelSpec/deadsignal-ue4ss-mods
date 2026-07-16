# Dead Signal Mods (UE4SS)

Free, open-source [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mods, tweaks,
and fixes for the game **Dead Signal** (Steam, Unreal Engine 5.2, single-player
horror).

**Included mods:**

- **ShadowToggle** is an automatic shadow fix for Dead Signal. It switches shadow
  quality by room, keeping the "Noir" shadow tell visible where it matters without
  making you change the setting manually every time you move.
- **FlashlightAlways** is a flashlight-from-start fix. It skips the mandatory
  flashlight pickup so your flashlight works from the first second of a new game.
- **DoorCodeMemory** is a simple quality-of-life memory helper. By default, it only
  remembers and displays a door code after you enter it correctly, proving you
  already know it. It gives no advance information; it just replaces writing the
  code on a real notepad or walking back to the computer to check it again.

Each folder in this repo is one mod. Copy the ones you want into your game and
enable them.

## Requirements

You need two things: the game, and **UE4SS** (the free mod loader that actually
runs these Lua mods). If you have never modded before, just follow the steps in
order; nothing here requires coding.

- **Dead Signal** on Steam.
- **UE4SS v3.0.1 or newer** (installed below).

### Step 1: Open your game folder

You do not need to hunt through your drive for it. Let Steam open it for you:

1. In Steam, right-click **Dead Signal** → **Manage** → **Browse local files**.
2. A folder window opens. Go into `DeadSignal` → `Binaries` → `Win64`.

This `Win64` folder is the one that contains `DeadSignal-Win64-Shipping.exe`.
**Keep this window open**; it is where everything below goes.

### Step 2: Install UE4SS (one time)

1. Open the [UE4SS releases page](https://github.com/UE4SS-RE/RE-UE4SS/releases).
2. Under the newest release, download the **main** zip (named like
   `UE4SS_v3.0.1.zip`). Do **not** download the "experimental", "dev", or "custom"
   builds.
3. Extract everything from that zip straight into the `Win64` folder from Step 1.
4. It worked if `Win64` now contains `dwmapi.dll`, `UE4SS.dll`, and a `Mods`
   folder, all sitting right next to `DeadSignal-Win64-Shipping.exe`.

## Install a mod

1. Copy the mod's folder (for example `ShadowToggle`) into the `Mods` folder you
   just got, so the path looks like:
   ```
   ...DeadSignal/Binaries/Win64/Mods/ShadowToggle/
   ```
2. In that same `Mods` folder, open **`mods.txt`** with Notepad (right-click it →
   **Open with** → **Notepad**). Add a line to turn the mod on, and put it
   **above** the `Keybinds : 1` line (that line has to stay last):
   ```
   ShadowToggle : 1
   ```
   `: 1` means on, `: 0` means off. Save the file and close it.
3. Launch the game. To confirm the mod loaded, open **`UE4SS.log`** (back in the
   `Win64` folder) and look for the line `Starting Lua mod 'ShadowToggle'`.

Some mods have extra commands you type into the **in-game console**. Open it with
**F10** or the **Caret** key (`^`, above Tab). The console is provided by the
bundled ConsoleEnablerMod, so it works as soon as UE4SS is installed.

## Not working?

- **No `UE4SS.log` and no console in-game:** UE4SS itself is not installed
  correctly. Double-check that `dwmapi.dll` and `UE4SS.dll` are in the same folder
  as `DeadSignal-Win64-Shipping.exe` (see Step 2), not in a subfolder.
- **The log has no `Starting Lua mod '...'` line for your mod:** the mod folder or
  the `mods.txt` line is wrong. Confirm the folder name and the name in `mods.txt`
  match exactly (case-sensitive), the value is `: 1`, and the line is **above**
  `Keybinds : 1`.
- **`mods.txt` won't save:** if you copied the game into a protected location,
  Notepad may need to be run as administrator, or copy the file to your Desktop,
  edit it, and copy it back.

---

## Mods

### ShadowToggle (automatic shadow fix / shadow quality toggle)

Automates Dead Signal's shadow-quality tradeoff so you stop switching it by hand in
the settings menu. Shadows toggle on and off automatically based on where you are.

**Why:** Dead Signal makes shadow quality a no-win choice. Low/off shadows give
great room visibility for spotting report items, navigating dark rooms, and reading
the security cameras, but hide the "Noir" shadow tell. Medium or higher renders the
Noir "is a killer here" tell in the apartment, but darkens rooms and worsens the
camera feeds. No single setting is right everywhere.

**What it does:** Shadows turn **ON** only while the game reports that you are in the
apartment's open-plan living area (computer / living room / kitchen), and **OFF**
everywhere else. Sitting at the desk also forces them OFF for a clearer camera feed.
The switch follows the game's room and active-pawn events.

**Controls**

| Input | Effect |
| --- | --- |
| (automatic) | Shadows follow the current room and active pawn; nothing to press. |
| `F8` | Toggle the automatic switching on/off. |
| `shadow on` / `shadow off` / `shadow <0-5>` | Force a shadow value (auto overrides it on the next room/pawn event). |
| `shadow auto on` / `shadow auto off` | Pause or resume automatic switching. |
| `shadowstate` | Print the cached room, active pawn, and current decision to the log. |

**Configuration** (top of `ShadowToggle/scripts/main.lua`):

- `ON_SHADOW_QUALITY` — shadow quality applied when ON (`1`-`5`, higher is sharper).
- `SHADOW_ON_LOCATIONS` — the game room values where shadows stay ON.
- `OFF_AT_DESK` — set `false` if you want shadows ON at the desk when inside the area.

**Note:** ShadowToggle sets `r.ShadowQuality` directly, which takes console priority.
While the mod is active, the in-game menu's Shadow Quality slider will not visibly do
anything. That is expected, not a bug.

**Retuning the ON rooms:** add or remove `LOCATION` entries in
`SHADOW_ON_LOCATIONS`, press **Ctrl+R** in-game, then cross a room boundary and test
with `shadowstate`.

### FlashlightAlways (flashlight from start / skip flashlight pickup)

Makes the flashlight usable from the start, skipping the mandatory pickup.

**Why:** grabbing the flashlight at the beginning is a pointless chore.

**What it does:** the game gates the flashlight behind an inventory item. This mod
hooks the game's item-possession check and reports the flashlight as owned, so the
**normal flashlight key works immediately** in a new game. No key rebinding, no
commands; it uses the game's own flashlight controls.

**Configuration** (top of `FlashlightAlways/scripts/main.lua`):

- `FLASHLIGHT_ITEM_ID` — the inventory id the game uses for the flashlight (`62`).
  Only change this if a game update renumbers items and the flashlight stops working.

### DoorCodeMemory (door code memory helper / QoL reminder)

Remembers the apartment door code after you enter it correctly, then shows it on
screen while you are away from the computer. The default behavior is a clear
quality-of-life helper, not an advantage: you must prove you know each code before
the mod will display it.

**Why:** the door code lives on the desktop computer and rerolls on a timer. When
you need the same code again, your choices are to remember it, write it down, or trek
back to check. This mod acts as an in-game notepad after a correct entry.

**What it does:** it privately captures the code when the desktop receives it. By
default, `DOORCODE: <code>` appears in the top-left only after you have entered that
code correctly at the apartment keypad. A reroll hides the old code until the new one
has also been entered correctly. The overlay stays hidden in menus, before the first
reveal, and while you are at the PC.

**Controls**

| Input | Effect |
| --- | --- |
| (automatic) | The code shows in the corner while you are away from the PC. |
| `doorcode` | Print the remembered code and current state to the log. |

**Configuration** (top of `DoorCodeMemory/scripts/main.lua`):

- `REVEAL_AFTER_CORRECT_ENTRY` — `true` (default) reveals each code only after it has
  been entered correctly at the apartment keypad. Set `false` to reveal the initial
  code and later rerolls after visiting the PC.
- `NOOB_MODE` — set `true` for the optional assist mode that shows every code
  immediately, without requiring a correct entry.
- `HUD_COLOR` / `HUD_FONT_SIZE` — overlay colour and text size.
- `HUD_LINES_DOWN` / `HUD_LEFT_PAD` — top and left margin of the overlay.

---

## Development

- **Hot reload:** enable it once by setting `EnableHotReloadSystem = 1` in
  `Binaries/Win64/UE4SS-settings.ini` (needs one game restart to take effect). After
  that, edit a mod's `main.lua` and press **Ctrl+R** in-game to reload. No restart.
- **Feedback channel:** `Binaries/Win64/UE4SS.log`. Every Lua `print(...)` shows up
  there prefixed with `[Lua]`, along with load messages and errors.
