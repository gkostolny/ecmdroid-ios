# ECMDroid for iOS

An iOS port of [ECMDroid](https://github.com/ecmdroid/ecmdroid) — a diagnostic
tool for Buell motorcycles with DDFI, DDFI-2, and DDFI-3 engine control modules.

The app talks to the bike's diagnostic port through a Bluetooth Low Energy
serial adapter (such as the BUELLtooth dongle) and provides:

- **Live data** — real-time engine channels (RPM, TPS, temperatures, voltages, …)
- **Trouble codes** — current and stored DTCs with plain-language descriptions
- **EEPROM editor** — read, edit, and burn ECM EEPROM values, with automatic
  as-read backups, named snapshots, and staged restore (nothing is written
  until you explicitly burn)
- **Data logging** — record runtime data and export it as MSL for
  MegaLogViewer / Excel / Numbers
- **Active tests** — trigger device tests (fuel pump, coils, injectors, fan, …)
- **Torque reference** — fastener torque specs for XB models

## Requirements

- Xcode 16 or later, iOS 17+
- A supported BLE serial adapter wired to the bike's diagnostic connector:
  - CC254x / HM-10 style modules (service `FFE0`, including split-characteristic
    variants like BUELLtooth)
  - Nordic UART (NUS)
  - Microchip RN4870
  - Telit TIO (credit-based flow control)

## Building

Open `ECMDroid.xcodeproj` in Xcode, select your own development team under
Signing & Capabilities, and run on a device. (The iOS Simulator has no
Bluetooth — see below for how to develop without hardware.)

## Developing without a motorcycle

The upstream project provides [ecmsim](https://github.com/ecmdroid/ecmsim),
a TCP-based ECM simulator. This repo integrates it:

```sh
brew install openjdk   # one-time, if you don't have Java
./run-ecmsim.sh        # clones, patches, builds, and starts the simulator
```

Then in the app: **Connect tab → ECM Simulator (TCP)**. From the iOS
Simulator use host `127.0.0.1`; from a phone use your Mac's LAN IP (the
script prints it). The full protocol stack — EEPROM editing, logging,
DTCs — works against the simulated ECM.

## Tests

```sh
./run-tests.sh
```

Compiles the transport/protocol/model layers into a macOS test binary and
runs ~30 unit and integration tests against a private ecmsim instance on a
dedicated port. No simulator or device needed. Please keep it green and add
tests alongside new protocol or model code.

## Safety

Burning EEPROM values changes how the engine runs. The app takes an automatic
backup the first time it reads an EEPROM and refuses to restore mismatched
dumps, but ultimately **you are writing to your motorcycle's ECU at your own
risk**. Keep backups. Don't burn with the engine running.

## License & credits

Licensed under the [GNU General Public License v3.0](LICENSE).

This is a derivative work of [ECMDroid](https://github.com/ecmdroid/ecmdroid),
Copyright © 2012 Michel Marti, licensed under GPL-3.0. The ECM definition
database (`ecmdroid.db`) comes from that project. The
[ecmsim](https://github.com/ecmdroid/ecmsim) simulator (GPL-3.0) is fetched at
first use by the helper scripts; a small local resilience patch is kept in
[`patches/`](patches/).
