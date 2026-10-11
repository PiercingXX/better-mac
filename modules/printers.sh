# shellcheck shell=bash
# GitHub.com/PiercingXX
# linux-mod's printers (modules/extras.sh): Canon D530 laser + Omezizy/XPrinter
# label printer. macOS ships CUPS, so the lpadmin/lpoptions setup is the same.
# The drivers come from Canon and XPrinter instead of the AUR: if one isn't
# installed, the vendor's download page opens and the script waits.
# Not part of the main install (the printer must be plugged in):
#   ./better-mac.sh printers [canon|omezizy|both]

CANON_PRINTER_NAME="${CANON_PRINTER_NAME:-Canon-D530}"
OMEZIZY_QUEUE_NAME="${OMEZIZY_QUEUE_NAME:-Omezizy_Label}"
OMEZIZY_MODEL_NAME="${OMEZIZY_MODEL_NAME:-XP-420B}"
CANON_DRIVER_URL="https://www.usa.canon.com/support/p/imageclass-d530"
XPRINTER_DRIVER_URL="https://www.xprintertech.com/drivers-2"

printers_install() {
    case "${1:-both}" in
        canon)   printers_canon ;;
        omezizy) printers_omezizy ;;
        both)    printers_canon; printers_omezizy ;;
        *)       warn "Unknown printer '$1' (canon, omezizy or both)."; return 1 ;;
    esac
}

# First installed driver (lpinfo -m) whose line matches <regex>
_printers_model() {
    lpinfo -m 2>/dev/null | grep -iE "$1" | head -n1 | awk '{print $1}'
}

# First connected device URI (lpinfo -v) matching <regex>, case-insensitive
_printers_uri() {
    lpinfo -v 2>/dev/null | awk -v re="$1" 'tolower($0) ~ re {print $2; exit}'
}

# _printers_driver <regex> <printer> <url> <driver>: sets PRINTER_MODEL to the
# installed driver, sending the user to the vendor download page once if needed
_printers_driver() {
    PRINTER_MODEL="$(_printers_model "$1")"
    [ -n "$PRINTER_MODEL" ] && return 0
    say "No $2 driver installed. Opening the download page..."
    open "$3"
    wait_for_user "Download and install $4, then come back here."
    PRINTER_MODEL="$(_printers_model "$1")"
    [ -n "$PRINTER_MODEL" ]
}

printers_canon() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "configure Canon D530: driver check, USB detection, lpadmin queue, default printer"
        return 0
    fi
    say "Setting up the Canon D530 queue..."
    if ! _printers_driver 'D530|D560' "Canon D530" "$CANON_DRIVER_URL" \
            "the \"UFRII LT Printer Driver\" for Mac"; then
        warn "Canon D530 driver still not found; rerun: ./better-mac.sh printers canon"
        return 1
    fi

    local uri
    uri="$(_printers_uri 'usb://canon')"
    if [ -z "$uri" ]; then
        warn "No Canon D530 detected over USB; plug it in and rerun: ./better-mac.sh printers canon"
        return 1
    fi

    sudo lpadmin -x "$CANON_PRINTER_NAME" 2>/dev/null || true
    if ! sudo lpadmin -p "$CANON_PRINTER_NAME" -E -v "$uri" -m "$PRINTER_MODEL"; then
        warn "lpadmin could not create $CANON_PRINTER_NAME."
        return 1
    fi
    sudo cupsenable "$CANON_PRINTER_NAME" 2>/dev/null || true
    sudo cupsaccept "$CANON_PRINTER_NAME" 2>/dev/null || true
    # Default printer, and stop macOS switching the default to the last one used
    lpoptions -d "$CANON_PRINTER_NAME" >/dev/null 2>&1 || true
    defaults write org.cups.PrintingPrefs UseLastPrinter -bool false
    ok "Canon D530 configured (queue: $CANON_PRINTER_NAME, driver: $PRINTER_MODEL)."
}

printers_omezizy() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "configure Omezizy label printer: driver check, USB detection, lpadmin queue + label options"
        return 0
    fi
    say "Setting up the Omezizy label printer..."
    if ! _printers_driver "$OMEZIZY_MODEL_NAME" "XPrinter $OMEZIZY_MODEL_NAME" "$XPRINTER_DRIVER_URL" \
            "XPrinter's \"Label printer (macOS)\" driver"; then
        # Same fallback as linux-mod: the CUPS sample Zebra driver, if present
        PRINTER_MODEL="$(_printers_model 'sample.drv/zebra.ppd')"
        if [ -z "$PRINTER_MODEL" ]; then
            warn "No XPrinter driver found; rerun: ./better-mac.sh printers omezizy"
            return 1
        fi
        warn "XPrinter driver not found; using the generic Zebra label driver."
    fi

    local uri
    uri="$(_printers_uri 'usb://.*(d520|labelprinter)')"
    if [ -z "$uri" ]; then
        warn "No Omezizy/XPrinter label printer detected over USB; plug it in and rerun."
        return 1
    fi

    sudo lpadmin -x "$OMEZIZY_QUEUE_NAME" 2>/dev/null || true
    if ! sudo lpadmin -p "$OMEZIZY_QUEUE_NAME" -E -v "$uri" -m "$PRINTER_MODEL"; then
        warn "lpadmin could not create $OMEZIZY_QUEUE_NAME."
        return 1
    fi
    # 4x6 shipping labels; option names come from the XPrinter driver, so
    # anything the installed driver doesn't know is ignored
    sudo lpoptions -p "$OMEZIZY_QUEUE_NAME" \
        -o PageSize=w4h6 -o Resolution=203dpi -o PaperType=LabelGaps \
        -o GapsHeight=3 -o PostAction=TearOff -o PrintSpeed=6 -o Darkness=12 2>/dev/null || true
    sudo cupsenable "$OMEZIZY_QUEUE_NAME" 2>/dev/null || true
    sudo cupsaccept "$OMEZIZY_QUEUE_NAME" 2>/dev/null || true
    ok "Omezizy label printer configured (queue: $OMEZIZY_QUEUE_NAME, driver: $PRINTER_MODEL)."
}
