//
//  ShareSheet.swift
//  MeetingScribe
//
//  Component chia sẻ file / văn bản chuẩn UIActivityViewController
//

import SwiftUI
import UIKit

public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Trình bày bảng chia sẻ hệ thống (UIActivityViewController) TRỰC TIẾP từ UIKit.
///
/// Vì sao không dùng `.sheet { ShareSheet(items:) }`:
/// Trên iOS 16+ (và càng rõ ở iOS 18/26), nhúng UIActivityViewController vào một
/// SwiftUI `.sheet` khiến bảng chia sẻ render thành một ô ĐEN/TRỐNG (chỉ thấy nền,
/// không thấy danh sách ứng dụng). Nguyên nhân là activity view controller là một
/// remote view controller, nó cần được present bởi một view controller ĐANG hiển thị
/// thật (không phải một UIViewController con vừa được tạo bên trong sheet).
///
/// Cách chuẩn: lấy view controller trên cùng của window hiện tại rồi `present()` nó.
public enum ShareSheetPresenter {

    /// Chia sẻ danh sách item (URL file, String, UIImage…) bằng bảng chia sẻ hệ thống.
    /// - Parameters:
    ///   - items: Danh sách item cần chia sẻ (phải không rỗng).
    ///   - completion: Gọi sau khi người dùng đóng bảng chia sẻ.
    @MainActor
    public static func present(items: [Any], completion: (() -> Void)? = nil) {
        guard !items.isEmpty, let host = topViewController() else { return }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }

        // iPad / chế độ cửa sổ: bắt buộc có anchor cho popover, nếu không sẽ crash.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(
                x: host.view.bounds.midX,
                y: host.view.bounds.maxY - 1,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        host.present(activity, animated: true)
    }

    /// Chia sẻ 1 file, kiểm tra tồn tại trước để tránh bảng chia sẻ rỗng.
    /// - Returns: `false` nếu file không tồn tại (khi đó không hiển thị gì).
    @MainActor
    @discardableResult
    public static func presentFile(at url: URL, completion: (() -> Void)? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        present(items: [url], completion: completion)
        return true
    }

    /// View controller đang hiển thị trên cùng (đi xuyên qua navigation/tab/sheet).
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first

        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

