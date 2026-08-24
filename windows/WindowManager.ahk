#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\VD.ah2

ListLines 0
SendMode "Input"
SetWorkingDir A_ScriptDir
KeyHistory 0
#WinActivateForce
ProcessSetPriority "H"
SetWinDelay -1
SetControlDelay -1

global DESKTOP_CLASSES := ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"]

global lastFocusedHwnd := 0
global lastFocusedMonitor := 1
SetTimer(TrackFocus, 100)

; ============================================================
; Helpers
; ============================================================

IsDesktopClass(class) {
    global DESKTOP_CLASSES
    for cls in DESKTOP_CLASSES {
        if class = cls
            return true
    }
    return false
}

IsVisibleAppWindow(hwnd) {
    if WinGetMinMax(hwnd) = -1
        return false
    if WinGetTitle(hwnd) = ""
        return false
    if !(WinGetStyle(hwnd) & 0x10000000)
        return false
    return true
}

SortByKey(arr, key, key2 := "", key3 := "") {
    n := arr.Length
    if n <= 1
        return
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            a := arr[j], b := arr[j+1]
            swap := false
            if a.%key% > b.%key%
                swap := true
            else if a.%key% = b.%key% {
                if key2 != "" && a.%key2% > b.%key2%
                    swap := true
                else if key2 != "" && a.%key2% = b.%key2% && key3 != "" && a.%key3% > b.%key3%
                    swap := true
            }
            if swap {
                arr[j] := b
                arr[j+1] := a
            }
        }
    }
}

GetWindowMonitor(hwnd) {
    monitor := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2)
    if monitor = 0
        return 1
    loop MonitorGetCount() {
        MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        pt := Buffer(8, 0)
        NumPut("Int", mLeft, pt, 0)
        NumPut("Int", mTop, pt, 4)
        monHandle := DllCall("MonitorFromPoint", "Int64", NumGet(pt, 0, "Int64"), "UInt", 1)
        if monHandle = monitor
            return A_Index
    }
    return 1
}

GetSortedMonitors() {
    monitors := []
    count := MonitorGetCount()
    loop count {
        MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        monitors.Push({index: A_Index, top: mTop, left: mLeft, right: mRight, bottom: mBottom})
    }
    SortByKey(monitors, "top", "left")
    return monitors
}

FindMonitorIndex(monitors, rawIndex) {
    for i, mon in monitors {
        if mon.index = rawIndex
            return i
    }
    return 0
}

GetWindowsOnDesktop(desktopNum, monitorIndex := 0) {
    windows := []
    for hwnd in WinGetList() {
        if !IsVisibleAppWindow(hwnd)
            continue
        try {
            dn := VD.getDesktopNumOfWindow("ahk_id " hwnd)
            if dn != desktopNum
                continue
            if monitorIndex != 0 && GetWindowMonitor(hwnd) != monitorIndex
                continue
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            cx := x + w // 2
            cy := y + h // 2
            windows.Push({hwnd: hwnd, x: x, y: y, w: w, h: h, cx: cx, cy: cy})
        } catch {
            continue
        }
    }
    return windows
}

GetCurrentDesktop() {
    try {
        hwnd := WinGetID("A")
        if hwnd != 0 {
            try {
                if VD.IsWindowPinned("ahk_id " hwnd)
                    return VD.getCurrentDesktopNum()
            }
            return VD.getDesktopNumOfWindow("ahk_id " hwnd)
        }
    } catch {
    }
    try {
        return VD.getCurrentDesktopNum()
    } catch {
        return 1
    }
}

; ============================================================
; Focus tracking
; ============================================================

TrackFocus() {
    global lastFocusedHwnd, lastFocusedMonitor
    try {
        hwnd := WinGetID("A")
        if hwnd = 0
            return
        class := WinGetClass("ahk_id " hwnd)
        if IsDesktopClass(class)
            return
        if WinExist("ahk_id " hwnd) {
            lastFocusedHwnd := hwnd
            lastFocusedMonitor := GetWindowMonitor(hwnd)
        }
    } catch {
        return
    }
}

