const std = @import("std");
const win = std.os.windows;
const d2 = @import("d2engine.zig");
const cfg_mod = @import("config.zig");

pub var g_config: cfg_mod.Config = .{};
var prng_state: u32 = 0x9e3779b9; // Golden ratio hash, used as PRNG state

// Thread safety: CRITICAL_SECTION protects g_config and prng_state
// CRITICAL_SECTION is 24 bytes on 32-bit Windows (6 x DWORD)
extern "kernel32" fn InitializeCriticalSection(lpCriticalSection: *anyopaque) callconv(.winapi) void;
extern "kernel32" fn EnterCriticalSection(lpCriticalSection: *anyopaque) callconv(.winapi) void;
extern "kernel32" fn LeaveCriticalSection(lpCriticalSection: *anyopaque) callconv(.winapi) void;
var g_cs_buf: [6]u32 = [_]u32{0} ** 6;

pub fn initLock() void {
    InitializeCriticalSection(@ptrCast(&g_cs_buf));
}

fn lock() void {
    EnterCriticalSection(@ptrCast(&g_cs_buf));
}

fn unlock() void {
    LeaveCriticalSection(@ptrCast(&g_cs_buf));
}

extern "kernel32" fn OutputDebugStringA(lpOutputString: [*:0]const u8) callconv(.winapi) void;
extern "kernel32" fn GetTickCount() callconv(.winapi) u32;

extern "kernel32" fn CreateFileA(
    lpFileName: [*:0]const u8,
    dwDesiredAccess: u32,
    dwShareMode: u32,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: u32,
    dwFlagsAndAttributes: u32,
    hTemplateFile: ?*anyopaque,
) callconv(.winapi) ?*anyopaque;

extern "kernel32" fn SetFilePointer(
    hFile: *anyopaque,
    lDistanceToMove: i32,
    lpDistanceToMoveHigh: ?*i32,
    dwMoveMethod: u32,
) callconv(.winapi) u32;

extern "kernel32" fn WriteFile(
    hFile: *anyopaque,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: u32,
    lpNumberOfBytesWritten: ?*u32,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) win.BOOL;

extern "kernel32" fn CloseHandle(hObject: *anyopaque) callconv(.winapi) win.BOOL;

// Cached log file handle (lazily initialized, kept open for lifetime of DLL)
var g_log_handle: ?*anyopaque = null;
var g_log_init: bool = false;

fn getLogHandle() ?*anyopaque {
    if (g_log_init) return g_log_handle;
    g_log_init = true;

    const targets = [_][*:0]const u8{
        "Z:\\mods\\rune_exchange.log",
        "rune_exchange.log",
    };
    for (targets) |path| {
        // OPEN_ALWAYS (4), FILE_SHARE_READ|FILE_SHARE_WRITE (3)
        const h = CreateFileA(path, 0x40000000, 3, null, 4, 0x80, null);
        if (h != null and @intFromPtr(h.?) != 0xFFFFFFFF) {
            g_log_handle = h;
            return h;
        }
    }
    return null;
}

pub fn logMsg(comptime fmt: []const u8, args: anytype) void {
    var buf: [512:0]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "[rune_exchange] " ++ fmt, args) catch {
        // Buffer overflow: output a truncation warning
        OutputDebugStringA("[rune_exchange] WARNING: log message truncated (>512 bytes)\x00");
        return;
    };
    OutputDebugStringA(msg.ptr);

    if (getLogHandle()) |hFile| {
        _ = SetFilePointer(hFile, 0, null, 2); // FILE_END
        var written: u32 = 0;
        _ = WriteFile(hFile, msg.ptr, @intCast(msg.len), &written, null);
    }
}

/// Lightweight debug-only log (OutputDebugStringA only, no file I/O).
/// Use for high-frequency non-critical messages to avoid log file bloat.
pub fn debugMsg(comptime fmt: []const u8, args: anytype) void {
    var buf: [512:0]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "[rune_exchange] " ++ fmt, args) catch return;
    OutputDebugStringA(msg.ptr);
}

