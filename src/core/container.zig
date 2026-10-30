// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Inversion-of-Control container.
//!
//! Components are instantiated in dependency order; each provider receives a
//! `Deps` handle that hands out exactly the components it declared in the
//! manifest - no more (missing argument), no less (unexpected argument).

const std = @import("std");
const failure = @import("failure.zig");
const logging = @import("logging.zig");
const Component = @import("modules/graph.zig").Component;

const log = logging.Logger.init("core.container");

pub const ContainerError = error{ContainerError};

/// Python had importlib. Zig has this table.
const providers = .{
    .{ "core.config:EnterpriseConfiguration", @import("config.zig").EnterpriseConfiguration },
    .{ "core.events:EventBus", @import("events.zig").EventBus },
    .{ "core.diagnostics.entropy:EntropyPool", @import("diagnostics/entropy.zig").EntropyPool },
    .{ "core.diagnostics.health_check:WarmupOrchestrator", @import("diagnostics/health_check.zig").WarmupOrchestrator },
    .{ "core.validation.audit_log:GlyphChain", @import("validation/audit_log.zig").GlyphChain },
    .{ "core.validation.policy:GlyphApprovalCommittee", @import("validation/policy.zig").GlyphApprovalCommittee },
    .{ "core.validation.normalization:LetterCaseNegotiator", @import("validation/normalization.zig").LetterCaseNegotiator },
    .{ "core.output.terminal:TerminalRenderingEngine", @import("output/terminal.zig").TerminalRenderingEngine },
    .{ "core.security.drm:LicenseManager", @import("security/drm.zig").LicenseManager },
    .{ "core.security.anticheat:AntiCheatEngine", @import("security/anticheat.zig").AntiCheatEngine },
    .{ "core.services:PiService", @import("services.zig").PiService },
    .{ "core.services:FirmwareLoader", @import("services.zig").FirmwareLoader },
    .{ "core.services:CpuService", @import("services.zig").CpuService },
    .{ "core.services:GreetingService", @import("services.zig").GreetingService },
};

pub const Provider = struct {
    type_name: []const u8,
    construct: *const fn (*Deps) anyerror!*anyopaque,
    on_start: ?*const fn (*anyopaque) anyerror!void,
};

fn providerFor(comptime T: type) Provider {
    const Hooks = struct {
        fn construct(deps: *Deps) anyerror!*anyopaque {
            const instance = try deps.allocator.create(T);
            try T.init(instance, deps);
            return instance;
        }

        fn onStart(instance: *anyopaque) anyerror!void {
            const self: *T = @ptrCast(@alignCast(instance));
            try self.onStart();
        }
    };
    return .{
        .type_name = @typeName(T),
        .construct = Hooks.construct,
        .on_start = if (@hasDecl(T, "onStart")) Hooks.onStart else null,
    };
}

pub fn importProvider(path: []const u8) !Provider {
    inline for (providers) |entry| {
        if (std.mem.eql(u8, entry[0], path)) return providerFor(entry[1]);
    }
    return failure.raise(error.ContainerError, "No provider registered for '{s}'", .{path});
}

pub const Instance = struct {
    name: []const u8,
    type_name: []const u8,
    pointer: *anyopaque,
    on_start: ?*const fn (*anyopaque) anyerror!void,

    pub fn onStart(self: Instance) !void {
        if (self.on_start) |hook| try hook(self.pointer);
    }
};

/// The dependencies of the component currently being constructed.
pub const Deps = struct {
    container: *Container,
    /// Lives as long as the container.
    allocator: std.mem.Allocator,
    /// General-purpose allocator for temporaries that are freed again.
    scratch: std.mem.Allocator,
    component: *const Component,
    consumed: u64 = 0,

    pub fn get(self: *Deps, comptime T: type, name: []const u8) !*T {
        for (self.component.requires, 0..) |requirement, i| {
            if (std.mem.eql(u8, requirement.name, name)) {
                self.consumed |= @as(u64, 1) << @intCast(i);
                return self.container.get(T, name);
            }
        }
        return failure.raise(error.ContainerError, "{s}() missing required argument: '{s}'", .{ self.component.provider, name });
    }
};

pub const Container = struct {
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    instances: std.StringArrayHashMap(Instance),

    pub fn init(allocator: std.mem.Allocator, scratch: std.mem.Allocator) Container {
        return .{ .allocator = allocator, .scratch = scratch, .instances = .init(allocator) };
    }

    pub fn instantiate(self: *Container, component: *const Component) !Instance {
        if (self.instances.contains(component.name)) {
            return failure.raise(error.ContainerError, "component already running: {s}", .{component.name});
        }
        const provider = try importProvider(component.provider);
        for (component.requires) |requirement| {
            if (!self.instances.contains(requirement.name)) {
                return failure.raise(error.ContainerError, "component not running: {s}", .{requirement.name});
            }
        }
        var deps: Deps = .{
            .container = self,
            .allocator = self.allocator,
            .scratch = self.scratch,
            .component = component,
        };
        const pointer = try provider.construct(&deps);
        for (component.requires, 0..) |requirement, i| {
            if (deps.consumed & (@as(u64, 1) << @intCast(i)) == 0) {
                return failure.raise(error.ContainerError, "{s}() got an unexpected keyword argument '{s}'", .{ component.provider, requirement.name });
            }
        }
        const instance: Instance = .{
            .name = component.name,
            .type_name = provider.type_name,
            .pointer = pointer,
            .on_start = provider.on_start,
        };
        try self.instances.put(component.name, instance);
        var version: [32]u8 = undefined;
        const version_text = std.fmt.bufPrint(&version, "{f}", .{component.version}) catch "?";
        log.info("started {s:<18} v{s:<6} <- {s}", .{ component.name, version_text, component.provider });
        return instance;
    }

    pub fn get(self: *Container, comptime T: type, name: []const u8) !*T {
        const instance = self.instances.get(name) orelse
            return failure.raise(error.ContainerError, "component not running: {s}", .{name});
        if (!std.mem.eql(u8, instance.type_name, @typeName(T))) {
            return failure.raise(error.ContainerError, "component {s} is a {s}, not a {s}", .{ name, instance.type_name, @typeName(T) });
        }
        return @ptrCast(@alignCast(instance.pointer));
    }

    pub fn contains(self: *const Container, name: []const u8) bool {
        return self.instances.contains(name);
    }
};
