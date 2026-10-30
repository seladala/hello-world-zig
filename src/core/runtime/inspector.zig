// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Disassembler, so that the machine code can be reviewed by the Architecture Board.

const std = @import("std");
const opcodes = @import("opcodes.zig");

pub fn disassemble(allocator: std.mem.Allocator, image: []const u8) ![][]const u8 {
    return disassembleRange(allocator, image, 0, image.len);
}

pub fn disassembleRange(allocator: std.mem.Allocator, image: []const u8, start: usize, end: usize) ![][]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var pc = start;
    while (pc < end) {
        const opcode = image[pc];
        const decoded = opcodes.decode(opcode);
        if (decoded == null or pc + decoded.?.size() > end) {
            try lines.append(allocator, try std.fmt.allocPrint(allocator, "{X:0>4}:  {X:0>2}            .byte 0x{X:0>2}", .{ pc, opcode, opcode }));
            pc += 1;
            continue;
        }
        const spec = decoded.?;
        const raw = image[pc .. pc + spec.size()];

        var hex: std.Io.Writer.Allocating = .init(allocator);
        defer hex.deinit();
        for (raw, 0..) |byte, i| {
            if (i != 0) try hex.writer.writeByte(' ');
            try hex.writer.print("{X:0>2}", .{byte});
        }

        var parts: std.Io.Writer.Allocating = .init(allocator);
        defer parts.deinit();
        var cursor = pc + 1;
        for (spec.operands, 0..) |kind, i| {
            if (i != 0) try parts.writer.writeAll(", ");
            switch (kind) {
                'r' => try parts.writer.print("R{d}", .{image[cursor]}),
                'p' => try parts.writer.print("0x{X:0>2}", .{image[cursor]}),
                else => try parts.writer.print("0x{X:0>4}", .{@as(u16, image[cursor]) | (@as(u16, image[cursor + 1]) << 8)}),
            }
            cursor += opcodes.operandSize(kind);
        }

        const line = try std.fmt.allocPrint(allocator, "{X:0>4}:  {s:<14}{s} {s}", .{ pc, hex.written(), spec.mnemonic(), parts.written() });
        try lines.append(allocator, std.mem.trimRight(u8, line, " "));
        pc += spec.size();
    }
    return lines.items;
}
