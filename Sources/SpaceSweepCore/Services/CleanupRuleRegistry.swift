import Foundation

/// The single, compiled-in source of every cleanup rule SpaceSweep knows about.
///
/// Classification is deliberately conservative: only two rules are Safe. Everything else is
/// Review (never selected automatically) or Protected (display-only).
public struct CleanupRuleRegistry: Sendable {
    public enum ID {
        public static let xcodeDerivedData = "xcode.derivedData"
        public static let npmCache = "npm.cache"
        public static let xcodeArchives = "xcode.archives"
        public static let xcodeDeviceSupport = "xcode.iosDeviceSupport"
        public static let xcodeWatchDeviceSupport = "xcode.watchOSDeviceSupport"
        public static let xcodePreviews = "xcode.previews"
        public static let simulatorCaches = "coreSimulator.caches"
        public static let simulatorDevices = "coreSimulator.devices"
        public static let yarnCache = "yarn.cache"
        public static let pnpmStore = "pnpm.store"
        public static let homebrewDownloads = "homebrew.downloads"
        public static let cocoaPodsCache = "cocoapods.cache"
        public static let swiftPMCache = "swiftpm.cache"
        public static let pipCache = "pip.cache"
        public static let goBuildCache = "go.buildCache"
        public static let chromeCache = "browser.chrome"
        public static let edgeCache = "browser.edge"
        public static let braveCache = "browser.brave"
        public static let firefoxCache = "browser.firefox"
        public static let thirdPartyCaches = "caches.thirdParty"
        public static let diagnosticReports = "logs.diagnosticReports"
        public static let trash = "user.trash"
        public static let iosBackups = "backups.ios"
        public static let xcodeDocumentationCache = "xcode.documentationCache"
        public static let vsCodeCaches = "editor.vscode"
        public static let cursorCaches = "editor.cursor"
        public static let slackCaches = "app.slack"
        public static let discordCaches = "app.discord"
        public static let spotifyCache = "app.spotify"
        public static let toolCaches = "dev.dotCache"
        public static let gradleCaches = "gradle.caches"
        public static let mavenRepository = "maven.repository"
        public static let bunCache = "bun.cache"
        public static let cargoRegistry = "cargo.registry"
        public static let cocoaPodsRepos = "cocoapods.specRepos"
        public static let androidSystemImages = "android.systemImages"
    }

    /// Cache folders Electron/Chromium-based apps keep inside their Application Support folder.
    /// Profiles, settings, local storage and IndexedDB are siblings of these and are never included.
    static func electronCacheRoots(_ app: String, extra: [[String]] = []) -> [[String]] {
        let base: [String] = ["Library", "Application Support", app]
        let folders: [[String]] = [
            ["Cache"], ["Code Cache"], ["GPUCache"], ["DawnGraphiteCache"], ["DawnWebGPUCache"],
            ["Service Worker", "CacheStorage"],
        ]
        var roots: [[String]] = []
        for folder in folders + extra {
            roots.append(base + folder)
        }
        return roots
    }

    public let rules: [CleanupRule]

    public init(rules: [CleanupRule] = CleanupRuleRegistry.builtInRules) {
        self.rules = rules
    }

    public static let standard = CleanupRuleRegistry()

    public func rule(id: String) -> CleanupRule? { rules.first { $0.id == id } }

    public var developerRules: [CleanupRule] { rules.filter(\.isDeveloperRule) }

    /// Locations that are too broad for a Safe rule's root.
    public static let broadRoots: [[String]] = [
        [], ["Library"], ["Library", "Caches"], ["Library", "Application Support"], ["Library", "Developer"],
        ["Library", "Logs"], ["Library", "Developer", "Xcode"], ["Library", "Developer", "CoreSimulator"],
    ]

    // MARK: Built-in rules

