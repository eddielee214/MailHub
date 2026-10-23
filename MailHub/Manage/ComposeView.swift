import SwiftUI

/// 写邮件：以 Outlook 账号自身身份通过 Graph 发一封纯文本邮件(网页"基础写邮件")
struct ComposeView: View {
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss

    let account: MailAccount
    var replyTo: String = ""
    var replySubject: String = ""

    @State private var recipients = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false
    @FocusState private var focus: Field?

    private enum Field { case to, subject, body }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                row("发件人") {
                    Text(account.email).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Divider().padding(.leading, DS.Spacing.screen)
                row("收件人") {
                    TextField("多个地址用逗号或空格分隔", text: $recipients)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .to)
                }
                Divider().padding(.leading, DS.Spacing.screen)
                row("主题") {
                    TextField("", text: $subject).focused($focus, equals: .subject)
                }
                Divider()
                TextEditor(text: $bodyText)
                    .focused($focus, equals: .body)
                    .padding(.horizontal, DS.Spacing.screen - 5)
                    .overlay(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("正文(纯文本)")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, DS.Spacing.screen)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .padding(DS.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.surface)
                }
            }
            .navigationTitle("写邮件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("发送", systemImage: "paperplane.fill", action: send)
                            .disabled(parsedRecipients.isEmpty)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: sent)
            .onAppear {
                recipients = replyTo
                if !replySubject.isEmpty {
                    subject = replySubject.hasPrefix("Re:") ? replySubject : "Re: " + replySubject
                }
                focus = replyTo.isEmpty ? .to : .body
            }
        }
    }

    private var parsedRecipients: [String] {
        recipients.split(whereSeparator: { ",; \n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("@") }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Text(label).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            content()
        }
        .padding(.horizontal, DS.Spacing.screen)
        .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget, alignment: .leading)
    }

    private func send() {
        sending = true
        error = nil
        Task {
            do {
                _ = try await api.sendMail(accountId: account.id, recipients: parsedRecipients,
                                           subject: subject, body: bodyText)
                sent = true
                try? await Task.sleep(for: .milliseconds(300))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }
}
