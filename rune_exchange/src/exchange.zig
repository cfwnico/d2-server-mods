const std = @import("std");
const win = std.os.windows;
const d2 = @import("d2engine.zig");
const cfg_mod = @import("config.zig");

pub var g_config: cfg_mod.Config = .{};
var seed_counter: u32 = 0x9e3779b9;

extern "kernel32" fn OutputDebugStringA(lpOutputString: [*:0]const u8) callconv(.winapi) void;

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

pub fn logMsg(comptime fmt: []const u8, args: anytype) void {
    var buf: [256:0]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "[rune_exchange] " ++ fmt, args) catch return;
    OutputDebugStringA(msg.ptr);

    const targets = [_][*:0]const u8{
        "Z:\\mods\\rune_exchange.log",
        "rune_exchange.log",
    };
    for (targets) |path| {
        const hFile = CreateFileA(path, 0x40000000, 1, null, 4, 0x80, null);
        if (hFile != null and @intFromPtr(hFile.?) != 0xFFFFFFFF) {
            defer _ = CloseHandle(hFile.?);
            _ = SetFilePointer(hFile.?, 0, null, 2);
            var written: u32 = 0;
            _ = WriteFile(hFile.?, msg.ptr, @intCast(msg.len), &written, null);
        }
    }
}

// 170 elite base codes extracted from authoritative MPQ TXT data (weapons.txt, armor.txt, jewelry)
pub const elite_codes = [_][4]u8{
    "6bs ".*, "6cb ".*, "6cs ".*, "6hb ".*, "6hx ".*, "6l7 ".*, "6lb ".*, "6ls ".*, "6lw ".*, "6lx ".*,
    "6mx ".*, "6rx ".*, "6s7 ".*, "6sb ".*, "6ss ".*, "6sw ".*, "6ws ".*, "72a ".*, "72h ".*, "7ar ".*,
    "7ax ".*, "7b7 ".*, "7b8 ".*, "7ba ".*, "7bk ".*, "7bl ".*, "7br ".*, "7bs ".*, "7bt ".*, "7bw ".*,
    "7cl ".*, "7cm ".*, "7cr ".*, "7cs ".*, "7dg ".*, "7di ".*, "7fb ".*, "7fc ".*, "7fl ".*, "7fo ".*,
    "7ga ".*, "7gd ".*, "7gi ".*, "7gl ".*, "7gm ".*, "7gs ".*, "7gw ".*, "7h7 ".*, "7ha ".*, "7ja ".*,
    "7kr ".*, "7la ".*, "7ls ".*, "7lw ".*, "7m7 ".*, "7ma ".*, "7mp ".*, "7o7 ".*, "7pa ".*, "7p7 ".*,
    "7pi ".*, "7qs ".*, "7s7 ".*, "7s8 ".*, "7sb ".*, "7sc ".*, "7sm ".*, "7sp ".*, "7sr ".*, "7ss ".*,
    "7st ".*, "7ta ".*, "7tr ".*, "7ts ".*, "7vo ".*, "7wa ".*, "7wb ".*, "7wc ".*, "7wd ".*, "7wh ".*,
    "7ws ".*, "7xf ".*, "7yc ".*, "amu ".*, "ci3 ".*, "ci4 ".*, "cm1 ".*, "cm2 ".*, "cm3 ".*, "dr6 ".*,
    "dr7 ".*, "dr8 ".*, "dr9 ".*, "dra ".*, "drb ".*, "drc ".*, "drd ".*, "dre ".*, "drf ".*, "ea1 ".*,
    "ea2 ".*, "ea3 ".*, "ea4 ".*, "ea5 ".*, "jew ".*, "nea ".*, "neb ".*, "neg ".*, "nef ".*, "ne8 ".*,
    "ne9 ".*, "pa6 ".*, "pa7 ".*, "pa8 ".*, "pa9 ".*, "paa ".*, "pab ".*, "pac ".*, "pad ".*, "pae ".*,
    "paf ".*, "rin ".*, "ucl ".*, "uh9 ".*, "uhb ".*, "uhc ".*, "uhg ".*, "uhl ".*, "uhm ".*, "uhn ".*,
    "uap ".*, "uul ".*, "uow ".*, "urg ".*, "ulc ".*, "uuc ".*, "umb ".*, "upk ".*, "uld ".*, "usk ".*,
    "uto ".*, "utb ".*, "utc ".*, "uth ".*, "utg ".*, "uts ".*, "utu ".*, "ung ".*, "urg ".*, "uts ".*,
    "uvc ".*, "uvg ".*, "uwc ".*, "uwh ".*, "uwi ".*, "uwl ".*, "uwm ".*, "uwn ".*, "uwp ".*, "uww ".*,
    "xar ".*, "xcl ".*, "xha ".*, "xh9 ".*, "xsk ".*, "xul ".*, "xsh ".*, "xpk ".*, "xtb ".*, "xmb ".*,
};

