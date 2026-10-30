// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Synchronous, in-process, single-threaded, enterprise-grade event bus.

const std = @import("std");
const container = @import("container.zig");
const logging = @import("logging.zig");
const repr = @import("repr.zig");

const log = logging.Logger.init("core.events");

var sequence_counter: u64 = 0;

pub const Scalar = union(enum) {
    int: i64,
    float: f64,
    text: []const u8,

    pub fn format(self: Scalar, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .int => |value| try w.print("{d}", .{value}),
            .float => |value| try w.print("{d}", .{value}),
            .text => |value| try repr.writeStr(w, value),
        }
    }
};

pub const Field = struct {
    key: []const u8,
    value: Scalar,
};

/// What Python called `Any`.
pub const Payload = union(enum) {
    none,
    int: i64,
    text: []const u8,
    /// `(index, glyph)`
    pair: struct { index: usize, glyph: []const u8 },
    /// `{'key': value, ...}`
    record: []const Field,

    pub fn format(self: Payload, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .none => try w.writeAll("None"),
            .int => |value| try w.print("{d}", .{value}),
            .text => |value| try repr.writeStr(w, value),
            .pair => |pair| {
                try w.print("({d}, ", .{pair.index});
                try repr.writeStr(w, pair.glyph);
                try w.writeByte(')');
            },
            .record => |fields| {
                try w.writeByte('{');
                for (fields, 0..) |field, i| {
                    if (i != 0) try w.writeAll(", ");
                    try repr.writeStr(w, field.key);
                    try w.print(": {f}", .{field.value});
                }
                try w.writeByte('}');
            },
        }
    }

    fn clone(self: Payload, allocator: std.mem.Allocator) !Payload {
        return switch (self) {
            .none, .int => self,
            .text => |value| .{ .text = try allocator.dupe(u8, value) },
            .pair => |pair| .{ .pair = .{ .index = pair.index, .glyph = try allocator.dupe(u8, pair.glyph) } },
            .record => |fields| blk: {
                const copy = try allocator.alloc(Field, fields.len);
                for (fields, copy) |field, *slot| {
                    slot.* = .{
                        .key = try allocator.dupe(u8, field.key),
                        .value = switch (field.value) {
                            .text => |text| .{ .text = try allocator.dupe(u8, text) },
                            else => field.value,
                        },
                    };
                }
                break :blk .{ .record = copy };
            },
        };
    }
};

pub const Event = struct {
    topic: []const u8,
    payload: Payload = .none,
    sequence: u64,
};

pub const Handler = struct {
    context: *anyopaque,
    call: *const fn (*anyopaque, Event) anyerror!void,

    /// Bind a method of the form `fn (self: *T, event: Event) !void`.
    pub fn bind(context: anytype, comptime method: anytype) Handler {
        const Ptr = @TypeOf(context);
        const Thunk = struct {
            fn call(ctx: *anyopaque, event: Event) anyerror!void {
                return method(@as(Ptr, @ptrCast(@alignCast(ctx))), event);
            }
        };
        return .{ .context = context, .call = Thunk.call };
    }
};

pub const EventBus = struct {
    allocator: std.mem.Allocator,
    subscribers: std.StringHashMap(std.ArrayList(Handler)),
    history: std.ArrayList(Event),

    pub fn init(self: *EventBus, deps: *container.Deps) !void {
        self.* = .{
            .allocator = deps.allocator,
            .subscribers = .init(deps.allocator),
            .history = .empty,
        };
    }

    pub fn subscribe(self: *EventBus, topic: []const u8, handler: Handler) !void {
        const entry = try self.subscribers.getOrPut(topic);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(self.allocator, handler);
    }

    pub fn publish(self: *EventBus, topic: []const u8, payload: Payload) !Event {
        sequence_counter += 1;
        const event: Event = .{
            .topic = topic,
            .payload = try payload.clone(self.allocator),
            .sequence = sequence_counter,
        };
        try self.history.append(self.allocator, event);
        log.debug("event #{d:0>5} {s:<28} {f}", .{ event.sequence, topic, event.payload });
        if (self.subscribers.get(topic)) |handlers| {
            for (handlers.items) |handler| try handler.call(handler.context, event);
        }
        if (self.subscribers.get("*")) |handlers| {
            for (handlers.items) |handler| try handler.call(handler.context, event);
        }
        return event;
    }
};
