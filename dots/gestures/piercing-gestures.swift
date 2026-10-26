// GitHub.com/PiercingXX
// piercing-gestures: the Hyprland touchpad gestures (hyprland/keybinds.lua),
// for AeroSpace on the built-in trackpad:
//   3 fingers left/right  next/previous workspace   (gesture ... "workspace")
//   3 fingers up          piercing-launcher (wm-app-launcher.sh, ulauncher)
//   4 fingers down        close the focused window  (gesture ... "close")
// for AeroSpace or Rift, whichever is running. Under Rift, left/right go
// through wm-workspace-swipe.sh, which skips unused workspaces and opens one
// new one past the last, like Hyprland.
// Reads trackpad touches from an event tap, so it needs Accessibility.
// macOS's own 3-finger swipes and 4-finger vertical swipes are turned off by
// modules/wm.sh so they don't fire alongside these. With them off, macOS hands
// a 3-finger swipe to apps as a sideways scroll, and Waterfox goes back a
// page: scrolling is swallowed while 3+ fingers are down, momentum included.
//
//   piercing-gestures           run (launchd: com.piercingxx.gestures)
//   piercing-gestures --debug   also print every gesture it sees

import AppKit
import ApplicationServices

// Fraction of the trackpad the fingers must travel, and how much more the
// main direction must be than the other one, before a swipe counts
let horizontalTravel: CGFloat = 0.12
let verticalTravel: CGFloat = 0.15
let dominance: CGFloat = 2.0

let debug = CommandLine.arguments.contains("--debug")

func log(_ message: String) {
    if debug { FileHandle.standardError.write((message + "\n").data(using: .utf8)!) }
}

func run(_ command: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    p.environment = env
    try? p.run()
}

enum Swipe { case left, right, up, down }

func act(_ swipe: Swipe, fingers: Int) {
    log("swipe \(swipe) with \(fingers) fingers")
    switch (fingers, swipe) {
    // Fingers move left -> the next workspace slides in from the right.
    // AeroSpace refuses next/prev with a non-tty stdin unless told to ignore it.
    case (3, .left):  run("if pgrep -xq rift; then ~/.scripts/Control-Scripts/wm-workspace-swipe.sh next; else aerospace workspace --no-stdin next; fi")
    case (3, .right): run("if pgrep -xq rift; then ~/.scripts/Control-Scripts/wm-workspace-swipe.sh prev; else aerospace workspace --no-stdin prev; fi")
    case (3, .up):    run("~/.local/bin/piercing-launcher --toggle")
    case (4, .down):  run("if pgrep -xq rift; then rift-cli execute window close; else aerospace close; fi")
    default: break
    }
}

// One swipe per touch. Each finger is measured from where it landed, so the
// count flickering (3 -> 2 -> 3 mid-swipe) doesn't restart the measurement;
// fire once, then wait for every finger to lift
var landed: [AnyHashable: CGPoint] = [:]
var fingers = 0
var fired = false

func handle(_ touches: Set<NSTouch>) {
    // Some gesture events carry no touches at all; they say nothing
    if touches.isEmpty { return }
    let live = touches.filter { !$0.isResting && $0.phase != .ended && $0.phase != .cancelled }
    if live.isEmpty {
        landed.removeAll()
        fingers = 0
        fired = false
        return
    }
    fingers = max(fingers, live.count)
    if fired { return }

    var dx: CGFloat = 0, dy: CGFloat = 0
    for t in live {
        let key = AnyHashable(t.identity as! NSObject)
        let p = t.normalizedPosition
        let s = landed[key] ?? p
        landed[key] = s
        dx += p.x - s.x
        dy += p.y - s.y
    }
    dx /= CGFloat(live.count)
    dy /= CGFloat(live.count)
    if debug { log(String(format: "  %d fingers, dx %.3f dy %.3f", fingers, dx, dy)) }

    if abs(dx) > horizontalTravel && abs(dx) > dominance * abs(dy) {
        fired = true
        act(dx < 0 ? .left : .right, fingers: fingers)
    } else if abs(dy) > verticalTravel && abs(dy) > dominance * abs(dx) {
        fired = true
        // normalizedPosition y grows towards the top of the trackpad
        act(dy > 0 ? .up : .down, fingers: fingers)
    }
}

var tap: CFMachPort?
// Set by a swallowed scroll; its momentum (after the fingers lift) goes too
var swallowing = false

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .scrollWheel {
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        if fingers >= 3 || (swallowing && momentum) {
            swallowing = true
            return nil
        }
        swallowing = false
        return Unmanaged.passUnretained(event)
    }
    if let ns = NSEvent(cgEvent: event) {
        let touches = ns.allTouches()
        if debug && !touches.isEmpty { log("event: \(touches.count) touches") }
        handle(touches)
    }
    return Unmanaged.passUnretained(event)
}

func startTap() -> Bool {
    let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        | CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
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

// Ask once (adds us to Privacy > Accessibility), then keep retrying so the
// gestures start working as soon as the switch is flipped, without a restart
let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(prompt) || !startTap() {
    log("waiting for Accessibility permission")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        if AXIsProcessTrusted() && startTap() { timer.invalidate() }
    }
}

app.run()
