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
    dwSignature: DWORD, // 0x00 (0x1020304)
    bGame1C: ?*anyopaque, // 0x04
    pOwner: ?*UnitAny, // 0x08
    pFirstItem: ?*UnitAny, // 0x0C
    pLastItem: ?*UnitAny, // 0x10
    _14: [2]DWORD, // 0x14
    dwLeftItemUid: DWORD, // 0x1C
    pCursorItem: ?*UnitAny, // 0x20
    dwOwnerId: DWORD, // 0x24
    dwItemCount: DWORD, // 0x28
};

pub const ItemData = extern struct {
    dwQuality: DWORD, // 0x00 (7 = Unique)
    dwSeed: [2]DWORD, // 0x04
    nPlayerGUID: DWORD, // 0x0C
    nModSeed: DWORD, // 0x10
    eItemCmd: DWORD, // 0x14
    dwItemFlags: DWORD, // 0x18 (0x00400000=ethereal, 0x100=personalized, 0x800=socketed)
    _1C: [2]DWORD, // 0x1C
    dwActionStamp: DWORD, // 0x24
    dwFileIndex: DWORD, // 0x28 (UniqueItems.txt row index)
    dwItemLevel: DWORD, // 0x2C (ilvl)
    wItemFormat: WORD, // 0x30
    wRarePrefix: WORD, // 0x32
    wRareSuffix: WORD, // 0x34
    wAutoPrefix: WORD, // 0x36
    wMagicPrefix: [3]WORD, // 0x38
    wMagicSuffix: [3]WORD, // 0x3E
    body_location: BYTE, // 0x44
    item_location: BYTE, // 0x45 (3 = Cube)
    _46: WORD, // 0x46
    bEarLevel: BYTE, // 0x48
    bVariant: BYTE, // 0x49
    szPlayerName: [16]u8, // 0x4A (Personalized name string)
    wRuneWordIndex: WORD, // 0x5A
    pOwnerInventory: ?*Inventory, // 0x5C
    pPrevItem: ?*UnitAny, // 0x60
    pNextItem: ?*UnitAny, // 0x64
    game_location: BYTE, // 0x68
    node_page: BYTE, // 0x69
    _6A: WORD, // 0x6A
    pPrevItemInPage: ?*UnitAny, // 0x6C
    pNextItemInPage: ?*UnitAny, // 0x70

    comptime {
        std.debug.assert(@offsetOf(ItemData, "dwItemFlags") == 0x18);
        std.debug.assert(@offsetOf(ItemData, "dwFileIndex") == 0x28);
        std.debug.assert(@offsetOf(ItemData, "dwItemLevel") == 0x2C);
        std.debug.assert(@offsetOf(ItemData, "item_location") == 0x45);
        std.debug.assert(@offsetOf(ItemData, "szPlayerName") == 0x4A);
        std.debug.assert(@offsetOf(ItemData, "pOwnerInventory") == 0x5C);
        std.debug.assert(@offsetOf(ItemData, "pNextItem") == 0x64);
    }
};

pub const ItemGenerationData = extern struct {
    pUnit: ?*UnitAny, // 0x00
    pNext: ?*anyopaque, // 0x04
    pGame: ?*anyopaque, // 0x08
    nItemLevel: i32, // 0x0C
    field_0x10: DWORD, // 0x10
    nItemClassId: i32, // 0x14
    dwMode: i32, // 0x18
    nPosX: i32, // 0x1C
    nPosY: i32, // 0x20
    pDrlgRoom: ?*anyopaque, // 0x24
    usually_one: i16, // 0x28
    wItemFormat: WORD, // 0x2A
    somethingCustom: BOOL, // 0x2C
    eQuality: DWORD, // 0x30 (7 = Unique)
    nPriceMaybe: i32, // 0x34
    durability: DWORD, // 0x38
    maxDurability: DWORD, // 0x3C
    dwFileIndex: DWORD, // 0x40
    eItemFlag: DWORD, // 0x44
    nInitSeed: i32, // 0x48
    nModSeed: i32, // 0x4C
    bGrade: u8, // 0x50
    _51: [7]u8, // 0x51
    szCustomName: [16]u8, // 0x58
    _68: [24]u8, // 0x68 .. 0x7F
    nFlags: DWORD, // 0x80

    comptime {
        std.debug.assert(@sizeOf(ItemGenerationData) == 0x84);
        std.debug.assert(@offsetOf(ItemGenerationData, "nItemClassId") == 0x14);
        std.debug.assert(@offsetOf(ItemGenerationData, "dwFileIndex") == 0x40);
        std.debug.assert(@offsetOf(ItemGenerationData, "eItemFlag") == 0x44);
        std.debug.assert(@offsetOf(ItemGenerationData, "szCustomName") == 0x58);
    }
};

