// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Re-pins every protected file in src/core/security/checksums.sha256.
//! Run it after an intentional change, or the program will (rightly) refuse to greet.

const std = @import("std");
const core = @import("core");

const integrity = core.security.integrity;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const root = core.paths.projectRoot();
    const entries = try integrity.computeManifest(arena, root);
    const path = try core.paths.resolve(arena, integrity.checksums_path);
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try integrity.writeManifest(&writer.interface, entries);
    try writer.interface.flush();
    std.debug.print("pinned {d} files in {s}\n", .{ entries.len, integrity.checksums_path });
}
