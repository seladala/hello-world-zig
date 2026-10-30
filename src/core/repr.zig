// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Python's `repr()`, for log lines and error messages that must read exactly
//! the way they did before the rewrite.

const std = @import("std");

/// `{f}`-formattable wrapper: `repr.str("hi")` prints `'hi'`.
pub fn str(text: []const u8) Str {
    return .{ .text = text };
}

pub const Str = struct {
    text: []const u8,

    pub fn format(self: Str, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeStr(w, self.text);
    }
};

pub fn writeStr(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    const has_single = std.mem.indexOfScalar(u8, text, '\'') != null;
    const has_double = std.mem.indexOfScalar(u8, text, '"') != null;
    const quote: u8 = if (has_single and !has_double) '"' else '\'';
    try w.writeByte(quote);
    var view = std.unicode.Utf8View.init(text) catch {
        for (text) |byte| try w.print("\\x{x:0>2}", .{byte});
        return w.writeByte(quote);
    };
    var it = view.iterator();
    while (it.nextCodepointSlice()) |slice| {
        const cp = std.unicode.utf8Decode(slice) catch unreachable;
        switch (cp) {
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (cp == quote) {
                    try w.writeByte('\\');
                    try w.writeByte(quote);
                } else if (cp < 0x20 or cp == 0x7F or (cp >= 0x80 and cp <= 0xA0) or cp == 0xAD) {
                    try w.print("\\x{x:0>2}", .{cp});
                } else {
                    try w.writeAll(slice);
                }
            },
        }
    }
    try w.writeByte(quote);
}

/// `[1, 2, 3]`
pub fn list(items: []const i64) List {
    return .{ .items = items };
}

pub const List = struct {
    items: []const i64,

    pub fn format(self: List, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeByte('[');
        for (self.items, 0..) |item, i| {
            if (i != 0) try w.writeAll(", ");
            try w.print("{d}", .{item});
        }
        try w.writeByte(']');
    }
};

/// `['a', 'b']`
pub fn strList(items: []const []const u8) StrList {
    return .{ .items = items };
}

pub const StrList = struct {
    items: []const []const u8,

    pub fn format(self: StrList, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeByte('[');
        for (self.items, 0..) |item, i| {
            if (i != 0) try w.writeAll(", ");
            try writeStr(w, item);
        }
        try w.writeByte(']');
    }
};
