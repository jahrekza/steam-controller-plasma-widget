# Steam Controller 2 ("Triton") — HID Protocol Research Notes

**Data zaczęcia badań:** 2026-06-12  
**Ostatnia aktualizacja:** 2026-06-30  
**Autor:** Jahrek + Claude Sonnet 4.6  
**Cel:** Widget KDE Plasma pokazujący stan baterii kontrolera

---

## 1. Identyfikacja urządzenia

| Parametr | Wartość |
|---|---|
| VID | `0x28de` (Valve) |
| PID | `0x1304` |
| Nazwa | Steam Controller 2nd gen ("Triton", 2026) |
| Kernel driver | `hid-generic` (NIE `hid-steam` — ten obsługuje tylko starego SC) |
| Usage page | `0xFF00` (vendor/proprietary) |
| Węzeł | `/dev/hidraw0` (może się zmienić; skrypt skanuje hidraw0-19 po VID:PID) |

**Ważne:** Kernel `hid-steam.c` ma wsparcie dla starego Steam Controllera (PID `0x1102`),
ale NIE dla nowego (PID `0x1304`). Wszystkie dane trzeba czytać z hidraw bezpośrednio.

Jak znaleźć właściwy hidraw:
```python
import fcntl, struct
fd = os.open("/dev/hidraw0", os.O_RDWR)
buf = bytearray(8)
fcntl.ioctl(fd, 0x80084803, buf, True)   # HIDIOCGRAWINFO
_, vendor, product = struct.unpack("ihh", bytes(buf))
# vendor == 0x28de and product == 0x1304 → to nasz kontroler
```

---

## 2. Typy raportów HID

Strumień `/dev/hidraw0` zawiera trzy typy raportów. Pierwszym bajtem jest zawsze Report ID.

### Report ID `0x45` — główny raport wejściowy (~99% strumienia)

**Długość:** 46 bajtów  
**Częstotliwość:** ~100/s ciągłe  
**Kiedy:** cały czas gdy kontroler jest aktywny i poza dockiem

```
Offset  Rozmiar  Opis
------  -------  ----
[0]     1        Report ID = 0x45
[1]     1        Licznik pakietów (0-255, kołowy)
[2-9]   8        Zera w spoczynku; prawdopodobnie przyciski/wyzwalacze (TODO)
[10]    1        Dane IMU/żyroskop/akcelerometr (ciągle zmienne)
[11]    1        Flaga (1 lub 2, zmienne)
[12]    1        Dane IMU
[13]    1        Flaga (3-4, zmienne)
[14]    1        Dane IMU
[15]    1        Flaga (1-2, zmienne)
[16]    1        Dane IMU
[17]    1        Flaga (1-2, zmienne)
[18-29] 12       Zera
[30-45] 16       Stałe bajty, unikalne per urządzenie (prawdopodobnie device ID lub kalibracja)
```

Przykładowy surowy hex (urządzenie w spoczynku, 4% baterii):
```
451e0000000000000000d6017c02630187020000000000000000000000004cc9f482e1009
0f39a3f0100ffffff
```

Bajty `[30-45]` są CONST dla danego urządzenia:
- `4c c9 f4 82 e1 00 90 f3 9a 3f 01 00 ff ff ff ff`

### Report ID `0x7b` — raport zdarzeniowy

**Długość:** 13 bajtów  
**Częstotliwość:** ~1-2/minutę (event-driven, nie ciągłe)  
**Kiedy:** nieregularnie, niezależnie od aktywności pada

```
Offset  Rozmiar  Opis
------  -------  ----
[0]     1        Report ID = 0x7b
[1]     1        Licznik klatek (varies, np. 245-251)
[2]     1        Stała = 0x01
[3]     1        Nieznane (135-136, minimalnie zmienne)
[4-8]   5        Zera
[9]     1        Jakość RF / siła sygnału? (216-224 przy każdym poziomie baterii)
[10]    1        Nieznane (0x00 lub 0x01 przy 4%, 0x00 przy 50%)
[11]    1        !! PUŁAPKA: NIE bateria — patrz sekcja "Martwe uliczki"
[12]    1        Stała = 0x02 (tryb bezprzewodowy?)
```

Przykłady hex przy ~50% baterii:
```
7bf801880000000300dd003002
7bf501870000000300dd003002
```

