// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Peano arithmetic, for counting characters the way Giuseppe intended.

const std = @import("std");

/// Either Z (no predecessor) or S(predecessor).
pub const Natural = struct {
    predecessor: ?*const Natural,

    pub fn format(self: *const Natural, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.predecessor) |p| {
            try w.writeAll("S(");
            try p.format(w);
            try w.writeByte(')');
        } else {
            try w.writeByte('Z');
        }
    }
};

const zero_instance: Natural = .{ .predecessor = null };

/// The one and only Zero.
pub const ZERO: *const Natural = &zero_instance;

pub fn succ(allocator: std.mem.Allocator, n: *const Natural) !*const Natural {
    const next = try allocator.create(Natural);
    next.* = .{ .predecessor = n };
    return next;
}

pub fn add(allocator: std.mem.Allocator, a: *const Natural, b: *const Natural) !*const Natural {
    var x = a;
    var y = b;
    while (y.predecessor) |p| {
        x = try succ(allocator, x);
        y = p;
    }
    return x;
}

/// Length of a UTF-8 string, in code points, in Peano numerals.
pub fn peanoLength(allocator: std.mem.Allocator, sequence: []const u8) !*const Natural {
    var total = ZERO;
    var it = (try std.unicode.Utf8View.init(sequence)).iterator();
    while (it.nextCodepointSlice()) |_| {
        total = try add(allocator, total, try succ(allocator, ZERO));
    }
    return total;
}

pub fn toInt(n: *const Natural) u64 {
    var count: u64 = 0;
    var cursor = n;
    while (cursor.predecessor) |p| {
        cursor = p;
        count += 1;
    }
    return count;
}
