; PenBar - a floating pen toolbar, handwriting pad and touch keyboard for
; Windows tablets and 2-in-1s.
; Needs AutoHotkey v2 (free, open source): https://www.autohotkey.com
;
; The bar and pad never take focus, so everything goes to the app you are in.
;   Write      opens the handwriting pad. Write, pause, and the words are typed
;              into your app. Tap a suggestion at the top to fix a misread word.
;   Keyboard   opens PenBar's keyboard: swipe typing, word suggestions, hold a
;              key for accents, symbols and F keys. The pad's swap button flips
;              between handwriting and keyboard.
;   Dictate    starts Windows voice typing (or offline dictation, in the tray menu).
;   Undo       removes the last word written on the pad (not the whole text).
;              For other text it sends the app's normal Ctrl+Z.
;   Dock       dock the bar on any screen edge or float it. The arrow minimizes it.
;   Drag the move handle to move the bar or pad. Positions are remembered.
;   More options: right-click the green "H" tray icon.

#Requires AutoHotkey v2.0
#SingleInstance Force

;@Ahk2Exe-SetName PenBar
;@Ahk2Exe-SetProductName PenBar
;@Ahk2Exe-SetDescription PenBar - pen toolbar with handwriting pad and keyboard
;@Ahk2Exe-SetVersion 1.1.0
;@Ahk2Exe-SetCopyright Copyright (c) 2026 z1ad - MIT License
;@Ahk2Exe-SetMainIcon PenBar.ico

PENBAR_VERSION := "1.1.0"
PENBAR_URL     := "https://github.com/z1ad/PenBar"
A_IconTip := "PenBar " PENBAR_VERSION
if !A_IsCompiled && FileExist(A_ScriptDir "\PenBar.ico")
    TraySetIcon(A_ScriptDir "\PenBar.ico")
InstallKeybdHook()
CoordMode("Caret", "Screen")
CoordMode("ToolTip", "Screen")
SetWinDelay(-1)            ; no built-in 100 ms pause after moving / resizing windows
SetControlDelay(-1)

; ---- settings -------------------------------------------------------------
; Script: settings next to PenBar.ahk. Compiled .exe (e.g. installed by
; winget into a read-only or versioned folder): settings in %APPDATA%\PenBar.
if A_IsCompiled {
    DirCreate(A_AppData "\PenBar")
    iniFile := A_AppData "\PenBar\PenBar.ini"
} else {
    iniFile := A_ScriptDir "\PenBar.ini"
}
mode      := IniRead(iniFile, "Bar", "mode", "float")      ; "float", "left", "right", "top" or "bottom"
barX      := IniRead(iniFile, "Bar", "x", "")
barY      := IniRead(iniFile, "Bar", "y", "")
dockY     := IniRead(iniFile, "Bar", "dockY", "")
dockX     := IniRead(iniFile, "Bar", "dockX", "")
padX      := IniRead(iniFile, "Pad", "x", "")
padY      := IniRead(iniFile, "Pad", "y", "")
autoSpace := Integer(IniRead(iniFile, "Pad", "autoSpace", 1))
delayMs   := Integer(IniRead(iniFile, "Pad", "delay", 1000))
undoWord  := Integer(IniRead(iniFile, "Undo", "fallbackDeleteWord", 0))
DELAYS := Map(600, "Fast (0.6 s)", 1000, "Normal (1 s)", 1500, "Slow (1.5 s)", 2000, "Very slow (2 s)")

PAD_H := 230                    ; writing area height (logical pixels)
BTN_H := 44, ICON_W := 30       ; button height, icon column width
BG := "2B2B2B", BTN := "3C3C3C", BTN_HIT := "6A6A6A"
INK_COLOR := 0xFFFFFF           ; BGR: white ink on the dark pad
PAD_BG := "202020"

; Segoe Fluent Icons glyphs
IC := Map("move", 0xE7C2, "up", 0xE70E, "down", 0xE70D, "left", 0xE76B, "right", 0xE76C, "write", 0xE76D,
          "undo", 0xE7A7, "redo", 0xE7A6, "tab", 0xE7FD, "copy", 0xE8C8,
          "paste", 0xE77F, "back", 0xE750, "enter", 0xE751, "switch", 0xE8AB,
          "tasks", 0xE7C4, "keyboard", 0xE765, "dock", 0xE90D, "space", 0xE75D,
          "clear", 0xE74D, "close", 0xE894, "screenshot", 0xE722, "palm", 0xEDA4, "winkbd", 0xE8A9, "mic", 0xE720, "labels", 0xE8D2, "resize", 0xE740)
ACTIVE := "0F6CBD"              ; background of a button that is switched on

dictMode   := IniRead(iniFile, "Dictation", "mode", "windows")   ; "windows" (Win+H) or "offline" (instant, no overlay)
DICT_FLAG  := A_Temp "\PenBar.listening"
barLabels  := Integer(IniRead(iniFile, "Bar", "labels", 1))
autoMin    := Integer(IniRead(iniFile, "Bar", "autoMinimize", 1))
floatVertical := Integer(IniRead(iniFile, "Bar", "floatVertical", 0))   ; float keeps the last dock shape
lastDock   := IniRead(iniFile, "Bar", "lastDock", "right")
startup    := Integer(IniRead(iniFile, "General", "startWithWindows", 1))
STARTUP_LNK := A_Startup "\PenBar.lnk"

; Apps that use Ctrl+Shift+Z for redo instead of Ctrl+Y.
REDO_SHIFT_Z := Map("krita.exe", 1, "photoshop.exe", 1, "illustrator.exe", 1,
                    "figma.exe", 1, "inkscape.exe", 1, "blender.exe", 1, "gimp-2.10.exe", 1)

; Toolbar buttons (defined before the bar is first built)
; [icon, label, short label, tooltip, starts a new group]
BAR_ITEMS := [  ; an icon starting with @ is drawn by PenBar (no font has it)
    ["write",      "Write",      "Write",  "Handwriting pad",                    1],
    ["keyboard",   "Keyboard",   "Keys",   "Keyboard",                           0],
    ["mic",        "Dictate",    "Voice",  "Dictate (tap to start / stop)",      0],
    ["@win",       "Default",    "Win",    "Windows touch keyboard",             0],
    ["undo",       "Undo",       "Undo",   "Undo",                               1],
    ["redo",       "Redo",       "Redo",   "Redo",                               0],
    ["copy",       "Copy",       "Copy",   "Copy",                               1],
    ["paste",      "Paste",      "Paste",  "Paste",                              0],
    ["back",       "Backspace",  "Back",   "Backspace",                          1],
    ["tab",        "Tab",        "Tab",    "Tab",                                0],
    ["enter",      "Enter",      "Enter",  "Enter",                              0],
    ["switch",     "Last App",   "Last",   "Switch to the last app (Alt+Tab)",   1],
    ["tasks",      "Task View",  "Tasks",  "Task View (all windows)",            0],
    ["screenshot", "Screenshot", "Snip",   "Screenshot (Print Screen)",          0]]


; ---- state ------------------------------------------------------------------
bar := 0, pad := 0, padGrip := 0, padVisible := false
collapsed := false, extra := [], altBtns := [], curAlts := []
lastWin := 0
hist := [], redoStack := []            ; text typed by PenBar, for word-level undo
histWin := 0, histTick := 0, histCaret := ""
; ink
strokes := [], curStroke := 0, penId := 0, mouseInk := false
inkDC := 0, inkPen := 0, writeRect := {l: 0, t: 0, r: 0, b: 0}, recognizing := false

writeBtn := 0, kbBtn := 0, winBtn := 0, dockBtn := 0, labelsBtn := 0, collapseBtn := 0,
barAll := [], barExpPos := Map(), barMinPos := Map(), barExpSize := [0, 0], barMinSize := [0, 0],
TIPS := Map(), tipHwnd := 0, padCwL := 0, resizeGhost := 0, barGrip := 0, barLabel := 0,
miniPen := 0, miniKbd := 0, miniMic := 0, winKbOn := false,
vAnchorBottom := false, hAnchorRight := false, palmBtn := 0, inputPane := 0, penIsTouch := false
padUndoBtn := 0, padRedoBtn := 0, dictPid := 0, kbShownDown := 0, resizeBtn := 0, padChL := 0
; pad (handwriting / PenBar keyboard)
padMode := "write", swapBtn := 0, padMicBtn := 0, spaceBtn := 0, backBtn := 0, tabBtn := 0, enterBtn := 0,
clearBtn := 0, closeBtn := 0, PAD_BTN_H := 40,
padResizer := 0, padTopH := 0, padMinW := 0, resizing := false, resizeStart := 0
padW := IniRead(iniFile, "Pad", "w", ""), padH := IniRead(iniFile, "Pad", "h", "")
kbPic := 0, kbBmp := 0, kbDC := 0, kbW := 0, kbH := 0, kbOrigin := [0, 0], kbKeys := [], kbLayoutKey := ""
kbLayer := "abc", kbShift := 0, kbLastShift := 0, kbDown := 0, kbPtr := 0, kbMouse := false
kbPath := [], kbSwiping := false, kbWord := "", kbQueue := [], altMode := "ink"
kbMods := Map("ctrl", false, "alt", false, "win", false), kbPopup := 0, kbCaps := false
kbCache := Map(), kbCacheSize := ""
kbCenters := Map(), kbTemplates := Map()
WORDS := LoadWords()

UpdateStartup()
BuildBar()
BuildTrayMenu()
CheckPosture()
SetTimer(CheckPosture, 1000)
SetTimer(TrackActive, 200)
SetTimer(UpdateKeyboardState, 400)
OnMessage(0x232, OnExitMove)           ; WM_EXITSIZEMOVE: a drag finished
OnMessage(0x245, OnPointer)            ; WM_POINTERUPDATE
OnMessage(0x246, OnPointer)            ; WM_POINTERDOWN
OnMessage(0x247, OnPointer)            ; WM_POINTERUP
OnMessage(0x24C, OnPointerLost)        ; WM_POINTERCAPTURECHANGED
OnMessage(0x24B, OnPointerActivate)    ; WM_POINTERACTIVATE
OnMessage(0x200, OnMouse)              ; WM_MOUSEMOVE   (mouse can write too)
OnMessage(0x201, OnMouse)              ; WM_LBUTTONDOWN
OnMessage(0x202, OnMouse)              ; WM_LBUTTONUP
OnMessage(0x203, OnMouse)              ; WM_LBUTTONDBLCLK (fast second tap)
OnExit(SaveAll)
OnExit((*) => StopDictation(true))

; Start with Windows: a shortcut in the Startup folder. Rewritten on every
; start so it always points at wherever PenBar.ahk lives now.
UpdateStartup() {
    try {
        if startup && A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, STARTUP_LNK, A_ScriptDir, , "PenBar pen toolbar")
        else if startup
            FileCreateShortcut(A_AhkPath, STARTUP_LNK, A_ScriptDir, '"' A_ScriptFullPath '"', "PenBar pen toolbar")
        else if FileExist(STARTUP_LNK)
            FileDelete(STARTUP_LNK)
    }
}

ToggleStartup(*) {
    global startup := !startup
    IniWrite(startup, iniFile, "General", "startWithWindows")
    UpdateStartup(), UpdateTrayChecks()
}

ToggleAutoMin(*) {
    global autoMin := !autoMin
    IniWrite(autoMin, iniFile, "Bar", "autoMinimize"), UpdateTrayChecks()
}


; ============================================================================
; Buttons: icon on the left, Title Case label
; ============================================================================

SetIconFont(g, size := 12) {
    g.SetFont("s" size " cWhite norm", "Segoe MDL2 Assets")
    g.SetFont("s" size " cWhite norm", "Segoe Fluent Icons")
}

; opt places the first control, e.g. "x+4 yp" or "xm y+4".
; labelW = 0 makes an icon-only button; icon = "" makes a label-only button.
MakeButton(g, icon, label, opt, labelW, handler) {
    b := {ctrls: [], icon: 0, label: 0, active: false, lw: labelW, h: BTN_H}
    if SubStr(icon, 1, 1) = "@" {                     ; drawn by PenBar
        b.draw := SubStr(icon, 2)
        b.icon := g.AddPicture(opt " w" ICON_W " h" BTN_H " +0xE")
        b.ctrls.Push(b.icon)
        SetDrawn(b, BTN)
        opt := "x+0 yp"
    } else if icon != "" {
        SetIconFont(g)
        b.icon := g.AddText(opt " w" ICON_W " h" BTN_H " Center +0x200 Background" BTN, Chr(IC[icon]))
        b.ctrls.Push(b.icon)
        opt := "x+0 yp"
    }
    if labelW {
        g.SetFont("s10 cWhite norm", "Segoe UI")
        b.label := g.AddText(opt " w" labelW " h" BTN_H " +0x200 Background" BTN (icon = "" ? " Center" : ""), label)
        b.ctrls.Push(b.label)
    }
    fn := (*) => (Flash(b), handler(b))
    for c in b.ctrls {
        c.OnEvent("Click", fn)
        c.OnEvent("DoubleClick", fn)      ; quick repeated taps count too
    }
    return b
}

ShowButton(b, show) {
    for c in b.ctrls
        c.Visible := show
}

Flash(b) {
    for c in b.ctrls
        try PaintCtrl(b, c, BTN_HIT)
    SetTimer(() => FlashOff(b), -150)
}

FlashOff(b) {
    for c in b.ctrls
        try PaintCtrl(b, c, b.active ? ACTIVE : BTN)     ; the bar may have been rebuilt
}