Przy 4% baterii (odłączony, na baterii):
```
7bf801860003000500d8001602
7bf701860005000600d7001602
```

Przy 100% baterii (po naładowaniu):
```
7bf801860005000500d8001602   ← byte[11] zmienia się losowo 4-78
```

### Report ID `0x43` — raport telemetryczny ⭐

**Długość:** 15 bajtów  
**Częstotliwość:** ~15 na 15000 odczytów (bardzo rzadki, ~raz/min)  
**Kiedy:** sporadycznie, niezależnie od aktywności

```
Offset  Rozmiar  Opis
------  -------  ----
[0]     1        Report ID = 0x43
[1]     1        Stała = 0x01
[2]     1        ⭐ BATERIA % przy starcie sesji, potem timer sesji ↑
[3]     1        Licznik kołowy (szybko zmienne)
[4]     1        Nieznane (14-16, lekka korelacja z baterią? TODO)
[5]     1        Multipleksowany czujnik A (zmienne: 0x00, 0x28, 0x40, 0x74, 0x88...)
[6]     1        Nieznane (14-16)
[7-12]  6        Zera
[13]    1        Multipleksowany czujnik B (zmienne, patrz niżej)
[14]    1        Multipleksowany czujnik B' (para do byte[13])
```

---

## 3. ⭐ Klucz: Battery % w `0x43 byte[2]`

### Odkrycie (2026-06-30)

`byte[2]` raportu `0x43` zawiera **procent baterii w chwili startu sesji**.  
Po nawiązaniu połączenia ta wartość powoli inkrementuje jako timer sesji (~1/min).

**Dane kalibracyjne:**

| Bateria (szacunek) | byte[2] | Data pomiaru | Uwagi |
|---|---|---|---|
| ~4% | **4** | 2026-06-30 14:28 | Kontroler rozładowany, wł. po bezczynności |
| ~44% | **44** | 2026-06-12 22:56 | Szacunek użytkownika "około 50%" |
| ~97% | **97** | 2026-06-30 19:52 | Po pełnym naładowaniu, ~17 min sesji |

Korelacja jest uderzająca (4→4, 44→44, 97≈100) i wyklucza przypadek.

### Mechanizm

```
byte[2] = battery_pct_at_connect + elapsed_minutes * ~1
```

Przy pierwszym połączeniu (`byte[2]` odczytany jak najwcześniej):
```python
battery_pct = byte[2]  # ≈ faktyczny % baterii
```

Po dłuższej sesji wartość drifuje w górę. Dlatego daemon przechwytuje ją
przy PIERWSZYM 0x43 po każdym połączeniu i zapisuje jako `session_b2`.

### Surowe heksy potwierdzające

**4% baterii (pierwsze raporty po włączeniu):**
```
4301 04 6c0e740e000000000000df68
          ^^ byte[2] = 0x04 = 4
```

**~44% baterii:**
```
4301 2c e20e000f000000000000225c
          ^^ byte[2] = 0x2c = 44
```

**~97% baterii (17 min po połączeniu, pad naładowany):**
```
4301 61 1c1040100000000000003867
          ^^ byte[2] = 0x61 = 97
```

---

## 4. Multipleksowanie w `0x43 byte[13]` — martwa uliczka #1

### Co zaobserwowano

`byte[13]` i `byte[14]` rotują przez kilka różnych par w jednej sesji.
Każda para to prawdopodobnie inny czujnik sprzętowy.

**Obserwowane pary (byte[13], byte[14]) przy różnych poziomach baterii:**

| Para (b13, b14) | hex | Kiedy widoczna | Interpretacja |
|---|---|---|---|
| (34, 92) | `22 5c` | 2026-06-12 ~44% | Jedna para przy 44% |
| (223, 104) | `df 68` | 4% ORAZ 100% | Stały czujnik (NIE bateria!) |
| (95, 98) | `5f 62` | 4% ~14:28 | Czujnik zewnętrzny |
| (149, 101) | `95 65` | 4% + przy 100% po 17 min | Czujnik zewnętrzny |
| (248, 99) | `f8 63` | 4% | Czujnik zewnętrzny |
| (56, 103) | `38 67` | 4% + 100% po 8 min | Czujnik zewnętrzny |
| (139, 106) | `8b 6a` | 100% pierwsze 8 min | Potencjalnie czujnik napięcia |
| (202, 96) | `ca 60` | 4%, rzadka | Czujnik zewnętrzny |