extern "kernel32" fn VirtualProtect(
    lpAddress: ?*anyopaque,
    dwSize: usize,
    flNewProtect: u32,
    lpflOldProtect: *u32,
) callconv(.winapi) win.BOOL;

pub const PAGE_EXECUTE_READWRITE: u32 = 0x40;

/// Memory addresses in 1.14d Game.exe
pub const ADDR_PACKET_TABLE_0x4F: usize = 0x006E0F90;
pub const ADDR_ORIG_SCMD_0x4F: usize = 0x0054C7C0;
pub const ADDR_SEND_PACKET_HELPER: usize = 0x0053B280;
pub const ADDR_ITEMS_REMOVE_AND_FREE: usize = 0x00557FD0;
pub const ADDR_SPAWN_ITEM_WITH_STRUCT: usize = 0x00558D90;
pub const ADDR_GET_ITEM_CLASSID_BY_CODE: usize = 0x00633680;
pub const ADDR_GET_ITEM_TEXT: usize = 0x006335F0;
pub const ADDR_RECEIVE_ITEM: usize = 0x00560200;
pub const ADDR_DROP_ITEM_GROUND: usize = 0x00555600;
pub const ADDR_PLAY_SOUND_MAYBE: usize = 0x00553380;
pub const ADDR_GET_UNIT_STAT: usize = 0x00625480;
pub const ADDR_SET_ITEM_SOCKETS: usize = 0x0062BE00;
pub const ADDR_ADD_SOCKET_ITEM: usize = 0x0063B210;
pub const ADDR_ADD_STATS_FROM_SOCKET: usize = 0x0055C2C0;
pub const ADDR_ATTACH_PROPERTIES: usize = 0x006276C0;
pub const ADDR_SET_UNIT_MODE: usize = 0x00624690;
pub const ADDR_RECALCULATE_ITEM: usize = 0x0062BED0;
pub const ADDR_UNIQUE_ITEMS_TABLE: usize = 0x0096C854;
pub const ADDR_UNIQUE_ITEMS_COUNT: usize = 0x0096C858;

/// Hook Packet 0x4F by updating the C2S jump table entry
pub fn hookPacket0x4F(new_handler: *const anyopaque) bool {
    var old_protect: u32 = 0;
    const target: *usize = @ptrFromInt(ADDR_PACKET_TABLE_0x4F);

    if (VirtualProtect(target, @sizeOf(usize), PAGE_EXECUTE_READWRITE, &old_protect) == .FALSE) {
        return false;
    }

    target.* = @intFromPtr(new_handler);

    var dummy: u32 = 0;
    _ = VirtualProtect(target, @sizeOf(usize), old_protect, &dummy);
    return true;
}

