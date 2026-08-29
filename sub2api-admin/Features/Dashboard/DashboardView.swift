import SwiftUI
import Charts

/// 仪表盘：快照 → 趋势 → 消费排行 → 模型分布
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("仪表盘")
                .refreshable { await viewModel.loadAll() }
                .task { await viewModel.loadAll() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.snapshot == nil {
            LoadingView()
        } else if let error = viewModel.error, viewModel.snapshot == nil {
            ErrorStateView(error: error) {
                Task { await viewModel.loadAll() }
            }
        } else {
            List {
                snapshotSection
                trendSection
                rankingSection
                modelSection
            }
        }
    }

    // MARK: - 快照

    private var snapshotSection: some View {
        Section("今日概览") {
            let snap = viewModel.snapshot
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "请求数", value: Fmt.number(snap?.todayRequests), symbol: "arrow.triangle.2.circlepath")
                StatCard(title: "费用", value: Fmt.usd(snap?.todayCost), symbol: "dollarsign.circle", tint: .orange)
                StatCard(title: "输入 Token", value: Fmt.number(snap?.todayInputTokens), symbol: "arrow.down.circle", tint: .blue)
                StatCard(title: "输出 Token", value: Fmt.number(snap?.todayOutputTokens), symbol: "arrow.up.circle", tint: .purple)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "活跃用户", value: Fmt.number(snap?.activeUsers), symbol: "person.2")
                StatCard(title: "可用账号", value: Fmt.number(snap?.activeAccounts), symbol: "server.rack")
                StatCard(title: "并发", value: Fmt.number(snap?.concurrency), symbol: "bolt.horizontal")
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    // MARK: - 趋势

    private var trendSection: some View {
        Section {
            Picker("指标", selection: $viewModel.trendMetric) {
                ForEach(DashboardViewModel.TrendMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            trendChart
                .listRowInsets(EdgeInsets())
                .frame(height: 220)
        } header: {
            Text("请求趋势")
        }
    }

    private var trendChart: some View {
        Chart(viewModel.trend, id: \.id) { point in
            LineMark(
                x: .value("日期", Fmt.date(point.date)),
                y: .value("数值", viewModel.trendMetric.value(of: point))
            )
            .foregroundStyle(.tint)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("日期", Fmt.date(point.date)),
                y: .value("数值", viewModel.trendMetric.value(of: point))
            )
            .foregroundStyle(.tint.opacity(0.12))
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(n.formatted(.number.notation(.compactName)))
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 排行

    private var rankingSection: some View {
        Section("用户消费排行") {
            if viewModel.userRanking.isEmpty {
                EmptyStateView(text: "暂无消费记录")
            } else {
                ForEach(viewModel.userRanking.prefix(10)) { entry in
                    HStack {
                        Text(entry.displayName)
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Fmt.usd(entry.cost))
                                .font(.subheadline.weight(.medium))
                            Text("\(Fmt.number(entry.requests)) 次请求")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 模型

    private var modelSection: some View {
        Section("模型用量") {
            if viewModel.modelStats.isEmpty {
                EmptyStateView(text: "暂无模型数据")
            } else {
                ForEach(viewModel.modelStats.prefix(10)) { entry in
                    HStack {
                        Text(entry.model ?? "-")
                            .font(.subheadline.monospaced())
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Fmt.number(entry.tokens))
                                .font(.subheadline.weight(.medium))
                            Text(Fmt.usd(entry.cost))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

@MainActor
@Observable
final class DashboardViewModel {
    enum TrendMetric: String, CaseIterable, Identifiable {
        case requests, tokens, cost
        var id: String { rawValue }
        var title: String {
            switch self {
            case .requests: return "请求"
            case .tokens: return "Token"
            case .cost: return "费用"
            }
        }

        func value(of point: TrendPoint) -> Double {
            switch self {
            case .requests: return Double(point.requests ?? 0)
            case .tokens: return Double(point.tokens ?? 0)
            case .cost: return point.cost ?? 0
            }
        }
    }

    var snapshot: DashboardSnapshot?
    var trend: [TrendPoint] = []
    var userRanking: [UserRankingEntry] = []
    var modelStats: [ModelStatsEntry] = []
    var trendMetric: TrendMetric = .requests

    var isLoading = false
    var error: Error?

    private var client: APIClient? { AppStateHolder.shared.client }

    private func fetch<T: Decodable>(_ client: APIClient?, _ path: String) async -> T? {
        guard let client else { return nil }
        return try? await client.request("GET", path) as T
    }

    func loadAll() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // 先取 client 值再并发请求，避免捕获期间切换服务器导致的引用不一致
        let client = self.client
        async let snap: DashboardSnapshot? = fetch(client, "/admin/dashboard/snapshot-v2")
        async let stats: DashboardSnapshot? = fetch(client, "/admin/dashboard/stats")
        async let trendData: [TrendPoint]? = fetch(client, "/admin/dashboard/trend")
        async let ranking: [UserRankingEntry]? = fetch(client, "/admin/dashboard/users-ranking")
        async let models: [ModelStatsEntry]? = fetch(client, "/admin/dashboard/models")

        self.snapshot = (await snap) ?? (await stats)
        // 无条件覆盖：避免接口失败/空结果时残留旧数据导致 failures 统计失真
        self.trend = await trendData ?? []
        if let r = await ranking { self.userRanking = r }
        if let m = await models { self.modelStats = m }

        var failures = 0
        if snapshot == nil { failures += 1 }
        if trend.isEmpty { failures += 1 }
        if userRanking.isEmpty { failures += 1 }
        if modelStats.isEmpty { failures += 1 }
        if failures >= 4 {
            // 全部端点失败才报错（单个失败降级为隐藏对应区块）
            error = APIError.invalidResponse
        }
    }
}
