// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! UHX-16 Instruction Set Architecture.
//!
//! The Unified Hardware eXecution unit is a 16-bit, 8-register, little-endian
//! CPU designed by a committee whose only requirement was "it must be able to
//! say hello world, eventually".
//!
//! Operand kinds:
//!     'r' - register index, 1 byte (R0..R7)
//!     'i' - 16-bit immediate / address, 2 bytes little-endian
//!     'p' - 8-bit I/O port number, 1 byte

const std = @import("std");

pub const Op = enum(u8) {
    nop = 0x00,
    hlt = 0x01,

    movi = 0x10,
    mov = 0x11,
    ldb = 0x12,
    stb = 0x13,

    add = 0x20,
    sub = 0x21,
    @"and" = 0x22,
    @"or" = 0x23,
    xor = 0x24,
    addi = 0x25,
    cmp = 0x26,
    cmpi = 0x27,
    shl = 0x28,
    shr = 0x29,
    inc = 0x2A,
    dec = 0x2B,

    jmp = 0x30,
    jz = 0x31,
    jnz = 0x32,
    jc = 0x33,
    jnc = 0x34,

    call = 0x38,
    ret = 0x39,
    push = 0x3A,
    pop = 0x3B,

    out = 0x40,
    in = 0x41,
};

pub const InstructionSpec = struct {
    op: Op,
    operands: []const u8,
    description: []const u8,

    pub fn mnemonic(self: InstructionSpec) []const u8 {
        return mnemonics[@intFromEnum(self.op)];
    }

    pub fn size(self: InstructionSpec) usize {
        var total: usize = 1;
        for (self.operands) |kind| total += operandSize(kind);
        return total;
    }
};

pub fn operandSize(kind: u8) usize {
    return switch (kind) {
        'r', 'p' => 1,
        'i' => 2,
        else => unreachable,
    };
}

pub const register_count = 8;

pub const specs = [_]InstructionSpec{
    .{ .op = .nop, .operands = "", .description = "do nothing, but professionally" },
    .{ .op = .hlt, .operands = "", .description = "stop the world" },
    .{ .op = .movi, .operands = "ri", .description = "rd <- imm16" },
    .{ .op = .mov, .operands = "rr", .description = "rd <- rs" },
    .{ .op = .ldb, .operands = "rr", .description = "rd <- mem8[rs]" },
    .{ .op = .stb, .operands = "rr", .description = "mem8[rd] <- rs & 0xFF" },
    .{ .op = .add, .operands = "rr", .description = "rd <- rd + rs" },
    .{ .op = .sub, .operands = "rr", .description = "rd <- rd - rs" },
    .{ .op = .@"and", .operands = "rr", .description = "rd <- rd & rs" },
    .{ .op = .@"or", .operands = "rr", .description = "rd <- rd | rs" },
    .{ .op = .xor, .operands = "rr", .description = "rd <- rd ^ rs" },
    .{ .op = .addi, .operands = "ri", .description = "rd <- rd + imm16" },
    .{ .op = .cmp, .operands = "rr", .description = "flags <- rd - rs" },
    .{ .op = .cmpi, .operands = "ri", .description = "flags <- rd - imm16" },
    .{ .op = .shl, .operands = "r", .description = "rd <- rd << 1" },
    .{ .op = .shr, .operands = "r", .description = "rd <- rd >> 1" },
    .{ .op = .inc, .operands = "r", .description = "rd <- rd + 1" },
    .{ .op = .dec, .operands = "r", .description = "rd <- rd - 1" },
    .{ .op = .jmp, .operands = "i", .description = "pc <- addr" },
    .{ .op = .jz, .operands = "i", .description = "if Z: pc <- addr" },
    .{ .op = .jnz, .operands = "i", .description = "if !Z: pc <- addr" },
    .{ .op = .jc, .operands = "i", .description = "if C: pc <- addr" },
    .{ .op = .jnc, .operands = "i", .description = "if !C: pc <- addr" },
    .{ .op = .call, .operands = "i", .description = "push pc; pc <- addr" },
    .{ .op = .ret, .operands = "", .description = "pc <- pop" },
    .{ .op = .push, .operands = "r", .description = "push rs" },
    .{ .op = .pop, .operands = "r", .description = "rd <- pop" },
    .{ .op = .out, .operands = "pr", .description = "port <- rs" },
    .{ .op = .in, .operands = "rp", .description = "rd <- port" },
};

/// Upper-case mnemonic for every opcode byte ("" for illegal ones).
const mnemonics: [256][]const u8 = blk: {
    var table = [_][]const u8{""} ** 256;
    for (std.enums.values(Op)) |op| {
        const name = @tagName(op);
        var upper: [name.len]u8 = undefined;
        _ = std.ascii.upperString(&upper, name);
        const frozen = upper;
        table[@intFromEnum(op)] = &frozen;
    }
    break :blk table;
};

/// Look up the spec of a raw opcode byte.
pub fn decode(opcode: u8) ?InstructionSpec {
    inline for (specs) |spec| {
        if (@intFromEnum(spec.op) == opcode) return spec;
    }
    return null;
}

/// Look up the spec of an (upper-case) mnemonic.
pub fn byMnemonic(name: []const u8) ?InstructionSpec {
    for (specs) |spec| {
        if (std.mem.eql(u8, spec.mnemonic(), name)) return spec;
    }
    return null;
}
