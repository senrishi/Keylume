#include <IOKit/hid/IOHIDLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>

static uint8_t input[128], response[64];
static unsigned reports;
static uint8_t expected_command;
static size_t received;

static void on_report(void *context, IOReturn result, void *sender,
                      IOHIDReportType type, uint32_t id, uint8_t *report,
                      CFIndex length) {
    reports++;
    fprintf(stderr, "RX callback: status=0x%x id=%u len=%ld", result, id, (long)length);
    for (CFIndex i = 0; i < length && i < 24; i++) fprintf(stderr, " %02x", report[i]);
    fputc('\n', stderr);
    if (result == kIOReturnSuccess && length == 64 && report[0] == 0xaa && report[1] == expected_command) {
        memcpy(response, report, 64);
        received = 64;
    }
}

static int exchange(IOHIDDeviceRef device, const uint8_t packet[64]) {
    received = 0;
    reports = 0;
    expected_command = packet[1];
    fprintf(stderr, "TX: %02x %02x %02x (%zu bytes)\n", packet[0], packet[1], packet[2], sizeof(response));
    IOReturn status = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, packet, 64);
    if (status != kIOReturnSuccess) {
        fprintf(stderr, "HID write failed: 0x%x\n", status);
        return 0;
    }
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 1.5;
    while (!received && CFAbsoluteTimeGetCurrent() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    if (!received) {
        fprintf(stderr, "No matching response to command %02x (%u callbacks)\n", packet[1], reports);
        return 0;
    }
    printf("%02x:", packet[1]);
    for (size_t i = 0; i < 20; i++) printf(" %02x", response[i]);
    puts("");
    return 1;
}

static const struct { const char *name; uint8_t index; } key_map[] = {
#include "key-map.h"
};

static int enable_custom_mode(IOHIDDeviceRef device) {
    if (response[7] == 22) return 1;
    if (!exchange(device, (uint8_t[64]){6, 22, 0, 0, 0, 1, 0, 22})) return 0;
    uint8_t mode[64] = {6, 11, 11};
    memcpy(mode + 5, response + 5, 11);
    mode[7] = 22;
    return exchange(device, mode) && response[2] == 1;
}

static int apply_effect(IOHIDDeviceRef device, uint8_t effect, uint8_t brightness, uint8_t speed) {
    if (!exchange(device, (uint8_t[64]){6, 22, 0, 0, 0, 1, 0, effect}) ||
        response[2] != 11 || response[7] != effect) {
        fputs("Keyboard did not return the requested effect template.\n", stderr);
        return 0;
    }

    uint8_t packet[64] = {6, 11, 11};
    memcpy(packet + 5, response + 5, 11);
    // Preserve the device-provided config type (FE12 returns type 1).
    packet[8] = brightness;
    packet[9] = speed;
    static const uint8_t intensity[] = {30, 80, 140, 200, 236};
    packet[15] = effect == 0 ? 0 : intensity[brightness];
    if (!exchange(device, packet) || response[2] != 1 ||
        !exchange(device, (uint8_t[64]){6, 10}) || response[7] != effect ||
        response[8] != brightness || response[9] != speed) {
        fputs("Keyboard did not confirm the requested effect.\n", stderr);
        return 0;
    }
    return 1;
}

static int write_color(IOHIDDeviceRef device, unsigned offset, unsigned rgb) {
    uint8_t packet[64] = {6, 20, 3, offset & 255, offset >> 8, 0, 0, 0,
                          rgb >> 16, rgb >> 8, rgb};
    return exchange(device, packet) && response[2] == 1 &&
           response[3] == packet[3] && response[4] == packet[4] &&
           memcmp(response + 8, packet + 8, 3) == 0;
}