**Kluczowa obserwacja:** `(223, 104)` pojawia się zarówno przy 4% JAK I przy 100%.
To wyklucza ją jako wskaźnik baterii. Wcześniej błędnie ją za taki uznaliśmy.

### Zmiany byte[13] podczas jednej sesji (100% bateria, 2026-06-30)

```
19:35 → 19:44  (0-8 min):    cycles(139, 223)
19:44 → 19:52  (8-17 min):   cycles(56, 223)
19:52 →         (17+ min):   cycles(56, 149)
```

Wartość w byte[13] **zmienia się nawet przy stałym poziomie baterii** — to potwierdza
że jest to multiplekser czujników, nie bezpośrednie kodowanie baterii.

### Próba filtru matematycznego (PORZUCONA)

Przez pewien czas próbowaliśmy identyfikować parę bateryjną przez linię prostą:
```python
# Linia przez (34,92)@50% i (223,104)@4%
def battery_line(b13):
    return 92 + (b13 - 34) * (104 - 92) / (223 - 34)
```
Filtr działał dla 2 punktów kalibracyjnych, ale okazał się błędny — `(223,104)` to
NIE jest para bateryjna. Porzucono na rzecz `byte[2]`.

---

## 5. `0x7b byte[11]` — martwa uliczka #2

Przez pewien czas podejrzewaliśmy, że `byte[11]` w raporcie `0x7b` to procent baterii.

**Dlaczego to fałszywy trop:**

| Czas | byte[11] | Stan baterii |
|---|---|---|
| 14:28 (świeżo włączony) | 48 | ~4% |
| 14:32 | 38 | ~4% (bez ładowania!) |
| 14:35 | 20 | ~4% (spadek mimo braku ładowania) |
| 19:35 (naładowany) | 4 | 100% (!!!) — wartość MNIEJSZA niż przy 4% |
| 19:36 | 78 | 100% |
| 19:37 | 56, 76, 46, 64... | 100% — losowe oscylacje |

Wartość oscyluje 36-78 przy 100% i jest MNIEJSZA przy 100% niż przy 4%.
To zdecydowanie NIE jest bateria. Prawdopodobnie licznik pakietów RF, RSSI lub inny
wskaźnik połączenia bezprzewodowego.

---

## 6. Inne obserwacje

### `0x43 byte[2]` jako timer sesji

Po starcie sesji `byte[2]` powoli rośnie. Tempo: ~1 jednostka na ~1 minutę.  
Po ~12 minutach sesji przy 100% baterii: byte[2] = 97 (start był ~85-100).

Oznacza to że przy długich sesjach wartość będzie wyższa od faktycznej baterii.
**Rozwiązanie:** przechwytuj PIERWSZY 0x43 raportu po połączeniu.

### `0x43 byte[4]` i `byte[6]`

Lekka zmiana wraz z baterią:
- 4% bateria: `0x0e` (14) i `0x0e` (14)
- ~44% bateria: `0x0e` (14) i `0x0f` (15)  
- ~100% bateria: `0x10` (16) i `0x10` (16)

Mogą być ADC odczytem napięcia ogniwa (bardzo powolna zmiana w zakresie 20-80%,
szybsza na skrajach). **TODO:** więcej danych do potwierdzenia.

### `0x45 byte[30-45]` — stałe per-device

```
4c c9 f4 82 e1 00 90 f3 9a 3f 01 00 ff ff ff ff
```
Te 16 bajtów jest stałe przez całą sesję i prawdopodobnie przez życie urządzenia.
Może to być unikalny identyfikator urządzenia, dane kalibracji fabrycznej lub klucz BT.

### `0x7b byte[9]`

Stały w zakresie 216-224 niezależnie od baterii i aktywności.  
Prawdopodobnie: siła sygnału RF lub jakość połączenia (wysoka = dobra).

### Kontroler na docku (pucku)

Gdy kontroler jest na doku ładującym:
- `/dev/hidraw0` może nadal istnieć (BT) ale nie wysyła danych 0x45
- `select()` zwraca timeout (silence)
- Demon interpretuje ciszę jako "pad na pucku / ładowanie"

