# PQGM-IPSec 实施规划与验收

版本：v1 
日期：2026-2-27  
代码管理：Git + GitHub（必须）  
实现平台：strongSwan 6.0+（实验原型）  
国密密码库：GMSSL 3.1.3（底层），以插件形式集成（gmalg）  
协议依据：RFC 7296 / RFC 9242 / RFC 9370 / RFC 7383  
PQC：ML-KEM（FIPS 203）  
认证：ML-DSA-65（FIPS 204）  
国密：SM2/SM3/SM4（GB/T 35276-2017 等），工程语境参考 GM/T 0022-2023  
PRF：HMAC-SM3（按 GM/T 0022-2023：PRF(key,msg)=HMAC(key,msg)，HMAC 基于 SM3）

---

## 1. 项目目标（Goal）
在保持 IKEv2 主流程（IKE_SA_INIT / IKE_AUTH）不变的前提下：
1) 固定插入 3 轮 IKE_INTERMEDIATE；  
2) 按 RFC 9370 执行两次 ADDKE：ADDKE1=SM2-KEM（私有组），ADDKE2=ML-KEM-768；  
3) 双证书（SignCert/EncCert）在中间交换分发；SM2-KEM 使用 EncCert 完成一往返双向封装；  
4) IKE_AUTH 强制使用 PQ 签名认证（ML-DSA-65），并将 intermediate 通过 IntAuth 思路绑定进 AUTH；  
5) 测试先 Docker 双端互通，后双机部署验证。

---

## 2. strongSwan 6.0+ 现成能力说明（减少重复开发）
下列能力在 strongSwan 6.0+ 已具备（无需从零实现，按配置/对接使用）：
- IKE_INTERMEDIATE（RFC 9242）承载中间交换；（strongSwan6.0+ 已实现）
- Multiple Key Exchanges（RFC 9370，ADDKE 框架）；（strongSwan6.0+ 已实现）
- IKE 分片（RFC 7383）；（strongSwan6.0+ 已实现）
- ML-KEM（插件/后端支持方式）；（strongSwan6.0+ 已实现）

注意：PQ 签名（ML-DSA）在主线不一定默认可用，需引入上游分支/补丁或自实现插件（见 M4）。

---

## 3. 范围（Scope）
### 3.1 必做（MUST）
- 协议：3 个 IKE_INTERMEDIATE + ADDKE1(SM2-KEM) + ADDKE2(ML-KEM-768) + IKE_AUTH(ML-DSA-65)。
- PRF：强制使用 **HMAC-SM3**（GM/T 0022-2023 定义），用于 RFC 9370 密钥更新链中的 prf/prf+。
- 国密：以 GMSSL 3.1.3 为底层，实现 gmalg 插件补齐 strongSwan 的 SM2/SM3/SM4（至少满足本项目所需接口：HMAC-SM3、SM2-KEM 所需的 SM2 公钥加密/解密、证书解析/用途分类所需能力）。
- 配置：IKE 配置中新增字段指定 SignCert/EncCert 的路径/标志（swanctl.conf 扩展）。
- 证书验证：实验阶段“模拟验证通过”（bypass/accept），但必须保留接口与日志，便于后续切换为真实验证。
- GitHub 管理：里程碑、Issue、PR 证据路径强约束（见第 11 节）。
- 测试：Docker 通过后再双机复现。

### 3.2 不做（Out of Scope）
- 私有 Transform ID 的通用互通（只保证本实验两端互通）。
- 生产级 CA/证书链运营与完整合规验证。
- 生产级 DoS 防护增强（可记录风险但不作为必交付）。

---

## 4. 固定握手时序（3 个 IKE_INTERMEDIATE）
> 说明：证书在 ML-KEM 前发送（更简单）。SM2-KEM 共享秘密 SK_sm2 采用拼接，不做 KDF。
```
IKE_SA_INIT:
I -> R: SA(主KE=x25519, ADDKE1=sm2-kem[priv], ADDKE2=ml-kem-768, PRF=HMAC-SM3), KEi, Ni, N(INTERMEDIATE_SUPPORTED)
R -> I: SA(...), KEr, Nr, N(INTERMEDIATE_SUPPORTED)

IKE_INTERMEDIATE #1（双证书分发，仅数据，不更新密钥）:
I -> R: SK { CERT(SignCert_i), CERT(EncCert_i), [CERTREQ] }
R -> I: SK { CERT(SignCert_r), CERT(EncCert_r) }

IKE_INTERMEDIATE #2（ADDKE1 = SM2-KEM，更新一次密钥）:
I -> R: SK { KEi(1)[sm2-kem]=ct_i }
R -> I: SK { KEr(1)[sm2-kem]=ct_r }
=> r_len=PRF输出长度=32B（HMAC-SM3）
SK(1)=SK_sm2 = r_i||r_r（64B）
更新 SKEYSEED(1), SK_*(1)

IKE_INTERMEDIATE #3（ADDKE2 = ML-KEM-768，更新二次密钥）:
I -> R: SK { KEi(2)[ml-kem-768] }
R -> I: SK { KEr(2)[ml-kem-768] }
=> SK(2)=mlkem_ss
更新 SKEYSEED(2), SK_*(2)

IKE_AUTH（强制 ML-DSA-65 + IntAuth 绑定）:
I -> R: SK { IDi, CERT(ML-DSA-65证书), AUTH(ML-DSA-65签名), SA, TSi, TSr }
R -> I: SK { IDr, CERT(ML-DSA-65证书), AUTH(ML-DSA-65签名), SA, TSi, TSr }
```

