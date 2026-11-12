# MK1300 RGB for macOS

Native SwiftUI per-key RGB editor and firmware effect controller for the Ant Esports MK1300 V2 (36AE:FE12). Includes brightness control, saved layouts, and 140 attributed Kicktroll presets.

## Build

Requires macOS 13+ and Xcode Command Line Tools. Run `zsh build.sh`. The signed app is generated at `dist/MK1300-RGB.app`; the build verifies the 61-key layout, brightness scaling, and bundled presets without changing keyboard lighting.

The installed app lives at `/Applications/MK1300-RGB.app`. Move the built bundle there after quitting the running app, replacing the previous installation. Keep only this installed copy; do not retain duplicate app bundles or app archives.

## Keyboard protocol

`rgb-probe` uses the vendor HID interface (usage page FF00, usage 2). Firmware effects preserve the config type returned by the keyboard (type 1 on FE12); forcing type 0 causes writes to time out. Effect writes require acknowledgment and mode, brightness, and speed readback.

The `mk1300v2_RGB` submodule contains the upstream browser project used to import presets. Attribution and its license are bundled in `Resources/`.

## Web app

The complete browser version lives in [`web/`](web/README.md). Build with `cd web && npm run build`, then host `web/dist` over HTTPS. Personal presets are browser-local and transferable via JSON; no backend is required.

## Native app 1.4

The native studio has a searchable preset library, saved-layout tab, RGB key previews, brush swatches, and separate lighting controls. The cyan, pink, and green bars icon in the macOS menu bar opens quick controls for brightness, applying saved layouts, restoring/applying the current layout, and turning lights off. Changing brightness is a preview until Apply is pressed; choosing a preset from the menu bar applies it immediately.

Closing the editor leaves the menu bar controls running. Choose **Open RGB Studio** to reopen it or **Quit** to exit the app. The menu bar and editor share one state and one in-flight keyboard operation. Lights Off preserves the layout, and the last successfully applied layout is restored in the editor on the next launch without automatically writing to the keyboard. Existing saved presets and brightness preferences are retained.

The hosted web app is configured for public access at https://mk1300-rgb-studio.earlyactor1.chatgpt.site; anonymous HTTP access was verified after the access policy propagated.