---

## 7. Architektura implementacji

### Demon Python

**Lokalizacja:** `/var/home/jahrek/.local/bin/sc-battery-daemon`  
**Autostart:** `/var/home/jahrek/.config/autostart/sc-battery-daemon.desktop`

**Schemat działania:**
```
loop:
    find_sc_hidraw()          ← skanuje hidraw0-19 po VID:PID
    open(O_RDONLY)
    read hidraw continuously:
        0x43 → first report: capture byte[2] as battery_pct
        every 3000 reads: write /tmp/sc-battery.json
    on IOError: reconnect
```

**Format JSON `/tmp/sc-battery.json`:**
```json
{
    "battery_pct": 97,
    "connected": true,
    "charging": false,
    "last_seen": "19:52",
    "provisional": false,
    "updated_at": "2026-06-30T19:52:56"
}
```

Plik aktualizowany atomowo przez `rename()` żeby uniknąć partial reads w QML.

### Widget KDE Plasma 6

**Lokalizacja:** `/var/home/jahrek/.local/share/plasma/plasmoids/com.jahrek.steamcontroller/`

```
com.jahrek.steamcontroller/
├── metadata.json
└── contents/
    └── ui/
        └── main.qml
```

**Ważne pułapki Plasma 6:**

1. `PlasmaCore.DataSource` został USUNIĘTY w Plasma 6.  
   Poprawny import: `import org.kde.plasma.plasma5support as P5Support`  
   i `P5Support.DataSource { engine: "executable" }`

2. `metadata.json` MUSI zawierać `"KPackageStructure": "Plasma/Applet"`.  
   Bez tego widget nie pojawia się na liście.

3. `kpackagetool6 --upgrade` kasuje katalog przy błędzie — lepiej pisać pliki
   bezpośrednio i restartować plasmashell.

4. `XMLHttpRequest` z `file://` nie działa w sandboxie Plasma — stąd `P5Support.DataSource`
   z `cat /tmp/sc-battery.json`.

5. Restart plasmashell po zmianach:
   ```bash
   kquitapp6 plasmashell && kstart plasmashell
   ```

**Odczyt JSON w QML:**
```qml
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []
    onNewData: function(source, data) {
        var d = JSON.parse(data["stdout"])
        root.batteryPct = d.battery_pct ?? -1
        root.connected  = d.connected   ?? false
        disconnectSource(source)
    }
    function poll() {
        connectSource("cat /tmp/sc-battery.json 2>/dev/null || echo '{}'")
    }
}
Timer { interval: 30000; running: true; repeat: true;
        triggeredOnStart: true; onTriggered: runner.poll() }
```

---

## 8. Narzędzia badawcze

Wszystkie w `/var/home/jahrek/Claude Code/steam-controller-battery/`:

| Plik | Opis |
|---|---|
| `sc_dump.py` | Zapisuje surowy strumień HID do pliku tekstowego (hex) |
| `sc_filter.py` | Filtruje strumień po Report ID, zlicza N raportów danego typu |
| `sc_monitor.py` | Analiza statystyczna bajtów (CONST vs VARIES) dla danego raportu |
| `sc_charge_monitor.py` | Monitor ładowania: loguje 0x43 i 0x7b do pliku, auto-reconnect |

### Użycie

```bash
# Zbierz 15000 raportów 0x43
python3 sc_filter.py /dev/hidraw0 15000 43

# Zbierz 8000 raportów 0x7b
python3 sc_filter.py /dev/hidraw0 8000 7b

# Analiza bajtów raportu 0x45 (8000 próbek)
python3 sc_monitor.py /dev/hidraw0 45 8000

# Monitor ładowania (loguje do sc_logs/)
python3 sc_charge_monitor.py sc_logs/moja_sesja.txt
```

---

## 9. Logi kalibracyjne

Zebrane dane w `sc_logs/`:

