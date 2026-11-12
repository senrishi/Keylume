# Keylume for Windows

Portable Windows x64 RGB editor for the **Ant Esports MK1300 V2** (36AE:FE12). Uses the shared web UI offline with an isolated Electron preload and native `node-hid` transport, so browser HID restrictions do not apply. Supports per-key layouts, firmware effects, saved presets, JSON import/export, and a tray icon.

```sh
npm ci
npm test
npm run dist
```

Run on a Windows machine with Node 22+. Output is `dist/Keylume-<version>-Windows-x64.exe`. `npm start` runs a development copy. The packaging script copies the current web UI and branded assets into ignored `ui/` and `assets/` directories. No host account is needed. Presets are in the local Electron profile; use JSON export/import for backups/transfers. Close hides the window; the tray menu reopens it or quits.

CI smoke-tests the unpacked packaged executable with `--self-test`, validating the UI files, preset catalog, app icon, and native HID module enumeration without changing a keyboard. This does not validate physical lighting behavior. Only the matching vendor configuration interface can be opened. Multiple matching keyboards are rejected to avoid changing the wrong keyboard.
