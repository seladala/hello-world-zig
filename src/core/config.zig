// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Strongly-typed-ish configuration facade over a perfectly ordinary .ini file.

const std = @import("std");
const container = @import("container.zig");
const failure = @import("failure.zig");
const paths = @import("paths.zig");

pub const default_path = "src/core/settings.ini";

pub const ConfigurationError = error{ConfigurationError};

const Section = std.StringHashMap([]const u8);

pub const EnterpriseConfiguration = struct {
    sections: std.StringHashMap(Section),

    pub fn init(self: *EnterpriseConfiguration, deps: *container.Deps) !void {
        try self.load(deps.allocator, try paths.resolve(deps.allocator, default_path));
    }

    pub fn load(self: *EnterpriseConfiguration, allocator: std.mem.Allocator, path: []const u8) !void {
        const text = std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch |err| switch (err) {
            error.FileNotFound => return failure.raise(err, "enterprise configuration missing: {s}", .{path}),
            else => return err,
        };
        self.* = .{ .sections = .init(allocator) };
        try self.parse(allocator, text);
    }

    fn parse(self: *EnterpriseConfiguration, allocator: std.mem.Allocator, text: []const u8) !void {
        var current: ?*Section = null;
        var lines = std.mem.splitScalar(u8, text, '\n');
        var line_no: usize = 0;
        while (lines.next()) |raw| {
            line_no += 1;
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == ';' or line[0] == '#') continue;
            if (line[0] == '[') {
                if (line[line.len - 1] != ']') {
                    return failure.raise(error.ConfigurationError, "line {d}: malformed section header", .{line_no});
                }
                const entry = try self.sections.getOrPut(line[1 .. line.len - 1]);
                if (entry.found_existing) {
                    return failure.raise(error.ConfigurationError, "line {d}: section '{s}' already exists", .{ line_no, entry.key_ptr.* });
                }
                entry.value_ptr.* = .init(allocator);
                current = entry.value_ptr;
                continue;
            }
            const section = current orelse
                return failure.raise(error.ConfigurationError, "line {d}: option outside of any section", .{line_no});
            const separator = std.mem.indexOfAny(u8, line, "=:") orelse
                return failure.raise(error.ConfigurationError, "line {d}: expected 'key = value'", .{line_no});
            const key = try std.ascii.allocLowerString(allocator, std.mem.trim(u8, line[0..separator], " \t"));
            try section.put(key, stripInlineComment(std.mem.trim(u8, line[separator + 1 ..], " \t")));
        }
    }

    /// An inline comment starts at a ';' that follows whitespace.
    fn stripInlineComment(value: []const u8) []const u8 {
        var i: usize = 1;
        while (i < value.len) : (i += 1) {
            if (value[i] == ';' and std.ascii.isWhitespace(value[i - 1])) {
                return std.mem.trimRight(u8, value[0..i], " \t");
            }
        }
        return value;
    }

    pub fn get(self: *const EnterpriseConfiguration, section: []const u8, key: []const u8) ![]const u8 {
        const options = self.sections.get(section) orelse
            return failure.raise(error.ConfigurationError, "No section: '{s}'", .{section});
        return options.get(key) orelse
            failure.raise(error.ConfigurationError, "No option '{s}' in section: '{s}'", .{ key, section });
    }

    pub fn getInt(self: *const EnterpriseConfiguration, section: []const u8, key: []const u8) !i64 {
        const value = try self.get(section, key);
        return std.fmt.parseInt(i64, value, 0) catch
            failure.raise(error.ConfigurationError, "invalid literal for int() with base 0: '{s}'", .{value});
    }

    pub fn getFloat(self: *const EnterpriseConfiguration, section: []const u8, key: []const u8) !f64 {
        const value = try self.get(section, key);
        return std.fmt.parseFloat(f64, value) catch
            failure.raise(error.ConfigurationError, "could not convert string to float: '{s}'", .{value});
    }

    pub fn getBool(self: *const EnterpriseConfiguration, section: []const u8, key: []const u8) !bool {
        const value = try self.get(section, key);
        const truthy = [_][]const u8{ "1", "yes", "true", "on" };
        const falsy = [_][]const u8{ "0", "no", "false", "off" };
        for (truthy) |word| if (std.ascii.eqlIgnoreCase(value, word)) return true;
        for (falsy) |word| if (std.ascii.eqlIgnoreCase(value, word)) return false;
        return failure.raise(error.ConfigurationError, "Not a boolean: {s}", .{value});
    }
};
