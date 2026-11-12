# Power telemetry feasibility

Investigated 2026-11-12 for the connected Ant Esports MK1300 V2, VID 36AE / PID FE12.

## Result

No usable source of measured keyboard current, voltage, or wattage was found in the inspected macOS registry or official software protocol paths. A genuine once-per-second wattage readout cannot currently be implemented from those sources. Do not present the USB power allocation or an RGB-based estimate as measured consumption.

## Observations

- The keyboard IOUSBHostDevice reports `UsbPowerSinkAllocation = 500`. Its power management properties describe discrete states, not electrical measurements. The scoped USB/IOService subtree exposes no measured amperage, voltage, wattage, or energy counters. Three registry samples one second apart had the same allocation/state.
- Apple documents USB configuration power requirements as the maximum required bus current, not sampled draw: https://developer.apple.com/documentation/iousbhost/parsing-usb-descriptors and https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBOverview/USBOverview.html.
- The official Electron app's `getKeyboardConfig()` sends `[6, 5]`. Its decoded fields are version, PID, firmware, work mode, link status, battery, charging state, profiles, layers, optional sleep time and serial. Battery percentage/charging state are not measurements of USB current or power. The live device returns 14 config bytes.
- A bounded search of the extracted official JavaScript for battery, voltage, amperage, watts, power and corresponding Chinese electrical terms found no electrical telemetry implementation. Power references found in key definitions refer to the system Power key; other references include UI animation parameters and generic battery features for other supported devices.
- The existing probe's read-only `diagnose` operation succeeded for config, lighting config and color readback. No unknown opcodes were sent.

## Artifact and analysis evidence

REA CLI 6.4.0 analyzed the official packaged `app/resources/app.asar` (SHA-256 `b8251094ec2595d418fd34b14cfe09bb9cd76f4c8d0152292ee1a82f147a39a4`).

Evidence ID: `ev_eb8bac2a6a00139f86fedf87434710da3557e8438c625cf8640e4f03e75e9348`.

Inventory: 212 relevant files; 195 JavaScript files parsed, zero parse failures. Expanded semantic graph coverage was incomplete due to result/memory budgets; static observations were retained. This is not proof that undocumented firmware commands or physical sensing hardware do not exist.

Manual code inspection used the extracted `build/_next/static/chunks/app/page-eb8e7cd4112363c5.js`, SHA-256 `1a51310f44f31e8128212034acf61071d82d46f641f7a3794f70fbaf27c702d4`, matching the artifact identity recorded by REA. The config parser and search conclusions above come from manual static inspection, not runtime observation of the Windows app.

Local raw evidence is retained in `/tmp/mk1300-power-rea.json`, `/tmp/mk1300-power-summary.json`, `/tmp/mk1300-usb-services.plist`, and `/tmp/mk1300-power-diagnose.log` for this investigation. These temporary paths are not portable repo artifacts.

## Feasible next steps

Actual power monitoring needs a measurement source, such as an inline USB power meter with USB data passthrough and a documented computer-readable telemetry interface. Its voltage and current samples could be polled each second and watts computed as volts times amps. A display-only meter cannot automatically feed the app.

A software estimate based on lit keys and RGB intensity is possible, but requires device-specific calibration and remains an estimate, especially for firmware animations whose instantaneous LED output is not known to the app. No arbitrary constants or simulated live readings were added.
