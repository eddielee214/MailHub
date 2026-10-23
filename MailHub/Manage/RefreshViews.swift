import SwiftUI

/// Token 刷新管理(网页顶栏同名页面)：统计、全量刷新、重试失败、按状态筛选账号、单个刷新、刷新记录
struct RefreshCenterView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    var onChanged: () -> Void = {}

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all, failed, success, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部"
            case .failed: "失败"
            case .success: "正常"
            case .never: "未刷新"
            }
        }
    }

    @State private var filter: StatusFilter = .all
    @State private var query = ""
    @State private var items: [MailAccount] = []
    @State private var total = 0
    @State private var page = 1
    @State private var stats: RefreshStats?
    @State private var loading = true
    @State private var error: String?
    @State private var refreshing: Set<Int> = []
    @State private var run: APIClient.RefreshKind?
    @State private var showGroupRefresh = false
    @State private var toast: String?
    @Namespace private var chips

    var body: some View {
        NavigationStack {
            List {
                if let stats {
                    StatsCard(stats: stats)
                        .listRowSeparator(.hidden)
                        .listRowInsets(insets(top: DS.Spacing.xs, bottom: DS.Spacing.m))
                }
                actions
                    .listRowSeparator(.hidden)
                    .listRowInsets(insets(top: 0, bottom: DS.Spacing.s))
                filterBar
                    .listRowSeparator(.hidden)
                    .listRowInsets(insets(top: 0, bottom: DS.Spacing.xs))

                if let error, items.isEmpty {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                        .listRowSeparator(.hidden)
                }
                ForEach(items) { account in
                    NavigationLink {
                        RefreshLogsView(accountId: account.id)
                    } label: {
                        RefreshAccountRow(account: account, refreshing: refreshing.contains(account.id))
                    }
                    .listRowInsets(insets(top: DS.Spacing.s, bottom: DS.Spacing.s))
                    .swipeActions(edge: .trailing) {
                        Button("刷新", systemImage: "arrow.triangle.2.circlepath") { refreshOne(account) }
                            .tint(DS.Palette.warning)
                    }
                    .onAppear {
                        if account.id == items.last?.id, items.count < total { Task { await load(reset: false) } }
                    }
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                }
                if !loading, error == nil, items.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "没有\(filter.title)的账号" : "没有匹配的账号",
                                           systemImage: "key")
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索邮箱")
            .refreshable { await load(reset: true) }
            .navigationTitle("Token 刷新管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { RefreshLogsView() } label: { Label("刷新记录", systemImage: "clock") }
                }
            }
            .sheet(item: Binding(get: { run.map(RunBox.init) }, set: { run = $0?.kind })) { box in
                RefreshRunView(kind: box.kind) {
                    onChanged()
                    Task { await load(reset: true) }
                }
            }
            .sheet(isPresented: $showGroupRefresh) {
                RefreshSetupView {
                    onChanged()
                    Task { await load(reset: true) }
                }
            }
            .task(id: "\(filter.rawValue)|\(query)") {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                await load(reset: true)
            }
            .toast($toast)
        }
    }

    private struct RunBox: Identifiable {
        let kind: APIClient.RefreshKind
        var id: String { "run" }
    }

    private func insets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: DS.Spacing.screen, bottom: bottom, trailing: DS.Spacing.screen)
    }

    private var actions: some View {
        VStack(spacing: DS.Spacing.s) {
        HStack(spacing: DS.Spacing.m) {
            Button { run = .all } label: {
                Label("全量刷新", systemImage: "arrow.triangle.2.circlepath")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
                    .foregroundStyle(.white)
                    .background(DS.Palette.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
            Button { run = .failed } label: {
                Label("重试失败 \(stats?.failedCount ?? 0)", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
                    .foregroundStyle((stats?.failedCount ?? 0) > 0 ? DS.Palette.danger : .secondary)
                    .background(DS.Palette.surface, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled((stats?.failedCount ?? 0) == 0)
        }
        Button { showGroupRefresh = true } label: {
            HStack {
                Label("按分组刷新，自定义间隔", systemImage: "slider.horizontal.3")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, DS.Spacing.l)
            .frame(minHeight: DS.Size.tapTarget)
            .background(DS.Palette.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.s) {
                ForEach(StatusFilter.allCases) { f in
                    FilterChip(title: f.title, count: count(for: f), selected: filter == f, namespace: chips) {
                        withAnimation(DS.Motion.snappy) { filter = f }
                    }
                }
            }
        }
    }

    private func count(for f: StatusFilter) -> Int? {
        switch f {
        case .all: stats?.total
        case .failed: stats?.failedCount
        case .success: stats?.successCount
        case .never: stats?.neverCount
        }
    }

    private func load(reset: Bool) async {
        if !reset && loading { return }
        loading = true
        let next = reset ? 1 : page + 1
        do {
            let r = try await api.refreshStatusList(status: filter.rawValue, query: query, page: next)
            withAnimation(DS.Motion.snappy) {
                items = reset ? r.items : items + r.items
                stats = r.stats ?? stats
            }
            total = r.total ?? items.count
            page = next
            error = nil
        } catch {
            if reset { items = [] }
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func refreshOne(_ account: MailAccount) {
        refreshing.insert(account.id)
        Task {
            do {
                let r = account.refreshFailed
                    ? try await api.retryRefresh(accountId: account.id)
                    : try await api.refreshToken(accountId: account.id)
                toast = r.message ?? "刷新成功"
                onChanged()
                await load(reset: true)
            } catch {
                toast = "刷新失败：\(error.localizedDescription)"
            }
            refreshing.remove(account.id)
        }
    }
}

struct RefreshAccountRow: View {
    let account: MailAccount
    var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.email)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DS.Spacing.xs)
                if refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }
            }
            if account.refreshFailed, let err = account.lastRefreshError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .lineLimit(2)
            }
            Text(RelativeTime.text(account.lastRefreshAt).map { "最近刷新 \($0)" } ?? "从未刷新")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch account.lastRefreshStatus {
        case "success": "正常"
        case "failed": "失败"
        default: "未刷新"
        }
    }

    private var statusColor: Color {
        switch account.lastRefreshStatus {
        case "success": DS.Palette.success
        case "failed": DS.Palette.danger
        default: .secondary
        }
    }
}

/// 一次批量刷新的实时进度(全量 / 重试失败 / 选中账号)，数据来自服务端 SSE
struct RefreshRunView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let kind: APIClient.RefreshKind
    var onFinish: () -> Void = {}

    private struct Result: Identifiable {
        let id = UUID()
        let email: String
        let success: Bool
        let message: String
    }

    @State private var total = 0
    @State private var current = 0
    @State private var successCount = 0
    @State private var failedCount = 0
    @State private var currentEmail = ""
    @State private var waitSeconds: Int?
    /// 顺序刷新时下一个账号开始的时间，用来显示倒计时
    @State private var waitUntil: Date?
    @State private var runTask: Task<Void, Never>?
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @State private var results: [Result] = []
    @State private var finished = false
    @State private var finalMessage: String?
    @State private var stopping = false

    private var title: String {
        switch kind {
        case .all: "全量刷新"
        case .failed: "重试失败账号"
        case .selected(let ids): "刷新 \(ids.count) 个账号"
        case .sequence(let targets, _): "刷新 \(targets.count) 个账号"
        }
    }

    private var isSequence: Bool {
        if case .sequence = kind { return true }
        return false
    }

    /// 全量刷新在服务端停；顺序刷新是 App 自己跑的，取消任务即停
    private var canStop: Bool {
        switch kind {
        case .all, .sequence: true
        default: false
        }
    }

    private var progress: Double { total > 0 ? Double(current) / Double(total) : 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: DS.Spacing.l) {
                        ZStack {
                            Circle().stroke(DS.Palette.surface, lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(finished && failedCount == 0 ? DS.Palette.success : DS.Palette.accent,
                                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 2) {
                                Text("\(current)/\(total)")
                                    .font(.title2.bold().monospacedDigit())
                                    .contentTransition(.numericText(value: Double(current)))
                                Text(finished ? "已完成" : (total == 0 ? "准备中" : "进行中"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 140, height: 140)
                        .animation(DS.Motion.panel, value: current)

                        HStack(spacing: DS.Spacing.xl) {
                            stat("成功", successCount, DS.Palette.success)
                            stat("失败", failedCount, DS.Palette.danger)
                        }

                        if !finished {
                            Group {
                                if let waitUntil, waitUntil > .now {
                                    HStack(spacing: 4) {
                                        Text("间隔中，下一个")
                                        Text(timerInterval: Date.now...waitUntil, countsDown: true)
                                            .monospacedDigit()
                                    }
                                } else if let waitSeconds {
                                    Text("间隔 \(waitSeconds) 秒，避免触发风控")
                                } else if !currentEmail.isEmpty {
                                    Text(currentEmail).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                        } else if let finalMessage {
                            Text(finalMessage).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.m)
                } footer: {
                    if !finished {
                        Text(isSequence
                             ? "这次刷新由 App 逐个执行，请保持 App 在前台；锁屏或切走一会儿后会暂停。"
                             : "离开这个页面不会中断服务器上的刷新。")
                    }
                }

                if !results.isEmpty {
                    Section("结果") {
                        ForEach(results) { r in
                            HStack(alignment: .top, spacing: DS.Spacing.m) {
                                Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(r.success ? DS.Palette.success : DS.Palette.danger)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.email).font(.subheadline).lineLimit(1).truncationMode(.middle)
                                    if !r.message.isEmpty {
                                        Text(r.message)
                                            .font(.caption)
                                            .foregroundStyle(r.success ? Color.secondary : DS.Palette.danger)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(finished ? "完成" : (isSequence ? "停止并关闭" : "后台继续")) {
                        runTask?.cancel()
                        onFinish()
                        dismiss()
                    }
                }
                if canStop, !finished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("停止", role: .destructive, action: stop).disabled(stopping)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: finished) { _, new in new }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                // 切到后台时向系统多要一点时间，让当前这个账号刷完
                backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MailHubRefresh") {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
                if runTask == nil { runTask = Task { await runStream() } }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
        .interactiveDismissDisabled(!finished)
    }

    private func stat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .animation(DS.Motion.snappy, value: value)
    }

    private func runStream() async {
        do {
            for try await e in api.refreshStream(kind) {
                withAnimation(DS.Motion.snappy) { apply(e) }
            }
            if !finished {
                finished = true
                finalMessage = Task.isCancelled ? "已停止" : (finalMessage ?? "刷新结束")
            }
        } catch {
            finished = true
            finalMessage = "连接中断：\(error.localizedDescription)。服务器上的刷新可能仍在进行，稍后在列表里查看结果。"
        }
    }

    private func apply(_ e: RefreshEvent) {
        if let t = e.total { total = t }
        if let c = e.current { current = c }
        if let s = e.successCount { successCount = s }
        if let f = e.failedCount { failedCount = f }
        switch e.type {
        case "progress":
            currentEmail = e.email ?? ""
            waitSeconds = nil
            waitUntil = nil
        case "delay":
            waitSeconds = e.seconds
            waitUntil = e.seconds.map { Date.now.addingTimeInterval(TimeInterval($0)) }
        case "account_result":
            let ok = e.status == "success"
            results.insert(Result(email: e.email ?? "", success: ok,
                                  message: ok ? (e.message ?? "") : (e.errorMessage ?? e.message ?? "")), at: 0)
        case "complete":
            current = total
            finished = true
            finalMessage = total == 0 ? "没有需要刷新的账号" : "成功 \(successCount) 个，失败 \(failedCount) 个"
        case "stopped":
            finished = true
            finalMessage = "已停止"
        case "error", "conflict":
            finished = true
            finalMessage = e.message ?? "刷新出错"
        default:
            break
        }
    }

    private func stop() {
        if isSequence {
            runTask?.cancel()
            return
        }
        stopping = true
        Task {
            _ = try? await api.stopFullRefresh()
            stopping = false
        }
    }
}
