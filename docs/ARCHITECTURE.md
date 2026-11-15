# Hawkthorne: Ashes of the Stars — architecture

Godot 4.3 / GDScript, GL Compatibility, 1280 × 720 logical canvas. Artwork, portraits, effects, music, and sound are generated in code. Modules preload script resources instead of using `class_name`; source startup does not depend on an editor import pass. Scene trees are assembled in code below the existing `main.tscn` entry point.

## Ownership and module map

`AGENT.md` defines the interface between the primary gameplay implementation and this secondary presentation/tooling implementation. A module's presence does not establish integration or campaign completion.

| Module | Owner | Responsibility |
| --- | --- | --- |
| `project.godot`, `main.tscn`, `src/main.gd` | Primary | Entry point, game lifecycle, room transitions, root references, UI wiring. The provided main script is a placeholder. |
| `src/core/db.gd` (`DB`) | Primary | Static region/actor/upgrade tables; parsers for chunks, rooms, quests, dialogue; room assembly and conditional dialogue resolution. |
| `src/core/game.gd` (`G`) | Primary | State, narrative conditions/effects, save migration and checksum validation, settings, input, telemetry, progression. |
| `src/core/audio.gd` (`Snd`) | Primary | Synthesized SFX/instruments, regional music themes and sequencer, audio buses. |
| `src/core/art.gd` (`Art`) | Primary | Shared procedural drawing helpers, humanoids, creatures, portraits, font and glow. |
| `src/world/level.gd`, `src/actors/*` | Primary | Room tiles/collisions, entities, player movement/combat, enemy/boss AI, camera, interactions. Not included in the initial work-order checkout. |
| `src/ui/hud.gd`, `src/ui/dialogue_ui.gd` | Primary | Player HUD, conversations, choice/effect processing, cutscene orchestration. Not included in the initial work-order checkout. |
| `data/*` | Primary | Authored room/chunk/quest/dialogue content; text data must be included in exports. The provided rooms, chunks, and quests are empty; dialogue files are absent. |
| `src/ui/menus.gd` | Secondary | Drawn title, slots, pause, settings, bindings, journal, inventory, upgrades, star/local maps, credits, ending records. |
| `src/world/backdrop.gd`, `shaders/sky.gdshader`, `shaders/fog.gdshader` | Secondary | Regional parallax geometry, sky, weather, fog. |
| `src/world/post.gd`, `shaders/post.gdshader` | Secondary | Colour grade, vignette, grain, damage pulse, water, darkness and desaturation. |
| `src/ui/vista.gd` | Secondary | Procedural cinematic tableaux and letterboxing. |
| `src/world/flight.gd` | Secondary | Space-navigation interlude, hazards, three hull points, restart, Sable assistance. |
| `src/dev/console.gd` | Secondary | Developer-only commands; must be instantiated by the root to receive input. |
| `tests/*` | Secondary | Content/progression/state/save validation and runtime smoke checks. |
| `run.sh`, `run.bat`, `export_presets.cfg`, `tools/build.sh` | Secondary | Terminal launch and Windows/Linux packaging. |

Only the three existing singletons (`DB`, `G`, `Snd`) are autoloads. Optional presentation modules are ordinary nodes owned by the root or level. Preserve the file boundary: report required primary changes in `AGENT.md` instead of silently changing primary files.

## Lifecycle and integration contracts

1. The engine loads `DB`, `G`, and `Snd`. `DB` parses `data/*.txt`; `G` initializes state/settings/actions; `Snd` initializes its buses and generated audio.
2. The root sets `G.main`, constructs menu/dialogue/vista/console nodes, and opens `menus.open("main")`. Console functionality is restricted by `G.dev`.
3. `new_game(slot)` or `continue_game(slot)` initializes/loads state, then creates the current `level.gd` and assigns `G.level`.
4. A level assembles `DB.assemble(room_id)`, spawns actors, calls backdrop/post setup, and updates the backdrop with the camera centre and elapsed time.
5. Dialogue resolves `DB` nodes and calls `G.apply(effects)` for progression/relationship/quest mutations. The root handles deferred room transitions and cinematic APIs.
6. Returning to title frees gameplay nodes, clears `G.level`, and releases gameplay pause ownership. Live node instances and timers are recreated on load; persistent progress belongs in `G.state`.

