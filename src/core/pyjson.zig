// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! `json.dumps`, byte-for-byte compatible with CPython (ensure_ascii=True), so
//! that signatures and block hashes computed by the Python edition still verify.

const std = @import("std");

pub const Options = struct {
    sort_keys: bool = false,
    item_separator: []const u8 = ", ",
    key_separator: []const u8 = ": ",
};

/// `separators=(",", ":"), sort_keys=True`
pub const canonical: Options = .{ .sort_keys = true, .item_separator = ",", .key_separator = ":" };

pub fn dump(w: *std.Io.Writer, value: std.json.Value, options: Options) std.Io.Writer.Error!void {
    switch (value) {
        .null => try w.writeAll("null"),
        .bool => |flag| try w.writeAll(if (flag) "true" else "false"),
        .integer => |number| try w.print("{d}", .{number}),
        .float => |number| try w.print("{d}", .{number}),
        .number_string => |digits| try w.writeAll(digits),
        .string => |text| try dumpString(w, text),
        .array => |items| {
            try w.writeByte('[');
            for (items.items, 0..) |item, i| {
                if (i != 0) try w.writeAll(options.item_separator);
                try dump(w, item, options);
            }
            try w.writeByte(']');
        },
        .object => |object| {
            var keys_buffer: [64][]const u8 = undefined;
            const keys = keys_buffer[0..object.count()];
            @memcpy(keys, object.keys());
            if (options.sort_keys) {
                std.mem.sort([]const u8, keys, {}, struct {
                    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                        return std.mem.lessThan(u8, a, b);
                    }
                }.lessThan);
            }
            try w.writeByte('{');
            for (keys, 0..) |key, i| {
                if (i != 0) try w.writeAll(options.item_separator);
                try dumpString(w, key);
                try w.writeAll(options.key_separator);
                try dump(w, object.get(key).?, options);
            }
            try w.writeByte('}');
        },
    }
}

fn dumpString(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    var it = std.unicode.Utf8View.initUnchecked(text).iterator();
    while (it.nextCodepoint()) |cp| {
        switch (cp) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x08 => try w.writeAll("\\b"),
            0x0C => try w.writeAll("\\f"),
            ' '...'!', '#'...'[', ']'...'~' => try w.writeByte(@intCast(cp)),
            else => if (cp > 0xFFFF) {
                const v = cp - 0x10000;
                try w.print("\\u{x:0>4}\\u{x:0>4}", .{ 0xD800 | (v >> 10), 0xDC00 | (v & 0x3FF) });
            } else {
                try w.print("\\u{x:0>4}", .{cp});
            },
        }
    }
    try w.writeByte('"');
}

pub fn dumpsAlloc(allocator: std.mem.Allocator, value: std.json.Value, options: Options) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try dump(&out.writer, value, options);
    return out.toOwnedSlice();
}
