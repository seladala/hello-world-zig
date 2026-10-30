// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Terminal Rendering Engine: turns approved glyphs into photons (via stdout).

const std = @import("std");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const events = @import("../events.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;

pub const RenderingError = error{RuntimeError};

pub const GlyphBuffer = struct {
    allocator: std.mem.Allocator,
    glyphs: std.ArrayList([]const u8) = .empty,

    pub fn push(self: *GlyphBuffer, glyph: []const u8) !void {
        try self.glyphs.append(self.allocator, glyph);
    }

    pub fn drain(self: *GlyphBuffer) ![]const u8 {
        const text = try std.mem.concat(self.allocator, u8, self.glyphs.items);
        self.glyphs = .empty;
        return text;
    }
};

pub const TerminalRenderingEngine = struct {
    newline: bool,
    buffer: GlyphBuffer,

    pub fn init(self: *TerminalRenderingEngine, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        const bus = try deps.get(events.EventBus, "event_bus");
        self.* = .{
            .newline = try config.getBool("rendering", "trailing_newline"),
            .buffer = .{ .allocator = deps.allocator },
        };
        try bus.subscribe("glyph.render", .bind(self, onGlyph));
        try bus.subscribe("transmission.complete", .bind(self, onComplete));
    }

    fn onGlyph(self: *TerminalRenderingEngine, event: events.Event) !void {
        try self.buffer.push(event.payload.text);
    }

    fn onComplete(self: *TerminalRenderingEngine, event: events.Event) !void {
        const text = try self.buffer.drain();
        const glyphs = try std.unicode.utf8CountCodepoints(text);
        if (glyphs != event.payload.int) {
            return failure.raise(error.RuntimeError, "glyphs were lost in transit", .{});
        }
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(text);
        if (self.newline) try stdout.writeAll("\n");
    }
};
