// GitHub.com/PiercingXX
// piercing-launcher: Ulauncher for the Mac, in place of Sol. Option+Space
// (tapping Option sends it, via Karabiner) toggles a search bar on the screen
// with the pointer: apps by fuzzy match with the recent ones first, a
// calculator, ~ and / file browsing, and the g/so/wiki web shortcuts. Looks
// like piercing-dots' Ulauncher (Aura theme, 750 wide, 6 recent apps, closes
// on focus out). Needs no permissions.
//
//   piercing-launcher            the resident launcher (LaunchAgent com.piercingxx.launcher)
//   piercing-launcher --toggle   show or hide it (3-finger swipe up)
//
// Keys: Up/Down or Ctrl+J/K move, Enter runs, Option+1..9 runs that row,
// Tab completes a path, Option+Enter opens a folder in Finder, Esc closes.

import AppKit
import Carbon

let toggleName = Notification.Name("com.piercingxx.launcher.toggle")
if CommandLine.arguments.contains("--toggle") {
    DistributedNotificationCenter.default().postNotificationName(toggleName, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// ---- Look: piercing-dots dots/ulauncher Aura theme ----
func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let bgColor = rgba(36, 40, 59, 0.9)
let borderColor = rgba(42, 195, 222)
let inputColor = rgba(158, 206, 106)
let selectedBox = rgba(65, 72, 104, 0.8)
let nameColor = rgba(86, 95, 137)
let nameSelected = rgba(115, 218, 202)
let textColor = rgba(187, 154, 247)
let textSelected = rgba(255, 158, 100)
let matchColor = rgba(122, 162, 247)
let matchSelected = rgba(180, 249, 248)
let keyColor = rgba(224, 175, 104)
let keySelected = rgba(247, 118, 142)
let fontName = "JetBrainsMono Nerd Font"

let width: CGFloat = 750
let inputHeight: CGFloat = 64
let rowHeight: CGFloat = 54
let pad: CGFloat = 16
let maxRows = 9
let recentCount = 6

func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
    NSFont(name: fontName + (bold ? " Bold" : ""), size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
}

// ---- Results ----
enum Action {
    case app(String)        // path
    case open(URL)
    case browse(String)     // a directory: Enter walks into it
    case copy(String)
}

struct Item {
    var name: String
    var text: String
    var icon: NSImage
    var matches: [Int] = []  // Character offsets into name
    var action: Action
}

let home = NSHomeDirectory()
func abbreviate(_ path: String) -> String {
    path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

var icons: [String: NSImage] = [:]
func icon(_ path: String) -> NSImage {
    if let i = icons[path] { return i }
    let i = NSWorkspace.shared.icon(forFile: path)
    i.size = NSSize(width: 40, height: 40)
    icons[path] = i
    return i
}

// ---- Apps ----
struct App {
    let path: String
    let name: String
    let chars: [Character]
    let lower: [Character]
}
var apps: [App] = []
var lastScan = Date.distantPast
let appDirs = ["/Applications", "/System/Applications", home + "/Applications",
               "/System/Library/CoreServices/Applications"]

// Each dir's .apps and one folder down (Utilities, Steam's games)
func scanApps() -> [App] {
    let fm = FileManager.default
    var seen = Set<String>(), out: [App] = []
    func add(_ path: String) {
        guard seen.insert(path).inserted else { return }
        var name = fm.displayName(atPath: path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        out.append(App(path: path, name: name, chars: Array(name), lower: Array(name.lowercased())))
    }
    for dir in appDirs {
        for e in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !e.hasPrefix(".") {
            let p = dir + "/" + e
            if e.hasSuffix(".app") {
                add(p)
            } else {
                for s in (try? fm.contentsOfDirectory(atPath: p)) ?? [] where s.hasSuffix(".app") { add(p + "/" + s) }
            }
        }
    }
    add("/System/Library/CoreServices/Finder.app")
    return out
}

// ---- Launch history: recent apps and a frequency boost ----
let dataDir = home + "/.local/share/piercing-launcher"
let historyURL = URL(fileURLWithPath: dataDir + "/history.json")
struct Use: Codable {
    var count: Int
    var last: Double
}
var history: [String: Use] = (try? JSONDecoder().decode([String: Use].self, from: Data(contentsOf: historyURL))) ?? [:]

func remember(_ path: String) {
    var u = history[path] ?? Use(count: 0, last: 0)
    u.count += 1
    u.last = Date().timeIntervalSince1970
    history[path] = u
    try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
    try? JSONEncoder().encode(history).write(to: historyURL)
}

// ---- Fuzzy match: every query character in order. A run continues if it
// can, else the next word start, else the nearest; bonuses for the start,
// word starts and runs, a small cost per skipped character ----
func fuzzy(_ q: [Character], _ lower: [Character], _ chars: [Character]) -> (score: Int, at: [Int])? {
    if q.isEmpty { return (0, []) }
    func wordStart(_ j: Int) -> Bool {
        if j == 0 { return true }
        let p = chars[j - 1]
        return " -_./".contains(p) || (p.isLowercase && chars[j].isUppercase) || (!p.isNumber && chars[j].isNumber)
    }
    var at: [Int] = [], score = 0, j = 0
    for c in q {
        guard j < lower.count, let near = lower[j...].firstIndex(of: c) else { return nil }
        var pick = near
        if let prev = at.last, near == prev + 1 {
            pick = near
        } else if let ws = (near..<lower.count).first(where: { lower[$0] == c && wordStart($0) }) {
            pick = ws
        }
        let run = at.last.map { pick == $0 + 1 } ?? false
        score += 1 + (pick == 0 ? 10 : 0) + (wordStart(pick) ? 8 : 0) + (run ? 5 : 0) - min(pick - j, 3)
        at.append(pick)
        j = pick + 1
    }
    if lower.starts(with: q) { score += 20 }
    return (score - lower.count / 10, at)
}

// ---- Calculator: + - * / % ^ (x for *) and parentheses ----
func calc(_ s: String) -> Double? {
    let t = Array(s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ""))
    guard t.contains(where: \.isNumber),
          t.allSatisfy({ "0123456789.+-*/%^()x".contains($0) }),
          t.dropFirst().contains(where: { "+-*/%^x".contains($0) }) else { return nil }
    var i = 0
    func peek() -> Character? { i < t.count ? t[i] : nil }
    func number() -> Double? {
        let start = i
        while let c = peek(), c.isNumber || c == "." { i += 1 }
        return start < i ? Double(String(t[start..<i])) : nil
    }
    func primary() -> Double? {
        if peek() == "-" { i += 1; return primary().map { -$0 } }
        if peek() == "(" {
            i += 1
            guard let v = expr(), peek() == ")" else { return nil }
            i += 1
            return v
        }
        return number()
    }
    func power() -> Double? {
        guard let b = primary() else { return nil }
        if peek() == "^" {
            i += 1
            return power().map { pow(b, $0) }
        }
        return b
    }
    func term() -> Double? {
        guard var v = power() else { return nil }
        while let op = peek(), "*/%x".contains(op) {
            i += 1
            guard let r = power() else { return nil }
            switch op {
            case "/": v /= r
            case "%": v = v.truncatingRemainder(dividingBy: r)
            default: v *= r
            }
        }
        return v
    }
    func expr() -> Double? {
        guard var v = term() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            i += 1
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }
    guard let v = expr(), i == t.count, v.isFinite else { return nil }
    return v
}

func format(_ v: Double) -> String {
    v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(format: "%.10g", v)
}

// ---- Web shortcuts: piercing-dots dots/ulauncher/shortcuts.json ----
let shortcuts = [("g", "Google Search", "https://google.com/search?q=%s"),
                 ("so", "Stack Overflow", "https://stackoverflow.com/search?q=%s"),
                 ("wiki", "Wikipedia", "https://en.wikipedia.org/wiki/%s")]

func browserIcon() -> NSImage {
    guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
        return NSImage(named: NSImage.networkName) ?? NSImage()
    }
    return icon(app.path)
}

func search(_ s: (String, String, String), _ q: String) -> Item {
    let arg = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
    return Item(name: s.1, text: q, icon: browserIcon(),
                action: .open(URL(string: s.2.replacingOccurrences(of: "%s", with: arg))!))
}

// ---- File browsing: a query starting with ~ or / ----
func files(_ query: String) -> [Item] {
    let q = query == "~" ? "~/" : query
    let full = (q as NSString).expandingTildeInPath
    let dir = q.hasSuffix("/") ? full : (full as NSString).deletingLastPathComponent
    let part = q.hasSuffix("/") ? "" : (full as NSString).lastPathComponent
    let p = Array(part.lowercased())
    var out: [(Int, Item)] = []
    for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where part.hasPrefix(".") || !n.hasPrefix(".") {
        guard let m = fuzzy(p, Array(n.lowercased()), Array(n)) else { continue }
        let path = (dir as NSString).appendingPathComponent(n)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let walk = isDir.boolValue && !n.hasSuffix(".app")
        out.append((m.score, Item(name: walk ? n + "/" : n, text: abbreviate(path), icon: icon(path), matches: m.at,
                                  action: walk ? .browse(path) : .open(URL(fileURLWithPath: path)))))
    }
    return out.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.name.lowercased() < $1.1.name.lowercased() }
        .prefix(maxRows).map(\.1)
}

func results(_ query: String) -> [Item] {
    let q = query.trimmingCharacters(in: .whitespaces)
    if q.isEmpty {
        return apps.filter { history[$0.path] != nil }
            .sorted { history[$0.path]!.last > history[$1.path]!.last }
            .prefix(recentCount)
            .map { Item(name: $0.name, text: abbreviate($0.path), icon: icon($0.path), action: .app($0.path)) }
    }
    if q.hasPrefix("/") || q.hasPrefix("~") { return files(q) }
    var out: [Item] = []
    if let v = calc(q) {
        out.append(Item(name: format(v), text: "Enter copies it", icon: icon("/System/Applications/Calculator.app"),
                        action: .copy(format(v))))
    }
    // "g something" goes straight to that shortcut
    let parts = q.split(separator: " ", maxSplits: 1)
    if parts.count == 2, let s = shortcuts.first(where: { $0.0 == parts[0].lowercased() }) {
        return out + [search(s, String(parts[1]))]
    }
    let ql = Array(q.lowercased())
    let scored = apps.compactMap { a -> (Int, App, [Int])? in
        guard let m = fuzzy(ql, a.lower, a.chars) else { return nil }
        return (m.score + min(history[a.path]?.count ?? 0, 20) * 3, a, m.at)
    }.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.name < $1.1.name }
    out += scored.prefix(maxRows - shortcuts.count - out.count).map {
        Item(name: $0.1.name, text: abbreviate($0.1.path), icon: icon($0.1.path), matches: $0.2, action: .app($0.1.path))
    }
    // Ulauncher's default searches, last
    return out + shortcuts.map { search($0, q) }
}

