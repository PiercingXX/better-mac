// GitHub.com/PiercingXX
// piercing-kbd: keyboard backlight from the command line. Apple Silicon
// MacBooks dropped the backlight keys and macOS has no CLI for it, so this
// talks to the private KeyboardBrightnessClient in CoreBrightness.
//   piercing-kbd            print the level, 0-100
//   piercing-kbd set N      set it to N (0-100)
//   piercing-kbd cycle      step through the presets (wraps), print the new level
// Setting a level turns off "Adjust keyboard brightness in low light", or
// macOS would move it straight back.
import Foundation

let presets = [0, 5, 30, 60, 90]

@objc protocol KeyboardBrightnessClient {
    func copyKeyboardBacklightIDs() -> [NSNumber]?
    @objc(brightnessForKeyboard:) func brightness(forKeyboard id: UInt64) -> Float
    @objc(setBrightness:forKeyboard:) func setBrightness(_ value: Float, forKeyboard id: UInt64) -> Bool
    @objc(enableAutoBrightness:forKeyboard:) func enableAutoBrightness(_ on: Bool, forKeyboard id: UInt64) -> Bool
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
      let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
    fail("CoreBrightness's KeyboardBrightnessClient is missing")
}
let client = unsafeBitCast(cls.init(), to: KeyboardBrightnessClient.self)
guard let ids = client.copyKeyboardBacklightIDs()?.map({ $0.uint64Value }), let first = ids.first else {
    fail("no backlit keyboard found")
}

func level() -> Int { Int((client.brightness(forKeyboard: first) * 100).rounded()) }

func set(_ percent: Int) {
    let value = Float(min(max(percent, 0), 100)) / 100
    for id in ids {
        _ = client.enableAutoBrightness(false, forKeyboard: id)
        _ = client.setBrightness(value, forKeyboard: id)
    }
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case nil:
    print(level())
case "set":
    guard args.count == 2, let n = Int(args[args.startIndex + 1]) else { fail("usage: piercing-kbd set 0-100") }
    set(n)
    print(level())
case "cycle":
    // The next preset above the current level, so a level set elsewhere
    // (System Settings, Control Center) still steps up from where it is
    let now = level()
    let next = presets.first(where: { $0 > now + 2 }) ?? presets[0]
    set(next)
    print(next)
default:
    fail("usage: piercing-kbd [set 0-100 | cycle]")
}
