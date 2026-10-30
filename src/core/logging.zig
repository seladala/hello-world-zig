// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Python's `logging` module, reduced to the one format string we ever used:
//!
//!     [%(levelname)-5s] %(name)s: %(message)s

const std = @import("std");

pub const Level = enum(u8) {
    debug = 10,
    info = 20,
    warning = 30,
    @"error" = 40,

    fn label(self: Level) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warning => "WARNING",
            .@"error" => "ERROR",
        };
    }
};

var threshold: Level = .warning;

pub fn basicConfig(level: Level) void {
    threshold = level;
}

pub fn isEnabledFor(level: Level) bool {
    return @intFromEnum(level) >= @intFromEnum(threshold);
}

pub const Logger = struct {
    name: []const u8,

    pub fn init(comptime name: []const u8) Logger {
        return .{ .name = name };
    }

    pub fn debug(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.emit(.debug, fmt, args);
    }

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.emit(.info, fmt, args);
    }

    pub fn warning(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.emit(.warning, fmt, args);
    }

    fn emit(self: Logger, level: Level, comptime fmt: []const u8, args: anytype) void {
        if (!isEnabledFor(level)) return;
        var buffer: [1024]u8 = undefined;
        var writer = std.fs.File.stderr().writerStreaming(&buffer);
        const out = &writer.interface;
        out.print("[{s:<5}] {s}: ", .{ level.label(), self.name }) catch return;
        out.print(fmt ++ "\n", args) catch return;
        out.flush() catch return;
    }
};
