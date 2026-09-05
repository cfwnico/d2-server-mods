const std = @import("std");
const win = std.os.windows;
const d2 = @import("d2engine.zig");
const cfg = @import("config.zig");

extern "kernel32" fn OutputDebugStringA(lpOutputString: [*:0]const u8) callconv(.winapi) void;
extern "kernel32" fn CreateFileA(
    lpFileName: [*:0]const u8,
    dwDesiredAccess: win.DWORD,
    dwShareMode: win.DWORD,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: win.DWORD,
    dwFlagsAndAttributes: win.DWORD,
    hTemplateFile: ?*anyopaque,
) callconv(.winapi) ?*anyopaque;

extern "kernel32" fn WriteFile(
    hFile: *anyopaque,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: win.DWORD,
    lpNumberOfBytesWritten: ?*win.DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) win.BOOL;

extern "kernel32" fn CloseHandle(hObject: *anyopaque) callconv(.winapi) win.BOOL;
extern "kernel32" fn SetFilePointer(
    hFile: *anyopaque,
    lDistanceToMove: win.LONG,
    lpDistanceToMoveHigh: ?*win.LONG,
    dwMoveMethod: win.DWORD,
) callconv(.winapi) win.DWORD;

extern "kernel32" fn GetTickCount() callconv(.winapi) u32;

extern "kernel32" fn InitializeCriticalSection(lpCriticalSection: *anyopaque) callconv(.winapi) void;
extern "kernel32" fn EnterCriticalSection(lpCriticalSection: *anyopaque) callconv(.winapi) void;
extern "kernel32" fn LeaveCriticalSection(lpCriticalSection: *anyopaque) callconv(.winapi) void;

var g_crit_section: [24]u8 align(4) = [_]u8{0} ** 24;
var g_crit_inited: bool = false;
var g_seed_counter: u32 = 0x12345678;

var g_log_handle: ?*anyopaque = null;
var g_log_init: bool = false;

pub var g_config: cfg.Config = .{};

pub fn initLock() void {
    if (!g_crit_inited) {
        InitializeCriticalSection(&g_crit_section);
        g_crit_inited = true;
    }
}

fn getLogHandle() ?*anyopaque {
    if (g_log_init) return g_log_handle;
    g_log_init = true;

    const targets = [_][*:0]const u8{
        "Z:\\mods\\Unique_reroll.log",
        "Unique_reroll.log",
        ".\\mods\\Unique_reroll.log",
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
    if (g_crit_inited) EnterCriticalSection(&g_crit_section);
    defer if (g_crit_inited) LeaveCriticalSection(&g_crit_section);

    var buf: [512:0]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "[Unique_reroll] " ++ fmt, args) catch return;

    OutputDebugStringA(msg.ptr);

    if (getLogHandle()) |h| {
        _ = SetFilePointer(h, 0, null, 2); // FILE_END
        var written: win.DWORD = 0;
        _ = WriteFile(h, msg.ptr, @intCast(msg.len), &written, null);
    }
}

/// Check if a unique item is a quest item to be excluded
pub fn isQuestItem(classId: u32, fileIndex: u32) bool {
    // Unique quest item indices in UniqueItems.txt:
    // 123: vip (Amulet of the Viper)
    // 124: msf (Staff of Kings)
    // 125: hst (Horadric Staff)
    // 126: hfh (Hell Forge Hammer)
    // 127: qf1 (Khalim's Flail)
    // 128: qf2 (Super Khalim's Flail)
    if (fileIndex >= 123 and fileIndex <= 128) return true;

    // Horadric Cube itself (box = classId 549)
    if (classId == 549) return true;

    return false;
}

/// Check if the unique item naturally rolls variable sockets in UniqueItems.txt
pub fn isVariableSocketsUnique(fileIndex: u32) bool {
    return switch (fileIndex) {
        291, // Djinnslayer (1~2)
        299, // Tomb Reaver (1~3)
        314, // Runemaster (3~5)
        345, // Crown of Ages (1~2)
        372, // Heaven's Light (1~3)
        380, // Giantskull (1~2)
        391, // Headhunter's Glory (1~3)
        => true,
        else => false,
    };
}

