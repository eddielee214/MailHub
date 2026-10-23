import SwiftUI

/// 按分组 / 选中账号刷新 Token，可自定义账号之间的间隔秒数。
/// 服务端的刷新间隔是全局设置，这里改由 App 逐个调用单账号刷新来实现任意间隔。
struct RefreshSetupView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    /// 首页当前分组(从分组进来时)；nil = 全部
    var initialGroupId: Int?
    /// 批量选中的账号(从批量操作进来时)，有它就不再按分组取
    var preselected: [MailAccount]?
    var onFinish: () -> Void = {}

    @AppStorage("refreshIntervalSeconds") private var interval = 5
    @State private var groups: [MailGroup] = []
    @State private var groupId: Int?
    @State private var onlyProblem = false
    @State private var candidates: [MailAccount] = []
    @State private var loading = false
    @State private var error: String?
    @State private var run: APIClient.RefreshKind?

    private static let presets = [0, 3, 5, 10, 30, 60]

    /// 实际要刷新的账号：只刷新失败/未刷新时过滤掉正常的
    private var targets: [MailAccount] {
        let base = (preselected ?? candidates).filter { $0.isOutlook && $0.isActive }
        return onlyProblem ? base.filter { $0.lastRefreshStatus != "success" } : base
    }

    var body: some View {
        if let run {
            RefreshRunView(kind: run) {
                onFinish()
                dismiss()
            }
        } else {
            NavigationStack { form }
        }
    }

    private var form: some View {
        Form {
            Section {
                if let preselected {
                    LabeledContent("范围", value: "选中的 \(preselected.count) 个账号")
                } else {
                    Picker("分组", selection: $groupId) {
                        Text("全部分组").tag(Int?.none)
                        ForEach(groups.filter { !$0.isTempEmailGroup }) { g in
                            Text(String(repeating: "  ", count: max(0, (g.level ?? 1) - 1)) + g.name).tag(Int?.some(g.id))
                        }
                    }
                }
                Toggle("只刷新失败和未刷新的", isOn: $onlyProblem.animation(DS.Motion.snappy))
                LabeledContent("要刷新") {
                    if loading {
                        ProgressView()
                    } else {
                        Text("\(targets.count) 个 Outlook 账号")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(targets.count)))
                    }
                }
            } footer: {
                Text("包含子分组；已停用的账号和 IMAP 账号(没有 Token)会跳过。")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.s), count: 3),
                          spacing: 0) {
                    ForEach(Self.presets, id: \.self) { s in
                        FilterChip(title: s == 0 ? "不间隔" : "\(s) 秒", selected: interval == s, expands: true) {
                            withAnimation(DS.Motion.snappy) { interval = s }
                        }
                    }
                }
                Stepper(value: $interval, in: 0...600, step: interval < 10 ? 1 : 5) {
                    LabeledContent("自定义") {
                        Text("\(interval) 秒").monospacedDigit()
                    }
                }
            } header: {
                Text("每个账号之间间隔")
            } footer: {
                Text(estimate)
            }

            if let error {
                Section { Text(error).foregroundStyle(DS.Palette.danger) }
            }

            Section {
                Button(action: start) {
                    Text("开始刷新 \(targets.count) 个账号")
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(DS.Palette.accent, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(targets.isEmpty || loading)
                .opacity(targets.isEmpty || loading ? 0.5 : 1)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("刷新由 App 逐个执行，过程中请保持 App 在前台。")
            }
        }
        .navigationTitle(preselected == nil ? "按分组刷新" : "刷新选中账号")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
        .task {
            groupId = initialGroupId
            if preselected == nil {
                groups = (try? await api.groups()) ?? []
            }
        }
        .task(id: groupId) { await loadCandidates() }
    }

    /// 估算总用时：间隔 × (n-1)，每个账号刷新本身大约 2 秒
    private var estimate: String {
        let n = targets.count
        guard n > 0 else { return "没有需要刷新的账号。" }
        let seconds = interval * max(0, n - 1) + n * 2
        let text = seconds < 60 ? "\(seconds) 秒" : "\(Int((Double(seconds) / 60).rounded(.up))) 分钟"
        return "间隔太短可能触发微软风控。按现在的设置预计约 \(text)。"
    }

    private func loadCandidates() async {
        guard preselected == nil else { return }
        loading = true
        do {
            let list = try await api.refreshableAccounts(groupId: groupId)
            withAnimation(DS.Motion.snappy) { candidates = list }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func start() {
        let list = targets.map { APIClient.RefreshTarget(id: $0.id, email: $0.email) }
        withAnimation(DS.Motion.panel) { run = .sequence(list, interval: interval) }
    }
}
