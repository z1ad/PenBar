# PenBar

A floating pen toolbar and handwriting pad for Windows 11 tablets and 2-in-1s
(built on a Samsung Galaxy Book3 360). Written in AutoHotkey v2.

The bar and pad never take focus, so every button acts on the app you are using.

## Features

- **Handwriting pad**: write with the pen, pause, and the text is typed into
  the current app. Tap one of the suggestions to fix a misread word. Only the
  pen writes, so a palm or finger resting on the screen is ignored. Uses the
  handwriting recognizer built into Windows (works offline).
- **Word-level Undo / Redo** for text written on the pad. For other text it
  sends the app's own Ctrl+Z / Ctrl+Y (Ctrl+Shift+Z in apps that use it).
- **Buttons**: Write, Keyboard, Undo, Redo, Copy, Paste, Backspace, Tab,
  Enter, Last App, Task View, Screenshot, Dock.
- **On-states**: Write and Keyboard turn blue while the pad or the touch
  keyboard is open.
- **Docking**: right edge (vertical), top edge, bottom edge (above the
  taskbar), or floating. Drag the move handle; positions are remembered.
- **Auto-minimize**: minimizes when the keyboard is attached, expands in
  tablet mode.
- **Quieter Windows**: while PenBar runs, the Windows touch keyboard does not
  pop up by itself. Your own setting is restored when PenBar exits.
- **Start with Windows** (tray option).

## Setup

1. Install [AutoHotkey v2](https://www.autohotkey.com) (`winget install AutoHotkey.AutoHotkey`).
2. Double-click `PenBar.ahk`.

More options are in the tray menu (right-click the green **H** icon).
Settings and positions are saved in `PenBar.ini` next to the script.
