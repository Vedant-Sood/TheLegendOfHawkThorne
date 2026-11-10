# AGENT.md — Work order for the secondary agent

**Project:** *Hawkthorne: Ashes of the Stars* — Godot 4.3, GDScript, `gl_compatibility` renderer, 1280×720 viewport.
**Branch:** `claude/hawkthorne-game-development-2qwlla` (work here; `git pull --rebase origin <branch>` before every push; push small commits often).

The codebase is split in two halves by **file ownership**. Only edit files you own. If you need a change in a
file owned by the primary agent, add a note under "Requests" at the bottom of this file instead of editing it.

| Owner | Files |
|---|---|
| **Primary agent** | `project.godot`, `main.tscn`, `src/main.gd`, `src/core/*`, `src/world/level.gd`, `src/actors/*`, `src/ui/hud.gd`, `src/ui/dialogue_ui.gd`, `data/**` |
| **Secondary agent (you)** | `src/world/backdrop.gd`, `src/world/post.gd`, `src/world/flight.gd`, `src/ui/menus.gd`, `src/ui/vista.gd`, `src/dev/console.gd`, `shaders/*`, `tests/*`, `run.sh`, `run.bat`, `export_presets.cfg`, `tools/*`, `docs/ARCHITECTURE.md`, `docs/WINDOWS_SETUP.md` |

## House rules

- **No bitmap/audio assets.** Everything is drawn procedurally (`_draw`, shaders) — see `src/core/art.gd`.
  Use `const Art = preload("res://src/core/art.gd")`. **Do not use `class_name`** (the game must run without an editor import pass).
- No `.tscn` scenes; build node trees in code. Do not add autoloads.
- Untyped/loosely typed GDScript; never use `:=` on a Variant expression.
- Input: use the actions defined in `G.ACTIONS` (`left right up down jump attack shoot gauntlet dash parry heal interact swap sable journal pause accept`).
  Menus must be fully usable with keyboard **and** controller: `up/down/left/right` navigate, `accept` or `jump` or `interact` confirms, `pause` or `dash` goes back.
- Audio: `Snd.sfx("ui")`, `Snd.sfx("ui_ok")`, `Snd.sfx("ui_back")`, `Snd.music(theme)`.
- Every script must load cleanly under `godot --headless --path . --quit-after 5` with no script errors.
- Never claim something works without running it. Screenshot check: `xvfb-run -a godot --path . --rendering-driver opengl3 ...`.

## Globals you can rely on (already implemented)

- `G.state` (dict: `flags rel chapter room cp shards upgrades abilities mods equipped items quests visited taken bosses log time stats`),
  `G.settings`, `G.meta.endings`, `G.val(name)`, `G.cond(expr)`, `G.apply(effects)`, `G.set_quest(id, stage)`,
  `G.save_game()`, `G.read_slot(n) -> {ok, error, data, saved}`, `G.load_game(n)`, `G.delete_slot(n)`, `G.SLOTS`,
  `G.save_meta()`, `G.apply_settings()`, `G.rebind(action, event)`, `G.bind_text(action)`, `G.total_time()`,
  `G.max_hp()`, `G.max_en()`, `G.sable_stage()`, signals `G.toast(msg)`, `G.quest_changed(id)`, `G.dev` (true when launched with `-- --dev`).
- `DB.regions`, `DB.chars`, `DB.enemies`, `DB.bosses`, `DB.upgrades` (`[id, name, desc, max_level, base_cost]`), `DB.mods`,
  `DB.items`, `DB.abilities`, `DB.chapters`, `DB.side_dest` (`[id, label, region, room, cond, quest]`), `DB.quests`
  (`{id,title,type,stages{int:text}}`), `DB.rooms`, `DB.nodes`, `DB.resolve(node_id)`, `DB.assemble(room_id) -> {W,H,grid,slots}`, `DB.errors`.
- `G.main` (root node, primary agent) exposes:
  `new_game(slot)`, `continue_game(slot)`, `load_room(room_id, entry="start")`, `to_menu()`, `fade(alpha_target, seconds)`,
  `dialogue.play(node_id, on_done=Callable())`, `dialogue.active`, and `G.level` (current level or null; `G.level.player`).

