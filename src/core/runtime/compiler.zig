// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Two-pass assembler for UHX-16 assembly.
//!
//! Syntax:
//!     label:                  define a label
//!     MNEMONIC op, op         instruction (registers R0..R7, [Rn] allowed for LDB/STB)
//!     .org  ADDR              move the location counter forward
//!     .equ  NAME, VALUE       define a constant
//!     .byte v, v, ...         emit bytes
//!     .word v, v, ...         emit 16-bit little-endian words
//!     ; comment
//!
//! Values may be decimal, 0x-hex, 0b-binary, or a symbol name.
//! String literals are deliberately unsupported: typing "hello world" would be cheating.

const std = @import("std");
const failure = @import("../failure.zig");
const repr = @import("../repr.zig");
const opcodes = @import("opcodes.zig");

pub const AssemblyError = error{AssemblyError};

pub const ListingEntry = struct {
    address: usize,
    line: []const u8,
};

pub const AssembledProgram = struct {
    image: []u8,
    symbols: std.StringArrayHashMap(i64),
    listing: []ListingEntry,
};

const Line = struct {
    number: usize,
    text: []const u8,
};

const whitespace = " \t\r\n\x0b\x0c";

/// `^([A-Za-z_][A-Za-z0-9_]*):` - returns the label name, if any.
fn matchLabel(line: []const u8) ?[]const u8 {
    if (line.len == 0 or !(std.ascii.isAlphabetic(line[0]) or line[0] == '_')) return null;
    var i: usize = 1;
    while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) i += 1;
    if (i < line.len and line[i] == ':') return line[0..i];
    return null;
}

fn stripLabels(line: []const u8) []const u8 {
    var rest = line;
    while (matchLabel(rest)) |name| rest = std.mem.trim(u8, rest[name.len + 1 ..], whitespace);
    return rest;
}

fn splitOperands(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
    var operands: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, whitespace);
        if (trimmed.len != 0) try operands.append(allocator, trimmed);
    }
    return operands.items;
}

/// `line.partition(" ")`
fn partition(line: []const u8) struct { head: []const u8, rest: []const u8 } {
    const space = std.mem.indexOfScalar(u8, line, ' ') orelse return .{ .head = line, .rest = "" };
    return .{ .head = line[0..space], .rest = line[space + 1 ..] };
}

/// `^\[?R([0-9])\]?$`, case-insensitive.
fn parseRegister(token: []const u8, line_no: usize) !u8 {
    var body = token;
    if (body.len != 0 and body[0] == '[') body = body[1..];
    if (body.len != 0 and body[body.len - 1] == ']') body = body[0 .. body.len - 1];
    if (body.len == 2 and (body[0] == 'R' or body[0] == 'r') and std.ascii.isDigit(body[1])) {
        const index = body[1] - '0';
        if (index < opcodes.register_count) return index;
    }
    return failure.raise(error.AssemblyError, "line {d}: expected register, got {f}", .{ line_no, repr.str(token) });
}

fn parseValue(token: []const u8, symbols: *const std.StringArrayHashMap(i64), line_no: usize, strict: bool) !i64 {
    const trimmed = std.mem.trim(u8, token, whitespace);
    if (std.fmt.parseInt(i64, trimmed, 0)) |value| return value else |_| {}
    if (symbols.get(trimmed)) |value| return value;
    if (strict) return failure.raise(error.AssemblyError, "line {d}: unknown symbol {f}", .{ line_no, repr.str(trimmed) });
    return 0;
}

fn cleanLines(allocator: std.mem.Allocator, source: []const u8) ![]Line {
    var lines: std.ArrayList(Line) = .empty;
    var it = std.mem.splitScalar(u8, source, '\n');
    var number: usize = 0;
    while (it.next()) |raw| {
        number += 1;
        const code = if (std.mem.indexOfScalar(u8, raw, ';')) |semicolon| raw[0..semicolon] else raw;
        const line = std.mem.trim(u8, code, whitespace);
        if (line.len != 0) try lines.append(allocator, .{ .number = number, .text = line });
    }
    return lines.items;
}

fn upper(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.ascii.allocUpperString(allocator, text);
}

