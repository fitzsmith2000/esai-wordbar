import AppKit
import Carbon
import CryptoKit
import SQLite3
import SwiftUI
import WebKit

private struct AccentPreset: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
    static let choices = [
        AccentPreset(name: "esai 绿", hex: "#0A8552"),
        AccentPreset(name: "经典蓝", hex: "#2878ED"),
        AccentPreset(name: "鸢尾紫", hex: "#8054D6"),
        AccentPreset(name: "琥珀橙", hex: "#C66A08"),
        AccentPreset(name: "玫瑰红", hex: "#D5446F"),
        AccentPreset(name: "湖水青", hex: "#008A93")
    ]
}

private struct AccentRGB {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let bits = UInt32(digits, radix: 16) else { return nil }
        red = Double((bits >> 16) & 255) / 255
        green = Double((bits >> 8) & 255) / 255
        blue = Double(bits & 255) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()),
            Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    private var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func readable(onDark: Bool) -> AccentRGB {
        var value = self
        for _ in 0..<32 {
            if onDark ? value.luminance >= 0.32 : value.luminance <= 0.17 { break }
            let target = onDark ? 1.0 : 0.0
            value = AccentRGB(red: value.red * 0.94 + target * 0.06,
                green: value.green * 0.94 + target * 0.06,
                blue: value.blue * 0.94 + target * 0.06)
        }
        return value
    }
}

// Surface levels and hairlines follow esai's panel design tokens.
private enum WordSurface {
    static let raised = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.065) : NSColor.black.withAlphaComponent(0.045)
    })
    static let sunken = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.045) : NSColor.black.withAlphaComponent(0.03)
    })
    static let hairline = Color(nsColor: .separatorColor)
}

private struct WordCardSurface: ViewModifier {
    let raised: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background(raised ? WordSurface.raised : WordSurface.sunken, in: shape)
            .overlay {
                if colorScheme == .dark { shape.strokeBorder(WordSurface.hairline, lineWidth: 1) }
            }
    }
}

private extension View {
    func wordCard(raised: Bool = true) -> some View { modifier(WordCardSurface(raised: raised)) }
}

private struct WordFooterAction: View {
    let title: String
    let symbol: String
    let destructive: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(hovered ? (destructive ? Color.red : Color.primary) : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(hovered ? Color.primary.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

private struct WordGradeAction: View {
    let title: String
    let shortcut: String
    let hoverColor: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(hovered ? hoverColor : Color.secondary)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(hovered ? hoverColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(shortcut)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct WordSense: Codable {
    let pos: String
    let zh: String
    let en: String
}

struct WordExample: Codable {
    let en: String
    let zh: String
}

struct WordEntry: Codable, Identifiable {
    let w: String
    let uk: String
    let us: String
    let senses: [WordSense]
    let ex: [WordExample]
    let col: [String]
    let fam: [String]
    let syn: [String]
    let ant: [String]
    let tip: String
    let cefr: String
    let topic: String
    let note: String
    let id: String
}

struct CustomBook: Codable, Identifiable {
    let id: String
    let title: String
    let words: [WordEntry]
}

private struct FreemdictBook: Identifiable {
    let id: String
    let title: String
    let detail: String
    let filename: String
    let sha256: String

    var url: URL {
        let base = "https://downloads.freemdict.com/100G_Super_Big_Collection/%E8%8B%B1%E8%AF%AD/%E6%99%AE%E9%80%9A%E8%AF%8D%E5%85%B8/%5B%E8%8B%B1-%E6%B1%89%5D/"
        return URL(string: base + filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
    }

    static let choices = [
        FreemdictBook(id: "freemdict.exam900", title: "英语考点 900", detail: "入门巩固 · 英汉释义与例句 · 约 240 KB",
            filename: "[英-汉] ◆考点900词典【匿名原创】【版本日期未注明】.mdx",
            sha256: "a75a2355d7e20108ea86fab2a2c36a41c8ca4b02bd8e281620789322770934f0"),
        FreemdictBook(id: "freemdict.kaoyan", title: "考研核心", detail: "考研高频 · 英汉释义 · 约 380 KB",
            filename: "[英-汉] ◆考研核心词典【匿名原创】【版本日期未注明】.mdx",
            sha256: "6956865db5df487b2e0d67b614915d1ac6376161703856003cc3f8842872e1e8"),
        FreemdictBook(id: "freemdict.toefl", title: "托福专题", detail: "托福备考 · 含音标与英汉释义 · 约 200 KB",
            filename: "[英-汉] 《TOEFL iBT -新托福词汇专题突破》[2145](090428).mdx",
            sha256: "38f239e480e0d52255cf0f9303b5bd74b3fc08d0b9edabab02ed94de674597c3"),
        FreemdictBook(id: "freemdict.sat", title: "SAT 基础 3500", detail: "SAT 备考 · 英汉释义与英文解释 · 约 410 KB",
            filename: "[英-汉] 《Barron's SAT 3500 巴朗SAT基础词汇》[3366](090730).mdx",
            sha256: "a90d7c019834d9c395f52e487dd67f9771d0622baa1f3ba6ec857307568fc7cd")
    ]
}

private struct PopularBook: Identifiable {
    let id: String
    let title: String
    let detail: String
    let filename: String
    let sha256: String
    var url: URL { URL(string: "https://raw.githubusercontent.com/grhliu/wordtyper-vocabularies/b5790cafcad1795873410e984c834ef1ddac20ac/vocabularies/\(filename).json")! }
    static let choices = [
        PopularBook(id: "popular.cet4", title: "大学英语四级", detail: "CET-4 · 约 3,815 词", filename: "cet4", sha256: "568b5203eb6b48bdecf8deb8d5ad3bc6546b7960c72e9eafcd877242b6b70105"),
        PopularBook(id: "popular.cet6", title: "大学英语六级", detail: "CET-6 · 约 5,371 词", filename: "cet6", sha256: "216de305c1838b7dd5d473d80e5606838abdc8d2780509893bf623d37ad60dd5"),
        PopularBook(id: "popular.ielts", title: "雅思高频词汇", detail: "IELTS · 约 4,974 词", filename: "ielts_core", sha256: "faf6705f919ae9a6cd6270bdcf6ce47bab314f8d91a74dae6b6d7bac0c76bf3c"),
        PopularBook(id: "popular.gre", title: "GRE 词汇", detail: "GRE · 约 7,485 词", filename: "gre", sha256: "2bb3065cb6f47ee3cf12c4ea87abfcdf2ff7f2e11dd184af208bbeec7e355b25"),
        PopularBook(id: "popular.gmat", title: "GMAT 学术词汇", detail: "GMAT 方向 · 约 2,996 词", filename: "gmat", sha256: "7f77a31a304cf860deb6be4e255c60e856c184627cd2d3a770ca45c4a9c79454")
    ]
}

private struct PopularBookFile: Decodable {
    struct Item: Decodable {
        let word: String
        let phonetic: String
        let translations: [String]
    }
    let words: [Item]
}

struct ReviewState: Codable {
    var interval: Int
    var due: Date
    var seen: Int
    var last: Date
}

struct WordHotKey: Codable, Equatable {
    let code: UInt32
    let modifiers: UInt32
    let label: String
    static let next = WordHotKey(code: UInt32(kVK_F10), modifiers: UInt32(optionKey), label: "⌥ F10")
    static let previous = WordHotKey(code: UInt32(kVK_F10), modifiers: UInt32(optionKey | shiftKey), label: "⌥ ⇧ F10")
    static let meaning = WordHotKey(code: UInt32(kVK_F9), modifiers: UInt32(optionKey | shiftKey), label: "⌥ ⇧ F9")
    static let forgot = WordHotKey(code: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey | cmdKey), label: "⌥ ⌘ 1")
    static let uncertain = WordHotKey(code: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey | cmdKey), label: "⌥ ⌘ 2")
    static let known = WordHotKey(code: UInt32(kVK_ANSI_3), modifiers: UInt32(optionKey | cmdKey), label: "⌥ ⌘ 3")
    static let keyNames: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        UInt32(kVK_PageUp): "PgUp", UInt32(kVK_PageDown): "PgDn",
        UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Return): "↩", UInt32(kVK_ANSI_KeypadEnter): "小键盘 Enter",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Space): "空格", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "Esc", UInt32(kVK_Help): "Help",
        UInt32(kVK_ANSI_Keypad0): "小键盘 0", UInt32(kVK_ANSI_Keypad1): "小键盘 1",
        UInt32(kVK_ANSI_Keypad2): "小键盘 2", UInt32(kVK_ANSI_Keypad3): "小键盘 3",
        UInt32(kVK_ANSI_Keypad4): "小键盘 4", UInt32(kVK_ANSI_Keypad5): "小键盘 5",
        UInt32(kVK_ANSI_Keypad6): "小键盘 6", UInt32(kVK_ANSI_Keypad7): "小键盘 7",
        UInt32(kVK_ANSI_Keypad8): "小键盘 8", UInt32(kVK_ANSI_Keypad9): "小键盘 9",
        UInt32(kVK_ANSI_KeypadDecimal): "小键盘 .", UInt32(kVK_ANSI_KeypadPlus): "小键盘 +",
        UInt32(kVK_ANSI_KeypadMinus): "小键盘 −", UInt32(kVK_ANSI_KeypadMultiply): "小键盘 ×",
        UInt32(kVK_ANSI_KeypadDivide): "小键盘 ÷", UInt32(kVK_ANSI_KeypadEquals): "小键盘 =",
        UInt32(kVK_ANSI_KeypadClear): "小键盘 Clear"
    ]
    var displayLabel: String {
        guard let key = Self.keyNames[code] else {
            return label.unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) })
                ? "未识别按键，请重新录制" : label
        }
        return "\(modifiers & UInt32(controlKey) != 0 ? "⌃ " : "")\(modifiers & UInt32(optionKey) != 0 ? "⌥ " : "")\(modifiers & UInt32(shiftKey) != 0 ? "⇧ " : "")\(modifiers & UInt32(cmdKey) != 0 ? "⌘ " : "")\(key)"
    }
}

