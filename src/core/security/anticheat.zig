// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Runtime anti-tamper and anti-cheat protection.
//!
//! Detects debuggers and tracers, preloaded instrumentation, interactive
//! inspection, patching of critical machine code, output stream hijacking and
//! clock manipulation ("speedhacks"). Scans run at boot and again right before
//! rendering.

const std = @import("std");
const builtin = @import("builtin");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const logging = @import("../logging.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;
const EventBus = @import("../events.zig").EventBus;
const Machine = @import("../runtime/executor.zig").Machine;
const TerminalRenderingEngine = @import("../output/terminal.zig").TerminalRenderingEngine;
const LetterCaseNegotiator = @import("../validation/normalization.zig").LetterCaseNegotiator;
const GlyphApprovalCommittee = @import("../validation/policy.zig").GlyphApprovalCommittee;

const log = logging.Logger.init("core.security.anticheat");

const protected_types = .{ Machine, GlyphApprovalCommittee, LetterCaseNegotiator, TerminalRenderingEngine };
const protected_count = protected_types.len;

/// How many bytes of each method's machine code are fingerprinted.
const code_window = 64;

/// SHA-256 over the first bytes of machine code of every concrete function of `T`.
fn codeFingerprint(comptime T: type) [32]u8 {
    var digest = std.crypto.hash.sha2.Sha256.init(.{});
    const decls = comptime blk: {
        const all = @typeInfo(T).@"struct".decls;
        var names: [all.len][]const u8 = undefined;
        for (all, 0..) |decl, i| names[i] = decl.name;
        std.mem.sortUnstable([]const u8, &names, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
        break :blk names;
    };
    inline for (decls) |name| {
        const member = @field(T, name);
        const info = @typeInfo(@TypeOf(member));
        if (info == .@"fn" and !info.@"fn".is_generic) {
            const code: [*]const u8 = @ptrCast(&member);
            digest.update(name);
            digest.update(code[0..code_window]);
        }
    }
    return digest.finalResult();
}

const Snapshot = [protected_count][32]u8;

fn snapshot() Snapshot {
    var result: Snapshot = undefined;
    inline for (protected_types, 0..) |T, i| result[i] = codeFingerprint(T);
    return result;
}

/// Ratio of wall-clock to monotonic time over a short busy wait.
fn clockRatio(duration_ns: u64) !f64 {
    const wall_start = std.time.nanoTimestamp();
    const mono_start = try std.time.Instant.now();
    var mono: u64 = 0;
    while (mono < duration_ns) mono = (try std.time.Instant.now()).since(mono_start);
    const wall: f64 = @floatFromInt(std.time.nanoTimestamp() - wall_start);
    return wall / @as(f64, @floatFromInt(mono));
}

/// `TracerPid:` from /proc/self/status; 0 when nobody is watching.
pub fn tracerPid(status: []const u8) u64 {
    var lines = std.mem.splitScalar(u8, status, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "TracerPid:")) {
            return std.fmt.parseInt(u64, std.mem.trim(u8, line["TracerPid:".len..], " \t"), 10) catch 0;
        }
    }
    return 0;
}

fn debuggerAttached() bool {
    if (builtin.os.tag != .linux) return false;
    var buffer: [4096]u8 = undefined;
    const status = std.fs.cwd().readFile("/proc/self/status", &buffer) catch return false;
    return tracerPid(status) != 0;
}

fn isSet(name: []const u8) bool {
    const value = std.posix.getenv(name) orelse return false;
    return value.len != 0;
}

const StreamIdentity = struct { dev: u64, ino: u64 };

fn stdoutIdentity() ?StreamIdentity {
    const stat = std.posix.fstat(std.posix.STDOUT_FILENO) catch return null;
    return .{ .dev = @intCast(stat.dev), .ino = @intCast(stat.ino) };
}

pub const AntiCheatEngine = struct {
    tolerance: f64,
    bus: *EventBus,
    baseline: Snapshot = undefined,
    stdout: ?StreamIdentity = null,
    scans: u64 = 0,

    pub fn init(self: *AntiCheatEngine, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{
            .tolerance = try config.getFloat("security", "clock_tolerance"),
            .bus = try deps.get(EventBus, "event_bus"),
        };
    }

    pub fn onStart(self: *AntiCheatEngine) !void {
        self.baseline = snapshot();
        self.stdout = stdoutIdentity();
        try self.scan();
    }

    pub fn scan(self: *AntiCheatEngine) !void {
        if (debuggerAttached()) {
            return failure.raise(error.CheatDetected, "debugger or tracer attached", .{});
        }
        if (isSet("LD_PRELOAD") or isSet("LD_AUDIT")) {
            return failure.raise(error.CheatDetected, "profiler or instrumentation library preloaded", .{});
        }
        if (isSet("PYTHONINSPECT")) {
            // The Zig edition has no interactive mode, but the policy predates the rewrite.
            return failure.raise(error.CheatDetected, "interactive inspection mode enabled", .{});
        }
        if (!std.meta.eql(stdoutIdentity(), self.stdout)) {
            return failure.raise(error.CheatDetected, "standard output was hijacked after boot", .{});
        }
        const current = snapshot();
        inline for (protected_types, 0..) |T, i| {
            if (!std.mem.eql(u8, &current[i], &self.baseline[i])) {
                return failure.raise(error.CheatDetected, "runtime code modification detected in {s}", .{@typeName(T)});
            }
        }
        const ratio = try clockRatio(5 * std.time.ns_per_ms);
        if (@abs(ratio - 1.0) > self.tolerance) {
            return failure.raise(error.CheatDetected, "clock manipulation detected (ratio {d:.2})", .{ratio});
        }
        self.scans += 1;
        _ = try self.bus.publish("anticheat.scan.clean", .{ .int = @intCast(self.scans) });
        log.info("anti-cheat: scan #{d} clean ({d} protected classes)", .{ self.scans, protected_count });
    }

    /// Detect self-modifying firmware or memory editing during execution.
    pub fn verifyCodeSegment(machine: *const Machine, image: []const u8) !void {
        if (!std.mem.eql(u8, machine.memory[0..image.len], image)) {
            return failure.raise(error.CheatDetected, "firmware code segment was modified during execution", .{});
        }
    }
};
