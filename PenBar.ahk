; PenBar - a floating pen toolbar + handwriting pad for Windows tablets.
; Needs AutoHotkey v2 (free, open source): https://www.autohotkey.com
;
; The bar and pad never take focus, so everything goes to the app you are in.
;   Write      opens the handwriting pad. Write, pause, and the words are typed
;              into your app. Tap a suggestion at the top to fix a misread word.
;              Palm Rejection (on by default): only the pen writes on the pad and
;              palm/finger touches are ignored. Turn it off to write with a finger.
;   Undo       removes the last word written on the pad (not the whole text).
;              For other text it sends the app's normal Ctrl+Z.
;   Redo       puts back the last word you undid.
;   Dock       dock the bar on the right edge (vertical), the top edge, or float.
;   Drag the move handle to move the bar or pad. Positions are remembered.
;   More options: right-click the green "H" tray icon.

#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook()
CoordMode("Caret", "Screen")

; ---- settings -------------------------------------------------------------
iniFile   := A_ScriptDir "\PenBar.ini"
mode      := IniRead(iniFile, "Bar", "mode", "float")      ; "float", "right", "top" or "bottom"
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
INK_COLOR := 0x202020           ; BGR

; Segoe Fluent Icons glyphs
IC := Map("move", 0xE7C2, "hide", 0xE70E, "show", 0xE70D, "write", 0xE76D,
          "undo", 0xE7A7, "redo", 0xE7A6, "tab", 0xE7FD, "copy", 0xE8C8,
          "paste", 0xE77F, "back", 0xE750, "enter", 0xE751, "switch", 0xE8AB,
          "tasks", 0xE7C4, "keyboard", 0xE765, "dock", 0xE90D, "space", 0xE75D,
          "clear", 0xE74D, "close", 0xE894, "screenshot", 0xE722, "palm", 0xEDA4)
ACTIVE := "0F6CBD"              ; background of a button that is switched on

palmReject := Integer(IniRead(iniFile, "Pad", "palmRejection", 1))
autoMin    := Integer(IniRead(iniFile, "Bar", "autoMinimize", 1))
startup    := Integer(IniRead(iniFile, "General", "startWithWindows", 1))
STARTUP_LNK := A_Startup "\PenBar.lnk"

; Apps that use Ctrl+Shift+Z for redo instead of Ctrl+Y.
REDO_SHIFT_Z := Map("krita.exe", 1, "photoshop.exe", 1, "illustrator.exe", 1,
                    "figma.exe", 1, "inkscape.exe", 1, "blender.exe", 1, "gimp-2.10.exe", 1)

; ---- state ------------------------------------------------------------------
bar := 0, pad := 0, padGrip := 0, padVisible := false
collapsed := false, extra := [], altBtns := [], curAlts := []
lastWin := 0
hist := [], redoStack := []            ; text typed by PenBar, for word-level undo
histWin := 0, histTick := 0, histCaret := ""
; ink
strokes := [], curStroke := 0, penId := 0, mouseInk := false
inkDC := 0, inkPen := 0, writeRect := {l: 0, t: 0, r: 0, b: 0}, recognizing := false

writeBtn := 0, kbBtn := 0, collapseBtn := 0, palmBtn := 0, inputPane := 0

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
OnExit(SaveAll)

