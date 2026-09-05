# Unique Reroll (暗黑破坏神 II 1.14d 暗金装备重 Roll 特色插件)

## 1. 插件概述

`Unique_reroll` 是专为现代化暗黑破坏神 II 1.14d 服务端定制开发的纯服务端注入插件（Feature DLL）。

### 核心功能
- **暗金装备方块重 Roll**：玩家将满足条件的暗金装备放入赫拉迪克方块，搭配 INI 中配置的两种材料（默认 `26# 符文 Vex` + `解毒药剂 Antidote Potion`），点击合成按钮（Transmute）即可重新随机抽取该暗金装备的所有变量数值。
- **严格继承物品等级（ilvl）**：重 roll 后的暗金装备严格保持原物品的 `dwItemLevel`（例如 88 级巴尔掉落的暗金重 roll 后仍为 88 级）。
- **底材基础防御重 Roll**：防具底材的基础防御（Base Defense）参与随机 roll 点，在 $[minac, maxac]$ 范围内重新生成，完美实现真正的全变量重置。
- **孔数分类处理与镶嵌物智能保留**：
  - **拉苏克（Larzuk）/ SOJ 任务打孔**：装备天生无孔，属于任务打孔（固定 1 孔，非变量），重 roll 时强制保留这 1 孔，内部镶嵌物 100% 完整保留。
  - **天然变量孔暗金**（如盗墓者 1~3 孔、年纪之冠 1~2 孔、巨骷髅 1~2 孔、天堂之光 1~3 孔、符文大师 3~5 孔等）：孔数参与原生重新 roll 点。若新 roll 出的孔数小于原镶嵌物数量，**严格按位保留前 $N_{new}$ 个镶嵌物**，超出孔位的后部镶嵌物安全舍弃消失（如 3 孔盗墓者镶嵌 3 颗宝石，新 roll 出 1 孔则仅保留第 1 颗宝石，后 2 颗消失）；若新孔数大于等于原镶嵌物数量，则所有镶嵌物完整保留。
- **无形（Ethereal）与个性化签名（Anya）完整保持**：无形装备重 roll 后保持无形，带有安雅个性化名字签名的装备重 roll 后完整保留签名。
- **全暗金类型覆盖与任务道具安全拦截**：支持暗金武器、防具、戒指、项链、护身符（毁灭/火炬/基德）以及珠宝（彩虹刻面）；自动识别并排除所有任务暗金与任务道具（如蛇发项链 `vip`、王者之杖 `msf`、赫拉迪克法杖 `hst`、地狱铁锤 `hfh`、克林姆意志 `qf1`/`qf2` 以及方块自身 `box`）。
- **绿色系统公告提示**：重 roll 成功后，服务器会向该玩家客户端发送一条绿色的英文公告提示（例如：`[Unique Reroll] Successfully rerolled Harlequin Crest!`），并播放方块合成声效。
- **配方材料格式对齐 `cubemain.txt`**：INI 配置项直接采用 3~4 字符的原始物品代码（如 `r26`、`yps`、`tbk`、`gpv` 等），支持热重载。
- **纯服务端实现**：遵循 MODDING 规范，客户端无需安装任何补丁或修改，原版客户端即可完美兼容体验。
- **彻底绕过原生 Moddata 限制**：纯内存拦截，不依赖外部 `cubemain.txt`，彻底解决服务端启用 moddata 或挂载 `-direct -txt` 参数不生效的顽疾，同时彻底根除原生 `useitem` 无法重 roll 与 `usetype` 变 1 级亮金手斧的 Bug。

---

## 2. 目录结构说明

```
release/
└── Unique_reroll/
    ├── bin/                           # 预编译产物发布目录（开箱即用）
    │   ├── Unique_reroll.dll          # 插件动态链接库 (x86 PE)
    │   ├── Unique_reroll.pdb          # 调试符号文件
    │   └── Unique_reroll.ini          # 运行时配置文件
    ├── src/                           # 完整源代码目录
    │   ├── main.zig                   # DLLMain 入口及 Packet 0x4F 裸函数拦截注入
    │   ├── reroll.zig                 # 重Roll核心逻辑、孔数判定、镶嵌物迁移与过滤
    │   ├── d2engine.zig               # 1.14d 引擎内存地址、数据结构与底层汇编包装
    │   └── config.zig                 # INI 配置文件读取、物品代码解析与热重载
    ├── build.zig                      # Zig 自动化构建工程脚本
    ├── Unique_reroll.ini              # 配置文件模板
    └── README.md                      # 本文档
```

