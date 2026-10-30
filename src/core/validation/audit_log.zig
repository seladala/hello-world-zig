// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! GlyphChain: a proof-of-work blockchain that records every approved character.
//!
//! Decentralised across exactly one process.

const std = @import("std");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const pyjson = @import("../pyjson.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;
const EventBus = @import("../events.zig").EventBus;

pub const genesis_hash = "0" ** 64;

pub const LedgerCorruption = error{LedgerCorruption};

pub const Block = struct {
    index: usize,
    data: std.json.Value,
    previous_hash: [64]u8,
    nonce: u64,
    hash: [64]u8,
};

/// sha256(json.dumps([index, data, previous_hash, nonce], sort_keys=True))
fn digest(index: usize, data: std.json.Value, previous_hash: []const u8, nonce: u64) [64]u8 {
    var buffer: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    const options: pyjson.Options = .{ .sort_keys = true };
    w.print("[{d}, ", .{index}) catch unreachable;
    pyjson.dump(&w, data, options) catch unreachable;
    w.writeAll(", ") catch unreachable;
    pyjson.dump(&w, .{ .string = previous_hash }, options) catch unreachable;
    w.print(", {d}]", .{nonce}) catch unreachable;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(w.buffered(), &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}

pub const GlyphChain = struct {
    allocator: std.mem.Allocator,
    difficulty: usize,
    bus: *EventBus,
    blocks: std.ArrayList(Block),

    pub fn init(self: *GlyphChain, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{
            .allocator = deps.allocator,
            .difficulty = @intCast(try config.getInt("ledger", "difficulty")),
            .bus = try deps.get(EventBus, "event_bus"),
            .blocks = .empty,
        };
    }

    pub fn append(self: *GlyphChain, data: std.json.Value) !Block {
        const index = self.blocks.items.len;
        const previous: [64]u8 = if (index == 0) genesis_hash.* else self.blocks.items[index - 1].hash;
        var nonce: u64 = 0;
        var hash = digest(index, data, &previous, nonce);
        while (!hasLeadingZeros(&hash, self.difficulty)) {
            nonce += 1;
            hash = digest(index, data, &previous, nonce);
        }
        const block: Block = .{ .index = index, .data = data, .previous_hash = previous, .nonce = nonce, .hash = hash };
        try self.blocks.append(self.allocator, block);
        _ = try self.bus.publish("ledger.block.mined", .{ .record = &.{
            .{ .key = "index", .value = .{ .int = @intCast(index) } },
            .{ .key = "nonce", .value = .{ .int = @intCast(nonce) } },
            .{ .key = "hash", .value = .{ .text = hash[0..12] } },
        } });
        return block;
    }

    pub fn verify(self: *const GlyphChain) !void {
        var previous: [64]u8 = genesis_hash.*;
        for (self.blocks.items) |*block| {
            if (!std.mem.eql(u8, &block.previous_hash, &previous)) {
                return failure.raise(error.LedgerCorruption, "block {d} is not linked to its parent", .{block.index});
            }
            const expected = digest(block.index, block.data, &block.previous_hash, block.nonce);
            if (!std.mem.eql(u8, &expected, &block.hash)) {
                return failure.raise(error.LedgerCorruption, "block {d} has been tampered with", .{block.index});
            }
            previous = block.hash;
        }
    }
};

fn hasLeadingZeros(hash: []const u8, count: usize) bool {
    for (hash[0..count]) |c| if (c != '0') return false;
    return true;
}
