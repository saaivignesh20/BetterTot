import AppKit

enum BetterTotAppIcon {
    static func make(resourceURL: URL? = defaultResourceURL) -> NSImage {
        let image = resourceURL.flatMap(NSImage.init(contentsOf:))
            ?? NSApplication.shared.applicationIconImage
            ?? NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "BetterTot"
            )!
        image.accessibilityDescription = "BetterTot"
        return image
    }

    private static var defaultResourceURL: URL? {
        if let bundled = Bundle.main.url(forResource: "BetterTot", withExtension: "icns") {
            return bundled
        }
        return BrandResources.developmentAsset(named: "AppIcon.svg")
    }
}

enum MenuBarIcon {
    static func make(resourceURL: URL? = defaultResourceURL) -> NSImage {
        let image = resourceURL.flatMap(NSImage.init(contentsOf:))
            ?? NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "BetterTot scratchpad"
            )!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "BetterTot scratchpad"
        return image
    }

    private static var defaultResourceURL: URL? {
        if let bundled = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") {
            return bundled
        }
        return BrandResources.developmentAsset(named: "MenuBarIcon.png")
    }
}

private enum BrandResources {
    static func developmentAsset(named name: String) -> URL? {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let developmentAsset = repositoryRoot
            .appendingPathComponent("Assets")
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: developmentAsset.path)
            ? developmentAsset
            : nil
    }
}
