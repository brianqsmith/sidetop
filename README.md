# Sidetop

Sidetop tucks the contents of your macOS Desktop into a resizable panel at the right side of the screen. It is a native menu-bar app for macOS 13 Ventura and newer.

## Features

- Open from the menu-bar icon or hold the pointer against any display's right edge for one second.
- Groups Desktop items into Folders, Documents, Images, and Other.
- Open, rename, duplicate, copy/paste, move to Trash, reveal in Finder, and drag files in or out.
- Press Space to preview the selected item with Quick Look.
- Automatically hides when you click outside the panel.
- Appears on the display where it was activated and remains anchored to its top-right corner while resizing.
- Hides Finder's Desktop icons while running and restores the user's previous setting on quit.
- Launches at login by default, with a toggle in Settings.
- Universal Apple Silicon and Intel build.

## Install the unsigned build

1. Download `Sidetop-1.0.0-universal.dmg` from the latest GitHub Actions build or release.
2. Open the DMG and drag Sidetop into Applications.
3. Control-click Sidetop in Applications and choose **Open**, then confirm **Open**.

Because Sidetop is not signed or notarized, macOS may instead require you to allow it under **System Settings → Privacy & Security**. Only install builds you obtained from this repository.

## Usage

- Click the menu-bar icon to show or hide Sidetop.
- Right-click the menu-bar icon for Settings and Quit.
- Select an item and press Space for Quick Look, Return to open, Delete to move it to Trash, or use Command-C/Command-V/Command-D.
- Drag an item out to another app or folder. Drag files onto the panel to copy them to the Desktop.

Always quit using Sidetop's menu when possible so the original Finder Desktop-icon preference is restored immediately. If Sidetop is interrupted, it repairs the saved preference the next time it launches.

## Build locally

Xcode with the macOS SDK and command-line tools is required.

```sh
./scripts/package_dmg.sh
```

The unsigned universal DMG is written to `dist/`.

## Privacy

Sidetop runs locally. It does not collect analytics, make network requests, or upload files.