---

## 5. 里程碑（Milestones）——按“最小可验收”推进
### M1：Docker 基线 + 3 轮 intermediate 框架（2–4 天）
- 重点：启用/验证 intermediate 与 RFC 9370 框架（strongSwan6.0+ 已实现），先跑通“空 intermediate”。
- 交付：TC-HS-000 通过（pcap+日志+配置）。

### M2：国密能力接入（GMSSL + gmalg 插件）（5–10 天）
- 重点：补齐至少：HMAC-SM3（PRF）、SM2 公钥加密/解密（用于 KEM ct）、SM3 哈希（如需）。
- 交付：gmalg 可加载；最小自测通过（接口正确）。

### M3：SM2-KEM 私有 KE method + 双证书配置扩展（5–10 天）
- 重点：实现 sm2-kem 私有 group=65001 的 KE payload 处理；扩展 swanctl.conf 支持 sign_cert / enc_cert 路径。
- 交付：TC-HS-001 通过（ADDKE1=SM2-KEM + 密钥更新一次）。

### M4：ADDKE2=ML-KEM + IKE_AUTH 强制 ML-DSA-65（5–15 天）
- 重点：ML-KEM 使用 strongSwan6.0+ 已实现能力；ML-DSA-65 通过上游分支/补丁或插件接入。
- 交付：TC-HS-002 + TC-AUTH-001 通过。

### M5：双机部署 + 评估（3–7 天）
- 重点：把 Docker 通过配置迁移到两台真实机器；输出评估指标。
- 交付：TC-EVAL-001 指标表 + 复现指南。

---

## 6. 验收标准（Definition of Done）
必须同时满足：
1) 功能：TC-HS-001、TC-HS-002、TC-AUTH-001 全通过；
2) 负例：TC-NEG-001、TC-NEG-002 全通过（能失败且失败点正确）；
3) 证据：每个 TC 都有 pcap + charon 日志 + 配置快照；
4) 可复现：Docker 一键复跑成功；双机复跑成功。

---

## 7. 测试策略（先 Docker 后双机）
### 7.1 Docker 阶段（必须）
- docker-compose 启两个容器（init/responder），同网段。
- 每个用例产出：pcapng、charon.log、swanctl.conf 快照。

### 7.2 双机阶段（必须）
- 两台 Linux 主机，静态路由/直连均可。
- 复现实验：同样的 TC 用例集复跑，结果一致性检查。

---

## 8. 测试用例（最少集合）
- TC-HS-000：仅 3 轮 intermediate 框架可跑通（不做真实 KEM），用于证明流程正确。
- TC-HS-001：双证书分发 + ADDKE1(SM2-KEM) 成功；发生一次密钥更新（PRF=HMAC-SM3）。
- TC-HS-002：在 TC-HS-001 基础上加入 ADDKE2(ML-KEM) 成功；发生第二次密钥更新。
- TC-AUTH-001：IKE_AUTH 强制 ML-DSA-65 成功；更换证书/算法应失败。
- TC-NEG-001：篡改 intermediate#2 的 ct_i/ct_r => IKE_AUTH 失败。
- TC-NEG-002：篡改 intermediate#1 的 EncCert（替换）=> IKE_AUTH 失败。
- TC-EVAL-001：输出：握手总时延、CPU 时间、报文大小/分片次数、失败重试统计。

---

## 9. 配置扩展（必须交付）
swanctl.conf 新增字段（字段名以实现为准，但语义必须一致）：
- local.sign_cert：签名证书路径
- local.enc_cert：加密证书路径（SM2-KEM 使用）
并明确：SM2-KEM 必须使用 EncCert 公钥。

---

## 10. 证书验证策略（实验简化）
- V1.3 阶段：证书链验证“模拟通过”（accept-all 或最小检查）；
- 仍需记录日志：证书解析成功/用途分类成功/是否 bypass；
- 风险：易被中间人替换证书，必须依赖 IntAuth 绑定与用例 TC-NEG-002 验证可检测篡改。

---

## 11. Git/GitHub 管理规范（必须）
- main：可运行稳定版本；dev：日常集成；feature/*：功能分支（gmalg、sm2-kem、mldsa-auth 等）
- 每个里程碑用 GitHub Milestone 管理；每个 TC 对应一个 Issue（含验收证据路径）
- PR 必须附：关联 Issue、测试用例结果、pcap/日志链接（仓库内相对路径）

---

## 12. 交付物（Artifacts）
- docs/PQGM-IPSec-Plan-V1.3.md（本文件）
- docs/PQGM-IKEv2-Spec-V1.3.md（协议实现规范）
- pcaps/TC-*.pcapng
- logs/TC-*.log
- configs/TC-*.conf
- evaluation/metrics.csv
- docker-compose.yml + README（Docker 复现）
