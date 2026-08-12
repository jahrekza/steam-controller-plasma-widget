# Steam Controller 2 (2026) — Battery HID Reverse Engineering

## Cel
Zlokalizować bajt(y) reprezentujące poziom baterii w surowych raportach HID
Steam Controller 2nd gen (2026), żeby zbudować widget KDE Plasma pokazujący
battery % i status połączenia. Cel finalny: kontrybucja do społeczności
Bazzite/KDE (widget + ew. patch do kernela `hid-steam`).

## Sprzęt
- Steam Controller (2nd gen / "Triton"), wydany 4 maja 2026
- VID:PID = `28de:1304` ("Steam Controller Puck" — dongle USB)
- Bus 3 (USB), 5x hidraw interfejsy (hidraw0–4), tylko **hidraw0** ma żywe dane
- System: Bazzite Linux (Fedora-based, rpm-ostree), KDE Plasma

## Stan sterownika
Sterownik kernela widzi urządzenie jako `hid-generic` (NIE `hid-steam`) —
istniejący `hid-steam.c` w kernelu Linux jest pisany dla **starszego**
Steam Controllera (2018) i nie rozpoznaje nowego PID. Stąd:
- `/sys/class/power_supply/` — PUSTE, brak ekspozycji baterii przez kernel
- `upower -e` — tylko `DisplayDevice`, brak urządzenia pada
- Trzeba czytać surowy strumień przez `/dev/hidraw0`

## Report descriptor
Usage Page `0xFF00` — w pełni proprietarny protokół Valve, BEZ standardowych
usage'ów (np. Battery Strength 0x06/0x20). Bateria, jeśli jest w strumieniu,
jest zakodowana jako "magiczny bajt" bez deklaracji semantycznej —
identyfikacja możliwa tylko empirycznie (porównanie różnych stanów baterii).

Pełny hex deskryptora w historii projektu (372 bajty na hidraw0-3, 54 bajty
na hidraw4).

## Zidentyfikowane raporty (Report ID = pierwszy bajt)

| Report ID | Rozmiar | Częstotliwość | Charakter |
|---|---|---|---|
| **0x45** | 46 bajtów | continuous (~99% strumienia) | Main input: przyciski, analogi (bajty 10-17), IMU/accel/gyro (bajty 30-39, stałe gdy pad leży nieruchomo) |
| **0x7b** | 13 bajtów | event-driven (rzadki, ~15-60 / 8000-15000 odczytów) | **Najbardziej obiecujący kandydat na status/telemetrię** |
| **0x43** | 15 bajtów | bardzo rzadki (2-16 / 8000-15000) | Możliwe: config/firmware/battery info |

## Dane referencyjne — porównanie stanów baterii

### ~50% baterii (12 czerwca 2026, 22:55-22:56)
Plik: `sc_logs/sc_45pct_20260612_2255.txt`, `sc_logs/sc_monitor_50pct_20260612_2256.txt`

**Report 0x43** (2 próbki, identyczne):
```
43012ce20e000f000000000000225c
```
- byte[13] = **0x22 (34)** — STAŁE

**Report 0x7b** (15 próbek w monitorze):
- byte[3] VARIES 134-136
- byte[9] VARIES 220-221
- byte[11] = CONST 0x32 (50) -- *podejrzane, ale prawdopodobnie zbieg okoliczności, nie battery%*

### ~4% baterii (30 czerwca 2026, 14:xx) — kilka tygodni później
Plik: `sc_logs/sc_4pct_*.txt`, `sc_logs/sc_monitor_4pct_*.txt`, `sc_logs/sc_43_4pct_*.txt`

**Report 0x43** (16 próbek, stabilizuje się):
```
4301046c0e740e000000000000df68   (najczęstsza wartość, 9/16)
```
- byte[5] = VARIES 0x6b-0x6d (107-109) -- **nowy ruchomy bajt, był inny w 50% dump**
- byte[13] = **0xdf (223)** — STABILNE po kilku próbkach (pierwsze 2 próbki w monitor_4pct miały anomalię 139/223, prawdopodobnie przejściowe)

**Report 0x7b** (15 próbek w monitorze):
- byte[3] VARIES 135-136
- byte[9] VARIES 218-219
- byte[11] = CONST 0x30 (48)

## Kluczowa obserwacja — GŁÓWNY KANDYDAT

