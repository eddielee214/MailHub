import Foundation

/// 把邮件正文包成给 WKWebView 用的完整 HTML(普通邮件和临时邮件共用)
enum MailHTML {
    static func wrap(_ d: MailDetail, allowRemote: Bool) -> String {
        let body = d.body ?? ""
        let content: String
        if d.bodyType == "html" {
            content = body
        } else {
            let escaped = body
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            content = "<pre class=\"plain\">\(escaped)</pre>"
        }
        // 隐私：脚本、表单、内嵌网页一律不许；远程图片/样式/字体只有允许时才能加载。
        // CSP 只认 <head> 里的 meta，邮件正文里自带的 meta 落在 body 里，放不宽这条规则。
        let remote = allowRemote ? "https: http:" : ""
        let csp = "default-src 'none'; img-src data: cid: \(remote); style-src 'unsafe-inline' \(remote); "
            + "font-src data: \(remote); media-src \(remote); form-action 'none'"
        // 邮件 HTML 大多按浅色背景写的，所以正文区固定用白底
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta http-equiv="x-dns-prefetch-control" content="off">
        <meta name="referrer" content="no-referrer">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0 16px 24px; font: -apple-system-body; background: #fff; color: #111; word-wrap: break-word; }
        img { max-width: 100%; height: auto; }
        \(allowRemote ? "" : "img:not([src^='data:']):not([src^='cid:']) { background: #eef1f6; border-radius: 4px; border: 0; }")
        pre.plain { white-space: pre-wrap; font: -apple-system-body; margin: 0; }
        </style></head><body>\(content)</body></html>
        """
    }
}
