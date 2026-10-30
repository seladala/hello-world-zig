// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
const std = @import("std");
const core = @import("core");
const options = @import("test_options");

const testing = std.testing;
const runtime = core.runtime;
const modules = core.modules;
const numerics = core.numerics;
const arithmetic = core.diagnostics.arithmetic;

const Run = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,
};

fn runProgram(allocator: std.mem.Allocator, argv: []const []const u8, root: ?[]const u8) !Run {
    var env = try std.process.getEnvMap(allocator);
    if (root) |path| try env.put(core.paths.root_env_var, path);
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = argv, .env_map = &env });
    return .{
        .status = switch (result.term) {
            .Exited => |code| code,
            else => 255,
        },
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

// ------------------------------------------------------------------ end to end

test "prints hello world" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try runProgram(arena.allocator(), &.{options.exe_path}, null);
    try testing.expectEqualStrings("hello world\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.status);
}

test "main is exactly 67000 lines" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const path = try std.fs.path.join(arena.allocator(), &.{ options.project_root, "src/main.zig" });
    const text = try std.fs.cwd().readFileAlloc(arena.allocator(), path, 16 << 20);
    try testing.expectEqual(@as(usize, 67_000), std.mem.count(u8, text, "\n"));
}

// -------------------------------------------------------------------- security

/// Copies src/ into a temporary project, applies one edit, and runs the program against it.
fn runTampered(relative_path: []const u8, old: []const u8, new: []const u8, refresh_checksums: bool) !Run {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    const arena = arena_state.allocator();
    errdefer arena_state.deinit();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(arena, ".");

    var source = try std.fs.cwd().openDir(try std.fs.path.join(arena, &.{ options.project_root, "src" }), .{ .iterate = true });
    defer source.close();
    var walker = try source.walk(arena);
    while (try walker.next()) |entry| {
        const target = try std.fs.path.join(arena, &.{ "src", entry.path });
        switch (entry.kind) {
            .directory => try tmp.dir.makePath(target),
            .file => {
                try tmp.dir.makePath(std.fs.path.dirname(target).?);
                try source.copyFile(entry.path, tmp.dir, target, .{});
            },
            else => {},
        }
    }

    const target = try std.fs.path.join(arena, &.{ root, relative_path });
    const original = try std.fs.cwd().readFileAlloc(arena, target, 16 << 20);
    const edited = try std.mem.replaceOwned(u8, arena, original, old, new);
    try std.fs.cwd().writeFile(.{ .sub_path = target, .data = edited });

    if (refresh_checksums) {
        const entries = try core.security.integrity.computeManifest(arena, root);
        const file = try std.fs.createFileAbsolute(try std.fs.path.join(arena, &.{ root, core.security.integrity.checksums_path }), .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        try core.security.integrity.writeManifest(&writer.interface, entries);
        try writer.interface.flush();
    }

    const result = try runProgram(arena, &.{options.exe_path}, root);
    // hand the strings to the testing allocator so the arena can go
    const owned: Run = .{
        .status = result.status,
        .stdout = try testing.allocator.dupe(u8, result.stdout),
        .stderr = try testing.allocator.dupe(u8, result.stderr),
    };
    arena_state.deinit();
    return owned;
}

fn freeRun(result: Run) void {
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}

test "modified file is rejected" {
    const result = try runTampered("src/core/settings.ini", "case = lower", "case = UPPER", false);
    defer freeRun(result);
    try testing.expectEqual(@as(u8, 3), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "modified: src/core/settings.ini") != null);
}

test "forged license is rejected" {
    const result = try runTampered("src/core/security/license.dat", "\"Everyone\"", "\"Pirate\"", true);
    defer freeRun(result);
    try testing.expectEqual(@as(u8, 3), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "license signature invalid") != null);
}

test "debugger is detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = runProgram(arena.allocator(), &.{ "strace", "-f", "-o", "/dev/null", options.exe_path }, null) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest, // no strace, no tracer, no test
        else => return err,
    };
    try testing.expectEqual(@as(u8, 3), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "debugger") != null);
}

test "tracer pid is parsed from /proc/self/status" {
    try testing.expectEqual(@as(u64, 0), core.security.anticheat.tracerPid("Name:\tx\nTracerPid:\t0\n"));
    try testing.expectEqual(@as(u64, 4242), core.security.anticheat.tracerPid("TracerPid:\t4242\nUid:\t0\n"));
}

// ------------------------------------------------------------------------- cpu

const Collector = struct {
    values: std.ArrayList(u16) = .empty,

    fn push(self: *Collector, value: u16) !void {
        try self.values.append(testing.allocator, value);
    }
};

test "arithmetic and flags" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const program = try runtime.assemble(arena.allocator(),
        \\    MOVI R0, 5
        \\    MOVI R1, 7
        \\    ADD  R0, R1
        \\    CMPI R0, 12
        \\    JZ   ok
        \\    HLT
        \\ok: MOVI R2, 1
        \\    OUT  0x01, R2
        \\    HLT
    );
    const machine = try runtime.Machine.create(testing.allocator);
    defer testing.allocator.destroy(machine);
    try machine.load(program.image, 0);
    var out: Collector = .{};
    defer out.values.deinit(testing.allocator);
    machine.attachOutput(1, .bind(&out, Collector.push));
    _ = try machine.run(5_000_000);
    try testing.expectEqualSlices(u16, &.{1}, out.values.items);
    try testing.expectEqual(@as(u16, 12), machine.registers[0]);
}

// -------------------------------------------------------------------------- pi

test "all algorithms agree" {
    const digits = try numerics.high_precision.piDigits(testing.allocator, 500);
    defer testing.allocator.free(digits);
    try testing.expect(std.mem.startsWith(u8, digits, "31415926535897932384626433"));
    const machin = try numerics.series.piDigits(testing.allocator, 500);
    defer testing.allocator.free(machin);
    try testing.expectEqualStrings(digits, machin);
    const spigot = try numerics.streaming.piDigits(testing.allocator, 500);
    defer testing.allocator.free(spigot);
    try testing.expectEqualStrings(digits, spigot);
}

// ------------------------------------------------------------------ dependency

test "semver" {
    try testing.expect(try modules.satisfies(try modules.Version.parse("3.14.15"), ">=3.14,<4"));
    try testing.expect(try modules.satisfies(try modules.Version.parse("2.3.9"), "~2.3"));
    try testing.expect(!try modules.satisfies(try modules.Version.parse("3.1.4"), ">=3.14"));
}

test "cycle detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var components = modules.Components.init(arena.allocator());
    const version = try modules.Version.parse("1.0.0");
    try components.put("a", .{ .name = "a", .version = version, .provider = "x:y", .requires = &.{.{ .name = "b", .spec = ">=1" }} });
    try components.put("b", .{ .name = "b", .version = version, .provider = "x:y", .requires = &.{.{ .name = "a", .spec = ">=1" }} });
    try testing.expectError(error.DependencyError, modules.resolve(arena.allocator(), &components));
}

// ----------------------------------------------------------------------- peano

test "length" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(@as(u64, 11), arithmetic.toInt(try arithmetic.peanoLength(arena.allocator(), "hello world")));
}

// --------------------------------------------------------- python compatibility

test "mersenne twister matches CPython" {
    // python3 -c "import random; print(random.Random(0xC0FFEE).getrandbits(32))"
    var rng: core.diagnostics.mersenne.Random = .init(0xC0FFEE);
    try testing.expectEqual(@as(u64, 4116735509), rng.getrandbits(32));
}
