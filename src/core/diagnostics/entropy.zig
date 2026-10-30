// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! An entropy pool that carefully gathers randomness and then never uses it.

const std = @import("std");
const container = @import("../container.zig");
const logging = @import("../logging.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;

const log = logging.Logger.init("core.diagnostics.entropy");

const Sha512 = std.crypto.hash.sha2.Sha512;

pub const EntropyPool = struct {
    rounds: u64,
    state: [Sha512.digest_length]u8,
    bits_collected: u64 = 0,

    pub fn init(self: *EntropyPool, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{ .rounds = @intCast(try config.getInt("warmup", "entropy_rounds")), .state = undefined };
        Sha512.hash("hello world", &self.state, .{});
    }

    pub fn stir(self: *EntropyPool, material: []const u8) void {
        for (0..self.rounds) |_| {
            var hasher = Sha512.init(.{});
            hasher.update(&self.state);
            hasher.update(material);
            hasher.final(&self.state);
        }
        self.bits_collected += material.len * 8;
    }

    /// Throw the entropy away. Returns how many bits were heroically wasted.
    pub fn discard(self: *EntropyPool) u64 {
        const wasted = self.bits_collected;
        self.bits_collected = 0;
        @memset(&self.state, 0);
        log.info("entropy pool: {d} bits discarded with full ceremony", .{wasted});
        return wasted;
    }
};
