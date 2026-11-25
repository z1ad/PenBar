<img src="assets/icon.png" width="72" align="right" alt="PenBar icon">

# PenBar

A free floating pen toolbar and handwriting pad for Windows 11 tablets and
2-in-1 laptops. It was built on a Samsung Galaxy Book3 360 and works on any
Windows pen device. Written in [AutoHotkey v2](https://www.autohotkey.com).

The bar and pad never take focus, so every button acts on the app you are
using.

**[Download PenBar.exe](https://github.com/z1ad/PenBar/releases/latest)** ·
`winget install z1ad.PenBar` · [Report a problem](https://github.com/z1ad/PenBar/issues)

## Why PenBar?

Windows 11 has pen support, but using a 2-in-1 with only the pen is still
awkward:

- **Undo is all-or-nothing.** Text from Windows' handwriting panel goes in as
  one block, so Ctrl+Z often wipes out everything you wrote. PenBar undoes
  handwriting **one word at a time**, and Redo puts the word back.
- **Your palm gets in the way.** Resting your hand on the screen can stop the
  pen from writing. PenBar's pad listens to the pen only.
- **No undo, copy, paste or tab without a keyboard.** PenBar puts them one tap
  away, plus Last App, Task View and Screenshot.
- **Switching between keyboard and handwriting takes several taps.** PenBar
  has one button for each, and they show whether they're open.
- **It stays out of the way.** It docks to any screen edge, minimizes itself
  when the keyboard is attached, and never steals focus from your app.

It's free, open source (MIT), runs offline, and needs no account.

## Features

- **Handwriting pad**: write with the pen, pause, and the text is typed into
  the current app. Up to 3 suggestions appear at the top; tap one to fix a
  misread word. Uses the handwriting recognizer built into Windows and works
  offline.
- **Palm Rejection** (on the pad, on by default): only the pen writes, so a
  palm or finger resting on the screen is ignored. Turn it off to write with
  a finger.
- **Word-by-word Undo and Redo** for text written on the pad. For other text,
  Undo and Redo send the app's own shortcuts (Ctrl+Z, and Ctrl+Y or
  Ctrl+Shift+Z depending on the app).
- **Buttons**, in groups: Write, Keyboard | Undo, Redo | Copy, Paste |
  Backspace, Tab, Enter | Last App, Task View, Screenshot | Dock.
- **On/off states**: Write and Keyboard turn blue while the pad or the touch
  keyboard is open.
- **Docking**: right edge (vertical), top edge, bottom edge (above the
  taskbar), or floating. Drag the move handle to reposition; positions are
  remembered.
- **Auto-minimize**: the bar shrinks to a small tab when the keyboard is
  attached, and expands when you fold the screen back into tablet mode.
- **Start with Windows** (on by default, can be turned off).

## Install

### Option 1: the ready-to-run app (easiest)

No other software needed.

- **winget** (built into Windows 11). Open Terminal and run:

  ```powershell
  winget install z1ad.PenBar
  ```

  Then start it by typing `PenBar` in Terminal or the Run box (Win+R).

- **Or download** `PenBar.exe` from the
  [latest release](https://github.com/z1ad/PenBar/releases/latest), put it in
  a permanent folder, and double-click it.

The app isn't code-signed yet, so Windows may show **"Windows protected your
PC"** the first time. Choose **More info → Run anyway**. The app's settings
are saved in `%APPDATA%\PenBar\PenBar.ini`.

### Option 2: run the script with AutoHotkey

Use this if you want to read or change the code.

1. **Install AutoHotkey v2.** Open PowerShell or Terminal and run:

   ```powershell
   winget install --id AutoHotkey.AutoHotkey --exact
   ```

   Or download it from [autohotkey.com](https://www.autohotkey.com).

2. **Get PenBar.** Either download the repository as a ZIP from GitHub
   (**Code → Download ZIP**) and unzip it, or clone it:

   ```powershell
   git clone https://github.com/z1ad/PenBar.git
   ```

   Put the folder somewhere permanent, such as `Documents\PenBar`. The
   start-with-Windows shortcut points at wherever the script lives.

## Run the script

- Double-click `PenBar.ahk`, or run it from PowerShell:

  ```powershell
  & "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" "$HOME\Documents\PenBar\PenBar.ahk"
  ```

  If AutoHotkey was installed for all users, the program is in
  `C:\Program Files\AutoHotkey\v2\` instead.

- PenBar adds itself to Windows startup the first time it runs. To stop that,
  untick **Start with Windows** in the tray menu.
- **Quit**: right-click the green **H** icon in the system tray and choose
  **Exit**.

## Using it

| Button | What it does |
|---|---|
| Move handle | Drag to move the bar |
| Minimize / expand | Shrinks the bar to its top row, or opens it again |
| Write | Opens or closes the handwriting pad |
| Keyboard | Opens or closes the Windows touch keyboard |
| Undo / Redo | Word-by-word for pad text, the app's own undo/redo otherwise |
| Copy / Paste | Ctrl+C / Ctrl+V |
| Backspace, Tab, Enter | The same keys |
| Last App | Switches to the previous app (Alt+Tab) |
| Task View | Shows all open windows |
| Screenshot | Presses Print Screen (opens the Snipping Tool on Windows 11) |
| Dock | Dock right, top, bottom, or float |

**Handwriting pad:** write, then pause. The text is typed after the pause.
Use **Space** to add a space, **Clear Ink** to discard what you wrote,
**Palm Rejection** to allow or block finger writing, and **×** to close the
pad.

**Tray menu** (right-click the green **H** icon):

- Dock position
- Add a space after each word
- What Undo does outside the pad
- Minimize the bar when the keyboard is attached
- Start with Windows
- How long a pause types the text (0.6 to 2 seconds)
- Reset the bar and pad positions

Settings and positions are saved in `PenBar.ini` next to the script (or in
`%APPDATA%\PenBar` for the app).

## Optional Windows settings

PenBar doesn't change any Windows settings. If Windows' own pen and keyboard
pop-ups get in the way, you can switch these off yourself:

| What it stops | Where |
|---|---|
| Touch keyboard popping up when you tap a text field | Settings → Time & language → Typing → Touch keyboard → **Show the touch keyboard** → **Never**. PenBar's Keyboard button still opens it. |
| Windows' handwriting box appearing when you write in a text field | Settings → Bluetooth & devices → Pen & Windows Ink → turn off **Shell handwriting** |
| Pen menu opening when you take the pen out | Settings → Bluetooth & devices → Pen & Windows Ink → turn off the option that opens the pen menu when the pen is removed |
| Pen menu, touch keyboard and virtual touchpad icons on the taskbar | Settings → Personalization → Taskbar → System tray icons → turn off **Pen menu**, **Touch keyboard** and **Virtual touchpad** |
| Taskbar hiding app icons in tablet mode | Settings → Personalization → Taskbar → Taskbar behaviors → untick **Optimize taskbar for touch interactions when this device is used as a tablet** |

Setting names can differ slightly between Windows 11 versions.

## Uninstall

1. In the tray menu, untick **Start with Windows**, then choose **Exit**.
2. Remove PenBar:
   - installed with winget: `winget uninstall z1ad.PenBar`
   - downloaded or script version: delete the PenBar folder
3. Optionally delete the settings folder `%APPDATA%\PenBar`, and uninstall
   AutoHotkey if you installed it for the script:

   ```powershell
   winget uninstall --id AutoHotkey.AutoHotkey --exact
   ```

## Building the app

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" /in PenBar.ahk /out dist\PenBar.exe /base "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
```

The version, icon and file details come from the `;@Ahk2Exe-` lines at the
top of `PenBar.ahk`.

## License

PenBar is free and open source under the [MIT License](LICENSE).
