import SwiftUI

struct AccountListView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var groups: [MailGroup] = []
    @State private var tags: [MailTag] = []
    @State private var groupId: Int?
    @State private var tagIds: Set<Int> = []
    @State private var query = ""

    @State private var accounts: [MailAccount] = []
    @State private var total = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    /// 每次重新加载递增，丢掉过期请求的结果(快速切换筛选时)
    @State private var generation = 0
    @State private var stats: RefreshStats?
    /// 正在刷新 Token 的账号，行里显示转圈
    @State private var refreshing: Set<Int> = []

    @State private var path = NavigationPath()
    /// iPad 等宽屏：分组常驻左栏，选中的账号在右边显示邮件
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedAccount: MailAccount?
    @State private var columns: NavigationSplitViewVisibility = .automatic
    /// 三栏的总宽度：够宽(横屏)时分组栏默认常驻，窄(竖屏)时是盖在上面的浮层
    @State private var splitWidth: CGFloat = 0
    /// 分组栏有没有被系统挂到界面上(收起时会摘掉，触发 onDisappear)。
    /// 手势收起、点空白处关浮层时系统不一定改 columns，所以不能只看 columns
    @State private var groupsOnScreen = false
    @State private var drawerOpen = false
    /// 手指拖动抽屉时的位移(相对于开/关的静止位置)
    @State private var drawerDrag: CGFloat = 0
    @State private var fabCollapsed = false
    /// 当前弹出的页面(导入、设置、分享、编辑……统一用一个 sheet)
    @State private var panel: Panel?
    /// 批量选择模式
    @State private var selecting = false
    @State private var selection: Set<Int> = []
    @State private var confirmBatchDelete = false
    @State private var askExportPassword = false
    @State private var exportedFile: SharedFile?
    @State private var toast: String?
    @State private var copyCount = 0
    @Namespace private var chipSpace

    #if DEBUG
    init() {
        _drawerOpen = State(initialValue: DemoMode.screen == "drawer")
        _selecting = State(initialValue: DemoMode.screen == "batch")
        _selection = State(initialValue: DemoMode.screen == "batch" ? [1, 3] : [])
        // 复现"记录的值是全部显示、屏幕上其实收着"的状态(竖屏启动时就是这样)
        if DemoMode.screen == "split-toggle" { _columns = State(initialValue: .all) }
    }
    #endif

    private var filterKey: String {
        "\(groupId ?? -1)|\(tagIds.sorted())|\(query)"
    }

    /// 宽度够时(iPad、大屏横放)用三栏；状态都在这个 View 上，切换布局不会丢选择和筛选
    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular { splitLayout } else { stackLayout }
        }
        .sheet(item: $panel) { panelView($0) }
        .sheet(item: $exportedFile, onDismiss: TempFiles.purge) {
            ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large])
        }
        .confirmationDialog("删除选中的 \(selection.count) 个账号？", isPresented: $confirmBatchDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { runBatch("已删除") { try await api.batchDelete(Array(selection)) } }
        } message: {
            Text("账号和它们的别名、分享链接、刷新记录都会删除，无法恢复。")
        }
        .passwordPrompt($askExportPassword, title: "导出 \(selection.count) 个账号",
                        message: "导出文件包含密码和 Token，需要输入网页登录密码确认。") { password in
            exportSelected(password: password)
        }
        .toast($toast)
        .sensoryFeedback(.success, trigger: copyCount)
        .task { await loadFilters() }
        .task(id: filterKey) {
            // 输入搜索词时等一下再请求，避免每敲一个字发一次
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
        .onChange(of: groupId) { setDrawer(false) }
    }

    // MARK: 布局

    /// 手机：单栏导航，分组在抽屉里
    private var stackLayout: some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $path) {
                mainColumn
                    .navigationDestination(for: MailAccount.self) { MailListView(account: $0) }
                    // 首页从屏幕左边缘往右拖拉出抽屉(Gmail 手势)
                    .overlay(alignment: .leading) {
                        if path.isEmpty && !drawerOpen {
                            Color.clear
                                .frame(width: 18)
                                .contentShape(Rectangle())
                                .gesture(drawerGesture)
                        }
                    }
            }

            drawerLayer
        }
    }

    /// iPad：分组栏 | 账号列表 | 邮件。竖屏时分组栏自动收起，点搜索栏左边的按钮或从左边缘划出
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columns) {
            groupDrawer
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { groupsOnScreen = true }
                .onDisappear { groupsOnScreen = false }
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        } content: {
            mainColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 440)
        } detail: {
            NavigationStack {
                if let selectedAccount {
                    MailListView(account: selectedAccount)
                        .id(selectedAccount.id)
                } else {
                    ContentUnavailableView("选择一个邮箱", systemImage: "tray",
                                           description: Text("在左边的列表里点一个账号查看邮件"))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitWidth = $0 }
    }

    /// 宽于这个值时分组栏和列表并排，窄了是浮层(实测 iPad 13 寸竖屏 1032pt 是浮层，各尺寸横屏都在 1180pt 以上)
    private static let wideSplit: CGFloat = 1100

    /// 竖屏启动时分组栏虽然收着也会先 onAppear 一次，但系统会把 columns 改成 .doubleColumn，两个一起看
    private var groupsShown: Bool { groupsOnScreen && columns != .doubleColumn }

    private func showGroups(_ show: Bool) {
        let target: NavigationSplitViewVisibility = show ? .all : .doubleColumn
        if columns == target {
            // 记录的值和屏幕上不一致(系统自己开关过)：赋同样的值不会生效，先换成和现状一致的值，下一帧再设
            columns = show ? .doubleColumn : .all
            Task { withAnimation(DS.Motion.panel) { columns = target } }
        } else {
            withAnimation(DS.Motion.panel) { columns = target }
        }
    }

    /// 搜索栏 + 分组标签 + 账号列表，两种布局共用
    private var mainColumn: some View {
        VStack(spacing: 0) {
            searchBar
            // 宽屏时分组常驻左栏，不再重复显示这一排
            if !isRegular { groupTabs }
            accountList
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            if !selecting {
                FloatingButton(title: "导入", systemImage: "square.and.arrow.down", collapsed: fabCollapsed) {
                    panel = .importAccounts
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                BatchBar(
                    count: selection.count, groups: groups, tags: tags,
                    onMove: { id in runBatch("已移动") { try await api.batchMove(Array(selection), groupId: id) } },
                    onTag: { id, add in
                        runBatch(add ? "已添加标签" : "已移除标签") { try await api.batchTag(Array(selection), tagId: id, add: add) }
                    },
                    onStatus: { on in runBatch(on ? "已启用" : "已停用") { try await api.batchStatus(Array(selection), active: on) } },
                    onForwarding: { on in
                        runBatch(on ? "已开启转发" : "已关闭转发") { try await api.batchForwarding(Array(selection), enabled: on) }
                    },
                    onRefresh: { panel = .refreshSetup(nil, accounts.filter { selection.contains($0.id) }) },
                    onCopy: copySelected,
                    onExport: { askExportPassword = true },
                    onDelete: { confirmBatchDelete = true })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.snappy, value: selecting)
    }

    /// 搜索栏左边的按钮：手机上拉出抽屉，iPad 上显示/收起分组栏
    private func toggleGroups() {
        if isRegular {
            showGroups(!groupsShown)
        } else {
            setDrawer(true)
        }
    }

    // MARK: 抽屉(跟手拖动，松手按速度决定开关)

    private let drawerWidth: CGFloat = 304

    /// 0 = 关，1 = 开；拖动时是中间值，遮罩透明度和抽屉位置都跟着它走
    private var drawerProgress: CGFloat {
        let base: CGFloat = drawerOpen ? drawerWidth : 0
        return min(max((base + drawerDrag) / drawerWidth, 0), 1)
    }

    private var drawerGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // 开着时只能往左拖，关着时只能往右拉
                drawerDrag = drawerOpen ? min(0, value.translation.width) : max(0, value.translation.width)
            }
            .onEnded { value in
                // 按"甩出去会停在哪"判断，快速一甩即使没拖过半也算
                let base: CGFloat = drawerOpen ? drawerWidth : 0
                let projected = base + value.predictedEndTranslation.width
                setDrawer(projected > drawerWidth / 2, fling: true)
            }
    }

    private var drawerLayer: some View {
        let progress = drawerProgress
        return ZStack(alignment: .leading) {
            Color.black
                .opacity(0.35 * progress)
                .ignoresSafeArea()
                .allowsHitTesting(progress > 0)
                .onTapGesture { setDrawer(false) }
                .accessibilityHidden(true)
            groupDrawer
            .frame(width: drawerWidth)
            .shadow(color: .black.opacity(0.2 * progress), radius: 16, x: 4)
            .offset(x: (progress - 1) * (drawerWidth + 24))
            .gesture(drawerGesture)
            .accessibilityHidden(progress == 0)
        }
    }

    /// 手机上是抽屉，iPad 上是常驻的左栏
    private var groupDrawer: some View {
        GroupDrawer(
            groups: orderedGroups, tags: tags, allCount: allCount,
            server: api.serverURL.host() ?? "",
            groupId: $groupId, tagIds: $tagIds,
            onSelectGroup: selectGroup,
            onImport: { open(.importAccounts) },
            onSettings: { open(.settings) },
            onShares: { open(.shares) },
            onRefreshCenter: { open(.refreshCenter) },
            onTempEmails: { open(.tempEmails) },
            onForwarding: { open(.forwarding) },
            onOAuth: { open(.oauthHelper) },
            onManageTags: { open(.tags) },
            onEditGroup: { open(.group($0)) },
            onRefreshGroup: { open(.refreshSetup($0.id, nil)) },
            onNewSubgroup: { open(.subgroup($0)) },
            tempCount: groups.first(where: \.isTempEmailGroup)?.accountCount ?? 0,
            onLogout: { Task { await api.logout() } }
        )
    }

    private func setDrawer(_ open: Bool, fling: Bool = false) {
        let animation = DS.Motion.adaptive(fling ? DS.Motion.fling : DS.Motion.panel, reduceMotion: reduceMotion)
        withAnimation(animation) {
            drawerOpen = open
            drawerDrag = 0
        }
    }

    // MARK: 顶部搜索栏(Gmail 式)

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button("分组和标签", systemImage: isRegular ? "sidebar.left" : "line.3.horizontal", action: toggleGroups)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索邮箱、备注、标签、别名", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Menu {
                Section(api.serverURL.host() ?? "") {
                    Button("刷新列表", systemImage: "arrow.clockwise") { Task { await reloadAll() } }
                    Button("Token 刷新管理", systemImage: "key") { panel = .refreshCenter }
                    Button(groupId == nil ? "按分组刷新 Token" : "刷新当前分组 Token", systemImage: "arrow.triangle.2.circlepath") {
                        panel = .refreshSetup(groupId, nil)
                    }
                    Button("分享管理", systemImage: "link") { panel = .shares }
                    Button("设置与隐私", systemImage: "gearshape") { panel = .settings }
                    Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await api.logout() }
                    }
                }
            } label: {
                Avatar(text: api.serverURL.host() ?? "M", size: 32)
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            }
            .accessibilityLabel("服务器与设置")
        }
        .animation(DS.Motion.snappy, value: query.isEmpty)
        .foregroundStyle(.primary)
        .padding(.horizontal, DS.Spacing.xs)
        .background(DS.Palette.surface, in: Capsule())
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.top, DS.Spacing.xs)
    }

    /// Gmail"主要/推广/社交"那样的一排分组标签，只放一级分组，完整树在抽屉里。
    /// 选中色块在标签之间滑动，选中的标签自动滚到可见位置。
    private var groupTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.s) {
                    FilterChip(title: "全部", systemImage: "tray.2", count: allCount,
                               selected: groupId == nil, namespace: chipSpace) { selectGroup(nil) }
                        .id(-1)
                    ForEach(orderedGroups.filter { $0.depth == 0 }, id: \.group.id) { item in
                        let g = item.group
                        FilterChip(title: g.name, systemImage: "circle.fill", tint: Color(hex: g.color) ?? .gray,
                                   count: g.descendantAccountCount ?? g.accountCount,
                                   selected: rootGroupId == g.id, namespace: chipSpace) { selectGroup(g.id) }
                            .id(g.id)
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
            }
            .onChange(of: rootGroupId) { _, id in
                withAnimation(DS.Motion.snappy) { proxy.scrollTo(id ?? -1, anchor: .center) }
            }
        }
    }

    /// 选中的分组所属的一级分组(选了子分组时，标签行高亮它的父级)
    private var rootGroupId: Int? {
        guard var id = groupId else { return nil }
        while let parent = groups.first(where: { $0.id == id })?.parentId, groups.contains(where: { $0.id == parent }) {
            id = parent
        }
        return id
    }

    private func selectGroup(_ id: Int?) {
        withAnimation(DS.Motion.adaptive(DS.Motion.snappy, reduceMotion: reduceMotion)) { groupId = id }
        // 竖屏时分组栏是浮层，选完收起来看列表
        if isRegular, splitWidth < Self.wideSplit, groupsShown { showGroups(false) }
    }

    // MARK: 列表

    private var accountList: some View {
        List {
            if groupId == nil, query.isEmpty, tagIds.isEmpty, !selecting, let stats {
                Button { panel = .refreshCenter } label: { StatsCard(stats: stats) }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets(top: DS.Spacing.xs, bottom: DS.Spacing.s))
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            listHeader
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets(top: DS.Spacing.xs, bottom: DS.Spacing.xs))

            if let error, accounts.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    .listRowSeparator(.hidden)
            }
            ForEach(accounts) { account in
                Group {
                    if selecting {
                        Button { toggle(account.id) } label: {
                            HStack(spacing: DS.Spacing.m) {
                                Image(systemName: selection.contains(account.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(account.id) ? DS.Palette.accent : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                AccountRow(account: account, refreshing: refreshing.contains(account.id))
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else if isRegular {
                        // 宽屏：点一下在右栏打开，不压栈
                        Button { selectedAccount = account } label: {
                            AccountRow(account: account, refreshing: refreshing.contains(account.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedAccount?.id == account.id ? .isSelected : [])
                    } else {
                        ZStack {
                            // NavigationLink 自带的箭头和 Gmail 风格不搭，用透明链接盖住整行
                            NavigationLink(value: account) { EmptyView() }.opacity(0)
                            AccountRow(account: account, refreshing: refreshing.contains(account.id))
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets(top: DS.Spacing.s, bottom: DS.Spacing.s))
                .listRowBackground(selectionBackground(for: account))
                .swipeActions(edge: .leading) {
                    Button("复制", systemImage: "doc.on.doc") { copy(account.email) }
                        .tint(DS.Palette.accent)
                    Button("分享", systemImage: "link") { panel = .share(account) }
                        .tint(DS.Palette.ink)
                }
                .swipeActions(edge: .trailing) {
                    if account.isOutlook {
                        Button("刷新 Token", systemImage: "arrow.triangle.2.circlepath") { refreshToken(account) }
                            .tint(DS.Palette.warning)
                    }
                }
                .contextMenu {
                    Button("复制邮箱", systemImage: "doc.on.doc") { copy(account.email) }
                    Button("编辑账号", systemImage: "pencil") { panel = .edit(account) }
                    Button("分享邮箱", systemImage: "link") { panel = .share(account) }
                    Button("分享记录", systemImage: "clock.arrow.circlepath") { panel = .shareHistory(account) }
                    ForEach(account.aliases ?? [], id: \.self) { alias in
                        Button("复制别名 \(alias)", systemImage: "at") { copy(alias) }
                    }
                    if account.isOutlook {
                        Button("刷新 Token", systemImage: "arrow.triangle.2.circlepath") { refreshToken(account) }
                    }
                    if account.refreshFailed, let err = account.lastRefreshError, !err.isEmpty {
                        Section("上次刷新失败") { Text(err) }
                    }
                }
                .onAppear {
                    if account.id == accounts.last?.id, hasMore { Task { await load(reset: false) } }
                }
            }
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !loading, error == nil, accounts.isEmpty {
                Group {
                    if query.isEmpty {
                        ContentUnavailableView("没有账号", systemImage: "tray", description: Text("点右下角的\"导入\"添加邮箱"))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .listRowSeparator(.hidden)
            }
            // 给悬浮按钮留位置，最后一行不被挡住
            Color.clear.frame(height: 72).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await reloadAll() }
        // 往下滚收起悬浮按钮的文字，往上滚或回到顶部展开
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
            if new < 24 { fabCollapsed = false } else if new - old > 8 { fabCollapsed = true } else if old - new > 8 { fabCollapsed = false }
        }
    }

    /// 宽屏时右栏正在看的账号：浅蓝圆角底，和分组栏的选中色一致
    @ViewBuilder
    private func selectionBackground(for account: MailAccount) -> some View {
        if isRegular, !selecting, selectedAccount?.id == account.id {
            RoundedRectangle(cornerRadius: DS.Radius.chip)
                .fill(DS.Palette.accentSoft)
                .padding(.horizontal, DS.Spacing.s)
        }
    }

    private func rowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: DS.Spacing.screen, bottom: bottom, trailing: DS.Spacing.screen)
    }

    /// 网页账号栏顶部那样：分组色点 + 名字 + "N 个邮箱"，下面是已选标签
    private var listHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.s) {
                if let group = selectedGroup {
                    Circle().fill(Color(hex: group.color) ?? .gray).frame(width: 10, height: 10)
                }
                Text(query.isEmpty ? (selectedGroup?.name ?? "全部账号") : "搜索结果")
                    .font(.title3)
                    .bold()
                    .contentTransition(.opacity)
                Text("\(total) 个邮箱")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(total)))
                    .padding(.horizontal, DS.Spacing.s).padding(.vertical, 3)
                    .background(DS.Palette.surface, in: Capsule())
                Spacer()
                if selecting {
                    Button(selection.count == accounts.count && !accounts.isEmpty ? "全不选" : "全选") {
                        withAnimation(DS.Motion.snappy) {
                            selection = selection.count == accounts.count ? [] : Set(accounts.map(\.id))
                        }
                    }
                    .font(.subheadline)
                }
                Button(selecting ? "完成" : "选择") {
                    withAnimation(DS.Motion.snappy) {
                        selecting.toggle()
                        selection = []
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: DS.Size.tapTarget)
            }
            .animation(DS.Motion.snappy, value: total)
            if !tagIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags.filter { tagIds.contains($0.id) }) { tag in
                            Button {
                                _ = withAnimation(DS.Motion.snappy) { tagIds.remove(tag.id) }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(tag.name)
                                    Image(systemName: "xmark").imageScale(.small)
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color(hex: tag.color) ?? .gray, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("取消标签 \(tag.name)")
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    private var selectedGroup: MailGroup? {
        groupId.flatMap { id in groups.first { $0.id == id } }
    }

    private var allCount: Int {
        groups.filter { !$0.isTempEmailGroup && $0.parentId == nil }
            .reduce(0) { $0 + ($1.descendantAccountCount ?? $1.accountCount ?? 0) }
    }

    /// 服务端分组是平铺的，按 parent_id 排成树(父后面紧跟子)，最多三级
    private var orderedGroups: [(group: MailGroup, depth: Int)] {
        let visible = groups.filter { !$0.isTempEmailGroup }
        let ids = Set(visible.map(\.id))
        var result: [(MailGroup, Int)] = []
        func walk(_ parent: Int?, _ depth: Int) {
            for g in visible where g.parentId == parent || (parent == nil && g.parentId.map { !ids.contains($0) } == true) {
                result.append((g, depth))
                if depth < 3 { walk(g.id, depth + 1) }
            }
        }
        walk(nil, 0)
        return result
    }

    // MARK: 弹出页

    enum Panel: Identifiable {
        case importAccounts, settings, shares, refreshCenter, tempEmails, forwarding, oauthHelper, tags
        case share(MailAccount), shareHistory(MailAccount), edit(MailAccount)
        case group(MailGroup?)
        /// 在这个分组下新建子分组
        case subgroup(MailGroup)
        /// 按分组(nil = 全部)或按选中账号刷新，可自定义间隔
        case refreshSetup(Int?, [MailAccount]?)

        var id: String {
            switch self {
            case .importAccounts: "import"
            case .settings: "settings"
            case .shares: "shares"
            case .refreshCenter: "refresh"
            case .tempEmails: "temp"
            case .forwarding: "forwarding"
            case .oauthHelper: "oauth"
            case .tags: "tags"
            case .share(let a): "share-\(a.id)"
            case .shareHistory(let a): "history-\(a.id)"
            case .edit(let a): "edit-\(a.id)"
            case .group(let g): "group-\(g?.id ?? 0)"
            case .subgroup(let g): "subgroup-\(g.id)"
            case .refreshSetup: "refresh-setup"
            }
        }
    }

    private func open(_ p: Panel) {
        setDrawer(false)
        panel = p
    }

    @ViewBuilder
    private func panelView(_ p: Panel) -> some View {
        let normalGroups = groups.filter { !$0.isTempEmailGroup }
        switch p {
        case .importAccounts:
            ImportAccountsView(groups: normalGroups, initialGroupId: groupId) { Task { await reloadAll() } }
        case .settings:
            SettingsView()
        case .shares:
            ShareManagementView()
        case .share(let a):
            CreateShareView(account: a)
        case .shareHistory(let a):
            ShareManagementView(account: a)
        case .edit(let a):
            AccountEditView(accountId: a.id, groups: normalGroups, tags: tags) { Task { await reloadAll() } }
        case .refreshCenter:
            RefreshCenterView { Task { await reloadAll() } }
        case .refreshSetup(let group, let selected):
            RefreshSetupView(initialGroupId: group, preselected: selected) {
                withAnimation(DS.Motion.snappy) {
                    selecting = false
                    selection = []
                }
                Task { await reloadAll() }
            }
        case .tempEmails:
            TempEmailListView()
        case .forwarding:
            NavigationStack { ForwardingLogsView() }
        case .oauthHelper:
            OAuthHelperView(groups: normalGroups, initialGroupId: groupId) { Task { await reloadAll() } }
        case .tags:
            TagManageView { Task { await reloadAll() } }
        case .group(let g):
            GroupEditView(group: g, groups: normalGroups) { Task { await reloadAll() } }
        case .subgroup(let parent):
            GroupEditView(group: nil, groups: normalGroups, initialParentId: parent.id) { Task { await reloadAll() } }
        }
    }

    // MARK: 批量操作

    private func toggle(_ id: Int) {
        withAnimation(DS.Motion.snappy) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        }
    }

    /// 执行一个批量操作：成功后提示、退出选择模式、刷新列表
    private func runBatch(_ done: String, _ action: @escaping () async throws -> APIClient.MessageResult) {
        Task {
            do {
                let r = try await action()
                toast = r.message ?? done
                withAnimation(DS.Motion.snappy) {
                    selecting = false
                    selection = []
                }
                await reloadAll()
            } catch {
                toast = "操作失败：\(error.localizedDescription)"
            }
        }
    }

    private func copySelected() {
        let emails = accounts.filter { selection.contains($0.id) }.map(\.email)
        Privacy.shared.copy(emails.joined(separator: "\n"))
        copyCount += 1
        toast = "已复制 \(emails.count) 个邮箱"
    }

    private func exportSelected(password: String) {
        Task {
            do {
                let file = try await api.exportAccounts(password: password, accountIds: Array(selection))
                exportedFile = SharedFile(url: file)
            } catch {
                toast = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: 数据

    private func loadFilters() async {
        async let g = api.groups()
        async let t = api.tags()
        async let s = api.refreshStats()
        let (newGroups, newTags, newStats) = (try? await g, try? await t, try? await s)
        withAnimation(DS.Motion.panel) {
            groups = newGroups ?? groups
            tags = newTags ?? tags
            stats = newStats ?? stats
        }
    }

    private func reloadAll() async {
        await loadFilters()
        await load(reset: true)
    }

    private func load(reset: Bool) async {
        if !reset && loading { return }
        generation += 1
        let current = generation
        loading = true
        if reset { error = nil }
        do {
            let page = try await api.accounts(query: query, groupId: groupId, tagIds: Array(tagIds),
                                              offset: reset ? 0 : accounts.count)
            guard current == generation else { return }
            // 切换筛选时整页内容淡入替换；翻页追加不加动画
            withAnimation(reset ? DS.Motion.snappy : nil) {
                accounts = reset ? page.accounts : accounts + page.accounts
            }
            total = page.total ?? accounts.count
            hasMore = page.hasMore ?? false
            #if DEBUG
            // iPad 截图用：直接选中第一个账号
            if DemoMode.screen?.hasPrefix("split") == true, selectedAccount == nil { selectedAccount = accounts.first }
            if DemoMode.screen == "split-groups" { columns = .all }
            // 模拟器里点不了按钮：自动按几次开关，配合定时截图检查开合
            if DemoMode.screen == "split-toggle", generation == 1 {
                Task {
                    for _ in 0..<4 {
                        try? await Task.sleep(for: .seconds(4))
                        toggleGroups()
                    }
                }
            }
            #endif
        } catch {
            guard current == generation else { return }
            if reset { accounts = []; total = 0 }
            hasMore = false
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func copy(_ text: String) {
        Privacy.shared.copy(text)
        copyCount += 1
        toast = "已复制 \(text)"
    }

    private func refreshToken(_ account: MailAccount) {
        refreshing.insert(account.id)
        Task {
            do {
                let r = try await api.refreshToken(accountId: account.id)
                toast = r.message ?? "刷新成功"
                await load(reset: true)
                async let s = api.refreshStats()
                if let newStats = try? await s { withAnimation(DS.Motion.snappy) { stats = newStats } }
            } catch {
                toast = "刷新失败：\(error.localizedDescription)"
            }
            refreshing.remove(account.id)
        }
    }
}
