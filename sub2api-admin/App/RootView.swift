import SwiftUI

/// 根视图：未配置服务器 / 未登录 → 登录页；已登录 → 主界面
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.activeServer == nil || !appState.isSessionValid {
                LoginView()
            } else {
                MainTabView()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("仪表盘", systemImage: "square.grid.2x2") }

            UserListView()
                .tabItem { Label("用户", systemImage: "person.2") }

            AccountListView()
                .tabItem { Label("账号", systemImage: "server.rack") }

            UsageListView()
                .tabItem { Label("日志", systemImage: "doc.text.magnifyingglass") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
