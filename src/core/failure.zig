// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Zig errors carry no payload, so the human-readable reason for the most
//! recent failure is parked here, in one global buffer, like in the good old days.

const std = @import("std");

var buffer: [2048]u8 = undefined;
var length: usize = 0;

/// Record why something went wrong and hand back the error to return.
pub fn raise(err: anytype, comptime fmt: []const u8, args: anytype) @TypeOf(err) {
    const text = std.fmt.bufPrint(&buffer, fmt, args) catch blk: {
        const ellipsis = "...";
        @memcpy(buffer[buffer.len - ellipsis.len ..], ellipsis);
        break :blk buffer[0..];
    };
    length = text.len;
    return err;
}

/// The message attached to the most recent `raise`, or "" if nothing was raised.
pub fn message() []const u8 {
    return buffer[0..length];
}

pub fn clear() void {
    length = 0;
}
