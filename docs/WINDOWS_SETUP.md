# Windows setup and builds

Use **Godot 4.3 stable, standard edition, Windows x86-64**. This is a GDScript project; .NET and Visual Studio are not required. The renderer is GL Compatibility (OpenGL 3.3). The game uses a 1280 × 720 viewport and scales the canvas to the window.

## Install and launch from source

1. Download the standard Windows editor ZIP from the [official Godot 4.3 release](https://github.com/godotengine/godot-builds/releases/tag/4.3-stable). Compare its SHA-512 with that release's `SHA512-SUMS.txt`; PowerShell provides `Get-FileHash <zip> -Algorithm SHA512`.
2. Extract the complete ZIP to a permanent directory. Keep the console executable beside the graphical executable if using the console variant.
3. Clone this repository, or extract its source archive.
4. Set `GODOT` to the executable's full path, then run the launcher. Do not include quote characters inside the variable value.

Command Prompt:

```bat
cd C:\Projects\TheLegendOfHawkThorne
set "GODOT=C:\Tools\Godot\Godot_v4.3-stable_win64.exe"
run.bat
run.bat -- --dev
```

PowerShell:

```powershell
Set-Location C:\Projects\TheLegendOfHawkThorne
$env:GODOT = 'C:\Tools\Godot\Godot_v4.3-stable_win64.exe'
.\run.bat
.\run.bat -- --dev
```

Alternatively place an executable named `godot.exe` or `godot4.exe` on `PATH`. `GODOT` takes priority. Launchers work from other working directories and preserve the arguments after `--`, including `--dev`. Running source does not require an editor import pass. To open the editor, use `run.bat --editor`.

The game and exported packages work offline after the editor or package has been obtained. No account or network service is needed for play. The developer console is enabled only with `-- --dev` and toggled with backquote.

## Controls and local data

The defaults are WASD/arrows for movement and menu navigation; Space jumps/confirms, Enter confirms, E interacts/confirms, and Escape goes back/pauses. In gameplay, J attacks, K shoots, L uses the gauntlet, Shift dashes, I parries, Q heals, R changes ammunition, F calls Sable, and Tab opens the journal. Controller sticks/D-pad navigate, A confirms/jumps, B goes back/dashes, and Start pauses. Settings includes binding and accessibility controls.

Godot stores this project's settings, three versioned save slots, and telemetry in `%APPDATA%\HawkthorneAshes`. Back up that directory before testing saves or moving machines. Reinstalling the source does not reset saves. On Linux, the usual path is `~/.local/share/HawkthorneAshes`; `XDG_DATA_HOME` can change the base directory.

## Automated checks

From Command Prompt with `GODOT` set:

```bat
run.bat --headless --quit-after 5
run.bat --headless -s tests/run_tests.gd
run.bat --headless -s tests/run_tests.gd -- --unit-only
run.bat --headless -s tests/run_secondary.gd
```

Read the output as well as the exit code: a Godot process can exit successfully after a script-loading error. The test runner returns a failure for missing required campaign data and modules, invalid references, unreachable progression, and failed save/state checks. A blank window or an open process does not establish a playable campaign.

The unit-only mode explicitly skips campaign checks. The secondary suite tests
presentation interfaces with temporary data and restores existing save slots and
settings. For graphical verification, omit `--headless` and add
`-- --render --screenshots C:\Temp\HawkthorneFrames` to the secondary command.

## Export Windows and Linux packages

Install the **matching 4.3 stable export templates** through **Editor → Manage Export Templates**. Both targets use standard x86-64 templates, embedded game data, and the GL Compatibility renderer. Godot locates templates in `%APPDATA%\Godot\export_templates\4.3.stable` on Windows. Presets explicitly include `data/*`, because dialogue/quest/room text is loaded at runtime.

In the editor, choose **Project → Export**, select **Windows Desktop** or **Linux**, and export to the path in its preset. Windows resource modification and signing are disabled, so cross-exporting from Linux does not require Wine or signing credentials. Packages are unsigned development builds.

For the repeatable script, use Bash (Git Bash on Windows, or Bash on Linux/macOS):

```bash
export GODOT='/c/Tools/Godot/Godot_v4.3-stable_win64.exe'  # Git Bash example
./tools/build.sh windows --release
./tools/build.sh linux --release
./tools/build.sh all --debug
```

`tools/build.sh` checks the engine and matching template files, imports resources, then exports. Errors fail the command, and a failed export preserves the previous executable. Output goes to `build/windows/Hawkthorne.exe` and `build/linux/Hawkthorne.x86_64`. Transfer the target executable to a matching operating system and run it; the data pack is embedded. Windows builds still require a real Windows launch and controller check before release.

## Troubleshooting and release status

- **Engine not found:** check the exact `GODOT` path, including `.exe`, or use `where godot` / `where godot4`. The standard ZIP retains its versioned filename; renaming it is optional when using `GODOT`.
- **Missing export templates:** install templates for the editor's exact version. A different minor or patch release needs its own matching templates.
- **Graphics driver error:** update the GPU driver. GL Compatibility needs OpenGL 3.3 support; a headless run does not verify graphical rendering.
- **Missing content, a blank window, or failed tests:** inspect [ARCHITECTURE.md](ARCHITECTURE.md) and the primary-agent requests in `AGENT.md`. Launchers and exports cannot supply absent gameplay or narrative modules.

The secondary-agent implementation supplies presentation, menus, tools, and validation. The original primary-agent checkout has a placeholder `src/main.gd`, missing gameplay/UI modules, and empty campaign data files. Until those are supplied and integrated, an export is a development artifact, **not a playable release**. No 10-hour campaign playthrough or Windows runtime certification is claimed.
