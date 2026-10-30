// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Warm-up routines. None of them influence the output. All of them are mandatory.

const std = @import("std");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const logging = @import("../logging.zig");
const repr = @import("../repr.zig");
const mersenne = @import("mersenne.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;
const EntropyPool = @import("entropy.zig").EntropyPool;

const log = logging.Logger.init("core.diagnostics.health_check");

const known_prime_counts = [_]struct { u64, u64 }{
    .{ 1000, 168 }, .{ 10000, 1229 }, .{ 20000, 2262 }, .{ 100000, 9592 },
};

pub const WarmupFailure = error{WarmupFailure};

/// Check the Collatz conjecture up to `limit`. Returns the longest trajectory found.
pub fn verifyCollatz(allocator: std.mem.Allocator, limit: u64) !u64 {
    var known = std.AutoHashMap(u64, u64).init(allocator);
    defer known.deinit();
    try known.put(1, 0);
    var path: std.ArrayList(u64) = .empty;
    defer path.deinit(allocator);
    var longest: u64 = 0;
    var start: u64 = 1;
    while (start <= limit) : (start += 1) {
        path.clearRetainingCapacity();
        var n = start;
        while (!known.contains(n)) {
            try path.append(allocator, n);
            n = if (n % 2 == 0) n / 2 else 3 * n + 1;
        }
        var steps = known.get(n).?;
        var i = path.items.len;
        while (i > 0) {
            i -= 1;
            steps += 1;
            try known.put(path.items[i], steps);
        }
        longest = @max(longest, known.get(start).?);
    }
    return longest;
}

pub fn countPrimes(allocator: std.mem.Allocator, limit: usize) !u64 {
    const sieve = try allocator.alloc(bool, limit + 1);
    defer allocator.free(sieve);
    @memset(sieve, true);
    sieve[0] = false;
    if (limit >= 1) sieve[1] = false;
    var i: usize = 2;
    while (i * i <= limit) : (i += 1) {
        if (!sieve[i]) continue;
        var j = i * i;
        while (j <= limit) : (j += i) sieve[j] = false;
    }
    var count: u64 = 0;
    for (sieve) |is_prime| count += @intFromBool(is_prime);
    return count;
}

/// `fractions.Fraction`, as much of it as Gaussian elimination needs.
pub const Fraction = struct {
    num: i64,
    den: i64 = 1,

    fn make(num: i64, den: i64) Fraction {
        const sign: i64 = if (den < 0) -1 else 1;
        const g: i64 = @intCast(std.math.gcd(@abs(num), @abs(den)));
        return .{ .num = sign * @divExact(num, g), .den = sign * @divExact(den, g) };
    }

    pub fn sub(a: Fraction, b: Fraction) Fraction {
        return make(a.num * b.den - b.num * a.den, a.den * b.den);
    }

    pub fn mul(a: Fraction, b: Fraction) Fraction {
        return make(a.num * b.num, a.den * b.den);
    }

    pub fn div(a: Fraction, b: Fraction) Fraction {
        return make(a.num * b.den, a.den * b.num);
    }

    pub fn neg(a: Fraction) Fraction {
        return .{ .num = -a.num, .den = a.den };
    }

    pub fn eql(a: Fraction, b: Fraction) bool {
        return a.num == b.num and a.den == b.den;
    }

    /// `str(fraction)`
    pub fn format(self: Fraction, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.den == 1) return w.print("{d}", .{self.num});
        try w.print("{d}/{d}", .{ self.num, self.den });
    }
};

/// Gaussian elimination on the identity matrix, in exact rational arithmetic.
pub fn identityDeterminant(allocator: std.mem.Allocator, size: usize) !Fraction {
    const m = try allocator.alloc([]Fraction, size);
    defer {
        for (m) |row| allocator.free(row);
        allocator.free(m);
    }
    for (m, 0..) |*row, r| {
        row.* = try allocator.alloc(Fraction, size);
        for (row.*, 0..) |*cell, col| cell.* = .{ .num = @intFromBool(r == col) };
    }
    var det: Fraction = .{ .num = 1 };
    for (0..size) |col| {
        const pivot = for (col..size) |r| {
            if (m[r][col].num != 0) break r;
        } else return failure.raise(error.WarmupFailure, "matrix is singular", .{});
        if (pivot != col) {
            std.mem.swap([]Fraction, &m[col], &m[pivot]);
            det = det.neg();
        }
        det = det.mul(m[col][col]);
        for (col + 1..size) |r| {
            const factor = m[r][col].div(m[col][col]);
            for (m[r], m[col]) |*a, b| a.* = a.sub(factor.mul(b));
        }
    }
    return det;
}

fn isSorted(items: []const i64) bool {
    for (items[0..items.len -| 1], items[@min(1, items.len)..]) |a, b| {
        if (a > b) return false;
    }
    return true;
}

pub fn bogosort(items: []i64, rng: *mersenne.Random) u64 {
    var attempts: u64 = 0;
    while (!isSorted(items)) {
        rng.shuffle(i64, items);
        attempts += 1;
    }
    return attempts;
}

pub const WarmupOrchestrator = struct {
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    config: *EnterpriseConfiguration,
    entropy: *EntropyPool,

    pub fn init(self: *WarmupOrchestrator, deps: *container.Deps) !void {
        self.* = .{
            .allocator = deps.allocator,
            .scratch = deps.scratch,
            .config = try deps.get(EnterpriseConfiguration, "config"),
            .entropy = try deps.get(EntropyPool, "entropy_pool"),
        };
    }

    pub fn onStart(self: *WarmupOrchestrator) !void {
        const cfg = self.config;
        const longest = try verifyCollatz(self.scratch, @intCast(try cfg.getInt("warmup", "collatz_limit")));
        log.info("warmup: Collatz conjecture holds (longest trajectory: {d} steps)", .{longest});

        const limit: u64 = @intCast(try cfg.getInt("warmup", "sieve_limit"));
        const primes = try countPrimes(self.scratch, limit);
        for (known_prime_counts) |known| {
            if (known[0] == limit and known[1] != primes) {
                return failure.raise(error.WarmupFailure, "number theory is broken: pi({d}) = {d}", .{ limit, primes });
            }
        }
        log.info("warmup: {d} primes below {d}, as expected", .{ primes, limit });

        const det = try identityDeterminant(self.scratch, @intCast(try cfg.getInt("warmup", "matrix_size")));
        if (!det.eql(.{ .num = 1 })) {
            return failure.raise(error.WarmupFailure, "det(I) = {f}", .{det});
        }
        log.info("warmup: det(I) = 1, linear algebra operational", .{});

        var rng: mersenne.Random = .init(0xC0FFEE);
        const size: usize = @intCast(try cfg.getInt("warmup", "bogosort_size"));
        const sample = try rng.sampleRange(self.allocator, 100, size);
        const items = try self.allocator.alloc(i64, size);
        for (items, sample) |*item, value| item.* = @intCast(value);
        const attempts = bogosort(items, &rng);
        log.info("warmup: bogosort sorted {f} in {d} attempts", .{ repr.list(items), attempts });

        const material = try std.fmt.allocPrint(self.allocator, "({d}, {d}, Fraction({d}, {d}), {f}, {d})", .{
            longest, primes, det.num, det.den, repr.list(items), attempts,
        });
        self.entropy.stir(material);
        _ = self.entropy.discard();
    }
};
