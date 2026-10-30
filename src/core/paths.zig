// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Where the project lives. Python asked `__file__`; Zig asks the build system.

const std = @import("std");
const build_options = @import("build_options");

/// Overrides the project root baked in at build time.
pub const root_env_var = "HELLO_WORLD_ROOT";

pub const entry_point = "src/main.zig";
pub const package_dir = "src/core";

pub fn projectRoot() []const u8 {
    if (std.posix.getenv(root_env_var)) |value| {
        if (value.len != 0) return value;
    }
    return build_options.project_root;
}

/// Absolute path of a file given relative to the project root.
pub fn resolve(allocator: std.mem.Allocator, relative: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ projectRoot(), relative });
}