// 170 elite base codes (from weapons.txt, armor.txt, misc.txt) as sorted little-endian u32 for binary search.
// Each u32 packs a 4-byte item code, e.g. "7ar " -> 0x20726137 (little-endian).
const elite_codes_sorted = [_]u32{
    0x20316D63, 0x20326D63, 0x20336963, 0x20336D63, 0x20376237, 0x20376837, 0x20376C36, 0x20376D37,
    0x20376F37, 0x20377037, 0x20377336, 0x20377337, 0x20386237, 0x20387337, 0x20396875, 0x20613237,
    0x20616237, 0x20616575, 0x20616737, 0x20616837, 0x20616A37, 0x20616C37, 0x20616C75, 0x20616D37,
    0x20617037, 0x20617437, 0x20617737, 0x20626162, 0x20626170, 0x2062626F, 0x20626336, 0x2062656E,
    0x20626637, 0x20626836, 0x20626875, 0x20626C36, 0x20626C75, 0x20626D61, 0x20626D75, 0x20627264,
    0x20627336, 0x20627337, 0x20627475, 0x20627675, 0x20627737, 0x20636162, 0x20636170, 0x2063626F,
    0x20636637, 0x20636875, 0x20636C75, 0x20636D61, 0x20636D75, 0x20637264, 0x20637337, 0x20637475,
    0x20637575, 0x20637675, 0x20637737, 0x20646162, 0x20646170, 0x2064626F, 0x2064656E, 0x20646737,
    0x20646C75, 0x20646D61, 0x20647264, 0x20647737, 0x20656162, 0x20656170, 0x2065626F, 0x2065656E,
    0x20656D61, 0x20657264, 0x20666162, 0x20666170, 0x2066626F, 0x2066656E, 0x20666D61, 0x20667264,
    0x20667837, 0x20676437, 0x2067656E, 0x20676875, 0x20676C75, 0x20676D75, 0x20676E75, 0x20677275,
    0x20677475, 0x20677675, 0x20683237, 0x20687375, 0x20687475, 0x20687737, 0x20696437, 0x20696737,
    0x20697037, 0x20697575, 0x206B6237, 0x206B7075, 0x206B7375, 0x206B7437, 0x206C6237, 0x206C6337,
    0x206C6375, 0x206C6637, 0x206C6737, 0x206C6875, 0x206C6D75, 0x206C7075, 0x206C7575, 0x206D6337,
    0x206D6737, 0x206D6875, 0x206D6C75, 0x206D7337, 0x206E6875, 0x206E6972, 0x206E7275, 0x206E7737,
    0x206F7637, 0x20706175, 0x20706B75, 0x20706D37, 0x20707337, 0x20707475, 0x20726137, 0x20726175,
    0x20726237, 0x20726337, 0x20726B37, 0x20727137, 0x20727337, 0x20727437, 0x20736236, 0x20736237,
    0x20736336, 0x20736337, 0x20736737, 0x20736C36, 0x20736C37, 0x20737137, 0x20737275, 0x20737336,
    0x20737337, 0x20737437, 0x20737475, 0x20737736, 0x20737737, 0x20746237, 0x20746975, 0x20746C75,
    0x20746D37, 0x20747337, 0x20756D61, 0x20757475, 0x20776237, 0x2077656A, 0x20776737, 0x20776C36,
    0x20776C37, 0x20776F75, 0x20777336, 0x20777437, 0x20777937, 0x20786137, 0x20786836, 0x20786C36,
    0x20786D36, 0x20787236,
};

/// Check if an item code belongs to elite/jewelry set using binary search (O(log n), ~8 comparisons).
pub fn isElite(code: [4]u8) bool {
    const key = std.mem.readInt(u32, &code, .little);
    var lo: usize = 0;
    var hi: usize = elite_codes_sorted.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (elite_codes_sorted[mid] < key) {
            lo = mid + 1;
        } else if (elite_codes_sorted[mid] > key) {
            hi = mid;
        } else {
            return true;
        }
    }
    return false;
}

/// Call the original Packet 0x33 sell handler (D2GAME_SCMD_0x33 at 0x0054BB20).
/// Calling convention: __thiscall (ECX=pGame, EDX=pPlayer, stack: pPacket, nPacketLen)
/// Return value: 0 = success (item sold, gold credited), non-zero = rejected (e.g. invalid item).
pub fn callOrigHandler(pGame: usize, pPlayer: usize, pPacket: usize, nPacketLen: u32) i32 {
    const fn_addr: u32 = d2.ADDR_ORIG_SCMD_0x33;
    var buf = [3]u32{
        nPacketLen,
        @truncate(pPacket),
        fn_addr,
    };
    const res = asm volatile (
        \\pushl (%[buf])
        \\pushl 4(%[buf])
        \\movl %[g], %%ecx
        \\movl %[p], %%edx
        \\call *8(%[buf])
        : [ret] "={eax}" (-> i32),
        : [buf] "r" (&buf),
          [g] "r" (pGame),
          [p] "r" (pPlayer),
        : .{ .ecx = true, .edx = true, .memory = true }
    );
    return res;
}