`src/main.gd` loads your scripts with `load()` guarded by `ResourceLoader.exists()`, so the game keeps running while your half is in progress.

## Task list (in priority order)

### 1. `src/ui/menus.gd` — all menu screens (`extends CanvasLayer`, layer 30, `process_mode = ALWAYS`)

API used by main: `open(name, args = {})`, `close_all()`, `is_open() -> bool`. Draw with `_draw` on a full-rect Control (no themed Control widgets);
one reusable list widget (title, items with label / value / detail text, selection highlight, scroll) is enough. Animated open/close transitions (slide + fade).
Screens:
- `main` — animated title screen (use `backdrop`/sky shader + title lettering "HAWKTHORNE — ASHES OF THE STARS"), items: Continue (most recent valid slot), New Game, Load Game, Settings, Endings & Records, Credits, Quit. Plays `Snd.music("menu")`.
- `slots` (`args.mode = "new"|"load"`) — 3 slots showing chapter title, play time, save date, or the validation error from `G.read_slot`; confirm overwrite / delete.
- `pause` — Resume, Journal, Map, Inventory, Settings, Save & Quit to Title. Pauses the tree (`get_tree().paused = true`).
- `settings` — master/music/sfx volume, fullscreen, screen shake (0–1), text speed, difficulty (Story/Normal/Hard), and accessibility:
  high-contrast (`contrast`), reduce flashes (`flash=false`), large text (`big_text`), auto-parry assist (`auto_parry`), slow motion 80% (`slow`). Write to `G.settings`, then `G.apply_settings()` + `G.save_meta()`.
- `bindings` — list every `G.ACTIONS` entry with `G.bind_text(id)`; select → "press a key or button" → `G.rebind(id, event)`; reset-to-default option (`G.settings.binds = {}` then `G.setup_input()`).
- `journal` — tabs: Quests (active/completed from `G.state.quests` + `DB.quests`, stage 99 = done), Relationships (`G.state.rel` with a descriptive word per band, portrait via `Art.portrait`), Dialogue History (`G.state.log`, scrollable), Codex (lore flags `lore.*`).
- `inventory` — key items (`G.state.items`), mods (`G.state.mods`; equip up to 2 into `G.state.equipped`), abilities list.
- `upgrades` (opened from the ship workbench) — buy levels from `DB.upgrades` with shards; cost = `base_cost * (level + 1)`.
- `starmap` (opened from the ship nav console) — a drawn star chart: one node per region, the current main chapter destination
  (`DB.chapters[G.state.chapter]`) highlighted, optional destinations from `DB.side_dest` whose `cond` passes, and previously
  completed chapters for free-roam revisits. Selecting calls `G.main.load_room(room)`.
- `map` — local map: boxes for each room of the current chapter chain (follow `exit=` links from the chapter start room; doors `D` as branches), visited rooms (`G.state.visited`) lit, current room marked.
- `credits`, `endings` (records from `G.meta.endings`; five endings: `mesh`, `sever`, `ascend`, `dominion`, `steward`).

### 2. `src/world/backdrop.gd` + `shaders/` — parallax scenery, weather, fog (`extends CanvasLayer`, layer -10)

API: `setup(region_id, room)` and `update_view(cam_center: Vector2, t: float)` (called every frame by the level).
- Sky: full-screen `ColorRect` with `shaders/sky.gdshader` (gradient from `region.top`→`region.bot`, stars, nebula noise, sun/dying-star disc from `region.sun`/`sunc`).
- 3–4 parallax layers per region (factors ~0.08/0.2/0.4/0.65), each a `Node2D` whose `_draw` runs once and tiles horizontally (2560 px wide). Region art direction (all 11 keys in `DB.regions`):
  `kharon` megastructure towers, gantries, lit windows, holo-ads, drifting ships · `colony` domes, antennae, dusk mountains · `glass` dunes, crystal spires, buried starship rib, observatory dome ·
  `drowned` flooded lab silhouettes, light shafts, kelp · `cathedral` colossal arches, holographic stained glass, hanging machinery · `orbit` planet with storm bands, rotating warship wrecks ·
  `city` cavern with geometric monoliths and glowing circuitry · `ashen` burning skyline, snapped orbital elevator, artillery flashes · `heart` dying star, megastructure arcs, memory fragments ·
  `mind` pale void with inverted houses of Veyra · `ship` hull interior with star-streak windows.
