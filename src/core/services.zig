// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Core services. Each one does a small job in the largest possible number of steps.

const std = @import("std");
const container = @import("container.zig");
const failure = @import("failure.zig");
const logging = @import("logging.zig");
const paths = @import("paths.zig");
const runtime = @import("runtime/runtime.zig");
const arithmetic = @import("diagnostics/arithmetic.zig");
const events = @import("events.zig");
const EnterpriseConfiguration = @import("config.zig").EnterpriseConfiguration;
const PiConsensusProtocol = @import("numerics/numerics.zig").PiConsensusProtocol;
const TerminalRenderingEngine = @import("output/terminal.zig").TerminalRenderingEngine;
const AntiCheatEngine = @import("security/anticheat.zig").AntiCheatEngine;
const LicenseManager = @import("security/drm.zig").LicenseManager;
const GlyphApprovalCommittee = @import("validation/policy.zig").GlyphApprovalCommittee;
const LetterCaseNegotiator = @import("validation/normalization.zig").LetterCaseNegotiator;

const log = logging.Logger.init("core.services");

pub const programs_dir = "src/core/runtime/firmware";

pub const PORT_TTY = 0x01;
pub const PORT_STATUS = 0x02;
pub const PORT_FIB = 0x10;
pub const PORT_RAM = 0x11;
pub const STATUS_GOOD = 0x600D;

pub const ValueError = error{ValueError};

pub const PiService = struct {
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    protocol: PiConsensusProtocol,
    count: usize,
    bus: *events.EventBus,
    cached: ?[]const u8 = null,

    pub fn init(self: *PiService, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{
            .allocator = deps.allocator,
            .scratch = deps.scratch,
            .protocol = .{ .quorum = @intCast(try config.getInt("pi", "quorum")) },
            .count = @intCast(try config.getInt("pi", "digits")),
            .bus = try deps.get(events.EventBus, "event_bus"),
        };
    }

    pub fn digits(self: *PiService) ![]const u8 {
        if (self.cached == null) {
            const agreed = try self.protocol.agree(self.allocator, self.scratch, self.count);
            self.cached = agreed;
            var preview: [16]u8 = undefined;
            const shown = try std.fmt.bufPrint(&preview, "{s}...", .{agreed[0..@min(10, agreed.len)]});
            _ = try self.bus.publish("pi.agreed", .{ .text = shown });
        }
        return self.cached.?;
    }
};

pub const FirmwareLoader = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(runtime.AssembledProgram),

    pub fn init(self: *FirmwareLoader, deps: *container.Deps) !void {
        _ = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{ .allocator = deps.allocator, .cache = .init(deps.allocator) };
    }

    pub fn load(self: *FirmwareLoader, name: []const u8) !runtime.AssembledProgram {
        if (self.cache.get(name)) |program| return program;
        const path = try std.fs.path.join(self.allocator, &.{ paths.projectRoot(), programs_dir, name });
        const source = try std.fs.cwd().readFileAlloc(self.allocator, path, 1 << 20);
        const program = try runtime.assemble(self.allocator, source);
        const listing = try runtime.disassemble(self.allocator, program.image);
        log.info("firmware {s}: {d} bytes, {d} disassembled lines, {d} symbols", .{
            name, program.image.len, listing.len, program.symbols.count(),
        });
        for (listing) |line| log.debug("  {s}", .{line});
        try self.cache.put(name, program);
        return program;
    }
};

const PostResults = struct {
    fib: ?u16 = null,
    ram_errors: ?u16 = null,

    fn onFib(self: *PostResults, value: u16) !void {
        self.fib = value;
    }

    fn onRam(self: *PostResults, value: u16) !void {
        self.ram_errors = value;
    }

    fn passed(self: PostResults) bool {
        return self.fib == 6765 and self.ram_errors == 0;
    }

    /// The results as a `{'fib': ..., 'ram_errors': ...}` record, skipping unreported ones.
    fn fields(self: PostResults, buffer: *[2]events.Field) []events.Field {
        var count: usize = 0;
        if (self.fib) |value| {
            buffer[count] = .{ .key = "fib", .value = .{ .int = value } };
            count += 1;
        }
        if (self.ram_errors) |value| {
            buffer[count] = .{ .key = "ram_errors", .value = .{ .int = value } };
            count += 1;
        }
        return buffer[0..count];
    }
};

const FirmwareOutput = struct {
    allocator: std.mem.Allocator,
    text: std.ArrayList(u8) = .empty,
    status: std.ArrayList(u16) = .empty,

    /// `chr(value & 0xFF)`, spelled in UTF-8.
    fn onTty(self: *FirmwareOutput, value: u16) !void {
        var encoded: [2]u8 = undefined;
        const len = try std.unicode.utf8Encode(value & 0xFF, &encoded);
        try self.text.appendSlice(self.allocator, encoded[0..len]);
    }

    fn onStatus(self: *FirmwareOutput, value: u16) !void {
        try self.status.append(self.allocator, value);
    }
};

