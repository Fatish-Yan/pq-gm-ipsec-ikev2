# PQGM-IKEv2 协议实现规范

版本：v1  
状态：Experimental（实验性扩展）  
基线：RFC 7296 / RFC 9242 / RFC 9370 / RFC 7383  
PQC：ML-KEM（FIPS 203）  
认证：ML-DSA-65（FIPS 204）  
国密：SM2/SM3/SM4（GB/T 35276-2017 等），底层 GMSSL 3.1.3  
PRF：HMAC-SM3（按 GM/T 0022-2023：PRF(key,msg)=HMAC(key,msg)，HMAC 基于 SM3；输出 256bit）

---

## 1. 术语
- 主 KE：IKE_SA_INIT 的经典 DH（默认 x25519）
- ADDKE n：RFC 9370 第 n 个额外密钥交换
- SK(n)：第 n 个 ADDKE 导出的共享秘密
- SignCert / EncCert：双证书（签名/加密）
- sm2-kem：本文定义的私有 Key Exchange Method（Transform Type 4 私有 group）

---

## 2. 关键决策（与实现对齐）
- IKE_INTERMEDIATE：固定 3 轮
- ADDKE 顺序：ADDKE1=SM2-KEM；ADDKE2=ML-KEM-768
- 证书分发：在 ML-KEM 前（intermediate#1）
- PRF：HMAC-SM3（输出 32B）
- SM2-KEM 共享秘密：SK_sm2 = r_i || r_r（不做 KDF）
- IKE_AUTH：强制 ML-DSA-65 签名认证
- 证书链验证：实验阶段 bypass（模拟通过）

---

## 3. 协商（Negotiation）
### 3.1 SA Proposal（MUST）
IKE_SA_INIT 的 SAi1/SAr1 必须包含：
- 主 KE：x25519
- ADDKE1：sm2-kem（私有 group）
- ADDKE2：ml-kem-768
- PRF：HMAC-SM3
并携带 N(INTERMEDIATE_EXCHANGE_SUPPORTED)。

### 3.2 私有 Transform ID（MUST）
- Transform Type：4（DH Group）
- 私有 group ID：65001（保持）
- 实现/配置命名：sm2kem

---

## 4. 报文流程（固定 3 个 IKE_INTERMEDIATE）
### 4.1 IKE_SA_INIT（MUST）
交换：SA（含 ADDKE 列表与 PRF）、KEi/KEr（主 KE）、Ni/Nr、N(INTERMEDIATE_SUPPORTED)。

### 4.2 IKE_INTERMEDIATE #1：双证书分发（MUST，不更新密钥）
- I -> R：SK { CERT(SignCert_i), CERT(EncCert_i), [CERTREQ] }
- R -> I：SK { CERT(SignCert_r), CERT(EncCert_r) }
约束：
- 不携带 KE payload；
- 不触发 RFC 9370 密钥更新（沿用 IKE_SA_INIT 派生的 SK_*）。

### 4.3 IKE_INTERMEDIATE #2：ADDKE1 = SM2-KEM（MUST）
#### 4.3.1 r_i / r_r 长度（MUST）
- PRF=HMAC-SM3，输出长度固定为 256bit = 32B  
- r_len = 32B  
- r_i、r_r 均为 32B  
- SK(1) = SK_sm2 = r_i || r_r，长度为 64B  
- 拼接顺序固定：先 r_i 后 r_r

#### 4.3.2 一往返“双向封装”（MUST）
- Initiator：
  - 生成 r_i（32B）
  - 使用 Responder 的 EncCert 公钥封装/加密得到 ct_i
  - 发送：SK { KEi(1)[group=sm2-kem]=ct_i }
- Responder：
  - 解封装/解密得到 r_i
  - 生成 r_r（32B）
  - 使用 Initiator 的 EncCert 公钥封装/加密得到 ct_r
  - 发送：SK { KEr(1)[group=sm2-kem]=ct_r }

完成后按第 6 节更新密钥，得到 SKEYSEED(1)、SK_*(1)。

### 4.4 IKE_INTERMEDIATE #3：ADDKE2 = ML-KEM-768（MUST）
- I -> R：SK { KEi(2)[group=ml-kem-768] }
- R -> I：SK { KEr(2)[group=ml-kem-768] }
- SK(2) = mlkem_ss（由 ML-KEM 解封装得到）

完成后按第 6 节再次更新密钥，得到 SKEYSEED(2)、SK_*(2)。

### 4.5 IKE_AUTH：强制 ML-DSA-65 + IntAuth 绑定（MUST）
- I -> R：SK { IDi, CERT(ML-DSA-65证书), AUTH(ML-DSA-65签名), SA, TSi, TSr }
- R -> I：SK { IDr, CERT(ML-DSA-65证书), AUTH(ML-DSA-65签名), SA, TSi, TSr }

要求：
- AUTH 必须使用 ML-DSA-65；
- 必须将所有 intermediate 的关键内容纳入 AUTH 绑定（按 RFC 9242 的 IntAuth 思路），确保任意篡改导致认证失败；
- 若主线 strongSwan 无 ML-DSA：允许引入上游分支/补丁或新增插件提供 signer/验证能力（推荐插件化）。

---

## 5. Payload 编码约定（Minimal Contract）
### 5.1 CERT（MUST）
- 使用标准 CERT payload；
- 必须能区分/定位 EncCert 公钥用于 SM2-KEM；
- 实验阶段证书链验证 bypass，但证书解析与用途分类必须成功（否则失败）。

### 5.2 KE（MUST）
- Group：
  - sm2-kem：65001
  - ml-kem-768：按 strongSwan 实现映射
- KE Data：
  - sm2-kem：ct_i / ct_r
  - ml-kem：按实现要求的 KEM 数据

---

## 6. 密钥更新（RFC 9370 链式更新，MUST）
当执行第 n 个 ADDKE 得到 SK(n) 后更新：
- SKEYSEED(n) = prf(SK_d(n-1), SK(n) | Ni | Nr)
- SK_* = prf+(SKEYSEED(n), Ni | Nr | SPIi | SPIr)

其中：
- prf / prf+ 均使用 PRF=HMAC-SM3
- SK(1)=r_i||r_r（64B）
- SK(2)=mlkem_ss

---

## 7. 降级与失败策略（MUST）
- 不允许降级：任一 MUST 能力协商失败 => 本次建链失败；
- 任一 intermediate 被篡改 => IKE_AUTH 必须失败（由 IntAuth/密钥链保证）。

---

## 8. 配置契约（swanctl.conf 扩展，MUST）
新增字段（字段名可实现自定，但语义必须一致）：
- local.sign_cert：签名证书路径
- local.enc_cert：加密证书路径（SM2-KEM 使用）
约束：
- 启用 sm2-kem 时，local.enc_cert 必须存在；
- 对端 EncCert 必须可获取（来自 intermediate#1 的 CERT），否则失败。

---

## 9. 分片（MUST）
必须启用 RFC 7383（IKEv2 Message Fragmentation），并在测试中覆盖大证书/多轮 intermediate 场景。

---

## 10. 实验日志（SHOULD）
- 打印每轮 ADDKE 编号与 group；
- 打印 SKEYSEED(1)/SKEYSEED(2) 更新发生的标记；
- 打印 EncCert/SignCert 选择结果；
- 明确记录“证书验证 bypass 已启用”（安全风险可追溯）。