/// New location counter for a label-free line.
fn sizeOf(allocator: std.mem.Allocator, line: []const u8, symbols: *const std.StringArrayHashMap(i64), line_no: usize, location: i64) !i64 {
    const parts = partition(line);
    const head = try upper(allocator, parts.head);
    const operands = try splitOperands(allocator, parts.rest);
    if (std.mem.eql(u8, head, ".ORG")) {
        if (operands.len == 0) return failure.raise(error.AssemblyError, "line {d}: .org needs an address", .{line_no});
        const target = try parseValue(operands[0], symbols, line_no, true);
        if (target < location) return failure.raise(error.AssemblyError, "line {d}: .org moves backwards", .{line_no});
        return target;
    }
    if (std.mem.eql(u8, head, ".EQU")) return location;
    if (std.mem.eql(u8, head, ".BYTE")) return location + @as(i64, @intCast(operands.len));
    if (std.mem.eql(u8, head, ".WORD")) return location + 2 * @as(i64, @intCast(operands.len));
    const spec = opcodes.byMnemonic(head) orelse
        return failure.raise(error.AssemblyError, "line {d}: unknown mnemonic {f}", .{ line_no, repr.str(head) });
    return location + @as(i64, @intCast(spec.size()));
}

pub fn assemble(allocator: std.mem.Allocator, source: []const u8) !AssembledProgram {
    const lines = try cleanLines(allocator, source);
    var symbols = std.StringArrayHashMap(i64).init(allocator);

    // Pass 1: assign addresses to labels and constants.
    var location: i64 = 0;
    for (lines) |entry| {
        var line = entry.text;
        while (matchLabel(line)) |name| {
            if (symbols.contains(name)) {
                return failure.raise(error.AssemblyError, "line {d}: duplicate symbol {f}", .{ entry.number, repr.str(name) });
            }
            try symbols.put(name, location);
            line = std.mem.trim(u8, line[name.len + 1 ..], whitespace);
        }
        if (line.len == 0) continue;
        const parts = partition(line);
        if (std.ascii.eqlIgnoreCase(parts.head, ".EQU")) {
            const operands = try splitOperands(allocator, parts.rest);
            if (operands.len != 2) {
                return failure.raise(error.AssemblyError, "line {d}: .equ expects NAME, VALUE", .{entry.number});
            }
            try symbols.put(operands[0], try parseValue(operands[1], &symbols, entry.number, true));
            continue;
        }
        location = try sizeOf(allocator, line, &symbols, entry.number, location);
    }

    // Pass 2: emit bytes.
    var image: std.ArrayList(u8) = .empty;
    var listing: std.ArrayList(ListingEntry) = .empty;
    for (lines) |entry| {
        const line = stripLabels(entry.text);
        if (line.len == 0) continue;
        const parts = partition(line);
        const head = try upper(allocator, parts.head);
        const operands = try splitOperands(allocator, parts.rest);
        if (std.mem.eql(u8, head, ".EQU")) continue;
        if (std.mem.eql(u8, head, ".ORG")) {
            const target: usize = @intCast(try parseValue(operands[0], &symbols, entry.number, true));
            try image.appendNTimes(allocator, 0, target - image.items.len);
            continue;
        }
        try listing.append(allocator, .{ .address = image.items.len, .line = line });
        if (std.mem.eql(u8, head, ".BYTE")) {
            for (operands) |token| {
                const value = try parseValue(token, &symbols, entry.number, true);
                if (value < 0 or value > 0xFF) {
                    return failure.raise(error.AssemblyError, "line {d}: byte out of range: {d}", .{ entry.number, value });
                }
                try image.append(allocator, @intCast(value));
            }
            continue;
        }
        if (std.mem.eql(u8, head, ".WORD")) {
            for (operands) |token| {
                const value: u16 = @truncate(@as(u64, @bitCast(try parseValue(token, &symbols, entry.number, true))));
                try image.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(u16, value)));
            }
            continue;
        }
        const spec = opcodes.byMnemonic(head).?;
        if (operands.len != spec.operands.len) {
            return failure.raise(error.AssemblyError, "line {d}: {s} expects {d} operands, got {d}", .{
                entry.number, head, spec.operands.len, operands.len,
            });
        }
        try image.append(allocator, @intFromEnum(spec.op));
        for (spec.operands, operands) |kind, token| {
            if (kind == 'r') {
                try image.append(allocator, try parseRegister(token, entry.number));
                continue;
            }
            const value: u64 = @bitCast(try parseValue(token, &symbols, entry.number, true));
            for (0..opcodes.operandSize(kind)) |i| {
                try image.append(allocator, @truncate(value >> @intCast(8 * i)));
            }
        }
    }
    return .{ .image = image.items, .symbols = symbols, .listing = listing.items };
}
