# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PQ-GM-IPSec & IKEv2** is an experimental post-quantum cryptography (PQC) implementation for IKEv2/IPsec based on **strongSwan 6.0+**. It integrates:
- **PQC algorithms**: ML-KEM-768 (FIPS 203) + ML-DSA-65 (FIPS 204)
- **Chinese cryptography**: SM2/SM3/SM4 (GB/T standards) via **GMSSL 3.1.3**
- **Protocol extensions**: IKE_INTERMEDIATE (RFC 9242) + Multiple Key Exchanges/ADDKE (RFC 9370)

### Core Design
The protocol uses a **fixed 3-round IKE_INTERMEDIATE sequence**:
1. **IKE_SA_INIT**: Negotiate with ADDKE support (HMAC-SM3 PRF)
2. **IKE_INTERMEDIATE #1**: Exchange dual certificates (SignCert/EncCert) — no key update
3. **IKE_INTERMEDIATE #2**: ADDKE1 = SM2-KEM (group 65001) — first key update with SK_sm2 = r_i || r_r (64B)
4. **IKE_INTERMEDIATE #3**: ADDKE2 = ML-KEM-768 — second key update
5. **IKE_AUTH**: Mandatory ML-DSA-65 signature with IntAuth binding of intermediates

See `docs/project/PQGM-IKEv2 协议实现规范.md` and `docs/project/PQGM-IPSec 实施规划与验收.md` for full protocol specification and milestones.

## Repository Structure

```
pqgm-ipsec/
├── docs/
│   ├── project/
│   │   ├── PQGM-IKEv2 协议实现规范.md      # Protocol specification
│   │   └── PQGM-IPSec 实施规划与验收.md     # Implementation plan & test cases
│   └── role/
│       └── 角色定义.md                     # Developer constraints & requirements
├── third_party/                           # Git submodules (strongswan, gmssl)
│   ├── strongswan/                        # strongSwan 6.0+ base
│   └── gmssl/                             # GMSSL 3.1.3 crypto library
├── src/
│   ├── new-plugins/                       # Custom plugins (gmalg, sm2kem, mldsa)
│   └── patches/
│       ├── strongswan/                    # Patches applied to strongSwan (0001-*.patch...)
│       └── gmssl/                         # Patches applied to GMSSL
├── tests/
│   ├── data/                              # Test artifacts (pcaps, logs, configs)
│   │   ├── pcaps/TC-*.pcapng
│   │   ├── logs/TC-*.log
│   │   └── configs_snapshot/TC-*.conf
│   └── scripts/                           # Test execution scripts
├── docker/                                # Docker compose for dual-container testing
├── configs/                               # swanctl.conf templates
└── README.md                              # Quick start guide
```

## Key Architectural Patterns

### Plugin Integration
**strongSwan uses a plugin architecture**. Custom implementations go in `src/new-plugins/`:
- **gmalg**: Integrates GMSSL via dlopen/libcrypto interface (provides HMAC-SM3, SM2 encryption/decryption, SM3/SM4)
- **sm2kem**: Implements SM2-KEM as a private Transform Type 4 DH Group (ID 65001) per RFC 9370
- **mldsa** (if needed): Provides ML-DSA-65 signing/verification (either via strongSwan upstream or custom plugin)

### Patches vs. Plugins
- **Prefer plugins** (`src/new-plugins/`) for isolation and maintainability
- **Patches** (`src/patches/strongswan/`, `src/patches/gmssl/`) are reserved for unavoidable core changes:
  - Applied in sequence during build (use `git am` for git-managed patches)
  - Must be documented in README with apply order
  - Version-lock submodules after patching

### Configuration Extension
**swanctl.conf** must support new fields for dual certificates (per `docs/project/...`):
- `local.sign_cert`: Path to signing certificate (SM2/ML-DSA key pair)
- `local.enc_cert`: Path to encryption certificate (SM2 public key for SM2-KEM)

### Key Update Chain (RFC 9370)
Each ADDKE generates a shared secret SK(n), triggering sequential key updates:
```
SKEYSEED(n) = prf(SK_d(n-1), SK(n) | Ni | Nr)
SK_* = prf+(SKEYSEED(n), Ni | Nr | SPIi | SPIr)
```
Where `prf` and `prf+` use **HMAC-SM3** (32B output) throughout.

### Certificate Verification Strategy
**Experimental phase**: Certificate chain validation is bypassed ("accept-all" mode) but:
- Certificate parsing and SignCert/EncCert classification must succeed
- Logs must clearly mark "certificate verification bypass enabled"
- Reliance on **IntAuth binding** (RFC 9242) ensures tampering causes IKE_AUTH failure
- Negative test cases (TC-NEG-001, TC-NEG-002) prove tampering is detectable

## Development Workflow

### Initial Setup
1. **Initialize submodules** (if not already done):
   ```bash
   git submodule update --init --recursive
   ```
2. **Verify submodule versions** are locked in `.gitmodules` — do not auto-upgrade without explicit cause

### Building (General Pattern)
The project uses **strongSwan's autoconf build system**. Typical workflow:
```bash
# 1. Prepare strongSwan with patches and plugins
cd third_party/strongswan
git am ../../src/patches/strongswan/*.patch
./autogen.sh
./configure --prefix=/usr/local --enable-debug [+ plugin flags]
make
make install

# 2. Build custom plugins
cd ../../src/new-plugins
# Each plugin has its own build (e.g., gmalg uses GMSSL library)
```

