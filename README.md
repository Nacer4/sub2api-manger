# sub2api-manger

[Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api) 的 **iOS 原生管理员面板**（SwiftUI）。

> ⚠️ sub2api 官方声明：使用可能违反上游服务商条款，仅供学习研究。本项目仅封装其管理端 API，风险与合规责任由使用者自行承担。

## 技术栈

| 层 | 技术 |
|---|---|
| UI | SwiftUI + Swift Charts，`@Observable`（iOS 17+） |
| 网络 | URLSession async/await，自封装 APIClient |
| 凭证 | Keychain（JWT/Refresh Token）+ UserDefaults（服务器配置） |
| 工程 | XcodeGen（`project.yml` 生成 .xcodeproj） |

## 快速开始

```bash
brew install xcodegen   # 或 pip/binary 安装
cd sub2api-manger
xcodegen generate       # 生成 Sub2Admin.xcodeproj
open Sub2Admin.xcodeproj
# Xcode 中 Cmd+R 运行（真机请在 Signing & Capabilities 签名）
```

## 目录结构

```
sub2api-manger/
├── project.yml                  # XcodeGen 工程定义
└── sub2api-admin/
    ├── App/
    │   ├── Sub2AdminApp.swift       # 入口，注入 AppState
    │   ├── AppState.swift           # 全局状态：激活服务器 / 登录态 / APIClient
    │   ├── AppStateHolder.swift     # VM 全局取 client 的入口
    │   └── RootView.swift           # 登录门 + 五 Tab 主界面
    ├── Core/
    │   ├── Networking/
    │   │   ├── APIClient.swift      # 请求核心（认证/刷新/信封解析）
    │   │   └── APIEnvelope.swift    # {code,message,data} 信封 + 分页 + 错误
    │   ├── Models/                  # User/Account/Group/Dashboard/Usage/System
    │   └── Persistence/
    │       ├── TokenStore.swift     # Keychain 封装
    │       └── ServerStore.swift    # 多服务器配置持久化
    ├── Features/
    │   ├── Auth/                    # 登录 + 服务器编辑
    │   ├── Dashboard/               # 仪表盘
    │   ├── Users/                   # 用户列表/详情/余额
    │   ├── Accounts/                # 账号池列表/详情/运维操作
    │   ├── Usage/                   # 使用记录 + 错误请求
    │   └── Settings/                # 设置
    └── DesignSystem/                # StatCard/StatusPill/空态/格式化
```

## 架构说明

**分层**：`App（状态/路由）→ Features（每模块 View + @Observable VM）→ Core（网络/模型/持久化）`。

**API 适配**（对照 sub2api 后端源码 `backend/internal/server/routes/`）：

- 认证双通道：JWT `Authorization: Bearer` 或 Admin Key `x-api-key: admin-…`；401 时自动 `/auth/refresh` 续期一次，失败则要求重新登录
- 统一信封 `{code, message, data}`；分页 `page/page_size/sort_by/sort_order`，返回 `{items,total,page,pages}`
- 所有模型字段均为 `Optional` 宽松解码，与部署版本字段差异时不会崩溃（不匹配的项显示 `-`）
- 敏感操作（账号导出、备份、插件管理）后端要求 step-up TOTP，当前版本未开放这些入口

## 功能规格

### 1. 服务器与登录（Auth）

- 1.1 多服务器管理：添加/编辑/删除/切换；名称 + BaseURL，支持自建 http 内网地址（ATS 已放行）
- 1.2 认证方式二选一：
  - 面板账号：邮箱 + 密码 + 可选 2FA（TOTP）验证码
  - Admin API Key：登录时立即调 `/admin/dashboard/stats` 验证有效性
- 1.3 凭证安全：JWT 与 Refresh Token 存 Keychain（`AfterFirstUnlockThisDeviceOnly`）；登出/删服务器时清除
- 1.4 Token 生命周期：401 自动刷新一次并重放原请求；仍失败则回登录页

### 2. 仪表盘（Dashboard）

