import SwiftUI

/// 分组和标签可选的颜色(和网页一样存 #rrggbb)
enum SwatchPalette {
    static let colors = [
        "#1a1a1a", "#666666", "#dc2626", "#ea580c", "#ca8a04", "#16a34a",
        "#0d9488", "#2563eb", "#4f46e5", "#9333ea", "#db2777", "#78716c",
    ]
}

struct ColorSwatches: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.s), count: 6),
                  spacing: DS.Spacing.s) {
            ForEach(SwatchPalette.colors, id: \.self) { hex in
                let on = selection.lowercased() == hex
                Button { withAnimation(DS.Motion.snappy) { selection = hex } } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if on {
                                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().stroke(on ? Color.primary : .clear, lineWidth: 2).padding(-4))
                        .frame(minWidth: DS.Size.tapTarget, minHeight: DS.Size.tapTarget)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(hex)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// 新建/编辑分组：名称、颜色、上级分组(最多三级)、分组代理、说明；编辑时可删除
struct GroupEditView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    /// nil = 新建
    let group: MailGroup?
    let groups: [MailGroup]
    var onChanged: () -> Void = {}

    @State private var name = ""
    @State private var color = "#2563eb"
    @State private var parentId: Int?
    @State private var proxy = ""
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false

    /// 能当上级的分组：不能是自己或自己的后代，且只能挂在一、二级下面
    private var parentCandidates: [MailGroup] {
        let excluded = group.map { descendants(of: $0.id) } ?? []
        return groups.filter { ($0.level ?? 1) < 3 && !excluded.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("分组名称", text: $name)
                    ColorSwatches(selection: $color)
                        .padding(.vertical, DS.Spacing.xs)
                }
                Section {
                    Picker("上级分组", selection: $parentId) {
                        Text("无(一级分组)").tag(Int?.none)
                        ForEach(parentCandidates) { g in
                            Text(String(repeating: "  ", count: max(0, (g.level ?? 1) - 1)) + g.name).tag(Int?.some(g.id))
                        }
                    }
                } footer: {
                    Text("分组最多三级。")
                }
                Section {
                    TextField("分组代理(可选)", text: $proxy)
                        .font(.subheadline.monospaced())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("说明(可选)", text: $note, axis: .vertical)
                } footer: {
                    Text("组内账号默认走这个代理，子分组和账号可以覆盖。支持 {mail} 模板。")
                }
                if let error {
                    Section { Text(error).foregroundStyle(DS.Palette.danger) }
                }
                if group != nil {
                    Section {
                        Button("删除分组", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    } footer: {
                        Text("子分组会一起删除，里面的账号移回默认分组，不会删除账号。")
                    }
                }
            }
            .navigationTitle(group == nil ? "新建分组" : "编辑分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("保存", action: save).bold()
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("删除分组「\(group?.name ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive, action: delete)
            }
            .task { await load() }
        }
    }

    private func descendants(of id: Int) -> Set<Int> {
        var result: Set<Int> = [id]
        var changed = true
        while changed {
            changed = false
            for g in groups where g.parentId.map(result.contains) == true && !result.contains(g.id) {
                result.insert(g.id)
                changed = true
            }
        }
        return result
    }

    private func load() async {
        guard let group else { return }
        name = group.name
        color = group.color ?? color
        parentId = group.parentId
        // 代理和说明不在列表接口里，单独取一次
        if let d = try? await api.groupDetail(id: group.id) {
            proxy = d.proxyUrl ?? ""
            note = d.description ?? ""
        }
    }

    private func save() {
        saving = true
        error = nil
        let input = APIClient.GroupInput(name: name.trimmingCharacters(in: .whitespaces), description: note,
                                         color: color, proxy_url: proxy.trimmingCharacters(in: .whitespaces),
                                         parent_id: parentId)
        Task {
            do {
                _ = try await api.saveGroup(id: group?.id, input)
                onChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private func delete() {
        guard let group else { return }
        Task {
            do {
                _ = try await api.deleteGroup(id: group.id)
                onChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// 标签管理：新建(名称 + 颜色)、左滑删除
struct TagManageView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    var onChanged: () -> Void = {}

    @State private var tags: [MailTag] = []
    @State private var name = ""
    @State private var color = "#2563eb"
    @State private var error: String?
    @State private var pendingDelete: MailTag?

    var body: some View {
        NavigationStack {
            Form {
                Section("新建标签") {
                    HStack {
                        TextField("标签名称", text: $name)
                            .onSubmit(create)
                        Button("添加", action: create)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ColorSwatches(selection: $color)
                        .padding(.vertical, DS.Spacing.xs)
                }
                Section {
                    ForEach(tags) { tag in
                        Label {
                            Text(tag.name)
                        } icon: {
                            Image(systemName: "tag.fill").foregroundStyle(Color(hex: tag.color) ?? .gray)
                        }
                        .swipeActions {
                            Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = tag }
                        }
                    }
                    if tags.isEmpty {
                        Text("还没有标签").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("已有标签")
                } footer: {
                    Text("左滑删除。删除标签不会删除账号。")
                }
                if let error {
                    Section { Text(error).foregroundStyle(DS.Palette.danger) }
                }
            }
            .navigationTitle("标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("删除标签「\(pendingDelete?.name ?? "")」？", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { tag in
                Button("删除", role: .destructive) { delete(tag) }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if let list = try? await api.tags() {
            withAnimation(DS.Motion.snappy) { tags = list }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                _ = try await api.createTag(name: trimmed, color: color)
                name = ""
                error = nil
                onChanged()
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete(_ tag: MailTag) {
        Task {
            do {
                _ = try await api.deleteTag(id: tag.id)
                onChanged()
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