PaintCtrl(b, c, color) {
    if b.HasProp("draw") && c = b.icon
        SetDrawn(b, color)
    else
        c.Opt("Background" color), c.Redraw()
}

; Icons no font has, drawn by PenBar: the Windows logo and "dock to <side>".
DrawnIcon(kind, bgHex, hL := BTN_H) {
    k := A_ScreenDPI / 96
    w := Round(ICON_W * k), h := Round(hL * k)
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", sdc, "int", w, "int", h, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    dc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    ob := DllCall("SelectObject", "ptr", dc, "ptr", hbm, "ptr")
    rgb := Integer("0x" bgHex)
    bg := DllCall("CreateSolidBrush", "uint", ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16), "ptr")
    wb := DllCall("CreateSolidBrush", "uint", 0xFFFFFF, "ptr")
    rc := Buffer(16)
    Fill(x1, y1, x2, y2, br) => (NumPut("int", x1, "int", y1, "int", x2, "int", y2, rc), DllCall("FillRect", "ptr", dc, "ptr", rc, "ptr", br))
    Fill(0, 0, w, h, bg)
    cx := w // 2, cy := h // 2
    if kind = "win" {                                ; four outlined squares, like the other line icons
        sz := Round(Min(w, h) * 0.5), half := sz // 2, gp := Max(2, Round(1.6 * k)), t := Max(1, Round(1.2 * k))
        x0 := cx - half, y0 := cy - half
        for q in [[0, 0], [1, 0], [0, 1], [1, 1]] {
            qx := x0 + q[1] * (half + gp // 2), qy := y0 + q[2] * (half + gp // 2), qs := half - gp // 2
            Fill(qx, qy, qx + qs, qy + t, wb), Fill(qx, qy + qs - t, qx + qs, qy + qs, wb)
            Fill(qx, qy, qx + t, qy + qs, wb), Fill(qx + qs - t, qy, qx + qs, qy + qs, wb)
        }
    } else if kind = "resize" {                      ; the resize glyph, mirrored: arrows top-left to bottom-right
        tdc := DllCall("CreateCompatibleDC", "ptr", dc, "ptr")
        tbm := DllCall("CreateCompatibleBitmap", "ptr", dc, "int", w, "int", h, "ptr")
        otb := DllCall("SelectObject", "ptr", tdc, "ptr", tbm, "ptr")
        NumPut("int", 0, "int", 0, "int", w, "int", h, rc), DllCall("FillRect", "ptr", tdc, "ptr", rc, "ptr", bg)
        hf := 0
        for face in ["Segoe Fluent Icons", "Segoe MDL2 Assets"] {
            hf := DllCall("CreateFont", "int", -Round(16 * k), "int", 0, "int", 0, "int", 0, "int", 400, "uint", 0, "uint", 0,
                "uint", 0, "uint", 1, "uint", 0, "uint", 0, "uint", 4, "uint", 0, "str", face, "ptr")
            if hf
                break
        }
        of := DllCall("SelectObject", "ptr", tdc, "ptr", hf, "ptr")
        DllCall("SetBkMode", "ptr", tdc, "int", 1), DllCall("SetTextColor", "ptr", tdc, "uint", 0xFFFFFF)
        DllCall("DrawText", "ptr", tdc, "str", Chr(IC["resize"]), "int", -1, "ptr", rc, "uint", 0x25)   ; centre, vcentre, single line
        DllCall("StretchBlt", "ptr", dc, "int", w - 1, "int", 0, "int", -w, "int", h,
            "ptr", tdc, "int", 0, "int", 0, "int", w, "int", h, "uint", 0xCC0020)                      ; mirrored left-right
        DllCall("SelectObject", "ptr", tdc, "ptr", of), DllCall("DeleteObject", "ptr", hf)
        DllCall("SelectObject", "ptr", tdc, "ptr", otb), DllCall("DeleteObject", "ptr", tbm), DllCall("DeleteDC", "ptr", tdc)
    } else {                                         ; dock-<side>: a window outline with a solid band on that side
        bw := Round(18 * k), bh := Round(14 * k), t := Max(1, Round(1.3 * k)), band := Round(5 * k)
        x0 := cx - bw // 2, y0 := cy - bh // 2, x1 := x0 + bw, y1 := y0 + bh
        Fill(x0, y0, x1, y0 + t, wb), Fill(x0, y1 - t, x1, y1, wb), Fill(x0, y0, x0 + t, y1, wb), Fill(x1 - t, y0, x1, y1, wb)
        switch kind {
            case "dock-left":   Fill(x0, y0, x0 + band, y1, wb)
            case "dock-right":  Fill(x1 - band, y0, x1, y1, wb)
            case "dock-top":    Fill(x0, y0, x1, y0 + band, wb)
            case "dock-bottom": Fill(x0, y1 - band, x1, y1, wb)
        }
    }
    DllCall("DeleteObject", "ptr", bg), DllCall("DeleteObject", "ptr", wb)
    DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("DeleteDC", "ptr", dc)
    return hbm
}

SetDrawn(b, color) {
    old := SendMessage(0x172, 0, DrawnIcon(b.draw, color, b.h), b.icon)    ; STM_SETIMAGE
    if old
        DllCall("DeleteObject", "ptr", old)
}

; Show a toggle button as on (blue) or off.
SetActive(b, on) {
    if !b || b.active = !!on
        return
    b.active := !!on
    FlashOff(b)
}

UpdateKeyboardState() {
    global inputPane
    on := false
    try {
        if !inputPane
            inputPane := ComObject("{D5120AA3-46BA-44C5-822D-CA8092C1FC72}", "{5752238B-24F0-495A-82F1-2FD593056796}")
        rc := Buffer(16, 0)
        ComCall(6, inputPane, "ptr", rc)              ; IFrameworkInputPane::Location
        on := NumGet(rc, 8, "int") > NumGet(rc, 0, "int")
    } catch {
        inputPane := 0
    }
    global winKbOn := on
    UpdateBarStates()
}

; Write / Keyboard are on while the pad shows handwriting / PenBar's keyboard.
; Default is on while the Windows touch keyboard is open. They are independent.
UpdateBarStates() {
    w := padVisible && padMode = "write"
    k := padVisible && padMode = "keys"
    SetActive(writeBtn, w), SetActive(miniPen, w)
    SetActive(kbBtn, k), SetActive(miniKbd, k)
    SetActive(winBtn, winKbOn)
    d := DictationOn()
    for b in [extra.Length >= 3 ? extra[3] : 0, miniMic, padMicBtn]
        SetActive(b, d)
}

; ============================================================================
; Bar
; ============================================================================

MeasureText(text) {
    static g := 0, cache := Map()
    if cache.Has(text)
        return cache[text]
    if !g
        g := Gui(), g.SetFont("s10 norm", "Segoe UI")
    g.AddText("xm ym", text).GetPos(, , &w)
    return cache[text] := w
}

; The bar is laid out by hand so it can be: horizontal or vertical, with labels
; (full or short words, whatever fits) or as a thin strip of icons.
BuildBar() {
    global bar, extra, writeBtn, kbBtn, winBtn, dockBtn, labelsBtn, collapseBtn, barGrip, miniPen, miniKbd, miniMic
    global BTN_H, barAll, barExpPos, barMinPos, barExpSize, barMinSize
    oldBar := bar
    extra := [], barAll := [], barExpPos := Map(), barMinPos := Map()
    vertical := IsVertical()
    BTN_H := vertical ? (barLabels ? 36 : ICON_W) : 40     ; thin vertical: square buttons so it fits
    gap := 3, grp := 10, m := 4, step := ICON_W + gap      ; (AutoHotkey names ignore case: no g / G pair)
    handlers := [WriteButton, KeyboardButton, DictateButton, DefaultKbButton, SmartUndo, SmartRedo,
        KeysFn("^c"), KeysFn("^v"), BackspaceKey, KeysFn("{Tab}"), EnterKey,
        KeysFn("!{Tab}"), KeysFn("#{Tab}"), KeysFn("{PrintScreen}")]

    ; +E0x08000000 = WS_EX_NOACTIVATE: tapping the bar does not steal focus.
    ; +E0x02000000 = WS_EX_COMPOSITED: double-buffered painting, no flicker when dragged.
    bar := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x02000000", "PenBar")
    bar.BackColor := BG
    bar.MarginX := 0, bar.MarginY := 0

    ; Labels: full words. If they don't all fit across the screen, each label
    ; is shortened with "…" so the bar still fits.
    labW := []
    for it in BAR_ITEMS
        labW.Push(barLabels ? MeasureText(it[2]) + 6 : 0)
    if barLabels && !vertical {
        MonitorGetWorkArea(, &L, &T, &R, &B)
        avail := (R - L) * 96 / A_ScreenDPI - 16
        fixed := 2 * m + 4 * step + grp - gap, lsum := 0
        for i, it in BAR_ITEMS
            fixed += ICON_W + gap + (i > 1 && it[5] ? grp - gap : 0), lsum += labW[i]
        if fixed + lsum > avail {
            f := Max(0, (avail - fixed) / lsum)
            for i, v in labW
                labW[i] := Max(28, Floor(v * f))
        }
    }
    VW := ICON_W
    if vertical && barLabels {
        for v in labW
            VW := Max(VW, ICON_W + v)
        VW := Max(VW, 5 * ICON_W + 4 * gap)              ; as wide as the minimized row
    }

    ; controls (positions are set below)
    SetIconFont(bar)
    barGrip := bar.AddText("x0 y0 w" ICON_W " h" BTN_H " Center +0x200 cAAAAAA", Chr(IC["move"]))
    barGrip.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , bar))
    labelsBtn := MakeButton(bar, "labels", "", "x0 y0", 0, ToggleBarLabels)
    dockBtn := MakeButton(bar, "@dock-right", "", "x0 y0", 0, DockCycle)
    collapseBtn := MakeButton(bar, "up", "", "x0 y0", 0, (*) => SetCollapsed(!collapsed))
    for i, it in BAR_ITEMS {
        b := MakeButton(bar, it[1], barLabels ? it[2] : "", "x0 y0", labW[i], handlers[i])
        if b.label
            b.label.Opt("+0x4000")                        ; SS_ENDELLIPSIS: "…" when shortened
        extra.Push(b)
    }
    writeBtn := extra[1], kbBtn := extra[2], winBtn := extra[4]
    miniPen := MakeButton(bar, "write", "", "x0 y0", 0, WriteButton)
    miniKbd := MakeButton(bar, "keyboard", "", "x0 y0", 0, KeyboardButton)
    miniMic := MakeButton(bar, "mic", "", "x0 y0", 0, DictateButton)

    ; tooltips
    Tip(barGrip, "Move (drag)"), Tip(labelsBtn, "Show / hide labels"), Tip(collapseBtn, "Minimize / expand")
    for i, it in BAR_ITEMS
        Tip(extra[i], it[4])
    Tip(miniPen, BAR_ITEMS[1][4]), Tip(miniKbd, BAR_ITEMS[2][4]), Tip(miniMic, BAR_ITEMS[3][4])

    top := [barGrip, labelsBtn.icon, dockBtn.icon, collapseBtn.icon]
    minis := [barGrip, miniPen.icon, miniKbd.icon, miniMic.icon, collapseBtn.icon]
    barAll := [barGrip, labelsBtn.icon, dockBtn.icon, collapseBtn.icon, miniPen.icon, miniKbd.icon, miniMic.icon]
    for b in extra {
        barAll.Push(b.icon)
        if b.label
            barAll.Push(b.label)
    }

    ; expanded layout
    if !vertical {                                   ; one row
        x := m                                       ; move first, labels/dock/expand at the end
        barExpPos[barGrip] := [x, m, ICON_W], x += step
        for i, it in BAR_ITEMS {
            if i > 1 && it[5]
                x += grp - gap
            b := extra[i]
            barExpPos[b.icon] := [x, m, ICON_W], x += ICON_W
            if b.label
                barExpPos[b.label] := [x, m, b.lw], x += b.lw
            x += gap
        }
        x += grp - gap
        for c in [labelsBtn.icon, dockBtn.icon, collapseBtn.icon]
            barExpPos[c] := [x, m, ICON_W], x += step
        barExpSize := [x - gap + m, BTN_H + 2 * m]
    } else {                                         ; one column
        if barLabels {                               ; top controls side by side
            x := m
            for c in top
                barExpPos[c] := [x, m, ICON_W], x += step
            y := m + BTN_H + grp
        } else {                                     ; thin: move on top, labels/dock/minimize at the bottom
            y := m
            barExpPos[barGrip] := [m, y, ICON_W]
            y += BTN_H + gap
        }
        for i, it in BAR_ITEMS {
            if i > 1 && it[5]
                y += grp - gap
            b := extra[i]
            barExpPos[b.icon] := [m, y, ICON_W]
            if b.label
                barExpPos[b.label] := [m + ICON_W, y, VW - ICON_W]
            y += BTN_H + gap
        }
        if !barLabels {
            y += grp - gap
            for c in [labelsBtn.icon, dockBtn.icon, collapseBtn.icon]
                barExpPos[c] := [m, y, ICON_W], y += BTN_H + gap
        }
        barExpSize := [VW + 2 * m, y - gap + m]
    }
    ; minimized layout: [move][Write][Keyboard][Dictate][expand], a column when vertical
    if vertical {
        y := m
        for c in minis
            barMinPos[c] := [m, y, ICON_W], y += BTN_H + gap
        barMinSize := [ICON_W + 2 * m, y - gap + m]
    } else {
        x := m
        for c in minis
            barMinPos[c] := [x, m, ICON_W], x += step
        barMinSize := [x - gap + m, BTN_H + 2 * m]
    }

    ; Lay out (minimized or not) while still hidden, then show once.
    ApplyBarLayout()
    bar.Show("Hide " BarSizeOpt())
    BarTarget(&x, &y)
    bar.Show("NA x" x " y" y)
    UpdateArrow()
    UpdateBarStates()
    RedrawBar()
    if oldBar
        oldBar.Destroy()
}

