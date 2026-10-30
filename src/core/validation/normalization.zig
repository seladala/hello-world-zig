// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Letter case is decided through structured multi-round negotiation.

const std = @import("std");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const logging = @import("../logging.zig");
const repr = @import("../repr.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;

const log = logging.Logger.init("core.validation.normalization");

pub const NegotiationDeadlock = error{NegotiationDeadlock};

const Transform = *const fn ([]u8) void;

fn toUpper(text: []u8) void {
    for (text) |*c| c.* = std.ascii.toUpper(c.*);
}

fn toLower(text: []u8) void {
    for (text) |*c| c.* = std.ascii.toLower(c.*);
}

/// `str.title`: upper-case after every non-letter, lower-case elsewhere.
fn toTitle(text: []u8) void {
    var previous_cased = false;
    for (text) |*c| {
        c.* = if (previous_cased) std.ascii.toLower(c.*) else std.ascii.toUpper(c.*);
        previous_cased = std.ascii.isAlphabetic(c.*);
    }
}

/// `str.capitalize`
fn toSentence(text: []u8) void {
    toLower(text);
    if (text.len != 0) text[0] = std.ascii.toUpper(text[0]);
}

const proposals = [_]struct { name: []const u8, transform: Transform }{
    .{ .name = "UPPER", .transform = toUpper },
    .{ .name = "Title", .transform = toTitle },
    .{ .name = "Sentence", .transform = toSentence },
    .{ .name = "lower", .transform = toLower },
};

pub const LetterCaseNegotiator = struct {
    allocator: std.mem.Allocator,
    mandate: []const u8,
    separator_policy: []const u8,

    pub fn init(self: *LetterCaseNegotiator, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{
            .allocator = deps.allocator,
            .mandate = try config.get("greeting", "case"),
            .separator_policy = try config.get("greeting", "separator_policy"),
        };
    }

    pub fn negotiate(self: *const LetterCaseNegotiator, text: []const u8) ![]const u8 {
        for (proposals, 1..) |proposal, round_no| {
            const draft = try self.allocator.dupe(u8, text);
            proposal.transform(draft);
            const accepted = std.ascii.eqlIgnoreCase(proposal.name, self.mandate);
            log.info("case negotiation round {d}: {s:<8} -> {f} {s}", .{
                round_no, proposal.name, repr.str(draft), if (accepted) "ACCEPTED" else "rejected, escalating",
            });
            if (accepted) return self.enforceSeparators(draft);
        }
        return failure.raise(error.NegotiationDeadlock, "no proposal satisfies mandate {f}", .{repr.str(self.mandate)});
    }

    /// `" ".join(text.split())`
    fn enforceSeparators(self: *const LetterCaseNegotiator, text: []const u8) ![]const u8 {
        if (!std.mem.eql(u8, self.separator_policy, "single-space")) return text;
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeAny(u8, text, " \t\r\n\x0b\x0c");
        while (it.next()) |word| try words.append(self.allocator, word);
        return std.mem.join(self.allocator, " ", words.items);
    }
};
