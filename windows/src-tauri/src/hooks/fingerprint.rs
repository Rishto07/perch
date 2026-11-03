// Identifies the exact bytes a preview was computed from, so Perch only ever
// writes what the user actually looked at. The question is always "is this
// still the file I showed the user?" — never a checksum for anything else.

pub(crate) fn fingerprint(bytes: &[u8]) -> String {
    // FNV-1a is plenty for that.
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(0x1000_0000_01b3);
    }
    format!("{hash:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fingerprint_notices_any_change() {
        assert_eq!(fingerprint(b"{}"), fingerprint(b"{}"));
        assert_ne!(fingerprint(b"{}"), fingerprint(b"{ }"));
        assert_ne!(fingerprint(b""), fingerprint(b"{}"));
    }
}
