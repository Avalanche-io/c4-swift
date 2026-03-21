# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in c4-swift, please report it responsibly.

**Do not open a public issue.** Instead, email security@avalanche.io with:

- A description of the vulnerability
- Steps to reproduce it
- The potential impact
- Any suggested fix (if you have one)

We will acknowledge your report within 48 hours and provide a timeline for a fix.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |

## Security Considerations

### C4M Parsing

The `Decoder` processes untrusted input. The following protections are in place:

- **Path traversal prevention**: Entry names are validated to reject `..`, `/` separators, `\` separators, and null bytes. The `validate()` method checks for path traversal attacks.
- **Duplicate path detection**: `validate()` rejects manifests with duplicate full paths.
- **CR rejection**: Lines containing CR (0x0D) bytes are rejected. C4m requires LF-only line endings.
- **Directive rejection**: Lines starting with `@` are rejected to prevent injection of unsupported directives.
- **Bounded parsing**: The decoder processes input line by line with bounded field parsing. There are no recursive descent patterns that could cause stack overflow.

### C4 ID Computation

C4 IDs are computed using SHA-512 via Apple's CryptoKit framework. The implementation does not include its own cryptographic primitives.

- **Base-58 encoding/decoding**: Uses a constant-time lookup table for decoding. Invalid characters are rejected.
- **Digest validation**: C4ID construction from a digest requires exactly 64 bytes. String parsing requires exactly 90 characters starting with "c4".

### SafeName Encoding

The Universal Filename Encoding (`safeName` / `unsafeName`) handles arbitrary byte sequences in filenames:

- **Null bytes**: Encoded as `\0` (Tier 2 backslash escape)
- **Control characters**: Non-printable bytes are encoded using Tier 2 (backslash) or Tier 3 (braille) encoding
- **Round-trip safety**: `unsafeName(safeName(x)) == x` for all valid inputs

### Patch Chain Verification

When decoding c4m files with embedded patch chains, each checkpoint C4 ID is verified against the accumulated manifest state. A mismatch throws `C4MError.patchIDMismatch`, preventing tampered patches from being silently applied.

### Memory Safety

All types are value types (or reference types with controlled mutation). The package builds with Swift 6 strict concurrency checking and has no unsafe memory access patterns.

## Cryptographic Note

C4 uses SHA-512 for content identification. SHA-512 is a collision-resistant hash function suitable for content addressing. C4 IDs are not used for password hashing, key derivation, or authentication -- they identify content.

The SMPTE ST 2114:2017 standard specifies SHA-512 as the hash algorithm for C4. This is not configurable.
