const std = @import("std");
const win = std.os.windows;
const d2 = @import("d2engine.zig");

extern "kernel32" fn GetPrivateProfileIntA(
    lpAppName: [*:0]const u8,
    lpKeyName: [*:0]const u8,
    nDefault: i32,
    lpFileName: [*:0]const u8,
) callconv(.winapi) u32;

extern "kernel32" fn GetPrivateProfileStringA(
    lpAppName: [*:0]const u8,
    lpKeyName: [*:0]const u8,
    lpDefault: [*:0]const u8,
    lpReturnedString: [*]u8,
    nSize: u32,
    lpFileName: [*:0]const u8,
) callconv(.winapi) u32;

pub const Config = struct {
    enabled: bool = true,
    debug_log: bool = true,

    has_input2: bool = true,

    input1_str: [8]u8 = [_]u8{ 'r', '2', '6', 0, 0, 0, 0, 0 },
    input2_str: [8]u8 = [_]u8{ 'y', 'p', 's', 0, 0, 0, 0, 0 },

    input1_code: u32 = 0,
    input2_code: u32 = 0,

    input1_class_id: i32 = -1,
    input2_class_id: i32 = -1,

    pub fn parseCode(str: []const u8) u32 {
        var buf = [4]u8{ ' ', ' ', ' ', ' ' };
        var i: usize = 0;
        for (str) |c| {
            if (c == 0 or c == ' ' or c == '\t' or c == '\r' or c == '\n') break;
            if (i < 4) {
                buf[i] = c;
                i += 1;
            }
        }
        return @as(u32, buf[0]) |
            (@as(u32, buf[1]) << 8) |
            (@as(u32, buf[2]) << 16) |
            (@as(u32, buf[3]) << 24);
    }

    pub fn load() Config {
        var cfg = Config{};

        const ini_paths = [_][*:0]const u8{
            "Z:\\mods\\Unique_reroll.ini",
            "Unique_reroll.ini",
            ".\\Unique_reroll.ini",
            ".\\mods\\Unique_reroll.ini",
        };

        var found_path: ?[*:0]const u8 = null;
        for (ini_paths) |p| {
            const val = GetPrivateProfileIntA("Settings", "Enable", -1, p);
            if (val != 0xFFFFFFFF and val != 4294967295) {
                found_path = p;
                break;
            }
        }

        const ini = found_path orelse "Unique_reroll.ini";

        cfg.enabled = GetPrivateProfileIntA("Settings", "Enable", 1, ini) != 0;
        cfg.debug_log = GetPrivateProfileIntA("Settings", "DebugLog", 1, ini) != 0;

        var str_buf1: [32]u8 = undefined;
        const len1 = GetPrivateProfileStringA("Settings", "Input1", "r26", &str_buf1, 32, ini);
        const slice1 = std.mem.trim(u8, str_buf1[0..len1], " \t\r\n");
        @memset(&cfg.input1_str, 0);
        const copy_len1 = @min(slice1.len, 7);
        @memcpy(cfg.input1_str[0..copy_len1], slice1[0..copy_len1]);

        var str_buf2: [32]u8 = undefined;
        const len2 = GetPrivateProfileStringA("Settings", "Input2", "yps", &str_buf2, 32, ini);
        const slice2 = std.mem.trim(u8, str_buf2[0..len2], " \t\r\n");
        @memset(&cfg.input2_str, 0);
        const copy_len2 = @min(slice2.len, 7);
        @memcpy(cfg.input2_str[0..copy_len2], slice2[0..copy_len2]);

        cfg.input1_code = parseCode(slice1);

        if (slice2.len == 0 or std.mem.eql(u8, slice2, "none") or std.mem.eql(u8, slice2, "0")) {
            cfg.has_input2 = false;
            cfg.input2_code = 0;
        } else {
            cfg.has_input2 = true;
            cfg.input2_code = parseCode(slice2);
        }

        return cfg;
    }
};