pub fn onSellPacket(pGame: usize, pPlayer: usize, pPacket: usize, nPacketLen: u32) callconv(.c) i32 {
    lock();
    defer unlock();

    if (cfg_mod.reloadIfChanged()) |new_cfg| {
        g_config = new_cfg;
        logMsg("Config hot-reloaded: Enable={d}, TestMode={d}, OnlyAkara={d}, MinRune={d}, MaxRune={d}\n", .{
            @as(u32, if (g_config.enabled) 1 else 0),
            @as(u32, if (g_config.test_mode) 1 else 0),
            @as(u32, if (g_config.only_akara) 1 else 0),
            g_config.min_rune,
            g_config.max_rune,
        });
    }
    if (!g_config.enabled) return 0;
    if (nPacketLen != 0x11) return 0;

    const pkt_ptr: [*]const u8 = @ptrFromInt(pPacket);
    if (pkt_ptr[0] != 0x33) return 0;

    const npc_id = std.mem.readInt(u32, pkt_ptr[1..5], .little);
    const item_id = std.mem.readInt(u32, pkt_ptr[5..9], .little);

    const pNpc = d2.getServerUnit(@ptrFromInt(pGame), 1, npc_id) orelse {
        debugMsg("Sell Packet 0x33: NPC unit {d} not found in game\n", .{npc_id});
        return 0;
    };
    const pItem = d2.getServerUnit(@ptrFromInt(pGame), 4, item_id) orelse {
        debugMsg("Sell Packet 0x33: Item unit {d} not found in game\n", .{item_id});
        return 0;
    };

    var item_code: [4]u8 = [_]u8{ ' ', ' ', ' ', ' ' };
    const GetItemTxtFn = *const fn (u32) callconv(.winapi) ?*anyopaque;
    const getTxt: GetItemTxtFn = @ptrFromInt(d2.ADDR_GET_ITEM_TEXT);
    if (getTxt(pItem.dwTxtFileNo)) |raw_txt| {
        const txt_bytes: [*]const u8 = @ptrCast(raw_txt);
        @memcpy(&item_code, txt_bytes[0x80..0x84]);
    }

    var quality: u32 = 0;
    if (pItem.pUnitData) |pData| {
        const pItemData: *const d2.ItemData = @ptrCast(@alignCast(pData));
        quality = pItemData.dwQuality;
    }

    // Check NPC filter
    if (g_config.only_akara and pNpc.dwTxtFileNo != 148) {
        return 0; // Not Akara, proceed with normal sell
    }

    // Check Item filter
    var is_eligible = false;
    if (g_config.test_mode) {
        // Test phase: any item triggers exchange!
        is_eligible = true;
    } else {
        // Production phase: must be unique (quality == 7) and elite/jewelry
        if (quality == 7 and isElite(item_code)) {
            is_eligible = true;
        }
    }

    if (!is_eligible) {
        return 0; // Not eligible, let original handler run
    }

    // Follow vanilla D2's Runeword / Ethereal non-buyback mechanism:
    // In D2GAME_NpcSell_579510, having ITEMFLAG_ETHEREAL (0x00400000) or ITEMFLAG_CANNOT_STORE (0x100)
    // causes the engine to jump directly to 0x005798da, destroying the item and crediting gold.
    if (pItem.pUnitData) |pData| {
        const pItemData: *d2.ItemData = @ptrCast(@alignCast(pData));
        pItemData.dwItemFlags |= 0x00400100;
    }

    // Step 1: Let the original sell handler execute so gold is credited and item is destroyed.
    // Return convention: 0 = success (item sold & gold credited), non-zero = error/rejection.
    const orig_res = callOrigHandler(pGame, pPlayer, pPacket, nPacketLen);
    if (orig_res != 0) {
        logMsg("Original sell handler rejected with code {d}\n", .{orig_res});
        return 1; // Mark handled so the naked hook does not re-dispatch to 0x0054BB20
    }

    // Step 2: High-quality PRNG mixing
    // 1) Hardware/OS tick count (real millisecond timing entropy from player interactions)
    // 2) Game state pointers and unit IDs
    // 3) Golden ratio additive constant + MurmurHash3 / SplitMix32 avalanche finalizer
    prng_state ^= GetTickCount();
    prng_state ^= @as(u32, @truncate(pPlayer)) +% @as(u32, @truncate(npc_id)) +% item_id;
    prng_state +%= 0x9e3779b9;

    var mix: u32 = prng_state;
    mix ^= mix >> 16;
    mix *%= 0x85ebca6b;
    mix ^= mix >> 13;
    mix *%= 0xc2b2ae35;
    mix ^= mix >> 16;

    const picked = g_config.pickRune(mix);

    // Step 3: Generate the new rune into the NPC's shop (ilvl 90 satisfies all rune levels)
    const pRune = d2.generateNpcItem(pNpc, @ptrFromInt(pGame), picked.code, 90);

    if (pRune) |_| {
        logMsg("Exchanged '{s}' (ID {d}) -> Rune #{d} at NPC {d} (seed: 0x{X:08})\n", .{
            item_code,
            item_id,
            picked.rune_id,
            npc_id,
            mix,
        });

        // Step 4: Send in-game reminder message to player (Color: 0x02 = Green, pure English)
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "[Rune Exchange] Rune #{d} spawned in Misc tab! Switch to Misc tab to buy.", .{
            picked.rune_id,
        }) catch "[Rune Exchange] Rune spawned in Misc tab! Switch to Misc tab to buy.";
        d2.sendServerMessage(pPlayer, msg, 0x02);
    } else {
        logMsg("ERROR: Failed to generate Rune #{d} — NPC Misc page is full!\n", .{picked.rune_id});
        d2.sendServerMessage(pPlayer, "[Rune Exchange] Shop is full! Please buy some items to free space.", 0x01);
    }

    return 1; // Return handled!
}


