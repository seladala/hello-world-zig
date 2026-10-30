// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! A semantic versioning implementation, because "1.2.3" is too hard to compare by eye.

const std = @import("std");
const failure = @import("../failure.zig");
const repr = @import("../repr.zig");

pub const VersionError = error{ValueError};

pub const Version = struct {
    parts: [3]u64,

    /// Strict `MAJOR.MINOR.PATCH`.
    pub fn parse(text: []const u8) VersionError!Version {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        var version: Version = .{ .parts = undefined };
        var pieces = std.mem.splitScalar(u8, trimmed, '.');
        var count: usize = 0;
        while (pieces.next()) |piece| : (count += 1) {
            if (count == 3 or !isNumber(piece)) return notAVersion(text);
            version.parts[count] = std.fmt.parseInt(u64, piece, 10) catch return notAVersion(text);
        }
        if (count != 3) return notAVersion(text);
        return version;
    }

    /// `"3.14"` -> `3.14.0`, `"2"` -> `2.0.0`.
    pub fn loose(text: []const u8) VersionError!Version {
        var parts = [3][]const u8{ "0", "0", "0" };
        var pieces = std.mem.splitScalar(u8, text, '.');
        for (&parts) |*part| part.* = pieces.next() orelse break;
        var buffer: [96]u8 = undefined;
        const joined = std.fmt.bufPrint(&buffer, "{s}.{s}.{s}", .{ parts[0], parts[1], parts[2] }) catch
            return notAVersion(text);
        return parse(joined);
    }

    pub fn order(a: Version, b: Version) std.math.Order {
        for (a.parts, b.parts) |x, y| {
            const result = std.math.order(x, y);
            if (result != .eq) return result;
        }
        return .eq;
    }

    pub fn format(self: Version, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{d}.{d}.{d}", .{ self.parts[0], self.parts[1], self.parts[2] });
    }

    fn notAVersion(text: []const u8) VersionError {
        return failure.raise(error.ValueError, "not a semantic version: {f}", .{repr.str(text)});
    }
};

fn isNumber(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

const Operator = enum { ge, le, eq, ne, gt, lt, caret, tilde };

const operator_tokens = [_]struct { []const u8, Operator }{
    .{ ">=", .ge }, .{ "<=", .le }, .{ "==", .eq },   .{ "!=", .ne },
    .{ ">", .gt },  .{ "<", .lt },  .{ "^", .caret }, .{ "~", .tilde },
};

/// Check a version against a comma-separated constraint list, e.g. '>=1.2,<2'.
pub fn satisfies(version: Version, spec: []const u8) VersionError!bool {
    var clauses = std.mem.splitScalar(u8, spec, ',');
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " \t");
        if (clause.len == 0) continue;
        var op: Operator = .eq;
        var rest = clause;
        for (operator_tokens) |token| {
            if (std.mem.startsWith(u8, clause, token[0])) {
                op = token[1];
                rest = std.mem.trimLeft(u8, clause[token[0].len..], " \t");
                break;
            }
        }
        if (!isLooseNumber(rest)) {
            return failure.raise(error.ValueError, "bad constraint: {f}", .{repr.str(clause)});
        }
        const target = try Version.loose(rest);
        const cmp = version.order(target);
        const ok = switch (op) {
            .ge => cmp != .lt,
            .le => cmp != .gt,
            .eq => cmp == .eq,
            .ne => cmp != .eq,
            .gt => cmp == .gt,
            .lt => cmp == .lt,
            .caret => cmp != .lt and version.parts[0] == target.parts[0],
            .tilde => cmp != .lt and version.parts[0] == target.parts[0] and version.parts[1] == target.parts[1],
        };
        if (!ok) return false;
    }
    return true;
}

/// `\d+(\.\d+){0,2}`
fn isLooseNumber(text: []const u8) bool {
    var pieces = std.mem.splitScalar(u8, text, '.');
    var count: usize = 0;
    while (pieces.next()) |piece| : (count += 1) {
        if (count == 3 or !isNumber(piece)) return false;
    }
    return count >= 1;
}
