# sub2api iOS 管理面板 · 玻璃拟态 UI 架构设计文档

> 版本：v1.0（对应 Web 设计稿 `ui-design/sub2api-admin.html`）
> 适用工程：`/workspace/sub2api-admin`（SwiftUI + @Observable + XcodeGen）
> 目标平台：iOS 26+（Liquid Glass 优先），iOS 17/18 降级路径（`Material` 体系）

---

## 目录

1. [设计原则与目标](#1-设计原则与目标)
2. [视觉语言映射（Web → SwiftUI）](#2-视觉语言映射web--swiftui)
3. [分层架构与目录结构](#3-分层架构与目录结构)
4. [Token 层：`GlassTokens`](#4-token-层glasstokens)
5. [玻璃材质分级系统](#5-玻璃材质分级系统)
6. [背景系统：Aurora 极光层](#6-背景系统aurora-极光层)
7. [组件库规格](#7-组件库规格)
8. [动效系统](#8-动效系统)
9. [页面级实现规格](#9-页面级实现规格)
10. [深浅色与无障碍](#10-深浅色与无障碍)
11. [性能约束](#11-性能约束)
12. [迁移计划（对现有代码的最小改动路径）](#12-迁移计划)

---

## 1. 设计原则与目标

用户定调的三条核心原则，作为所有实现决策的裁决标准：

| 原则 | 工程含义 | 反例（禁止） |
|---|---|---|
| **低透毛玻璃 + 渐变光影，通透不糊** | 玻璃层必须有"可折射的内容"（Aurora 背景层），材质本身偏实底；文字永远落在 ≥ 4.5:1 对比度的基底上 | 全屏 `ultraThinMaterial` 盖在纯色背景上（一片灰糊） |
| **玻璃仅做点缀，信息层级优先** | 玻璃只出现在**悬浮层**：Tab 栏、批量操作条、Sheet、Push 导航栏、Toast、统计卡。列表/详情/表单区一律实底卡 | 列表行、错误消息块、代码块用玻璃材质 |
| **统一规范，细节克制** | 一套 Token（色彩/圆角/曲线/透明度阶梯）贯穿；同层级组件不出现两种材质混用；动效只用统一弹簧 | 每个页面各自发明圆角和动画参数 |

**验收口径**：「好用」（可读性、触达性、性能）优先于「好看」；任何玻璃效果若导致文字对比度不达标或滚动掉帧，降级为实底。

---

## 2. 视觉语言映射（Web → SwiftUI）

| Web 原型 | SwiftUI 实现 | 说明 |
|---|---|---|
| `backdrop-filter: blur(24px) saturate(160%)` | `.glassEffect()`（iOS 26）/ `.regularMaterial`（降级） | 见 §5 材质分级 |
| 极光背景 3 个 blur 光斑 | `MeshGradient`（iOS 18+）/ 3 个 `RadialGradient` 圆叠加（降级） | 见 §6 |
| `inset 0 1px 0` 内上高光 | `.strokeBorder(.white.opacity(0.09), lineWidth: 0.5)` + 顶部渐变叠层 | 模拟玻璃厚度 |
| iPhone 机身/灵动岛 | 真机不需要；设计稿仅用于传达比例 | — |
| 底部玻璃 Tab 栏（浮岛） | 系统原生 `TabView`（iOS 26 自动 Liquid Glass）+ 原始形状 TabBarAccessory | **不自绘 Tab 栏**，走原生 |
| 浮动批量操作条 | `safeAreaInset(edge: .bottom)` 内的自定义玻璃容器 | 见 §7.3 |
| 底部 Sheet（圆角 34 + 抓手条） | 原生 `.sheet` + `.presentationDetents([.medium, .large])` + `.presentationCornerRadius(34)` | 抓手条由系统渲染 |
| Push 侧滑详情页 | `NavigationStack` + `navigationDestination` | 原生转场，禁自绘 |
| iOS 段选滑块动画 | 自定义 `GlassSegmentedPicker`（`matchedGeometryEffect`） | 系统 Picker 无玻璃滑块 |
| iOS 开关 | 原生 `Toggle`（`.switch` style） | 颜色用 tint 覆写 |
| 数字滚动动画 | 自定义 `AnimatedNumberText`（`TimelineView` 驱动） | 见 §7.7 |
| 延迟分解堆叠条 | `HStack` + `GeometryReader` 比例宽度 | 见 §7.8 |
| Toast 玻璃胶囊 | 自定义 `GlassToastPresenter`（overlay） | SwiftUI 无原生 Toast |
| 趋势图（SVG + dash 动画） | Swift Charts `Chart` + `chartScrollableAxes` | 见 §7.9 |

---

## 3. 分层架构与目录结构

严格沿用现有工程四层结构，玻璃 UI 属于 **DesignSystem 层**，不侵入业务：

```text
sub2api-admin/
├── App/
│   ├── Sub2AdminApp.swift          # 入口
│   ├── AppState.swift / AppStateHolder.swift
│   └── RootView.swift              # 登录 ⇄ MainTabView 切换（改造点：见 §12）
├── Features/                        # 业务视图层（只依赖 DesignSystem，不实现材质）
│   ├── Dashboard/DashboardView.swift
│   ├── Accounts/AccountListView.swift     # 注入 GlassBatchBar、GlassStatCard
│   ├── Usage/UsageListView.swift          # 注入 GlassSegmentedPicker、GlassFilterSheet
│   ├── Users/ …
│   ├── Auth/ …
│   └── Settings/ …
├── DesignSystem/                    # ★ 本文档的主战场
│   ├── GlassTokens.swift            # §4：全部 Token
│   ├── GlassBackground.swift        # §6：Aurora 极光背景
│   ├── GlassComponents.swift        # §7：玻璃卡片/批量条/段选/Toast
│   ├── GlassCharts.swift            # §7.9：图表样式扩展
│   ├── Components.swift             # 现有组件（迁移目标，见 §12）
│   └── Formatters.swift
└── Core/                            # 与 UI 无关（网络/模型/持久化），零改动
    ├── Networking/  Models/  Persistence/
```

**依赖方向**：`App → Features → DesignSystem → (SwiftUI only)`。Core 层不感知玻璃 UI；DesignSystem 不 import 任何业务模型。这条规则保证设计系统可整体移植。

---

## 4. Token 层：`GlassTokens`

Web 原型 `:root` CSS 变量的 1:1 Swift 化。**所有组件禁止字面量取色/取圆角**，统一从 Token 读。

```swift
import SwiftUI

/// 玻璃拟态设计 Token —— 唯一事实来源
enum GlassTokens {
    // MARK: 色彩（暗色为主主题，浅色见 §10）
    static let accent      = Color(hex: 0xFF8A3D)   // 信号橙
    static let accentHi    = Color(hex: 0xFFB066)
    static let ok          = Color(hex: 0x34D399)
    static let err         = Color(hex: 0xFF6B6B)
    static let warn        = Color(hex: 0xFBBF50)
    static let info        = Color(hex: 0x6CB8FF)

    // 文字三级（对应 --ink / --ink-2 / --ink-3）
    static let ink   = Color.primary
    static let ink2  = Color.primary.opacity(0.62)
    static let ink3  = Color.primary.opacity(0.34)

    // Aurora 三色（对应极光光斑）
    static let aurora1 = Color(hex: 0xFF8A3D)
    static let aurora2 = Color(hex: 0x7B6CFF)
    static let aurora3 = Color(hex: 0x3FD8C2)

    // MARK: 圆角阶梯（对应 --r-sm/md/lg）
    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 26
        static let sheet: CGFloat = 34   // 原生 sheet 覆写用
    }

    // MARK: 透明度阶梯（玻璃边框/高光，对应 --stroke / --stroke-2）
    enum Stroke {
        static let regular = Color.white.opacity(0.10)
        static let strong  = Color.white.opacity(0.16)
        static let innerHi = Color.white.opacity(0.09)  // inset 1px 上高光
    }

    // MARK: 动效（对应 --ease 与统一时长）
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let pressScale: CGFloat = 0.97      // 按钮反馈
    static let revealStagger: Double = 0.07    // 卡片入场错峰
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}
```

---

## 5. 玻璃材质分级系统

三条原则的核心落地。**两个材质档位 + 一个禁用清单**：

| 档位 | Web 原型 | SwiftUI（iOS 26） | 降级（iOS 17/18） | 使用场景 |
|---|---|---|---|---|
| **Glass 浮层** | `--glass-2` (rgba .72) + blur 30-40 | `.glassEffect(.regular.tint(基底色).interactive())` | `.regularMaterial`（系统已含 saturate） | Tab 栏浮岛区、批量操作条、Push 导航栏、Sheet 内容底、Toast |
| **Glass 点缀卡** | `--glass` (rgba .60) + blur 24 | `.glassEffect(.regular.tint(...))` + 顶部光泽渐变 | `.ultraThinMaterial` + 渐变叠层 | 仅仪表盘 4 张统计卡（需要折射 Aurora 才成立） |
| **实底信息卡** | `rgba(255,255,255,.045)` | `GlassCardStyle.solid`（自绘背景） | 同左 | **列表行、详情分组、代码块、表单、错误消息**——一切文字密集区 |

```swift
/// 玻璃卡样式枚举 —— 组件的材质入口唯一化
enum GlassCardStyle {
    case solid          // 实底信息卡（默认）
    case glassFloating  // 玻璃浮层
    case glassAccent    // 玻璃点缀卡（仅仪表盘统计卡）
}

/// 统一卡片容器：内部处理材质/边框/内高光，业务侧只选档位
struct GlassCard<Content: View>: View {
    let style: GlassCardStyle
    @ViewBuilder let content: Content

    var body: some View {
        switch style {
        case .solid:
            content
                .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: GlassTokens.Radius.md))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: GlassTokens.Radius.md)
                        .strokeBorder(GlassTokens.Stroke.regular.opacity(0.6))
                }
        case .glassFloating, .glassAccent:
            content
                .background {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: GlassTokens.Radius.md)
                            .fill(.clear)
                            .glassEffect(.regular.tint(.black.opacity(0.45)))
                            .overlay(alignment: .top) { topHighlight }
                    } else {
                        RoundedRectangle(cornerRadius: GlassTokens.Radius.md)
                            .fill(.regularMaterial)
                            .overlay(alignment: .top) { topHighlight }
                    }
                }
        }
    }

    /// 玻璃厚度感：左上→46% 渐变内高光（对应 .stat::after）
    private var topHighlight: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.09), location: 0),
                .init(color: .clear, location: 0.46)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .clipShape(.rect(cornerRadius: GlassTokens.Radius.md))
        .allowsHitTesting(false)
    }
}
```

**禁用清单**（code review 检查项）：
- `List` / `Form` 行内禁止 `.background(.ultraThinMaterial)`
- `Text` 直接落在玻璃上时禁止使用 `ink3`（0.34 透明度在玻璃上不可读）
- 同屏玻璃浮层 ≤ 2 个（Tab 栏不算）
- 长文本（> 2 行）所在容器禁止玻璃材质

---

## 6. 背景系统：Aurora 极光层

玻璃「通透不糊」的前提是**底下有东西可折射**。全屏极光层挂在 `RootView`，所有 tab 共享一份实例（性能：见 §11）。

```swift
/// 极光背景：3 个缓慢漂移的模糊光斑（对应 .aurora 的 3 个 <i>）
struct GlassBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(hex: 0x0A0C14)  // --bg

            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, drift ? 0.62 : 0.38], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        GlassTokens.aurora1.opacity(0.55), .clear, .clear,
                        .clear, .clear, GlassTokens.aurora3.opacity(0.30),
                        .clear, GlassTokens.aurura2.opacity(0.45), .clear
                    ]
                )
                .ignoresSafeArea()
            } else {
                // 降级：3 个径向渐变光斑 + 漂移动画
                ZStack {
                    blob(GlassTokens.aurora1, size: 340, x: -100, y: -120)
                    blob(GlassTokens.aurora2, size: 300, x: 90,  y: 480)
                    blob(GlassTokens.aurora3, size: 240, x: 110, y: 300).opacity(0.35)
                }
                .blur(radius: 70)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.55))
            .frame(width: size, height: size)
            .offset(x: drift ? x + 40 : x, y: drift ? y + 30 : y)
    }
}
```

> 挂载位置：`MainTabView` 的 `background(GlassBackground())`。`List` 底色改 `Color.clear`（`scrollContentBackground(.hidden)`），让列表通透地露出极光——这是「通透层次感」的来源。

---

## 7. 组件库规格

### 7.1 GlassStatCard（仪表盘统计卡 · 玻璃点缀档）

替代现有 [Components.swift](../sub2api-admin/DesignSystem/Components.swift) 的 `StatCard`。

```swift
struct GlassStatCard: View {
    let title: String
    let value: Double
    var format: ValueFormat = .plain
    var trend: Trend? = nil          // ▲12.4% / ▼2 错误态

    @State private var appeared = false

    var body: some View {
        GlassCard(style: .glassAccent) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(GlassTokens.ink3)
                AnimatedNumberText(value: value, format: format)
                    .font(.system(size: 26, weight: .bold))
                trendLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(GlassTokens.spring.delay(revealDelay)) { appeared = true }
        }
    }
}
```

规格要点：
- 入场动画错峰 70ms 递增（对应 `--i` 变量），由父视图传 `revealDelay`
- 费用卡 `.tint(GlassTokens.accentHi)` 数值着色
- **仅此组件允许 glassAccent 档**

### 7.2 GlassSegmentedPicker（段选器 + 滑块动画）

对应 Web 的 iOS 段选（滑块用 `matchedGeometryEffect` 实现弹性滑动）：

```swift
struct GlassSegmentedPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                let isOn = opt == selection
                Button {
                    withAnimation(GlassTokens.spring) { selection = opt }
                } label: {
                    Text(title(opt))
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? GlassTokens.ink : GlassTokens.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(Color.primary.opacity(0.13))
                                    .matchedGeometryEffect(id: "seg-slide", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .overlay(Capsule().strokeBorder(GlassTokens.Stroke.regular))
    }
}
```

用于：日志 Tab（使用/错误）、流式筛选、错误时间窗口（1H/24H/7D/30D）、解决状态。

### 7.3 GlassBatchBar（浮动批量操作条 · 玻璃浮层档）

账号管理多选模式的悬浮操作条，对应 Web `#batch-bar`：

```swift
struct GlassBatchBar: View {
    let count: Int
    let onAction: (AccountBatchAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            VStack(spacing: 0) {
                Text("已选").font(.caption2).foregroundStyle(GlassTokens.ink3)
                Text("\(count)").font(.title2.bold()).foregroundStyle(GlassTokens.accentHi)
            }
            Divider().frame(height: 34)
            batchButton(.batchRefresh)
            batchButton(.batchClearError)
            batchButton(.batchRefreshTier)
            batchButton(.batchDelete)   // 内部红字
            Button("取消", action: onCancel)
                .font(.footnote).foregroundStyle(GlassTokens.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(GlassCard(style: .glassFloating))  // 橙色描边变体
    }
}
```

**挂载方式**（关键决策——不自绘悬浮，用安全区插图）：

```swift
// AccountListView 内
List { /* 账号行 */ }
.safeAreaInset(edge: .bottom) {
    if viewModel.selectMode, !viewModel.selectedIds.isEmpty {
        GlassBatchBar(count: viewModel.selectedIds.count, ...)
            .padding(.horizontal, 18)
            .padding(.bottom, 88)   // 避开 Tab 栏
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

### 7.4 GlassToast（玻璃胶囊 Toast）

```swift
/// 全局 Toast 中心：挂 MainTabView 的 overlay 顶部（对应 .toasts）
@Observable
final class ToastCenter {
    struct Item: Identifiable { let id = UUID(); let text: String; var isError = false }
    var current: Item?

    func show(_ text: String, isError: Bool = false) {
        withAnimation(GlassTokens.spring) { current = .init(text: text, isError: isError) }
        Task { try? await Task.sleep(for: .seconds(3)); dismiss() }
    }
}

struct GlassToastView: View {
    let item: ToastCenter.Item
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(item.isError ? GlassTokens.err : GlassTokens.ok)
                .frame(width: 7, height: 7).shadow(radius: 4)
            Text(item.text).font(.subheadline)
        }
        .padding(.horizontal, 19).padding(.vertical, 11)
        .background(GlassCard(style: .glassFloating))
        .clipShape(Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

### 7.5 GlassFilterSheet（多条件筛选 Sheet）

**不自绘**，直接用原生 sheet + detents，内容区用实底信息卡：

```swift
.sheet(isPresented: $viewModel.showFilterSheet) {
    UsageFilterSheet(filter: viewModel.filter) { viewModel.applyFilter($0) }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(GlassTokens.Radius.sheet)
        .presentationBackground(.thinMaterial)   // Sheet 本体玻璃化（系统提供）
}
```

Sheet 内部表单沿用现有 `Form`，字段规格对齐 [README §5.2/5.5](../README.md)（user_id/account_id/request_id/日期范围/流式/时间窗口/解决状态）。

### 7.6 AnimatedNumberText（数字滚动）

```swift
struct AnimatedNumberText: View {
    let value: Double
    var format: GlassStatCard.ValueFormat
    @State private var progress: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            Text(format.string(value: value * easedProgress))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .onAppear { progress = 0; withAnimation(.easeOut(duration: 1.1)) { progress = 1 } }
    }
}
```

### 7.7 LatencyBreakdownBar（延迟分解堆叠条）

错误详情页专属，对应 Web `.lat` 四段堆叠：

```swift
struct LatencyBreakdownBar: View {
    let auth: Double, route: Double, upstream: Double, response: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                seg(auth,     color: GlassTokens.info)
                seg(route,    color: GlassTokens.ok)
                seg(upstream, color: GlassTokens.accent)
                seg(response, color: GlassTokens.warn)
            }
            .frame(width: geo.size.width, height: 24)
        }
        .frame(height: 24)
        .clipShape(.rect(cornerRadius: 9))
        .overlay(.rect(cornerRadius: 9).strokeBorder(GlassTokens.Stroke.regular))
    }
}
```

### 7.8 图表样式（Swift Charts）

趋势图改用 Swift Charts（替代自绘 SVG），交互（悬停取值）用系统 `ChartScrollableAxes` + `chartOverlay`：

- 线条 `.foregroundStyle(GlassTokens.accent)` + 渐变面积
- 指标切换（请求/Token/费用）复用 `GlassSegmentedPicker`
- 用户消费 Top 复用排行组件（实底卡 + 延迟动画进度条）

### 7.9 错误详情 Push

原生 `NavigationStack` push（已在 [UsageListView.swift](../sub2api-admin/Features/Usage/UsageListView.swift) 实现），本次仅换皮：
- 导航栏自动玻璃化（iOS 26 原生）
- 分组容器 `GlassCard(.solid)`，区标题用 `GlassTokens.accentHi` monospaced 小字
- 错误响应体：实底深色代码块 + `textSelection(.enabled)`
- 「标记已解决」按钮：`GlassButton(.primary)`（橙色渐变 + 按压缩放）
- 「关联使用记录」钻取：现有 request_id 联动逻辑保持不变

---

## 8. 动效系统

| 场景 | 曲线/时长 | SwiftUI |
|---|---|---|
| 全局默认 | `cubic-bezier(.32,.72,.28,1)` ≈ 弹簧 | `Animation.spring(response: 0.42, dampingFraction: 0.86)` |
| 按钮反馈 | 缩放 0.97 | `.buttonStyle(GlassPressStyle)` |
| 卡片入场 | 上移 16 + 缩放 0.97，错峰 70ms | `withAnimation(spring.delay(i * 0.07))` |
| 批量条进出 | 底部上滑 + 淡入 | `.transition(.move(edge: .bottom).combined(with: .opacity))` |
| Sheet | 原生弹簧 | 系统默认（不自绘） |
| 段选滑块 | matchedGeometry | `withAnimation(spring)` |
| 图表绘线 | 1.5s 缓出 | Swift Charts `Chart` 自带 / `.animation(.easeOut(duration: 1.5))` |

```swift
/// 统一按压反馈样式（对应 .btn:active）
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? GlassTokens.pressScale : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
```

---

## 9. 页面级实现规格

### 9.1 MainTabView（根导航）

**决策：不自绘玻璃 Tab 栏**。iOS 26 的 `TabView` 自带 Liquid Glass 浮岛效果，与 Web 原型视觉一致；降级到 iOS 17/18 时系统 Tab 栏 + `.toolbarBackground(.ultraThinMaterial, for: .tabBar)`。保留账号管理 tab 的错误数角标（`.badge()`）。

```swift
struct MainTabView: View {
    @State private var toast = ToastCenter()
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            DashboardView().tabItem { Label("仪表盘", systemImage: "square.grid.2x2.fill") }
            AccountListView().tabItem { Label("账号管理", systemImage: "server.rack") }
                .badge(appState.errorAccountCount)
            UsageListView().tabItem { Label("日志", systemImage: "doc.text.magnifyingglass") }
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }
        }
        .background(GlassBackground())
        .environment(toast)
        .overlay(alignment: .top) {          // Toast 挂载点
            if let item = toast.current { GlassToastView(item: item).padding(.top, 60) }
        }
        .tint(GlassTokens.accent)
    }
}
```

（用户 tab 并入日志页段选或保留五 tab，按现有 `RootView` 结构为准——迁移期不改信息架构。）

### 9.2 仪表盘 DashboardView

- 大标题 `仪表盘`（`navigationTitle` + `.toolbarTitleDisplayMode(.large)`）+ 服务器状态胶囊（玻璃档、绿点脉冲）
- 4 张 `GlassStatCard`（唯一 glassAccent 场景）2×2 LazyVGrid
- 趋势图 `GlassCard(.solid)` + 指标段选
- 消费/模型排行：实底卡 + 条形延迟动画
- 下拉刷新 `refreshable`（沿用现有 ViewModel）

### 9.3 账号管理 AccountListView

- 大标题 + 右上「选择」按钮切换多选模式（标题变「已选 N」）
- 平台 chips 横滑（`ScrollView(.horizontal)` + 渐隐遮罩 `mask`）
- 列表行：实底卡 = 复选圆钮（多选态）/ 调度 `Toggle`（浏览态）+ 平台图标 + `StatusPill`
- 多选模式 → `safeAreaInset` 弹出 `GlassBatchBar` → 批量确认 Sheet（选中预览前 5 + 溢出计数 + 红色危险态 + 进度条）→ 完成后 toast + 自动 reload
- 业务逻辑完全复用现有 `AccountBatchAction` 与 `runBatch()`

### 9.4 日志 UsageListView

- 双段选（`GlassSegmentedPicker`）：使用记录 / 错误请求
- 使用记录：搜索防抖 + 流式段选 + 筛选 Sheet + 活动筛选条（橙色虚线框实底）+ 行点击 → 详情 push（`UsageLogDetailView`，实底分组）
- 错误请求：时间窗口段选（1H/24H/7D/30D，`start_time` RFC3339）+ 解决状态段选 + 搜索 → 行点击 → `RequestErrorDetailView` push
- 错误详情：错误信息/上下文/延迟分解条/上游错误卡/解决操作/Request ID 钻取（现有逻辑不动，仅换容器为 `GlassCard(.solid)`）

### 9.5 设置 SettingsView

- 分组实底卡 + KV 行（现有结构微调）；「设计规范」区展示材质参数（对应 Web 原型彩蛋）

---

## 10. 深浅色与无障碍

- **主主题为暗色**（设计稿基调）。浅色模式提供降级：`GlassBackground` 换浅色极光（低饱和）；`GlassCard` 三档材质自动跟随系统 `Material`（系统材质本身自适应）；Token 文字色基于 `Color.primary` 自动翻转
- **对比度红线**：玻璃上正文 ≥ 4.5:1（用 `.contrast` 修饰器跑 audit）；`ink3` 仅用于辅助标签且不落玻璃
- **无障碍**：
  - 全部交互 ≥ 44×44pt（批量条内竖排图标按钮做 `frame(minWidth: 44, minHeight: 44)` 命中区扩展）
  - `GlassSegmentedPicker` 补 `accessibilityLabel` + `.accessibilityAddTraits(.isSelected)`
  - 色彩状态（红/绿点）冗余文本（已有 `StatusPill` 文本，合规）
  - 动效尊重 `accessibilityReduceMotion`：错峰入场/数字滚动退化为直出
- **Dynamic Type**：统计卡数值用 `.system(size: 26, weight: .bold)` 时必须挂 `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` 上限兜底；正文全部语义字体

---

## 11. 性能约束

| 风险点 | 约束 | 对策 |
|---|---|---|
| 玻璃层数量 | 同屏 ≤ 2 浮层 | Tab 栏系统托管；批量条/Toast 互斥出现 |
| Aurora 漂移动画 | 仅 1 实例、常驻 GPU | MeshGradient 优先；26s 周期低频；`reducedMotion` 停止 |
| List 滚动 | 列表行零玻璃、零实时 blur | 行背景为静态色（`.opacity(0.045)`） |
| 图表 | Charts 一次渲染 | 指标切换重建数据源，禁逐帧动画 |
| 内存 | 无新增大资源 | 玻璃/极光全部程序化绘制，无图片资产 |

**验证手段**：Instruments → Core Animation Commits，滚动 60fps 无丢帧；`Debug → Color Blended Layers` 检查玻璃区域 blend 层级 ≤ 3。

---

## 12. 迁移计划

现有工程已具备全部业务逻辑（批量操作、多条件筛选、错误钻取、Request ID 联动），玻璃 UI 是**纯换皮工程**，按依赖顺序四步走，每步独立可编译可回滚：

| 阶段 | 内容 | 改动文件 | 风险 |
|---|---|---|---|
| **P1 Token + 背景** | `GlassTokens` / `GlassBackground`；`MainTabView` 挂背景与 tint；List 透明化 | 新增 2 文件 + `RootView.swift` | 零（纯叠加） |
| **P2 基础组件** | `GlassCard` 三档 / `GlassSegmentedPicker` / `GlassPressStyle` / `GlassToastCenter`；`StatCard` → `GlassStatCard` | 新增 `GlassComponents.swift`，替换 `Components.swift` 中 StatCard 引用 | 低（视觉替换） |
| **P3 浮层组件** | `GlassBatchBar` 接入 `AccountListView.safeAreaInset`（复用 `AccountBatchAction`）；`ToastCenter` 接批量回调 | `AccountListView.swift` | 中（交互重排，逻辑不动） |
| **P4 页面换皮** | 日志双段选 / 错误详情 Push 容器 / Sheet 玻璃化 / Swift Charts 替换趋势图 | `UsageListView.swift` / `DashboardView.swift` | 中 |

**不动的部分**（明确边界）：`Core/`（网络/模型/Keychain）、全部 ViewModel 业务逻辑、`APIClient`、导航结构（NavigationStack + navigationDestination）、README 记录的 API 契约。

**完成定义（DoD）**：
1. Web 原型的全部交互在真机可复现（批量确认含预览/错误钻取/联动筛选/标记解决）
2. 暗色为主、浅色可用的双主题
3. 滚动 60fps；同屏玻璃浮层 ≤ 2；对比度达标
4. `DesignSystem` 不 import 业务模块（可整体移植验证）
