// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! UHX-16 cycle-approximate emulator.
//!
//! 64 KiB of byte-addressable memory, eight 16-bit registers, a downward
//! growing stack and three flags (Z, N, C). I/O happens through numbered ports
//! which the host wires up to Zig callbacks.

const std = @import("std");
const failure = @import("../failure.zig");
const opcodes = @import("opcodes.zig");

const Op = opcodes.Op;

pub const MachineFault = error{MachineFault};

/// Output port: receives the value of a register.
pub const Sink = struct {
    context: *anyopaque,
    call: *const fn (*anyopaque, u16) anyerror!void,

    /// Bind a method of the form `fn (self: *T, value: u16) !void`.
    pub fn bind(context: anytype, comptime method: anytype) Sink {
        const Ptr = @TypeOf(context);
        const Thunk = struct {
            fn call(ctx: *anyopaque, value: u16) anyerror!void {
                return method(@as(Ptr, @ptrCast(@alignCast(ctx))), value);
            }
        };
        return .{ .context = context, .call = Thunk.call };
    }
};

/// Input port: produces a value for a register.
pub const Source = struct {
    context: *anyopaque,
    call: *const fn (*anyopaque) anyerror!u16,
};

pub const Machine = struct {
    pub const memory_size = 0x10000;

    memory: [memory_size]u8 = [_]u8{0} ** memory_size,
    registers: [8]u16 = [_]u16{0} ** 8,
    pc: u16 = 0,
    sp: u16 = 0xFFFE,
    zero: bool = false,
    negative: bool = false,
    carry: bool = false,
    halted: bool = false,
    cycles: u64 = 0,
    out_ports: [256]?Sink = [_]?Sink{null} ** 256,
    in_ports: [256]?Source = [_]?Source{null} ** 256,

    /// Opcode byte -> handler, built at compile time from `opcodes.specs`.
    const dispatch: [256]?*const fn (*Machine) anyerror!void = blk: {
        var table = [_]?*const fn (*Machine) anyerror!void{null} ** 256;
        for (opcodes.specs) |spec| {
            table[@intFromEnum(spec.op)] = @field(Machine, "op_" ++ @tagName(spec.op));
        }
        break :blk table;
    };

    // ------------------------------------------------------------------ setup
    pub fn create(allocator: std.mem.Allocator) !*Machine {
        const machine = try allocator.create(Machine);
        machine.* = .{};
        return machine;
    }

    pub fn load(self: *Machine, image: []const u8, origin: usize) !void {
        if (origin + image.len > memory_size) {
            return failure.raise(error.MachineFault, "image does not fit in memory", .{});
        }
        @memcpy(self.memory[origin .. origin + image.len], image);
    }

    pub fn attachOutput(self: *Machine, port: u8, sink: Sink) void {
        self.out_ports[port] = sink;
    }

    pub fn attachInput(self: *Machine, port: u8, source: Source) void {
        self.in_ports[port] = source;
    }

    // ---------------------------------------------------------------- helpers
    fn fetch8(self: *Machine) u8 {
        const value = self.memory[self.pc];
        self.pc +%= 1;
        return value;
    }

    fn fetch16(self: *Machine) u16 {
        const lo: u16 = self.fetch8();
        return lo | (@as(u16, self.fetch8()) << 8);
    }

    fn fetchRegister(self: *Machine) !u3 {
        const index = self.fetch8();
        if (index >= opcodes.register_count) {
            return failure.raise(error.MachineFault, "invalid register R{d} at 0x{X:0>4}", .{ index, self.pc -% 1 });
        }
        return @intCast(index);
    }

    fn setFlags(self: *Machine, raw: i32) u16 {
        const result: u16 = @truncate(@as(u32, @bitCast(raw)));
        self.zero = result == 0;
        self.negative = result & 0x8000 != 0;
        self.carry = raw < 0 or raw > 0xFFFF;
        return result;
    }

    fn push(self: *Machine, value: u16) void {
        self.sp -%= 2;
        self.memory[self.sp] = @truncate(value);
        self.memory[self.sp +% 1] = @truncate(value >> 8);
    }

    fn pop(self: *Machine) u16 {
        const value = @as(u16, self.memory[self.sp]) | (@as(u16, self.memory[self.sp +% 1]) << 8);
        self.sp +%= 2;
        return value;
    }

    // -------------------------------------------------------------- execution
    pub fn step(self: *Machine) !void {
        const opcode = self.fetch8();
        const handler = dispatch[opcode] orelse {
            return failure.raise(error.MachineFault, "illegal opcode 0x{X:0>2} at 0x{X:0>4}", .{ opcode, self.pc -% 1 });
        };
        try handler(self);
        self.cycles += opcodes.decode(opcode).?.size();
    }

    pub fn run(self: *Machine, max_cycles: u64) !u64 {
        while (!self.halted) {
            if (self.cycles > max_cycles) {
                return failure.raise(error.MachineFault, "watchdog: program refuses to halt", .{});
            }
            try self.step();
        }
        return self.cycles;
    }

    // ----------------------------------------------------------- instructions
    fn op_nop(_: *Machine) !void {}

    fn op_hlt(self: *Machine) !void {
        self.halted = true;
    }

    fn op_movi(self: *Machine) !void {
        const rd = try self.fetchRegister();
        self.registers[rd] = self.fetch16();
    }

    fn op_mov(self: *Machine) !void {
        const rd = try self.fetchRegister();
        const rs = try self.fetchRegister();
        self.registers[rd] = self.registers[rs];
    }

    fn op_ldb(self: *Machine) !void {
        const rd = try self.fetchRegister();
        const rs = try self.fetchRegister();
        self.registers[rd] = self.memory[self.registers[rs]];
    }

    fn op_stb(self: *Machine) !void {
        const rd = try self.fetchRegister();
        const rs = try self.fetchRegister();
        self.memory[self.registers[rd]] = @truncate(self.registers[rs]);
    }

    const Alu = fn (i32, i32) i32;

    fn alu(self: *Machine, comptime f: Alu, comptime store: bool) !void {
        const rd = try self.fetchRegister();
        const rs = try self.fetchRegister();
        const result = self.setFlags(f(self.registers[rd], self.registers[rs]));
        if (store) self.registers[rd] = result;
    }

    fn aluImm(self: *Machine, comptime f: Alu, comptime store: bool) !void {
        const rd = try self.fetchRegister();
        const result = self.setFlags(f(self.registers[rd], self.fetch16()));
        if (store) self.registers[rd] = result;
    }

    fn plus(a: i32, b: i32) i32 {
        return a + b;
    }
    fn minus(a: i32, b: i32) i32 {
        return a - b;
    }
    fn bitAnd(a: i32, b: i32) i32 {
        return a & b;
    }
    fn bitOr(a: i32, b: i32) i32 {
        return a | b;
    }
    fn bitXor(a: i32, b: i32) i32 {
        return a ^ b;
    }

    fn op_add(self: *Machine) !void {
        try self.alu(plus, true);
    }
    fn op_sub(self: *Machine) !void {
        try self.alu(minus, true);
    }
    fn op_and(self: *Machine) !void {
        try self.alu(bitAnd, true);
    }
    fn op_or(self: *Machine) !void {
        try self.alu(bitOr, true);
    }
    fn op_xor(self: *Machine) !void {
        try self.alu(bitXor, true);
    }
    fn op_addi(self: *Machine) !void {
        try self.aluImm(plus, true);
    }
    fn op_cmp(self: *Machine) !void {
        try self.alu(minus, false);
    }
    fn op_cmpi(self: *Machine) !void {
        try self.aluImm(minus, false);
    }

    fn unary(self: *Machine, comptime f: fn (i32) i32) !void {
        const rd = try self.fetchRegister();
        self.registers[rd] = self.setFlags(f(self.registers[rd]));
    }

    fn op_shl(self: *Machine) !void {
        try self.unary(struct {
            fn f(a: i32) i32 {
                return a << 1;
            }
        }.f);
    }
    fn op_shr(self: *Machine) !void {
        try self.unary(struct {
            fn f(a: i32) i32 {
                return a >> 1;
            }
        }.f);
    }
    fn op_inc(self: *Machine) !void {
        try self.unary(struct {
            fn f(a: i32) i32 {
                return a + 1;
            }
        }.f);
    }
    fn op_dec(self: *Machine) !void {
        try self.unary(struct {
            fn f(a: i32) i32 {
                return a - 1;
            }
        }.f);
    }

    fn jumpIf(self: *Machine, condition: bool) void {
        const target = self.fetch16();
        if (condition) self.pc = target;
    }

    fn op_jmp(self: *Machine) !void {
        self.jumpIf(true);
    }
    fn op_jz(self: *Machine) !void {
        self.jumpIf(self.zero);
    }
    fn op_jnz(self: *Machine) !void {
        self.jumpIf(!self.zero);
    }
    fn op_jc(self: *Machine) !void {
        self.jumpIf(self.carry);
    }
    fn op_jnc(self: *Machine) !void {
        self.jumpIf(!self.carry);
    }

    fn op_call(self: *Machine) !void {
        const target = self.fetch16();
        self.push(self.pc);
        self.pc = target;
    }

    fn op_ret(self: *Machine) !void {
        self.pc = self.pop();
    }

    fn op_push(self: *Machine) !void {
        const rs = try self.fetchRegister();
        self.push(self.registers[rs]);
    }

    fn op_pop(self: *Machine) !void {
        const rd = try self.fetchRegister();
        self.registers[rd] = self.pop();
    }

    fn op_out(self: *Machine) !void {
        const port = self.fetch8();
        const rs = try self.fetchRegister();
        const sink = self.out_ports[port] orelse
            return failure.raise(error.MachineFault, "write to unmapped port 0x{X:0>2}", .{port});
        try sink.call(sink.context, self.registers[rs]);
    }

    fn op_in(self: *Machine) !void {
        const rd = try self.fetchRegister();
        const port = self.fetch8();
        const source = self.in_ports[port] orelse
            return failure.raise(error.MachineFault, "read from unmapped port 0x{X:0>2}", .{port});
        self.registers[rd] = try source.call(source.context);
    }
};