GetActiveOrLast() {
    global lastFocusedHwnd, lastFocusedMonitor
    hwnd := 0
    isDesktop := false

    try {
        hwnd := WinGetID("A")
        if hwnd != 0 {
            class := WinGetClass("ahk_id " hwnd)
            if IsDesktopClass(class)
                isDesktop := true
        } else {
            isDesktop := true
        }
    } catch {
        isDesktop := true
    }

    if !isDesktop
        return {hwnd: hwnd, restored: false}

    if lastFocusedHwnd != 0 && WinExist("ahk_id " lastFocusedHwnd) {
        try {
            WinActivate("ahk_id " lastFocusedHwnd)
            return {hwnd: lastFocusedHwnd, restored: true}
        }
    }

    currentDesktop := GetCurrentDesktop()
    for hwnd in WinGetList() {
        if !IsVisibleAppWindow(hwnd)
            continue
        try {
            desktopNum := VD.getDesktopNumOfWindow("ahk_id " hwnd)
            if desktopNum != currentDesktop
                continue
            if GetWindowMonitor(hwnd) = lastFocusedMonitor {
                WinActivate("ahk_id " hwnd)
                return {hwnd: hwnd, restored: true}
            }
        } catch {
            continue
        }
    }

    return {hwnd: 0, restored: false}
}

; ============================================================
; Focus cycling by horizontal position (same monitor only)
; ============================================================
^!#a:: CycleWindows(-1)
^!#d:: CycleWindows(1)

CycleWindows(direction) {
    currentDesktop := GetCurrentDesktop()
    result := GetActiveOrLast()
    if result.restored || result.hwnd = 0
        return
    activeHwnd := result.hwnd
    activeMonitor := GetWindowMonitor(activeHwnd)

    windows := GetWindowsOnDesktop(currentDesktop, activeMonitor)
    if windows.Length = 0
        return

    SortByKey(windows, "cx", "cy", "hwnd")

    currentIndex := 0
    for i, win in windows {
        if win.hwnd = activeHwnd {
            currentIndex := i
            break
        }
    }

    if currentIndex = 0 {
        targetIndex := direction > 0 ? 1 : windows.Length
        WinActivate("ahk_id " windows[targetIndex].hwnd)
        return
    }

    nextIndex := Mod(currentIndex - 1 + direction + windows.Length, windows.Length) + 1
    WinActivate("ahk_id " windows[nextIndex].hwnd)
}

; ============================================================
; Focus other monitor (topmost window on that monitor)
; ============================================================
^!#w:: FocusMonitor(-1)
^!#s:: FocusMonitor(1)

FocusMonitor(direction) {
    currentDesktop := GetCurrentDesktop()
    result := GetActiveOrLast()
    if result.hwnd = 0
        return
    activeMonitor := GetWindowMonitor(result.hwnd)

    monitors := GetSortedMonitors()

    currentIndex := FindMonitorIndex(monitors, activeMonitor)
    if currentIndex = 0
        return

    targetIndex := currentIndex + direction
    if targetIndex < 1 || targetIndex > monitors.Length
        return

    target := monitors[targetIndex]

    windows := GetWindowsOnDesktop(currentDesktop, target.index)
    if windows.Length > 0
        WinActivate("ahk_id " windows[1].hwnd)
}

; ============================================================
; Toggle maximize
; ============================================================
^!#m:: {
    try {
        if WinGetMinMax("A") = 1
            WinRestore("A")
        else
            WinMaximize("A")
    }
}

; ============================================================
; Move window to monitor above/below
; ============================================================
^#+,:: MoveToMonitor(-1)
^#+.:: MoveToMonitor(1)