int main(int argc, char **argv) {
    int demo = argc == 2 && strcmp(argv[1], "demo") == 0;
    int diagnose = argc == 2 && strcmp(argv[1], "diagnose") == 0;
    int set = argc >= 4 && argc % 2 == 0 && strcmp(argv[1], "set") == 0;
    int effect = argc == 5 && strcmp(argv[1], "effect") == 0;
    unsigned effect_args[3];
    if (effect) {
        const unsigned limits[] = {15, 4, 4};
        for (int i = 0; i < 3; i++) {
            const char *value = argv[i + 2];
            if (!*value || strlen(value) > 2 || strspn(value, "0123456789") != strlen(value) ||
                (effect_args[i] = (unsigned)strtoul(value, NULL, 10)) > limits[i]) {
                fputs("Invalid effect, brightness, or speed.\n", stderr);
                return 2;
            }
        }
    }
    if (argc == 2 && strcmp(argv[1], "keys") == 0) {
        for (size_t i = 0; i < sizeof(key_map) / sizeof(key_map[0]); i++)
            puts(key_map[i].name);
        return 0;
    }
    if (argc > 1 && !demo && !diagnose && !set && !effect) {
        fputs("Usage: rgb-probe keys | diagnose | demo | set KEY RRGGBB [KEY RRGGBB ...] | effect MODE BRIGHTNESS SPEED\n", stderr);
        return 2;
    }
    unsigned offsets[argc], colors[argc];
    if (set) {
        for (int arg = 2; arg < argc; arg += 2) {
            size_t i = 0;
            while (i < sizeof(key_map) / sizeof(key_map[0]) &&
                   strcasecmp(key_map[i].name, argv[arg]) != 0) i++;
            const char *hex = argv[arg + 1];
            if (i == sizeof(key_map) / sizeof(key_map[0]) || strlen(hex) != 6 ||
                strspn(hex, "0123456789abcdefABCDEF") != 6) {
                fprintf(stderr, "Invalid key or RRGGBB color: %s %s\n", argv[arg], hex);
                return 2;
            }
            offsets[arg] = 3 * key_map[i].index;
            colors[arg] = (unsigned)strtoul(hex, NULL, 16);
        }
    }
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
    const void *keys[] = {CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey),
                          CFSTR(kIOHIDPrimaryUsagePageKey), CFSTR(kIOHIDPrimaryUsageKey)};
    int ids[] = {0x36ae, 0xfe12, 0xff00, 2};
    CFNumberRef numbers[4];
    for (size_t i = 0; i < 4; i++) numbers[i] = CFNumberCreate(NULL, kCFNumberIntType, &ids[i]);
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, (const void **)numbers, 4,
                                                 &kCFTypeDictionaryKeyCallBacks,
                                                 &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (!devices || CFSetGetCount(devices) != 1) {
        fputs("Expected one FE12 vendor interface.\n", stderr);
        return 1;
    }
    IOHIDDeviceRef device = NULL;
    CFSetGetValues(devices, (const void **)&device);
    IOReturn status = IOHIDDeviceOpen(device, 0);
    if (status != kIOReturnSuccess) {
        fprintf(stderr, "HID open failed: 0x%x\n", status);
        return 1;
    }
    IOHIDDeviceRegisterInputReportCallback(device, input, sizeof(input), on_report, NULL);
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    if (set) {
        if (!exchange(device, (uint8_t[64]){6, 5}) ||
            !exchange(device, (uint8_t[64]){6, 10}) || !enable_custom_mode(device)) return 1;
        for (int arg = 2; arg < argc; arg += 2) {
            if (!write_color(device, offsets[arg], colors[arg])) {
                fprintf(stderr, "Keyboard did not confirm color for %s\n", argv[arg]);
                return 1;
            }
            printf("%s #%06X acknowledged\n", argv[arg], colors[arg]);
        }
        return 0;
    }
    if (effect) {
        return apply_effect(device, effect_args[0], effect_args[1], effect_args[2]) ? 0 : 1;
    }
    if (diagnose) {
        int config = exchange(device, (uint8_t[64]){6, 5});
        int lighting = exchange(device, (uint8_t[64]){6, 10});
        int colors = exchange(device, (uint8_t[64]){6, 19, 58});
        return config && lighting && colors ? 0 : 1;
    }
    if (!exchange(device, (uint8_t[64]){6, 5}) ||
        !exchange(device, (uint8_t[64]){6, 10}) ||
        !exchange(device, (uint8_t[64]){6, 19, 58})) return 1;
    if (!demo) return 0;
    if (!exchange(device, (uint8_t[64]){6, 22, 0, 0, 0, 1, 0, 22})) return 1;
    uint8_t mode[64] = {6, 11, 11};
    memcpy(mode + 5, response + 5, 11);
    mode[7] = 22;
    if (!exchange(device, mode) ||
        !exchange(device, (uint8_t[64]){6, 20, 3, 0, 0, 0, 0, 0, 96, 0, 0}) ||
        !exchange(device, (uint8_t[64]){6, 20, 3, 3, 0, 0, 0, 0, 0, 0, 96}) ||
        !exchange(device, (uint8_t[64]){6, 19, 58})) return 1;
    const uint8_t expected[] = {96, 0, 0, 0, 0, 96};
    int rgb_matches = memcmp(response + 8, expected, sizeof(expected)) == 0;
    if (!exchange(device, (uint8_t[64]){6, 10})) return 1;
    if (!rgb_matches || response[7] != 22) {
        fprintf(stderr, "Readback mismatch: RGB match=%d, mode=%u\n", rgb_matches, response[7]);
        return 1;
    }
    puts("Readback verified: custom mode 22, Esc red, 1 blue.");
    return 0;
}
