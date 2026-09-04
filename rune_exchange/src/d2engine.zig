const std = @import("std");
const win = std.os.windows;

pub const DWORD = u32;
pub const WORD = u16;
pub const BYTE = u8;
pub const BOOL = i32;

pub const UnitAny = extern struct {
    dwType: DWORD, // 0x00 (0=player, 1=monster/npc, 4=item)
    dwTxtFileNo: DWORD, // 0x04 (class ID)
    _08: DWORD, // 0x08
    dwUnitId: DWORD, // 0x0C (GUID)
    dwMode: DWORD, // 0x10
    pUnitData: ?*anyopaque, // 0x14 (if type==4 -> ItemData, if type==0 -> PlayerData)
    dwAct: DWORD, // 0x18
    pAct: ?*anyopaque, // 0x1C
    dwSeed: [2]DWORD, // 0x20
    _28: DWORD, // 0x28
    pPath: ?*anyopaque, // 0x2C
    _30: [5]DWORD, // 0x30
    pStats: ?*anyopaque, // 0x44
    _48: [6]DWORD, // 0x48
    pInventory: ?*Inventory, // 0x60
    _64: [6]DWORD, // 0x64
    pTimerArgs: ?*anyopaque, // 0x7C
};

pub const Inventory = extern struct {
    dwSignature: DWORD, // 0x00
    bGame1C: ?*anyopaque, // 0x04
    pOwner: ?*UnitAny, // 0x08
    pFirstItem: ?*UnitAny, // 0x0C
    pLastItem: ?*UnitAny, // 0x10
};

pub const ItemData = extern struct {
    dwQuality: DWORD, // 0x00 (7 = Unique)
    dwSeed: [2]DWORD, // 0x04
    nPlayerGUID: DWORD, // 0x0C
    nModSeed: DWORD, // 0x10
    eItemCmd: DWORD, // 0x14
    dwItemFlags: DWORD, // 0x18
    _1C: [2]DWORD, // 0x1C
    dwActionStamp: DWORD, // 0x24
    dwFileIndex: DWORD, // 0x28 (UniqueItems.txt row)
    dwItemLevel: DWORD, // 0x2C
    _30: [11]DWORD, // 0x30 .. 0x5B
    pOwnerInventory: ?*Inventory, // 0x5C
    pPrevItem: ?*UnitAny, // 0x60
    pNextItem: ?*UnitAny, // 0x64
};

pub const D2GameStrc = extern struct {
    _00: [0x1C]u8,
    pMemoryPool: ?*anyopaque, // 0x1C
};

extern "kernel32" fn VirtualProtect(
    lpAddress: ?*anyopaque,
    dwSize: usize,
    flNewProtect: u32,
    lpflOldProtect: *u32,
) callconv(.winapi) win.BOOL;

pub const PAGE_EXECUTE_READWRITE: u32 = 0x40;

/// Memory addresses in 1.14d Game.exe
pub const ADDR_PACKET_TABLE_0x33: usize = 0x006E0EB0;
pub const ADDR_ORIG_SCMD_0x33: usize = 0x0054BB20;
pub const ADDR_SEND_PACKET_HELPER: usize = 0x0053B280;
pub const ADDR_SUNIT_GET_SERVER_UNIT: usize = 0x00552F60;
pub const ADDR_ITEMS_REMOVE_AND_FREE: usize = 0x00557FD0;
pub const ADDR_GET_ITEM_CLASSID_BY_CODE: usize = 0x00633680;
pub const ADDR_GET_ITEM_TEXT: usize = 0x006335F0;
pub const ADDR_GENERATE_NPC_ITEM: usize = 0x00576330;

/// Hook installation helper: patches the pointer at `0x006E0EB0`
pub fn hookPacket0x33(new_handler: *const anyopaque) bool {
    var old_protect: u32 = 0;
    const target: *usize = @ptrFromInt(ADDR_PACKET_TABLE_0x33);

    if (VirtualProtect(target, @sizeOf(usize), PAGE_EXECUTE_READWRITE, &old_protect) == .FALSE) {
        return false;
    }

    target.* = @intFromPtr(new_handler);

    var dummy: u32 = 0;
    _ = VirtualProtect(target, @sizeOf(usize), old_protect, &dummy);
    return true;
}

