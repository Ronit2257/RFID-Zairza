# Firmware baseline

The existing sketch was relocated without changing its bytes.

- Original: `Zairza_Workinginprocess.ino`
- Current: `firmware/esp32/Zairza_Workinginprocess/Zairza_Workinginprocess.ino`
- SHA-256: `bc8bb51a6a2564336078db19bcfd0a78b3f103e41937ca5a9b8ba1d5b032ea1a`
- Sketch folder matches the sketch filename for Arduino IDE use.
- Hardware operation is reported working by the project owner; no hardware build or live scan was performed during repository organization.

Source observations relevant to the reader application:

- Events contain the eight documented spreadsheet fields.
- Device time uses India Standard Time; displayed scan time has minute precision.
- Offline events can arrive after newer events.
- Per-card tap counters initialize to zero on device startup; supplied actions can therefore repeat after a restart.
- The firmware expects an existing LittleFS students.csv and SD audio assets. These are not present in this repository; moving the sketch does not recreate them.

The mobile project must consume the recorded actions and surface anomalies rather than rewrite hardware behavior.
