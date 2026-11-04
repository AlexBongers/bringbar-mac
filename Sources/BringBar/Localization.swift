import Foundation

/// English source text is the key; Resources/<lang>.lproj holds the translation.
/// The language is switchable at runtime, so views observe `Language.shared`.
final class Language: ObservableObject {
    static let shared = Language()

    @Published var code: String { didSet { UserDefaults.standard.set(code, forKey: "language") } }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "language"), ["en", "nl"].contains(saved) {
            code = saved
        } else {
            code = (Locale.preferredLanguages.first ?? "en").hasPrefix("nl") ? "nl" : "en"
        }
    }

    var bundle: Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Language.shared.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
