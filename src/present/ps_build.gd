extends RefCounted
## Build-time switches for the presentation shell.
##
## These are **compile-time** constants, not ProjectSettings: the project file is
## owned by the coordinator, and a debug panel must not be switchable at runtime
## (nothing on the box may turn it on).
##
## Flip one line here for an internal debug build; nothing else in the project
## branches on it.

## Internal 设置 / 调试 panel (`src/present/ps_tuning_panel.gd`).
##
## `false` (shipped default) means:
##   * `main.gd` never `load()`s the panel script, so its code is not even
##     compiled at boot and the node is never created;
##   * no key reaches it, nothing is drawn, and no frame pays for it (the only
##     residue is a constant-folded `if` in `main.gd`);
##   * `--capture-tuning` prints `node=absent` and saves evidence/tuning-off.png.
##
## `true` means the panel exists: F8 (or any key in `PSRemote.PANEL_KEYS`) opens
## it, it writes `cfg` / `PSTuning` live, and `--capture-tuning` drives it.
##
## Note: with the flag off the file is still *packed* into the export (it is not
## in the preload graph, but the exporter packs every `res://` file). Adding
## `src/present/ps_tuning_panel.gd` to the export preset's exclude filter removes
## it from the package completely; `export_presets.cfg` belongs to the
## coordinator, so this is left as a note rather than an edit.
const TUNING_ENABLED := false
