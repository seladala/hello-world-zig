// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Hello World core library.

pub const version = "6.7.0";

pub const bootstrap = @import("bootstrap.zig");
pub const cli = @import("cli.zig");
pub const config = @import("config.zig");
pub const container = @import("container.zig");
pub const diagnostics = @import("diagnostics/diagnostics.zig");
pub const events = @import("events.zig");
pub const failure = @import("failure.zig");
pub const logging = @import("logging.zig");
pub const modules = @import("modules/modules.zig");
pub const numerics = @import("numerics/numerics.zig");
pub const output = @import("output/output.zig");
pub const paths = @import("paths.zig");
pub const pyjson = @import("pyjson.zig");
pub const repr = @import("repr.zig");
pub const runtime = @import("runtime/runtime.zig");
pub const security = @import("security/security.zig");
pub const services = @import("services.zig");
pub const validation = @import("validation/validation.zig");
