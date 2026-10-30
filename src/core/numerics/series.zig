// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! John Machin's 1706 formula: pi/4 = 4*arctan(1/5) - arctan(1/239).

const std = @import("std");
const high_precision = @import("high_precision.zig");
const Managed = std.math.big.int.Managed;

fn arctanInv(allocator: std.mem.Allocator, x: u32, scale: *const Managed) !Managed {
    var remainder = try Managed.init(allocator);
    defer remainder.deinit();
    var divisor = try Managed.initSet(allocator, x);
    defer divisor.deinit();

    var term = try Managed.init(allocator);
    defer term.deinit();
    try term.divFloor(&remainder, scale, &divisor);
    var total = try term.clone();
    errdefer total.deinit();

    var piece = try Managed.init(allocator);
    defer piece.deinit();
    var n: u64 = 1;
    var negative = true;
    while (!term.eqlZero()) {
        try divisor.set(@as(u64, x) * x);
        try term.divFloor(&remainder, &term, &divisor);
        try divisor.set(2 * n + 1);
        try piece.divFloor(&remainder, &term, &divisor);
        if (negative) try total.sub(&total, &piece) else try total.add(&total, &piece);
        negative = !negative;
        n += 1;
    }
    return total;
}

pub fn piDigits(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const guard = 10;
    var scale = try Managed.initSet(allocator, 10);
    defer scale.deinit();
    try scale.pow(&scale, @intCast(n + guard));

    var a = try arctanInv(allocator, 5, &scale);
    defer a.deinit();
    var b = try arctanInv(allocator, 239, &scale);
    defer b.deinit();

    var four = try Managed.initSet(allocator, 4);
    defer four.deinit();
    try a.mul(&a, &four);
    try a.sub(&a, &b);
    try a.mul(&a, &four);
    return high_precision.truncatedDecimal(allocator, &a, n);
}
