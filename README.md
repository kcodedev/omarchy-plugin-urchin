# Urchin for Omarchy

A native Omarchy Quattro panel for editing, building, and flashing an Urchin
keyboard running ZMK.

## What it does

- Renders every layer using the physical coordinates from `urchin.json`.
- Edits one ZMK binding at a time without reformatting the rest of the keymap.
- Shows the keymap's uncommitted Git diff.
- Builds left, right, or settings-reset UF2 firmware locally in the official
  ZMK Docker image.
- Keeps the ZMK checkout and build directories cached for incremental builds.
- Waits for a mounted `NICENANO` bootloader and flashes the selected artifact.
- Opens ZMK Studio for temporary live experiments.
- Shows the live left-half battery percentage when hovering over the bar icon.
  When firmware exposes the split peripheral battery proxy, the tooltip shows
  both halves.

The ZMK config repository remains the source of truth. The plugin never commits
or pushes automatically.

## Install

```bash
omarchy plugin add https://github.com/kcodedev/urchin-omarchy-plugin.git --enable
```

For local development, link the checkout into the user plugin directory and
rescan the shell:

```bash
ln -s /absolute/path/to/urchin-omarchy-plugin \
  ~/.config/omarchy/plugins/kcodedev.urchin
omarchy-shell shell rescanPlugins
omarchy plugin enable kcodedev.urchin --section right
```

The default firmware repository is
`/home/kob/Repos/zmk-urchin-kcodedev`. It can be changed in the widget's plugin
settings along with the relative keymap and physical-layout paths.

## First local build

Docker must be installed and available to the desktop user. The first build
pulls the official ZMK ARM image and downloads the west modules declared by the
firmware repository. Later builds reuse:

```text
~/.cache/urchin-manager/workspace/
~/.local/state/urchin-manager/artifacts/
```

The CLI used by the panel is also available directly:

```bash
bin/urchinctl snapshot
bin/urchinctl battery
bin/urchinctl build left
bin/urchinctl build all
bin/urchinctl flash left
```

The tested official image is pinned by digest. Set `URCHIN_ZMK_IMAGE` to
override it when deliberately upgrading the toolchain.

## Flashing

Build the desired half, select **Flash left** or **Flash right**, then put that
controller into bootloader mode. The plugin only writes after finding a mounted
filesystem whose label is exactly `NICENANO`.

For a settings reset, build the reset image and use the CLI to flash it:

```bash
bin/urchinctl flash reset
```

Follow the normal ZMK split-keyboard reset sequence; both halves lose their
pairing data and must be reset and reflashed appropriately.

## ZMK Studio

Studio stores runtime keymap changes in the keyboard. Those settings override
future `.keymap` changes until **Restore Stock Settings** is used in ZMK Studio.
Use Studio for experiments and this plugin for the canonical source keymap.

## Validate

```bash
python -m unittest discover -s tests -v
qmllint -I /usr/share/omarchy/shell Panel.qml BarWidget.qml
omarchy plugin validate .
```
