// GitHub.com/PiercingXX: Waterfox without window chrome, like a Hyprland window
// (modules/wm.sh copies this and chrome/ into the default profile)
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// Tabs sit where the title bar was
user_pref("browser.tabs.inTitlebar", 1);
// No "make Waterfox your default browser?" bar
user_pref("browser.shell.checkDefaultBrowser", false);
