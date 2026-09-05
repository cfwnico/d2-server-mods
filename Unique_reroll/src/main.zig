const std = @import("std");
const win = std.os.windows;
const d2 = @import("d2engine.zig");
const cfg = @import("config.zig");
const reroll = @import("reroll.zig");

pub export fn Hook_SCMD_0x4F() callconv(.naked) void {
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
        \\movl $0x0054C7C0, %%eax
        \\jmp *%%eax
        \\.Lhandled:
        \\popfl
        \\popal
        \\xorl %%eax, %%eax
        \\ret $8
        :
        : [handler] "X" (&reroll.onCubePacket),
    );
}

pub export fn DllMain(hinst: win.HINSTANCE, reason: win.DWORD, reserved: win.LPVOID) callconv(.winapi) win.BOOL {
    _ = hinst;
    _ = reserved;

    if (reason == 1) { // DLL_PROCESS_ATTACH
        reroll.initLock();
        reroll.logMsg("Initializing Unique Reroll Mod...\n", .{});
        reroll.g_config = cfg.Config.load();

        reroll.logMsg("Config: Enable={}, Input1='{s}', Input2='{s}', Input1Code=0x{X:08}, Input2Code=0x{X:08}\n", .{
            reroll.g_config.enabled,
            std.mem.sliceTo(&reroll.g_config.input1_str, 0),
            std.mem.sliceTo(&reroll.g_config.input2_str, 0),
            reroll.g_config.input1_code,
            reroll.g_config.input2_code,
        });

        if (reroll.g_config.enabled) {
            if (d2.hookPacket0x4F(&Hook_SCMD_0x4F)) {
                reroll.logMsg("Successfully hooked Packet 0x4F at 0x{X:08}!\n", .{d2.ADDR_PACKET_TABLE_0x4F});
            } else {
                reroll.logMsg("FAILED to hook Packet 0x4F at 0x{X:08}!\n", .{d2.ADDR_PACKET_TABLE_0x4F});
            }
        } else {
            reroll.logMsg("Unique Reroll Mod is DISABLED via config.\n", .{});
        }
    }

    return .TRUE;
}