**Note**: Exact build commands and test setup are in `README.md` and `docker/` compose file. Refer there for complete instructions.

### Testing Strategy
1. **Docker Phase (MUST)**:
   - Use `docker-compose` in `docker/` to spin up dual containers (initiator/responder)
   - Each test case (TC-ID) produces: `.pcapng`, `.log`, `.conf` snapshot
2. **Dual-Machine Phase (MUST)**:
   - Deploy same configuration to two physical Linux hosts
   - Re-run test cases to verify consistency

### Test Cases (Minimum Set)
All test cases are defined in `docs/project/PQGM-IPSec 实施规划与验收.md`:
- **TC-HS-000**: Framework — 3 IKE_INTERMEDIATE rounds execute (no real KEM, validates sequencing)
- **TC-HS-001**: Dual certificate distribution + ADDKE1 (SM2-KEM) successful, 1× key update
- **TC-HS-002**: TC-HS-001 + ADDKE2 (ML-KEM) successful, 2× key update
- **TC-AUTH-001**: IKE_AUTH mandatory ML-DSA-65 succeeds; wrong cert/algorithm fails
- **TC-NEG-001**: Tamper with intermediate #2 ct_i/ct_r → IKE_AUTH must fail
- **TC-NEG-002**: Replace intermediate #1 EncCert → IKE_AUTH must fail
- **TC-EVAL-001**: Evaluation metrics (handshake latency, CPU time, packet size, fragmentation, retry stats)

### Git Workflow & PR Requirements
- **main**: Stable, runnable versions only
- **dev**: Daily integration branch
- **feature/\***: Feature branches (e.g., `feature/gmalg`, `feature/sm2kem`, `feature/mldsa`)
- **Each PR must include**:
  - Associated GitHub Issue (TC-ID reference)
  - Test case results (pass/fail + evidence)
  - Links to test artifacts in `tests/data/` (relative paths)

### Patch Management
If core changes to submodules are necessary:
1. Modify files in `third_party/strongswan/` or `third_party/gmssl/`
2. Generate patch:
   ```bash
   cd third_party/strongswan && git diff > ../../src/patches/strongswan/0001-description.patch
   ```
3. Document patch purpose and apply sequence in README
4. **Never copy upstream sources into main repo directory** — always work via submodule + patches

## Common Commands

| Task | Pattern |
|------|---------|
| Build strongSwan with patches | See `README.md` build section |
| Run Docker tests | `docker-compose up` in `docker/` (or per README) |
| Run single test case TC-ID | See `tests/scripts/` or Docker run command |
| Check certificate parsing | Look for `"SignCert"/"EncCert"` markers in charon logs |
| Validate SM2-KEM in pcap | Filter for KE payload with group=65001 in Wireshark |
| Verify HMAC-SM3 PRF | Check SKEYSEED derivation logs; expect 32B output |
| Check IntAuth binding | Look for "IKE_AUTH" logs including all intermediate hashes |
| Apply patches to submodule | `cd third_party/strongswan && git am ../../src/patches/strongswan/*.patch` |

## Important Implementation Notes

1. **SM2-KEM Shared Secret Format**:
   - Always `SK_sm2 = r_i || r_r` (Initiator random first, Responder random second)
   - Both r_i and r_r are 32B (derived from HMAC-SM3 output length)
   - Total 64B, no KDF applied

2. **Private Transform ID**:
   - DH Group Transform Type = 4
   - Private group ID = 65001
   - Must be recognized in both initiator and responder negotiations

3. **Certificate Distinction**:
   - SignCert: Used for ML-DSA-65 signature in IKE_AUTH; also used for SM2 signature verification (if needed)
   - EncCert: Used for SM2 public-key encryption in SM2-KEM encapsulation
   - Both must be present in IKE_INTERMEDIATE #1 for sm2-kem negotiation to proceed

4. **Fragmentation (RFC 7383)**:
   - Must be enabled for large certificates/multi-round intermediates
   - Test with TC-HS-001, TC-HS-002 to ensure proper reassembly

5. **ML-DSA-65 Availability**:
   - If not in strongSwan main branch, use upstream patch/branch or implement plugin
   - Must support standard PKIX certificate encoding with ML-DSA OID
   - Signature verification in IKE_AUTH is critical — failure = connection denied

6. **Logging for Verification**:
   - Always enable `charon --debug` or equivalent for test execution
   - Capture logs to `tests/data/logs/TC-*.log` for each test case
   - Key markers: `CERT payload`, `KE group=65001`, `SKEYSEED(1)`, `SKEYSEED(2)`, `IKE_AUTH`, `IntAuth`

## References

- **Protocol**: RFC 7296 (IKEv2), RFC 9242 (IKE_INTERMEDIATE), RFC 9370 (ADDKE), RFC 7383 (Fragmentation)
- **PQC**: FIPS 203 (ML-KEM), FIPS 204 (ML-DSA)
- **Chinese Crypto**: GB/T 35276-2017, GM/T 0022-2023 (SM2/SM3/SM4)
- **Implementation Baseline**: strongSwan 6.0+, GMSSL 3.1.3
- **Test Documentation**: `docs/project/PQGM-IPSec 实施规划与验收.md` (Milestones M1–M5, Test Cases)
