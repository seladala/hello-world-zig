// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! File integrity verification.
//!
//! Every source file, firmware image, configuration file and main.zig is pinned
//! by SHA-256 in checksums.sha256. Modified, missing or unexpected files abort
//! startup before a single module is resolved.

const std = @import("std");
const failure = @import("../failure.zig");
const logging = @import("../logging.zig");
const paths = @import("../paths.zig");

const log = logging.Logger.init("core.security.integrity");

pub const checksums_path = "src/core/security/checksums.sha256";

pub const Entry = struct {
    name: []const u8,
    digest: [64]u8,
};

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Project-relative paths of every protected file, entry point first.
pub fn protectedFiles(allocator: std.mem.Allocator, root: []const u8) ![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    try files.append(allocator, paths.entry_point);

    const package = try std.fs.path.join(allocator, &.{ root, paths.package_dir });
    var dir = try std.fs.openDirAbsolute(package, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const relative = try std.fs.path.join(allocator, &.{ paths.package_dir, entry.path });
        std.mem.replaceScalar(u8, relative, std.fs.path.sep, '/');
        if (std.mem.eql(u8, relative, checksums_path)) continue;
        try found.append(allocator, relative);
    }
    std.mem.sort([]const u8, found.items, {}, lessThan);
    try files.appendSlice(allocator, found.items);
    return files.items;
}

pub fn sha256Of(allocator: std.mem.Allocator, path: []const u8) ![64]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const chunk = try allocator.alloc(u8, 1 << 16);
    defer allocator.free(chunk);
    while (true) {
        const n = try file.read(chunk);
        if (n == 0) break;
        hasher.update(chunk[0..n]);
    }
    return std.fmt.bytesToHex(hasher.finalResult(), .lower);
}

pub fn computeManifest(allocator: std.mem.Allocator, root: []const u8) ![]Entry {
    const files = try protectedFiles(allocator, root);
    const entries = try allocator.alloc(Entry, files.len);
    for (files, entries) |name, *entry| {
        const absolute = try std.fs.path.join(allocator, &.{ root, name });
        defer allocator.free(absolute);
        entry.* = .{ .name = name, .digest = try sha256Of(allocator, absolute) };
    }
    return entries;
}

/// The checksums file format: `<sha256>  <path>` per line, `#` for comments.
pub fn writeManifest(w: *std.Io.Writer, entries: []const Entry) !void {
    try w.writeAll("# НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.\n");
    try w.writeAll("# Каждая строка набрана лично на клавиатуре. Честно 🤝✅\n");
    for (entries) |entry| try w.print("{s}  {s}\n", .{ entry.digest, entry.name });
}

pub fn loadManifest(allocator: std.mem.Allocator, path: []const u8) !std.StringArrayHashMap([]const u8) {
    const text = std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return failure.raise(error.IntegrityViolation, "integrity manifest missing: {s}", .{std.fs.path.basename(path)}),
        else => return err,
    };
    var entries = std.StringArrayHashMap([]const u8).init(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len == 0 or line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const digest = fields.next().?;
        const name = std.mem.trim(u8, fields.rest(), " \t\r");
        try entries.put(name, digest);
    }
    return entries;
}

pub fn verify(allocator: std.mem.Allocator) !usize {
    const root = paths.projectRoot();
    const expected = try loadManifest(allocator, try paths.resolve(allocator, checksums_path));
    const actual = try computeManifest(allocator, root);

    var modified: std.ArrayList([]const u8) = .empty;
    var missing: std.ArrayList([]const u8) = .empty;
    var unexpected: std.ArrayList([]const u8) = .empty;
    var seen = std.StringHashMap(void).init(allocator);
    for (actual) |entry| {
        try seen.put(entry.name, {});
        if (expected.get(entry.name)) |digest| {
            if (!std.mem.eql(u8, digest, &entry.digest)) try modified.append(allocator, entry.name);
        } else {
            try unexpected.append(allocator, entry.name);
        }
    }
    for (expected.keys()) |name| {
        if (!seen.contains(name)) try missing.append(allocator, name);
    }

    if (modified.items.len + missing.items.len + unexpected.items.len != 0) {
        var details: std.ArrayList(u8) = .empty;
        const groups = [_]struct { []const u8, [][]const u8 }{
            .{ "modified", modified.items },
            .{ "missing", missing.items },
            .{ "unexpected", unexpected.items },
        };
        for (groups) |group| {
            if (group[1].len == 0) continue;
            std.mem.sort([]const u8, group[1], {}, lessThan);
            if (details.items.len != 0) try details.appendSlice(allocator, "; ");
            try details.appendSlice(allocator, group[0]);
            try details.appendSlice(allocator, ": ");
            try details.appendSlice(allocator, try std.mem.join(allocator, ", ", group[1]));
        }
        return failure.raise(error.IntegrityViolation, "file integrity check failed ({s})", .{details.items});
    }
    log.info("integrity: {d} files verified against SHA-256 manifest", .{actual.len});
    return actual.len;
}
