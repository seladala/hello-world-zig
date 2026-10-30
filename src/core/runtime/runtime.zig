// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
const compiler = @import("compiler.zig");
const executor = @import("executor.zig");
const inspector = @import("inspector.zig");

pub const opcodes = @import("opcodes.zig");

pub const AssembledProgram = compiler.AssembledProgram;
pub const AssemblyError = compiler.AssemblyError;
pub const Machine = executor.Machine;
pub const MachineFault = executor.MachineFault;
pub const Sink = executor.Sink;
pub const Source = executor.Source;
pub const assemble = compiler.assemble;
pub const disassemble = inspector.disassemble;
