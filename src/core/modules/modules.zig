// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
const graph = @import("graph.zig");
const versioning = @import("versioning.zig");

pub const Component = graph.Component;
pub const Components = graph.Components;
pub const DependencyError = graph.DependencyError;
pub const Requirement = graph.Requirement;
pub const Version = versioning.Version;
pub const loadManifest = graph.loadManifest;
pub const resolve = graph.resolve;
pub const satisfies = versioning.satisfies;
