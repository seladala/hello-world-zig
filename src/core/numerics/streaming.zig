// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Gibbons' unbounded spigot: streams digits of pi one at a time, forever.

const std = @import("std");
const Managed = std.math.big.int.Managed;

pub const Stream = struct {
    q: Managed,
    r: Managed,
    t: Managed,
    k: u64 = 1,
    n: i64 = 3,
    l: u64 = 3,
    // scratch registers, so that "forever" does not also mean "allocate forever"
    a: Managed,
    b: Managed,
    rem: Managed,
    ten: Managed,

    pub fn init(allocator: std.mem.Allocator) !Stream {
        return .{
            .q = try Managed.initSet(allocator, 1),
            .r = try Managed.initSet(allocator, 0),
            .t = try Managed.initSet(allocator, 1),
            .a = try Managed.init(allocator),
            .b = try Managed.init(allocator),
            .rem = try Managed.init(allocator),
            .ten = try Managed.initSet(allocator, 10),
        };
    }

    pub fn deinit(self: *Stream) void {
        inline for (.{ "q", "r", "t", "a", "b", "rem", "ten" }) |name| @field(self, name).deinit();
    }

    /// The next decimal digit of pi. Never returns null; it is a spigot after all.
    pub fn next(self: *Stream) !u8 {
        while (true) {
            // a = 4q + r - t ; b = n * t
            try self.a.set(4);
            try self.a.mul(&self.a, &self.q);
            try self.a.add(&self.a, &self.r);
            try self.a.sub(&self.a, &self.t);
            try self.b.set(self.n);
            try self.b.mul(&self.b, &self.t);
            if (self.a.order(self.b) == .lt) {
                const digit: u8 = @intCast(self.n);
                // n' = (10 * (3q + r)) // t - 10n
                try self.a.set(3);
                try self.a.mul(&self.a, &self.q);
                try self.a.add(&self.a, &self.r);
                try self.a.mul(&self.a, &self.ten);
                try self.a.divFloor(&self.rem, &self.a, &self.t);
                const next_n = (try self.a.toInt(i64)) - 10 * self.n;
                // r' = 10 * (r - n*t)   (b still holds n*t)
                try self.r.sub(&self.r, &self.b);
                try self.r.mul(&self.r, &self.ten);
                // q' = 10q
                try self.q.mul(&self.q, &self.ten);
                self.n = next_n;
                return digit;
            }
            // n' = (q*(7k+2) + r*l) // (t*l)
            try self.a.set(7 * self.k + 2);
            try self.a.mul(&self.a, &self.q);
            try self.b.set(self.l);
            try self.b.mul(&self.b, &self.r);
            try self.a.add(&self.a, &self.b);
            try self.b.set(self.l);
            try self.b.mul(&self.b, &self.t);
            try self.a.divFloor(&self.rem, &self.a, &self.b);
            const next_n = try self.a.toInt(i64);
            // r' = (2q + r) * l
            try self.a.set(2);
            try self.a.mul(&self.a, &self.q);
            try self.r.add(&self.r, &self.a);
            try self.a.set(self.l);
            try self.r.mul(&self.r, &self.a);
            // q' = q*k ; t' = t*l
            try self.a.set(self.k);
            try self.q.mul(&self.q, &self.a);
            try self.a.set(self.l);
            try self.t.mul(&self.t, &self.a);
            self.k += 1;
            self.n = next_n;
            self.l += 2;
        }
    }
};

pub fn piDigits(allocator: std.mem.Allocator, n: usize) ![]u8 {
    var stream = try Stream.init(allocator);
    defer stream.deinit();
    const digits = try allocator.alloc(u8, n);
    for (digits) |*digit| digit.* = '0' + try stream.next();
    return digits;
}