/// Main C2S Packet 0x4F interception callback
pub fn onCubePacket(pGame: usize, pPlayer: usize, pPacket: usize, nPacketLen: usize) callconv(.c) i32 {
    // Packet 0x4F is strictly 7 bytes in 1.14d Game.exe
    if (pGame == 0 or pPlayer == 0 or pPacket == 0 or nPacketLen != 7) return 0;

    const pPktBytes: [*]const u8 = @ptrFromInt(pPacket);
    if (pPktBytes[0] != 0x4F) return 0;

    // Action word at pPacket+1 (0x0018 is the Transmute button in Horadric Cube)
    const action: u16 = @as(u16, pPktBytes[1]) | (@as(u16, pPktBytes[2]) << 8);
    if (action != 0x0018) return 0;

    // Protect global config and reroll operations with critical section
    if (g_crit_inited) EnterCriticalSection(&g_crit_section);
    defer if (g_crit_inited) LeaveCriticalSection(&g_crit_section);

    // Live hot-reload config on transmute click
    g_config = cfg.Config.load();
    if (!g_config.enabled) return 0;

    if (tryUniqueReroll(pGame, pPlayer)) {
        // Handled: block vanilla 0x0054C7C0 from executing
        return 1;
    }

    // Pass through to vanilla cube processing
    return 0;
}

