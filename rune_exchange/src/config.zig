const std = @import("std");
const win = std.os.windows;

extern "kernel32" fn GetPrivateProfileIntA(
    lpAppName: [*:0]const u8,
    lpKeyName: [*:0]const u8,
    nDefault: i32,
    lpFileName: [*:0]const u8,
) callconv(.winapi) u32;

extern "kernel32" fn GetFileAttributesA(lpFileName: [*:0]const u8) callconv(.winapi) u32;

const FILETIME = extern struct {
    dwLowDateTime: u32,
    dwHighDateTime: u32,
};

const WIN32_FILE_ATTRIBUTE_DATA = extern struct {
    dwFileAttributes: u32,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    nFileSizeHigh: u32,
    nFileSizeLow: u32,
};

extern "kernel32" fn GetFileAttributesExA(
    lpFileName: [*:0]const u8,
    fInfoLevelId: u32,
    lpFileInformation: *WIN32_FILE_ATTRIBUTE_DATA,
) callconv(.winapi) win.BOOL;

// Module-level cached state for hot-reload detection
var g_ini_path: [*:0]const u8 = ".\\rune_exchange.ini";
var g_ini_path_resolved: bool = false;
var g_last_write_low: u32 = 0;
var g_last_write_high: u32 = 0;

fn resolveIniPath() [*:0]const u8 {
    if (g_ini_path_resolved) return g_ini_path;

    const paths = [_][*:0]const u8{
        "Z:\\mods\\rune_exchange.ini",
        "/mods/rune_exchange.ini",
        ".\\rune_exchange.ini",
        "rune_exchange.ini",
    };

    for (paths) |p| {
        const attr = GetFileAttributesA(p);
        if (attr != 0xFFFFFFFF) {
            g_ini_path = p;
            break;
        }
    }

    g_ini_path_resolved = true;
    return g_ini_path;
}

/// Check if the INI file has been modified since last load.
/// Returns a new Config if changed, null if unchanged.
pub fn reloadIfChanged() ?Config {
    const path = resolveIniPath();
    var data: WIN32_FILE_ATTRIBUTE_DATA = undefined;
    if (GetFileAttributesExA(path, 0, &data) == .FALSE) return null;

    if (data.ftLastWriteTime.dwLowDateTime == g_last_write_low and
        data.ftLastWriteTime.dwHighDateTime == g_last_write_high)
    {
        return null; // File not modified
    }

    g_last_write_low = data.ftLastWriteTime.dwLowDateTime;
    g_last_write_high = data.ftLastWriteTime.dwHighDateTime;
    return Config.loadFromPath(path);
}

pub const Config = struct {
    enabled: bool = true,
    test_mode: bool = false,
    only_akara: bool = false,
    min_rune: u32 = 18,
    max_rune: u32 = 30,
    weights: [33]u32 = [_]u32{
        // 1# ~ 17# (Low to Mid runes)
        5000, // 1 El
        4500, // 2 Eld
        4000, // 3 Tir
        3500, // 4 Nef
        3000, // 5 Eth
        2500, // 6 Ith
        2200, // 7 Tal
        2000, // 8 Ral
        1800, // 9 Ort
        1600, // 10 Thul
        1500, // 11 Amn
        1400, // 12 Sol
        1300, // 13 Shael
        1200, // 14 Dol
        1100, // 15 Hel
        1050, // 16 Io
        1000, // 17 Lum
        // 18# ~ 33# (High runes)
        1000, // 18 Ko
        800,  // 19 Fal
        600,  // 20 Lem
        500,  // 21 Pul
        400,  // 22 Um
        300,  // 23 Mal
        250,  // 24 Ist
        200,  // 25 Gul
        150,  // 26 Vex
        100,  // 27 Ohm
        70,   // 28 Lo
        50,   // 29 Sur
        35,   // 30 Ber
        20,   // 31 Jah
        10,   // 32 Cham
        5,    // 33 Zod
    },
    total_weight: u32 = 0,

    pub fn load() Config {
        const path = resolveIniPath();
        // Update cached write time on initial load
        var data: WIN32_FILE_ATTRIBUTE_DATA = undefined;
        if (GetFileAttributesExA(path, 0, &data) != .FALSE) {
            g_last_write_low = data.ftLastWriteTime.dwLowDateTime;
            g_last_write_high = data.ftLastWriteTime.dwHighDateTime;
        }
        return loadFromPath(path);
    }

    fn loadFromPath(ini_path: [*:0]const u8) Config {
        var cfg = Config{};

        cfg.enabled = GetPrivateProfileIntA("Settings", "Enable", 1, ini_path) != 0;
        cfg.test_mode = GetPrivateProfileIntA("Settings", "TestMode", 0, ini_path) != 0;
        cfg.only_akara = GetPrivateProfileIntA("Settings", "OnlyAkara", 0, ini_path) != 0;
        cfg.min_rune = GetPrivateProfileIntA("Settings", "MinRune", 18, ini_path);
        cfg.max_rune = GetPrivateProfileIntA("Settings", "MaxRune", 30, ini_path);

        // Sanitize bounds
        if (cfg.min_rune < 1) cfg.min_rune = 1;
        if (cfg.max_rune > 33) cfg.max_rune = 33;
        if (cfg.min_rune > cfg.max_rune) cfg.min_rune = cfg.max_rune;

        var sum: u32 = 0;
        var r: u32 = 1;
        while (r <= 33) : (r += 1) {
            var key_buf: [16:0]u8 = undefined;
            const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{r}) catch continue;
            const idx = r - 1;
            const default_w: i32 = @intCast(cfg.weights[idx]);
            const w = GetPrivateProfileIntA("RuneWeights", key.ptr, default_w, ini_path);
            cfg.weights[idx] = w;
            if (r >= cfg.min_rune and r <= cfg.max_rune) {
                sum += w;
            }
        }
        cfg.total_weight = if (sum > 0) sum else 1;
        return cfg;
    }

    pub fn pickRune(self: *const Config, seed: u32) struct { rune_id: u32, code: u32 } {
        if (self.total_weight == 0) return .{ .rune_id = self.min_rune, .code = 0x20383172 };

        const target = seed % self.total_weight;
        var current: u32 = 0;
        var picked: u32 = self.min_rune;

        var r = self.min_rune;
        while (r <= self.max_rune) : (r += 1) {
            const idx = r - 1;
            if (idx < self.weights.len) {
                current += self.weights[idx];
                if (target < current) {
                    picked = r;
                    break;
                }
            }
        }

        // Convert rune number (e.g. 24) to packed 4-byte code ('r24 ')
        // 'r' = 0x72, '2' = 0x32, '4' = 0x34, ' ' = 0x20
        const d1: u8 = @intCast((picked / 10) + '0');
        const d2: u8 = @intCast((picked % 10) + '0');
        const code: u32 = @as(u32, 0x72) |
            (@as(u32, d1) << 8) |
            (@as(u32, d2) << 16) |
            (@as(u32, 0x20) << 24);

        return .{ .rune_id = picked, .code = code };
    }
};