- Weather layer (separate CanvasLayer +2 child you own): `rain dust sand bubbles motes debris ash memory none` from `region.weather`; stateless hash-based particles drawn in `_draw`.
- Fog: `ColorRect` + `shaders/fog.gdshader` using `region.fog`/`foga`.

### 3. `src/world/post.gd` + `shaders/post.gdshader` — screen post-process (`extends CanvasLayer`, layer 5)

Full-screen ColorRect reading `hint_screen_texture`: vignette, colour grade (`region.grade`), film grain, chromatic aberration pulse on damage,
underwater wobble (`region.water`), desaturation, and a darkness mask with a light hole at the player's screen position.
API: `setup(region_id)`, `pulse(amount)` (hit aberration, decays), `set_dark(amount, screen_pos)`, `set_desat(x)`. Respect `G.settings.flash` and `G.settings.contrast`.

### 4. `src/ui/vista.gd` — cinematic vistas for cutscenes (`extends CanvasLayer`, layer 15)

API: `show_vista(name)`, `hide_vista()`, `visible_now()`. Full-screen animated illustrated scenes drawn procedurally, with slow camera drift and letterbox bars
(the dialogue box is drawn above them by the primary agent's dialogue UI). Required: `veyra_fall` (a blue-green world, the station breaking apart, fire lines racing across the surface),
`black_dawn` (assault craft approaching the station), `cockpit` (the Cinder Wren's bridge, stars), `fleet_battle`, `dimming` (a starfield where stars go out one by one),
`memorial` (a rock face with thousands of small lights), `senate`, `heart` (megastructure around the dying star), `mesh`, `sever`, `ascend`, `dominion`, `steward` (ending tableaux).

### 5. `tests/run_tests.gd` — automated checks (`extends SceneTree`, run: `godot --headless --path . -s tests/run_tests.gd`)

Exit code 1 on any failure. Checks: DB loads with `DB.errors` empty; every room's chunks exist; every `exit/back/D` target room exists; every dialogue `->`/choice target and
every room-referenced node (`enter`, `end`, `t`, `n` → `npc_<id>`, `L` → `lore_<id>`) resolves; every speaker is known; every enemy/boss id in rooms exists;
quest ids used in effects exist; chapter chain 1→14 is connected (each chapter start room reaches a room whose `end`/dialogue sets `chapter:N+1`);
platformer reachability of each room (standable-tile graph: jump ≤3 tiles up, ≤6 across; treat gates as open) from spawn to the right edge;
save/load round-trip, checksum tamper rejection, version migration; `G.cond`/`G.apply` unit tests; a smoke test that instantiates `level.gd` for every room and steps 120 physics frames.

### 6. `src/dev/console.gd` — developer console (only when `G.dev`), toggled with backquote

Commands: `room <id>`, `chapter <n>`, `flag <name> <v>`, `rel <who> <v>`, `give <shards>`, `unlock <ability|all>`, `god`, `kill` (all enemies), `heal`, `save`, `time`, `help`.

### 7. `src/world/flight.gd` — space-navigation sequence (`extends Node2D`)

A side-scrolling piloting interlude (the Cinder Wren weaving through wreckage; Sable calls out hazards and — when `G.val("rel.sable") >= 3` — projects a safe-path line).
API: `start(config: Dictionary, on_done: Callable)` with `config = {length_sec, density, region}`; 3 hull points; failing restarts the run.

### 8. Launch & packaging

`run.sh` / `run.bat` (find `godot`/`godot4`/`GODOT` env var; pass `-- --dev` through), `export_presets.cfg` (Windows Desktop + Linux, include filter `data/*`),
`tools/build.sh`, `docs/WINDOWS_SETUP.md`, `docs/ARCHITECTURE.md` (module map of both halves).

## Requests (secondary → primary)

_(append here)_