/// Send in-game server announcement message (color 0x02 = Green) via Packet 0x26
pub fn sendServerMessage(pPlayer: usize, msg: []const u8, color: u8) void {
    const pPlayerUnit: *const UnitAny = @ptrFromInt(pPlayer);
    const pUnitData = pPlayerUnit.pUnitData orelse return;
    const pClient: usize = @as(*align(1) const usize, @ptrFromInt(@intFromPtr(pUnitData) + 0x9C)).*;
    if (pClient == 0) return;

    var buf: [256]u8 = undefined;
    @memset(buf[0..256], 0);

    buf[0] = 0x26; // Packet 0x26
    buf[1] = 0x04; // System Announcement
    buf[2] = color;
    buf[3] = 0x00;
    // bytes 4..7: unit_id = 0
    buf[8] = color;
    buf[9] = 0x00;
    buf[10] = 0x00; // Empty sender name ("\0")

    const max_len = @min(msg.len, 200);
    @memcpy(buf[11 .. 11 + max_len], msg[0..max_len]);
    buf[11 + max_len] = 0x00;

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

/// Remove and free an item unit: ECX=pGame, EDX=pItem
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

/// Spawn item using Blizzard's ItemGenerationData: ECX=pGame, EDX=&genCtx, stack: 1
pub fn spawnItemWithStruct(pGame: ?*anyopaque, genCtx: *ItemGenerationData) ?*UnitAny {
    const raw = asm volatile (
        \\pushl $1
        \\movl %[g], %%ecx
        \\movl %[ctx], %%edx
        \\movl $0x00558D90, %%eax
        \\call *%%eax
        : [ret] "={eax}" (-> usize),
        : [g] "r" (@intFromPtr(pGame)),
          [ctx] "r" (@intFromPtr(genCtx)),
        : .{ .ecx = true, .edx = true, .memory = true }
    );
    return if (raw == 0) null else @ptrFromInt(raw);
}

/// Get item class ID by 4-byte packed code (stdcall, 1 arg, ret 4)
pub fn getItemClassIdByCode(code: u32) i32 {
    const Fn = *const fn (u32) callconv(.winapi) i32;
    const ptr: Fn = @ptrFromInt(ADDR_GET_ITEM_CLASSID_BY_CODE);
    return ptr(code);
}

/// Get 4-byte packed item code from ItemTxt table record offset 0x80
pub fn getItemCode(classId: u32) u32 {
    const GetItemTxtFn = *const fn (u32) callconv(.winapi) ?*anyopaque;
    const getTxt: GetItemTxtFn = @ptrFromInt(ADDR_GET_ITEM_TEXT);
    if (getTxt(classId)) |raw_txt| {
        const p: *align(1) const u32 = @ptrCast(@as([*]const u8, @ptrCast(raw_txt)) + 0x80);
        return p.*;
    }
    return 0;
}

/// Set item inventory page (3 = Cube) directly
pub fn setItemPage(pItem: *UnitAny, page: u8) void {
    const pData = pItem.pUnitData orelse return;
    const pItemData: *ItemData = @ptrCast(@alignCast(pData));
    pItemData.item_location = page;
}

/// Insert item into player inventory / cube and sync network packet to client
pub fn insertItemToInventory(pGame: ?*anyopaque, pPlayer: ?*UnitAny, itemGuid: u32) u32 {
    const ret = asm volatile (
        \\pushl $0
        \\pushl $1
        \\pushl $1
        \\pushl $0
        \\pushl $0
        \\pushl %[guid]
        \\pushl %[p]
        \\pushl %[g]
        \\movl $0x55b, %%edx
        \\movl $0x6e11d8, %%ecx
        \\movl $0x00560200, %%eax
        \\call *%%eax
        : [ret] "={eax}" (-> u32),
        : [guid] "r" (itemGuid),
          [p] "r" (@intFromPtr(pPlayer)),
          [g] "r" (@intFromPtr(pGame)),
        : .{ .ecx = true, .edx = true, .memory = true }
    );
    return ret;
}

/// Drop item on ground near player: ECX=pGame, EDX=pItem
pub fn dropItemToGround(pGame: ?*anyopaque, pItem: *UnitAny) void {
    const fn_addr: u32 = ADDR_DROP_ITEM_GROUND;
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

/// Play cube sound: ECX=pPlayer, EDX=4, stack=[pPlayer]
pub fn playCubeSound(pPlayer: ?*UnitAny) void {
    var buf = [2]u32{ @intFromPtr(pPlayer), ADDR_PLAY_SOUND_MAYBE };
    asm volatile (
        \\pushl (%[buf])
        \\movl %[p], %%ecx
        \\movl $4, %%edx
        \\call *4(%[buf])
        :
        : [buf] "r" (&buf),
          [p] "r" (@intFromPtr(pPlayer)),
        : .{ .ecx = true, .edx = true, .memory = true }
    );
}

/// Get unit stat: stdcall(pUnit, statId, subStat) -> u32
pub fn getUnitStat(pUnit: ?*UnitAny, statId: u32, subStat: u32) u32 {
    const Fn = *const fn (?*UnitAny, DWORD, DWORD) callconv(.winapi) DWORD;
    const ptr: Fn = @ptrFromInt(ADDR_GET_UNIT_STAT);
    return ptr(pUnit, statId, subStat);
}

/// Set item sockets: stdcall(pItem, nSockets)
pub fn setItemSockets(pItem: *UnitAny, nSockets: u32) void {
    const Fn = *const fn (*UnitAny, DWORD) callconv(.winapi) void;
    const ptr: Fn = @ptrFromInt(ADDR_SET_ITEM_SOCKETS);
    ptr(pItem, nSockets);
}

/// Add socket item into socket container: stdcall(pInventory, pSocketItem, 1) -> u32
pub fn addSocketItem(pInventory: ?*anyopaque, pSocketItem: *UnitAny) u32 {
    const Fn = *const fn (?*anyopaque, *UnitAny, DWORD) callconv(.winapi) u32;
    const ptr: Fn = @ptrFromInt(ADDR_ADD_SOCKET_ITEM);
    return ptr(pInventory, pSocketItem, 1);
}

/// Add stats from socketed item to target item: ECX=pGame, EDX=pSocketItem, stack=[pTargetItem, 0]
pub fn addStatsFromSocketItem(pGame: ?*anyopaque, pSocketItem: *UnitAny, pTargetItem: *UnitAny) void {
    asm volatile (
        \\pushl $0
        \\pushl %[target]
        \\movl %[g], %%ecx
        \\movl %[s], %%edx
        \\movl $0x0055C2C0, %%eax
        \\call *%%eax
        :
        : [target] "r" (@intFromPtr(pTargetItem)),
          [g] "r" (@intFromPtr(pGame)),
          [s] "r" (@intFromPtr(pSocketItem)),
        : .{ .eax = true, .ecx = true, .edx = true, .memory = true }
    );
}

/// Attach properties from socketed item to target item: stdcall(pSocketItem, pTargetItem)
pub fn attachProperties(pSocketItem: *UnitAny, pTargetItem: *UnitAny) void {
    const Fn = *const fn (*UnitAny, *UnitAny) callconv(.winapi) void;
    const ptr: Fn = @ptrFromInt(ADDR_ATTACH_PROPERTIES);
    ptr(pSocketItem, pTargetItem);
}

/// Set unit mode: stdcall(pUnit, mode)
pub fn setUnitMode(pUnit: *UnitAny, mode: u32) void {
    const Fn = *const fn (*UnitAny, DWORD) callconv(.winapi) void;
    const ptr: Fn = @ptrFromInt(ADDR_SET_UNIT_MODE);
    ptr(pUnit, mode);
}

pub const ADDR_CREATE_INVENTORY: usize = 0x0063ABD0;
pub const ADDR_REMOVE_PLAYER_ITEM: usize = 0x0055E000;

/// Create and attach Inventory to a Unit: stdcall(pMemPool, pOwnerUnit) -> ?*Inventory
pub fn createInventory(pMemPool: ?*anyopaque, pOwner: *UnitAny) ?*Inventory {
    const Fn = *const fn (?*anyopaque, *UnitAny) callconv(.winapi) ?*Inventory;
    const ptr: Fn = @ptrFromInt(ADDR_CREATE_INVENTORY);
    return ptr(pMemPool, pOwner);
}

/// Safely remove item from player inventory, notify client (Packet 0x9D), and free item unit
/// ESI = pPlayer, EDI = pItem, stack = [pGame] (ret 4)
pub fn removePlayerItem(pGame: ?*anyopaque, pPlayer: *UnitAny, pItem: *UnitAny) void {
    asm volatile (
        \\pushl %%esi
        \\pushl %%edi
        \\pushl %[g]
        \\movl %[p], %%esi
        \\movl %[i], %%edi
        \\movl $0x0055E000, %%eax
        \\call *%%eax
        \\popl %%edi
        \\popl %%esi
        :
        : [g] "r" (@intFromPtr(pGame)),
          [p] "r" (@intFromPtr(pPlayer)),
          [i] "r" (@intFromPtr(pItem)),
        : .{ .eax = true, .ecx = true, .edx = true, .memory = true }
    );
}

/// Recalculate item stats / requirements: stdcall(pItem)
pub fn recalculateItem(pItem: *UnitAny) void {
    const Fn = *const fn (*UnitAny) callconv(.winapi) void;
    const ptr: Fn = @ptrFromInt(ADDR_RECALCULATE_ITEM);
    ptr(pItem);
}

/// Get Unique item name string by dwFileIndex from the engine's data table
pub fn getUniqueItemName(fileIndex: u32) ?[:0]const u8 {
    const pTable: *const usize = @ptrFromInt(ADDR_UNIQUE_ITEMS_TABLE);
    const pCount: *const u32 = @ptrFromInt(ADDR_UNIQUE_ITEMS_COUNT);
    if (pTable.* == 0 or fileIndex >= pCount.*) return null;

    // UniqueItemTxt record size is 0x14C (332 bytes). Name string is at offset +2.
    const record_addr = pTable.* + fileIndex * 0x14C;
    const name_ptr: [*:0]const u8 = @ptrFromInt(record_addr + 2);

    const len = std.mem.indexOfScalar(u8, name_ptr[0..32], 0) orelse return null;
    if (len == 0) return null;
    return name_ptr[0..len :0];
}
