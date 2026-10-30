// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! `argparse`, the parts we need: flags, counters, --version, --help, unique
//! prefix abbreviations and the exact same complaints about bad arguments.

const std = @import("std");

pub const Action = enum { store_true, count, version, help };

pub const Argument = struct {
    flags: []const []const u8,
    action: Action,
    help: []const u8,
    dest: []const u8 = "",
};

pub const Parser = struct {
    prog: []const u8,
    description: []const u8,
    arguments: []const Argument,
    version: []const u8 = "",

    pub fn formatUsage(self: Parser, w: *std.Io.Writer) !void {
        try w.print("usage: {s}", .{self.prog});
        for (self.arguments) |argument| try w.print(" [{s}]", .{argument.flags[0]});
        try w.writeByte('\n');
    }

    pub fn formatHelp(self: Parser, w: *std.Io.Writer) !void {
        try self.formatUsage(w);
        try w.print("\n{s}\n\noptions:\n", .{self.description});
        var width: usize = 0;
        for (self.arguments) |argument| width = @max(width, invocationLength(argument));
        for (self.arguments) |argument| {
            try w.writeAll("  ");
            for (argument.flags, 0..) |flag, i| {
                if (i != 0) try w.writeAll(", ");
                try w.writeAll(flag);
            }
            try w.splatByteAll(' ', width - invocationLength(argument) + 2);
            try w.print("{s}\n", .{argument.help});
        }
    }

    fn invocationLength(argument: Argument) usize {
        var length: usize = 0;
        for (argument.flags, 0..) |flag, i| length += flag.len + @as(usize, if (i != 0) 2 else 0);
        return length;
    }

    pub const Outcome = union(enum) {
        /// Parsed successfully; one counter per argument, in declaration order.
        namespace: Namespace,
        /// --help / --version already printed; exit with this status.
        exit: u8,
    };

    pub fn parse(self: Parser, allocator: std.mem.Allocator, argv: []const []const u8) !Outcome {
        const counts = try allocator.alloc(u32, self.arguments.len);
        @memset(counts, 0);
        var unrecognized: std.ArrayList([]const u8) = .empty;

        for (argv) |token| {
            if (token.len > 1 and token[0] == '-' and token[1] != '-') {
                // bundled short flags: -vv
                for (token[1..]) |letter| {
                    const index = self.findShort(letter) orelse {
                        try unrecognized.append(allocator, token);
                        break;
                    };
                    if (try self.apply(index, counts)) |status| return .{ .exit = status };
                }
                continue;
            }
            if (std.mem.startsWith(u8, token, "--") and token.len > 2) {
                const index = switch (try self.findLong(allocator, token)) {
                    .found => |index| index,
                    .missing => {
                        try unrecognized.append(allocator, token);
                        continue;
                    },
                    .ambiguous => |status| return .{ .exit = status },
                };
                if (try self.apply(index, counts)) |status| return .{ .exit = status };
                continue;
            }
            try unrecognized.append(allocator, token);
        }

        if (unrecognized.items.len != 0) {
            const joined = try std.mem.join(allocator, " ", unrecognized.items);
            return .{ .exit = self.fail("unrecognized arguments: {s}", .{joined}) };
        }
        return .{ .namespace = .{ .parser = self, .counts = counts } };
    }

    fn findShort(self: Parser, letter: u8) ?usize {
        for (self.arguments, 0..) |argument, index| {
            for (argument.flags) |flag| {
                if (flag.len == 2 and flag[0] == '-' and flag[1] == letter) return index;
            }
        }
        return null;
    }

    const LongMatch = union(enum) { found: usize, missing, ambiguous: u8 };

    fn findLong(self: Parser, allocator: std.mem.Allocator, token: []const u8) !LongMatch {
        var candidates: std.ArrayList([]const u8) = .empty;
        var match: ?usize = null;
        for (self.arguments, 0..) |argument, index| {
            for (argument.flags) |flag| {
                if (!std.mem.startsWith(u8, flag, "--")) continue;
                if (std.mem.eql(u8, flag, token)) return .{ .found = index };
                if (std.mem.startsWith(u8, flag, token)) {
                    try candidates.append(allocator, flag);
                    match = index;
                }
            }
        }
        if (candidates.items.len == 1) return .{ .found = match.? };
        if (candidates.items.len == 0) return .missing;
        const options = try std.mem.join(allocator, ", ", candidates.items);
        return .{ .ambiguous = self.fail("ambiguous option: {s} could match {s}", .{ token, options }) };
    }

    /// Returns an exit status when the action ends the program.
    fn apply(self: Parser, index: usize, counts: []u32) !?u8 {
        switch (self.arguments[index].action) {
            .store_true, .count => counts[index] += 1,
            .version => {
                try printTo(std.fs.File.stdout(), "{s}\n", .{self.version});
                return 0;
            },
            .help => {
                var buffer: [1024]u8 = undefined;
                var writer = std.fs.File.stdout().writerStreaming(&buffer);
                try self.formatHelp(&writer.interface);
                try writer.interface.flush();
                return 0;
            },
        }
        return null;
    }

    fn fail(self: Parser, comptime fmt: []const u8, args: anytype) u8 {
        var buffer: [1024]u8 = undefined;
        var writer = std.fs.File.stderr().writerStreaming(&buffer);
        const w = &writer.interface;
        self.formatUsage(w) catch {};
        w.print("{s}: error: " ++ fmt ++ "\n", .{self.prog} ++ args) catch {};
        w.flush() catch {};
        return 2;
    }
};

pub const Namespace = struct {
    parser: Parser,
    counts: []const u32,

    pub fn get(self: Namespace, dest: []const u8) u32 {
        for (self.parser.arguments, self.counts) |argument, count| {
            if (std.mem.eql(u8, argument.dest, dest)) return count;
        }
        unreachable;
    }
};

fn printTo(file: std.fs.File, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [256]u8 = undefined;
    var writer = file.writerStreaming(&buffer);
    try writer.interface.print(fmt, args);
    try writer.interface.flush();
}