/// Send in-game server announcement message (gold text in chat box) via Packet 0x26
/// Client length parser at 0x0052b98e and handler at 0x0045dfc0 / 0x0049f803:
/// [0]: 0x26 (Packet ID)
/// [1]: 0x04 (Chat type 4 = System Announcement directly into chat box)
/// [2]: 0x00 (Language)
/// [3]: 0x00
/// [4..7]: 0x00000000 (Unit ID)
/// [8]: Color (0x04 = Gold / Unique)
/// [9]: 0x00
/// [10]: 0x00 (Null-terminated empty sender name)
/// [11..]: Null-terminated message string
/// Total packet length = 10 (header) + 1 (sender null) + msg_len + 1 (msg null) = 12 + msg_len
pub fn sendServerMessage(pPlayer: usize, msg: []const u8) void {
    const pPlayerUnit: *const UnitAny = @ptrFromInt(pPlayer);
    const pUnitData = pPlayerUnit.pUnitData orelse return;
    const pClient: usize = @as(*align(1) const usize, @ptrFromInt(@intFromPtr(pUnitData) + 0x9C)).*;
    if (pClient == 0) return;

    var buf: [256]u8 = undefined;
    @memset(buf[0..256], 0);

    buf[0] = 0x26; // Packet 0x26
    buf[1] = 0x04; // Chat type 4: System Announcement (chat window)
    buf[2] = 0x00;
    buf[3] = 0x00;
    // bytes 4..7: unit_id = 0
    buf[8] = 0x04; // Color: 4 = Gold / Unique
    buf[9] = 0x00;
    buf[10] = 0x00; // Empty sender name ("\0")

    const max_len = @min(msg.len, 200);
    @memcpy(buf[11 .. 11 + max_len], msg[0..max_len]);
    buf[11 + max_len] = 0x00; // Null-terminator for message

    const total_len: u32 = @intCast(12 + max_len);

    var args = [3]u32{
        total_len,
        @intFromPtr(&buf),
        ADDR_SEND_PACKET_HELPER,
    };
    asm volatile (
        \\pushl (%[args])
        \\pushl 4(%[args])
        \\movl %[client], %%edi
        \\call *8(%[args])
        :
        : [args] "r" (&args),
          [client] "r" (pClient),
        : .{ .eax = true, .ecx = true, .edx = true, .edi = true, .memory = true }
    );
}

/// SUNIT_GetServerUnit: (pGame [ECX], eUnitType [EDX], dwUnitId [stack])
pub fn getServerUnit(pGame: ?*anyopaque, unit_type: u32, unit_id: u32) ?*UnitAny {
    var buf = [2]u32{ unit_id, ADDR_SUNIT_GET_SERVER_UNIT };
    const raw = asm volatile (
        \\pushl (%[buf])
        \\movl %[g], %%ecx
        \\movl %[t], %%edx
        \\call *4(%[buf])
        : [ret] "={eax}" (-> usize),
        : [buf] "r" (&buf),
          [g] "r" (@intFromPtr(pGame)),
          [t] "r" (unit_type),
        : .{ .ecx = true, .edx = true, .memory = true }
    );
    return if (raw == 0) null else @ptrFromInt(raw);
}

/// Remove and free an item unit: (pGame [ECX], pItem [EDX])
pub fn removeItemAndFree(pGame: ?*anyopaque, pItem: *UnitAny) void {
    const fn_addr: u32 = ADDR_ITEMS_REMOVE_AND_FREE;
    asm volatile (
        \\movl %[g], %%ecx
        \\movl %[i], %%edx
        \\call *%[func]
        :
        : [g] "r" (@intFromPtr(pGame)),
          [i] "r" (@intFromPtr(pItem)),
          [func] "r" (fn_addr),
        : .{ .eax = true, .ecx = true, .edx = true, .memory = true }
    );
}

/// Get item class ID by 4-byte packed code (stdcall, 1 arg, ret 4)
pub fn getItemClassIdByCode(code: u32) i32 {
    const Fn = *const fn (u32) callconv(.winapi) i32;
    const ptr: Fn = @ptrFromInt(ADDR_GET_ITEM_CLASSID_BY_CODE);
    return ptr(code);
}

/// Generate NPC Item: ECX=pNpc, EDX=itemCode, stack: [pGame, 1, itemLevel, difficulty, page]
pub fn generateNpcItem(pNpc: *UnitAny, pGame: ?*anyopaque, itemCode: u32, itemLevel: u32) ?*UnitAny {
    var buf = [6]u32{
        @intFromPtr(pGame),
        1, // is_vendor = 1
        itemLevel,
        0, // difficulty
        0, // page
        ADDR_GENERATE_NPC_ITEM,
    };
    const raw = asm volatile (
        \\pushl 16(%[buf])
        \\pushl 12(%[buf])
        \\pushl 8(%[buf])
        \\pushl 4(%[buf])
        \\pushl (%[buf])
        \\movl %[npc], %%ecx
        \\movl %[code], %%edx
        \\call *20(%[buf])
        : [ret] "={eax}" (-> usize),
        : [buf] "r" (&buf),
          [npc] "r" (@intFromPtr(pNpc)),
          [code] "r" (itemCode),
        : .{ .ecx = true, .edx = true, .memory = true }
    );
    return if (raw == 0) null else @ptrFromInt(raw);
}