BarSizeOpt() => collapsed ? "w" barMinSize[1] " h" barMinSize[2] : "w" barExpSize[1] " h" barExpSize[2]

ToggleBarLabels(*) {
    global barLabels := !barLabels
    IniWrite(barLabels, iniFile, "Bar", "labels")
    BuildBar()
}

; ---- tooltips (shown when a pen or mouse hovers over a button) ------------------

Tip(ctrlOrBtn, text) {
    if IsObject(ctrlOrBtn) && ctrlOrBtn.HasProp("ctrls") {
        for c in ctrlOrBtn.ctrls
            TIPS[c.Hwnd] := text
    } else {
        TIPS[ctrlOrBtn.Hwnd] := text
    }
}

TipHover(hwnd) {
    global tipHwnd
    if hwnd = tipHwnd
        return
    tipHwnd := hwnd
    ToolTip()
    SetTimer(TipShow, -600)
}

TipShow() {
    MouseGetPos(, , , &c, 2)
    if c && c = tipHwnd && TIPS.Has(c) {
        ToolTip(TIPS[c])
        SetTimer(TipWatch, 200)
    }
}

TipWatch() {
    global tipHwnd
    MouseGetPos(, , , &c, 2)
    if c != tipHwnd {
        ToolTip(), tipHwnd := 0
        SetTimer(TipWatch, 0)
    }
}

