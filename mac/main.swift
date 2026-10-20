import Cocoa
import ApplicationServices

// ===== Config =====
let UNLOCK_KEYCODE: Int64 = 11 // tecla B (de bebé)
let COMBO_TEXT = "⌃⌥⌘B"

let testMode = CommandLine.arguments.contains("--test")
let keyboardOnly = CommandLine.arguments.contains("--solo-teclado")
var autoUnlockSeconds: Double? = nil
if let i = CommandLine.arguments.firstIndex(of: "--minutos"),
   i + 1 < CommandLine.arguments.count,
   let m = Double(CommandLine.arguments[i + 1]), m > 0 {
    autoUnlockSeconds = m * 60
}

var eventTap: CFMachPort?
var overlayWindow: NSWindow?
var lastFlags: CGEventFlags = []
var pillRectCG = CGRect.zero // rect de la pastilla en coords CG: única zona clickeable

// Tipos de evento de mouse/trackpad (rawValues de CGEventType/NSEvent)
let clickTypes: Set<UInt32> = [1, 2, 3, 4, 6, 7, 25, 26, 27] // downs, ups y drags de todos los botones
let gestureTypes: Set<UInt32> = [18, 19, 20, 29, 30, 31, 32, 33, 34] // rotate, gesture, magnify, swipe, smartMagnify, quickLook, pressure
let scrollType: UInt32 = 22
// mouseMoved (5) pasa siempre: mover el cursor no rompe nada y permite apuntar a la pastilla

func playSound(_ name: String) {
    guard !testMode else { return }
    NSSound(named: name)?.play()
}

func unlockAndQuit(_ reason: String) {
    if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    overlayWindow?.orderOut(nil)
    print("desbloqueado (\(reason))")
    if testMode { print("TEST OK"); exit(0) }
    playSound("Glass")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
}

// ===== Event tap: se traga teclado y mouse salvo el combo y la pastilla =====
let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return nil
    }
    if type == .flagsChanged {
        lastFlags = event.flags
        return nil
    }
    if type == .keyDown {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.union(lastFlags)
        if code == UNLOCK_KEYCODE,
           flags.contains(.maskControl),
           flags.contains(.maskAlternate),
           flags.contains(.maskCommand) {
            DispatchQueue.main.async { unlockAndQuit("combo") }
        }
        return nil
    }
    if type == .keyUp {
        return nil
    }
    if type.rawValue == 14 { // NSSystemDefined: volumen, brillo, play/pausa
        if let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
    if !keyboardOnly {
        let raw = type.rawValue
        if clickTypes.contains(raw) {
            // clicks solo dentro de la pastilla (ahí vive el doble click de escape)
            if pillRectCG.insetBy(dx: -4, dy: -4).contains(event.location) {
                return Unmanaged.passUnretained(event)
            }
            return nil
        }
        if raw == scrollType || gestureTypes.contains(raw) {
            return nil
        }
    }
    return Unmanaged.passUnretained(event)
}

// ===== Pastilla flotante (doble click = desbloquear) =====
final class PillView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { unlockAndQuit("doble click") }
    }
}

func cgRectFromAppKit(_ r: NSRect) -> CGRect {
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.origin.x, y: primaryH - r.maxY, width: r.width, height: r.height)
}

func showOverlay() {
    let label = NSTextField(labelWithString: "🔒 \(COMBO_TEXT) o doble click acá")
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .white
    label.sizeToFit()
    let padX: CGFloat = 16, padY: CGFloat = 8
    let w = label.frame.width + padX * 2
    let h = label.frame.height + padY * 2
    guard let screen = NSScreen.main else { return }
    let f = screen.visibleFrame
    let rect = NSRect(x: f.maxX - w - 16, y: f.maxY - h - 12, width: w, height: h)

    let panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let pill = PillView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    pill.wantsLayer = true
    pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    pill.layer?.cornerRadius = h / 2
    label.setFrameOrigin(NSPoint(x: padX, y: padY))
    pill.addSubview(label)
    panel.contentView = pill
    panel.orderFrontRegardless()
    overlayWindow = panel
    pillRectCG = cgRectFromAppKit(panel.frame)
}

// ===== Main =====
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if !testMode, let bid = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty { print("BabyLock ya está corriendo"); exit(0) }
}

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptKey: !testMode] as CFDictionary)
if !trusted {
    print("NO PERMISSION: falta Accesibilidad")
    if !testMode {
        let a = NSAlert()
        a.messageText = "BabyLock necesita permiso de Accesibilidad"
        a.informativeText = "En Ajustes del Sistema → Privacidad y seguridad → Accesibilidad, activá BabyLock (si ya figura activado, desactivalo y activalo de nuevo). Después volvé a abrir la app (Spotlight → BabyLock)."
        a.addButton(withTitle: "Abrir Ajustes")
        a.addButton(withTitle: "Cerrar")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    exit(3)
}

func bit(_ t: CGEventType) -> CGEventMask { CGEventMask(1) << CGEventMask(t.rawValue) }
var mask: CGEventMask = bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged) | (CGEventMask(1) << 14)
if !keyboardOnly {
    for r in clickTypes.union(gestureTypes).union([scrollType]) {
        mask |= CGEventMask(1) << CGEventMask(r)
    }
}

eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                             place: .headInsertEventTap,
                             options: .defaultTap,
                             eventsOfInterest: mask,
                             callback: tapCallback,
                             userInfo: nil)
guard let tap = eventTap, let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
    print("ERROR: no pude crear el event tap (¿permiso de Accesibilidad?)")
    exit(4)
}
CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

if testMode {
    print("TEST: tap creado (teclado\(keyboardOnly ? "" : " + mouse")), bloqueado; probando…")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        let p = CGPoint(x: 200, y: 200)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(UNLOCK_KEYCODE), keyDown: true)
        down?.flags = [.maskControl, .maskAlternate, .maskCommand]
        down?.post(tap: .cghidEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        print("TEST FAIL: el combo no destrabó")
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: false) }
        exit(2)
    }
} else {
    showOverlay()
    playSound("Pop")
    let alcance = keyboardOnly ? "teclado" : "teclado + trackpad/mouse (clicks solo en la pastilla)"
    print("🔒 Bloqueado: \(alcance). Desbloqueo: \(COMBO_TEXT) o doble click en la pastilla de arriba a la derecha.")
    if let s = autoUnlockSeconds {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { unlockAndQuit("timer") }
    }
}

app.run()
