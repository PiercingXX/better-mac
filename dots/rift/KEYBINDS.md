# PiercingXX keybinds on macOS (Rift)

Same binds as piercing-dots Hyprland, by key position:

    Hyprland SUPER  ->  Option (⌥)      Hyprland ALT  ->  Cmd (⌘)      CTRL -> Ctrl

Letters follow the active input source, Colemak or Piercing Num, like Hyprland
does (Rift rebuilds its key map whenever the source changes).
Switch layouts with the Globe key or Ctrl-Option-Space (Ctrl-Space is the tmux prefix).

## Essentials
    tap ⌥              Sol launcher                (was: tap Super -> ulauncher)
    ⌥ Q                close window
    ⌥ ⇧ Q              force-quit app
    ⌥ F                toggle float
    ⌥ ⇧ F              toggle fullscreen
    ⌥ X                toggle split direction
    ⌥ R                toggle SketchyBar
    ⌥ ⇧ Y              clipboard history (Sol)
    ⌥ S                settings menu               (was: Super + S)
    ⌥ ⇧ S              Sound settings              (was: pavucontrol)
    ⌥ ⌘ S              System Settings             (was: gnome-control-center)
    ⌥ ⇧ ;              reload Rift config
    ⌥ /                this file
    Caps Lock          Backspace                   (both layouts)
    Backspace          Forward Delete              (every layout)
    Right ⌥ + h/j/k/l  arrows                      (Piercing Num, AltGr arrows)
    ⌥ E                screenshot a region         (was: Print)
    ⌥ ⇧ E              screenshot a window         (was: Shift + Print)
    ⌥ ⌘ E              screenshot the screen
                       all go to ~/Pictures/Screenshots + clipboard
    ⌥ + drag           move a window; drop it on another to swap (was: Super + drag)

## Touchpad
    3 fingers left/right   next/previous workspace in use; past the last one,
                           a new empty one (Hyprland's workspace swipe)
    3 fingers up           Sol
    4 fingers down         close window

## Apps
    ⌥ W  kitty         ⌥ T  kitty + tmux       ⌥ Z  yazi          ⌥ ⇧ Z  Finder
    ⌥ C  Waterfox      ⌥ D  Discord            ⌥ B  Obsidian      ⌥ G    GIMP
    ⌥ V  nvim          ⌥ ⇧ V  OpenCode         ⌥ ⌘ V  VS Code
    Ctrl ⌘ Backspace   Activity Monitor        (was: Ctrl Alt Del -> Mission Center)

## Notes / server / AI   (run your ~/.scripts in kitty)
    ⌥ N  daily note split    ⌥ ⇧ N  view    ⌥ ⌘ N  todo    ⌥ ⌘ ⇧ N  note directory
    ⌥ I  inventory
    ⌥ M  server monitor      ⌥ ⇧ M  remote
    ⌥ A  skippy remote       ⌥ ⇧ A  ollama skippy           ⌥ ⌘ A  ollama gemma

## Windows
    ⌥ H J K L / arrows       focus
    ⌥ ⇧ H J K L / arrows     move window
    ⌥ ⌘ H J K L / arrows     resize

## Workspaces
    ⌥ 1-0              go to workspace 1-10
    ⌥ ⇧ 1-0            move window there and follow
    ⌥ ⌘ 1-0            move window there silently

## Session / audio
    ⌥ `                lock screen
    ⌥ ⇧ `              suspend
    Ctrl ⌘ ⇧ K         shut down now, no prompt
    Ctrl ⌘ ⇧ Backspace shut down (macOS asks to save open work)
    ⌥ O                next audio output
    ⌥ P                time notification       ⌥ ⇧ P  calendar notification      ⌥ ⇧ C  Calculator
    Media/brightness keys work natively.
