// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Byzantine-fault-tolerant consensus on the value of pi.
//!
//! Three independent algorithms each propose digits. A digit string is accepted
//! only when a quorum of oracles agrees on it. If the universe ever disagrees
//! with itself about pi, we will be the first to know.

const std = @import("std");
const failure = @import("../failure.zig");
const logging = @import("../logging.zig");
const high_precision = @import("high_precision.zig");
const series = @import("series.zig");
const streaming = @import("streaming.zig");

const log = logging.Logger.init("core.numerics.quorum");

pub const PiConsensusFailure = error{PiConsensusFailure};

pub const PiOracle = struct {
    name: []const u8,
    compute: *const fn (std.mem.Allocator, usize) anyerror![]u8,
    max_digits: usize,
};

pub const oracles = [_]PiOracle{
    .{ .name = "Chudnovsky (1988)", .compute = high_precision.piDigits, .max_digits = 1_000_000 },
    .{ .name = "Machin (1706)", .compute = series.piDigits, .max_digits = 50_000 },
    .{ .name = "Gibbons spigot (2006)", .compute = streaming.piDigits, .max_digits = 2_000 },
};

pub const PiConsensusProtocol = struct {
    oracles: []const PiOracle = &oracles,
    quorum: usize = 2,

    /// Returns the agreed digits, allocated with `allocator`. `scratch` holds the proposals.
    pub fn agree(self: PiConsensusProtocol, allocator: std.mem.Allocator, scratch: std.mem.Allocator, digits: usize) ![]u8 {
        var proposals: std.ArrayList([]u8) = .empty;
        defer {
            for (proposals.items) |proposal| scratch.free(proposal);
            proposals.deinit(scratch);
        }
        for (self.oracles) |oracle| {
            const proposal = try oracle.compute(scratch, @min(digits, oracle.max_digits));
            errdefer scratch.free(proposal);
            log.debug("oracle {s:<22} proposes {s}... ({d} digits)", .{ oracle.name, proposal[0..@min(12, proposal.len)], proposal.len });
            try proposals.append(scratch, proposal);
        }
        // Every full-length proposal is a candidate; oracles with a shorter
        // horizon endorse any candidate that extends what they can see.
        var winner: ?[]const u8 = null;
        var best: usize = 0;
        for (proposals.items, 0..) |candidate, index| {
            if (candidate.len != digits) continue;
            const seen_before = for (proposals.items[0..index]) |earlier| {
                if (std.mem.eql(u8, earlier, candidate)) break true;
            } else false;
            if (seen_before) continue;
            var votes: usize = 0;
            for (proposals.items) |proposal| {
                if (std.mem.startsWith(u8, candidate, proposal)) votes += 1;
            }
            if (votes > best) {
                winner = candidate;
                best = votes;
            }
        }
        const agreed = winner orelse return failure.raise(error.PiConsensusFailure, "no oracle could see far enough", .{});
        if (best < self.quorum) {
            return failure.raise(error.PiConsensusFailure, "no quorum on pi ({d}/{d})", .{ best, proposals.items.len });
        }
        log.info("pi consensus reached: {d}/{d} oracles agree on {d} digits", .{ best, proposals.items.len, digits });
        return allocator.dupe(u8, agreed);
    }
};
