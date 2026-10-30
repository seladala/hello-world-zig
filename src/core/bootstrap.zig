// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Kernel: resolves the dependency graph, boots every component, runs lifecycle hooks.

const std = @import("std");
const modules = @import("modules/modules.zig");
const logging = @import("logging.zig");
const paths = @import("paths.zig");
const integrity = @import("security/integrity.zig");
const Container = @import("container.zig").Container;
const EventBus = @import("events.zig").EventBus;
const GreetingService = @import("services.zig").GreetingService;

const log = logging.Logger.init("core.bootstrap");

pub const default_manifest = "src/core/manifests/services.json";

pub const Kernel = struct {
    container: *Container,

    pub fn boot(allocator: std.mem.Allocator, scratch: std.mem.Allocator) !Kernel {
        return bootManifest(allocator, scratch, try paths.resolve(allocator, default_manifest));
    }

    pub fn bootManifest(allocator: std.mem.Allocator, scratch: std.mem.Allocator, manifest: []const u8) !Kernel {
        _ = try integrity.verify(allocator);
        var components = try modules.loadManifest(allocator, manifest);
        const order = try modules.resolve(allocator, &components);
        if (logging.isEnabledFor(.info)) {
            var names: std.ArrayList(u8) = .empty;
            for (order, 0..) |component, i| {
                if (i != 0) try names.appendSlice(allocator, " -> ");
                try names.appendSlice(allocator, component.name);
            }
            log.info("boot order: {s}", .{names.items});
        }
        const container = try allocator.create(Container);
        container.* = .init(allocator, scratch);
        for (order) |*component| {
            const instance = try container.instantiate(component);
            try instance.onStart();
        }
        const bus = try container.get(EventBus, "event_bus");
        _ = try bus.publish("kernel.booted", .{ .int = @intCast(order.len) });
        return .{ .container = container };
    }

    pub fn produceGreeting(self: Kernel) ![]const u8 {
        return (try self.container.get(GreetingService, "greeting_service")).produce();
    }

    pub fn render(self: Kernel, message: []const u8) !void {
        try (try self.container.get(GreetingService, "greeting_service")).deliver(message);
    }
};
