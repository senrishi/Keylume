# Keylume · Web

A standalone static WebHID editor for the Ant Esports MK1300 V2 (36AE:FE12). Paint any of the 61 keys, control brightness, apply 14 firmware effects, browse 140 Kicktroll presets and the RS monogram, save personal presets, and export/import JSON.

## Run locally

From this directory:

```sh
npm test
npm run build
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open http://localhost:4173 in desktop Chrome or Edge. Node is only needed to run the tests/build; the output has no server or npm runtime dependency. No packages need installing.

## Host on your homelab

Serve the **contents of `apps/web/dist`** from any static host (Caddy, Nginx, Apache, or a NAS web server). The app uses relative asset URLs, so it can also live under a subdirectory. Serve it over **HTTPS** for remote/LAN access: a plain HTTP LAN IP does not qualify as a secure context for WebHID. Localhost is the development exception.

Optional Docker image, built from `apps/web/`:

```sh
docker build -t mk1300-studio .
docker run -d --name mk1300-studio -p 127.0.0.1:8080:80 mk1300-studio
```

Place your existing HTTPS reverse proxy in front of port 8080. For example, a Caddy site block for a domain you control:

```caddy
rgb.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Configure DNS and certificate issuance for your environment. No USB device needs to be passed into the container: the **visitor's browser** communicates with the keyboard plugged into the visitor's computer. Hosting this app does not enable remote control of a keyboard left attached to the homelab server.

## Browser/device support

Use a desktop browser that exposes WebHID (normally Chrome or Edge). Safari, Firefox, and mobile browsers may support offline layout editing but do not support this app's keyboard connection. Browser support and device access are separate: the keyboard's vendor collection must expose output reports. The app requests only VID 36AE / PID FE12, usage page FF00, usage 2. Close the native RGB app before connecting.

Some browsers protect this keyboard's report IDs even when the vendor collection exists. The app detects unavailable output reports and provides an explanation; it does not disable browser security controls. Linux may additionally need hidraw device permissions. See https://developer.chrome.com/docs/capabilities/hid.

## Presets and privacy

Personal presets are stored in `localStorage` under `mk1300-studio-v1`. There is no preset session token, account, database, or network sync. Different browsers, profiles, computers, and origins have independent preset stores. Clearing site data clears personal presets. JSON export/import transfers layouts and firmware settings between machines and hosting origins. Import validates all 61 key colors and supported lighting settings. Imported layouts must be saved explicitly to persist.

The Sites-hosted copy can have its own hosting access control; this does not synchronize preset data. Browser-granted HID permission is also separate from preset storage. Permissions are requested on each browser/origin. No keypress input is captured; only RGB configuration acknowledgments are handled. The optional Google Fonts stylesheet is the only third-party styling dependency; system font fallbacks work without it.

## Protocol and verification

The driver serializes keyboard transactions, validates acknowledgments and effect readback, and blocks commands outside a small RGB/config allowlist. It preserves the FE12's returned config type 1 when writing firmware effects. Static layouts scale RGB channels before sending all 61 colors; firmware effects use the hardware brightness steps. Only Apply changes keyboard lighting.

`npm test` uses a simulated device to exercise the verified command shapes, config type regression, color offsets, RGB scaling, report matching, rejected commands, readback failures, and preset imports. This does not replace a live browser/device test. Native IOKit communication previously verified on this keyboard does not guarantee WebHID access in every browser.

No power measurement is simulated or exposed. Hardware animation previews are symbolic; the keyboard renders motion.

## Credits

The Kicktroll preset catalog is derived from https://github.com/kicktroll/mk1300v2_RGB. See `attribution.txt` and `LICENSE-presets.txt` for attribution and Apache-2.0 terms. The RS monogram comes from this repository's `shared/presets/RS.json`.