---

## 3. 配置文件详解 (`Unique_reroll.ini`)

配置文件采用标准 Windows INI 格式，可在运行时随时修改并实时生效。

```ini
[Settings]
; 是否启用该插件 (1=启用, 0=关闭)
Enable=1

; 材料 1 物品代码（严格对齐 cubemain.txt 格式）
; 默认：r26 代表 26# 符文 伐克斯 (Vex)
Input1=r26

; 材料 2 物品代码（严格对齐 cubemain.txt 格式）
; 默认：yps 代表 解毒药剂 (Antidote Potion)
Input2=yps

; 是否开启详细调试日志 (1=开启，日志输出至 Unique_reroll.log; 0=关闭)
DebugLog=1
```

### 3.1 常用物品代码速查表（对齐 `cubemain.txt`）

| 物品类别 | 常用代码示例 | 对应中文名称 |
| :--- | :--- | :--- |
| **高级符文** | `r20` ~ `r33` | 20# 蓝姆 (Lem) 到 33# 佐德 (Zod)（如 `r24`=24# 伊司特, `r26`=26# 伐克斯） |
| **低级符文** | `r01` ~ `r19` | 1# 艾尔 (El) 到 19# 法尔 (Fal) |
| **功能药剂** | `yps` / `wms` / `vps` | 解毒药剂 (Antidote) / 溶解药剂 (Thawing) / 体力药剂 (Stamina) |
| **回城/辨识** | `tbk` / `ibk` / `tsc` / `isc` | 回城书 / 辨识书 / 回城卷轴 / 辨识卷轴 |
| **完美宝石** | `gpv` / `gpr` / `gpb` / `gpg` / `gpw` / `gpy` / `skz` | 完美紫宝石 / 完美红宝石 / 完美蓝宝石 / 完美绿宝石 / 完美白宝石 / 完美黄宝石 / 完美骷髅 |

- **相同材料判定**：若配置 `Input1=r24` 且 `Input2=r24`，放入 1 件暗金 + 2 枚 24# 符文即可触发。

---

## 4. 核心机制与业务规则

### 4.1 镶嵌物与孔数继承规则

暗黑破坏神 II 中暗金装备的孔数来源分为三类，本插件采取最严谨的分类策略：

1. **天然变量孔数装备**（共 7 件）：
   - `Djinnslayer` (精灵倒戈)：1~2 孔
   - `Tomb Reaver` (盗墓者)：1~3 孔
   - `Runemaster` (符文大师)：3~5 孔
   - `Crown of Ages` (年纪之冠)：1~2 孔
   - `Heaven's Light` (天堂之光)：1~3 孔
   - `Giantskull` (巨骷髅)：1~2 孔
   - `Headhunter's Glory` (猎头人的荣耀)：1~3 孔
   - **重 Roll 规则**：新孔数 $N_{new}$ 参与原生随机抽取。
     - 若 $N_{new} \ge M$（原镶嵌物数）：全部保留。
     - 若 $N_{new} < M$：按顺序仅保留前 $N_{new}$ 个镶嵌物，超出孔位的后部镶嵌物安全销毁舍弃。
2. **拉苏克任务打孔装备**：
   - 装备天生无孔，原装备拥有 1 孔（通过第五幕任务打孔）。
   - **重 Roll 规则**：判定为任务固有孔（非变量），强制在新装备上保留这 1 孔，且原孔内镶嵌物 100% 完整保留。
3. **天然固定孔数装备**（如水魔陷阱 3 孔、刺木 1 孔、黑荆棘 3 孔等）：
   - 随生成器天然生成固定孔数，镶嵌物完整继承。

### 4.2 防御（Base Defense）重 Roll

防具底材的基础防御具有 $[minac, maxac]$ 范围。本插件通过暴雪原生 `SpawnItemWithStruct` 注入新的动态随机种子，使底材基础防御连同暗金专属的 `%ED` 或固定防御加成一同刷新，实现真正的全变量重置。

### 4.3 随机数发生器与变量 Roll 点算法 (PRNG Engine)

插件采用两级紧密结合的随机数架构，既保证外部种子的离散均匀度，又 100% 保持暴雪原厂词缀生成的数学概率：