    public static let builtInRules: [CleanupRule] = [
        // ── Safe ───────────────────────────────────────────────────────────
        CleanupRule(
            id: ID.xcodeDerivedData,
            title: "Xcode DerivedData",
            summary: "Build products and indexes Xcode recreates on the next build.",
            explanation: "DerivedData holds intermediate build files, module caches and the code index for each project. Xcode regenerates all of it automatically. Only the per-project folders inside DerivedData are removed — never the DerivedData folder itself, and never your source code.",
            consequence: "Your next build and indexing pass will take longer while Xcode rebuilds this data.",
            tier: .safe,
            category: .xcode,
            symbolName: "hammer.fill",
            rootComponents: ["Library", "Developer", "Xcode", "DerivedData"],
            requiresClosedApps: [.xcode],
            defaultSelected: true,
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.npmCache,
            title: "npm cache",
            summary: "npm’s content-addressable download cache (~/.npm/_cacache).",
            explanation: "npm stores downloaded package tarballs and metadata in _cacache. It is a cache only — your projects and their node_modules folders are untouched. This is the same data `npm cache clean --force` removes.",
            consequence: "Packages are re-downloaded the next time you install them. Offline installs of uncached packages won’t work until then. Avoid cleaning while an npm install is running.",
            tier: .safe,
            category: .packageManager,
            symbolName: "shippingbox.fill",
            rootComponents: [".npm", "_cacache"],
            defaultSelected: true,
            isDeveloperRule: true
        ),

        // ── Review: developer ──────────────────────────────────────────────
        CleanupRule(
            id: ID.xcodeArchives,
            title: "Xcode Archives",
            summary: "Archived builds created with Product › Archive.",
            explanation: "Archives may be the only copy of a build you shipped, including the dSYMs needed to symbolicate crash reports. Review each archive by date before removing it.",
            consequence: "Removed archives cannot be re-exported, re-uploaded or used to symbolicate crashes.",
            tier: .review,
            category: .xcode,
            symbolName: "archivebox.fill",
            rootComponents: ["Library", "Developer", "Xcode", "Archives"],
            requiresClosedApps: [.xcode],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.xcodeDeviceSupport,
            title: "iOS Device Support",
            summary: "Debug symbols copied from devices you’ve connected.",
            explanation: "Xcode copies system symbols from each iOS version you debug on. Old versions are often unused, but removing a version you still debug against forces Xcode to copy it again.",
            consequence: "Xcode re-copies symbols (which can take several minutes) the next time you debug on that iOS version.",
            tier: .review,
            category: .xcode,
            symbolName: "iphone",
            rootComponents: ["Library", "Developer", "Xcode", "iOS DeviceSupport"],
            requiresClosedApps: [.xcode],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.xcodeWatchDeviceSupport,
            title: "watchOS Device Support",
            summary: "Debug symbols copied from paired Apple Watches.",
            explanation: "Like iOS Device Support, these symbols are copied per watchOS version and are re-created when needed.",
            consequence: "Xcode re-copies symbols the next time you debug on that watchOS version.",
            tier: .review,
            category: .xcode,
            symbolName: "applewatch",
            rootComponents: ["Library", "Developer", "Xcode", "watchOS DeviceSupport"],
            requiresClosedApps: [.xcode],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.xcodePreviews,
            title: "SwiftUI Previews",
            summary: "Simulator data used by Xcode previews.",
            explanation: "Xcode Previews keeps its own simulator devices and build products. They are recreated, but may hold preview state.",
            consequence: "The first preview after cleaning will take longer to appear.",
            tier: .review,
            category: .xcode,
            symbolName: "rectangle.on.rectangle",
            rootComponents: ["Library", "Developer", "Xcode", "UserData", "Previews"],
            requiresClosedApps: [.xcode, .simulator],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.simulatorCaches,
            title: "Simulator caches",
            summary: "CoreSimulator’s shared caches (dyld and runtime caches).",
            explanation: "These caches speed up simulator launches and are rebuilt automatically. Simulator devices and their app data live elsewhere and are not included.",
            consequence: "The next simulator boot will be slower while caches rebuild.",
            tier: .review,
            category: .simulator,
            symbolName: "square.stack.3d.up.fill",
            rootComponents: ["Library", "Developer", "CoreSimulator", "Caches"],
            requiresClosedApps: [.xcode, .simulator],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.yarnCache,
            title: "Yarn cache",
            summary: "Yarn Classic’s global package cache.",
            explanation: "Yarn keeps every downloaded package here. It is a cache, but offline installs depend on it.",
            consequence: "Packages are downloaded again on the next install.",
            tier: .review,
            category: .packageManager,
            symbolName: "shippingbox",
            rootComponents: ["Library", "Caches", "Yarn"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.pnpmStore,
            title: "pnpm store",
            summary: "pnpm’s content-addressable package store.",
            explanation: "Projects installed with pnpm hard-link packages from this store. Removing it is recoverable but forces a re-download, and existing node_modules may need reinstalling.",
            consequence: "Run `pnpm install` again in your projects afterwards.",
            tier: .review,
            category: .packageManager,
            symbolName: "cube.box.fill",
            rootComponents: ["Library", "pnpm", "store"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.homebrewDownloads,
            title: "Homebrew downloads",
            summary: "Downloaded bottles and source archives in Homebrew’s cache.",
            explanation: "Only the downloads folder of Homebrew’s cache is offered. Installed formulae, casks, the Cellar and /opt/homebrew are never touched.",
            consequence: "Homebrew downloads files again if you reinstall or upgrade.",
            tier: .review,
            category: .packageManager,
            symbolName: "mug.fill",
            rootComponents: ["Library", "Caches", "Homebrew", "downloads"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.cocoaPodsCache,
            title: "CocoaPods cache",
            summary: "Downloaded pod sources and specs.",
            explanation: "CocoaPods caches pods it has downloaded. Your Pods folders and Podfile.lock are not affected.",
            consequence: "Pods are downloaded again on the next `pod install`.",
            tier: .review,
            category: .packageManager,
            symbolName: "leaf.fill",
            rootComponents: ["Library", "Caches", "CocoaPods"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.swiftPMCache,
            title: "Swift Package Manager cache",
            summary: "Shared repository and artifact cache used by SwiftPM and Xcode.",
            explanation: "SwiftPM caches package repositories and binary artifacts here. Package.resolved and your packages’ checkouts are separate.",
            consequence: "Package dependencies are fetched again on the next resolve.",
            tier: .review,
            category: .packageManager,
            symbolName: "swift",
            rootComponents: ["Library", "Caches", "org.swift.swiftpm"],
            requiresClosedApps: [.xcode],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.pipCache,
            title: "pip cache",
            summary: "Python package downloads and built wheels.",
            explanation: "pip caches downloaded packages and locally built wheels. Installed packages and virtual environments are untouched.",
            consequence: "Packages are downloaded (and possibly rebuilt) on the next install.",
            tier: .review,
            category: .packageManager,
            symbolName: "chevron.left.forwardslash.chevron.right",
            rootComponents: ["Library", "Caches", "pip"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.goBuildCache,
            title: "Go build cache",
            summary: "Compiled package cache used by `go build` and `go test`.",
            explanation: "Go keeps compiled packages and test results here. It is rebuilt on demand.",
            consequence: "The next Go build or test run will be slower.",
            tier: .review,
            category: .packageManager,
            symbolName: "bolt.horizontal.fill",
            rootComponents: ["Library", "Caches", "go-build"],
            isDeveloperRule: true
        ),

        // ── Review: editors, apps and dev tools ────────────────────────────
        CleanupRule(
            id: ID.vsCodeCaches,
            title: "Visual Studio Code caches",
            summary: "Editor caches, compiled-code cache and downloaded extension installers.",
            explanation: "VS Code (an Electron app) keeps its web cache, GPU and compiled-code caches, cached data and downloaded extension packages (.vsix) in Application Support. Only those cache folders are offered — your settings, extensions, workspaces and history are separate and never touched.",
            consequence: "VS Code may start a little slower once while caches rebuild.",
            tier: .review,
            category: .devTools,
            symbolName: "chevron.left.forwardslash.chevron.right",
            rootComponents: ["Library", "Application Support", "Code", "CachedData"],
            additionalRoots: electronCacheRoots("Code", extra: [["CachedExtensionVSIXs"]]),
            requiresClosedApps: [.vsCode],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.cursorCaches,
            title: "Cursor caches",
            summary: "Editor caches and downloaded extension installers.",
            explanation: "Cursor is built on VS Code and keeps the same kinds of cache folders in Application Support. Settings, extensions, chats and workspaces are separate and never touched.",
            consequence: "Cursor may start a little slower once while caches rebuild.",
            tier: .review,
            category: .devTools,
            symbolName: "cursorarrow.rays",
            rootComponents: ["Library", "Application Support", "Cursor", "CachedData"],
            additionalRoots: electronCacheRoots("Cursor", extra: [["CachedExtensionVSIXs"]]),
            requiresClosedApps: [.cursor],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.xcodeDocumentationCache,
            title: "Xcode documentation cache",
            summary: "Downloaded and indexed developer documentation.",
            explanation: "Xcode caches documentation it has downloaded and indexed. It is fetched again when you open the documentation viewer.",
            consequence: "Documentation is downloaded again the next time you browse it.",
            tier: .review,
            category: .xcode,
            symbolName: "book.closed.fill",
            rootComponents: ["Library", "Developer", "Xcode", "DocumentationCache"],
            requiresClosedApps: [.xcode],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.toolCaches,
            title: "Tool caches (~/.cache)",
            summary: "Shared cache folder used by many command-line tools.",
            explanation: "Tools such as Hugging Face, pre-commit, node-gyp, Puppeteer and others keep downloads here, one folder per tool. Everything here is a cache, but some downloads (like AI models) are large and slow to fetch again — review each folder.",
            consequence: "Each tool re-downloads what it needs the next time it runs.",
            tier: .review,
            category: .devTools,
            symbolName: "terminal.fill",
            rootComponents: [".cache"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.gradleCaches,
            title: "Gradle caches",
            summary: "Downloaded dependencies and build caches used by Gradle and Android Studio.",
            explanation: "Gradle keeps every downloaded dependency and build-cache entry here. Your projects are untouched.",
            consequence: "The next Gradle build re-downloads dependencies and runs slower.",
            tier: .review,
            category: .packageManager,
            symbolName: "square.stack.3d.down.right.fill",
            rootComponents: [".gradle", "caches"],
            requiresClosedApps: [.androidStudio],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.mavenRepository,
            title: "Maven local repository",
            summary: "Downloaded Java/Kotlin dependencies (~/.m2/repository).",
            explanation: "Maven and many JVM tools download dependencies here. Anything you installed locally with `mvn install` lives here too, so review before cleaning.",
            consequence: "Dependencies are downloaded again on the next build. Locally installed artifacts must be rebuilt.",
            tier: .review,
            category: .packageManager,
            symbolName: "cup.and.saucer.fill",
            rootComponents: [".m2", "repository"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.bunCache,
            title: "Bun cache",
            summary: "Bun’s global package install cache.",
            explanation: "Bun stores downloaded packages here and links them into projects. Projects and their node_modules are untouched.",
            consequence: "Packages are downloaded again on the next `bun install`.",
            tier: .review,
            category: .packageManager,
            symbolName: "takeoutbag.and.cup.and.straw.fill",
            rootComponents: [".bun", "install", "cache"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.cargoRegistry,
            title: "Cargo registry cache",
            summary: "Downloaded and unpacked Rust crates.",
            explanation: "Cargo keeps downloaded crate archives and their unpacked sources here. Your projects, installed binaries and toolchains are untouched.",
            consequence: "Crates are downloaded again on the next build.",
            tier: .review,
            category: .packageManager,
            symbolName: "gearshape.2.fill",
            rootComponents: [".cargo", "registry", "cache"],
            additionalRoots: [[".cargo", "registry", "src"]],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.cocoaPodsRepos,
            title: "CocoaPods spec repos",
            summary: "Local copies of CocoaPods spec repositories.",
            explanation: "Older CocoaPods setups clone the entire Specs repository locally, which can be several gigabytes. Modern CocoaPods uses the CDN instead.",
            consequence: "Run `pod repo update` (or use the CDN source) if a project still needs them.",
            tier: .review,
            category: .packageManager,
            symbolName: "leaf",
            rootComponents: [".cocoapods", "repos"],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.androidSystemImages,
            title: "Android emulator system images",
            summary: "Downloaded Android system images used by emulators.",
            explanation: "Each Android version you’ve created an emulator for downloads a multi-gigabyte system image. Emulators that use a removed image stop working until it’s downloaded again.",
            consequence: "Re-download images in Android Studio › SDK Manager when you need them.",
            tier: .review,
            category: .devTools,
            symbolName: "smartphone",
            rootComponents: ["Library", "Android", "sdk", "system-images"],
            requiresClosedApps: [.androidStudio],
            isDeveloperRule: true
        ),
        CleanupRule(
            id: ID.slackCaches,
            title: "Slack caches",
            summary: "Slack’s web and media caches. Messages and sign-in are untouched.",
            explanation: "The Slack desktop app keeps web, code and media caches in Application Support. Your workspaces and sign-in live elsewhere and are never touched. (The App Store version stores data in a container SpaceSweep doesn’t access.)",
            consequence: "Images and files are downloaded again as you view them.",
            tier: .review,
            category: .appCache,
            symbolName: "number",
            rootComponents: ["Library", "Application Support", "Slack", "Cache"],
            additionalRoots: Array(electronCacheRoots("Slack").dropFirst()),
            requiresClosedApps: [.slack]
        ),
        CleanupRule(
            id: ID.discordCaches,
            title: "Discord caches",
            summary: "Discord’s web and media caches. Messages and sign-in are untouched.",
            explanation: "Discord keeps web, code and media caches in Application Support. Settings and sign-in live elsewhere and are never touched.",
            consequence: "Images and media are downloaded again as you view them.",
            tier: .review,
            category: .appCache,
            symbolName: "bubble.left.and.bubble.right.fill",
            rootComponents: ["Library", "Application Support", "discord", "Cache"],
            additionalRoots: Array(electronCacheRoots("discord").dropFirst()),
            requiresClosedApps: [.discord]
        ),
        CleanupRule(
            id: ID.spotifyCache,
            title: "Spotify streaming cache",
            summary: "Cached streamed music. Downloaded playlists are kept by Spotify itself.",
            explanation: "Spotify caches streamed audio in PersistentCache. You can also cap its size in Spotify › Settings › Storage.",
            consequence: "Songs stream again instead of playing from cache.",
            tier: .review,
            category: .appCache,
            symbolName: "music.note",
            rootComponents: ["Library", "Application Support", "Spotify", "PersistentCache"],
            requiresClosedApps: [.spotify]
        ),

        // ── Review: browsers (cache folders only) ──────────────────────────
        CleanupRule(
            id: ID.chromeCache,
            title: "Google Chrome cache",
            summary: "Web cache only. Cookies, history, passwords and profiles are untouched.",
            explanation: "Chrome keeps its disk cache under ~/Library/Caches. Profiles, cookies, saved passwords and history live in Application Support, which SpaceSweep never touches.",
            consequence: "Websites may load more slowly the first time you revisit them.",
            tier: .review,
            category: .browser,
            symbolName: "globe",
            rootComponents: ["Library", "Caches", "Google", "Chrome"],
            requiresClosedApps: [.chrome]
        ),
        CleanupRule(
            id: ID.edgeCache,
            title: "Microsoft Edge cache",
            summary: "Web cache only. Cookies, history, passwords and profiles are untouched.",
            explanation: "Edge keeps its disk cache under ~/Library/Caches. Profiles and site data live elsewhere and are never touched.",
            consequence: "Websites may load more slowly the first time you revisit them.",
            tier: .review,
            category: .browser,
            symbolName: "globe",
            rootComponents: ["Library", "Caches", "Microsoft Edge"],
            requiresClosedApps: [.edge]
        ),
        CleanupRule(
            id: ID.braveCache,
            title: "Brave cache",
            summary: "Web cache only. Cookies, history, passwords and profiles are untouched.",
            explanation: "Brave keeps its disk cache under ~/Library/Caches. Profiles and site data live elsewhere and are never touched.",
            consequence: "Websites may load more slowly the first time you revisit them.",
            tier: .review,
            category: .browser,
            symbolName: "globe",
            rootComponents: ["Library", "Caches", "BraveSoftware", "Brave-Browser"],
            requiresClosedApps: [.brave]
        ),
        CleanupRule(
            id: ID.firefoxCache,
            title: "Firefox cache",
            summary: "Web cache only. Profiles, cookies and passwords are untouched.",
            explanation: "Firefox stores its network cache per profile under ~/Library/Caches/Firefox. The profiles themselves live in Application Support and are never touched.",
            consequence: "Websites may load more slowly the first time you revisit them.",
            tier: .review,
            category: .browser,
            symbolName: "globe",
            rootComponents: ["Library", "Caches", "Firefox"],
            requiresClosedApps: [.firefox]
        ),

        // ── Review: general ────────────────────────────────────────────────
        CleanupRule(
            id: ID.thirdPartyCaches,
            title: "Other app caches",
            summary: "Per-app folders in ~/Library/Caches, listed one by one.",
            explanation: "Apps may store anything here, and SpaceSweep can’t prove each folder is disposable, so every folder is review-only and listed individually. Apple’s own caches are excluded, as are folders covered by a more specific rule. A folder named after a running app is blocked until that app quits.",
            consequence: "Apps usually rebuild their caches, but may be slower, lose offline content, or need you to sign in again.",
            tier: .review,
            category: .appCache,
            symbolName: "square.grid.2x2.fill",
            rootComponents: ["Library", "Caches"],
            excludedChildNames: [
                "CloudKit", "GeoServices", "FamilyCircle", "PassKit", "Metadata", "SiriTTS", "storeassetd",
                "familycircled", "AMSDataMigratorTool", "TemporaryItems", "Homebrew", "com.plausiblelabs.crashreporter.data",
            ],
            excludedChildPrefixes: ["com.apple.", "Apple", "."],
            blocksChildrenNamedAfterRunningApps: true
        ),
        CleanupRule(
            id: ID.diagnosticReports,
            title: "Old diagnostic reports",
            summary: "Crash and hang reports older than 14 days.",
            explanation: "macOS writes a report each time an app crashes or hangs. Reports from the last 14 days are kept so recent problems can still be investigated.",
            consequence: "Removed reports can’t be sent to developers or inspected later.",
            tier: .review,
            category: .logs,
            symbolName: "doc.text.magnifyingglass",
            rootComponents: ["Library", "Logs", "DiagnosticReports"],
            minimumAgeDays: 14,
            excludedChildPrefixes: ["."]
        ),
        CleanupRule(
            id: ID.trash,
            title: "Trash",
            summary: "Items you’ve moved to the Trash.",
            explanation: "These are your own files. Emptying the Trash removes them permanently — they cannot be recovered afterwards. The Trash is never included in One-click Safe Clean.",
            consequence: "Items are permanently removed and cannot be put back.",
            tier: .review,
            category: .trash,
            symbolName: "trash.fill",
            rootComponents: [".Trash"],
            excludedChildNames: [".DS_Store"],
            mayNeedFullDiskAccess: true,
            removesUserFilesPermanently: true
        ),

        // ── Protected: display-only ────────────────────────────────────────
        CleanupRule(
            id: ID.simulatorDevices,
            title: "Simulator devices",
            summary: "Simulator devices, their installed apps and data.",
            explanation: "Each simulator device holds app data and state you may rely on. SpaceSweep only shows the size.",
            consequence: "Not cleaned by SpaceSweep.",
            tier: .protected,
            category: .simulator,
            symbolName: "ipad.and.iphone",
            rootComponents: ["Library", "Developer", "CoreSimulator", "Devices"],
            scope: .displayOnlyAggregate,
            isDeveloperRule: true,
            managementHint: "Manage simulators in Xcode › Window › Devices and Simulators, or remove unavailable devices with `xcrun simctl delete unavailable` in Terminal."
        ),
        CleanupRule(
            id: ID.iosBackups,
            title: "iPhone & iPad backups",
            summary: "Local device backups made by Finder.",
            explanation: "Backups may be the only copy of a device’s data. SpaceSweep only shows their size.",
            consequence: "Not cleaned by SpaceSweep.",
            tier: .protected,
            category: .backups,
            symbolName: "externaldrive.fill.badge.timemachine",
            rootComponents: ["Library", "Application Support", "MobileSync", "Backup"],
            scope: .displayOnlyAggregate,
            mayNeedFullDiskAccess: true,
            managementHint: "Connect the device, select it in the Finder sidebar, then choose Manage Backups."
        ),
    ]
}