// ---- Window ----
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class RowView: FlippedView {
    let item: Item
    let index: Int
    var selected = false { didSet { needsDisplay = true } }
    var onClick: (Int) -> Void = { _ in }

    init(item: Item, index: Int, frame: NSRect) {
        self.item = item
        self.index = index
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    func line(_ text: String, _ f: NSFont, _ color: NSColor, matches: [Int] = [], match: NSColor? = nil) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: text, attributes: [.font: f, .foregroundColor: color, .paragraphStyle: style])
        if let match, !matches.isEmpty {
            let hit = Set(matches)
            var offset = 0
            for (n, c) in text.enumerated() {
                let len = String(c).utf16.count
                if hit.contains(n) { s.addAttribute(.foregroundColor, value: match, range: NSRange(location: offset, length: len)) }
                offset += len
            }
        }
        return s
    }

    override func draw(_ dirty: NSRect) {
        if selected {
            selectedBox.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 2), xRadius: 15, yRadius: 15).fill()
        } else {
            // the dashed separator
            let sep = NSBezierPath()
            sep.move(to: NSPoint(x: 12, y: bounds.maxY - 0.5))
            sep.line(to: NSPoint(x: bounds.maxX - 12, y: bounds.maxY - 0.5))
            sep.setLineDash([3, 3], count: 2, phase: 0)
            sep.lineWidth = 1
            borderColor.withAlphaComponent(0.1).setStroke()
            sep.stroke()
        }
        item.icon.draw(in: NSRect(x: 12, y: (bounds.height - 40) / 2, width: 40, height: 40),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let keyW: CGFloat = index < 9 ? 44 : 0
        let textW = bounds.width - 64 - keyW - 12
        line(item.name, font(15, bold: true), selected ? nameSelected : nameColor,
             matches: item.matches, match: selected ? matchSelected : matchColor)
            .draw(in: NSRect(x: 64, y: 8, width: textW, height: 20))
        line(item.text, font(12), selected ? textSelected : textColor)
            .draw(in: NSRect(x: 64, y: 29, width: textW, height: 17))
        if index < 9 {
            let key = line("⌥\(index + 1)", font(13, bold: true), selected ? keySelected : keyColor)
            key.draw(at: NSPoint(x: bounds.maxX - keyW, y: (bounds.height - key.size().height) / 2))
        }
    }

    override func mouseDown(with event: NSEvent) { onClick(index) }
}