; Where the bar belongs for the current mode and size.
BarTarget(&x, &y) {
    WinGetPos(, , &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    if mode = "right" || mode = "left" {
        x := (mode = "right") ? R - w : L
        y := (dockY = "") ? T + (B - T - h) // 2 : Max(T, Min(Integer(dockY), B - h))
    } else if mode = "top" || mode = "bottom" {
        x := (dockX = "") ? L + (R - L - w) // 2 : Max(L, Min(Integer(dockX), R - w))
        y := (mode = "top") ? T : B - h
    } else {
        x := (barX = "") ? L + (R - L - w) // 2 : Max(L, Min(Integer(barX), R - w))
        y := (barY = "") ? T + 40 : Max(T, Min(Integer(barY), B - h))
    }
}

; Dock button: a floating bar docks to the nearest edge; a docked bar moves
; on to the next edge (right, bottom, left, top), so all four are one tap away.
DockTarget() {
    WinGetPos(&x, &y, &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    if mode = "float" {
        cx := x + w / 2, cy := y + h / 2
        d := Map("left", cx - L, "right", R - cx, "top", cy - T, "bottom", B - cy)
        edge := "right"
        for e, v in d
            if v < d[edge]
                edge := e
        return edge
    }
    order := ["right", "bottom", "left", "top"]
    for i, e in order
        if e = mode
            return order[Mod(i, 4) + 1]
    return "right"
}

DockCycle(*) {
    global dockX, dockY
    WinGetPos(&x, &y, , , bar)
    edge := DockTarget()
    dockY := y, dockX := x
    SetMode(edge)
}

; The dock button shows the edge it will dock to: arrow into that edge.
UpdateDockIcon() {
    if !dockBtn
        return
    e := DockTarget()
    if dockBtn.draw != "dock-" e {
        dockBtn.draw := "dock-" e
        try SetDrawn(dockBtn, dockBtn.active ? ACTIVE : BTN)
    }
    Tip(dockBtn, "Dock to the " e " edge")
}

KeysFn(keys) {
    return (*) => (EnsureTarget(), ForgetHist(), Send(keys))
}

; Vertical bar: docked left/right, or floating after being docked there.
IsVertical() => mode = "right" || mode = "left" || (mode = "float" && floatVertical)

; The arrow points the way the bar opens while minimized, and back while
; expanded. Vertical bars open down from the top half of the screen and up
; from the bottom half; horizontal bars open right from the left half and
; left from the right half.
ArrowFor(isCollapsed) {
    if IsVertical()
        return isCollapsed ? (vAnchorBottom ? "up" : "down") : (vAnchorBottom ? "down" : "up")
    return isCollapsed ? (hAnchorRight ? "left" : "right") : (hAnchorRight ? "right" : "left")
}

; Work out which way to open from where the (minimized) bar sits.
UpdateAnchors() {
    global vAnchorBottom, hAnchorRight
    WinGetPos(&x, &y, &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    if IsVertical()
        vAnchorBottom := (y + h / 2) > (T + B) / 2
    else
        hAnchorRight := (x + w / 2) > (L + R) / 2
}

; Show either the full bar or the minimized row, without resizing the window.
ApplyBarLayout() {
    pos := collapsed ? barMinPos : barExpPos
    for c in barAll {
        if pos.Has(c) {
            q := pos[c]
            c.Move(q[1], q[2], q[3])
            c.Visible := true
        } else {
            c.Visible := false
        }
    }
}


; Minimize the bar to one row: [move][Write][Keyboard][Dictate][expand], or
; expand it. The bar keeps the edge it opened from (bottom or right) in place.
SetCollapsed(state) {
    global collapsed
    WinGetPos(&ox, &oy, &ow, &oh, bar)
    if collapsed && !state
        UpdateAnchors()
    collapsed := state
    ApplyBarLayout()
    bar.Show("NA " BarSizeOpt())
    WinGetPos(, , &nw, &nh, bar)
    if IsVertical() && vAnchorBottom
        WinMove(, oy + oh - nh, , , bar)
    else if !IsVertical() && hAnchorRight
        WinMove(ox + ow - nw, , , , bar)
    KeepOnScreen()
    UpdateArrow()
    RedrawBar()
}

; The double-buffered bar doesn't always repaint the area revealed when it
; grows, so repaint everything after any size or position change.
RedrawBar() {
    if bar
        DllCall("RedrawWindow", "ptr", bar.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x85)    ; INVALIDATE|ERASE|ALLCHILDREN (no waiting)
}

; Docked: snap to the edge. Floating: keep fully on screen, above the taskbar.
KeepOnScreen() {
    if mode != "float"
        return SnapToEdge()
    WinGetPos(&x, &y, &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    WinMove(Max(L, Min(x, R - w)), Max(T, Min(y, B - h)), , , bar)
}

UpdateArrow() {
    if collapsed
        UpdateAnchors()
    collapseBtn.icon.Text := Chr(IC[ArrowFor(collapsed)])
    UpdateDockIcon()
}

; Minimize when the keyboard is attached (laptop), expand in tablet mode.
; Only reacts when the posture changes, so a manual expand/minimize sticks.
CheckPosture() {
    static last := -1
    slate := DllCall("GetSystemMetrics", "int", 0x2003) = 0   ; SM_CONVERTIBLESLATEMODE
    if slate = last
        return
    last := slate
    if autoMin && bar
        SetCollapsed(!slate)
}

ShowDockMenu(*) {
    m := Menu()
    m.Add("Dock on right edge (vertical)", (*) => SetMode("right"))
    m.Add("Dock on left edge (vertical)", (*) => SetMode("left"))
    m.Add("Dock on top edge", (*) => SetMode("top"))
    m.Add("Dock on bottom edge (above taskbar)", (*) => SetMode("bottom"))
    m.Add("Floating", (*) => SetMode("float"))
    names := Map("right", "Dock on right edge (vertical)", "left", "Dock on left edge (vertical)", "top", "Dock on top edge",
                 "bottom", "Dock on bottom edge (above taskbar)", "float", "Floating")
    m.Check(names[mode])
    m.Show()
}

SetMode(newMode) {
    global mode, floatVertical, lastDock
    SaveAll()
    wasVertical := IsVertical()
    if newMode = "float" && mode != "float" {     ; float keeps the shape of the last dock
        floatVertical := (mode = "left" || mode = "right")
        IniWrite(floatVertical, iniFile, "Bar", "floatVertical")
    }
    if newMode != "float" {
        lastDock := newMode
        IniWrite(lastDock, iniFile, "Bar", "lastDock")
    }
    mode := newMode
    IniWrite(mode, iniFile, "Bar", "mode")
    if bar && wasVertical = IsVertical() {        ; same shape: just move it (instant)
        BarTarget(&x, &y)
        WinMove(x, y, , , bar)
        UpdateArrow(), RedrawBar()
    } else {
        BuildBar()                                  ; vertical <-> horizontal: rebuild
    }
    UpdateTrayChecks()
}

SnapToEdge() {
    global dockY, dockX
    WinGetPos(&x, &y, &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    if mode = "right" || mode = "left" {
        y := Max(T, Min(y, B - h))
        WinMove(mode = "right" ? R - w : L, y, , , bar)
        dockY := y
    } else if mode = "top" || mode = "bottom" {
        x := Max(L, Min(x, R - w))
        WinMove(x, mode = "top" ? T : B - h, , , bar)
        dockX := x
    }
}

OnExitMove(wParam, lParam, msg, hwnd) {
    global barX, barY, dockX, dockY
    if bar && hwnd = bar.Hwnd {
        WinGetPos(&x, &y, &w, &h, bar)
        MonitorGetWorkArea(, &L, &T, &R, &B)
        ; Dropped with the pen/pointer at a screen edge: dock to that edge.
        CoordMode("Mouse", "Screen"), MouseGetPos(&mx, &my)
        thr := 40 * A_ScreenDPI / 96
        near := []
        if mx <= L + thr
            near.Push("left")
        if mx >= R - 1 - thr
            near.Push("right")
        if my <= T + thr
            near.Push("top")
        if my >= B - 1 - thr
            near.Push("bottom")
        ; In a corner, keep the current dock (or the last one) instead of flipping.
        edge := ""
        if near.Length && !InArray(near, mode)
            edge := InArray(near, lastDock) ? lastDock : near[1]
        if edge != "" {
            if edge = "left" || edge = "right"
                dockY := Max(T, Min(my - 20, B - 100))
            else
                dockX := Max(L, Min(x, R - w))
            SetMode(edge)
            return
        }
        if mode != "float" {
            ; Dragged well away from its edge: undock and float where dropped.
            gap := Map("right", R - (x + w), "left", x - L, "top", y - T, "bottom", B - (y + h))[mode]
            if gap > 150 * A_ScreenDPI / 96 {
                barX := Max(L, Min(x, R - w)), barY := Max(T, Min(y, B - h))
                IniWrite(barX, iniFile, "Bar", "x"), IniWrite(barY, iniFile, "Bar", "y")
                SetMode("float")
                return
            }
        }
        KeepOnScreen()
        UpdateArrow()
        RedrawBar()
    }
    if (bar && hwnd = bar.Hwnd) || (pad && hwnd = pad.Hwnd)
        SaveAll()
}

; ============================================================================
; Handwriting pad
; ============================================================================

; Write button: show the handwriting pad (or hide it if it is showing).
WriteButton(*) {
    if padVisible && padMode = "write"
        HidePad()
    else
        ShowPad("write")
}
TogglePad() => WriteButton()

; Keyboard button: show PenBar's keyboard (or hide it if it is showing).
KeyboardButton(*) {
    if padVisible && padMode = "keys"
        HidePad()
    else
        ShowPad("keys")
}

; Default button: the Windows touch keyboard, separate from the pad.
DefaultKbButton(*) {
    ToggleTouchKeyboard()
    SetTimer(UpdateKeyboardState, -700)
}

; Dictate: Windows voice typing (Win+H) into the app you are using.
; Dictate: offline speech recognition that types straight into your app, with
; no overlay (Windows' own engine). Tap to start, tap again to stop. Or, if
; chosen in the tray menu, Windows voice typing (Win+H).
DictateButton(*) {
    if dictMode = "windows" {
        EnsureTarget()
        Send("#h")
        return
    }
    if DictationOn()
        StopDictation()
    else
        StartDictation()
}

DictationOn() => FileExist(DICT_FLAG) != ""

StartDictation() {
    global dictPid
    if !dictPid || !ProcessExist(dictPid) {
        if A_IsCompiled {
            try {                         ; FileInstall starts its line so Ahk2Exe bundles the file
                FileInstall("dictate.ps1", A_AppData "\PenBar\dictate.ps1", 1)
            }
            script := A_AppData "\PenBar\dictate.ps1"
        } else {
            script := A_ScriptDir "\dictate.ps1"
        }
        Run('powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' script '" "' DICT_FLAG '" ' ProcessExist(), , "Hide", &dictPid)
    }
    try FileAppend("", DICT_FLAG)
    EnsureTarget()
    UpdateBarStates()
}

StopDictation(quit := false) {
    global dictPid
    try FileDelete(DICT_FLAG)
    if quit && dictPid
        try ProcessClose(dictPid)
    if !quit
        UpdateBarStates()
}

SetDictMode(m) {
    global dictMode := m
    IniWrite(m, iniFile, "Dictation", "mode")
    StopDictation()
    UpdateTrayChecks()
}

ShowPad(m) {
    global padVisible
    if !pad
        BuildPad()
    else
        pad.Show("NA")
    padVisible := true
    SetPadMode(m)
}

HidePad(*) {
    global padVisible, kbDown, kbPopup
    SetTimer(DoRecognize, 0), DiscardInk()
    kbDown := 0, kbPopup := 0
    if pad
        pad.Hide()
    padVisible := false
    UpdateBarStates()
}

SwapPadMode(*) => SetPadMode(padMode = "write" ? "keys" : "write")

; The pad shows either the handwriting area or PenBar's keyboard.
SetPadMode(m) {
    global padMode, kbWord
    padMode := m
    keys := (m = "keys")
    SetTimer(DoRecognize, 0), DiscardInk(), HideAlts()
    kbWord := ""
    swapBtn.icon.Text := Chr(IC[keys ? "write" : "keyboard"])        ; offers the other mode
    Tip(swapBtn, keys ? "Switch to handwriting" : "Switch to keyboard")
    kbPic.Visible := keys
    PadLayout()
    UpdateBarStates()
}

BuildPad() {
    global pad, padGrip, altBtns, inkPen, BTN_H, swapBtn, padMicBtn, spaceBtn, backBtn, tabBtn, enterBtn, padUndoBtn, padRedoBtn
    global clearBtn, closeBtn, padResizer, padTopH, padMinW
    barH := BTN_H, BTN_H := PAD_BTN_H
    pad := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +Border", "PenBar Pad")
    pad.BackColor := PAD_BG                         ; same dark theme as the keyboard
    pad.MarginX := 0, pad.MarginY := 0

    ; top row, always: [move][Dictate][write/keyboard] ... [close]
    SetIconFont(pad)
    padGrip := pad.AddText("x4 y4 w" ICON_W " h" BTN_H " Center +0x200 cWhite Background" BTN, Chr(IC["move"]))
    padGrip.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , pad))
    padMicBtn := MakeButton(pad, "mic",      "", "x0 y0", 0, DictateButton)
    swapBtn   := MakeButton(pad, "keyboard", "", "x0 y0", 0, SwapPadMode)
    padUndoBtn := MakeButton(pad, "undo",    "", "x0 y0", 0, SmartUndo)
    padRedoBtn := MakeButton(pad, "redo",    "", "x0 y0", 0, SmartRedo)
    closeBtn  := MakeButton(pad, "close",    "", "x0 y0", 0, HidePad)
    ; top row, otherwise: suggestions, or [Clear Ink][Palm Rejection]
    clearBtn  := MakeButton(pad, "clear", "Clear", "x0 y0", MeasureText("Clear") + 6,
        (*) => (SetTimer(DoRecognize, 0), DiscardInk(), HideAlts()))
    altBtns := []
    loop 3 {
        b := MakeButton(pad, "", "", "x0 y0", 110, AltFn(A_Index))
        ShowButton(b, false)
        altBtns.Push(b)
    }
    ; writing pad: keyboard keys in a column on the right, below close
    spaceBtn  := MakeButton(pad, "space", "", "x0 y0", 0, SpaceKey)
    backBtn   := MakeButton(pad, "back",  "", "x0 y0", 0, BackspaceKey)
    tabBtn    := MakeButton(pad, "tab",   "", "x0 y0", 0, KeysFn("{Tab}"))
    enterBtn  := MakeButton(pad, "enter", "", "x0 y0", 0, EnterKey)
    Tip(padGrip, "Move (drag)"), Tip(padMicBtn, "Dictate"), Tip(closeBtn, "Close")
    Tip(clearBtn, "Clear ink and suggestions"), Tip(padUndoBtn, "Undo"), Tip(padRedoBtn, "Redo")
    Tip(spaceBtn, "Space"), Tip(backBtn, "Backspace"), Tip(tabBtn, "Tab"), Tip(enterBtn, "Enter")
    BTN_H := barH
    padMinW := 480
    padTopH := Round((PAD_BTN_H + 8) * A_ScreenDPI / 96)
    pad.Show("Hide w800 h" (PAD_BTN_H + 8 + PAD_H))

    ; Round-capped ink pen
    lb := Buffer(16, 0)
    NumPut("uint", 0, "uint", INK_COLOR, lb)                 ; BS_SOLID, color
    width := Max(2, Round(3 * A_ScreenDPI / 96))
    inkPen := DllCall("ExtCreatePen", "uint", 0x10000, "uint", width, "ptr", lb, "uint", 0, "ptr", 0, "ptr")

    ; PenBar keyboard: a picture over the writing area (ignores input, so taps
    ; reach the pad), and a resize handle in the bottom-right corner on top.
    CreateKeyboard()
    BTN_H := PAD_BTN_H
    global resizeBtn := MakeButton(pad, "@resize", "", "x0 y0", 0, (*) => 0)   ; dragging it resizes (see OnMouse)
    padResizer := resizeBtn.icon
    Tip(resizeBtn, "Resize (drag), or tap for the smallest size")
    BTN_H := barH

    ; remembered size, never smaller than the minimum
    if padW != "" {
        mw := MinPadSize()
        WinMove(, , Max(Integer(padW), mw[1]), Max(Integer(padH), mw[2]), pad)
    }
    WinGetPos(, , &w, &h, pad)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    x := (padX = "") ? L + (R - L - w) // 2 : Max(L, Min(Integer(padX), R - w))
    y := (padY = "") ? B - h - 12 : Max(T, Min(Integer(padY), B - h))
    PadLayout()
    pad.Show("NA x" x " y" y)
}

; Smallest pad: a usable writing / keyboard area below the top row.
MinPadSize() {
    k := A_ScreenDPI / 96
    step := PAD_BTN_H + 3
    colH := 4 + 6 * step + 4                     ; writing pad: close, space, back, tab, enter, resize
    return [Round(padMinW * k) + 2, Max(padTopH + Round(170 * k), Round(colH * k)) + 2]
}

; Top row: [move][Dictate][write/keyboard] then suggestions (+ Clear), or
; [Clear][Palm Rejection] on the writing pad ... [close].
; Top row: [move][Dictate][write/keyboard][undo][redo], then suggestions (+ Clear)
; or [Clear] when there's ink ... [close].
PadTopRow() {
    if !pad || !padCwL
        return
    step := ICON_W + 3
    fixed := [padGrip, padMicBtn.icon, swapBtn.icon, padUndoBtn.icon, padRedoBtn.icon]
    for i, c in fixed
        c.Move(4 + (i - 1) * step, 4, ICON_W, PAD_BTN_H), c.Visible := true
    closeBtn.icon.Move(padCwL - 4 - ICON_W, 4, ICON_W, PAD_BTN_H), closeBtn.icon.Visible := true
    limit := padCwL - 4 - ICON_W - 6
    x := 4 + fixed.Length * step + 6
    hasAlts := curAlts.Length > 0
    for i, b in altBtns {
        if hasAlts && i <= curAlts.Length && x + 110 <= limit - (ICON_W + clearBtn.lw + 3) {
            b.label.Move(x, 4), b.label.Visible := true
            x += 113
        } else {
            b.label.Visible := false
        }
    }
    showClear := hasAlts || (padMode = "write" && (strokes.Length || curStroke))
    if showClear
        clearBtn.icon.Move(x, 4), clearBtn.label.Move(x + ICON_W, 4)
    ShowButton(clearBtn, showClear)
}

; Writing pad: Space, Backspace, Tab, Enter in a column on the right, below close.
; Writing pad: Space, Backspace, Tab, Enter in a column on the right, below
; close, and the resize button at the bottom of that column.
PadRightCol() {
    col := [spaceBtn, backBtn, tabBtn, enterBtn]
    show := padMode = "write"
    for i, b in col {
        if show
            b.icon.Move(padCwL - 4 - ICON_W, 4 + i * (PAD_BTN_H + 3), ICON_W, PAD_BTN_H)
        ShowButton(b, show)
    }
    ; resize: bottom-right corner (the keyboard's last row stops short of it)
    resizeBtn.icon.Move(padCwL - 4 - ICON_W, padChL - 4 - PAD_BTN_H, ICON_W, PAD_BTN_H)
    resizeBtn.icon.Visible := true
    ; above the keyboard picture, so the keyboard (WS_CLIPSIBLINGS) never paints over it
    DllCall("SetWindowPos", "ptr", resizeBtn.icon.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)
}

; Fit the rows, writing area / keyboard and resize handle to the pad's size.
PadLayout() {
    global writeRect, kbW, kbH, kbOrigin, kbBmp, padCwL
    rc := Buffer(16), pt := Buffer(8, 0)
    DllCall("GetClientRect", "ptr", pad.Hwnd, "ptr", rc)
    cw := NumGet(rc, 8, "int"), ch := NumGet(rc, 12, "int")
    s := 96 / A_ScreenDPI
    padCwL := Round(cw * s), chL := Round(ch * s)
    global padChL := chL
    colW := padMode = "write" ? Round((ICON_W + 8) / s) : 0
    writeRect := {l: 0, t: padTopH, r: cw - colW, b: ch}
    PadTopRow(), PadRightCol()
    kbPic.Move(0, Round(padTopH * s), padCwL, chL - Round(padTopH * s))
    DllCall("GetClientRect", "ptr", kbPic.Hwnd, "ptr", rc)
    nw := NumGet(rc, 8, "int"), nh := NumGet(rc, 12, "int")
    DllCall("ClientToScreen", "ptr", kbPic.Hwnd, "ptr", pt)
    DllCall("ScreenToClient", "ptr", pad.Hwnd, "ptr", pt)
    kbOrigin := [NumGet(pt, 0, "int"), NumGet(pt, 4, "int")]
    if nw != kbW || nh != kbH || !kbBmp {
        kbW := nw, kbH := nh
        sdc := DllCall("GetDC", "ptr", 0, "ptr")
        newBmp := DllCall("CreateCompatibleBitmap", "ptr", sdc, "int", kbW, "int", kbH, "ptr")
        DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
        SendMessage(0x172, 0, newBmp, kbPic)             ; STM_SETIMAGE: the picture shows our bitmap
        if kbBmp
            DllCall("DeleteObject", "ptr", kbBmp)
        kbBmp := newBmp
        SetTimer(KbPrerender, -60)                       ; draw every keyboard screen ahead of time
    }
    if padMode = "write"
        DiscardInk()
    RenderKeyboard()
    DllCall("RedrawWindow", "ptr", pad.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x181)   ; repaint, no extra erase
}

; ---- pen input -------------------------------------------------------------

PointerType(id) {
    t := 0
    DllCall("GetPointerType", "uint", id, "uint*", &t)
    return t                    ; 2 = touch, 3 = pen, 4 = mouse
}

OnPointer(wParam, lParam, msg, hwnd) {
    global penId
    if !pad || hwnd != pad.Hwnd
        return
    id := wParam & 0xFFFF
    t := PointerType(id)
    if padMode = "keys"
        return KbPointer(id, t, msg, lParam)
    if t != 3 && t != 2
        return
    ; Pen or finger both write. A resting palm (big contact) is ignored, and
    ; touches outside the writing area never reach it.
    if msg = 0x246 {            ; down
        p := ScreenToPad(lParam)
        if !InWriteArea(p)
            return              ; let the system handle it
        if t = 2 && IsPalm(id)
            return 0
        if penId {
            if t = 3 && penIsTouch
                CancelStroke()  ; the pen wins over a finger / palm stroke in progress
            else
                return 0
        }
        global penIsTouch := (t = 2)
        penId := id
        BeginStroke(p)
        return 0
    }
    if id != penId
        return 0
    if msg = 0x245 {            ; pen moved
        for p in PenHistory(id)
            AddPoint(p)
    } else {                    ; pen up
        for p in PenHistory(id)
            AddPoint(p)
        penId := 0
        EndStroke()
    }
    return 0
}

; A touch whose contact area is wider than about 1.8 cm is a palm, not a finger.
IsPalm(id) {
    buf := Buffer(160, 0)
    if !DllCall("GetPointerTouchInfo", "uint", id, "ptr", buf)
        return false
    if !(NumGet(buf, 100, "uint") & 0x1)            ; TOUCH_MASK_CONTACTAREA
        return false
    w := NumGet(buf, 112, "int") - NumGet(buf, 104, "int"), h := NumGet(buf, 116, "int") - NumGet(buf, 108, "int")
    return Max(w, h) > A_ScreenDPI / 2.54 * 1.8
}

; Drop the stroke being drawn (a palm or finger got there before the pen).
CancelStroke() {
    global curStroke, inkDC, penId
    curStroke := 0, penId := 0
    if inkDC
        DllCall("ReleaseDC", "ptr", pad.Hwnd, "ptr", inkDC), inkDC := 0
    DllCall("InvalidateRect", "ptr", pad.Hwnd, "ptr", 0, "int", 1)
    DllCall("UpdateWindow", "ptr", pad.Hwnd)
    RedrawInk()
}

RedrawInk() {
    dc := DllCall("GetDC", "ptr", pad.Hwnd, "ptr")
    DllCall("IntersectClipRect", "ptr", dc, "int", writeRect.l, "int", writeRect.t, "int", writeRect.r, "int", writeRect.b)
    DllCall("SelectObject", "ptr", dc, "ptr", inkPen)
    for st in strokes {
        DllCall("MoveToEx", "ptr", dc, "int", st[1][1], "int", st[1][2], "ptr", 0)
        for q in st
            DllCall("LineTo", "ptr", dc, "int", q[1], "int", q[2])
    }
    DllCall("ReleaseDC", "ptr", pad.Hwnd, "ptr", dc)
}

OnPointerLost(wParam, lParam, msg, hwnd) {
    global penId
    if pad && hwnd = pad.Hwnd && penId && (wParam & 0xFFFF) = penId {
        penId := 0
        EndStroke()
    }
}

OnPointerActivate(wParam, lParam, msg, hwnd) {
    if (pad && hwnd = pad.Hwnd) || (bar && hwnd = bar.Hwnd)
        return 3                ; PA_NOACTIVATE
}

; All points since the last message, oldest first (keeps fast strokes smooth).
PenHistory(id) {
    pts := []
    info := Buffer(96, 0)
    if !DllCall("GetPointerInfo", "uint", id, "ptr", info)
        return pts
    n := Max(1, NumGet(info, 68, "uint"))
    buf := Buffer(96 * n, 0), cnt := n
    if !DllCall("GetPointerInfoHistory", "uint", id, "uint*", &cnt, "ptr", buf)
        buf := info, cnt := 1
    loop cnt {
        i := cnt - A_Index
        pts.Push(ScreenToPadXY(NumGet(buf, i * 96 + 32, "int"), NumGet(buf, i * 96 + 36, "int")))
    }
    return pts
}

OnMouse(wParam, lParam, msg, hwnd) {
    global mouseInk, resizing, resizeStart, padW, padH, resizeGhost
    if msg = 0x200 && TIPS.Has(hwnd)
        TipHover(hwnd)
    ; Drag the corner to resize the pad: an outline follows the pointer, and the
    ; pad is resized once when you let go (no flicker while dragging).
    if padResizer && hwnd = padResizer.Hwnd {
        CoordMode("Mouse", "Screen"), MouseGetPos(&mx, &my)
        if msg = 0x201 || msg = 0x203 {
            WinGetPos(&px, &py, &w, &h, pad)
            resizeStart := [mx, my, w, h, px, py], resizing := true
            if !resizeGhost {
                resizeGhost := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020")   ; no focus, click-through
                resizeGhost.BackColor := ACTIVE
                WinSetTransparent(60, resizeGhost)
            }
            resizeGhost.Show("NA x" px " y" py " w" w " h" h)
            DllCall("SetCapture", "ptr", hwnd)
        } else if resizing && msg = 0x200 {
            mw := MinPadSize()
            WinMove(resizeStart[5], resizeStart[6], Max(mw[1], resizeStart[3] + mx - resizeStart[1]),
                Max(mw[2], resizeStart[4] + my - resizeStart[2]), resizeGhost)
        } else if resizing && msg = 0x202 {
            resizing := false
            DllCall("ReleaseCapture")
            WinGetPos(, , &w, &h, resizeGhost)
            resizeGhost.Hide()
            if Abs(mx - resizeStart[1]) < 8 && Abs(my - resizeStart[2]) < 8 {   ; a tap: shrink to the smallest size
                mw := MinPadSize(), w := mw[1], h := mw[2]
            }
            WinMove(, , w, h, pad)
            PadLayout()
            padW := w, padH := h
            IniWrite(w, iniFile, "Pad", "w"), IniWrite(h, iniFile, "Pad", "h")
        }
        return 0
    }
    if !pad || hwnd != pad.Hwnd
        return
    x := lParam << 48 >> 48, y := lParam << 32 >> 48
    p := [x, y]
    ; press anywhere on the top row (between buttons) to drag the pad
    if (msg = 0x201 || msg = 0x203) && y < padTopH {
        PostMessage(0xA1, 2, 0, , pad)
        return 0
    }
    if (DllCall("GetMessageExtraInfo", "ptr") & 0xFFFFFF00) = 0xFF515700
        return 0                ; generated by pen/touch: already handled
    if padMode = "keys"
        return KbOnMouse(msg, p)
    if (msg = 0x201 || msg = 0x203) && InWriteArea(p) {
        mouseInk := true
        DllCall("SetCapture", "ptr", pad.Hwnd)
        BeginStroke(p)
        return 0
    }
    if !mouseInk
        return
    if msg = 0x200 {
        AddPoint(p)
    } else if msg = 0x202 {
        AddPoint(p)
        mouseInk := false
        DllCall("ReleaseCapture")
        EndStroke()
    }
    return 0
}

ScreenToPad(lParam) => ScreenToPadXY(lParam << 48 >> 48, lParam << 32 >> 48)

ScreenToPadXY(x, y) {
    pt := Buffer(8)
    NumPut("int", x, "int", y, pt)
    DllCall("ScreenToClient", "ptr", pad.Hwnd, "ptr", pt)
    return [NumGet(pt, 0, "int"), NumGet(pt, 4, "int")]
}

InWriteArea(p) => p[1] >= writeRect.l && p[1] < writeRect.r && p[2] >= writeRect.t && p[2] < writeRect.b

; ---- PenBar keyboard -----------------------------------------------------------

; Key: [kind, value, width, label]. Kinds: char, back, tab, caps, enter, shift,
; page, ctrl, alt, win, layer, emoji, space. Every row is 12 units wide.
KB_MODROW(layerKey, layerLabel) => [["layer", layerKey, 1.25, layerLabel], ["ctrl", "", 1, "Ctrl"], ["win", "", 1, ""],
    ",", ["space", " ", 3.25, ""], ".", ["alt", "", 1, "Alt"], ["enter", "", 2, "Enter"]]
KB_EMOJI := ["emoji", "", 1, "☺"]
KB_BACK  := ["back", "", 1.75, "⌫"]
KB_F(n)  => ["send", "{F" n "}", 1, "F" n]
; Every screen has the same keys in the same places. Symbols sit roughly where
; they are on a real keyboard (brackets after P, quotes after L, < > ? bottom right).
KB_LAYOUTS := Map(
    "abc", [
        ["1","2","3","4","5","6","7","8","9","0","-","+"],
        [["tab", "", 2, "Tab"], "q","w","e","r","t","y","u","i","o","p"],
        [["caps", "", 2, "Caps"], "a","s","d","f","g","h","j","k","l",";"],
        [["shift", "", 2, "Shift"], "z","x","c","v","b","n","m", KB_BACK, KB_EMOJI],
        KB_MODROW("sym", "&123")],
    "sym", [
        ["!","@","#","$","%","^","&","*","(",")","_","="],
        [["tab", "", 2, "Tab"], "~","``","€","£","¥","°","[","]","{","}"],
        [["caps", "", 2, "Caps"], "\","|","§","©","®","™","…",":","'",'"'],
        [["page", "", 2, "1/2"], "×","÷","±","/","<",">","?", KB_BACK, KB_EMOJI],
        KB_MODROW("abc", "abc")],
    "sym2", [
        [KB_F(1), KB_F(2), KB_F(3), KB_F(4), KB_F(5), KB_F(6), KB_F(7), KB_F(8), KB_F(9), KB_F(10), KB_F(11), KB_F(12)],
        [["tab", "", 2, "Tab"], ["send", "{Home}", 2, "Home"], ["send", "{PgUp}", 2, "PgUp"], ["send", "{Ins}", 1, "Ins"],
            ["send", "{Esc}", 1, "Esc"], "≠","≤", ["send", "{Up}", 1, "↑"], "≥"],
        [["caps", "", 2, "Caps"], ["send", "{End}", 1, "End"], ["send", "{Del}", 1, "Del"], ["send", "{PgDn}", 2, "PgDn"],
            "≈","∞","π", ["send", "{Left}", 1, "←"], ["send", "{Down}", 1, "↓"], ["send", "{Right}", 1, "→"]],
        [["page", "", 2, "2/2"], "«","»","“","”","‘","’","¿", KB_BACK, KB_EMOJI],
        KB_MODROW("abc", "abc")])

; Hold a key for these alternatives (international letters, extra punctuation).
; Small hint in the corner of a key: hold it (or slide right) for that symbol.
KB_HINT := Map("1", "!", "2", "@", "3", "#", "4", "$", "5", "%", "6", "^", "7", "&", "8", "*", "9", "(", "0", ")",
    "-", "_", "+", "=", ",", "'", ".", "?", ";", ":")
KB_ALTS := Map("1", "!¹½", "2", "@²", "3", "#³", "4", "$€£", "5", "%", "6", "^", "7", "&", "8", "*", "9", "(", "0", ")°",
    "+", "=±", ",", "'", ";", ":", "a", "àáâäãåāæ", "c", "çćč", "e", "èéêëēėę", "i", "ìíîïīį", "n", "ñń", "o", "òóôöõøōœ",
    "s", "ßśš", "u", "ùúûüū", "y", "ýÿ", "z", "žźż", "l", "ł", "g", "ğ", "d", "ð",
    "-", "_–—", ".", "?!…:", "?", "¿", "!", "¡", "$", "€£¥¢", "'", "‘’", '"', "“”«»", "0", "°")

CreateKeyboard() {
    global kbPic, kbDC
    ; +0xE = SS_BITMAP, +0x04000000 = WS_CLIPSIBLINGS (don't paint over the resize handle)
    kbPic := pad.AddPicture("x0 y0 w10 h10 Hidden +0xE +0x04000000")
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    kbDC := DllCall("CreateCompatibleDC", "ptr", sdc, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
}

; Work out key rectangles for the current layer and size (keyboard-local pixels).
LayoutKeys() {
    global kbKeys, kbLayoutKey, kbCenters, kbTemplates
    key := kbLayer "|" kbW "|" kbH
    if kbLayoutKey = key && kbKeys.Length               ; keep the same key objects between redraws
        return
    kbLayoutKey := key
    kbKeys := []
    rows := KB_LAYOUTS[kbLayer]
    gap := Max(3, Round(4 * A_ScreenDPI / 96))
    rowH := (kbH - gap * (rows.Length + 1)) / rows.Length
    parsed := []
    for row in rows {
        keys := []
        for k in row
            keys.Push(IsObject(k) ? {k: k[1], v: k[2], w: k[3], lab: k[4]} : {k: "char", v: k, w: 1, lab: k})
        parsed.Push(keys)
    }
    ; the keys share x0..x1 by width, so every row fills its space
    LayRow(keys, x0, x1, y) {
        total := 0
        for kk in keys
            total += kk.w
        unit := (x1 - x0 - gap * (keys.Length - 1)) / total
        x := x0
        for kk in keys
            kk.l := Round(x), kk.t := Round(y), kk.r := Round(x + kk.w * unit), kk.b := Round(y + rowH), x += kk.w * unit + gap
    }
    RowY(r) => gap + (r - 1) * (rowH + gap)
    n := parsed.Length
    bottom := parsed[n]
    LayRow(bottom, gap, kbW - gap - Round((ICON_W + 4) * A_ScreenDPI / 96), RowY(n))   ; leave the corner to resize
    ent := bottom[bottom.Length]
    for r, keys in parsed {
        if r = n
            continue
        last := keys[keys.Length]
        if r = n - 1 && last.k = "emoji" {                       ; emoji lines up with the resize button
            keys.Pop()
            LayRow(keys, gap, ent.r, RowY(r))
            keys.Push(last)
            last.l := ent.r + gap, last.r := kbW - gap, last.t := Round(RowY(r)), last.b := Round(RowY(r) + rowH)
        } else {
            LayRow(keys, gap, kbW - gap, RowY(r))
        }
    }
    for keys in parsed
        for kk in keys
            kbKeys.Push(kk)
    if kbLayer = "abc" {                                 ; letter centres for swipe typing
        kbCenters := Map(), kbTemplates := Map()
        for kk in kbKeys
            if kk.k = "char" && kk.v ~= "^[a-z]$"
                kbCenters[kk.v] := [(kk.l + kk.r) / 2, (kk.t + kk.b) / 2]
    }
}

KbKeyOn(key) {
    switch key.k {
        case "shift": return kbLayer = "abc" && kbShift
        case "caps":  return kbCaps
        case "ctrl", "alt", "win": return kbMods[key.k]
    }
    return false
}

; Letters are capitals when exactly one of Shift / Caps Lock is on.
KbUpper() => kbLayer = "abc" && (kbCaps != (kbShift > 0))

; Shift also brings up the symbols on the number / punctuation keys (Shift+2 = @).
KbShifted(key) => kbLayer = "abc" && kbShift > 0 && key.k = "char" && KB_HINT.Has(key.v)

KbLabel(key) => key.k = "back" && kbLayer = "abc" && kbShift > 0 ? "Clear" : KbShifted(key) ? KB_HINT[key.v] : key.k = "char" && KbUpper() ? StrUpper(key.lab) : key.lab

DrawKey(dc, l, t, r, b, color, label, rc, rad, winLogo := false, hint := "") {
    static smallFont := 0, smallFor := 0
    br := DllCall("CreateSolidBrush", "uint", color, "ptr")
    ob := DllCall("SelectObject", "ptr", dc, "ptr", br, "ptr")
    DllCall("RoundRect", "ptr", dc, "int", l, "int", t, "int", r + 1, "int", b + 1, "int", rad, "int", rad)
    DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("DeleteObject", "ptr", br)
    if winLogo {                                     ; the Windows logo: four squares
        sz := Round(Min(r - l, b - t) * 0.36), half := sz // 2, gp := Max(1, sz // 12)
        x0 := (l + r) // 2 - half, y0 := (t + b) // 2 - half
        wb := DllCall("CreateSolidBrush", "uint", 0xFFFFFF, "ptr")
        for q in [[0, 0], [1, 0], [0, 1], [1, 1]] {
            qx := x0 + q[1] * (half + gp), qy := y0 + q[2] * (half + gp)
            NumPut("int", qx, "int", qy, "int", qx + half - gp, "int", qy + half - gp, rc)
            DllCall("FillRect", "ptr", dc, "ptr", rc, "ptr", wb)
        }
        DllCall("DeleteObject", "ptr", wb)
        return
    }
    kh := b - t, kw := r - l
    if hint = "" {
        NumPut("int", l, "int", t, "int", r, "int", b, rc)
        DllCall("DrawTextW", "ptr", dc, "str", label, "int", -1, "ptr", rc, "uint", 0x825)   ; centred, no "&" underline
        return
    }
    ; key with a symbol hint: main label nudged down-left, hint top-right
    NumPut("int", l, "int", t + Round(kh * 0.14), "int", r - Round(kw * 0.12), "int", b, rc)
    DllCall("DrawTextW", "ptr", dc, "str", label, "int", -1, "ptr", rc, "uint", 0x825)
    if smallFor != kh {
        if smallFont
            DllCall("DeleteObject", "ptr", smallFont)
        smallFont := DllCall("CreateFontW", "int", -Round(kh * 0.34), "int", 0, "int", 0, "int", 0, "int", 400,
            "uint", 0, "uint", 0, "uint", 0, "uint", 1, "uint", 0, "uint", 0, "uint", 5, "uint", 0, "str", "Segoe UI", "ptr")
        smallFor := kh
    }
    of := DllCall("SelectObject", "ptr", dc, "ptr", smallFont, "ptr")
    DllCall("SetTextColor", "ptr", dc, "uint", 0xB0B0B0)
    NumPut("int", l, "int", t + 1, "int", r - Round(kw * 0.1), "int", b, rc)
    DllCall("DrawTextW", "ptr", dc, "str", hint, "int", -1, "ptr", rc, "uint", 0x802)        ; top-right
    DllCall("SetTextColor", "ptr", dc, "uint", 0xFFFFFF)
    DllCall("SelectObject", "ptr", dc, "ptr", of)
}

KbHint(k) => KbShifted(k) ? "" : kbLayer = "abc" && k.k = "char" && KB_HINT.Has(k.v) ? KB_HINT[k.v] : ""

KbStateKey() => kbLayer "|" KbUpper() "|" kbShift "|" kbCaps "|" kbMods["ctrl"] kbMods["alt"] kbMods["win"]

KbFont(dc) {
    keyH := kbKeys[1].b - kbKeys[1].t
    font := DllCall("CreateFontW", "int", -Round(Min(keyH * 0.45, (kbKeys[1].r - kbKeys[1].l) * 0.5)), "int", 0, "int", 0,
        "int", 0, "int", 400, "uint", 0, "uint", 0, "uint", 0, "uint", 1, "uint", 0, "uint", 0, "uint", 5, "uint", 0,
        "str", "Segoe UI Symbol", "ptr")
    DllCall("SetBkMode", "ptr", dc, "int", 1)
    DllCall("SetTextColor", "ptr", dc, "uint", 0xFFFFFF)
    DllCall("SelectObject", "ptr", dc, "ptr", DllCall("GetStockObject", "int", 8, "ptr"))   ; NULL_PEN
    return font
}

; The keyboard without a pressed key, for the current screen / Shift / Ctrl...
; Drawn once and kept, so switching screens and typing are instant.
KbBase() {
    global kbCache, kbCacheSize
    if kbCacheSize != kbW "x" kbH {
        for k, hbm in kbCache
            DllCall("DeleteObject", "ptr", hbm)
        kbCache := Map(), kbCacheSize := kbW "x" kbH
    }
    key := KbStateKey()
    if kbCache.Has(key)
        return kbCache[key]
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", sdc, "int", kbW, "int", kbH, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    dc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    ob := DllCall("SelectObject", "ptr", dc, "ptr", hbm, "ptr")
    rc := Buffer(16)
    NumPut("int", 0, "int", 0, "int", kbW, "int", kbH, rc)
    bg := DllCall("CreateSolidBrush", "uint", 0x202020, "ptr")
    DllCall("FillRect", "ptr", dc, "ptr", rc, "ptr", bg), DllCall("DeleteObject", "ptr", bg)
    font := KbFont(dc)
    of := DllCall("SelectObject", "ptr", dc, "ptr", font, "ptr")
    rad := Round(8 * A_ScreenDPI / 96)
    for k in kbKeys
        DrawKey(dc, k.l, k.t, k.r, k.b, KbKeyOn(k) ? 0xBD6C0F : (k.k = "char" || k.k = "send" ? 0x3A3A3A : 0x2C2C2C),
            KbLabel(k), rc, rad, k.k = "win", KbHint(k))
    DllCall("SelectObject", "ptr", dc, "ptr", of), DllCall("DeleteObject", "ptr", font)
    DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("DeleteDC", "ptr", dc)
    return kbCache[key] := hbm
}

; Draw every main keyboard screen ahead of time.
KbPrerender() {
    global kbLayer, kbShift, kbCaps
    if !kbBmp
        return
    saved := [kbLayer, kbShift, kbCaps]
    for st in [["abc", 0, 0], ["abc", 1, 0], ["abc", 0, 1], ["sym", 0, 0], ["sym2", 0, 0]] {
        kbLayer := st[1], kbShift := st[2], kbCaps := st[3]
        LayoutKeys(), KbBase()
    }
    kbLayer := saved[1], kbShift := saved[2], kbCaps := saved[3]
    LayoutKeys()
}

RenderKeyboard() {
    if !kbPic || !kbBmp || padMode != "keys"
        return
    LayoutKeys()
    base := KbBase()
    src := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    os := DllCall("SelectObject", "ptr", src, "ptr", base, "ptr")
    ob := DllCall("SelectObject", "ptr", kbDC, "ptr", kbBmp, "ptr")
    DllCall("BitBlt", "ptr", kbDC, "int", 0, "int", 0, "int", kbW, "int", kbH, "ptr", src, "int", 0, "int", 0, "uint", 0xCC0020)
    DllCall("SelectObject", "ptr", src, "ptr", os), DllCall("DeleteDC", "ptr", src)
    if (kbDown && !kbPopup) || kbPopup {                 ; pressed key / accents on top
        rc := Buffer(16), rad := Round(8 * A_ScreenDPI / 96)
        font := KbFont(kbDC)
        of := DllCall("SelectObject", "ptr", kbDC, "ptr", font, "ptr")
        if kbDown && !kbPopup
            DrawKey(kbDC, kbDown.l, kbDown.t, kbDown.r, kbDown.b, 0x6A6A6A, KbLabel(kbDown), rc, rad, kbDown.k = "win", KbHint(kbDown))
        if kbPopup
            for i, pk in kbPopup.keys
                DrawKey(kbDC, pk.l, pk.t, pk.r, pk.b, i = kbPopup.sel ? 0xBD6C0F : 0x505050, pk.ch, rc, rad)
        DllCall("SelectObject", "ptr", kbDC, "ptr", of), DllCall("DeleteObject", "ptr", font)
    }
    global kbShownDown := kbPopup ? 0 : kbDown
    ; straight to the screen: no invalidate / erase, so no flicker
    dc := DllCall("GetDC", "ptr", kbPic.Hwnd, "ptr")
    DllCall("BitBlt", "ptr", dc, "int", 0, "int", 0, "int", kbW, "int", kbH, "ptr", kbDC, "int", 0, "int", 0, "uint", 0xCC0020)
    DllCall("ReleaseDC", "ptr", kbPic.Hwnd, "ptr", dc)
    DllCall("SelectObject", "ptr", kbDC, "ptr", ob)
}

; Show a key press by redrawing only the key(s) that changed (fast).
KbShowPressed() {
    global kbShownDown
    if kbShownDown = kbDown || !kbBmp || padMode != "keys"
        return
    keys := []
    if kbShownDown
        keys.Push(kbShownDown)
    if kbDown
        keys.Push(kbDown)
    kbShownDown := kbDown
    base := KbBase()
    src := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    os := DllCall("SelectObject", "ptr", src, "ptr", base, "ptr")
    ob := DllCall("SelectObject", "ptr", kbDC, "ptr", kbBmp, "ptr")
    font := KbFont(kbDC)
    of := DllCall("SelectObject", "ptr", kbDC, "ptr", font, "ptr")
    rc := Buffer(16), rad := Round(8 * A_ScreenDPI / 96)
    for k in keys {
        DllCall("BitBlt", "ptr", kbDC, "int", k.l - 1, "int", k.t - 1, "int", k.r - k.l + 3, "int", k.b - k.t + 3,
            "ptr", src, "int", k.l - 1, "int", k.t - 1, "uint", 0xCC0020)
        if k = kbDown
            DrawKey(kbDC, k.l, k.t, k.r, k.b, 0x6A6A6A, KbLabel(k), rc, rad, k.k = "win", KbHint(k))
    }
    DllCall("SelectObject", "ptr", kbDC, "ptr", of), DllCall("DeleteObject", "ptr", font)
    DllCall("SelectObject", "ptr", src, "ptr", os), DllCall("DeleteDC", "ptr", src)
    dc := DllCall("GetDC", "ptr", kbPic.Hwnd, "ptr")
    for k in keys
        DllCall("BitBlt", "ptr", dc, "int", k.l - 1, "int", k.t - 1, "int", k.r - k.l + 3, "int", k.b - k.t + 3,
            "ptr", kbDC, "int", k.l - 1, "int", k.t - 1, "uint", 0xCC0020)
    DllCall("ReleaseDC", "ptr", kbPic.Hwnd, "ptr", dc)
    DllCall("SelectObject", "ptr", kbDC, "ptr", ob)
}

KbLocal(p) => [p[1] - kbOrigin[1], p[2] - kbOrigin[2]]

KbHit(p) {
    lp := KbLocal(p)
    for key in kbKeys
        if lp[1] >= key.l && lp[1] < key.r && lp[2] >= key.t && lp[2] < key.b
            return key
    return 0
}

OverResizer(p) {
    padResizer.GetPos(&x, &y, &w, &h)
    k := A_ScreenDPI / 96
    return padResizer.Visible && p[1] >= x * k && p[1] < (x + w) * k && p[2] >= y * k && p[2] < (y + h) * k
}

; Pointer / mouse handlers only queue the event and return at once, so quick
; taps (double letters) are never dropped while a key is being typed.
KbPointer(id, t, msg, lParam) {
    global kbPtr
    if t != 2 && t != 3
        return
    if msg = 0x246 {                                  ; finger / pen down
        if kbPtr
            return 0                                  ; one key at a time
        p := ScreenToPad(lParam)
        if !InWriteArea(p) || OverResizer(p)
            return
        kbPtr := id
        KbEnqueue("down", [p])
        return 0
    }
    if id != kbPtr
        return 0
    if msg = 0x245 {
        KbEnqueue("move", PenHistory(id))
    } else {
        kbPtr := 0
        KbEnqueue("move", PenHistory(id))
        KbEnqueue("up", [])
    }
    return 0
}

KbOnMouse(msg, p) {
    global kbMouse
    if (msg = 0x201 || msg = 0x203) && InWriteArea(p) && !OverResizer(p) {
        kbMouse := true
        DllCall("SetCapture", "ptr", pad.Hwnd)
        KbEnqueue("down", [p])
        return 0
    }
    if !kbMouse
        return
    if msg = 0x200 {
        KbEnqueue("move", [p])
    } else if msg = 0x202 {
        kbMouse := false
        DllCall("ReleaseCapture")
        KbEnqueue("up", [])
    }
    return 0
}

KbEnqueue(kind, pts) {
    kbQueue.Push([kind, pts])
    SetTimer(KbProcess, -1)
}

KbProcess() {
    while kbQueue.Length {
        e := kbQueue.RemoveAt(1)
        if e[1] = "down" {
            KbOnDown(e[2][1])
        } else if e[1] = "move" {
            for p in e[2]
                KbOnMove(p)
        } else {
            KbOnUp()
        }
    }
}

KbOnDown(p) {
    global kbDown, kbPath, kbSwiping, kbPopup, kbShift, kbWord
    kbPath := [KbLocal(p)], kbSwiping := false, kbPopup := 0
    kbDown := KbHit(p)
    KbShowPressed()
    if kbDown && kbDown.k = "back" && kbLayer = "abc" && kbShift > 0 {   ; Shift + Backspace: clear everything
        kbShift := 0, kbWord := ""
        EnsureTarget(), ForgetHist()
        Send("^a{Delete}")
        HideAlts(), RenderKeyboard()
    } else if kbDown && kbDown.k = "back" {           ; backspace acts on press and repeats
        KbBackspace()
        SetTimer(KbRepeat, -450)
    } else if kbDown && kbDown.k = "char" && KB_ALTS.Has(StrLower(kbDown.v)) {
        SetTimer(KbLongPress, -300)                   ; hold for accents
    }
}

KbOnMove(p) {
    global kbDown, kbSwiping, kbPopup
    lp := KbLocal(p)
    prev := kbPath[-1]
    kbPath.Push(lp)
    if kbPopup {                                      ; choosing an accent
        ; slide along the strip to pick; slide well away from it to cancel
        sel := 0, h := kbPopup.keys[1].b - kbPopup.keys[1].t
        for i, pk in kbPopup.keys
            if lp[1] >= pk.l && lp[1] < pk.r && lp[2] >= pk.t - h && lp[2] < pk.b + 1.5 * h
                sel := i
        if sel != kbPopup.sel
            kbPopup.sel := sel, RenderKeyboard()
        return
    }
    if kbSwiping {
        DrawTrail(prev, lp)
        return
    }
    if Dist(kbPath[1], lp) > KeyUnit() * 0.25
        SetTimer(KbLongPress, 0)                      ; moving: not a hold
    ; Starting on a letter and sliding about a key's width: swipe typing.
    if kbLayer = "abc" && kbDown && kbDown.k = "char" && kbDown.v ~= "^[a-z]$" && PathLength(kbPath) > KeyUnit() * 0.6 {
        kbSwiping := true, kbDown := 0
        SetTimer(KbRepeat, 0)
        RenderKeyboard()
        loop kbPath.Length - 1
            DrawTrail(kbPath[A_Index], kbPath[A_Index + 1])
        return
    }
    k := KbHit(p)
    if k != kbDown {
        kbDown := k
        SetTimer(KbRepeat, 0)
        KbShowPressed()
    }
}

KbOnUp() {
    global kbDown, kbSwiping, kbPopup
    SetTimer(KbRepeat, 0), SetTimer(KbLongPress, 0)
    if kbPopup {
        c := kbPopup.sel ? kbPopup.keys[kbPopup.sel].ch : ""
        kbPopup := 0, kbDown := 0
        if c != ""
            KbTypeChar(c)
        RenderKeyboard()
        return
    }
    key := kbDown, kbDown := 0
    if kbSwiping {
        kbSwiping := false
        RenderKeyboard()
        SwipeType(kbPath)
        return
    }
    before := KbStateKey()
    if key && key.k != "back"
        KbPress(key)
    if KbStateKey() != before
        RenderKeyboard()        ; screen / Shift / Caps / Ctrl changed: whole keyboard
    else
        KbShowPressed()         ; otherwise just un-press the key
}

; Held a key: show its alternatives above it; slide to one and lift to type it.
KbLongPress() {
    global kbPopup
    if !kbDown || kbSwiping || kbDown.k != "char" || !KB_ALTS.Has(StrLower(kbDown.v))
        return
    upper := KbUpper() && kbDown.v ~= "^[a-z]$"
    ; the plain letter comes first, right above your finger, so a hold that
    ; changes nothing still types the normal letter
    chars := [upper ? StrUpper(kbDown.v) : kbDown.v]
    loop parse KB_ALTS[StrLower(kbDown.v)]
        chars.Push(upper ? StrUpper(A_LoopField) : A_LoopField)
    w := kbDown.r - kbDown.l, h := kbDown.b - kbDown.t, gap := 3
    total := chars.Length * (w + gap) - gap
    x := Max(0, Min(kbDown.l, kbW - total))
    y := kbDown.t - h - gap
    if y < 0
        y := kbDown.b + gap
    keys := []
    for i, c in chars
        keys.Push({l: Round(x + (i - 1) * (w + gap)), t: Round(y), r: Round(x + (i - 1) * (w + gap) + w), b: Round(y + h), ch: c})
    kbPopup := {keys: keys, sel: 1}
    RenderKeyboard()
}

KbRepeat() {
    if kbDown && kbDown.k = "back" {
        KbBackspace()
        SetTimer(KbRepeat, -70)
    }
}

KbBackspace() {
    global kbWord
    if KbModsActive()
        return SendWithMods("{Backspace}")
    BackspaceKey()
    if kbWord != "" {
        kbWord := SubStr(kbWord, 1, -1)
        ShowCompletions()
    }
}

KbModsActive() => kbMods["ctrl"] || kbMods["alt"] || kbMods["win"]

; Ctrl / Alt / Win are sticky: tap one, then the next key is sent with it.
SendWithMods(keyStr) {
    pre := (kbMods["ctrl"] ? "^" : "") (kbMods["alt"] ? "!" : "") (kbMods["win"] ? "#" : "")
    EnsureTarget(), ForgetHist()
    Send(pre keyStr)
    kbMods["ctrl"] := false, kbMods["alt"] := false, kbMods["win"] := false
}

KbTypeChar(c) {
    global kbWord, kbShift
    if KbModsActive()
        return SendWithMods("{" c "}")
    TypeChar(c)
    if c ~= "^[A-Za-zÀ-ÿ'’]$"
        kbWord .= c
    else
        kbWord := ""
    if kbShift = 1
        kbShift := 0
    ShowCompletions()
}

KbPress(key) {
    global kbShift, kbLastShift, kbLayer, kbWord, kbCaps
    mods := KbModsActive()
    switch key.k {
        case "char":
            c := KbShifted(key) ? KB_HINT[key.v] : key.v
            if KbUpper()
                c := StrUpper(c)
            KbTypeChar(c)
        case "send":                                  ; F keys, arrows, Home / End...
            if mods {
                SendWithMods(key.v)
            } else {
                EnsureTarget(), ForgetHist()
                Send(key.v)
            }
            kbWord := ""
            HideAlts()
        case "shift":
            ; tap = next letter flips case, double-tap = Caps Lock on
            if kbShift = 0 && A_TickCount - kbLastShift < 400 && !kbCaps
                kbCaps := true, kbShift := 0
            else
                kbShift := kbShift ? 0 : 1
            kbLastShift := A_TickCount
        case "caps":
            kbCaps := !kbCaps, kbShift := 0
        case "page":
            kbLayer := (kbLayer = "sym") ? "sym2" : "sym"
        case "space", "enter", "tab":
            if mods {
                SendWithMods("{" key.k "}")
            } else if key.k = "space" {
                SpaceKey()
            } else if key.k = "enter" {
                EnterKey()
            } else {
                EnsureTarget(), ForgetHist()
                Send("{Tab}")
            }
            kbWord := ""
            HideAlts()
        case "layer":
            kbLayer := key.v, kbShift := 0
        case "emoji":
            EnsureTarget()
            Send("#.")                                ; Windows emoji panel
        case "ctrl", "alt":
            kbMods[key.k] := !kbMods[key.k]
        case "win":
            if kbMods["win"] && !kbMods["ctrl"] && !kbMods["alt"] {
                kbMods["win"] := false                ; Win tapped twice: open Start
                EnsureTarget()
                Send("{LWin}")
            } else {
                kbMods["win"] := !kbMods["win"]
            }
    }
}

; Type one character from the keyboard (tracked so Undo can remove it).
TypeChar(c) {
    global hist, redoStack, kbWord
    EnsureTarget()
    if !HistValid()
        hist := [], kbWord := ""
    SendText(c)
    hist.Push({s: c, removed: ""}), redoStack := []
    MarkHist()
}

; ---- word list, suggestions and swipe typing ----------------------------------

LoadWords() {
    if A_IsCompiled {
        try {                             ; FileInstall starts its line so Ahk2Exe bundles the file
            FileInstall("words.txt", A_AppData "\PenBar\words.txt", 1)
        }
        path := A_AppData "\PenBar\words.txt"
    } else {
        path := A_ScriptDir "\words.txt"
    }
    list := [], seen := Map()
    try {
        loop read path {
            w := StrLower(Trim(A_LoopReadLine))
            if w != "" && !seen.Has(w)
                seen[w] := 1, list.Push(w)
        }
    }
    return list
}

; Words in the list are stored without apostrophes or capitals.
WORD_DISPLAY := Map("i", "I", "im", "I'm", "ive", "I've", "id", "I'd", "dont", "don't", "doesnt", "doesn't",
    "didnt", "didn't", "isnt", "isn't", "arent", "aren't", "wasnt", "wasn't", "werent", "weren't",
    "cant", "can't", "couldnt", "couldn't", "wouldnt", "wouldn't", "shouldnt", "shouldn't", "wont", "won't",
    "thats", "that's", "whats", "what's", "theres", "there's", "lets", "let's", "youre", "you're",
    "youve", "you've", "monday", "Monday", "tuesday", "Tuesday", "wednesday", "Wednesday",
    "thursday", "Thursday", "friday", "Friday", "saturday", "Saturday", "sunday", "Sunday",
    "january", "January", "february", "February", "april", "April", "june", "June", "july", "July",
    "september", "September", "october", "October", "november", "November", "december", "December",
    "microsoft", "Microsoft", "google", "Google")

DisplayWord(w, capital := false) {
    d := WORD_DISPLAY.Has(w) ? WORD_DISPLAY[w] : w
    return capital ? StrUpper(SubStr(d, 1, 1)) SubStr(d, 2) : d
}

; While typing a word on the keyboard, offer up to 3 completions.
ShowCompletions() {
    global curAlts, altMode
    pre := StrLower(StrReplace(kbWord, "'"))
    if pre = "" {
        HideAlts()
        return
    }
    cap := SubStr(kbWord, 1, 1) ~= "[A-Z]"
    res := []
    for w in WORDS {
        if StrLen(w) > StrLen(pre) && SubStr(w, 1, StrLen(pre)) == pre {
            res.Push(DisplayWord(w, cap))
            if res.Length = altBtns.Length
                break
        }
    }
    curAlts := res, altMode := "complete"
    ShowAlts()
}

; Replace the half-typed word with the tapped completion (plus a space).
CompletionPick(i) {
    global kbWord, hist
    w := curAlts[i]
    EnsureTarget()
    n := StrLen(kbWord)
    if n
        Send("{Backspace " n "}")
    loop n
        if hist.Length
            hist.Pop()
    kbWord := ""
    InsertText(w)
    HideAlts()
}

Dist(a, b) => Sqrt((a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)

PathLength(pts) {
    d := 0
    loop pts.Length - 1
        d += Dist(pts[A_Index], pts[A_Index + 1])
    return d
}

KeyUnit() {
    for k in kbKeys
        if k.k = "char"
            return k.r - k.l
    return 50
}

; Evenly spaced points along a path.
Resample(pts, n) {
    total := PathLength(pts)
    if pts.Length < 2 || total = 0 {
        out := []
        loop n
            out.Push(pts[1])
        return out
    }
    step := total / (n - 1), out := [pts[1]], acc := 0
    i := 2, prev := pts[1]
    while i <= pts.Length && out.Length < n {
        cur := pts[i], d := Dist(prev, cur)
        if acc + d >= step && d > 0 {
            t := (step - acc) / d
            q := [prev[1] + t * (cur[1] - prev[1]), prev[2] + t * (cur[2] - prev[2])]
            out.Push(q), prev := q, acc := 0
        } else {
            acc += d, prev := cur, i++
        }
    }
    while out.Length < n
        out.Push(pts[-1])
    return out
}

; The ideal swipe for a word: through the centre of each of its letters.
WordTemplate(w) {
    global kbTemplates
    if kbTemplates.Has(w)
        return kbTemplates[w]
    pts := [], last := ""
    loop parse w {
        if !kbCenters.Has(A_LoopField)
            return kbTemplates[w] := 0
        if A_LoopField != last
            pts.Push(kbCenters[A_LoopField])
        last := A_LoopField
    }
    return kbTemplates[w] := Resample(pts, 24)
}

; Turn a swipe into a word: compare it with the ideal swipe of every word that
; starts and ends near the right keys, favouring common words. Instant: no delay.
SwipeType(path) {
    global curAlts, altMode, kbShift, kbWord
    best := SwipeGuesses(path)
    if !best.Length
        return
    cap := kbShift > 0
    if kbShift = 1
        kbShift := 0
    kbWord := ""
    InsertText(kbCaps ? StrUpper(best[1]) : DisplayWord(best[1], cap))
    curAlts := []
    loop best.Length - 1
        curAlts.Push(DisplayWord(best[A_Index + 1], cap))
    altMode := "swipe"
    ShowAlts()
    RenderKeyboard()
}

; Best four words for a swipe path (keyboard-local points), best first.
SwipeGuesses(path) {
    if path.Length < 2 || !kbCenters.Count
        return []
    kw := KeyUnit()
    up := Resample(path, 24)
    s0 := path[1], s1 := path[-1]
    scored := []
    for rank, w in WORDS {
        if StrLen(w) < 2
            continue
        f := SubStr(w, 1, 1), l := SubStr(w, -1)
        if !kbCenters.Has(f) || !kbCenters.Has(l)
            continue
        if Dist(kbCenters[f], s0) > kw * 1.3 || Dist(kbCenters[l], s1) > kw * 1.3
            continue
        tpl := WordTemplate(w)
        if !tpl
            continue
        d := 0
        loop 24
            d += Dist(up[A_Index], tpl[A_Index])
        ; the shape, plus extra weight on where the swipe starts and ends
        d := d / 24 + 0.6 * Dist(tpl[1], s0) + 0.9 * Dist(tpl[24], s1)
        scored.Push([d / kw + 0.25 * Ln(rank + 1) / Ln(WORDS.Length + 1), w])
    }
    best := []
    loop Min(4, scored.Length) {
        bi := 1
        for i, sc in scored
            if sc[1] < scored[bi][1]
                bi := i
        best.Push(scored.RemoveAt(bi)[2])
    }
    return best
}

DrawTrail(a, b) {
    dc := DllCall("GetDC", "ptr", kbPic.Hwnd, "ptr")
    pen := DllCall("CreatePen", "int", 0, "int", Max(4, Round(7 * A_ScreenDPI / 96)), "uint", 0xF0B060, "ptr")
    op := DllCall("SelectObject", "ptr", dc, "ptr", pen, "ptr")
    DllCall("MoveToEx", "ptr", dc, "int", Round(a[1]), "int", Round(a[2]), "ptr", 0)
    DllCall("LineTo", "ptr", dc, "int", Round(b[1]), "int", Round(b[2]))
    DllCall("SelectObject", "ptr", dc, "ptr", op), DllCall("DeleteObject", "ptr", pen)
    DllCall("ReleaseDC", "ptr", kbPic.Hwnd, "ptr", dc)
}

; ---- strokes ---------------------------------------------------------------

BeginStroke(p) {
    global curStroke, inkDC
    SetTimer(DoRecognize, 0)          ; still writing: don't recognize yet
    curStroke := [p]
    if !clearBtn.icon.Visible
        PadTopRow()                   ; something drawn: show Clear
    inkDC := DllCall("GetDC", "ptr", pad.Hwnd, "ptr")
    DllCall("IntersectClipRect", "ptr", inkDC, "int", writeRect.l, "int", writeRect.t, "int", writeRect.r, "int", writeRect.b)
    DllCall("SelectObject", "ptr", inkDC, "ptr", inkPen)
    DllCall("MoveToEx", "ptr", inkDC, "int", p[1], "int", p[2], "ptr", 0)
    DllCall("LineTo", "ptr", inkDC, "int", p[1], "int", p[2])
}

AddPoint(p) {
    if !curStroke
        return
    last := curStroke[-1]
    if p[1] = last[1] && p[2] = last[2]
        return
    curStroke.Push(p)
    if inkDC
        DllCall("LineTo", "ptr", inkDC, "int", p[1], "int", p[2])
}

EndStroke() {
    global curStroke, inkDC
    if !curStroke
        return
    strokes.Push(curStroke)
    curStroke := 0
    if inkDC
        DllCall("ReleaseDC", "ptr", pad.Hwnd, "ptr", inkDC), inkDC := 0
    SetTimer(DoRecognize, -delayMs)   ; recognize after a pause
}

DiscardInk() {
    global strokes
    strokes := []
    if pad {
        DllCall("InvalidateRect", "ptr", pad.Hwnd, "ptr", 0, "int", 1)
        PadTopRow()                                 ; nothing drawn: hide Clear
    }
}

; Each batch of strokes is taken off the pad before recognizing, so it can
; never be recognized (and typed) twice.
DoRecognize() {
    global strokes, curStroke, recognizing, curAlts, altMode
    if recognizing || curStroke || penId || mouseInk || !strokes.Length
        return
    recognizing := true
    batch := strokes, strokes := []
    DllCall("InvalidateRect", "ptr", pad.Hwnd, "ptr", 0, "int", 1)
    text := "", alts := []
    try {
        ink := ComObject("msinkaut.InkObject")
        k := 2540 / A_ScreenDPI                      ; pixels -> HIMETRIC
        for s in batch {
            if s.Length = 1
                s.Push([s[1][1] + 1, s[1][2] + 1])
            arr := ComObjArray(3, s.Length * 2)
            for i, p in s
                arr[(i - 1) * 2] := Round(p[1] * k), arr[(i - 1) * 2 + 1] := Round(p[2] * k)
            ink.CreateStroke(arr, ComValue(0, 0))
        }
        ctx := ComObject("msinkaut.InkRecognizerContext")
        ctx.Strokes := ink.Strokes
        st := Buffer(4, 0)
        res := ctx.Recognize(ComValue(0x4003, st.Ptr))
        text := Trim(res.TopString)
        try {
            a := res.AlternatesFromSelection(0, -1, 6)
            loop a.Count {
                s := Trim(a.Item(A_Index - 1).String)
                if s != "" && s != text && !InArray(alts, s) && alts.Length < altBtns.Length
                    alts.Push(s)
            }
        }
    }
    if text != "" {
        InsertText(text)
        curAlts := alts, altMode := "ink"
        ShowAlts()
    }
    recognizing := false
    if strokes.Length && !curStroke        ; more was written meanwhile
        SetTimer(DoRecognize, -delayMs)
}

ShowAlts() {
    for i, b in altBtns
        if i <= curAlts.Length
            b.label.Text := curAlts[i]
    PadTopRow()
}

AltFn(i) {
    return (*) => AltPick(i)
}

; Replace the last word written with the suggestion that was tapped.
AltPick(i) {
    global hist, curAlts
    if i > curAlts.Length
        return
    if altMode = "complete"                         ; keyboard word completion
        return CompletionPick(i)
    EnsureTarget()
    if !(hist.Length && HistValid())
        return
    old := hist.Pop()
    Send("{Backspace " StrLen(old.s) "}")
    if old.removed != ""
        SendText(old.removed)
    newText := curAlts[i]
    InsertText(newText)
    HideAlts()                                      ; picked: the suggestions go away
}

; ============================================================================
; Typing + word-level undo/redo
; Each history entry is {s: text typed, removed: text deleted just before it}.
; ============================================================================

InsertText(text) {
    global hist, redoStack
    EnsureTarget()
    if !HistValid()
        hist := []
    removed := ""
    ; Punctuation sticks to the previous word: "hello ." -> "hello. "
    if autoSpace && RegExMatch(text, "^[.,!?;:]+$") && hist.Length && SubStr(hist[-1].s, -1) = " " {
        Send("{Backspace}")
        removed := " "
    }
    s := autoSpace ? text " " : text
    SendText(s)
    hist.Push({s: s, removed: removed}), redoStack := []
    MarkHist()
}

SmartUndo(*) {
    global hist, redoStack
    EnsureTarget()
    if hist.Length && HistValid() {
        e := hist.Pop()
        Send("{Backspace " StrLen(e.s) "}")
        if e.removed != ""
            SendText(e.removed)
        redoStack.Push(e)
        MarkHist()
        HideAlts()
    } else {
        ForgetHist()
        Send(undoWord ? "^{Backspace}" : "^z")
    }
}

SmartRedo(*) {
    global hist, redoStack
    EnsureTarget()
    if redoStack.Length && HistValid() {
        e := redoStack.Pop()
        if e.removed != ""
            Send("{Backspace " StrLen(e.removed) "}")
        SendText(e.s)
        hist.Push(e)
        MarkHist()
    } else {
        ForgetHist()
        Send(RedoKeys())
    }
}

BackspaceKey(*) {
    global hist, redoStack
    EnsureTarget()
    valid := hist.Length && HistValid()
    Send("{Backspace}")
    if valid {
        e := hist[-1]
        e.s := SubStr(e.s, 1, -1)
        if e.s = ""
            hist.Pop()
        redoStack := []
        MarkHist()
    } else {
        ForgetHist()
    }
}

SpaceKey(*) => TypeTracked(" ", "{Space}")
EnterKey(*) => TypeTracked("`n", "{Enter}")

TypeTracked(str, keys) {
    global hist, redoStack
    EnsureTarget()
    if !HistValid()
        hist := []
    Send(keys)
    hist.Push({s: str, removed: ""}), redoStack := []
    MarkHist()
}

HideAlts() {
    global curAlts
    curAlts := []
    PadTopRow()
}

MarkHist() {
    global histWin, histTick
    histWin := WinExist("A"), histTick := A_TickCount
    SetTimer(RecordCaret, -150)
}

ForgetHist() {
    global hist, redoStack, histWin
    hist := [], redoStack := [], histWin := 0
    HideAlts()
}

RecordCaret() {
    global histCaret
    histCaret := CaretGetPos(&cx, &cy) ? cx "," cy : ""
}

; PenBar only undoes its own words while you are still in the same spot:
; same window, no physical typing since, and the text cursor has not moved.
HistValid() {
    if !histWin || WinExist("A") != histWin
        return false
    if A_TimeIdleKeyboard < A_TickCount - histTick - 100
        return false
    if histCaret != "" && A_TickCount - histTick > 300 {
        if CaretGetPos(&cx, &cy) && (cx "," cy) != histCaret
            return false
    }
    return true
}

RedoKeys() {
    try {
        if REDO_SHIFT_Z.Has(StrLower(WinGetProcessName("A")))
            return "^+z"
    }
    return "^y"
}

; ============================================================================
; Focus helpers
; ============================================================================

TrackActive() {
    global lastWin
    try {
        h := WinExist("A")
        if h && h != bar.Hwnd && !(pad && h = pad.Hwnd) && WinGetClass(h) != "Shell_TrayWnd"
            lastWin := h
    }
}

EnsureTarget() {
    a := WinExist("A")
    if ((bar && a = bar.Hwnd) || (pad && a = pad.Hwnd)) && lastWin && WinExist(lastWin) {
        WinActivate(lastWin)
        WinWaitActive(lastWin, , 0.5)
    }
}

; Opens/closes the Windows touch keyboard (opens in the layout used last).
ToggleTouchKeyboard() {
    tabTip := A_ProgramFiles "\Common Files\microsoft shared\ink\TabTip.exe"
    if !ProcessExist("TabTip.exe") && FileExist(tabTip) {
        try Run(tabTip)
        Sleep(400)
    }
    try {
        tip := ComObject("{4ce576fa-83dc-4F88-951c-9d0782b4e376}", "{37c994e7-432b-4834-a2f7-dce1f13b834b}")
        ComCall(3, tip, "ptr", DllCall("GetDesktopWindow", "ptr"))
    } catch {
        Send("#^o")
    }
}

InArray(arr, val) {
    for v in arr
        if v == val
            return true
    return false
}

; ============================================================================
; Tray menu + saving
; ============================================================================

BuildTrayMenu() {
    global delayMenu
    tm := A_TrayMenu
    tm.Add()
    tm.Add("Handwriting pad", (*) => TogglePad())
    tm.Add("Dock bar on right edge", (*) => SetMode("right"))
    tm.Add("Dock bar on top edge", (*) => SetMode("top"))
    tm.Add("Dock bar on bottom edge", (*) => SetMode("bottom"))
    tm.Add("Dock bar on left edge", (*) => SetMode("left"))
    tm.Add("Floating bar", (*) => SetMode("float"))
    tm.Add()
    tm.Add("Add a space after each word", ToggleAutoSpace)
    tm.Add("Undo outside the pad deletes last word (not Ctrl+Z)", ToggleUndoWord)
    tm.Add("Minimize bar when the keyboard is attached", ToggleAutoMin)
    dm := Menu()
    dm.Add("Instant, offline (types straight into your app)", (*) => SetDictMode("offline"))
    dm.Add("Windows voice typing (Win+H)", (*) => SetDictMode("windows"))
    tm.Add("Dictation", dm)
    global dictMenu := dm
    tm.Add("Start with Windows", ToggleStartup)
    delayMenu := Menu()
    for ms, name in DELAYS
        delayMenu.Add(name, SetDelayFn(ms))
    tm.Add("Type text after a pause of", delayMenu)
    tm.Add("Reset bar and pad positions", ResetPositions)
    tm.Add()
    tm.Add("About PenBar " PENBAR_VERSION " (GitHub)", (*) => Run(PENBAR_URL))
    UpdateTrayChecks()
}

SetDelayFn(ms) => (*) => SetDelay(ms)

UpdateTrayChecks() {
    tm := A_TrayMenu
    (mode = "right") ? tm.Check("Dock bar on right edge") : tm.Uncheck("Dock bar on right edge")
    (mode = "top") ? tm.Check("Dock bar on top edge") : tm.Uncheck("Dock bar on top edge")
    (mode = "bottom") ? tm.Check("Dock bar on bottom edge") : tm.Uncheck("Dock bar on bottom edge")
    (mode = "left") ? tm.Check("Dock bar on left edge") : tm.Uncheck("Dock bar on left edge")
    autoMin ? tm.Check("Minimize bar when the keyboard is attached") : tm.Uncheck("Minimize bar when the keyboard is attached")
    startup ? tm.Check("Start with Windows") : tm.Uncheck("Start with Windows")
    if IsSet(dictMenu) && dictMenu {
        (dictMode = "offline") ? dictMenu.Check("Instant, offline (types straight into your app)") : dictMenu.Uncheck("Instant, offline (types straight into your app)")
        (dictMode = "windows") ? dictMenu.Check("Windows voice typing (Win+H)") : dictMenu.Uncheck("Windows voice typing (Win+H)")
    }
    (mode = "float") ? tm.Check("Floating bar") : tm.Uncheck("Floating bar")
    autoSpace ? tm.Check("Add a space after each word") : tm.Uncheck("Add a space after each word")
    undoWord ? tm.Check("Undo outside the pad deletes last word (not Ctrl+Z)")
             : tm.Uncheck("Undo outside the pad deletes last word (not Ctrl+Z)")
    for ms, name in DELAYS
        (delayMs = ms) ? delayMenu.Check(name) : delayMenu.Uncheck(name)
}

ToggleAutoSpace(*) {
    global autoSpace := !autoSpace
    IniWrite(autoSpace, iniFile, "Pad", "autoSpace"), UpdateTrayChecks()
}

ToggleUndoWord(*) {
    global undoWord := !undoWord
    IniWrite(undoWord, iniFile, "Undo", "fallbackDeleteWord"), UpdateTrayChecks()
}

SetDelay(ms) {
    global delayMs := ms
    IniWrite(ms, iniFile, "Pad", "delay"), UpdateTrayChecks()
}

ResetPositions(*) {
    global barX := "", barY := "", dockY := "", dockX := "", padX := "", padY := ""
    for k in ["x", "y", "dockY", "dockX"]
        try IniDelete(iniFile, "Bar", k)
    for k in ["x", "y"]
        try IniDelete(iniFile, "Pad", k)
    BuildBar()
    if pad {
        WinGetPos(, , &w, &h, pad)
        MonitorGetWorkArea(, &L, &T, &R, &B)
        WinMove(L + (R - L - w) // 2, B - h - 12, , , pad)
    }
}

SaveAll(*) {
    global barX, barY, dockY, dockX, padX, padY
    try {
        WinGetPos(&x, &y, , , bar)
        if mode = "right" || mode = "left"
            dockY := y, IniWrite(y, iniFile, "Bar", "dockY")
        else if mode = "top" || mode = "bottom"
            dockX := x, IniWrite(x, iniFile, "Bar", "dockX")
        else
            barX := x, barY := y, IniWrite(x, iniFile, "Bar", "x"), IniWrite(y, iniFile, "Bar", "y")
    }
    if pad {
        try {
            WinGetPos(&x, &y, , , pad)
            padX := x, padY := y
            IniWrite(x, iniFile, "Pad", "x"), IniWrite(y, iniFile, "Pad", "y")
        }
    }
}
