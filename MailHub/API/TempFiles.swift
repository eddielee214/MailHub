import Foundation

/// 附件和导出文件的临时目录。导出文件含明文密码和 Token，用完(分享面板关闭)和每次启动都清空
enum TempFiles {
    static var root: URL { FileManager.default.temporaryDirectory.appending(path: "MailHubFiles") }

    static func newFolder() throws -> URL {
        let dir = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    static func purge() {
        try? FileManager.default.removeItem(at: root)
    }
}
