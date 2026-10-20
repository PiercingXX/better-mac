// GitHub.com/PiercingXX
// piercing-notify: Linux-style notification popups (mako/swaync look) for the
// ~/.scripts notifiers, in place of macOS Notification Center banners. Each
// call shows one popup at the top right, under SketchyBar, on every
// workspace, and exits when it closes. Popups with the same key replace each
// other (notify-send's replace id), several stack downwards, a click
// dismisses one. Needs no permissions.
//
//   piercing-notify [--key K] [--timeout MS] [--urgency low|normal|critical] SUMMARY [BODY]
//   (timeout 0 = until clicked; scripts call it through notify_replace in
//    ~/.scripts/lib/common.sh)

import AppKit

let width: CGFloat = 340
let margin: CGFloat = 10       // from the screen edge and SketchyBar
let spacing: CGFloat = 8       // between stacked popups
let maxHeight: CGFloat = 120   // tallest popup (title 2 lines + body 4)
let fontName = "JetBrainsMono Nerd Font"

// ---- Arguments ----
var key = ""
var timeout = 5000
var urgency = "normal"
var texts: [String] = []
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--key": key = args.next() ?? ""
    case "--timeout": timeout = Int(args.next() ?? "") ?? timeout
    case "--urgency": urgency = args.next() ?? urgency
    default: texts.append(a)
    }
}
guard let summary = texts.first else {
    print("usage: piercing-notify [--key K] [--timeout MS] [--urgency low|normal|critical] SUMMARY [BODY]")
    exit(2)
}
let body = texts.count > 1 ? texts[1] : ""

// ---- Replace and stack bookkeeping: one file per popup in $TMPDIR ----
let stateDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("piercing-notify")
try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
let me = getpid()

// key-* files hold a pid, slot-* files "pid height"
func fields(_ url: URL) -> [String] {
    ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}
func alive(_ pid: pid_t) -> Bool { pid > 0 && kill(pid, 0) == 0 }
func pid(in url: URL) -> pid_t { pid_t(fields(url).first ?? "") ?? 0 }
func slotURL(_ s: Int) -> URL { stateDir.appendingPathComponent("slot-\(s)") }

// The popup this one replaces gives up its slot to it
var slot = -1
if !key.isEmpty {
    let keyFile = stateDir.appendingPathComponent("key-" + key.replacingOccurrences(of: "/", with: "_"))
    let old = pid(in: keyFile)
    if old != me && alive(old) {
        for s in 0..<10 where pid(in: slotURL(s)) == old {
            slot = s
        }
        kill(old, SIGTERM)
    }
    try? "\(me)".write(to: keyFile, atomically: true, encoding: .utf8)
}
// Otherwise the first slot nobody living holds
if slot < 0 {
    slot = (0..<10).first { !alive(pid(in: slotURL($0))) } ?? 0
}
let slotFile = slotURL(slot)

func cleanUp() {
    if pid(in: slotFile) == me { try? FileManager.default.removeItem(at: slotFile) }
}

// ---- The popup ----
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func font(_ size: CGFloat, bold: Bool) -> NSFont {
    let f = NSFont(name: fontName + (bold ? " Bold" : ""), size: size)
    return f ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
}

func label(_ text: String, _ f: NSFont, _ color: NSColor, lines: Int) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = f
    l.textColor = color
    // Wrap, and only cut the last line that fits
    l.maximumNumberOfLines = lines
    l.lineBreakMode = .byWordWrapping
    l.cell?.truncatesLastVisibleLine = true
    l.preferredMaxLayoutWidth = width - 28
    return l
}

let title = label(summary, font(13.6, bold: true), .white, lines: 2)
let text = label(body, font(12.5, bold: false), NSColor(white: 0.78, alpha: 1), lines: 4)
let stack = NSStackView(views: body.isEmpty ? [title] : [title, text])
stack.orientation = .vertical
stack.alignment = .leading
stack.spacing = 4
stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
let height = min(stack.fittingSize.height, maxHeight)
try? "\(me) \(Int(height))".write(to: slotFile, atomically: true, encoding: .utf8)
// Below the popups still showing in the slots above this one
let above = (0..<slot).reduce(CGFloat(0)) { sum, s in
    let f = fields(slotURL(s))
    guard let p = pid_t(f.first ?? ""), alive(p), f.count > 1, let h = Double(f[1]) else { return sum }
    return sum + CGFloat(h) + spacing
}

class Popup: NSPanel {
    override var canBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) { close(animated: true) }
    func close(animated: Bool) {
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = animated ? 0.15 : 0
            animator().alphaValue = 0
        }, completionHandler: { cleanUp(); exit(0) })
    }
}

let screen = NSScreen.main ?? NSScreen.screens[0]
// Below the notch strip SketchyBar sits in
let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) - margin
let frame = NSRect(x: screen.frame.maxX - width - margin,
                   y: top - height - above,
                   width: width, height: height)
let panel = Popup(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered, defer: false)
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.alphaValue = 0

// #1e1e1e like the bar, border white for critical, #414141 (inactive border) otherwise
let box = NSView(frame: NSRect(origin: .zero, size: frame.size))
box.wantsLayer = true
box.layer?.backgroundColor = NSColor(white: 0.118, alpha: 0.96).cgColor
box.layer?.cornerRadius = 10
box.layer?.borderWidth = urgency == "critical" ? 2 : 1
box.layer?.borderColor = (urgency == "critical" ? NSColor.white : NSColor(white: 0.255, alpha: 1)).cgColor
stack.frame = box.bounds
stack.autoresizingMask = [.width, .height]
box.addSubview(stack)
panel.contentView = box
panel.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { c in
    c.duration = 0.15
    panel.animator().alphaValue = 1
}

// Replaced by a newer popup with the same key: vanish at once
signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { panel.close(animated: false) }
term.resume()

if timeout > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeout)) { panel.close(animated: true) }
}
app.run()