| Consumer API | Contract |
| --- | --- |
| `G.main.new_game(slot)`, `continue_game(slot)`, `load_room(room_id, entry="start")`, `to_menu()` | Required gameplay lifecycle methods supplied by the primary root. |
| `G.main.fade(alpha_target, seconds)`, `G.main.dialogue.play(node_id, on_done)`, `dialogue.active` | Primary transition/dialogue hooks. |
| `menus.open(name, args={})`, `close_all()`, `is_open()` | Menu routing; slots use `{mode: "new"}` or `{mode: "load"}`. |
| `backdrop.setup(region_id, room)`, `update_view(cam_center, t)` | Initialize regional art; update parallax/weather without recreating geometry every frame. |
| `post.setup(region_id)`, `pulse(amount)`, `set_dark(amount, screen_pos)`, `set_desat(x)` | Region grade and gameplay effects; screen position is in viewport pixels. |
| `vista.show_vista(name)`, `hide_vista()`, `visible_now()` | Cinematic presentation under dialogue. |
| `flight.start({length_sec, density, region}, on_done)` | Starts/restarts the interlude; completion invokes the callback. |

Canvas layers: backdrop `-10`; ordinary level/actors `0`; weather `2`; post `5`; vista `15`; dialogue above vista; menus `30`. Keep HUD/dialogue above the effects they should not inherit. Menus process while paused and must restore prior tree pause state when closed. The primary lifecycle must avoid freeing a menu that still owns a pause without releasing it.

## State, data, and input

`G.state` stores chapter/room/checkpoint, flags, relationships, shards/upgrades, abilities/mods/equipment, key items, quests, visited/taken objects, boss records, dialogue log, chapter timers, combat statistics, and current player resources. Effects and conditions should go through `G.apply` / `G.cond`; avoid creating a second progression system inside presentation code.

Saves are versioned JSON with a SHA-256 integrity check; the public salt detects accidental damage and is not an anti-cheat/security boundary. `read_slot` validates/migrates before `load_game` accepts state. Save files and global settings/ending records live in `user://` (custom directory `HawkthorneAshes`), outside the source checkout. Tests must preserve or isolate existing player data.

`DB` reads chunks, rooms, and quests plus dialogue files `act1`, `act2`, `act3`, `act4`, `act5`, `act6`, `hub`, `side`, and `lore`. Regions, actors, upgrades, abilities, chapter destinations, and side destinations are table-driven. An empty `DB.errors` is necessary but does not prove that enough content was authored; tests must check nonempty required data and references.

Use actions in `G.ACTIONS`; menus accept up/down/left/right and confirm via accept/jump/interact, with pause/dash for back. Key/button bindings persist through `G.rebind`. Settings control audio, fullscreen, shake, text speed, difficulty, high contrast, flashes, large text, auto-parry, and slow motion. Gameplay owns combat/time-scale application; presentation respects the relevant visual settings.

## Verification and release gates

From the repository root:

```bash
GODOT=/path/to/godot ./run.sh --headless --quit-after 5
GODOT=/path/to/godot ./run.sh --headless -s tests/run_tests.gd
GODOT=/path/to/godot ./run.sh --headless -s tests/run_tests.gd -- --unit-only
GODOT=/path/to/godot ./run.sh --headless -s tests/run_secondary.gd
xvfb-run -a /path/to/godot --path . --rendering-driver opengl3 --audio-driver Dummy -s tests/run_secondary.gd -- --render --screenshots /tmp/hawkthorne-frames
GODOT=/path/to/godot ./tools/build.sh all --release
```

The five-frame project check only validates what startup actually loads. The data/state runner must fail for missing required content and check dialogue/room references, chapter progression, platform reachability, save integrity/migration, conditions/effects, and 120 physics frames for every level. A graphical run is additionally needed for shaders and visual layout. Exports must be launched on their target platform; exporting successfully does not certify gameplay or controller behaviour.

`--unit-only` deliberately skips the campaign gates. `run_secondary.gd` exercises
the actual presentation modules using temporary room/quest/dialogue fixtures and
a fake primary lifecycle. It checks menu navigation/confirmation, settings,
rebinding, mod limits, upgrade costs, map topology, every region/vista, flight
steering/loss/retry/completion, and developer-command validation. `--render`
additionally captures nonblank frames through the real renderer. These tests
validate the supplied module interfaces, not authored campaign gameplay or a
physical controller. Save slots/settings are restored after the secondary suite;
prefer a separate `XDG_DATA_HOME` for test runs on Linux. The state/save suite and
room worker use dedicated save destinations and never overwrite player slots.

The console listens only in developer mode (backquote, command history with
up/down, output scroll with PageUp/PageDown). Its `god` flag and `enemies` group
are primary integration contracts detailed under `AGENT.md` Requests.

Current integration prerequisites are the primary root lifecycle, levels/actors/HUD/dialogue UI, populated campaign data, and fixes to any primary parser/runtime defects recorded under `AGENT.md` Requests. Until these are complete, the presentation modules and packages are development components. A 14-chapter, 10+ hour game is **not verified**. Campaign length must be measured through active normal-difficulty playthroughs, excluding pauses, optional content, and idle time; design targets and file counts are not duration evidence.
