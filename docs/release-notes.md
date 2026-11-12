Keylume is an RGB studio for the **Ant Esports MK1300 V2**, 61-key / 60% mechanical keyboard (USB 36AE:FE12).

- Native SwiftUI macOS app with a searchable preset library and menu bar controls.
- New portable Windows x64 app with native HID and a system tray.
- Hostable static web editor, 140 Kicktroll presets, and the RS monogram.
- New Keylume name and keycap logo.
- Reorganized source and automated build/release workflows.

**Downloads:** macOS universal ZIP (unzip and move Keylume.app to Applications), Windows portable EXE, or Web ZIP for HTTPS self-hosting. Checksums are in SHA256SUMS.txt.

The macOS bundle is signed ad hoc and is not notarized; the Windows executable is unsigned. Existing macOS presets are preserved through the unchanged bundle identifier. Remove the previous MK1300-RGB.app after upgrading. Close other RGB software before connecting.

Windows packaging/native HID loading are smoke-tested in CI. Physical Windows keyboard operation has not yet been verified. Supported desktop browsers are required for web device control; the native apps do not use browser HID permissions.