| Plik | Opis |
|---|---|
| `sc_monitor_4pct_20260630_1428.txt` | Analiza bajtów 0x45 i 0x7b przy ~4% baterii |
| `sc_4pct_20260630_1428.txt` | 60 raportów 0x7b przy 4% — surowe hex |
| `sc_43_4pct_20260630_1430.txt` | 16 raportów 0x43 przy 4% — surowe hex |
| `sc_45pct_20260612_2255.txt` | 20 raportów 0x7b przy ~44% baterii |
| `sc_monitor_50pct_20260612_2256.txt` | Analiza bajtów przy ~44% (2 raporty 0x43) |
| `sc_charging_20260630_1510.txt` | Sesja ładowania (4% → naładowany), nieukończona |
| `sc_100pct_20260630.txt` | Monitor przy 100% — ~20 min danych, kluczowe obserwacje |

---

## 10. Nierozwiązane pytania / TODO

### Wysokie priorytety
- [ ] **Czego są `0x43 byte[4]` i `byte[6]`?** Czy to ADC napięcia? Zebrać dane przy 20%, 50%, 80%.
- [ ] **Czy da się wysłać Feature Report zapytanie o baterię?** Starego SC można było
  "zapytać" przez HIDIOCGFEATURE. Nieznane raporty wyjściowe nowego.
- [ ] **Wykrywanie ładowania.** Czy kontroler wysyła cokolwiek specyficznego gdy jest na
  doku i się ładuje? Daemon zakłada "silence = ładowanie" co jest przybliżeniem.
- [ ] **Kalibracja byte[2] przy niskich wartościach.** Czy 4→4% jest dokładne też dla
  2%, 1%? Czy kontroler odcina się zanim osiągnie 0?

### Niższe priorytety
- [ ] **Zdekodować 0x45 przyciski.** Jakie bity odpowiadają przyciskom A/B/X/Y, triggerom,
  touchpadom? Patrz bytes [2-9] które są zero w spoczynku.
- [ ] **0x45 byte[10-17] — IMU.** Prawdopodobnie żyroskop + akcelerometr. 4 pary
  (wartość, flaga) — dekodować format (big/little endian? signed?).
- [ ] **0x45 byte[30-45] — device ID.** Porównać między egzemplarzami.
- [ ] **Tray icon dla Plasma.** Oddzielny typ plasmoid (StatusNotifierItem).
- [ ] **Tryb wired (USB).** Czy hidraw działa inaczej przez kabel?
- [ ] **Dane o stanie RF.** Czy byte[9] w 0x7b to RSSI? Jak reaguje na odległość?
- [ ] **hid-steam.c contribution.** Docelowo zintegrować z kernelem dla natywnego wsparcia.

### Pytania bez odpowiedzi
- **Co to są `0x43 byte[13]/byte[14]`?** Rotujące czujniki, ale jakie konkretnie?
  Temperatura, napięcie, prąd? Potrzeba sprzętu do analizy energetycznej.
- **Dlaczego 0x43 jest tak rzadki (~1/1000)?** Może do triggerowania go jest Feature Report?
- **Czym jest byte[12] w 0x7b (`0x02`)?** Stała — może encoding trybu BT?

---

## 11. Środowisko deweloperskie

- **System:** Bazzite Linux (Fedora-based, immutable)
- **DE:** KDE Plasma 6.7.1
- **GPU:** RTX 4090
- **CPU:** i9-13900K
- **Path uwaga:** `/var/home/jahrek` i `/home/jahrek` to ten sam inode,
  ale `kpackagetool6` zachowuje się inaczej — używać `/var/home/jahrek`

---

## 12. Oś czasu badań

```
2026-06-12  Pierwsze zbieranie danych przy ~44% baterii.
            2 próbki 0x43 z byte[2]=44 (0x2c).
            Błędna hipoteza: byte[13]=34 to kalibracja baterii.

2026-06-30  Zbieranie danych przy 4% baterii.
            16 próbek 0x43 z byte[2]=4 (0x04).
            Odkrycie że (223,104) pojawia się stale — to NIE bateria.

2026-06-30  Pełne ładowanie (4% → 100%, ~4h).
            Monitor ładowania uruchomiony podczas ładowania.

2026-06-30  Dane przy 100%: byte[2]=97 (0x61).
            Przełom: byte[2] koreluje z %! 4→4%, 44→44%, 97≈100%.
            Daemon przepisany pod byte[2].
            Testy: JSON pokazuje 97%, widget wyświetla poprawnie.
```