#### 1. 插件层：双源正交种子生成
物品对象在暗黑2内存中拥有两组独立的 32 位随机数种子：
- **底材种子 (`pItem->dwSeed`)**：专职控制底材的基础防御、基础耐久度等；
- **词缀种子 (`pItem->pUnitData->dwSeed`)**：专职控制 `UniqueItems.txt` 中配置的所有可变魔法属性。

插件在每次玩家点击 Transmute 时，利用黄金分割比常数（Fibonacci/Weyl 步长常数 `0x9E3779B9`）与毫秒级时钟进行双源混合：
```zig
g_seed_counter +%= 0x9E3779B9;
const t_now = GetTickCount();

// 底材种子（控制基础防御等底材变量）
gen.nInitSeed = @as(i32, @bitCast(t_now ^ g_seed_counter));

// 词缀种子（经 LCG 线性同余混合，与底材种子严格统计正交）
gen.nModSeed = @as(i32, @bitCast((t_now *% 1103515245 +% 12345) ^ (g_seed_counter *% 31)));
```
- **黄金分割步长**：保证在 32 位空间内，即便玩家以极高频率连续点击，生成的种子在空间中依然保持完美的发散分布，彻底根除局部聚类与种子重复。
- **正交解耦**：`nInitSeed` 与 `nModSeed` 相互独立，不会因为 roll 到极品底材基础防御而干涉魔法词缀的概率分布。

#### 2. 引擎层：暴雪原生 64 位乘加带进位算法 (64-bit Multiply-With-Carry - `0x0045C390`)
暴雪引擎以 `nModSeed` 为初始低位、以 `0x29A` (666) 为初始高位进位，按 `UniqueItems.txt` 词缀列顺序调用核心 PRNG：
$$\text{temp} = \text{seed.low} \times 0\text{x6AC690C5} + \text{seed.high}$$
$$\text{seed.low} = \text{temp} \ \& \ 0\text{xFFFFFFFF}$$
$$\text{seed.high} = \text{temp} \gg 32$$
在取值区间 $[\text{Min}, \text{Max}]$（跨度 $\text{Range} = \text{Max} - \text{Min} + 1$）内生成均匀分布随机数：
$$\text{Roll} = \text{Min} + (\text{seed.low} \pmod{\text{Range}})$$
每个变量按顺序独立步进一次种子，无任何伪随机保底或偏差，与野外原生掉落暗金的生成纯真随机度完全一致。

### 4.4 暴雪原生合成清理机制与稳定性保障

- **对齐原生材料销毁接口 (`0x0055E000`)**：深度对齐暴雪方块合成主流程（`0x005640B3`），统一调用 `0x0055E000` 封装。该函数会自动获取玩家 `pClient`，发送 0x9D 网络包通知客户端平滑移除原材料图标，随后调用 `0x0055DF10` 从玩家背包链表中安全解挂并释放内存，彻底杜绝了手动调用底层接口引起的断言中断（`halt: assert caller=0x53d044, nLine=0x802`）与“连接中断”闪退。
- **内联汇编寄存器保护**：所有底层引擎封装均显式保护 `ESI`、`EDI`、`EBX` 寄存器并使用立即数传参，消除编译器自动分配寄存器导致的指针覆盖风险。

---

## 5. 部署与安装方法

### 5.1 服务端部署步骤

1. 将 `bin/Unique_reroll.dll` 与 `bin/Unique_reroll.ini` 拷贝至服务器的 Mod 挂载目录：
   ```bash
   # 宿主机挂载目录
   cp Unique_reroll.dll /home/cfwd2/d2mods/
   cp Unique_reroll.ini /home/cfwd2/d2mods/
   ```
2. 触发游戏服务 Pod 滚动重启以载入新 DLL：
   ```bash
   sudo k3s kubectl rollout restart deployment/d2gs-1-14d -n realm
   ```

### 5.2 验证加载状态

检查游戏服务端日志或插件专用日志：
```bash
# 查看插件输出日志
sudo k3s kubectl exec deployment/d2gs-1-14d -n realm -- tail -n 20 /mods/Unique_reroll.log
```
正常加载时会输出类似如下信息：
```
[Unique_reroll] Initializing Unique Reroll Mod...
[Unique_reroll] Config: Enable=true, Input1='r26', Input2='yps', Input1Code=0x20363272, Input2Code=0x20737079
[Unique_reroll] Successfully hooked Packet 0x4F at 0x006E0F90!
```