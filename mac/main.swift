import AppKit
import ApplicationServices

private struct Options {
    let duration: TimeInterval?
    let keyboardOnly: Bool

    init?(arguments: [String]) {
        var duration: TimeInterval?
        var keyboardOnly = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--solo-teclado":
                keyboardOnly = true
            case "--minutos":
                index += 1
                guard index < arguments.count,
                      let minutes = Double(arguments[index]),
                      minutes.isFinite, minutes > 0, minutes <= 1440 else {
                    return nil
                }
                duration = minutes * 60
            default:
                return nil
            }
            index += 1
        }

        self.duration = duration
        self.keyboardOnly = keyboardOnly
    }
}

private final class PillView: NSView {
    var unlock: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 27, yRadius: 27).fill()

        let title = "🔒 BabyLock"
        let subtitle = "Doble clic para desbloquear"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(calibratedWhite: 0.83, alpha: 1)
        ]

        let titleSize = title.size(withAttributes: titleAttributes)
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        title.draw(at: NSPoint(x: (bounds.width - titleSize.width) / 2, y: 29),
                   withAttributes: titleAttributes)
        subtitle.draw(at: NSPoint(x: (bounds.width - subtitleSize.width) / 2, y: 10),
                      withAttributes: subtitleAttributes)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            unlock?()
        }
    }
}

private final class LockController: NSObject, NSApplicationDelegate {
    private let options: Options
    private var window: NSPanel?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var unlockTimer: Timer?

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let accessibilityKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([accessibilityKey: true] as CFDictionary) else {
            let alert = NSAlert()
            alert.messageText = "BabyLock necesita Accesibilidad"
            alert.informativeText = "Permití BabyLock en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad. Después, abrila de nuevo."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let size = NSSize(width: 226, height: 54)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let frame = NSRect(x: screen.maxX - size.width - 20,
                           y: screen.maxY - size.height - 20,
                           width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        let pill = PillView(frame: NSRect(origin: .zero, size: size))
        pill.unlock = { NSApp.terminate(nil) }
        panel.contentView = pill
        panel.orderFrontRegardless()
        window = panel

        var eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        eventTypes.append(CGEventType(rawValue: 14)!)
        if !options.keyboardOnly {
            eventTypes += [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                           .otherMouseDown, .otherMouseUp, .scrollWheel]
        }
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: eventCallback, userInfo: context) else {
            let alert = NSAlert()
            alert.messageText = "No se pudo activar el bloqueo"
            alert.informativeText = "Revisá el permiso de Accesibilidad y abrí BabyLock otra vez."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        if let duration = options.duration {
            unlockTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unlockTimer?.invalidate()
        if let source = eventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
    }

    fileprivate func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if eventType == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == 11,
           event.flags.contains([.maskControl, .maskAlternate, .maskCommand]) {
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return nil
        }

        if !options.keyboardOnly,
           [.leftMouseDown, .leftMouseUp].contains(eventType),
           let window, window.frame.contains(event.location) {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }
}

private let eventCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<LockController>.fromOpaque(context).takeUnretainedValue()
    return controller.handle(eventType: type, event: event)
}

guard let options = Options(arguments: Array(CommandLine.arguments.dropFirst())) else {
    fputs("Uso: BabyLock [--minutos N] [--solo-teclado]\n", stderr)
    exit(2)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
private let controller = LockController(options: options)
application.delegate = controller
application.run()