; Start with Windows: a shortcut in the Startup folder. Rewritten on every
; start so it always points at wherever PenBar.ahk lives now.
UpdateStartup() {
    try {
        if startup
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

TogglePalm(*) {
    global palmReject := !palmReject
    IniWrite(palmReject, iniFile, "Pad", "palmRejection")
    SetActive(palmBtn, palmReject)
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
    b := {ctrls: [], icon: 0, label: 0, active: false}
    if icon != "" {
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
        c.Opt("Background" BTN_HIT), c.Redraw()
    SetTimer(() => FlashOff(b), -150)
}

FlashOff(b) {
    for c in b.ctrls
        c.Opt("Background" (b.active ? ACTIVE : BTN)), c.Redraw()
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
    SetActive(kbBtn, on)
}

; ============================================================================
; Bar
; ============================================================================

MeasureText(text) {
    static g := 0
    if !g
        g := Gui(), g.SetFont("s10 norm", "Segoe UI")
    g.AddText("xm ym", text).GetPos(, , &w)
    return w
}

BuildBar() {
    global bar, extra, writeBtn, kbBtn, collapseBtn, BTN_H
    if bar
        bar.Destroy()
    extra := []
    vertical := (mode = "right")
    BTN_H := vertical ? 36 : 40

    ; +E0x08000000 = WS_EX_NOACTIVATE: tapping the bar does not steal focus.
    bar := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "PenBar")
    bar.BackColor := BG
    bar.MarginX := 4, bar.MarginY := 4

    ; Groups: input | history | clipboard | keys | windows | dock
    ; [icon, label, handler, starts a new group]
    items := [
        ["write",      "Write",      (*) => TogglePad(),           1],
        ["keyboard",   "Keyboard",   KeyboardButton,               0],
        ["undo",       "Undo",       SmartUndo,                    1],
        ["redo",       "Redo",       SmartRedo,                    0],
        ["copy",       "Copy",       KeysFn("^c"),                 1],
        ["paste",      "Paste",      KeysFn("^v"),                 0],
        ["back",       "Backspace",  BackspaceKey,                 1],
        ["tab",        "Tab",        KeysFn("{Tab}"),              0],
        ["enter",      "Enter",      EnterKey,                     0],
        ["switch",     "Last App",   KeysFn("!{Tab}"),             1],
        ["tasks",      "Task View",  KeysFn("#{Tab}"),             0],
        ["screenshot", "Screenshot", KeysFn("{PrintScreen}"),      0],
        ["dock",       "Dock",       ShowDockMenu,                 1],
    ]
    ; Vertical bar is only as wide as its longest label.
    maxW := 0
    for it in items
        maxW := Max(maxW, MeasureText(it[2]))
    VW := ICON_W + maxW + 10

    ; One row: move handle + minimize/expand.
    SetIconFont(bar)
    gripW := vertical ? VW - ICON_W - 3 : ICON_W
    grip := bar.AddText("xm ym w" gripW " h" BTN_H " Center +0x200 cAAAAAA", Chr(IC["move"]))
    grip.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , bar))
    collapseBtn := MakeButton(bar, "hide", "", "x+3 yp", 0, (*) => SetCollapsed(!collapsed))

    pos := (gap) => vertical ? "xm y+" gap : "x+" gap " yp"
    lw  := (text) => vertical ? VW - ICON_W : MeasureText(text) + 6
    for it in items
        extra.Push(MakeButton(bar, it[1], it[2], pos(it[4] ? 10 : 3), lw(it[2]), it[3]))
    writeBtn := extra[1], kbBtn := extra[2]
    SetActive(writeBtn, padVisible)

    bar.Show("Hide AutoSize")
    WinGetPos(, , &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    if mode = "right" {
        x := R - w
        y := (dockY = "") ? T + (B - T - h) // 2 : Max(T, Min(Integer(dockY), B - h))
    } else if mode = "top" || mode = "bottom" {
        x := (dockX = "") ? L + (R - L - w) // 2 : Max(L, Min(Integer(dockX), R - w))
        y := (mode = "top") ? T : B - h
    } else {
        x := (barX = "") ? L + (R - L - w) // 2 : Max(L, Min(Integer(barX), R - w))
        y := (barY = "") ? T + 40 : Max(T, Min(Integer(barY), B - h))
    }
    bar.Show("NA x" x " y" y)
    if collapsed
        SetCollapsed(true)
}

KeysFn(keys) {
    return (*) => (EnsureTarget(), ForgetHist(), Send(keys))
}

; Minimize the bar to its top row (move + expand), or expand it again.
SetCollapsed(state) {
    global collapsed := state
    for e in extra
        ShowButton(e, !collapsed)
    collapseBtn.icon.Text := Chr(IC[collapsed ? "show" : "hide"])
    if collapsed {
        collapseBtn.icon.GetPos(&cx, &cy, &cw, &ch)
        bar.Show("NA w" (cx + cw + 4) " h" (cy + ch + 4))
    } else {
        bar.Show("NA AutoSize")
    }
    if mode != "float"
        SnapToEdge()            ; stay against the docked edge (e.g. bottom)
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
    m.Add("Dock on top edge", (*) => SetMode("top"))
    m.Add("Dock on bottom edge (above taskbar)", (*) => SetMode("bottom"))
    m.Add("Floating", (*) => SetMode("float"))
    names := Map("right", "Dock on right edge (vertical)", "top", "Dock on top edge",
                 "bottom", "Dock on bottom edge (above taskbar)", "float", "Floating")
    m.Check(names[mode])
    m.Show()
}

SetMode(newMode) {
    global mode
    SaveAll()
    mode := newMode
    IniWrite(mode, iniFile, "Bar", "mode")
    BuildBar()
    UpdateTrayChecks()
}

SnapToEdge() {
    global dockY, dockX
    WinGetPos(&x, &y, &w, &h, bar)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    if mode = "right" {
        y := Max(T, Min(y, B - h))
        WinMove(R - w, y, , , bar)
        dockY := y
    } else if mode = "top" || mode = "bottom" {
        x := Max(L, Min(x, R - w))
        WinMove(x, mode = "top" ? T : B - h, , , bar)
        dockX := x
    }
}

OnExitMove(wParam, lParam, msg, hwnd) {
    if bar && hwnd = bar.Hwnd && mode != "float"
        SnapToEdge()
    if (bar && hwnd = bar.Hwnd) || (pad && hwnd = pad.Hwnd)
        SaveAll()
}

; ============================================================================
; Handwriting pad
; ============================================================================

TogglePad() {
    global padVisible
    if !pad {
        BuildPad()
        padVisible := true
    } else {
        padVisible := !padVisible
        if padVisible {
            pad.Show("NA")
        } else {
            SetTimer(DoRecognize, 0)
            DiscardInk()
            pad.Hide()
        }
    }
    SetActive(writeBtn, padVisible)
}

KeyboardButton(*) {
    ToggleTouchKeyboard()
    SetTimer(UpdateKeyboardState, -700)
}

BuildPad() {
    global pad, padGrip, altBtns, writeRect, inkPen, BTN_H, palmBtn
    barH := BTN_H, BTN_H := 44
    pad := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +Border", "PenBar Pad")
    pad.BackColor := "FFFFFF"
    pad.MarginX := 4, pad.MarginY := 4

    SetIconFont(pad)
    padGrip := pad.AddText("xm ym w" ICON_W " h" BTN_H " Center +0x200 cWhite Background" BTN, Chr(IC["move"]))
    padGrip.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , pad))

    altBtns := []
    loop 3 {
        b := MakeButton(pad, "", "", "x+4 yp", 104, AltFn(A_Index))
        ShowButton(b, false)
        altBtns.Push(b)
    }
    ; Backspace / Enter / Undo live on the bar; the pad keeps only its own tools.
    MakeButton(pad, "space", "Space",     "x+12 yp", 50, SpaceKey)
    MakeButton(pad, "clear", "Clear Ink", "x+4 yp",  66, (*) => (SetTimer(DoRecognize, 0), DiscardInk()))
    palmBtn := MakeButton(pad, "palm", "Palm Rejection", "x+12 yp", 100, TogglePalm)
    SetActive(palmBtn, palmReject)
    MakeButton(pad, "close", "",          "x+4 yp",  0,  (*) => TogglePad())

    pad.Show("Hide AutoSize")
    pad.GetClientPos(, , &cw)                 ; logical width of the button row
    pad.Show("Hide w" Max(cw, 640) " h" (BTN_H + 8 + PAD_H))
    BTN_H := barH
    WinGetPos(, , &w, &h, pad)
    MonitorGetWorkArea(, &L, &T, &R, &B)
    x := (padX = "") ? L + (R - L - w) // 2 : Max(L, Min(Integer(padX), R - w))
    y := (padY = "") ? B - h - 12 : Max(T, Min(Integer(padY), B - h))
    pad.Show("NA x" x " y" y)

    ; Writing area (physical client pixels): everything below the button row.
    rc := Buffer(16), pt := Buffer(8)
    DllCall("GetWindowRect", "ptr", padGrip.Hwnd, "ptr", rc)
    NumPut("int", NumGet(rc, 0, "int"), "int", NumGet(rc, 12, "int"), pt)
    DllCall("ScreenToClient", "ptr", pad.Hwnd, "ptr", pt)
    DllCall("GetClientRect", "ptr", pad.Hwnd, "ptr", rc)
    writeRect := {l: 0, t: NumGet(pt, 4, "int") + 2, r: NumGet(rc, 8, "int"), b: NumGet(rc, 12, "int")}

    ; Round-capped ink pen
    lb := Buffer(16, 0)
    NumPut("uint", 0, "uint", INK_COLOR, lb)                 ; BS_SOLID, color
    width := Max(2, Round(3 * A_ScreenDPI / 96))
    inkPen := DllCall("ExtCreatePen", "uint", 0x10000, "uint", width, "ptr", lb, "uint", 0, "ptr", 0, "ptr")
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
    if t = 2 && palmReject
        return 0                ; palm rejection: ignore palm / finger touches
    if t != 3 && t != 2
        return
    if msg = 0x246 {            ; pen down
        p := ScreenToPad(lParam)
        if !InWriteArea(p)
            return              ; let the system handle it
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
    global mouseInk
    if !pad || hwnd != pad.Hwnd
        return
    if (DllCall("GetMessageExtraInfo", "ptr") & 0xFFFFFF00) = 0xFF515700
        return 0                ; generated by pen/touch: already handled
    x := lParam << 48 >> 48, y := lParam << 32 >> 48
    p := [x, y]
    if msg = 0x201 && InWriteArea(p) {
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

; ---- strokes ---------------------------------------------------------------

BeginStroke(p) {
    global curStroke, inkDC
    SetTimer(DoRecognize, 0)          ; still writing: don't recognize yet
    curStroke := [p]
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
    if pad
        DllCall("InvalidateRect", "ptr", pad.Hwnd, "ptr", 0, "int", 1)
}

; Each batch of strokes is taken off the pad before recognizing, so it can
; never be recognized (and typed) twice.
DoRecognize() {
    global strokes, curStroke, recognizing, curAlts
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
        curAlts := alts
        ShowAlts()
    }
    recognizing := false
    if strokes.Length && !curStroke        ; more was written meanwhile
        SetTimer(DoRecognize, -delayMs)
}

ShowAlts() {
    for i, b in altBtns {
        if i <= curAlts.Length
            b.label.Text := curAlts[i], ShowButton(b, true)
        else
            ShowButton(b, false)
    }
}

AltFn(i) {
    return (*) => AltPick(i)
}

; Replace the last word written with the suggestion that was tapped.
AltPick(i) {
    global hist, curAlts
    if i > curAlts.Length
        return
    EnsureTarget()
    if !(hist.Length && HistValid())
        return
    old := hist.Pop()
    Send("{Backspace " StrLen(old.s) "}")
    if old.removed != ""
        SendText(old.removed)
    newText := curAlts[i]
    curAlts[i] := Trim(old.s)
    InsertText(newText)
    ShowAlts()
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
    if pad
        ShowAlts()
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
    tm.Add("Floating bar", (*) => SetMode("float"))
    tm.Add()
    tm.Add("Add a space after each word", ToggleAutoSpace)
    tm.Add("Undo outside the pad deletes last word (not Ctrl+Z)", ToggleUndoWord)
    tm.Add("Minimize bar when the keyboard is attached", ToggleAutoMin)
    tm.Add("Start with Windows", ToggleStartup)
    delayMenu := Menu()
    for ms, name in DELAYS
        delayMenu.Add(name, SetDelayFn(ms))
    tm.Add("Type text after a pause of", delayMenu)
    tm.Add("Reset bar and pad positions", ResetPositions)
    UpdateTrayChecks()
}

SetDelayFn(ms) => (*) => SetDelay(ms)

UpdateTrayChecks() {
    tm := A_TrayMenu
    (mode = "right") ? tm.Check("Dock bar on right edge") : tm.Uncheck("Dock bar on right edge")
    (mode = "top") ? tm.Check("Dock bar on top edge") : tm.Uncheck("Dock bar on top edge")
    (mode = "bottom") ? tm.Check("Dock bar on bottom edge") : tm.Uncheck("Dock bar on bottom edge")
    autoMin ? tm.Check("Minimize bar when the keyboard is attached") : tm.Uncheck("Minimize bar when the keyboard is attached")
    startup ? tm.Check("Start with Windows") : tm.Uncheck("Start with Windows")
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
        if mode = "right"
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
