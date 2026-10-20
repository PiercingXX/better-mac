// GitHub.com/PiercingXX
// piercing-menubar: keeps the auto-hidden macOS menu bar from sliding down
// over SketchyBar. macOS can't remove the menu bar, only hide it, and it
// comes back whenever the pointer touches the top edge of a screen. This
// stops the pointer a few pixels short of that edge, so SketchyBar can still
// be clicked but the menu bar never sees the pointer arrive.
// Moves the pointer from an event tap, so it needs Accessibility.
//
//   piercing-menubar           run (launchd: com.piercingxx.menubar)
//   piercing-menubar --debug   also print every time it holds the pointer back

import AppKit
import ApplicationServices

// Points kept clear at the top of each screen. macOS reveals the menu bar
// with the pointer 3pt or less from the top edge (measured on Tahoe)
let margin: CGFloat = 5

let debug = CommandLine.arguments.contains("--debug")

func log(_ message: String) {
    if debug { FileHandle.standardError.write((message + "\n").data(using: .utf8)!) }
}

// Global display coordinates: origin at the main display's top-left, y grows
// downwards. Refreshed whenever displays are added, removed or rearranged.
var screens: [CGRect] = []

func loadScreens() {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    screens = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    log("screens: \(screens)")
}

// Where the pointer may go: below the top margin of the screen it's on,
// unless another screen sits right above (then the edge isn't a top edge)
func clamp(_ p: CGPoint) -> CGPoint? {
    guard let s = screens.first(where: { $0.contains(p) }) else { return nil }
    if p.y >= s.minY + margin { return nil }
    let above = CGPoint(x: p.x, y: s.minY - 1)
    if screens.contains(where: { $0.contains(above) }) { return nil }
    return CGPoint(x: p.x, y: s.minY + margin)
}

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if let p = clamp(event.location) {
        log(String(format: "held at y %.0f (wanted %.1f)", p.y, event.location.y))
        event.location = p
        CGWarpMouseCursorPosition(p)
    }
    return Unmanaged.passUnretained(event)
}

func startTap() -> Bool {
    let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                    options: .defaultTap, eventsOfInterest: mask,
                                    callback: callback, userInfo: nil) else { return false }
    tap = t
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    log("listening")
    return true
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

// A warp normally freezes local mouse events for a quarter second
CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0

loadScreens()
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: nil, queue: .main) { _ in loadScreens() }

// Ask once (adds us to Privacy > Accessibility), then keep retrying so it
// starts working as soon as the switch is flipped, without a restart
let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(prompt) || !startTap() {
    log("waiting for Accessibility permission")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        if AXIsProcessTrusted() && startTap() { timer.invalidate() }
    }
}

app.run()
