# Factorio AI 伙伴

<p align="right"><a href="README.md">English</a> · <b>简体中文</b></p>

由 Claude 通过 **MCP 工具经 RCON** 驱动的 **Factorio 2.x**(含 Space Age)AI 伙伴。生成一队
机器人伙伴 —— 或托管你自己的角色 —— 它们会采矿、合成、建造、战斗、跑物流,并搭建**完整的工厂**。
整个团队还能在**无人值守的专用服务器上自主运行**,因此 Claude 既能游玩,也能自我测试。

> **v0.45.1** · 100 个 RCON 命令与 99 个 MCP 工具保持 **1:1** 对应 · 完整历史见
> [CHANGELOG.md](CHANGELOG.md)。

---

## 目录

- [功能特性](#功能特性)
- [工作原理](#工作原理)
- [环境要求](#环境要求)
- [安装](#安装)
  - [1. 克隆并安装依赖](#1-克隆并安装依赖)
  - [2. 安装 Factorio Mod](#2-安装-factorio-mod)
  - [3. 启用 RCON](#3-启用-rcon)
  - [4. 托管游戏](#4-托管游戏)
  - [5. 将 MCP 服务器接入 Claude](#5-将-mcp-服务器接入-claude)
- [使用](#使用)
  - [游戏内聊天命令](#游戏内聊天命令)
  - [响应循环](#响应循环)
  - [与团队对话](#与团队对话)
  - [Headless / 完全自主](#headless--完全自主)
- [工具参考](#工具参考)
- [开发](#开发)
- [故障排查](#故障排查)
- [版本管理](#版本管理)
- [致谢与许可](#致谢与许可)

---

## 功能特性

三大支柱:

### 支柱一 —— 自主殖民地(工厂医生 → 整座工厂)
- **诊断**瓶颈与"死机"问题:断电 / 空转 / 缺燃料(`factory_analyze`、`factory_graph`)。
- **治疗**:放置机器、设置配方、接入电力、为燃烧型设备加燃料,并连好 I/O 机械臂与箱子
  (`factory_fix`、`factory_wire`)。
- **建造**:为任意配方搭建完整可用的**工作站**、按比例配置的机器**机组**,并铺设**传送带**
  (`build_station`、`build_bank`、`belt_connect`、`belt_link`)。
- **`auto_factory <item>`** 沿配方树递归,一条命令搭建*整条*产业链,按目标产率自动定尺,
  并自动分配运输工(`production_plan`、`recipe_deps`)。

### 支柱二 —— 涌现式协作
- **计划**以并行的**依赖 DAG** 运行;团队自行把每一步分配给最合适的空闲伙伴
  (最近 / 按专长 / 按能力感知)(`plan_create`、`plan_status`、`plan_run`)。
- **常驻角色**:守卫、加油工、维护工、**运输工**(持续 A→B 物流)、**侦察兵**(持续探图)
  (`assign_role`、`assign_courier`、`roles`)。
- **任务板预定**防止两个伙伴抢同一处资源(`reserve`、`release`、`reservations`)。
- 通过 `set_specialty` 进行**团队专长划分**(矿工 / 建造 / 运输 / 战斗)。

### 支柱三 —— 懂你的伙伴
- **持久化命名地点**(显示为地图图钉),以及跨存档保留的偏好和备注
  (`memory_remember`、`memory_recall`、`memory_forget`、`memory_goto`)。
- **自动学习地图**:记住矿脉与最近的威胁(`survey_remember`、`memory_nearest`)。

### 核心能力
- **伙伴管理**:生成 / 列表 / 状态 / 库存 / 血量 / 消失;通过 `attach_player` / `detach_player`
  托管玩家自己的角色。
- **导航**:寻路 `move_to`、`move_follow`、`move_stop`。
- **资源与合成**:查找/列举/采集资源、拾取/合成物品、查询配方(`resource_*`、`item_*`),
  以及后台技能 `resource_mine_until` 和 `combat_until`。
- **建造与蓝图**:放置/移除/旋转/加燃料/装填机器、设置配方、按蓝图批量建造
  (`building_*`、`blueprint_*`)。
- **物流**:`haul` 与 `refuel` 队列。
- **战斗团队**:攻击 / 防御 / 逃跑 / 巡逻 / 清巢 / 维修 / `wololo`(`action_*`、`combat_until`)。
- **科技研究**:读取/设置当前研究、进度、前置链(`research_*`、`tech_path`)。
- **世界感知**:`world_scan`、`world_nearest`、`world_enemies`、`world_survey`,以及一键
  `overview`。

---

## 工作原理

```
Claude  ──MCP 工具──►  MCP 服务器 (Bun, src/index.ts)  ──RCON──►  Factorio (ai-companion mod)
   ▲                                                                       │
   └────────────────── 聊天消息 / 状态(RCON 轮询) ◄───────────────────────┘
```

- **Mod**(`factorio-mod/`)暴露约 100 个 RCON 命令并捕获 `/fac` 聊天。
- **MCP 服务器**(`src/`)把每个命令封装为类型安全、经校验的 MCP 工具(与 Lua 侧保持 1:1)。
- **单个编排器**管理所有伙伴(id = 0, 1, 2, …),没有额外的子代理。

---

## 环境要求

- [Factorio](https://factorio.com) **2.x** —— 必须**以多人模式托管**(即便单人游玩,RCON 也只在
  托管时可用),或运行 **headless**(见下文)。
- [Bun](https://bun.sh)(MCP 服务器与脚本的运行时)。
- 一个 MCP 客户端(如 Claude Desktop / Claude Code)来驱动工具。

---

## 安装

### 1. 克隆并安装依赖

```bash
git clone https://github.com/lveillard/factorio-ai-companion.git
cd factorio-ai-companion
bun install
```

### 2. 安装 Factorio Mod

将 `factorio-mod/` 的内容复制到 Factorio 的 mods 目录下,命名为 `ai-companion` 文件夹。

**Windows(Git Bash / PowerShell):**
```bash
cp -r factorio-mod/* "$APPDATA/Factorio/mods/ai-companion/"
```

**Linux:**
```bash
cp -r factorio-mod ~/.factorio/mods/ai-companion
```

**macOS:**
```bash
cp -r factorio-mod ~/Library/Application\ Support/factorio/mods/ai-companion
```

随后在 Factorio 中:**主菜单 → Mods → 启用 "AI Companion" → 重启**。每次更新 mod 文件后都需重启。

### 3. 启用 RCON

将以下内容加入 `config.ini`(无需放在任何小节下)。Windows 上位于
`%APPDATA%\Factorio\config\config.ini`:

```ini
local-rcon-socket=127.0.0.1:34198
local-rcon-password=factorio
```

它们与 MCP 服务器默认值一致(`FACTORIO_HOST=127.0.0.1`、`FACTORIO_RCON_PORT=34198`、
`FACTORIO_RCON_PASSWORD=factorio`)。若更改了端口或密码,可通过环境变量覆盖。

### 4. 托管游戏

**多人游戏 → 创建新游戏**(或**加载游戏**)。RCON 仅在托管时生效 —— 单人单机模式**不会**接受
RCON 连接。

### 5. 将 MCP 服务器接入 Claude

仓库自带可直接使用的 `.mcp.json`:

```json
{
  "mcpServers": {
    "factorio-companion": {
      "command": "bun",
      "args": ["run", "src/index.ts"],
      "env": {
        "FACTORIO_HOST": "127.0.0.1",
        "FACTORIO_RCON_PORT": "34198",
        "FACTORIO_RCON_PASSWORD": "factorio"
      }
    }
  }
}
```

请使用与 `config.ini` 中相同的主机/端口/密码。

---

## 使用

### 游戏内聊天命令

```
/fac <msg>          与编排器对话(companionId 0)
/fac <id> <msg>     与指定伙伴对话
/fac spawn [n]      请求生成(可选 n 个伙伴)
/fac list           列出伙伴
/fac kill [id]      杀死伙伴
```

示例:`/fac 1 mina hierro` → 伙伴 1 去采铁。

### 响应循环

单个编排器管理所有伙伴。用以下命令启动:

```bash
bun run src/reactive-all.ts
```

它会轮询 RCON 获取新的 `/fac` 消息,交给 Claude,Claude 再用 MCP 工具调用作出响应。典型循环:

1. 运行响应循环(它会阻塞等待消息)。
2. 解析收到的 JSON:`[{companionId, player, message, tick}, ...]`。
3. 用 MCP 工具响应(如 `chat_say`、`resource_mine_until`)。
4. 循环。

### 与团队对话

```
玩家(游戏内): /fac 1 mina hierro

伙伴 1:
  - chat_say(companionId: 1, message: "Voy a minar hierro")
  - resource_mine_until(companionId: 1, resource: "iron-ore", quantity: 50)
```

**通过 MCP 生成伙伴:**
```
companion_spawn(companionId: 1)
companion_spawn(companionId: 2)
```

### Headless / 完全自主

伙伴可在无玩家时生成(回退到地图出生点),因此整个团队能在无人连接的专用服务器上经 RCON 运行 ——
Claude 既能游玩,也能自测。

```bash
bun run headless    # 若存档不存在则创建,然后启动专用服务器(开启 RCON、关闭 auto_pause)
bun run smoke       # 经 RCON 的实时回归测试 —— 覆盖每个命令(PASS/FAIL/SKIP)

bun scripts/rcon.ts "fac_overview"                       # 一键态势感知
bun scripts/rcon.ts "fac_auto_factory 1 iron-gear-wheel" # 一键工厂
```

人类可选择 **多人游戏 → 连接** 到 `127.0.0.1` 观战;机器人并不依赖此连接。

> **注意:** Factorio 禁止运行时 `require()`(所有 require 都在文件加载时完成)。请用单引号包裹的
> shell 字符串发送计划 JSON,并注意生成后紧接着的第一条 `/silent-command` 偶尔会失败 —— 重试即可。

---

## 工具参考

所有工具位于 `src/mcp/tools.ts`,并与 Lua RCON 命令 1:1 校验。

| 类别 | 工具 |
| --- | --- |
| **聊天** | `chat_get`、`chat_say` |
| **伙伴** | `companion_spawn`、`companion_list`、`companion_status`、`companion_position`、`companion_inventory`、`companion_health`、`companion_disappear`、`companion_stop`、`companion_stop_all`、`set_specialty`、`attach_player`、`detach_player` |
| **移动** | `move_to`、`move_follow`、`move_stop` |
| **资源** | `resource_nearest`、`resource_list`、`resource_mine`、`resource_mine_status`、`resource_mine_stop`、`resource_mine_until`(技能) |
| **物品 / 合成** | `item_pick`、`item_craft`、`item_craft_start`、`item_craft_status`、`item_craft_stop`、`item_recipes` |
| **建筑** | `building_place`、`building_place_start`、`building_place_status`、`building_remove`、`building_can_place`、`building_info`、`building_rotate`、`building_recipe`、`building_fuel`、`building_fill`、`building_empty` |
| **蓝图 / 传送带** | `blueprint_place`、`blueprint_line`、`blueprint_status`、`blueprint_stop`、`belt_connect`、`belt_link` |
| **物流** | `haul`、`haul_status`、`haul_stop`、`refuel`、`refuel_status`、`refuel_stop` |
| **战斗** | `action_attack`、`action_attack_start`、`action_attack_status`、`action_attack_stop`、`action_defend`、`action_flee`、`action_patrol`、`action_nest_clear`、`action_repair`、`action_wololo`、`combat_until`(技能) |
| **工厂医生(支柱一)** | `factory_analyze`、`factory_graph`、`factory_fix`、`factory_wire`、`build_station`、`build_bank`、`auto_factory`、`production_plan`、`recipe_deps` |
| **编排(支柱二)** | `reserve`、`release`、`reservations`、`assign_role`、`assign_courier`、`clear_role`、`roles` |
| **计划(支柱二)** | `plan_create`、`plan_status`、`plan_step_done`、`plan_run` |
| **记忆(支柱三)** | `memory_remember`、`memory_recall`、`memory_forget`、`memory_list`、`memory_goto`、`memory_nearest`、`survey_remember` |
| **研究** | `research_get`、`research_set`、`research_progress`、`tech_path` |
| **世界 / 状态** | `world_scan`、`world_nearest`、`world_enemies`、`world_survey`、`overview`、`session_status`、`context_clear`、`context_check`、`version`、`help` |

---

## 开发

```bash
bun run check    # validate-tools(MCP↔Lua 1:1)+ lint-lua-api(defines.* 对照内置 API 规范)
bun run smoke    # 实时回归套件(生成并武装一个临时测试伙伴,真实建造)
bun run gen-api  # 从 runtime-api dump 重新生成 reference/factorio-api-slim.json
```

**lefthook** 预提交钩子会运行 `bun run check`。常用单条命令:

```bash
bun scripts/rcon.ts "<fac_command>"   # 发送一条原始 RCON 命令
bun run scripts/validate-tools.ts     # 99 个 MCP 工具须映射到 100 个 RCON 命令
```

---

## 故障排查

| 现象 | 原因 / 解决 |
| --- | --- |
| **连接被拒绝** | Factorio 未以多人模式托管(RCON 关闭)。请托管游戏。 |
| **未知命令 `/fac`** | Mod 未加载 —— 在 Mods 中启用 "AI Companion" 并重启。 |
| **连续 3 次以上 ECONNREFUSED** | Factorio 断开;停止响应循环并重启。 |
| **RCON 认证失败** | `config.ini` 的 socket/密码与 MCP 环境变量不一致。 |
| **生成后首个动作失败** | 生成后的第一条 `/silent-command` 偶尔会失败 —— 重试。 |

---

## 版本管理

Mod 版本号位于 [`factorio-mod/info.json`](factorio-mod/info.json);分组、易读的历史见
[CHANGELOG.md](CHANGELOG.md)。

---

## 致谢与许可

灵感来自
[Factorio Learning Environment](https://github.com/JackHopkins/factorio-learning-environment)。
许可条款见 [LICENSE](LICENSE)。
