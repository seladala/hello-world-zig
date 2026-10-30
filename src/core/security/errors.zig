// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Security error set.

/// Every reason the program may refuse to greet you.
pub const SecurityViolation = error{
    IntegrityViolation,
    CheatDetected,
    LicenseError,
};

pub fn isSecurityViolation(err: anyerror) bool {
    inline for (@typeInfo(SecurityViolation).error_set.?) |member| {
        if (err == @field(anyerror, member.name)) return true;
    }
    return false;
}