class Launcher: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: width, height: inputHeight),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let box = FlippedView()
    let field = NSTextField()
    let rule = NSView()
    let list = FlippedView()
    var items: [Item] = []
    var rows: [RowView] = []
    var selected = 0
    var top: CGFloat = 0

    override init() {
        super.init()
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.delegate = self

        // Blur what's behind, like Hyprland does for Ulauncher, then the Aura colors
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 24
        blur.layer?.masksToBounds = true
        panel.contentView = blur
        box.frame = blur.bounds
        box.wantsLayer = true
        box.layer?.backgroundColor = bgColor.cgColor
        box.layer?.borderColor = borderColor.cgColor
        box.layer?.borderWidth = 2
        box.layer?.cornerRadius = 24
        box.autoresizingMask = [.width, .height]
        blur.addSubview(box)

        field.frame = NSRect(x: pad + 8, y: (inputHeight - 32) / 2, width: width - 2 * (pad + 8), height: 32)
        field.font = font(22)
        field.textColor = inputColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        box.addSubview(field)

        rule.wantsLayer = true
        rule.layer?.backgroundColor = borderColor.withAlphaComponent(0.3).cgColor
        rule.frame = NSRect(x: pad + 8, y: inputHeight - 4, width: width - 2 * (pad + 8), height: 1)
        box.addSubview(rule)
        box.addSubview(list)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] e in
            self.panel.isKeyWindow && self.key(e) ? nil : e
        }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        if Date().timeIntervalSince(lastScan) > 30 {
            apps = scanApps()
            lastScan = Date()
        }
        // The screen with the pointer, a fifth of the way down
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        top = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.2
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - width / 2, y: top - inputHeight))
        field.stringValue = ""
        update()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = inputColor
    }

    func hide() { panel.orderOut(nil) }

    func update() {
        items = results(field.stringValue)
        selected = 0
        rows.forEach { $0.removeFromSuperview() }
        rows = items.enumerated().map { n, item in
            let r = RowView(item: item, index: n, frame: NSRect(x: 0, y: CGFloat(n) * rowHeight, width: width - 2 * pad, height: rowHeight))
            r.onClick = { [unowned self] i in self.run(i) }
            list.addSubview(r)
            return r
        }
        rows.first?.selected = true
        rule.isHidden = items.isEmpty
        let listH = CGFloat(items.count) * rowHeight
        list.frame = NSRect(x: pad, y: inputHeight + 6, width: width - 2 * pad, height: listH)
        let h = inputHeight + (items.isEmpty ? 0 : 6 + listH + pad - 4)
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - h, width: width, height: h), display: true)
    }

    func move(_ by: Int) {
        guard !items.isEmpty else { return }
        rows[selected].selected = false
        selected = (selected + by + items.count) % items.count
        rows[selected].selected = true
    }

    func run(_ i: Int, alt: Bool = false) {
        guard items.indices.contains(i) else { return }
        switch items[i].action {
        case .app(let path):
            remember(path)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            hide()
        case .open(let url):
            NSWorkspace.shared.open(url)
            hide()
        case .browse(let path):
            if alt {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                hide()
            } else {
                setQuery(abbreviate(path) + "/")
            }
        case .copy(let s):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
            hide()
        }
    }

    // Tab: the selected file or folder's path into the query
    func complete() {
        guard items.indices.contains(selected) else { return }
        switch items[selected].action {
        case .browse(let path): setQuery(abbreviate(path) + "/")
        case .open(let url) where url.isFileURL: setQuery(abbreviate(url.path))
        default: break
        }
    }

    func setQuery(_ q: String) {
        field.stringValue = q
        field.currentEditor()?.selectedRange = NSRange(location: (q as NSString).length, length: 0)
        update()
    }

    func key(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        switch e.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 36, 76: run(selected, alt: mods.contains(.option) || mods.contains(.command))
        case 53: hide()
        case 48: complete()
        default:
            if mods == .control && ch == "j" { move(1) }
            else if mods == .control && ch == "k" { move(-1) }
            else if mods == .option, let d = Int(ch), (1...9).contains(d) { run(d - 1) }
            else { return false }
        }
        return true
    }

    func controlTextDidChange(_ obj: Notification) { update() }
    // Ulauncher's close-on-focus-out
    func windowDidResignKey(_ notification: Notification) { hide() }
}

// ---- Start ----
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Without an Edit menu the field has no Cmd+A/C/V/X/Z (Karabiner turns Ctrl into those)
let mainMenu = NSMenu()
let editItem = NSMenuItem()
let edit = NSMenu(title: "Edit")
for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"),
                             ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
    edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
}
editItem.submenu = edit
mainMenu.addItem(editItem)
app.mainMenu = mainMenu

let launcher = Launcher()
apps = scanApps()
lastScan = Date()

DistributedNotificationCenter.default().addObserver(forName: toggleName, object: nil, queue: .main) { _ in launcher.toggle() }

// Option+Space, the hotkey Karabiner sends on an Option tap
var hotKey: EventHotKeyRef?
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    DispatchQueue.main.async { launcher.toggle() }
    return noErr
}, 1, &spec, nil, nil)
let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: OSType(0x50584C4E), id: 1),
                                 GetApplicationEventTarget(), 0, &hotKey)
if status != noErr {
    FileHandle.standardError.write("piercing-launcher: Option+Space is taken (\(status)); is Sol still running?\n".data(using: .utf8)!)
}
app.run()