@MainActor final class WordModel: ObservableObject {
    let updates = UpdateService(enabled: !CommandLine.arguments.contains("--preview"))
    @Published private(set) var selectedBookID: String
    @Published private(set) var selectedDictionaryID: String
    @Published private(set) var queue: [WordEntry] = []
    @Published private(set) var queueIndex = 0
    @Published private(set) var learnedToday = 0
    @Published var revealed = false
    @Published var collinsHTML = ""
    @Published var definitionText = ""
    @Published var collinsMessage = ""
    @Published var collinsExpanded = true
    @Published var speechMessage = ""
    @Published var hotKeyMessage = ""
    @Published var nextShortcut: WordHotKey
    @Published var previousShortcut: WordHotKey
    @Published var meaningShortcut: WordHotKey
    @Published var forgotShortcut: WordHotKey
    @Published var uncertainShortcut: WordHotKey
    @Published var knownShortcut: WordHotKey
    @Published var page = "study"
    @Published var importMessage = ""
    @Published var downloadBookID: String?
    @Published var downloadMessage = ""
    @Published var downloadDictionaryID: String?
    @Published var dictionaryDownloadMessage = ""
    @Published var searchQuery = ""
    @Published private(set) var searchMatches: [String] = []
    @Published private(set) var searchWord = ""
    @Published var searchFocusToken = 0
    @Published var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: "dailyGoal"); rebuildQueue() }
    }
    @Published var autoMinutes: Int {
        didSet { UserDefaults.standard.set(autoMinutes, forKey: "autoMinutes"); onTimerChange?() }
    }
    @Published var appearanceMode: String {
        didSet {
            guard appearanceMode != oldValue else { return }
            UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode")
            onAppearanceChange?()
        }
    }
    @Published var glassBackground: Bool {
        didSet { UserDefaults.standard.set(glassBackground, forKey: "glassBackground") }
    }
    @Published var statusFontSize: Double {
        didSet {
            UserDefaults.standard.set(statusFontSize, forKey: "statusFontSize")
            onStatusFontChange?()
        }
    }
    @Published var panelWordFontSize: Double {
        didSet { UserDefaults.standard.set(panelWordFontSize, forKey: "panelWordFontSize") }
    }
    @Published private(set) var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: "accentHex") }
    }
    var onWordChange: (() -> Void)?
    var onTimerChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onHotKeyChange: (() -> Bool)?
    var onStatusFontChange: (() -> Void)?

    private let atlas: [WordEntry]
    private lazy var builtInWords: [String: [WordEntry]] = {
        let starters = ["academic", "analysis", "significant", "sustainable", "impact", "evidence",
            "approach", "factor", "benefit", "challenge", "research", "policy", "resource",
            "context", "trend", "evaluate", "contribute", "perspective", "environmental", "implement"]
        return [
            "core": atlas.filter { ["B1", "B2", "C1"].contains($0.cefr) }
                .sorted { (starters.firstIndex(of: $0.w.lowercased()) ?? 9999) < (starters.firstIndex(of: $1.w.lowercased()) ?? 9999) },
            "reading": atlas.filter { ["B2", "C1", "C2"].contains($0.cefr) &&
                ["science", "technology", "society", "government", "economy", "environment", "history"].contains($0.topic) },
            "listening": atlas.filter { ["A2", "B1", "B2"].contains($0.cefr) &&
                ["daily", "travel", "city", "education", "work", "health"].contains($0.topic) },
            "speaking": atlas.filter { ["B1", "B2", "C1"].contains($0.cefr) &&
                ["education", "environment", "health", "society", "technology", "thinking", "emotion"].contains($0.topic) }
        ]
    }()
    private var reviews: [String: ReviewState]
    private var customBooks: [CustomBook]
    private var pendingAccentHex: String?
    private var accentCommitTask: Task<Void, Never>?
    private let speech = NSSpeechSynthesizer()
    private let storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("esai-wordbar", isDirectory: true)

    init() {
        atlas = Bundle.main.url(forResource: "word-atlas", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([WordEntry].self, from: $0) } ?? []
        selectedBookID = UserDefaults.standard.string(forKey: "selectedBookID") ?? "core"
        selectedDictionaryID = UserDefaults.standard.string(forKey: "selectedDictionaryID") ?? "collins"
        dailyGoal = max(1, UserDefaults.standard.integer(forKey: "dailyGoal") == 0 ? 15 : UserDefaults.standard.integer(forKey: "dailyGoal"))
        autoMinutes = UserDefaults.standard.integer(forKey: "autoMinutes")
        let savedMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        appearanceMode = ["system", "light", "dark"].contains(savedMode) ? savedMode : "system"
        glassBackground = UserDefaults.standard.object(forKey: "glassBackground") as? Bool ?? true
        let savedFontSize = UserDefaults.standard.object(forKey: "statusFontSize") as? Double ?? 14
        statusFontSize = (9...18).contains(savedFontSize) ? savedFontSize : 14
        let savedPanelFontSize = UserDefaults.standard.object(forKey: "panelWordFontSize") as? Double ?? 25
        let compactFontSize = [21, 25].contains(savedPanelFontSize) && !UserDefaults.standard.bool(forKey: "compactPanelWordV2Migrated")
            ? 14 : savedPanelFontSize
        panelWordFontSize = (12...30).contains(compactFontSize) ? compactFontSize : 14
        accentHex = AccentRGB(hex: UserDefaults.standard.string(forKey: "accentHex") ?? "")?.hex ?? "#0A8552"
        nextShortcut = UserDefaults.standard.data(forKey: "nextShortcut").flatMap { try? JSONDecoder().decode(WordHotKey.self, from: $0) } ?? .next
        previousShortcut = UserDefaults.standard.data(forKey: "previousShortcut").flatMap { try? JSONDecoder().decode(WordHotKey.self, from: $0) } ?? .previous
        meaningShortcut = UserDefaults.standard.data(forKey: "meaningShortcut").flatMap { try? JSONDecoder().decode(WordHotKey.self, from: $0) } ?? .meaning
        forgotShortcut = UserDefaults.standard.data(forKey: "forgotShortcut").flatMap { try? JSONDecoder().decode(WordHotKey.self, from: $0) } ?? .forgot
        uncertainShortcut = UserDefaults.standard.data(forKey: "uncertainShortcut").flatMap { try? JSONDecoder().decode(WordHotKey.self, from: $0) } ?? .uncertain
        knownShortcut = UserDefaults.standard.data(forKey: "knownShortcut").flatMap { try? JSONDecoder().decode(WordHotKey.self, from: $0) } ?? .known
        reviews = (try? Data(contentsOf: storage.appendingPathComponent("reviews.json")))
            .flatMap { try? JSONDecoder().decode([String: ReviewState].self, from: $0) } ?? [:]
        customBooks = (try? Data(contentsOf: storage.appendingPathComponent("custom-books.json")))
            .flatMap { try? JSONDecoder().decode([CustomBook].self, from: $0) } ?? []
        let personalCollins = storage.appendingPathComponent("dictionaries/collins.sqlite")
        if !FileManager.default.fileExists(atPath: personalCollins.path),
           let bundledCollins = Bundle.main.url(forResource: "collins", withExtension: "sqlite") {
            try? FileManager.default.createDirectory(at: personalCollins.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: bundledCollins, to: personalCollins)
        }
        if !["book", "collins", "ecdict.zh", "ecdict.en"].contains(selectedDictionaryID)
            || (selectedDictionaryID == "collins" && !FileManager.default.fileExists(atPath: personalCollins.path))
            || (selectedDictionaryID.hasPrefix("ecdict.") && !FileManager.default.fileExists(atPath: storage.appendingPathComponent("dictionaries/ecdict.sqlite").path)) {
            selectedDictionaryID = "book"
        }
        UserDefaults.standard.set(panelWordFontSize, forKey: "panelWordFontSize")
        UserDefaults.standard.set(true, forKey: "compactPanelWordMigrated")
        UserDefaults.standard.set(true, forKey: "compactPanelWordV2Migrated")
        rebuildQueue()
    }

    var books: [(id: String, title: String, detail: String, count: Int)] {
        [
            ("core", "雅思核心", "B1–C1 · 日常与学术高频", builtInWords["core"]!.count),
            ("reading", "阅读学术", "科学、社会、经济与环境", builtInWords["reading"]!.count),
            ("listening", "听力场景", "生活、校园、工作与出行", builtInWords["listening"]!.count),
            ("speaking", "口语写作", "话题表达与观点论述", builtInWords["speaking"]!.count)
        ] + customBooks.map { ($0.id, $0.title,
            $0.id.hasPrefix("freemdict.") ? "FreeMdict 下载" : $0.id.hasPrefix("popular.") ? "热门考试词书" : "自定义词书", $0.words.count) }
    }

    func downloaded(_ id: String) -> Bool { customBooks.contains { $0.id == id } }

    fileprivate func downloadBook(_ choice: FreemdictBook) {
        guard downloadBookID == nil else { return }
        downloadBookID = choice.id
        downloadMessage = "正在下载 \(choice.title)…"
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) { () throws -> CustomBook in
                    var request = URLRequest(url: choice.url)
                    request.setValue("Mozilla/5.0 esai-wordbar/0.7", forHTTPHeaderField: "User-Agent")
                    let (source, response) = try await URLSession.shared.download(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw NSError(domain: "esai-wordbar", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "下载站没有返回词书文件，请稍后再试。"])
                    }
                    let digest = SHA256.hash(data: try Data(contentsOf: source))
                        .map { String(format: "%02x", $0) }.joined()
                    guard digest == choice.sha256 else {
                        throw NSError(domain: "esai-wordbar", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "下载文件与已验证版本不同，暂未导入。"])
                    }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent("esai-words-\(UUID().uuidString).jsonl")
                    defer { try? FileManager.default.removeItem(at: destination) }
                    let process = Process()
                    process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent()
                        .appendingPathComponent("esai-mdx-importer")
                    process.arguments = [source.path, destination.path]
                    process.standardError = Pipe()
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        throw NSError(domain: "esai-wordbar", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "词书解析失败，请稍后重试。"])
                    }
                    let content = try String(contentsOf: destination, encoding: .utf8)
                    let words = content.split(separator: "\n").compactMap { line -> WordEntry? in
                        guard let pair = try? JSONDecoder().decode([String].self, from: Data(line.utf8)),
                              pair.count == 2 else { return nil }
                        let headword = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: #"\s+\d+$"#, with: "", options: .regularExpression)
                        guard !headword.isEmpty, headword.count < 45,
                              headword.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.whitespaces).contains($0) || $0 == "-" || $0 == "'" }) else { return nil }
                        let plain = pair[1]
                            .replacingOccurrences(of: #"(?i)<br\s*/?>|</p>"#, with: "\n", options: .regularExpression)
                            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"^`\d+`[^`]*`\d+`"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                        let lines = plain.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        guard let meaningIndex = lines.firstIndex(where: {
                            $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
                        }) else { return nil }
                        var meaning = lines[meaningIndex]
                        let english = choice.id == "freemdict.sat"
                            ? lines[meaningIndex].range(of: #"(?<=[\p{Han}，。；、])\s+[A-Za-z]{2,}"#,
                                options: .regularExpression).map {
                                    String(lines[meaningIndex][$0.lowerBound...].split(separator: ".", maxSplits: 1)[0])
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                } ?? "" : ""
                        meaning = meaning.components(separatedBy: "【")[0]
                            .replacingOccurrences(of: #"(?<=[\p{Han}，。；、])\s+[A-Za-z]{2,}.*$"#,
                                with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !meaning.isEmpty else { return nil }
                        let phonetic = lines.first(where: { $0.hasPrefix("[") && $0.contains("]") }) ?? ""
                        let examples: [WordExample]
                        if choice.id == "freemdict.exam900", lines.count > meaningIndex + 2,
                           !lines[meaningIndex + 1].unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }),
                           lines[meaningIndex + 2].unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                            examples = [WordExample(en: lines[meaningIndex + 1], zh: lines[meaningIndex + 2])]
                        } else { examples = [] }
                        return WordEntry(w: headword, uk: phonetic, us: phonetic,
                            senses: [WordSense(pos: "", zh: String(meaning.prefix(100)), en: english)],
                            ex: examples, col: [], fam: [], syn: [], ant: [], tip: "", cefr: "",
                            topic: "freemdict", note: "", id: "\(choice.id).\(headword.lowercased())")
                    }
                    let unique = Dictionary(grouping: words, by: { $0.w.lowercased() })
                        .values.compactMap(\.first).sorted { $0.w.localizedCaseInsensitiveCompare($1.w) == .orderedAscending }
                    guard unique.count >= 100 else {
                        throw NSError(domain: "esai-wordbar", code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "词书内容不足，暂未导入。"])
                    }
                    return CustomBook(id: choice.id, title: choice.title, words: unique)
                }.value
                customBooks.removeAll { $0.id == choice.id }
                customBooks.append(book)
                persist(customBooks, to: "custom-books.json")
                downloadMessage = "已导入 \(book.words.count) 个单词，开始学习。"
                selectBook(book.id)
                page = "study"
            } catch {
                downloadMessage = "下载失败：\(error.localizedDescription)"
            }
            downloadBookID = nil
        }
    }

    fileprivate func downloadBook(_ choice: PopularBook) {
        guard downloadBookID == nil else { return }
        downloadBookID = choice.id
        downloadMessage = "正在下载 \(choice.title)…"
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) { () throws -> CustomBook in
                    let (source, response) = try await URLSession.shared.download(from: choice.url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw NSError(domain: "esai-wordbar", code: 1, userInfo: [NSLocalizedDescriptionKey: "词书下载失败，请稍后重试。"])
                    }
                    let data = try Data(contentsOf: source)
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard digest == choice.sha256 else {
                        throw NSError(domain: "esai-wordbar", code: 2, userInfo: [NSLocalizedDescriptionKey: "下载文件与已验证版本不同，暂未导入。"])
                    }
                    let decoded = try JSONDecoder().decode(PopularBookFile.self, from: data)
                    let words = decoded.words.compactMap { item -> WordEntry? in
                        let headword = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !headword.isEmpty, !item.translations.isEmpty else { return nil }
                        let senses = item.translations.map { translation -> WordSense in
                            let parts = translation.split(separator: " ", maxSplits: 1).map(String.init)
                            return WordSense(pos: parts.count == 2 && parts[0].hasSuffix(".") ? parts[0] : "",
                                zh: parts.count == 2 && parts[0].hasSuffix(".") ? parts[1] : translation, en: "")
                        }
                        return WordEntry(w: headword, uk: item.phonetic, us: item.phonetic,
                            senses: senses, ex: [], col: [], fam: [], syn: [], ant: [], tip: "", cefr: "",
                            topic: "popular", note: "", id: "\(choice.id).\(headword.lowercased())")
                    }
                    guard words.count >= 100 else {
                        throw NSError(domain: "esai-wordbar", code: 3, userInfo: [NSLocalizedDescriptionKey: "词书内容不足，暂未导入。"])
                    }
                    return CustomBook(id: choice.id, title: choice.title, words: words)
                }.value
                customBooks.removeAll { $0.id == choice.id }
                customBooks.append(book)
                persist(customBooks, to: "custom-books.json")
                downloadMessage = "已导入 \(book.words.count) 个单词，开始学习。"
                selectBook(book.id)
                page = "study"
            } catch {
                downloadMessage = "下载失败：\(error.localizedDescription)"
            }
            downloadBookID = nil
        }
    }

    var current: WordEntry? { queue.indices.contains(queueIndex) ? queue[queueIndex] : nil }
    var atlasCount: Int { atlas.count }
    var bookTitle: String {
        switch selectedBookID {
        case "core": return "雅思核心"
        case "reading": return "阅读学术"
        case "listening": return "听力场景"
        case "speaking": return "口语写作"
        default: return customBooks.first(where: { $0.id == selectedBookID })?.title ?? "雅思核心"
        }
    }
    var dueCount: Int { queue.filter { reviews[$0.id] != nil }.count }
    var reviewedToday: Int { reviews.values.filter { Calendar.current.isDateInToday($0.last) }.count }
    var accentColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = AccentRGB(hex: self.accentHex)!.readable(onDark: dark)
            return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        })
    }
    var selectedAccent: Color {
        let color = AccentRGB(hex: pendingAccentHex ?? accentHex)!
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    func setAccent(_ hex: String) {
        pendingAccentHex = nil
        if let color = AccentRGB(hex: hex), color.hex != accentHex { accentHex = color.hex }
    }

    func setAccentColor(_ color: Color) {
        if let value = NSColor(color).usingColorSpace(.sRGB) {
            let hex = AccentRGB(red: value.redComponent, green: value.greenComponent,
                blue: value.blueComponent).hex
            guard hex != (pendingAccentHex ?? accentHex) else { return }
            pendingAccentHex = hex
            guard accentCommitTask == nil else { return }
            accentCommitTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 33_000_000)
                accentCommitTask = nil
                if let hex = pendingAccentHex {
                    pendingAccentHex = nil
                    if hex != accentHex { accentHex = hex }
                }
            }
        }
    }

    private func words(for id: String) -> [WordEntry] {
        builtInWords[id] ?? customBooks.first(where: { $0.id == id })?.words ?? []
    }

    func selectBook(_ id: String) {
        selectedBookID = id
        UserDefaults.standard.set(id, forKey: "selectedBookID")
        queueIndex = 0
        rebuildQueue()
    }

    func refreshDay() { rebuildQueue() }

    private func rebuildQueue() {
        let candidates = words(for: selectedBookID)
        learnedToday = candidates.reduce(0) { count, word in
            guard let review = reviews[word.id], review.seen == 1,
                  Calendar.current.isDateInToday(review.last) else { return count }
            return count + 1
        }
        let due = candidates.filter { reviews[$0.id].map { $0.due <= .now } ?? false }
            .sorted { (reviews[$0.id]?.due ?? .distantFuture) < (reviews[$1.id]?.due ?? .distantFuture) }
        let new = candidates.filter { reviews[$0.id] == nil }
            .prefix(max(0, dailyGoal - learnedToday))
        queue = due + new
        queueIndex = min(queueIndex, max(0, queue.count - 1))
        revealed = false
        collinsHTML = ""
        definitionText = ""
        collinsMessage = ""
        collinsExpanded = true
        speechMessage = ""
        onWordChange?()
    }

    func move(_ direction: Int) {
        guard !queue.isEmpty else { return }
        let keepDefinitionVisible = revealed
        queueIndex = (queueIndex + direction + queue.count) % queue.count
        revealed = keepDefinitionVisible
        collinsHTML = ""
        definitionText = ""
        collinsMessage = ""
        collinsExpanded = true
        speechMessage = ""
        if keepDefinitionVisible { loadCollins() }
        onWordChange?()
    }

    func speakCurrent() {
        guard let word = current else { return }
        speech.stopSpeaking()
        speechMessage = speech.startSpeaking(word.w) ? "已开始朗读 \(word.w)" : "无法朗读，请检查系统语音设置。"
    }

    func revealCurrent() {
        revealed = true
        loadCollins()
    }

    func grade(_ quality: Int) {
        guard let word = current else { return }
        let previous = reviews[word.id]
        let interval = quality == 0 ? 0 : quality == 1 ? 1 : min(60, max(3, (previous?.interval ?? 0) * 2))
        reviews[word.id] = ReviewState(interval: interval,
            due: Calendar.current.date(byAdding: .minute, value: interval == 0 ? 10 : interval * 1440, to: .now) ?? .now,
            seen: (previous?.seen ?? 0) + 1, last: .now)
        persist(reviews, to: "reviews.json")
        rebuildQueue()
    }

    func importBook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let separator: Character = url.pathExtension.lowercased() == "tsv" ? "\t" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(content.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                } else { quoted.toggle() }
            } else if character == separator && !quoted {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines)); field = ""
            } else if character == "\n" && !quoted {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []; field = ""
            } else { field.append(character) }
            index += 1
        }
        row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard let header = rows.first?.map({ $0.lowercased() }),
              let wordColumn = header.firstIndex(where: { ["word", "单词"].contains($0) }),
              let meaningColumn = header.firstIndex(where: { ["meaning", "释义"].contains($0) }) else {
            importMessage = "表头需要 word, meaning；可选 phonetic, example, example_zh。"
            return
        }
        let phoneticColumn = header.firstIndex(where: { ["phonetic", "音标"].contains($0) })
        let exampleColumn = header.firstIndex(where: { ["example", "例句"].contains($0) })
        let translationColumn = header.firstIndex(where: { ["example_zh", "例句翻译"].contains($0) })
        let imported = rows.dropFirst().compactMap { fields -> WordEntry? in
            guard fields.indices.contains(wordColumn), fields.indices.contains(meaningColumn),
                  !fields[wordColumn].isEmpty else { return nil }
            let word = fields[wordColumn]
            let phonetic = phoneticColumn.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            let example = exampleColumn.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            let translation = translationColumn.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            return WordEntry(w: word, uk: phonetic, us: phonetic,
                senses: [WordSense(pos: "", zh: fields[meaningColumn], en: "")],
                ex: example.isEmpty ? [] : [WordExample(en: example, zh: translation)],
                col: [], fam: [], syn: [], ant: [], tip: "", cefr: "", topic: "custom", note: "",
                id: "custom.\(url.deletingPathExtension().lastPathComponent).\(word.lowercased())")
        }
        guard !imported.isEmpty else { importMessage = "没有找到可导入的单词。"; return }
        let book = CustomBook(id: UUID().uuidString, title: url.deletingPathExtension().lastPathComponent,
            words: Array(Dictionary(grouping: imported, by: { $0.w.lowercased() }).values.compactMap(\.first).sorted { $0.w < $1.w }))
        customBooks.append(book)
        persist(customBooks, to: "custom-books.json")
        importMessage = "已导入 \(book.words.count) 个单词。"
        selectBook(book.id)
        page = "study"
    }

    var collinsURL: URL {
        let personal = storage.appendingPathComponent("dictionaries/collins.sqlite")
        if FileManager.default.fileExists(atPath: personal.path) { return personal }
        return Bundle.main.url(forResource: "collins", withExtension: "sqlite")
            ?? URL(fileURLWithPath: "/Library/Application Support/esai-wordbar/dictionaries/collins.sqlite")
    }
    var collinsReady: Bool { FileManager.default.fileExists(atPath: collinsURL.path) }
    var dictionaryFolderURL: URL { storage.appendingPathComponent("dictionaries", isDirectory: true) }
    var ecdictURL: URL { storage.appendingPathComponent("dictionaries/ecdict.sqlite") }
    var ecdictReady: Bool { FileManager.default.fileExists(atPath: ecdictURL.path) }
    var dictionaryTitle: String {
        switch selectedDictionaryID {
        case "collins": "柯林斯 COBUILD"
        case "ecdict.zh": "ECDICT 英汉"
        case "ecdict.en": "ECDICT 英英"
        default: "词书自带释义"
        }
    }

    func selectDictionary(_ id: String) {
        guard id == "book" || (id == "collins" && collinsReady) || (id.hasPrefix("ecdict.") && ecdictReady) else { return }
        selectedDictionaryID = id
        UserDefaults.standard.set(id, forKey: "selectedDictionaryID")
        collinsHTML = ""
        definitionText = ""
        collinsMessage = ""
        if revealed { loadCollins() }
    }

    private var searchDictionaryID: String {
        if selectedDictionaryID != "book" { return selectedDictionaryID }
        if ecdictReady { return "ecdict.zh" }
        return collinsReady ? "collins" : "book"
    }

    var searchEntry: WordEntry? {
        let word = searchWord.lowercased()
        return words(for: selectedBookID).first { $0.w.lowercased() == word }
            ?? atlas.first { $0.w.lowercased() == word }
    }

    func updateSearchQuery(_ query: String) {
        if searchQuery != query {
            searchQuery = query
            refreshSearch()
        }
        if !query.isEmpty { page = "search" }
        else if page == "search" { page = "study" }
    }

    func refreshSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchMatches = []
            searchWord = ""
            return
        }
        let prefix = String(query.prefix(60))
        let local = (words(for: selectedBookID) + atlas)
            .filter { $0.w.lowercased().hasPrefix(prefix.lowercased()) }
            .prefix(12).map(\.w)
        var dictionaryWords: [String] = []
        if searchDictionaryID != "book" {
            var database: OpaquePointer?
            let file = searchDictionaryID == "collins" ? collinsURL : ecdictURL
            if sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(database, "SELECT word FROM entries WHERE word LIKE ? ORDER BY word LIMIT 12", -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, prefix + "%", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let value = sqlite3_column_text(statement, 0) { dictionaryWords.append(String(cString: value)) }
                    }
                }
                sqlite3_finalize(statement)
            }
            sqlite3_close(database)
        }
        searchMatches = Array(Set(local + dictionaryWords))
            .sorted { lhs, rhs in
                if lhs.lowercased() == prefix.lowercased() { return true }
                if rhs.lowercased() == prefix.lowercased() { return false }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .prefix(10).map { $0 }
        searchWord = ""
        if let exact = searchMatches.first(where: { $0.caseInsensitiveCompare(prefix) == .orderedSame }) {
            selectSearchWord(exact)
        }
    }

    func selectSearchWord(_ word: String) {
        searchWord = word
        loadCollins(word)
    }

    func downloadDictionary(_ id: String) {
        guard downloadDictionaryID == nil, ["collins", "ecdict"].contains(id) else { return }
        downloadDictionaryID = id
        dictionaryDownloadMessage = id == "collins" ? "正在下载柯林斯词典（约 50 MB）…" : "正在下载 ECDICT（约 66 MB）…"
        Task {
            do {
                let folder = storage.appendingPathComponent("dictionaries", isDirectory: true)
                let filename = id == "collins" ? "collins.sqlite" : "ecdict.sqlite"
                let url = id == "collins"
                    ? URL(string: "https://downloads.freemdict.com/uploads/tempertemper%27s%20collection/MD~/Collins/Collin%20Cobuild%20OH/CollinsCOBUILDOverhaul%20V%202-30.mdx")!
                    : URL(string: "https://raw.githubusercontent.com/skywind3000/ECDICT/39cfb9672c0906b63569e0453c2e6abfb9ab182a/ecdict.csv")!
                let expectedHash = id == "collins"
                    ? "2300431a0a1b748248fe8382b2917e550dbb0563c0ab6a60c1a563db71a7dafa"
                    : "d1ecbdf9ee2b920afb6f430ca6b6bb9f559588cf0dff86e04bd255f9390843cc"
                try await Task.detached(priority: .userInitiated) {
                    let (source, response) = try await URLSession.shared.download(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw NSError(domain: "esai-wordbar", code: 1, userInfo: [NSLocalizedDescriptionKey: "下载站没有返回词典文件。"])
                    }
                    let digest = SHA256.hash(data: try Data(contentsOf: source))
                        .map { String(format: "%02x", $0) }.joined()
                    guard digest == expectedHash else {
                        throw NSError(domain: "esai-wordbar", code: 2, userInfo: [NSLocalizedDescriptionKey: "下载文件与已验证版本不同，暂未导入。"])
                    }
                    let temporary = FileManager.default.temporaryDirectory
                        .appendingPathComponent("esai-dictionary-\(UUID().uuidString).sqlite")
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let process = Process()
                    process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent()
                        .appendingPathComponent("esai-mdx-importer")
                    process.arguments = [id == "collins" ? "--collins" : "--ecdict", source.path, temporary.path]
                    process.standardOutput = Pipe()
                    process.standardError = Pipe()
                    try process.run()
                    process.waitUntilExit()
                    let attributes = try? FileManager.default.attributesOfItem(atPath: temporary.path)
                    guard process.terminationStatus == 0,
                          (attributes?[.size] as? NSNumber)?.intValue ?? 0 > 1_000_000 else {
                        throw NSError(domain: "esai-wordbar", code: 3, userInfo: [NSLocalizedDescriptionKey: "词典转换失败，请稍后重试。"])
                    }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }.value
                selectDictionary(id == "collins" ? "collins" : "ecdict.zh")
                dictionaryDownloadMessage = "已安装 \(dictionaryTitle)，现在可以离线使用。"
            } catch {
                dictionaryDownloadMessage = "下载失败：\(error.localizedDescription)"
            }
            downloadDictionaryID = nil
        }
    }

    func setShortcut(_ shortcut: WordHotKey, action: Int) {
        let choices = [nextShortcut, previousShortcut, meaningShortcut, forgotShortcut, uncertainShortcut, knownShortcut]
        if choices.enumerated().contains(where: { $0.offset != action - 1 && $0.element.code == shortcut.code && $0.element.modifiers == shortcut.modifiers }) {
            hotKeyMessage = "不同操作不能使用同一个快捷键。"
            return
        }
        let old = choices[action - 1]
        switch action {
        case 1: nextShortcut = shortcut
        case 2: previousShortcut = shortcut
        case 3: meaningShortcut = shortcut
        case 4: forgotShortcut = shortcut
        case 5: uncertainShortcut = shortcut
        default: knownShortcut = shortcut
        }
        if onHotKeyChange?() != false {
            hotKeyMessage = "已设置 \(["下一词", "上一词", "按住显示中文", "忘了", "模糊", "认识"][action - 1])：\(shortcut.displayLabel)"
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: ["nextShortcut", "previousShortcut", "meaningShortcut", "forgotShortcut", "uncertainShortcut", "knownShortcut"][action - 1])
        } else {
            switch action {
            case 1: nextShortcut = old
            case 2: previousShortcut = old
            case 3: meaningShortcut = old
            case 4: forgotShortcut = old
            case 5: uncertainShortcut = old
            default: knownShortcut = old
            }
            _ = onHotKeyChange?()
            hotKeyMessage = "该快捷键已被占用，请换一个组合。"
        }
    }

    func loadCollins(_ searchedWord: String? = nil) {
        guard let word = searchedWord ?? current?.w else { return }
        collinsHTML = ""
        definitionText = ""
        collinsMessage = ""
        let source = searchedWord == nil ? selectedDictionaryID : searchDictionaryID
        guard source != "book" else { return }
        let isCollins = source == "collins"
        guard isCollins ? collinsReady : ecdictReady else {
            collinsMessage = "释义库尚未安装，请到设置 → 释义下载。"
            return
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2((isCollins ? collinsURL : ecdictURL).path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            collinsMessage = "无法打开本地释义库。"; return
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let column = isCollins ? "html" : source == "ecdict.zh" ? "zh" : "en"
        guard sqlite3_prepare_v2(database, "SELECT \(column) FROM entries WHERE word = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            collinsMessage = "本地词库查询失败。"; return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, word, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) {
            if isCollins { collinsHTML = String(cString: bytes) }
            else { definitionText = String(cString: bytes) }
            if collinsHTML.isEmpty && definitionText.isEmpty { collinsMessage = "这本释义库没有收录 \(word)。" }
            collinsExpanded = true
        } else {
            collinsMessage = "这本释义库没有收录 \(word)。"
        }
    }

    func openDictionaryFolder() {
        try? FileManager.default.createDirectory(at: dictionaryFolderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dictionaryFolderURL)
    }

    private func persist<T: Encodable>(_ value: T, to name: String) {
        try? FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: storage.appendingPathComponent(name), options: .atomic)
        }
    }
}