pub const CpuService = struct {
    allocator: std.mem.Allocator,
    config: *EnterpriseConfiguration,
    anticheat: *AntiCheatEngine,
    bus: *events.EventBus,
    loader: *FirmwareLoader,
    pi: *PiService,

    pub fn init(self: *CpuService, deps: *container.Deps) !void {
        self.* = .{
            .allocator = deps.allocator,
            .config = try deps.get(EnterpriseConfiguration, "config"),
            .bus = try deps.get(events.EventBus, "event_bus"),
            .loader = try deps.get(FirmwareLoader, "firmware_loader"),
            .pi = try deps.get(PiService, "pi_service"),
            .anticheat = try deps.get(AntiCheatEngine, "anticheat"),
        };
    }

    pub fn onStart(self: *CpuService) !void {
        try self.runSelfTest();
    }

    pub fn runSelfTest(self: *CpuService) !void {
        const machine = try runtime.Machine.create(self.allocator);
        defer self.allocator.destroy(machine);
        try machine.load((try self.loader.load(try self.config.get("cpu", "self_test"))).image, 0);
        var results: PostResults = .{};
        machine.attachOutput(PORT_FIB, .bind(&results, PostResults.onFib));
        machine.attachOutput(PORT_RAM, .bind(&results, PostResults.onRam));
        const cycles = try machine.run(@intCast(try self.config.getInt("cpu", "watchdog_cycles")));
        var buffer: [2]events.Field = undefined;
        const reported: events.Payload = .{ .record = results.fields(&buffer) };
        if (!results.passed()) {
            return failure.raise(error.MachineFault, "POST failed: {f}", .{reported});
        }
        var record: [3]events.Field = undefined;
        record[0] = .{ .key = "cycles", .value = .{ .int = @intCast(cycles) } };
        @memcpy(record[1..], reported.record);
        _ = try self.bus.publish("cpu.post.passed", .{ .record = &record });
    }

    pub fn executeFirmware(self: *CpuService) ![]const u8 {
        const firmware = try self.loader.load(try self.config.get("cpu", "firmware"));
        const machine = try runtime.Machine.create(self.allocator);
        defer self.allocator.destroy(machine);
        try machine.load(firmware.image, 0);
        const digits = try self.pi.digits();
        const digit_values = try self.allocator.alloc(u8, digits.len);
        for (digits, digit_values) |digit, *value| value.* = digit - '0';
        try machine.load(digit_values, @intCast(try self.config.getInt("cpu", "pi_digits_address")));

        var output: FirmwareOutput = .{ .allocator = self.allocator };
        machine.attachOutput(PORT_TTY, .bind(&output, FirmwareOutput.onTty));
        machine.attachOutput(PORT_STATUS, .bind(&output, FirmwareOutput.onStatus));
        const cycles = try machine.run(@intCast(try self.config.getInt("cpu", "watchdog_cycles")));
        try AntiCheatEngine.verifyCodeSegment(machine, firmware.image);
        if (output.status.items.len != 1 or output.status.items[0] != STATUS_GOOD) {
            const statuses = try self.allocator.alloc(i64, output.status.items.len);
            for (output.status.items, statuses) |status, *slot| slot.* = status;
            return failure.raise(error.MachineFault, "firmware reported bad status: {f}", .{@import("repr.zig").list(statuses)});
        }
        const clock_hz: f64 = @floatFromInt(try self.config.getInt("cpu", "clock_hz"));
        const emulated_seconds = @as(f64, @floatFromInt(cycles)) / clock_hz;
        _ = try self.bus.publish("cpu.firmware.halted", .{ .record = &.{
            .{ .key = "cycles", .value = .{ .int = @intCast(cycles) } },
            .{ .key = "emulated_seconds", .value = .{ .float = emulated_seconds } },
        } });
        return output.text.items;
    }
};

pub const GreetingService = struct {
    allocator: std.mem.Allocator,
    config: *EnterpriseConfiguration,
    drm: *LicenseManager,
    anticheat: *AntiCheatEngine,
    bus: *events.EventBus,
    cpu: *CpuService,
    committee: *GlyphApprovalCommittee,
    negotiator: *LetterCaseNegotiator,
    renderer: *TerminalRenderingEngine,

    pub fn init(self: *GreetingService, deps: *container.Deps) !void {
        self.* = .{
            .allocator = deps.allocator,
            .config = try deps.get(EnterpriseConfiguration, "config"),
            .drm = try deps.get(LicenseManager, "drm"),
            .anticheat = try deps.get(AntiCheatEngine, "anticheat"),
            .bus = try deps.get(events.EventBus, "event_bus"),
            .cpu = try deps.get(CpuService, "cpu_service"),
            .committee = try deps.get(GlyphApprovalCommittee, "committee"),
            .negotiator = try deps.get(LetterCaseNegotiator, "case_negotiator"),
            .renderer = try deps.get(TerminalRenderingEngine, "renderer"),
        };
    }

    pub fn produce(self: *GreetingService) ![]const u8 {
        try self.drm.require("greeting.produce");
        const raw = try self.cpu.executeFirmware();
        var it = (try std.unicode.Utf8View.init(raw)).iterator();
        var index: usize = 0;
        while (it.nextCodepointSlice()) |glyph| : (index += 1) {
            _ = try self.bus.publish("glyph.received", .{ .pair = .{ .index = index, .glyph = glyph } });
        }
        const approved = try self.committee.review(raw);
        const final = try self.negotiator.negotiate(approved);
        const expected: u64 = @intCast(try self.config.getInt("greeting", "expected_length"));
        if (arithmetic.toInt(try arithmetic.peanoLength(self.allocator, final)) != expected) {
            return failure.raise(error.ValueError, "greeting failed Peano length verification", .{});
        }
        return final;
    }

    pub fn deliver(self: *GreetingService, message: []const u8) !void {
        try self.drm.require("greeting.render");
        try self.anticheat.scan();
        var it = (try std.unicode.Utf8View.init(message)).iterator();
        var count: i64 = 0;
        while (it.nextCodepointSlice()) |glyph| : (count += 1) {
            _ = try self.bus.publish("glyph.render", .{ .text = glyph });
        }
        _ = try self.bus.publish("transmission.complete", .{ .int = count });
    }
};