MoveToMonitor(direction) {
    try {
        hwnd := WinGetID("A")
    } catch {
        return
    }
    if hwnd = 0
        return

    wasMaximized := WinGetMinMax("ahk_id " hwnd) = 1
    if wasMaximized
        WinRestore("ahk_id " hwnd)

    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)

    monitors := GetSortedMonitors()

    currentMonitor := FindMonitorIndex(monitors, GetWindowMonitor(hwnd))
    if currentMonitor = 0
        return

    targetIndex := currentMonitor + direction
    if targetIndex < 1 || targetIndex > monitors.Length
        return

    source := monitors[currentMonitor]
    target := monitors[targetIndex]

    sourceW := source.right - source.left
    sourceH := source.bottom - source.top
    targetW := target.right - target.left
    targetH := target.bottom - target.top

    relX := sourceW > 0 ? (x - source.left) / sourceW : 0.5
    relY := sourceH > 0 ? (y - source.top) / sourceH : 0.5

    newX := target.left + Round(relX * targetW)
    newY := target.top + Round(relY * targetH)

    if newX + w > target.right
        newX := target.right - w
    if newY + h > target.bottom
        newY := target.bottom - h
    if newX < target.left
        newX := target.left
    if newY < target.top
        newY := target.top

    WinMove(newX, newY, w, h, "ahk_id " hwnd)
    WinActivate("ahk_id " hwnd)

    if wasMaximized
        WinMaximize("ahk_id " hwnd)
}

; ============================================================
; Go to next/prev desktop (fast, via VD)
; ============================================================
^#+z:: GoToRelativeDesktop(-1)
^#+x:: GoToRelativeDesktop(1)

GoToRelativeDesktop(direction) {
    try {
        VD.gotoRelativeDesktopNum(direction)
    } catch {
        return
    }
}

; ============================================================
; Move window left/right desktop and follow
; ============================================================
^!#z:: MoveToRelativeDesktop(-1)
^!#x:: MoveToRelativeDesktop(1)

MoveToRelativeDesktop(direction) {
    try {
        hwnd := WinGetID("A")
        currentDesktop := VD.getCurrentDesktopNum()
        targetDesktop := VD.getRelativeDesktopNum(currentDesktop, direction)
        pView := VD._dll_GetViewForHwnd(hwnd)
        IVirtualDesktop := VD._GetDesktops_Obj().GetAt(targetDesktop)
        VD._dll_MoveViewToDesktop(pView, IVirtualDesktop)
        VD.goToDesktopNum(targetDesktop, false)
        WinActivate("ahk_id " hwnd)
    } catch {
        return
    }
}

; ============================================================
; Move window to specific desktop and follow
; ============================================================
^!#1:: MoveToDesktop(1)
^!#2:: MoveToDesktop(2)
^!#3:: MoveToDesktop(3)
^!#4:: MoveToDesktop(4)
^!#5:: MoveToDesktop(5)
^!#6:: MoveToDesktop(6)
^!#7:: MoveToDesktop(7)
^!#8:: MoveToDesktop(8)

MoveToDesktop(num) {
    try {
        if num > VD.getCount()
            return
        hwnd := WinGetID("A")
        pView := VD._dll_GetViewForHwnd(hwnd)
        IVirtualDesktop := VD._GetDesktops_Obj().GetAt(num)
        VD._dll_MoveViewToDesktop(pView, IVirtualDesktop)
        VD.goToDesktopNum(num, false)
        WinActivate("ahk_id " hwnd)
    } catch {
        return
    }
}

; ============================================================
; Go to desktop (no window move) - Shift+Win+Alt+1-8
; ============================================================
+#!1:: GoToDesktop(1)
+#!2:: GoToDesktop(2)
+#!3:: GoToDesktop(3)
+#!4:: GoToDesktop(4)
+#!5:: GoToDesktop(5)
+#!6:: GoToDesktop(6)
+#!7:: GoToDesktop(7)
+#!8:: GoToDesktop(8)

GoToDesktop(num) {
    try {
        if num > VD.getCount()
            return
        VD.goToDesktopNum(num)
    } catch {
        return
    }
}

; ============================================================
; Pin/unpin window to all desktops + always on top
; ============================================================
#+e:: TogglePinWindow()

TogglePinWindow() {
    try {
        hwnd := WinGetID("A")
        if hwnd = 0
            return
        if VD.IsWindowPinned("ahk_id " hwnd) {
            VD.UnPinWindow("ahk_id " hwnd)
            WinSetAlwaysOnTop(0, "ahk_id " hwnd)
            ToolTip("Unpinned")
        } else {
            VD.PinWindow("ahk_id " hwnd)
            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
            ToolTip("Pinned + always on top")
        }
        SetTimer(() => ToolTip(), -1500)
    } catch {
        return
    }
}
