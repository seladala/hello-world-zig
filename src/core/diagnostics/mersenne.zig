// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! MT19937, seeded and sampled exactly the way CPython's `random.Random` does it,
//! so that bogosort takes the same number of attempts as it did in Python.
//! Determinism is a feature; reproducible pointlessness is a requirement.

const std = @import("std");

pub const Random = struct {
    const n = 624;
    const m = 397;

    state: [n]u32 = undefined,
    index: usize = n + 1,

    /// `random.Random(seed)` for a non-negative integer seed.
    pub fn init(seed: u64) Random {
        var self: Random = .{};
        var key: [2]u32 = .{ @truncate(seed), @truncate(seed >> 32) };
        const key_len: usize = if (seed >> 32 == 0) 1 else 2;
        self.initByArray(key[0..key_len]);
        return self;
    }

    fn initGenrand(self: *Random, seed: u32) void {
        self.state[0] = seed;
        for (1..n) |i| {
            const previous = self.state[i - 1];
            self.state[i] = 1812433253 *% (previous ^ (previous >> 30)) +% @as(u32, @intCast(i));
        }
        self.index = n;
    }

    fn initByArray(self: *Random, key: []const u32) void {
        self.initGenrand(19650218);
        var i: usize = 1;
        var j: usize = 0;
        var k: usize = @max(n, key.len);
        while (k > 0) : (k -= 1) {
            const previous = self.state[i - 1];
            self.state[i] = (self.state[i] ^ ((previous ^ (previous >> 30)) *% 1664525)) +% key[j] +% @as(u32, @intCast(j));
            i += 1;
            j += 1;
            if (i >= n) {
                self.state[0] = self.state[n - 1];
                i = 1;
            }
            if (j >= key.len) j = 0;
        }
        k = n - 1;
        while (k > 0) : (k -= 1) {
            const previous = self.state[i - 1];
            self.state[i] = (self.state[i] ^ ((previous ^ (previous >> 30)) *% 1566083941)) -% @as(u32, @intCast(i));
            i += 1;
            if (i >= n) {
                self.state[0] = self.state[n - 1];
                i = 1;
            }
        }
        self.state[0] = 0x80000000;
    }

    fn genrandUint32(self: *Random) u32 {
        const upper_mask: u32 = 0x80000000;
        const lower_mask: u32 = 0x7fffffff;
        const mag01 = [2]u32{ 0, 0x9908b0df };
        if (self.index >= n) {
            var kk: usize = 0;
            while (kk < n - m) : (kk += 1) {
                const y = (self.state[kk] & upper_mask) | (self.state[kk + 1] & lower_mask);
                self.state[kk] = self.state[kk + m] ^ (y >> 1) ^ mag01[y & 1];
            }
            while (kk < n - 1) : (kk += 1) {
                const y = (self.state[kk] & upper_mask) | (self.state[kk + 1] & lower_mask);
                self.state[kk] = self.state[kk + m - n] ^ (y >> 1) ^ mag01[y & 1];
            }
            const y = (self.state[n - 1] & upper_mask) | (self.state[0] & lower_mask);
            self.state[n - 1] = self.state[m - 1] ^ (y >> 1) ^ mag01[y & 1];
            self.index = 0;
        }
        var y = self.state[self.index];
        self.index += 1;
        y ^= y >> 11;
        y ^= (y << 7) & 0x9d2c5680;
        y ^= (y << 15) & 0xefc60000;
        y ^= y >> 18;
        return y;
    }

    /// `getrandbits(k)` for 0 < k <= 64.
    pub fn getrandbits(self: *Random, k: u7) u64 {
        std.debug.assert(k > 0 and k <= 64);
        if (k <= 32) return self.genrandUint32() >> @intCast(32 - @as(u6, @intCast(k)));
        const low: u64 = self.genrandUint32();
        const high: u64 = self.genrandUint32() >> @intCast(64 - @as(u7, k));
        return low | (high << 32);
    }

    /// `_randbelow_with_getrandbits(n)`
    pub fn randbelow(self: *Random, bound: u64) u64 {
        if (bound == 0) return 0;
        const k: u7 = @intCast(64 - @clz(bound));
        var r = self.getrandbits(k);
        while (r >= bound) r = self.getrandbits(k);
        return r;
    }

    /// `shuffle(items)`
    pub fn shuffle(self: *Random, comptime T: type, items: []T) void {
        var i = items.len;
        while (i > 1) {
            i -= 1;
            const j = self.randbelow(i + 1);
            std.mem.swap(T, &items[i], &items[j]);
        }
    }

    /// `sample(range(population), k)`
    pub fn sampleRange(self: *Random, allocator: std.mem.Allocator, population: u64, k: usize) ![]u64 {
        std.debug.assert(k <= population);
        const result = try allocator.alloc(u64, k);
        errdefer allocator.free(result);
        var setsize: u64 = 21;
        if (k > 5) {
            const exponent = @ceil(@log(@as(f64, @floatFromInt(k * 3))) / @log(4.0));
            setsize += std.math.pow(u64, 4, @intFromFloat(exponent));
        }
        if (population <= setsize) {
            const pool = try allocator.alloc(u64, population);
            defer allocator.free(pool);
            for (pool, 0..) |*slot, i| slot.* = i;
            for (result, 0..) |*slot, i| {
                const j = self.randbelow(population - i);
                slot.* = pool[j];
                pool[j] = pool[population - i - 1];
            }
        } else {
            var selected = std.AutoHashMap(u64, void).init(allocator);
            defer selected.deinit();
            for (result) |*slot| {
                var j = self.randbelow(population);
                while (selected.contains(j)) j = self.randbelow(population);
                try selected.put(j, {});
                slot.* = j;
            }
        }
        return result;
    }
};
