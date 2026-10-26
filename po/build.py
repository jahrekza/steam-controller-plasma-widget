#!/usr/bin/env python3
"""Build the plasmoid's translations.

  1. xgettext the QML into po/plasma_applet_com.jahrek.steamcontroller.pot
  2. check that SOURCE (below) matches the .pot exactly
  3. write po/<lang>.po from translations_a/_b.py and compile them into
     plasmoid/.../contents/locale/<lang>/LC_MESSAGES/<domain>.mo

Run from the repo root:  python3 po/build.py
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DOMAIN = "plasma_applet_com.jahrek.steamcontroller"
UI = os.path.join(ROOT, "plasmoid/com.jahrek.steamcontroller/contents/ui")
LOCALE = os.path.join(ROOT, "plasmoid/com.jahrek.steamcontroller/contents/locale")
# the same translations as a JS table, for the "Language" option (Plasma itself only
# follows the system language)
TABLE_JS = os.path.join(ROOT, "plasmoid/com.jahrek.steamcontroller/contents/code/translations.js")
POT = os.path.join(HERE, DOMAIN + ".pot")

SOURCE = [
 "Custom", "Controller LED (default)", "Monochrome", "Warm", "Night",
 "Low battery warning:", "Notify when:", "the battery drops below the warning level",
 "the battery is fully charged", "the signal gets weak (puck)", "the controller disconnects",
 "Appearance", "Preset:", "Apply", "Reset appearance to defaults",
 "Card background:", "Dark", "Glass", "None (shadow only)",
 "Background colour:", "Glass colour:", "Background opacity:", "Percentage opacity:",
 "Controller outline:", "Controller fill:", "Text and icons:",
 "Text and icons: the %, status, signal, connection icon and battery outline. The battery fill and status mark keep the controller's LED colours, and low battery / weak signal stay red. Unticked: the default look.",
 "Status colours", "Puck:", "Bluetooth:", "USB-C cable:", "Off, on the dock:", "Low battery:",
 "Unticked: the colours of the controller's own LED.",
 "Signal strength:", "Show on the widget (desktop card)", "Show in the panel / system tray",
 "Show as:", "Bars", "Bars and dBm", "dBm only",
 "Only for the wireless puck (also the Steam Machine's). Over Bluetooth or a cable there is no signal reading. In the system tray every entry gets a small fixed square, so there it's a tiny meter on the icon; % and dBm are in the tooltip. Placed directly on a panel, the widget shows them next to the icon.",
 "Connected", "Charging", "via internal puck",
 "No signal", "Weak", "Fair", "Good", "Excellent",
 "%1 min", "%1 h", "%1 h %2 min",
 "Connected · internal puck", "Low — plug in", "Charging · on puck", "Charging · USB-C", "Charging · cable",
 "Disconnected", "Bluetooth", "USB-C cable", "Docked on puck", "Internal puck (Steam Machine)", "Wireless (puck)",
 "Steam Controller", "Signal: %1", "Signal: %1 (%2 dBm)", "Signal: %1 dBm",
 "full in %1", "%1 left", "Find controller",
 "Steam Controller battery low", "%1% left — plug it in",
 "Steam Controller charged", "The battery is full.",
 "Weak controller signal", "The controller is far from the receiver and may disconnect.",
 "Steam Controller disconnected", "The controller is no longer connected.",
 "%1 dBm", "−%1 h", "−%1 min", "now",
]

# Alternative puck names and the GabeCube option (translations_c.py)
NAMES = [
 "Connected · internal chongle", "Connected · internal dongle",
 "Charging · on chongle", "Charging · on dongle",
 "Docked on chongle", "Docked on dongle",
 "Internal chongle (Steam Machine)", "Internal dongle (Steam Machine)",
 "Wireless (chongle)", "Wireless (dongle)",
 "via internal chongle", "via internal dongle",
 "Names", "Puck name:", "Puck", "Chongle", "Dongle", "Call the Steam Machine “GabeCube”",
 "Chongle: what Valve called the puck internally. Dongle: what many players call it. GabeCube: the fans' nickname for the Steam Machine.",
 "Language:", "System language",
 "Charged", "Fully charged",
 "Find controller sound:", "Vibration only", "Tick-tock", "Little bird", "Ringing", "SOS", "Fast alarm", "Play",
 "via puck", "via chongle", "via dongle", "via Bluetooth", "via USB-C",
 "Details:", "Show how it is connected or charging (via puck, Bluetooth, USB-C)",
 "System tray:", "Show an icon in the system tray", "Settings:", "Use these settings on the desktop and in the tray",
 "Both take effect right away. The copy: everything on this page goes to every copy of this widget, the desktop card and the tray icon.",
]
# Two jokey puck names (translations_d.py): the forms above for each, then the names
FUN = [
 "Connected · internal gizmo",
 "Charging · on the gizmo",
 "Docked on the gizmo",
 "Internal gizmo (Steam Machine)",
 "Wireless (gizmo)",
 "via the internal gizmo",
 "via the gizmo",
 "Connected · internal whatchamacallit",
 "Charging · on the whatchamacallit",
 "Docked on the whatchamacallit",
 "Internal whatchamacallit (Steam Machine)",
 "Wireless (whatchamacallit)",
 "via the internal whatchamacallit",
 "via the whatchamacallit",
 "Gizmo",
 "Whatchamacallit",
]
SOURCE = SOURCE + NAMES + FUN

# Regional English for the two jokey names: the gizmo is "the yoke" in Ireland, "the
# hingmy" in Scotland and "the thingo" in Australia; the whatchamacallit is "yer man"
# (no "the": Irish English says "on yer man"), "the wee doofer" and "the doovalacky".
# en_IE and en_AU are real locales (a .mo each); Scotland has none, so en_SCT exists
# only in the widget's own language option.
def _en(src, name, the, inside):
    """The seven forms + name of one jokey puck name; `the` is the noun with its
    article as used in a sentence, `inside` the "internal" form."""
    return {f"Connected · internal {src}": f"Connected · {inside}",
            f"Charging · on the {src}": f"Charging · on {the}",
            f"Docked on the {src}": f"Docked on {the}",
            f"Internal {src} (Steam Machine)": f"{inside[0].upper() + inside[1:]} (Steam Machine)",
            f"Wireless ({src})": f"Wireless ({name.lower()})",
            f"via the internal {src}": f"via {the} inside",
            f"via the {src}": f"via {the}",
            src[0].upper() + src[1:]: name}
ENGLISH = {
    "en_IE": {**_en("gizmo", "The yoke", "the yoke", "internal yoke"),
              **_en("whatchamacallit", "Yer man", "yer man", "yer man inside")},
    "en_SCT": {**_en("gizmo", "The hingmy", "the hingmy", "internal hingmy"),
               **_en("whatchamacallit", "The wee doofer", "the wee doofer", "internal wee doofer")},
    "en_AU": {**_en("gizmo", "The thingo", "the thingo", "internal thingo"),
              **_en("whatchamacallit", "The doovalacky", "the doovalacky", "internal doovalacky")},
}

# Name / description shown in "Add Widgets" and the KDE Store
META = {
 "pl": ("Bateria Steam Controllera", "Pokazuje poziom baterii i stan połączenia Steam Controllera"),
 "de": ("Steam Controller-Akku", "Zeigt Akkustand und Verbindungsstatus des Steam Controllers"),
 "it": ("Batteria Steam Controller", "Mostra il livello della batteria e lo stato della connessione dello Steam Controller"),
 "es": ("Batería del Steam Controller", "Muestra el nivel de batería y el estado de conexión del Steam Controller"),
 "pt": ("Bateria do Steam Controller", "Mostra o nível da bateria e o estado da ligação do Steam Controller"),
 "pt_BR": ("Bateria do Steam Controller", "Mostra o nível da bateria e o estado da conexão do Steam Controller"),
 "nl": ("Steam Controller-batterij", "Toont het batterijniveau en de verbindingsstatus van de Steam Controller"),
 "hr": ("Baterija Steam Controllera", "Prikazuje razinu baterije i stanje veze Steam Controllera"),
 "cs": ("Baterie Steam Controlleru", "Zobrazuje stav baterie a připojení Steam Controlleru"),
 "sk": ("Batéria Steam Controllera", "Zobrazuje stav batérie a pripojenia Steam Controllera"),
 "hu": ("Steam Controller akkumulátor", "Megjeleníti a Steam Controller akkumulátorszintjét és kapcsolati állapotát"),
 "tr": ("Steam Controller Pili", "Steam Controller'ın pil seviyesini ve bağlantı durumunu gösterir"),
 "uk": ("Батарея Steam Controller", "Показує рівень заряду і стан з'єднання Steam Controller"),
 "lt": ("Steam Controller baterija", "Rodo Steam Controller baterijos lygį ir ryšio būseną"),
 "da": ("Steam Controller-batteri", "Viser batteriniveau og forbindelsesstatus for Steam Controller"),
 "sv": ("Steam Controller-batteri", "Visar batterinivå och anslutningsstatus för Steam Controller"),
 "fi": ("Steam Controllerin akku", "Näyttää Steam Controllerin akun varauksen ja yhteyden tilan"),
 "nb": ("Steam Controller-batteri", "Viser batterinivå og tilkoblingsstatus for Steam Controller"),
 "el": ("Μπαταρία Steam Controller", "Εμφανίζει τη στάθμη μπαταρίας και την κατάσταση σύνδεσης του Steam Controller"),
 "et": ("Steam Controlleri aku", "Näitab Steam Controlleri aku taset ja ühenduse olekut"),
 "lv": ("Steam Controller akumulators", "Rāda Steam Controller akumulatora līmeni un savienojuma stāvokli"),
}


def pot_ids():
    subprocess.run(["xgettext", "--from-code=UTF-8", "--language=JavaScript",
                    "-ki18n:1", "-ktr:1", "-ki18nc:1c,2", "-ki18np:1,2",
                    "--package-name=steam-controller-battery", "-o", POT]
                   + sorted(os.path.join(UI, f) for f in os.listdir(UI) if f.endswith(".qml")),
                   check=True)
    text = open(POT, encoding="utf-8").read()
    ids = []
    for m in re.finditer(r'^msgid ((?:"(?:[^"\\]|\\.)*"\n?)+)', text, re.M):
        s = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))
        if s:
            ids.append(s.encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
    return ids


def po_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def placeholders(s):
    return sorted(re.findall(r"%\d", s))


def main():
    sys.path.insert(0, HERE)
    from translations_a import T as TA
    from translations_b import T as TB
    from translations_c import T as TC
    from translations_d import T as TD
    tr = {lang: TA.get(lang, TB.get(lang)) + TC[lang] + TD[lang] for lang in {**TA, **TB}}
    tr["pt_BR"] = tr["pt"]

    ids = pot_ids()
    if sorted(ids) != sorted(SOURCE):
        print("SOURCE and the .pot differ:")
        print("  only in .pot:  ", sorted(set(ids) - set(SOURCE)))
        print("  only in SOURCE:", sorted(set(SOURCE) - set(ids)))
        sys.exit(1)

    bad = 0
    for lang, items in sorted(tr.items()):
        if len(items) != len(SOURCE):
            print(f"{lang}: {len(items)} strings, expected {len(SOURCE)}"); bad += 1; continue
        for src, dst in zip(SOURCE, items):
            if placeholders(src) != placeholders(dst):
                print(f"{lang}: placeholders differ in {src!r} -> {dst!r}"); bad += 1
    if bad:
        sys.exit(1)

    for lang, items in sorted(tr.items()):
        po = os.path.join(HERE, lang + ".po")
        with open(po, "w", encoding="utf-8") as f:
            f.write('msgid ""\nmsgstr ""\n'
                    '"Project-Id-Version: steam-controller-battery\\n"\n'
                    '"PO-Revision-Date: 2026-10-26 00:00+0000\\n"\n'
                    '"Last-Translator: machine-assisted, see translations_*.py\\n"\n'
                    '"Language-Team: none\\n"\n'
                    f'"Language: {lang}\\n"\n'
                    '"MIME-Version: 1.0\\n"\n'
                    '"Content-Type: text/plain; charset=UTF-8\\n"\n'
                    '"Content-Transfer-Encoding: 8bit\\n"\n\n')
            for src, dst in zip(SOURCE, items):
                f.write(f'msgid "{po_escape(src)}"\nmsgstr "{po_escape(dst)}"\n\n')
        out = os.path.join(LOCALE, lang, "LC_MESSAGES")
        os.makedirs(out, exist_ok=True)
        subprocess.run(["msgfmt", "--check", "-o", os.path.join(out, DOMAIN + ".mo"), po], check=True)
    # localized widget name / description for "Add Widgets" (Name[pl], Description[pl], ...)
    meta_path = os.path.join(ROOT, "plasmoid/com.jahrek.steamcontroller/metadata.json")
    meta = json.load(open(meta_path, encoding="utf-8"))
    kp = meta["KPlugin"]
    for k in [k for k in kp if k.startswith(("Name[", "Description["))]:
        del kp[k]
    for lang, (name, desc) in sorted(META.items()):
        kp[f"Name[{lang}]"] = name
        kp[f"Description[{lang}]"] = desc
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=4)
        f.write("\n")

    table = {lang: dict(zip(SOURCE, items)) for lang, items in sorted(tr.items())}
    for lang, items in sorted(ENGLISH.items()):
        assert set(items) <= set(SOURCE), set(items) - set(SOURCE)
        table[lang] = items
        if lang == "en_SCT":
            continue
        po = os.path.join(HERE, lang + ".po")
        with open(po, "w", encoding="utf-8") as f:
            f.write('msgid ""\nmsgstr ""\n'
                    '"Project-Id-Version: steam-controller-battery\\n"\n'
                    '"PO-Revision-Date: 2026-10-26 00:00+0000\\n"\n'
                    '"Last-Translator: see build.py\\n"\n'
                    '"Language-Team: none\\n"\n'
                    f'"Language: {lang}\\n"\n'
                    '"MIME-Version: 1.0\\n"\n'
                    '"Content-Type: text/plain; charset=UTF-8\\n"\n'
                    '"Content-Transfer-Encoding: 8bit\\n"\n\n')
            for src, dst in items.items():
                f.write(f'msgid "{po_escape(src)}"\nmsgstr "{po_escape(dst)}"\n\n')
        out = os.path.join(LOCALE, lang, "LC_MESSAGES")
        os.makedirs(out, exist_ok=True)
        subprocess.run(["msgfmt", "--check", "-o", os.path.join(out, DOMAIN + ".mo"), po], check=True)
    with open(TABLE_JS, "w", encoding="utf-8") as f:
        f.write(".pragma library\n// Generated by po/build.py — do not edit\n\nvar table = "
                + json.dumps(table, ensure_ascii=False, separators=(",", ":")) + "\n\n"
                + "// the string in the chosen language, or null to use Plasma's own i18n\n"
                + "function lookup(lang, s) {\n"
                + "    if (!lang) return null\n"
                + "    var t = table[lang]\n"
                + "    return t && t[s] !== undefined ? t[s] : s\n"
                + "}\n")
    print(f"{len(tr)} languages, {len(SOURCE)} strings each — OK")


if __name__ == "__main__":
    main()