**Report 0x43, byte[13]:**
- 50% baterii → `0x22` = 34 (dziesiętnie)
- 4% baterii → `0xdf` = 223 (dziesiętnie)

Zależność NIE jest prostym liniowym % (34→223 rosnąco przy spadku baterii
sugeruje albo odwróconą skalę, albo inną jednostkę — np. surowe napięcie
ADC, gdzie wartość rośnie/maleje nieliniowo, lub wartość może zawijać się
(wraparound) w jakimś zakresie).

**Hipotezy do zweryfikowania:**
1. To surowe napięcie baterii (Li-ion 8.39 Wh) zakodowane jako single-byte
   ADC reading ze skalowaniem — wymaga kalibracji w 2-3 punktach
   (pełne 100%, ~50%, ~4%, idealnie też podczas ładowania)
2. To może być wartość ze znakiem (int8) lub mieć inny offset/scaling
3. Może wymagać dodatkowego bajtu sąsiedniego (byte[5] w 0x43 też się
   zmienił między pomiarami — możliwe że to wieloajtowa wartość)

**Report 0x43, byte[5]** również się zmienił:
- 50% → VARIES [0, 236] (niespójne, mało próbek)
- 4% → VARIES [0x6b-0x6d] = 107-109 (stabilniejsze)
Wymaga więcej danych do potwierdzenia czy jest skorelowany z baterią.

## Narzędzia (w tym folderze)

- **`sc_dump.py`** — zrzut HID report descriptora (`HIDIOCGRDESC` ioctl)
  Użycie: `sudo python3 sc_dump.py /dev/hidraw0`

- **`sc_monitor.py`** — zbiera N próbek ze strumienia, grupuje po Report ID,
  pokazuje które bajty są CONST vs VARIES (i w jakim zakresie)
  Użycie: `sudo python3 sc_monitor.py /dev/hidraw0 2000`

- **`sc_filter.py`** — filtruje strumień do konkretnego Report ID, wypisuje
  surowy hex każdej próbki
  Użycie: `sudo python3 sc_filter.py /dev/hidraw0 8000 43`
  (ostatni argument: report ID w hex, bez "0x")

## Metodologia zbierania danych

WAŻNE: replikować warunki między pomiarami:
- Pad w tym samym fizycznym miejscu i orientacji (minimalizuje szum IMU
  w raporcie 0x45, choć nie powinno wpływać na 0x43/0x7b)
- Raport 0x43 jest rzadki — potrzeba dużo próbek (`n=15000` dało tylko 16
  trafień), więc dla pewnych danych warto zwiększać `n` w `sc_filter.py`

## Następne kroki

1. **Złapać więcej próbek 0x43 przy różnych poziomach baterii** — szczególnie
   przy **pełnym naładowaniu (100%)** i **podczas ładowania na pucku**
   (jeśli pad ma taką funkcję), żeby mieć min. 3-4 punkty kalibracyjne
2. Zbudować tabelę: battery_reported_% → byte[13] (i ew. byte[5]) →
   dopasować funkcję (liniową, czy inną)
3. Sprawdzić czy `byte[5]` i `byte[13]` razem tworzą 16-bit wartość
   (little/big endian) — częsta praktyka w HID dla precyzyjniejszych
   odczytów napięcia
4. Po namierzeniu offsetu: napisać daemon Python czytający `/dev/hidraw0`,
   wystawiający wartość przez D-Bus lub plik w `/tmp`, który KDE Plasma
   widget (QML) mógłby odpytywać
5. Rozważyć też zgłoszenie znalezisk do:
   - SDL issue: https://github.com/libsdl-org/SDL/issues/15471
   - Kernel `hid-steam.c` maintainerzy (Rodrigo Rivas Costa i in.)

## MVP widgetu (cele funkcjonalne)
**Priorytet 1:** battery % + connection status
**Priorytet 2 (nice to have):** charging indicator, signal strength,
sleep/idle state

## Kontekst osobisty
Projekt prowadzony przez Jahrek/Jarek, Bazzite (KDE Plasma), RTX 4090,
i9-13900K. Celem jest stworzenie rozwiązania społecznościowego (open source,
kontrybucja do Bazzite/KDE), a nie czekanie na oficjalne wsparcie
kernela/SDL — mimo że temat jest już śledzony w SDL issue tracker.
