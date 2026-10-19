// GitHub.com/PiercingXX
// piercing-cursor: the piercing-dots cursor theme (Black-Minimalistic, about
// 1.6x its XCURSOR_SIZE 22, with a light halo) as the macOS cursor. macOS has
// no public cursor-theme API, so this registers the images through
// WindowServer's private CGSRegisterCursorWithImages, the call Mousecape
// uses. Since macOS 26 the arrow and I-beam are drawn from ArrowS/IBeamS, so
// cursors.tsv names those too. WindowServer forgets the cursors at logout,
// and sometimes on wake, so this stays running and re-applies them.
//
//   piercing-cursor <dir>            apply <dir>/cursors.tsv and keep them applied
//   piercing-cursor <dir> --once     apply and exit
//   piercing-cursor --restore        put the macOS cursors back (all but the
//                                    arrow and I-beam; logging out resets those)
// (launchd: com.piercingxx.cursor, installed by modules/wm.sh)

import AppKit
import ImageIO

// Points the 32px theme images are drawn at: about 1.6x the Linux XCURSOR_SIZE 22
let pointSize: CGFloat = 35
// Light white halo around the black lines: blur radius in points, how many
// times it's stacked (more = a firmer outline) and its opacity
let haloBlur: CGFloat = 1
let haloPasses = 1
let haloAlpha: CGFloat = 0.8

typealias MainConnection = @convention(c) () -> Int32
typealias RegisterCursor = @convention(c) (Int32, UnsafePointer<CChar>, Bool, Bool, CGSize, CGPoint,
                                          UInt, CGFloat, CFArray, UnsafeMutablePointer<Int32>) -> Int32
typealias UnregisterAll = @convention(c) (Int32) -> Int32

// ApplicationServices re-exports SkyLight's CGS calls and HIServices'
// CoreCursorUnregisterAll
let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
func symbol<T>(_ name: String, _: T.Type) -> T {
    guard let p = dlsym(services, name) else {
        FileHandle.standardError.write("piercing-cursor: \(name) not found\n".data(using: .utf8)!)
        exit(1)
    }
    return unsafeBitCast(p, to: T.self)
}
let connection = symbol("CGSMainConnectionID", MainConnection.self)()

struct Cursor {
    let frames: Int
    let frameSeconds: CGFloat
    let hotspot: CGPoint   // pixels in the source image
    let pixels: CGFloat    // source frame width/height
    let names: [String]
    let image: CGImage     // frames stacked vertically
}

func load(_ dir: URL) -> [Cursor] {
    guard let table = try? String(contentsOf: dir.appendingPathComponent("cursors.tsv"), encoding: .utf8) else {
        FileHandle.standardError.write("piercing-cursor: no cursors.tsv in \(dir.path)\n".data(using: .utf8)!)
        exit(1)
    }
    var cursors: [Cursor] = []
    for line in table.split(separator: "\n") where !line.hasPrefix("#") {
        let f = line.split(separator: "\t").map(String.init)
        guard f.count == 7,
              let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(f[0] + ".png") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let frames = Int(f[1]), let ms = Double(f[2]),
              let hx = Double(f[3]), let hy = Double(f[4]), let px = Double(f[5]) else { continue }
        // A still cursor with a 0s frame draws as nothing; capes use 1s
        cursors.append(Cursor(frames: frames, frameSeconds: frames > 1 ? CGFloat(ms / 1000) : 1,
                              hotspot: CGPoint(x: hx, y: hy), pixels: CGFloat(px),
                              names: f[6].split(separator: " ").map(String.init), image: image))
    }
    return cursors
}

// The strip redrawn with each frame at <scale>x pointSize pixels, as
// premultiplied BGRA, the layout WindowServer keeps cursors in
func scaled(_ c: Cursor, _ scale: CGFloat) -> CGImage? {
    let side = Int((pointSize * scale).rounded())
    let bgra = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = CGContext(data: nil, width: side, height: side * c.frames, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: bgra) else { return nil }
    ctx.interpolationQuality = .high
    // The theme is bare black lines, lost on a dark desktop; the halo keeps
    // it visible the way the macOS arrow's outline does
    ctx.setShadow(offset: .zero, blur: haloBlur * scale, color: CGColor(gray: 1, alpha: haloAlpha))
    for _ in 0..<haloPasses {
        ctx.draw(c.image, in: CGRect(x: 0, y: 0, width: side, height: side * c.frames))
    }
    return ctx.makeImage()
}

func apply(_ cursors: [Cursor]) {
    let register = symbol("CGSRegisterCursorWithImages", RegisterCursor.self)
    let size = CGSize(width: pointSize, height: pointSize)
    var failed: [String] = []
    for c in cursors {
        let reps = [scaled(c, 1), scaled(c, 2)].compactMap { $0 }
        let k = pointSize / c.pixels
        let hot = CGPoint(x: c.hotspot.x * k, y: c.hotspot.y * k)
        for name in c.names {
            var seed: Int32 = 0
            let err = name.withCString {
                register(connection, $0, true, true, size, hot, UInt(c.frames), c.frameSeconds, reps as CFArray, &seed)
            }
            if err != 0 { failed.append(name) }
        }
    }
    if !failed.isEmpty {
        FileHandle.standardError.write("piercing-cursor: not applied: \(failed.joined(separator: " "))\n".data(using: .utf8)!)
    }
}

let args = CommandLine.arguments.dropFirst()
if args.contains("--restore") {
    _ = symbol("CoreCursorUnregisterAll", UnregisterAll.self)(connection)
    exit(0)
}
guard let dir = args.first(where: { !$0.hasPrefix("--") }) else {
    print("usage: piercing-cursor <theme dir> [--once] | --restore")
    exit(2)
}
let cursors = load(URL(fileURLWithPath: dir))
apply(cursors)
if args.contains("--once") { exit(0) }

// Re-apply whenever WindowServer may have reset them
let center = NSWorkspace.shared.notificationCenter
for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
             NSWorkspace.sessionDidBecomeActiveNotification] {
    center.addObserver(forName: name, object: nil, queue: .main) { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { apply(cursors) }
    }
}
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: nil, queue: .main) { _ in apply(cursors) }

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