pub fn isElite(code: [4]u8) bool {
    for (elite_codes) |c| {
        if (std.mem.eql(u8, &code, &c)) return true;
    }
    return false;
}

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
    g_config = cfg_mod.Config.load();
    if (!g_config.enabled) return 0;
    if (nPacketLen != 0x11) return 0;

    const pkt_ptr: [*]const u8 = @ptrFromInt(pPacket);
    if (pkt_ptr[0] != 0x33) return 0;

    const npc_id = std.mem.readInt(u32, pkt_ptr[1..5], .little);
    const item_id = std.mem.readInt(u32, pkt_ptr[5..9], .little);

    const pNpc = d2.getServerUnit(@ptrFromInt(pGame), 1, npc_id) orelse return 0;
    const pItem = d2.getServerUnit(@ptrFromInt(pGame), 4, item_id) orelse return 0;

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
        if (pItem.pUnitData) |pData| {
            const pItemData: *const d2.ItemData = @ptrCast(@alignCast(pData));
            if (pItemData.dwQuality == 7) {
                // Get item code from class ID
                const GetItemTxtFn = *const fn (u32) callconv(.winapi) ?*anyopaque;
                const getTxt: GetItemTxtFn = @ptrFromInt(d2.ADDR_GET_ITEM_TEXT);
                if (getTxt(pItem.dwTxtFileNo)) |raw_txt| {
                    const txt_bytes: [*]const u8 = @ptrCast(raw_txt);
                    var code: [4]u8 = undefined;
                    @memcpy(&code, txt_bytes[0x80..0x84]);
                    if (isElite(code)) {
                        is_eligible = true;
                    }
                }
            }
        }
    }

    if (!is_eligible) {
        return 0; // Not eligible, let original handler run
    }

    logMsg("Triggered rune exchange! (NPC={d}, Item={d}, ClassId={d})\n", .{
        npc_id,
        item_id,
        pItem.dwTxtFileNo,
    });

    // Follow vanilla D2's Runeword / Ethereal non-buyback mechanism:
    // In D2GAME_NpcSell_579510 (0x00579660, 0x005796b2, 0x005796d4), having ITEMFLAG_ETHEREAL (0x00400000)
    // or ITEMFLAG_CANNOT_STORE (0x100) causes the engine to set [ebp-4] = 0.
    // At 0x00579720 (cmp [ebp-4], 0; je 0x5798da), the engine jumps directly to 0x005798da,
    // which removes and destroys the item from player inventory, credits gold, and sends Packet 0x2A.
    // It NEVER duplicates or adds the item to the NPC shop / buyback page!
    if (pItem.pUnitData) |pData| {
        const pItemData: *d2.ItemData = @ptrCast(@alignCast(pData));
        pItemData.dwItemFlags |= 0x00400100;
    }

    // Step 1: Let the original sell handler execute so gold is credited and item is destroyed
    const orig_res = callOrigHandler(pGame, pPlayer, pPacket, nPacketLen);
    if (orig_res != 0) { // In Diablo II, 0 indicates SUCCESS
        logMsg("Original sell handler rejected with code {d}\n", .{orig_res});
        return 1; // Mark handled so we do not re-run 0x0054BB20
    }

    logMsg("Original sell succeeded (code 0). Item {d} was destroyed by engine.\n", .{item_id});

    // Step 2: Pick a rune based on weights
    seed_counter +%= 0x19660d +% @as(u32, @truncate(pPlayer)) +% @as(u32, @truncate(npc_id)) +% item_id;
    const picked = g_config.pickRune(seed_counter);
    logMsg("Generating Rune {d} (code: 0x{x:08}) for NPC {d}!\n", .{
        picked.rune_id,
        picked.code,
        npc_id,
    });

    // Step 3: Generate the new rune into the NPC's shop (ilvl 90 satisfies all rune levels)
    const pRune = d2.generateNpcItem(pNpc, @ptrFromInt(pGame), picked.code, 90);

    if (pRune) |r| {
        logMsg("Successfully generated Rune unit at 0x{X:08} (id={d}) in NPC shop!\n", .{
            @intFromPtr(r),
            r.dwUnitId,
        });

        // Step 4: Actively push Packet 0x9D (ITEMACTION_TO_STORE) to the client so it appears in the misc page immediately
        d2.sendItemToStore(pPlayer, pNpc, r);
        logMsg("Sent Packet 0x9D (ITEMACTION_TO_STORE) for Rune unit {d} to client shop UI!\n", .{r.dwUnitId});

        // Step 5: Send in-game reminder message to player
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "[Rune Exchange] Rune #{d} spawned in shop! Remember to buy it back.", .{
            picked.rune_id,
        }) catch "[Rune Exchange] Rune spawned in shop! Remember to buy it back.";
        d2.sendServerMessage(pPlayer, msg);
    } else {
        logMsg("ERROR: Failed to generate Rune #{d} — NPC misc page is completely full!\n", .{picked.rune_id});
        d2.sendServerMessage(pPlayer, "[Rune Exchange] Shop is full! Please buy some items to free space.");
    }

    logMsg("Rune exchange completed successfully!\n", .{});
    return 1; // Return handled!
}