- 2.1 今日概览卡片：请求数 / 费用 / 输入 Token / 输出 Token
- 2.2 资源卡片：活跃用户 / 可用账号 / 当前并发
- 2.3 请求趋势图（Swift Charts，折线+面积，可切换 请求/Token/费用 三个指标）
- 2.4 用户消费排行 Top10：费用 + 请求数
- 2.5 模型用量 Top10：Token + 费用
- 2.6 单端点失败降级：仅隐藏对应区块，全部失败才展示错误页；下拉刷新

### 3. 用户管理（Users）

- 3.1 列表：分页加载更多；搜索（邮箱/用户名，500ms 防抖）；按状态（active/disabled/banned）与角色（user/admin）筛选；余额与管理员标记一目了然
- 3.2 详情：
  - 基本信息：ID/邮箱/用户名/角色/状态/分组/并发上限/RPM 上限/注册时间
  - 余额区：大字余额 + 「调整余额」
  - API Keys 列表（名称 + Key 前缀）
  - 余额变动历史（金额红绿、原因、时间）
- 3.3 余额调整（Sheet）：增加 / 扣减 / 设为 三种操作 + 备注，携带 Idempotency-Key，提交后自动刷新
- 3.4 启用/禁用账号（PUT users/:id，确认弹窗）

### 4. 账号池（Accounts）

- 4.1 列表：分页；按平台（claude/openai/gemini/antigravity/grok/国产）与状态（active/error/rate_limited/expired）筛选；名称搜索防抖；平台图标 + 状态徽标 + 最近使用时间
- 4.2 详情：
  - 账号信息：ID/名称/平台/认证类型/状态/可调度/优先级/权重/分组/最近使用/创建时间
  - 当日用量：请求数 / 输入 Token / 输出 Token / 费用
  - 错误信息展示（红色文本区）
- 4.3 运维操作（确认后执行，完成后自动刷新状态）：
  - 测试可用性 / 刷新凭证 / 清除错误状态 / 清除限流状态 / 重置配额 / 恢复状态 / 刷新账号等级
- 4.4 调度开关（Toggle，即时生效）

### 5. 日志（Logs）

- 5.1 使用记录：分页；按模型名筛选（防抖）；每行显示 模型/状态/用户/账号/Token 数/费用/延迟/时间
- 5.2 错误请求（`/admin/ops/request-errors`）：已解决/未解决图标、错误码、错误信息、关联用户与账号

### 6. 设置（Settings）

- 6.1 服务器管理：列表点选切换（对勾标记）、编辑、删除（清除凭证，确认弹窗）
- 6.2 当前会话：服务器名 + 认证方式；退出登录
- 6.3 系统：服务端版本/构建时间，检查更新按钮
- 6.4 关于：应用版本、上游开源项目

## 路线图（按优先级）

| 优先级 | 模块 | 子功能 |
|---|---|---|
| P0 | 日志增强 | 使用记录多条件筛选（日期范围/user_id/account_id/是否流式）、请求详情钻取、上游错误查看 |
| P0 | 账号操作补全 | 批量操作（批量刷新/清错/删除）、OAuth 授权流（generate-auth-url → 回跳 exchange-code）、代理绑定 |
| P1 | 分组管理 | 列表/详情/模型路由/计费倍率/RPM 覆盖 |
| P1 | 卡密 | 兑换码生成/列表/作废/导出，优惠码管理 |
| P1 | 订阅 | 订阅列表/分配/延期/撤销/配额重置 |
| P2 | 运维监控 | 实时 QPS（WebSocket 子协议携带 JWT）、告警规则与事件、并发/账号可用性 |
| P2 | 实时仪表盘 | 下拉自轮询 + Live Activity 展示 QPS |
| P2 | 系统运维 | 版本更新/回滚/重启、系统日志、审计日志（需 TOTP）、合规确认页 |
| P3 | 支付 | 订单/套餐/渠道管理，退款重试 |
| P3 | 通知 | 告警规则触发推送（APNs，需自建 push 服务） |

## 已知限制

- 模型字段为宽松 Optional 解码，**不同 sub2api 版本的字段命名可能有差异**，联调时以实际响应为准微调 `Core/Models/`
- WebSocket（`/admin/ops/ws/qps`）子协议认证尚未实现
- step-up TOTP 二次验证流程尚未实现（导出账号、备份恢复等入口因此未开放）
