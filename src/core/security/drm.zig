// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Digital Rights Management.
//!
//! The greeting is licensed content. A signed license file grants entitlements;
//! the signing key is derived from the first 100 digits of pi, so the license
//! cannot even be checked until the pi oracles have reached consensus.

const std = @import("std");
const container = @import("../container.zig");
const failure = @import("../failure.zig");
const logging = @import("../logging.zig");
const paths = @import("../paths.zig");
const pyjson = @import("../pyjson.zig");
const repr = @import("../repr.zig");
const EnterpriseConfiguration = @import("../config.zig").EnterpriseConfiguration;
const EventBus = @import("../events.zig").EventBus;
const PiService = @import("../services.zig").PiService;

const log = logging.Logger.init("core.security.drm");

pub const license_path = "src/core/security/license.dat";
pub const key_digits = 100;

const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

pub fn deriveKey(pi_digits: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("pi:");
    hasher.update(pi_digits[0..@min(key_digits, pi_digits.len)]);
    return hasher.finalResult();
}

pub fn canonical(allocator: std.mem.Allocator, body: std.json.Value) ![]u8 {
    return pyjson.dumpsAlloc(allocator, body, pyjson.canonical);
}

pub fn sign(allocator: std.mem.Allocator, body: std.json.Value, key: [32]u8) ![64]u8 {
    const message = try canonical(allocator, body);
    defer allocator.free(message);
    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, message, &key);
    return std.fmt.bytesToHex(mac, .lower);
}

/// `hmac.compare_digest`: no early exit, no timing side channel, no fun.
fn compareDigest(a: []const u8, b: []const u8) bool {
    var difference: u8 = @intFromBool(a.len != b.len);
    for (0..@min(a.len, b.len)) |i| difference |= a[i] ^ b[i];
    return difference == 0;
}

/// `date.today().isoformat()`, in UTC.
fn today(buffer: *[10]u8) []const u8 {
    const seconds: u64 = @intCast(std.time.timestamp());
    const day = (std.time.epoch.EpochSeconds{ .secs = seconds }).getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        year_day.year, month_day.month.numeric(), month_day.day_index + 1,
    }) catch unreachable;
}

fn isIsoDate(text: []const u8) bool {
    if (text.len != 10 or text[4] != '-' or text[7] != '-') return false;
    for (text, 0..) |c, i| {
        if (i != 4 and i != 7 and !std.ascii.isDigit(c)) return false;
    }
    return true;
}

pub const LicenseManager = struct {
    allocator: std.mem.Allocator,
    bus: *EventBus,
    pi: *PiService,
    product: []const u8,
    entitlements: std.StringArrayHashMap(void),

    pub fn init(self: *LicenseManager, deps: *container.Deps) !void {
        const config = try deps.get(EnterpriseConfiguration, "config");
        self.* = .{
            .allocator = deps.allocator,
            .bus = try deps.get(EventBus, "event_bus"),
            .pi = try deps.get(PiService, "pi_service"),
            .product = try config.get("security", "product_id"),
            .entitlements = .init(deps.allocator),
        };
    }

    pub fn onStart(self: *LicenseManager) !void {
        const path = try paths.resolve(self.allocator, license_path);
        const text = std.fs.cwd().readFileAlloc(self.allocator, path, 1 << 20) catch |err|
            return failure.raise(error.LicenseError, "license file unreadable: {s}", .{@errorName(err)});
        var document = std.json.parseFromSliceLeaky(std.json.Value, self.allocator, text, .{}) catch |err|
            return failure.raise(error.LicenseError, "license file unreadable: {s}", .{@errorName(err)});
        if (document != .object) return failure.raise(error.LicenseError, "license file unreadable: not an object", .{});

        const signature = if (document.object.fetchOrderedRemove("signature")) |entry| switch (entry.value) {
            .string => |value| value,
            else => "",
        } else "";
        const expected = try sign(self.allocator, document, deriveKey(try self.pi.digits()));
        if (!compareDigest(signature, &expected)) {
            return failure.raise(error.LicenseError, "license signature invalid", .{});
        }

        const product = stringField(document, "product");
        if (product == null or !std.mem.eql(u8, product.?, self.product)) {
            return failure.raise(error.LicenseError, "license is for {f}, not {f}", .{ OptionalRepr{ .value = product }, repr.str(self.product) });
        }
        if (document.object.get("expires")) |expires| {
            if (expires != .null) {
                if (expires != .string or !isIsoDate(expires.string)) {
                    return failure.raise(error.LicenseError, "license expiry is not an ISO date", .{});
                }
                var buffer: [10]u8 = undefined;
                if (std.mem.order(u8, expires.string, today(&buffer)) == .lt) {
                    return failure.raise(error.LicenseError, "license expired on {s}", .{expires.string});
                }
            }
        }
        if (document.object.get("entitlements")) |granted| {
            for (granted.array.items) |entitlement| try self.entitlements.put(entitlement.string, {});
        }
        const licensee = stringField(document, "licensee") orelse
            return failure.raise(error.LicenseError, "license names no licensee", .{});
        _ = try self.bus.publish("drm.license.activated", .{ .text = licensee });
        log.info("drm: {s} edition licensed to {s} ({d} entitlements)", .{
            stringField(document, "edition") orelse "?", licensee, self.entitlements.count(),
        });
    }

    pub fn require(self: *const LicenseManager, entitlement: []const u8) !void {
        if (!self.entitlements.contains(entitlement)) {
            return failure.raise(error.LicenseError, "license does not grant {f}", .{repr.str(entitlement)});
        }
    }
};

fn stringField(document: std.json.Value, key: []const u8) ?[]const u8 {
    const value = document.object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

const OptionalRepr = struct {
    value: ?[]const u8,

    pub fn format(self: OptionalRepr, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.value) |text| try repr.writeStr(w, text) else try w.writeAll("None");
    }
};