private struct CollinsEntryView: NSViewRepresentable {
    let html: String
    let accentHex: String
    let dark: Bool
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font:13px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.5;color:\(dark ? "#e7eee9" : "#26352d");margin:10px;background:transparent}
        .collins_en_cn{padding:10px 0;border-top:1px solid \(dark ? "#526359" : "#e2e9e4")}.num,.st{color:\(accentHex);font-weight:700;margin-right:5px}.def_cn{display:block;color:\(accentHex);margin:4px 0}.collins_content ul{padding-left:18px}.collins_content li{margin:8px 0}.collins_content li p{margin:2px 0}.chinese-text{color:\(accentHex)}a{color:\(accentHex)}</style>
        \(html)
        """, baseURL: nil)
    }
}

private final class HotKeyCaptureButton: NSButton {
    var onCapture: ((WordHotKey) -> Void)?
    var titleBeforeCapture = ""
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { title = titleBeforeCapture; window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags.intersection([.option, .shift, .control, .command])
        guard flags.contains(.option) || flags.contains(.control) || flags.contains(.command),
              event.keyCode != 56, event.keyCode != 58, event.keyCode != 59, event.keyCode != 55 else {
            NSSound.beep(); return
        }
        let modifiers = (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.command) ? UInt32(cmdKey) : 0)
        let key = WordHotKey.keyNames[UInt32(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty, !key.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || (0xE000...0xF8FF).contains($0.value)
        }) else { NSSound.beep(); return }
        onCapture?(WordHotKey(code: UInt32(event.keyCode), modifiers: modifiers,
            label: "\(flags.contains(.control) ? "⌃ " : "")\(flags.contains(.option) ? "⌥ " : "")\(flags.contains(.shift) ? "⇧ " : "")\(flags.contains(.command) ? "⌘ " : "")\(key)"))
        window?.makeFirstResponder(nil)
    }
}

private struct HotKeyRecorder: NSViewRepresentable {
    let title: String
    let shortcut: WordHotKey
    let onCapture: (WordHotKey) -> Void
    func makeNSView(context: Context) -> HotKeyCaptureButton {
        let button = HotKeyCaptureButton()
        button.bezelStyle = .rounded
        button.target = context.coordinator
        button.action = #selector(Coordinator.startCapture(_:))
        return button
    }
    func updateNSView(_ button: HotKeyCaptureButton, context: Context) {
        button.title = shortcut.displayLabel
        button.setAccessibilityLabel("\(title)：\(shortcut.displayLabel)")
        button.onCapture = onCapture
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject {
        @objc func startCapture(_ button: HotKeyCaptureButton) {
            button.titleBeforeCapture = button.title
            button.title = "请按新快捷键…"
            button.window?.makeFirstResponder(button)
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: WordHotKey
    let onCapture: (WordHotKey) -> Void

    var body: some View {
        HStack {
            Text(title).font(.callout.weight(.medium))
            Spacer()
            HotKeyRecorder(title: title, shortcut: shortcut, onCapture: onCapture)
                .frame(width: 128, height: 26)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .wordCard(raised: false)
    }
}

private struct SegmentChoice: Identifiable {
    let id: String
    let title: String
}

private struct WordSegments: View {
    @Binding var selection: String
    let options: [SegmentChoice]
    let accent: Color
    let label = "选项"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        WordNativeSegments(selection:selection,options:options,accent:NSColor(accent),label:label,
            reduceMotion:reduceMotion,reduceTransparency:reduceTransparency,dark:colorScheme == .dark) { value in
            withTransaction(Transaction(animation:nil)) { selection = value }
        }
        .frame(height:34)
        .background(.thinMaterial,in:Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor).opacity(0.35),lineWidth:0.5))
    }
}

private struct WordNativeSegments: NSViewRepresentable {
    let selection:String
    let options:[SegmentChoice]
    let accent:NSColor
    let label: String
    let reduceMotion:Bool
    let reduceTransparency:Bool
    let dark:Bool
    let onSelect:(String)->Void
    func makeNSView(context:Context) -> WordSegmentedView { WordSegmentedView(frame:.zero) }
    func updateNSView(_ view:WordSegmentedView,context:Context) {
        view.configure(selection:selection,options:options,accent:accent,label:label,
            reduceMotion:reduceMotion,reduceTransparency:reduceTransparency,dark:dark,onSelect:onSelect)
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:WordSegmentedView,context:Context) -> CGSize? {
        CGSize(width:proposal.width ?? 200,height:34)
    }
}

private final class WordSegmentedView: NSView {
    private var glass:NSView!
    private var buttons:[NSButton] = []
    private var ids:[String] = []
    private var selection = ""
    private var onSelect:(String)->Void = { _ in }
    private var lastSize = CGSize.zero
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:34) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        if #available(macOS 26.0,*) {
            let native = NSGlassEffectView(); native.style = .regular; native.cornerRadius = 14
            native.contentView = NSView()
            glass = native
        } else { glass = NSView(); glass.wantsLayer = true; glass.layer?.cornerRadius = 14 }
        addSubview(glass)
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(selection:String,options:[SegmentChoice],accent:NSColor,label:String,
        reduceMotion:Bool,reduceTransparency:Bool,dark:Bool,onSelect:@escaping(String)->Void) {
        let changed = self.selection != selection && !self.selection.isEmpty
        self.selection = selection; self.onSelect = onSelect
        setAccessibilityLabel(label)
        if #available(macOS 26.0, *) {
            let native = glass is NSGlassEffectView
            if native == reduceTransparency {
                let oldFrame = glass.frame
                glass.removeFromSuperview()
                if reduceTransparency {
                    glass = NSView(); glass.wantsLayer = true; glass.layer?.cornerRadius = 14
                } else {
                    let effect = NSGlassEffectView(); effect.style = .regular; effect.cornerRadius = 14
                    effect.contentView = NSView(); glass = effect
                }
                glass.frame = oldFrame
                addSubview(glass,positioned:.below,relativeTo:buttons.first)
            }
        }
        if ids != options.map(\.id) {
            buttons.forEach { $0.removeFromSuperview() }; buttons = []; ids = options.map(\.id)
            for index in options.indices {
                let button = NSButton(title:"",target:self,action:#selector(select(_:)))
                button.tag = index; button.isBordered = false; button.focusRingType = .none
                addSubview(button,positioned:.above,relativeTo:glass); buttons.append(button)
            }
            lastSize = .zero; needsLayout = true
        }
        for (index,button) in buttons.enumerated() {
            let selected = ids[index] == selection
            let color = selected ? (dark ? NSColor.white : accent) : NSColor.labelColor
            button.attributedTitle = NSAttributedString(string:options[index].title,attributes:[
                .font:NSFont.systemFont(ofSize:13,weight:selected ? .semibold : .medium),.foregroundColor:color])
            button.setAccessibilityLabel(options[index].title)
            button.setAccessibilityValue(selected ? 1 : 0)
        }
        if #available(macOS 26.0,*), let native = glass as? NSGlassEffectView {
            native.tintColor = accent.withAlphaComponent(dark ? 0.32 : 0.18)
        } else { glass.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor }
        if bounds.width > 0 && changed && window != nil && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints:0.35,0,0.25,1)
                glass.animator().frame = selectionFrame
            }
        } else if changed && lastSize == bounds.size { glass.frame = selectionFrame }
    }
    private var selectionFrame:NSRect {
        let width = max(0,bounds.width-6)/CGFloat(max(1,ids.count))
        let index = ids.firstIndex(of:selection) ?? 0
        return NSRect(x:3+CGFloat(index)*width,y:3,width:width,height:28)
    }
    override func layout() {
        super.layout()
        let width = max(0,bounds.width-6)/CGFloat(max(1,ids.count))
        for (index,button) in buttons.enumerated() {
            button.frame = NSRect(x:3+CGFloat(index)*width,y:3,width:width,height:28)
        }
        if lastSize != bounds.size { glass.frame = selectionFrame; lastSize = bounds.size }
    }
    @objc private func select(_ button:NSButton) { if ids.indices.contains(button.tag) { onSelect(ids[button.tag]) } }
}

// Adapted from esai's EsaiScrollChrome, which credits Licoy/Quosparr.
private struct EsaiScrollChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> EsaiScrollChromeProbe { EsaiScrollChromeProbe() }
    func updateNSView(_ view: EsaiScrollChromeProbe, context: Context) {}
}

private final class EsaiScrollChromeProbe: NSView {
    private var pending = false
    private var styleObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        styleObserver = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.scheduleConfiguration() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleConfiguration() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleConfiguration() }

    func scheduleConfiguration() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending = false
            guard let scroll = enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.hasHorizontalScroller = false
            if !(scroll.verticalScroller is EsaiThinOverlayScroller) {
                let scroller = EsaiThinOverlayScroller()
                scroller.scrollerStyle = .overlay
                scroller.controlSize = .small
                scroll.verticalScroller = scroller
            }
        }
    }
}

private final class EsaiThinOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style) -> CGFloat { 7 }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let nativeKnob = rect(for: .knob)
        guard nativeKnob.height > 2 else { return }
        let knob = NSRect(x: bounds.midX - 1.5, y: nativeKnob.minY + 1,
            width: 3, height: max(3, nativeKnob.height - 2))
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.36)
            : NSColor.black.withAlphaComponent(0.22)).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

private final class WordPanelHostController: NSViewController {
    private let hosting: NSHostingView<WordPanel>
    init(model: WordModel) {
        hosting = NSHostingView(rootView: WordPanel(model: model))
        hosting.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 400, height: 560)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width, .height]
        view.addSubview(hosting)
    }
}

private struct ImmediateSearchField: NSViewRepresentable {
    let text: String
    let focusToken: Int
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "点开后直接输入英文查词"
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ImmediateSearchField
        var lastFocusToken = 0
        init(parent: ImmediateSearchField) { self.parent = parent }
        @objc func changed(_ field: NSSearchField) {
            parent.onChange(field.stringValue)
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                parent.onChange(field.stringValue)
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

struct WordPanel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: WordModel
    @State private var customHex = ""
    @State private var hexError = false
    @State private var settingsTab = CommandLine.arguments.contains("--preview-settings=dictionaries") ? "dictionaries" : "books"
    @State private var bookTab = CommandLine.arguments.contains("--preview-settings=books") ? "discover" : "mine"
    private var word: WordEntry? { model.current }
    private var accent: Color { model.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 17).padding(.top, 15).padding(.bottom, 13)
            WordSurface.hairline.frame(height: 1)
            if model.page == "settings" {
                settingsTabs.padding(.horizontal, 17).padding(.top, 12).padding(.bottom, 4)
            }
            ScrollView {
                Group {
                    if model.page == "study" { study }
                    else if model.page == "search" { search }
                    else { settingsContent }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .background(EsaiScrollChrome().allowsHitTesting(false))
            }
            .id("\(model.page)-\(settingsTab)-\(model.current?.id ?? "")")
            WordSurface.hairline.frame(height: 1)
            if model.page == "study" && model.revealed && word != nil {
                HStack(spacing: 4) {
                    WordGradeAction(title: "忘了", shortcut: model.forgotShortcut.displayLabel,
                        hoverColor: .orange) { model.grade(0) }
                    WordGradeAction(title: "模糊", shortcut: model.uncertainShortcut.displayLabel,
                        hoverColor: .blue) { model.grade(1) }
                    WordGradeAction(title: "认识", shortcut: model.knownShortcut.displayLabel,
                        hoverColor: accent) { model.grade(2) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 17).padding(.top, 8).padding(.bottom, 1)
            }
            footer.padding(.horizontal, 17).padding(.vertical, 11)
        }
        .frame(width: 400, height: 560)
        .background { if !model.glassBackground || reduceTransparency { Color(nsColor: .windowBackgroundColor) } }
        .tint(accent)
        .preferredColorScheme(model.appearanceMode == "dark" ? .dark : model.appearanceMode == "light" ? .light : nil)
        .onChange(of: model.page) { page in
            if page == "study" {
                if !model.revealed { model.revealCurrent() }
                else { model.loadCollins() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if model.page == "study" || model.page == "search" {
                    if let image = Bundle.main.url(forResource: "EsaiStatusTemplate", withExtension: "pdf")
                        .flatMap(NSImage.init(contentsOf:)) {
                        Image(nsImage: image).resizable().renderingMode(.template)
                            .foregroundStyle(accent).frame(width: 19, height: 19)
                    }
                    Text("esai单词").font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    if model.page == "study" {
                        Button {
                            settingsTab = "books"
                            bookTab = "mine"
                            model.page = "settings"
                        } label: {
                            Text(model.bookTitle).font(.caption.weight(.medium)).lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(WordSurface.raised, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain).help("选择词书")
                    }
                } else {
                    Button { model.page = "study" } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    Text("设置").font(.title3.weight(.semibold))
                    Spacer()
                }
            }
            if model.page == "study" || model.page == "search" {
                ImmediateSearchField(text: model.searchQuery, focusToken: model.searchFocusToken) { query in
                    model.updateSearchQuery(query)
                } onSubmit: {
                    if let first = model.searchMatches.first { model.selectSearchWord(first) }
                }
                .frame(height: 19)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(WordSurface.raised, in: RoundedRectangle(cornerRadius: 8))
            }
            if model.page == "study" && word != nil {
                HStack(spacing: 7) {
                    Text("学习中").font(.caption.weight(.semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(accent.opacity(0.12), in: Capsule())
                    Text("今日 \(model.learnedToday)/\(model.dailyGoal)")
                        .font(.callout.weight(.semibold)).foregroundStyle(accent)
                    Spacer()
                    Text("待复习 \(model.dueCount)").font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WordSurface.sunken)
                        Capsule().fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                            startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * min(1, Double(model.learnedToday) / Double(model.dailyGoal)))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var study: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let word {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.w).font(.system(size: model.panelWordFontSize, weight: .medium))
                            .minimumScaleFactor(0.75).lineLimit(1)
                        Spacer()
                        Button { model.speakCurrent() } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                        }.buttonStyle(.plain).foregroundStyle(accent).help("朗读单词")
                    }
                    if !model.speechMessage.isEmpty {
                        Text(model.speechMessage).font(.caption).foregroundStyle(accent)
                    }
                    HStack(spacing: 8) {
                        Text("英 \(word.uk)  美 \(word.us)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !word.cefr.isEmpty {
                            Text(word.cefr).font(.caption2.weight(.medium)).foregroundStyle(accent)
                        }
                        Spacer(minLength: 8)
                        Button { model.move(-1) } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 24, height: 24)
                                .background(WordSurface.sunken, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .help("上一词 · \(model.previousShortcut.displayLabel)")
                        Button { model.move(1) } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 24, height: 24)
                                .background(WordSurface.sunken, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .help("下一词 · \(model.nextShortcut.displayLabel)")
                    }
                    .buttonStyle(.plain)
                }
                .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                .wordCard()

                if !model.revealed {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("先在心里说出它的意思")
                            .font(.headline)
                        Text("像扇贝一样先回忆，再看答案；释义与例句会在揭晓后出现。")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("显示释义") { model.revealCurrent() }
                            .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .wordCard(raised: false)
                } else {
                    if model.selectedDictionaryID != "book" {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(model.dictionaryTitle).font(.headline)
                                Text("本地").font(.caption.weight(.medium)).foregroundStyle(accent)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(accent.opacity(0.1), in: Capsule())
                                Spacer()
                                Button(model.collinsExpanded ? "收起" : "展开") { model.collinsExpanded.toggle() }
                                    .buttonStyle(.plain).foregroundStyle(accent)
                            }
                            if !model.collinsMessage.isEmpty {
                                Text(model.collinsMessage).font(.caption).foregroundStyle(.secondary)
                            }
                            if model.collinsExpanded {
                                if !model.collinsHTML.isEmpty {
                                    CollinsEntryView(html: model.collinsHTML,
                                        accentHex: AccentRGB(hex: model.accentHex)!.readable(onDark: colorScheme == .dark).hex,
                                        dark: colorScheme == .dark).frame(height: 200)
                                }
                                if !model.definitionText.isEmpty {
                                    Text(model.definitionText).font(.callout).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .wordCard(raised: false)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        if model.selectedDictionaryID == "book" || (!model.collinsMessage.isEmpty && model.collinsHTML.isEmpty && model.definitionText.isEmpty) {
                            HStack {
                                Text("词书释义").font(.headline)
                                Spacer()
                                Text("\(word.senses.count) 条")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(Array(word.senses.enumerated()), id: \.offset) { _, sense in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(sense.pos.isEmpty ? "释义" : sense.pos)
                                            .font(.caption.weight(.semibold)).foregroundStyle(accent)
                                            .frame(width: 34, alignment: .leading)
                                        Text(sense.zh).font(.callout.weight(.medium))
                                    }
                                    if !sense.en.isEmpty {
                                        Text(sense.en).font(.caption).foregroundStyle(.secondary)
                                            .padding(.leading, 42)
                                    }
                                }
                            }
                        }
                        if let example = word.ex.last {
                            WordSurface.hairline.frame(height: 1)
                            Text("语境例句").font(.headline)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(example.en).font(.callout)
                                Text(example.zh).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .wordCard(raised: false)
                        }
                        if !word.col.isEmpty {
                            WordSurface.hairline.frame(height: 1)
                            Text("常用搭配").font(.headline)
                            ForEach(word.col.prefix(2), id: \.self) { Text($0).font(.caption) }
                        }
                        if !word.tip.isEmpty {
                            Text(word.tip).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(accent)
                    Text("今天的单词已完成").font(.title3.weight(.semibold))
                    Text("明天会按复习时间重新出现。也可以换一本词书继续学习。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("选择词书") { settingsTab = "books"; bookTab = "mine"; model.page = "settings" }
                        .buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 25)
            }
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.searchWord.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.searchWord).font(.system(size: model.panelWordFontSize, weight: .medium))
                    if let entry = model.searchEntry, !entry.uk.isEmpty {
                        Text("英 \(entry.uk)  美 \(entry.us)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.collinsHTML.isEmpty {
                        CollinsEntryView(html: model.collinsHTML,
                            accentHex: AccentRGB(hex: model.accentHex)!.readable(onDark: colorScheme == .dark).hex,
                            dark: colorScheme == .dark).frame(height: 230)
                    } else if !model.definitionText.isEmpty {
                        Text(model.definitionText).font(.callout).textSelection(.enabled)
                    } else if let entry = model.searchEntry {
                        ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                            Text("\(sense.pos) \(sense.zh)").font(.callout).textSelection(.enabled)
                        }
                    } else {
                        Text("当前释义库没有收录这个词。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .wordCard(raised: false)
            }
            if !model.searchMatches.isEmpty {
                Text(model.searchWord.isEmpty ? "匹配的单词" : "相近词")
                    .font(.headline)
                ForEach(model.searchMatches.filter { $0 != model.searchWord }.prefix(8), id: \.self) { match in
                    Button { model.selectSearchWord(match) } label: {
                        HStack {
                            Text(match).font(.callout)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10).wordCard(raised: false)
                    }.buttonStyle(.plain)
                }
            } else if model.searchWord.isEmpty {
                Text("没有找到匹配的词，试试完整拼写。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("查词不会改变正在背的单词或复习记录。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var books: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择一本开始背；切换后会保留已有的记忆记录。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前在背").font(.caption).foregroundStyle(.secondary)
                    Text(model.bookTitle).font(.callout.weight(.semibold))
                }
                Spacer()
                Text("今天 \(model.learnedToday)/\(model.dailyGoal)")
                    .font(.caption.weight(.medium)).foregroundStyle(accent)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .wordCard(raised: true)
            WordSegments(selection: $bookTab, options: [
                SegmentChoice(id: "mine", title: "我的词书"),
                SegmentChoice(id: "discover", title: "下载词书")
            ], accent: accent).frame(height: 34)
            if bookTab == "mine" {
                Text("内置词书").font(.headline)
                ForEach(model.books.filter { ["core", "reading", "listening", "speaking"].contains($0.id) }, id: \.id) { book in
                    bookRow(book)
                }
                Text("按雅思学习场景筛选自 Word Atlas；不是雅思官方词表。")
                    .font(.caption).foregroundStyle(.secondary)
                let personal = model.books.filter { !["core", "reading", "listening", "speaking"].contains($0.id) }
                if !personal.isEmpty {
                    WordSurface.hairline.frame(height: 1)
                    Text("已下载与导入").font(.headline)
                    ForEach(personal, id: \.id) { book in bookRow(book) }
                }
                WordSurface.hairline.frame(height: 1)
                Button("导入文件词书…") { model.importBook() }
                    .buttonStyle(.bordered)
                Text("支持 CSV / TSV；表头需要 word, meaning。可选 phonetic、example、example_zh。")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.importMessage.isEmpty {
                    Text(model.importMessage).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("热门考试").font(.headline)
                    Text("按公开词表整理；并非考试机构官方词表。下载后可离线背诵。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(PopularBook.choices) { choice in
                    HStack(spacing: 10) {
                        Image(systemName: model.downloaded(choice.id) ? "checkmark.circle.fill" : "arrow.down.book.closed")
                            .foregroundStyle(accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title).font(.callout.weight(.semibold))
                            Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button(model.downloaded(choice.id) ? "开始学习" : model.downloadBookID == choice.id ? "下载中" : "下载并开始") {
                            if model.downloaded(choice.id) {
                                model.selectBook(choice.id)
                                model.page = "study"
                            } else { model.downloadBook(choice) }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(model.downloadBookID != nil)
                    }
                    .padding(11).wordCard(raised: false)
                }
                Link("查看热门考试词表来源 ↗", destination: URL(string: "https://github.com/grhliu/wordtyper-vocabularies")!)
                    .font(.caption)
                WordSurface.hairline.frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FreeMdict 精选").font(.headline)
                    Text("点击下载并开始，即可自动导入；以后无需联网。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(FreemdictBook.choices) { choice in
                    HStack(spacing: 10) {
                        Image(systemName: model.downloaded(choice.id) ? "checkmark.circle.fill" : "arrow.down.book.closed")
                            .foregroundStyle(accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title).font(.callout.weight(.semibold))
                            Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button(model.downloaded(choice.id) ? "开始学习" : model.downloadBookID == choice.id ? "下载中" : "下载并开始") {
                            if model.downloaded(choice.id) {
                                if model.selectedBookID != choice.id { model.selectBook(choice.id) }
                                model.page = "study"
                            } else { model.downloadBook(choice) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.downloadBookID != nil)
                    }
                    .padding(11).wordCard(raised: false)
                }
                if model.downloadBookID != nil { ProgressView().controlSize(.small) }
                if !model.downloadMessage.isEmpty {
                    Text(model.downloadMessage).font(.caption)
                        .foregroundStyle(model.downloadMessage.hasPrefix("下载失败") ? Color.orange : Color.secondary)
                }
                Link("查看 FreeMdict 来源 ↗", destination: URL(string: "https://downloads.freemdict.com/")!)
                    .font(.caption)
            }
        }
    }

    private var dictionaries: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择背词时显示的释义。切换释义不会改变词书或学习进度。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前释义").font(.caption).foregroundStyle(.secondary)
                    Text(model.dictionaryTitle).font(.callout.weight(.semibold))
                }
                Spacer()
                Image(systemName: "text.book.closed").foregroundStyle(accent)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).wordCard(raised: true)
            Text("已可使用").font(.headline)
            ForEach([("book", "词书自带释义", "无需下载 · 跟随当前词书"),
                ("collins", "柯林斯 COBUILD", "英汉双解 · 本地词典"),
                ("ecdict.zh", "ECDICT 英汉", "中文释义 · 本地词典"),
                ("ecdict.en", "ECDICT 英英", "英文释义 · 本地词典")], id: \.0) { choice in
                let (id, title, detail) = choice
                if id == "book" || (id == "collins" && model.collinsReady) || (id.hasPrefix("ecdict.") && model.ecdictReady) {
                    Button { model.selectDictionary(id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.selectedDictionaryID == id ? "checkmark.circle.fill" : "text.book.closed")
                                .foregroundStyle(model.selectedDictionaryID == id ? accent : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title).font(.callout.weight(.semibold))
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedDictionaryID == id {
                                Text("使用中").font(.caption).foregroundStyle(accent)
                            }
                        }
                        .padding(11).wordCard(raised: model.selectedDictionaryID == id)
                    }.buttonStyle(.plain)
                }
            }
            WordSurface.hairline.frame(height: 1)
            Text("下载更多释义").font(.headline)
            if !model.collinsReady {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.book.closed").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text("柯林斯 COBUILD").font(.callout.weight(.semibold))
                            Text("推荐").font(.caption2.weight(.semibold)).foregroundStyle(accent)
                        }
                        Text("来自 FreeMdict · 约 50 MB · 下载后本机转换")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button(model.downloadDictionaryID == "collins" ? "下载中" : "下载并使用") { model.downloadDictionary("collins") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(model.downloadDictionaryID != nil)
                }.padding(11).wordCard(raised: false)
            }
            if !model.ecdictReady {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.book.closed").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ECDICT 英汉 + 英英").font(.callout.weight(.semibold))
                        Text("一次下载，两种释义 · 约 66 MB · MIT 开源")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button(model.downloadDictionaryID == "ecdict" ? "下载中" : "下载") { model.downloadDictionary("ecdict") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(model.downloadDictionaryID != nil)
                }.padding(11).wordCard(raised: false)
            }
            if model.downloadDictionaryID != nil { ProgressView().controlSize(.small) }
            if !model.dictionaryDownloadMessage.isEmpty {
                Text(model.dictionaryDownloadMessage).font(.caption)
                    .foregroundStyle(model.dictionaryDownloadMessage.hasPrefix("下载失败") ? Color.orange : Color.secondary)
            }
            Link("查看 FreeMdict 来源 ↗", destination: URL(string: "https://downloads.freemdict.com/")!)
                .font(.caption)
            Link("查看 ECDICT 来源 ↗", destination: URL(string: "https://github.com/skywind3000/ECDICT")!)
                .font(.caption)
            DisclosureGroup("本地释义文件") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.dictionaryFolderURL.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                    Button("在访达中查看") { model.openDictionaryFolder() }.buttonStyle(.bordered)
                }.padding(.top, 8)
            }.font(.callout.weight(.medium))
        }
    }

    private func bookRow(_ book: (id: String, title: String, detail: String, count: Int)) -> some View {
        Button {
            if model.selectedBookID != book.id { model.selectBook(book.id) }
            model.page = "study"
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.selectedBookID == book.id ? "checkmark.circle.fill" : "book.closed")
                    .foregroundStyle(model.selectedBookID == book.id ? accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.callout.weight(.semibold))
                    Text(book.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.selectedBookID == book.id ? "使用中" : "\(book.count) 词")
                    .font(.caption).foregroundStyle(model.selectedBookID == book.id ? accent : Color.secondary)
            }
            .padding(11).wordCard(raised: model.selectedBookID == book.id)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                model.selectedBookID == book.id ? accent.opacity(0.35) : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var settingsTabs: some View {
        WordSegments(selection: $settingsTab, options: [
            SegmentChoice(id: "books", title: "词书"),
            SegmentChoice(id: "dictionaries", title: "释义"),
            SegmentChoice(id: "learning", title: "学习"),
            SegmentChoice(id: "shortcuts", title: "快捷键"),
            SegmentChoice(id: "appearance", title: "外观"),
            SegmentChoice(id: "general", title: "通用")
        ], accent: accent)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if settingsTab == "books" { books }
                else if settingsTab == "dictionaries" { dictionaries }
                else if settingsTab == "appearance" { appearanceSettings }
                else if settingsTab == "learning" { learningSettings }
                else if settingsTab == "shortcuts" { shortcutSettings }
                else { generalSettings }
            }.animation(nil, value: settingsTab)
        }
        .onAppear { customHex = model.accentHex }
        .onChange(of: model.accentHex) { customHex = $0 }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("状态栏文字").font(.headline)
                    Spacer()
                    Button("恢复默认") { model.statusFontSize = 14 }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(accent)
                        .disabled(model.statusFontSize == 14)
                }
                HStack {
                    Text("字号").font(.callout).frame(width: 38, alignment: .leading)
                    Slider(value: $model.statusFontSize, in: 9...18, step: 0.5)
                        .accessibilityLabel("状态栏字号")
                    Text(String(format: "%.1f pt", model.statusFontSize))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
                Text("即时应用到菜单栏单词；较长的单词会按需加宽。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .wordCard(raised: false)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("面板单词").font(.headline)
                    Spacer()
                    Button("恢复默认") { model.panelWordFontSize = 14 }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(accent)
                        .disabled(model.panelWordFontSize == 14)
                }
                HStack {
                    Text("字号").font(.callout).frame(width: 38, alignment: .leading)
                    Slider(value: $model.panelWordFontSize, in: 12...30, step: 1)
                        .accessibilityLabel("面板单词字号")
                    Text(String(format: "%.0f pt", model.panelWordFontSize))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
                Text("调整面板里英文单词的大小；长词会自动缩小以适应词卡。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .wordCard(raised: false)
            WordSurface.hairline.frame(height: 1)
            VStack(alignment: .leading, spacing: 9) {
                Text("外观模式").font(.headline)
                WordSegments(selection: $model.appearanceMode, options: [
                    SegmentChoice(id: "system", title: "跟随系统"),
                    SegmentChoice(id: "light", title: "浅色"),
                    SegmentChoice(id: "dark", title: "深色")
                ], accent: accent)
            }
            VStack(alignment: .leading, spacing: 7) {
                Toggle("透明玻璃背景", isOn: $model.glassBackground)
                    .toggleStyle(.switch).controlSize(.mini).tint(accent).font(.callout.weight(.medium))
                Text("开启时透出桌面背景；关闭后使用实色面板。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .wordCard(raised: false)
            WordSurface.hairline.frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("强调色").font(.headline)
                    Text("选择经典颜色，或调出属于你的 esai。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 8) {
                    ForEach(AccentPreset.choices) { preset in
                        Button { model.setAccent(preset.hex); customHex = model.accentHex; hexError = false } label: {
                            VStack(spacing: 6) {
                                let color = AccentRGB(hex: preset.hex)!
                                Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                                    .frame(width: 29, height: 29)
                                    .overlay {
                                        if model.accentHex == preset.hex {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(model.accentHex == preset.hex ? accent : Color.clear, lineWidth: 1.5))
                                Text(preset.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain).help(preset.name).accessibilityLabel(preset.name)
                    }
                }
                HStack(spacing: 8) {
                    ColorPicker("自定义颜色", selection: Binding(get: { model.selectedAccent }, set: {
                        model.setAccentColor($0); hexError = false
                    }), supportsOpacity: false)
                        .font(.caption)
                    Spacer(minLength: 0)
                    TextField("#RRGGBB", text: $customHex)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                        .onSubmit { applyCustomHex() }
                    Button("应用") { applyCustomHex() }.buttonStyle(.bordered)
                }
                if hexError { Text("请输入六位 HEX 色值，例如 #2878ED。").font(.caption).foregroundStyle(.red) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("强调色预览", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(accent)
                        Spacer()
                        Text("已启用").font(.caption.weight(.medium)).foregroundStyle(accent)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                    Capsule().fill(accent).frame(height: 5)
                    Text("实时应用并保存；浅色和深色模式自动调整可读性。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12).wordCard(raised: false)
            }
        }
    }

    private func applyCustomHex() {
        guard AccentRGB(hex: customHex) != nil else { hexError = true; return }
        model.setAccent(customHex)
        customHex = model.accentHex
        hexError = false
    }

    private var learningSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("学习计划").font(.headline)
                Stepper("每天新词 \(model.dailyGoal) 个", value: $model.dailyGoal, in: 1...50)
                Picker("自动换词", selection: $model.autoMinutes) {
                    Text("关闭").tag(0)
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("60 分钟").tag(60)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .wordCard(raised: false)
            Text("切词不计为学会；按“忘了 / 模糊 / 认识”才会安排复习。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键").font(.headline)
            Text("切换与查看").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ShortcutRow(title: "下一词", shortcut: model.nextShortcut) { model.setShortcut($0, action: 1) }
            ShortcutRow(title: "上一词", shortcut: model.previousShortcut) { model.setShortcut($0, action: 2) }
            ShortcutRow(title: "按住显示中文", shortcut: model.meaningShortcut) { model.setShortcut($0, action: 3) }
            WordSurface.hairline.frame(height: 1)
            Text("给当前单词评分").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ShortcutRow(title: "忘了", shortcut: model.forgotShortcut) { model.setShortcut($0, action: 4) }
            ShortcutRow(title: "模糊", shortcut: model.uncertainShortcut) { model.setShortcut($0, action: 5) }
            ShortcutRow(title: "认识", shortcut: model.knownShortcut) { model.setShortcut($0, action: 6) }
            if !model.hotKeyMessage.isEmpty { Text(model.hotKeyMessage).font(.caption).foregroundStyle(.orange) }
            Text("打开面板后可用评分快捷键。点击对应按钮再按新组合；须包含 ⌥、⌃ 或 ⌘。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            UpdateControls(service: model.updates)
        }
    }

    private var footer: some View {
        HStack {
            if model.page == "study" {
                WordFooterAction(title: "设置", symbol: "slider.horizontal.3", destructive: false) {
                    model.page = "settings"
                }
            } else if model.page == "search" {
                WordFooterAction(title: "返回背词", symbol: "chevron.left", destructive: false) {
                    model.updateSearchQuery("")
                }
            } else {
                Text("esai单词").foregroundStyle(.tertiary)
            }
            Spacer()
            WordFooterAction(title: "退出", symbol: "power", destructive: true) {
                NSApp.terminate(nil)
            }
        }
    }
}

@MainActor final class WordbarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = WordModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKeyHandler: EventHandlerRef?
    private var nextHotKey: EventHotKeyRef?
    private var previousHotKey: EventHotKeyRef?
    private var meaningHotKey: EventHotKeyRef?
    private var forgotHotKey: EventHotKeyRef?
    private var uncertainHotKey: EventHotKeyRef?
    private var knownHotKey: EventHotKeyRef?
    private var showingStatusMeaning = false
    private var timer: Timer?
    private var dayTimer: Timer?
    private var previewWindow: NSWindow?
    private var localPanelMonitor: Any?
    private var globalPanelMonitor: Any?
    private var panelResignObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onWordChange = { [weak self] in
            guard let self else { return }
            self.updateStatus()
            if (self.previewWindow != nil || self.popover.isShown) && self.model.page == "study" && !self.model.revealed {
                self.model.revealCurrent()
            }
        }
        if CommandLine.arguments.contains("--preview") {
            NSApp.setActivationPolicy(.regular)
            applyAppearance()
            model.revealCurrent()
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--preview-settings=") }) { model.page = "settings" }
            if let query = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-search=") })?.split(separator: "=", maxSplits: 1).last {
                model.searchQuery = String(query)
                model.refreshSearch()
                model.page = "search"
            }
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 560),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "esai单词 — 预览"
            window.appearance = NSApp.appearance
            window.contentViewController = WordPanelHostController(model: model)
            model.onAppearanceChange = { [weak self] in self?.applyAppearance() }
            window.makeKeyAndOrderFront(nil)
            previewWindow = window
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 150)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
        statusItem.button?.alignment = .left
        statusItem.button?.font = NSFont.systemFont(ofSize: CGFloat(model.statusFontSize), weight: .medium)
        statusItem.button?.cell?.lineBreakMode = .byTruncatingTail
        popover.contentSize = NSSize(width: 400, height: 560)
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = WordPanelHostController(model: model)
        model.updates.willPresentUpdate = { [weak self] in
            self?.stopPanelMonitors()
            self?.popover.performClose(nil)
        }
        model.updates.start()
        model.onTimerChange = { [weak self] in self?.scheduleTimer() }
        model.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        model.onHotKeyChange = { [weak self] in self?.registerHotKeys() ?? false }
        model.onStatusFontChange = { [weak self] in self?.applyStatusFont() }
        applyAppearance()
        updateStatus()
        scheduleTimer()
        scheduleNextDay()
        let types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let handlerStatus = types.withUnsafeBufferPointer { eventTypes in
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let owner = Unmanaged<WordbarDelegate>.fromOpaque(userData).takeUnretainedValue()
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            if CommandLine.arguments.contains("--hotkey-observe") && identifier.id == 3 {
                print("MEANING_EVENT \(released ? "released" : "pressed")")
                fflush(stdout)
            }
            Task { @MainActor in
                if identifier.id == 3 {
                    owner.showingStatusMeaning = !released
                    owner.updateStatus()
                } else if !released {
                    switch identifier.id {
                    case 1: owner.model.move(1)
                    case 2: owner.model.move(-1)
                    case 4...6:
                        if owner.model.revealed { owner.model.grade(Int(identifier.id - 4)) }
                    default: break
                    }
                }
            }
            return noErr
            }, eventTypes.count, eventTypes.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        if handlerStatus != noErr { model.hotKeyMessage = "无法监听全局快捷键（\(handlerStatus)）。" }
        if !registerHotKeys() { model.hotKeyMessage = "快捷键注册失败，请在设置中更换。" }
        if CommandLine.arguments.contains("--hotkey-check") {
            print("HOTKEY_CHECK next=\(model.nextShortcut.displayLabel) previous=\(model.previousShortcut.displayLabel) meaning=\(model.meaningShortcut.displayLabel) forgot=\(model.forgotShortcut.displayLabel) uncertain=\(model.uncertainShortcut.displayLabel) known=\(model.knownShortcut.displayLabel) registered=\(model.hotKeyMessage.isEmpty)")
            exit(model.hotKeyMessage.isEmpty ? 0 : 2)
        }
        if CommandLine.arguments.contains("--meaning-check") {
            let english = statusItem.button?.title ?? ""
            let englishWidth = statusItem.length
            showingStatusMeaning = true
            updateStatus()
            let chinese = statusItem.button?.title ?? ""
            let chineseWidth = statusItem.length
            showingStatusMeaning = false
            updateStatus()
            let restored = statusItem.button?.title == english
            model.move(1)
            let nextWidth = statusItem.length
            print("MEANING_CHECK english=\(english) held=\(chinese) released=\(restored) widths=\(englishWidth),\(chineseWidth),\(nextWidth) flower=\(statusItem.button?.image != nil)")
            exit(english != chinese && restored && statusItem.button?.image == nil
                && englishWidth == chineseWidth && chineseWidth == nextWidth ? 0 : 2)
        }
        if CommandLine.arguments.contains("--focus-check") || CommandLine.arguments.contains("--search-focus-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.togglePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let active = NSApp.isActive
                    let key = self?.popover.contentViewController?.view.window?.isKeyWindow == true
                    let shown = self?.popover.isShown == true
                    let revealed = self?.model.revealed == true
                    let responder = self?.popover.contentViewController?.view.window?.firstResponder
                    let searchFocused = responder is NSTextView
                    print("FOCUS_CHECK active=\(active) key=\(key) shown=\(shown) revealed=\(revealed) search=\(searchFocused) responder=\(responder.map { String(describing: type(of: $0)) } ?? "none")")
                    exit(active && key && shown && revealed
                        && (!CommandLine.arguments.contains("--search-focus-check") || searchFocused) ? 0 : 2)
                }
            }
        } else if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.togglePopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        dayTimer?.invalidate()
        stopPanelMonitors()
        if let nextHotKey { UnregisterEventHotKey(nextHotKey) }
        if let previousHotKey { UnregisterEventHotKey(previousHotKey) }
        if let meaningHotKey { UnregisterEventHotKey(meaningHotKey) }
        if let forgotHotKey { UnregisterEventHotKey(forgotHotKey) }
        if let uncertainHotKey { UnregisterEventHotKey(uncertainHotKey) }
        if let knownHotKey { UnregisterEventHotKey(knownHotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    private func updateStatus() {
        guard let statusItem, let button = statusItem.button else { return }
        let title = model.current.map { word in
            let meaning = word.senses.first?.zh.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let shortMeaning = meaning.components(separatedBy: CharacterSet(charactersIn: "；;、")).first ?? meaning
            let display = showingStatusMeaning && !shortMeaning.isEmpty
                ? String(shortMeaning.prefix(8)) + (shortMeaning.count > 8 ? "…" : "") : word.w
            return "  \(display)"
        } ?? "  今日完成"
        button.title = title
        statusItem.length = max(150, min(230, ceil((title as NSString).size(
            withAttributes: [.font: button.font ?? NSFont.systemFont(ofSize: CGFloat(model.statusFontSize))]).width) + 16))
        button.toolTip = model.current.map { "\($0.w) · \($0.senses.first?.zh ?? "") · \(model.bookTitle)" } ?? "今天的单词已完成"
    }

    private func applyStatusFont() {
        statusItem.button?.font = NSFont.systemFont(ofSize: CGFloat(model.statusFontSize), weight: .medium)
        updateStatus()
    }

    private func registerHotKeys() -> Bool {
        showingStatusMeaning = false
        updateStatus()
        if let nextHotKey { UnregisterEventHotKey(nextHotKey); self.nextHotKey = nil }
        if let previousHotKey { UnregisterEventHotKey(previousHotKey); self.previousHotKey = nil }
        if let meaningHotKey { UnregisterEventHotKey(meaningHotKey); self.meaningHotKey = nil }
        if let forgotHotKey { UnregisterEventHotKey(forgotHotKey); self.forgotHotKey = nil }
        if let uncertainHotKey { UnregisterEventHotKey(uncertainHotKey); self.uncertainHotKey = nil }
        if let knownHotKey { UnregisterEventHotKey(knownHotKey); self.knownHotKey = nil }
        let nextStatus = RegisterEventHotKey(model.nextShortcut.code, model.nextShortcut.modifiers,
            EventHotKeyID(signature: 0x45534149, id: 1), GetApplicationEventTarget(), 0, &nextHotKey)
        let previousStatus = RegisterEventHotKey(model.previousShortcut.code, model.previousShortcut.modifiers,
            EventHotKeyID(signature: 0x45534149, id: 2), GetApplicationEventTarget(), 0, &previousHotKey)
        let meaningStatus = RegisterEventHotKey(model.meaningShortcut.code, model.meaningShortcut.modifiers,
            EventHotKeyID(signature: 0x45534149, id: 3), GetApplicationEventTarget(), 0, &meaningHotKey)
        let forgotStatus = RegisterEventHotKey(model.forgotShortcut.code, model.forgotShortcut.modifiers,
            EventHotKeyID(signature: 0x45534149, id: 4), GetApplicationEventTarget(), 0, &forgotHotKey)
        let uncertainStatus = RegisterEventHotKey(model.uncertainShortcut.code, model.uncertainShortcut.modifiers,
            EventHotKeyID(signature: 0x45534149, id: 5), GetApplicationEventTarget(), 0, &uncertainHotKey)
        let knownStatus = RegisterEventHotKey(model.knownShortcut.code, model.knownShortcut.modifiers,
            EventHotKeyID(signature: 0x45534149, id: 6), GetApplicationEventTarget(), 0, &knownHotKey)
        if [nextStatus, previousStatus, meaningStatus, forgotStatus, uncertainStatus, knownStatus].contains(where: { $0 != noErr }) {
            if let nextHotKey { UnregisterEventHotKey(nextHotKey); self.nextHotKey = nil }
            if let previousHotKey { UnregisterEventHotKey(previousHotKey); self.previousHotKey = nil }
            if let meaningHotKey { UnregisterEventHotKey(meaningHotKey); self.meaningHotKey = nil }
            if let forgotHotKey { UnregisterEventHotKey(forgotHotKey); self.forgotHotKey = nil }
            if let uncertainHotKey { UnregisterEventHotKey(uncertainHotKey); self.uncertainHotKey = nil }
            if let knownHotKey { UnregisterEventHotKey(knownHotKey); self.knownHotKey = nil }
            return false
        }
        return true
    }

    private func applyAppearance() {
        let appearance: NSAppearance?
        switch model.appearanceMode {
        case "dark": appearance = NSAppearance(named: .darkAqua)
        case "light": appearance = NSAppearance(named: .aqua)
        default: appearance = nil
        }
        NSApp.appearance = appearance
        popover.appearance = appearance
        if popover.contentViewController?.isViewLoaded == true {
            popover.contentViewController?.view.appearance = appearance
            popover.contentViewController?.view.window?.appearance = appearance
        }
        previewWindow?.appearance = appearance
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard model.autoMinutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(model.autoMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.move(1) }
        }
    }

    private func scheduleNextDay() {
        dayTimer?.invalidate()
        guard let next = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: .now)) else { return }
        dayTimer = Timer.scheduledTimer(withTimeInterval: max(1, next.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.model.refreshDay()
                self?.scheduleNextDay()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            applyAppearance()
            model.updateSearchQuery("")
            model.page = "study"
            model.revealCurrent()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            focusPanel()
            DispatchQueue.main.async { [weak self] in
                self?.focusPanel()
                self?.model.searchFocusToken += 1
            }
        }
    }

    private func focusPanel() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        window.orderFront(nil)
    }

    func popoverDidShow(_ notification: Notification) {
        focusPanel()
        stopPanelMonitors()
        localPanelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.popover.performClose(nil); return nil }
                if ["study", "search"].contains(self.model.page),
                   event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    if event.keyCode == 51 {
                        self.model.updateSearchQuery(String(self.model.searchQuery.dropLast()))
                        return nil
                    }
                    if let character = event.charactersIgnoringModifiers,
                       character.count == 1,
                       character.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'" }) {
                        self.model.updateSearchQuery(self.model.searchQuery + character.lowercased())
                        return nil
                    }
                }
                return event
            }
            guard let window = self.popover.contentViewController?.view.window else { return event }
            if event.window === window || event.window === self.statusItem.button?.window || event.window?.sheetParent === window {
                return event
            }
            if let other = event.window, other is NSPanel || other.level > .normal { return event }
            self.popover.performClose(nil)
            return event
        }
        globalPanelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        panelResignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: NSApp, queue: .main) { [weak self] _ in self?.popover.performClose(nil) }
    }

    func popoverDidClose(_ notification: Notification) { stopPanelMonitors() }

    private func stopPanelMonitors() {
        if let localPanelMonitor { NSEvent.removeMonitor(localPanelMonitor); self.localPanelMonitor = nil }
        if let globalPanelMonitor { NSEvent.removeMonitor(globalPanelMonitor); self.globalPanelMonitor = nil }
        if let panelResignObserver { NotificationCenter.default.removeObserver(panelResignObserver); self.panelResignObserver = nil }
    }
}

@main struct WordbarApp {
    static func main() {
        if CommandLine.arguments.contains("--dictionary-check") {
            let model = WordModel()
            model.selectDictionary("collins")
            model.loadCollins()
            print("DICTIONARY_CHECK ready=\(model.collinsReady) word=\(model.current?.w ?? "none") html=\(model.collinsHTML.count)")
            guard model.collinsReady, !model.collinsHTML.isEmpty else { exit(1) }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            let model = WordModel()
            print("atlas=\(model.atlasCount) books=\(model.books.count) queue=\(model.queue.count) first=\(model.current?.w ?? "none")")
            guard model.atlasCount == 7298, model.books.count >= 4, model.current != nil else { exit(1) }
            return
        }
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--download-check") }) {
            let model = WordModel()
            if let choice = PopularBook.choices.first(where: { CommandLine.arguments.contains("--download-check=\($0.id)") }) {
                model.downloadBook(choice)
                let deadline = Date().addingTimeInterval(90)
                while model.downloadBookID != nil && Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                }
                print("DOWNLOAD_CHECK \(model.downloadMessage) selected=\(model.bookTitle) meaning=\(model.current?.senses.first?.zh ?? "none")")
                guard model.downloaded(choice.id), model.current?.senses.first?.zh.isEmpty == false else { exit(1) }
                return
            }
            let choice = FreemdictBook.choices.first(where: {
                CommandLine.arguments.contains("--download-check=\($0.id)")
            }) ?? FreemdictBook.choices[0]
            model.downloadBook(choice)
            let deadline = Date().addingTimeInterval(45)
            while model.downloadBookID != nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            print("DOWNLOAD_CHECK \(model.downloadMessage) selected=\(model.bookTitle) meaning=\(model.current?.senses.first?.zh ?? "none") example=\(model.current?.ex.count ?? 0) english=\(model.current?.senses.first?.en ?? "")")
            guard model.downloaded(choice.id),
                  !model.downloadMessage.hasPrefix("下载失败"),
                  model.current?.senses.first?.zh.isEmpty == false else { exit(1) }
            return
        }
        if CommandLine.arguments.contains("--dictionary-download-check=ecdict") {
            let model = WordModel()
            model.downloadDictionary("ecdict")
            let deadline = Date().addingTimeInterval(180)
            while model.downloadDictionaryID != nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            model.loadCollins()
            print("DICTIONARY_DOWNLOAD_CHECK \(model.dictionaryDownloadMessage) ready=\(model.ecdictReady) selected=\(model.dictionaryTitle) text=\(model.definitionText.prefix(80))")
            guard model.ecdictReady, !model.definitionText.isEmpty else { exit(1) }
            return
        }
        if CommandLine.arguments.contains("--search-check") {
            let model = WordModel()
            model.searchQuery = "academic"
            let started = CFAbsoluteTimeGetCurrent()
            model.refreshSearch()
            print("SEARCH_CHECK matches=\(model.searchMatches.prefix(5)) selected=\(model.searchWord) definition=\(model.definitionText.prefix(60)) elapsed_ms=\(Int((CFAbsoluteTimeGetCurrent() - started) * 1000))")
            guard model.searchWord == "academic", !model.definitionText.isEmpty || !model.collinsHTML.isEmpty else { exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = WordbarDelegate()
        app.delegate = delegate
        app.run()
    }
}
