# Changelog

Each release on GitHub uses its section below as the release notes.

## 1.1.0

PenBar is now a full input toolbar: handwriting, a keyboard, and voice, with
one tap to switch between them.

### New

- **PenBar keyboard**, with:
  - **Swipe typing**, with no start-up delay.
  - **Word suggestions** as you type. Tap one to finish the word.
  - **Hold a key for accents** and extra symbols (é, ñ, ü, €, …).
  - **Shift shows symbols** on the number keys (Shift+2 = @). **Shift +
    Backspace clears** the text box.
  - A number row, a **symbols page laid out like a real keyboard**, and a
    second page with **F1–F12, arrows, Home/End, PgUp/PgDn, Esc and Del**.
  - **Ctrl, Alt and Win** keys that stay on for the next key, so Ctrl+S or
    Alt+F4 work.
  - An **emoji** button.
- **One-tap swap** between handwriting and the keyboard on the pad.
- **Dictate** button: Windows voice typing, or an instant offline mode (tray
  menu → Dictation).
- **Default** button opens the Windows touch keyboard.
- **Dock on the left edge** as well as right, top and bottom. Drag it away from
  an edge to float it, and back to an edge to dock it again.
- **Labels on or off** for a thinner bar.
- **Minimized bar** keeps Write, Keyboard and Dictate one tap away, as a row
  or a column to match how it's docked.
- **Resizable pad**: drag the corner, or tap it to shrink to the smallest
  size.
- **Dark theme** for the pad and keyboard.
- **Undo and Redo on the pad**, and Space / Backspace / Tab / Enter beside the
  writing area.
- **Tooltips** on every button.

### Improved

- **Palm rejection is automatic**: touches outside the writing area are
  ignored, and the pen wins over a finger. The toggle is gone.
- **Clear** only appears when there's ink or there are suggestions to clear.
- The minimize arrow points the way the bar opens.
- Faster, flicker-free drawing when typing, moving and docking the bar.

### Fixed

- The bar no longer draws only partly when it expands.
- The bar no longer pauses briefly after you drag or undock it.

## 1.0.0

First release: a floating pen toolbar and handwriting pad for Windows 11
tablets and 2-in-1s.

- **Handwriting pad**: write, pause, and the text is typed into your app. Tap
  a suggestion to fix a misread word. Works offline using Windows' own
  recognizer.
- **Palm Rejection** (toggle on the pad): only the pen writes.
- **Word-by-word Undo / Redo** for handwritten text.
- **Buttons**: Write, Keyboard, Undo, Redo, Copy, Paste, Backspace, Tab,
  Enter, Last App, Task View, Screenshot, Dock.
- **Docking** to the right, top or bottom edge, or floating.
- **Auto-minimize** when the keyboard is attached; expands in tablet mode.
- **Start with Windows** (tray option).
