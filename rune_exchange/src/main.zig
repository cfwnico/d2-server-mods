const std = @import("std");
const win = std.os.windows;
const d2 = @import("d2engine.zig");
const cfg = @import("config.zig");
const exchange = @import("exchange.zig");

pub export fn Hook_SCMD_0x33() callconv(.naked) void {
    asm volatile (
        \\pushal
        \\pushfl
        \\pushl 44(%%esp)
        \\pushl 44(%%esp)
        \\pushl %%edx
        \\pushl %%ecx
        \\call %[handler:P]
        \\add $16, %%esp
        \\test %%eax, %%eax
        \\jnz .Lhandled
        \\popfl
        \\popal
        \\movl $0x0054BB20, %%eax
        \\jmp *%%eax
        \\.Lhandled:
        \\popfl
        \\popal
        \\xorl %%eax, %%eax
        \\ret $8
        :
        : [handler] "X" (&exchange.onSellPacket),
    );
}

pub export fn DllMain(hinst: win.HINSTANCE, reason: win.DWORD, reserved: win.LPVOID) callconv(.winapi) win.BOOL {
    _ = hinst;
    _ = reserved;

    if (reason == 1) { // DLL_PROCESS_ATTACH
        exchange.initLock();
        exchange.logMsg("Initializing Rune Exchange Mod...\n", .{});
        exchange.g_config = cfg.Config.load();

        exchange.logMsg("Config: Enable={d}, TestMode={d}, OnlyAkara={d}, MinRune={d}, MaxRune={d}\n", .{
            @as(u32, if (exchange.g_config.enabled) 1 else 0),
            @as(u32, if (exchange.g_config.test_mode) 1 else 0),
            @as(u32, if (exchange.g_config.only_akara) 1 else 0),
            exchange.g_config.min_rune,
            exchange.g_config.max_rune,
        });

        if (exchange.g_config.enabled) {
            if (d2.hookPacket0x33(&Hook_SCMD_0x33)) {
                exchange.logMsg("Successfully hooked Packet 0x33 at 0x{X:08}!\n", .{d2.ADDR_PACKET_TABLE_0x33});
            } else {
                exchange.logMsg("FAILED to hook Packet 0x33 at 0x{X:08}!\n", .{d2.ADDR_PACKET_TABLE_0x33});
            }
        } else {
            exchange.logMsg("Rune Exchange Mod is DISABLED via config.\n", .{});
        }
    }

    return .TRUE;
}
