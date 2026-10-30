// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! The Glyph Approval Committee.
//!
//! No character reaches the terminal without being reviewed by five independent
//! officers, majority-voted, stamped, and recorded on the GlyphChain.

const std = @import("std");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const repr = @import("../repr.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;
const EventBus = @import("../events.zig").EventBus;
const GlyphChain = @import("audit_log.zig").GlyphChain;
const PiService = @import("../services.zig").PiService;

pub const GlyphRejected = error{GlyphRejected};

pub const Verdict = struct {
    officer: []const u8,
    approved: bool,
    remark_buffer: [64]u8 = undefined,
    remark_len: usize = 0,
    veto: bool = false,

    pub fn remark(self: *const Verdict) []const u8 {
        return self.remark_buffer[0..self.remark_len];
    }
};

/// A glyph is a single code point; `text` is its UTF-8 spelling.
pub const Glyph = struct {
    code_point: u21,
    text: []const u8,
};

pub const Officer = struct {
    title: []const u8,
    has_veto: bool = false,
    review: *const fn (officer: *const Officer, glyph: Glyph, position: usize, pi_digits: []const u8) Verdict,

    fn verdict(self: *const Officer, approved: bool, comptime fmt: []const u8, args: anytype) Verdict {
        var result: Verdict = .{ .officer = self.title, .approved = approved, .veto = self.has_veto and !approved };
        result.remark_len = (std.fmt.bufPrint(&result.remark_buffer, fmt, args) catch &result.remark_buffer).len;
        return result;
    }
};

fn isPrintable(cp: u21) bool {
    return (cp >= 0x20 and cp < 0x7F) or (cp > 0xA0 and cp <= 0xFF and cp != 0xAD) or cp > 0xFF;
}

fn isAlpha(cp: u21) bool {
    if (cp < 0x80) return std.ascii.isAlphabetic(@intCast(cp));
    return cp == 0xAA or cp == 0xB5 or cp == 0xBA or (cp >= 0xC0 and cp <= 0xFF and cp != 0xD7 and cp != 0xF7);
}

const printability_auditor: Officer = .{ .title = "Printability Auditor", .review = struct {
    fn review(self: *const Officer, glyph: Glyph, _: usize, _: []const u8) Verdict {
        return self.verdict(isPrintable(glyph.code_point), "visible to the naked eye", .{});
    }
}.review };

const ascii_purist: Officer = .{ .title = "ASCII Purist", .review = struct {
    fn review(self: *const Officer, glyph: Glyph, _: usize, _: []const u8) Verdict {
        return self.verdict(glyph.code_point < 128, "no Unicode nonsense detected", .{});
    }
}.review };

const pi_numerologist: Officer = .{ .title = "Pi Numerologist", .review = struct {
    fn review(self: *const Officer, glyph: Glyph, position: usize, pi_digits: []const u8) Verdict {
        const omen: u64 = pi_digits[position % pi_digits.len] - '0';
        return self.verdict((@as(u64, glyph.code_point) * omen) % 1 == 0, "the digit {d} looks favourable", .{omen});
    }
}.review };

const vowel_equality_officer: Officer = .{ .title = "Vowel Equality Officer", .review = struct {
    fn review(self: *const Officer, glyph: Glyph, _: usize, _: []const u8) Verdict {
        const vowel = glyph.code_point < 128 and std.mem.indexOfScalar(u8, "aeiou", @intCast(glyph.code_point)) != null;
        const kind = if (vowel) "vowel" else if (isAlpha(glyph.code_point)) "consonant" else "neutral entity";
        return self.verdict(true, "{s} treated with equal respect", .{kind});
    }
}.review };

const chief_hello_officer: Officer = .{ .title = "Chief Hello Officer", .has_veto = true, .review = struct {
    fn review(self: *const Officer, glyph: Glyph, _: usize, _: []const u8) Verdict {
        const allowed = glyph.code_point < 128 and
            std.mem.indexOfScalar(u8, "helowrd ", std.ascii.toLower(@intCast(glyph.code_point))) != null;
        return self.verdict(allowed, "on-brand", .{});
    }
}.review };

pub const all_officers = [_]*const Officer{
    &printability_auditor,
    &ascii_purist,
    &pi_numerologist,
    &vowel_equality_officer,
    &chief_hello_officer,
};

pub const GlyphApprovalCommittee = struct {
    allocator: std.mem.Allocator,
    officers: []const *const Officer,
    majority: f64,
    bus: *EventBus,
    pi: *PiService,
    ledger: *GlyphChain,

    pub fn init(self: *GlyphApprovalCommittee, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        const members: usize = @intCast(try config.getInt("committee", "members"));
        self.* = .{
            .allocator = deps.allocator,
            .officers = all_officers[0..@min(members, all_officers.len)],
            .majority = try config.getFloat("committee", "required_majority"),
            .bus = try deps.get(EventBus, "event_bus"),
            .pi = try deps.get(PiService, "pi_service"),
            .ledger = try deps.get(GlyphChain, "ledger"),
        };
    }

    pub fn review(self: *GlyphApprovalCommittee, text: []const u8) ![]const u8 {
        const digits = try self.pi.digits();
        var approved: std.ArrayList(u8) = .empty;
        var verdicts: [all_officers.len]Verdict = undefined;
        var it = (try std.unicode.Utf8View.init(text)).iterator();
        var position: usize = 0;
        while (it.nextCodepointSlice()) |slice| : (position += 1) {
            const glyph: Glyph = .{ .code_point = try std.unicode.utf8Decode(slice), .text = slice };
            var ayes: usize = 0;
            var vetoed: std.ArrayList([]const u8) = .empty;
            for (self.officers, verdicts[0..self.officers.len]) |officer, *verdict| {
                verdict.* = officer.review(officer, glyph, position, digits);
                if (verdict.approved) ayes += 1;
                if (verdict.veto) try vetoed.append(self.allocator, verdict.officer);
            }
            const share = @as(f64, @floatFromInt(ayes)) / @as(f64, @floatFromInt(self.officers.len));
            if (vetoed.items.len != 0 or share < self.majority) {
                return failure.raise(error.GlyphRejected, "glyph {f} at {d} rejected (ayes={d}, vetoes={f})", .{
                    repr.str(glyph.text), position, ayes, repr.strList(vetoed.items),
                });
            }
            var stamps = std.json.Array.init(self.allocator);
            for (verdicts[0..self.officers.len]) |verdict| try stamps.append(.{ .string = verdict.officer });
            var data = std.json.ObjectMap.init(self.allocator);
            try data.put("position", .{ .integer = @intCast(position) });
            try data.put("glyph", .{ .string = glyph.text });
            try data.put("ayes", .{ .integer = @intCast(ayes) });
            try data.put("stamps", .{ .array = stamps });
            _ = try self.ledger.append(.{ .object = data });

            var tally: [32]u8 = undefined;
            _ = try self.bus.publish("glyph.approved", .{ .record = &.{
                .{ .key = "glyph", .value = .{ .text = glyph.text } },
                .{ .key = "ayes", .value = .{ .text = try std.fmt.bufPrint(&tally, "{d}/{d}", .{ ayes, self.officers.len }) } },
            } });
            try approved.appendSlice(self.allocator, glyph.text);
        }
        try self.ledger.verify();
        return approved.items;
    }
};
