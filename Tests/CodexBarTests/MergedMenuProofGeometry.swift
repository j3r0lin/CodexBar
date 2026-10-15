import AppKit
@testable import CodexBar

/// Menu geometry receipts and window captures shared by native menu proofs.
@MainActor
enum MergedMenuProofGeometry {
    static func phaseReceipt(menu: NSMenu, label: String, settings: SettingsStore) -> [String: Any] {
        let anyView = menu.items.lazy.compactMap(\.view).first { $0.window != nil }
        let window = anyView?.window
        var receipt: [String: Any] = [
            "phase": label,
            "selectedProvider": settings.selectedMenuProvider?.rawValue ?? "none",
            "overviewSelected": settings.mergedMenuLastSelectedWasOverview,
            "items": menu.numberOfItems,
            "menuSize": NSStringFromSize(menu.size),
            "window": window.map { NSStringFromRect($0.frame) } ?? "none",
        ]
        guard let anyView else { return receipt }
        var chain: [String] = []
        var representation: NSView?
        var clip: NSView?
        var node: NSView? = anyView.superview
        while let current = node {
            let name = String(describing: type(of: current))
            chain.append("\(name) \(NSStringFromRect(current.frame)) bounds=\(NSStringFromRect(current.bounds))")
            if representation == nil, name.contains("MenuRepresentation") { representation = current }
            if clip == nil, current is NSClipView { clip = current }
            node = current.superview
        }
        receipt["ancestorChain"] = chain
        receipt["menuItems"] = menu.items.enumerated().compactMap { index, item -> [String: Any]? in
            guard let view = item.view else { return nil }
            var rowFrame = "none"
            var node: NSView? = view.superview
            while let current = node {
                if current is NSTableRowView {
                    rowFrame = NSStringFromRect(current.frame)
                    break
                }
                node = current.superview
            }
            return [
                "index": index,
                "itemObject": String(UInt(bitPattern: ObjectIdentifier(item).hashValue), radix: 16),
                "viewObject": String(UInt(bitPattern: ObjectIdentifier(view).hashValue), radix: 16),
                "id": (item.representedObject as? String) ?? item.title,
                "view": String(describing: type(of: view)),
                "isCard": view is ErasedMenuCardHostingView,
                "viewFrame": NSStringFromRect(view.frame),
                "intrinsic": NSStringFromSize(view.intrinsicContentSize),
                "fitting": NSStringFromSize(view.fittingSize),
                "row": rowFrame,
            ]
        }
        receipt["tableHeight"] = representation.map { Double($0.frame.height) } ?? -1
        receipt["clipHeight"] = clip.map { Double($0.frame.height) } ?? -1
        receipt["clipOffsetY"] = clip.map { Double($0.bounds.minY) } ?? -1
        if let representation {
            let rows = representation.subviews.sorted { $0.frame.minY < $1.frame.minY }
            receipt["rowCount"] = rows.count
            receipt["rowHeightSum"] = Double(rows.reduce(0) { $0 + $1.frame.height })
            receipt["rows"] = rows.map { row -> [String: Any] in
                let content = Self.deepestCustomView(in: row)
                var entry: [String: Any] = [
                    "class": String(describing: type(of: row)),
                    "frame": NSStringFromRect(row.frame),
                ]
                if let content {
                    entry["content"] = String(describing: type(of: content))
                    entry["contentFrame"] = NSStringFromRect(content.frame)
                    entry["contentFitting"] = NSStringFromSize(content.fittingSize)
                    entry["contentIntrinsic"] = NSStringFromSize(content.intrinsicContentSize)
                    entry["rowMinusContentHeight"] = Double(row.frame.height - content.frame.height)
                }
                return entry
            }
        }
        return receipt
    }

    /// The menu item's own view inside a custom row (skipping AppKit's wrapper views).
    private static func deepestCustomView(in row: NSView) -> NSView? {
        var queue = row.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            let name = String(describing: type(of: view))
            if !name.hasPrefix("NS") || name.contains("Hosting") { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    static func capture(menu: NSMenu, to url: URL) {
        guard let window = menu.items.lazy.compactMap({ $0.view?.window }).first else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try? capture.run()
        capture.waitUntilExit()
        if capture.terminationStatus != 0 {
            let note = "screencapture exit \(capture.terminationStatus) window \(window.windowNumber) " +
                "frame \(NSStringFromRect(window.frame))"
            try? note.write(to: url.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        }
    }
}