fn tryUniqueReroll(pGame: usize, pPlayer: usize) bool {
    const pPlayerUnit: *d2.UnitAny = @ptrFromInt(pPlayer);
    const pInv = pPlayerUnit.pInventory orelse return false;

    // 1. Scan player inventory for items inside the Horadric Cube (bPage == 3)
    var cube_items: [16]*d2.UnitAny = undefined;
    var cube_count: usize = 0;

    var curr = pInv.pFirstItem;
    var safety: usize = 0;
    while (curr) |item| : (safety += 1) {
        if (safety > 512) break;
        if (item.dwType == 4) {
            if (item.pUnitData) |data| {
                const idata: *d2.ItemData = @ptrCast(@alignCast(data));
                if (idata.item_location == 3) {
                    if (cube_count < 16) {
                        cube_items[cube_count] = item;
                        cube_count += 1;
                    } else {
                        return false;
                    }
                }
            }
        }
        if (item.pUnitData) |data| {
            const idata: *d2.ItemData = @ptrCast(@alignCast(data));
            curr = idata.pNextItem;
        } else {
            break;
        }
    }

    // Formula requires strictly 1 Unique + configured input materials
    const expected_count: usize = if (g_config.has_input2) 3 else 2;
    if (cube_count != expected_count) return false;

    var pUnique: ?*d2.UnitAny = null;
    var pInput1: ?*d2.UnitAny = null;
    var pInput2: ?*d2.UnitAny = null;
    var matched_in1 = false;
    var matched_in2 = false;

    for (cube_items[0..expected_count]) |item| {
        const idata: *d2.ItemData = @ptrCast(@alignCast(item.pUnitData.?));
        const item_code = d2.getItemCode(item.dwTxtFileNo);
        if (idata.dwQuality == 7 and !isQuestItem(item.dwTxtFileNo, idata.dwFileIndex) and pUnique == null) {
            pUnique = item;
        } else if (!matched_in1 and item_code == g_config.input1_code) {
            matched_in1 = true;
            pInput1 = item;
        } else if (g_config.has_input2 and !matched_in2 and item_code == g_config.input2_code) {
            matched_in2 = true;
            pInput2 = item;
        } else {
            // Unmatched item present in cube
            return false;
        }
    }

    if (pUnique == null or pInput1 == null or (g_config.has_input2 and pInput2 == null)) {
        return false;
    }

    const oldItem = pUnique.?;
    const oldData: *d2.ItemData = @ptrCast(@alignCast(oldItem.pUnitData.?));

    const dwFileIndex = oldData.dwFileIndex;
    const dwTxtFileNo = oldItem.dwTxtFileNo;
    const dwItemLevel = oldData.dwItemLevel;
    const bEthereal = (oldData.dwItemFlags & 0x00400000) != 0;
    const bPersonalized = (oldData.dwItemFlags & 0x00000100) != 0;
    const szPlayerName = oldData.szPlayerName;
    const wItemFormat = oldData.wItemFormat;

    const oldSockets = d2.getUnitStat(oldItem, 194, 0);
    const oldMaxDur = d2.getUnitStat(oldItem, 73, 0);

    // Collect all socketed gems/runes/jewels from old item
    var socketed_gems: [6]*d2.UnitAny = undefined;
    var gem_count: usize = 0;
    if (oldItem.pInventory) |itemInv| {
        var gem_curr = itemInv.pFirstItem;
        var gem_safety: usize = 0;
        while (gem_curr) |gem| : (gem_safety += 1) {
            if (gem_safety > 16) break;
            if (gem_count < 6) {
                socketed_gems[gem_count] = gem;
                gem_count += 1;
            }
            if (gem.pUnitData) |gemData| {
                const gData: *d2.ItemData = @ptrCast(@alignCast(gemData));
                gem_curr = gData.pNextItem;
            } else break;
        }
    }

    const is_var_socket = isVariableSocketsUnique(dwFileIndex);

    if (g_config.debug_log) {
        logMsg("Triggering Unique Reroll: FileIndex={d}, TxtFileNo={d}, ilvl={d}, Ethereal={}, Sockets={d}, Gems={d}, VarSockets={}\n", .{
            dwFileIndex,
            dwTxtFileNo,
            dwItemLevel,
            bEthereal,
            oldSockets,
            gem_count,
            is_var_socket,
        });
    }

    // 2. Generate a brand new Unique instance using Blizzard's ItemGenerationData
    var gen = std.mem.zeroes(d2.ItemGenerationData);
    gen.pGame = @ptrFromInt(pGame);
    gen.nItemLevel = @as(i32, @bitCast(dwItemLevel));
    gen.nItemClassId = @as(i32, @bitCast(dwTxtFileNo));
    gen.dwMode = 4; // ITEMMODE_CURSOR (container staging)
    gen.usually_one = 1;
    gen.wItemFormat = if (wItemFormat != 0) wItemFormat else 0x65;
    gen.somethingCustom = 1;
    gen.eQuality = 7; // Unique
    gen.dwFileIndex = dwFileIndex;

    // Fully restore durability if the item base uses durability
    if (oldMaxDur > 0) {
        gen.durability = oldMaxDur;
        gen.maxDurability = oldMaxDur;
    }

    // Dynamic seeds for true re-roll of variables & base defense
    g_seed_counter +%= 0x9E3779B9;
    const t_now = GetTickCount();
    gen.nInitSeed = @as(i32, @bitCast(t_now ^ g_seed_counter));
    gen.nModSeed = @as(i32, @bitCast((t_now *% 1103515245 +% 12345) ^ (g_seed_counter *% 31)));

    // Unique rerolled items are identified
    gen.eItemFlag |= 0x00000010;

    if (bEthereal) {
        gen.eItemFlag |= 0x00400000;
    }
    if (bPersonalized) {
        gen.eItemFlag |= 0x00000100;
        @memcpy(&gen.szCustomName, &szPlayerName);
    }

    const pNewItem = d2.spawnItemWithStruct(@ptrFromInt(pGame), &gen);
    if (pNewItem == null) {
        logMsg("ERROR: spawnItemWithStruct returned null for Unique fileIndex={d}!\n", .{dwFileIndex});
        return false;
    }

    const newItem = pNewItem.?;
    const newData: *d2.ItemData = @ptrCast(@alignCast(newItem.pUnitData.?));

    // Ensure item level, identified, ethereal, and personalized flags are strictly copied
    newData.dwItemLevel = dwItemLevel;
    newData.dwItemFlags |= 0x00000010; // Identified
    if (bEthereal) {
        newData.dwItemFlags |= 0x00400000;
    } else {
        newData.dwItemFlags &= ~@as(u32, 0x00400000);
    }
    if (bPersonalized) {
        newData.dwItemFlags |= 0x00000100;
        newData.szPlayerName = szPlayerName;
    }

    // 3. Handle Sockets & Socketed Items
    var newSockets = d2.getUnitStat(newItem, 194, 0);

    if (!is_var_socket and oldSockets > 0 and newSockets == 0) {
        // Quest punched socket (Larzuk/SOJ): preserve the fixed 1 socket
        d2.setItemSockets(newItem, oldSockets);
        newSockets = oldSockets;
    }

    // Ensure newItem has an Inventory container if it has sockets
    if (newItem.pInventory == null and newSockets > 0) {
        _ = d2.createInventory(null, newItem);
    }

    // Calculate how many socketed items to retain
    const keep_gems_count = @min(gem_count, @as(usize, newSockets));

    // Detach all gems from old item's inventory so destroying old item won't free them
    if (oldItem.pInventory) |oldInv| {
        oldInv.pFirstItem = null;
        oldInv.pLastItem = null;
        oldInv.dwItemCount = 0;
    }

    // Safely free discarded excess gems if newSockets < gem_count
    if (gem_count > keep_gems_count) {
        for (socketed_gems[keep_gems_count..gem_count]) |excessGem| {
            d2.removeItemAndFree(@ptrFromInt(pGame), excessGem);
        }
    }

    // Transfer retained gems to new item
    var gi: usize = 0;
    while (gi < keep_gems_count) : (gi += 1) {
        const gem = socketed_gems[gi];
        const gemData: *d2.ItemData = @ptrCast(@alignCast(gem.pUnitData.?));
        gemData.pOwnerInventory = null;
        gemData.pPrevItem = null;
        gemData.pNextItem = null;

        if (newItem.pInventory) |newInv| {
            _ = d2.addSocketItem(newInv, gem);
            d2.addStatsFromSocketItem(@ptrFromInt(pGame), gem, newItem);
            d2.setUnitMode(gem, 6); // ITEMMODE_SOCKET
        }
    }
    if (keep_gems_count > 0) {
        d2.recalculateItem(newItem);
    }

    // 4. Safely notify client (Packet 0x9D) and unlink+free old items from player inventory
    d2.removePlayerItem(@ptrFromInt(pGame), pPlayerUnit, oldItem);
    d2.removePlayerItem(@ptrFromInt(pGame), pPlayerUnit, pInput1.?);
    if (pInput2) |in2| {
        d2.removePlayerItem(@ptrFromInt(pGame), pPlayerUnit, in2);
    }

    // 5. Place new item into Horadric Cube (Page 3) and sync to client
    d2.setItemPage(newItem, 3);
    const syncRet = d2.insertItemToInventory(@ptrFromInt(pGame), pPlayerUnit, newItem.dwUnitId);
    if (syncRet == 0) {
        // Insertion failed: safely free item to avoid memory leaks
        d2.removeItemAndFree(@ptrFromInt(pGame), newItem);
        return false;
    }

    // 6. Send Green English system announcement in chat box
    var msg_buf: [128]u8 = undefined;
    const item_name = d2.getUniqueItemName(dwFileIndex) orelse "Unique Item";
    const msg = std.fmt.bufPrint(&msg_buf, "[Unique Reroll] Successfully rerolled {s}!", .{item_name}) catch "[Unique Reroll] Successfully rerolled Unique Item!";
    d2.sendServerMessage(pPlayer, msg, 0x02); // 0x02 = Green

    if (g_config.debug_log) {
        logMsg("Reroll SUCCESS: {s} (NewSockets={d}, RetainedGems={d})\n", .{
            item_name,
            newSockets,
            keep_gems_count,
        });
    }

    return true;
}
