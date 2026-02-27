# PQGM-IPSec（Experimental）

本项目基于 **strongSwan 6.0+** 实现一个“抗量子 + 国密特色”的 IKEv2/IPsec 实验原型（PQGM-IPSec）：
- IKEv2 主流程不变（RFC 7296）
- 使用 IKE_INTERMEDIATE（RFC 9242）+ RFC 9370（ADDKE）实现多重密钥交换
- ADDKE1：**SM2-KEM（私有 group=65001）**，共享秘密 **SK_sm2 = r_i || r_r**（r_len=32B）
- ADDKE2：**ML-KEM-768**
- PRF：**HMAC-SM3**（国密 IPsec 语境）
- IKE_AUTH：强制 **ML-DSA-65**
- 国密算法能力通过 **GMSSL 3.1.3** 以 **gmalg 插件**方式接入

> 说明：证书链验证在实验阶段允许 bypass（模拟通过），但依赖 IntAuth 绑定 + 负例用例保证篡改可检测。

---

## 仓库结构
- `docs/`：两份主文档（Plan/Spec）
- `third_party/`：`strongswan`、`gmssl`（git submodule，锁版本）
- `src/plugins/`：`gmalg`（GMSSL 接入）、`sm2kem`（私有 KE）、`mldsa`（若需自实现/补丁）
- `docker/`：双容器测试环境（先 Docker，后双机）
- `tests/data/`：验收证据（pcap/log/config snapshot）
- `src/patches/strongswan/`：必要的强制补丁（按序 apply）

---

## 快速开始
