import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var loggedIn = false
    @Published var busy = false
    @Published var message: String?
    @Published var isError = false
    @Published var lists: [BringList] = []
    @Published var selectedListID: String? {
        didSet {
            UserDefaults.standard.set(selectedListID, forKey: "selectedList")
            if oldValue != selectedListID { Task { await reloadListContent() } }
        }
    }
    @Published var purchase: [BringItem] = []
    @Published var recently: [BringItem] = []
    @Published var catalog: [String: String] = [:]        // key -> localized
    private var reverseCatalog: [String: String] = [:]    // lowercased localized -> key
    private var catalogLocale: String?
    private var listLanguages: [String: String] = [:]

    private let api = BringAPI()
    private var email: String? { UserDefaults.standard.string(forKey: "email") }

    init() {
        if let raw = Keychain.get("session"),
           let s = try? JSONDecoder().decode(BringSession.self, from: Data(raw.utf8)) {
            api.session = s
            loggedIn = true
            selectedListID = UserDefaults.standard.string(forKey: "selectedList") ?? s.defaultListUUID
            Task { await refreshAll() }
        }
    }

    // MARK: Auth

    func login(email: String, password: String) async {
        busy = true; defer { busy = false }
        do {
            let s = try await api.login(email: email, password: password)
            UserDefaults.standard.set(email, forKey: "email")
            Keychain.set(password, for: "password")
            saveSession(s)
            loggedIn = true
            show(nil)
            if selectedListID == nil { selectedListID = s.defaultListUUID }
            await refreshAll()
        } catch {
            show(L("Sign-in failed: check your email and password."), error: true)
        }
    }

    func logout() {
        Keychain.delete("session"); Keychain.delete("password")
        UserDefaults.standard.removeObject(forKey: "selectedList")
        api.session = nil
        loggedIn = false
        lists = []; purchase = []; recently = []
        selectedListID = nil
    }

    private func saveSession(_ s: BringSession) {
        if let data = try? JSONEncoder().encode(s) { Keychain.set(String(decoding: data, as: UTF8.self), for: "session") }
    }

    /// Runs an API call; on an expired token, silently logs in again with the stored password.
    private func withAuth<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() } catch BringError.unauthorized {
            guard let email, let pw = Keychain.get("password") else { logout(); throw BringError.unauthorized }
            let s = try await api.login(email: email, password: pw)
            saveSession(s)
            return try await op()
        }
    }

    // MARK: Data

    func refreshAll() async {
        do {
            let ls = try await withAuth { try await api.lists() }
            lists = ls
            if selectedListID == nil || !ls.contains(where: { $0.id == selectedListID }) {
                selectedListID = api.session?.defaultListUUID ?? ls.first?.id
            }
            listLanguages = (try? await withAuth { try await api.listLanguages() }) ?? [:]
            await reloadListContent()
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    func reloadListContent() async {
        guard let id = selectedListID, loggedIn else { return }
        let locale = listLanguages[id] ?? "nl-NL"
        if locale != catalogLocale {
            catalogLocale = locale
            var cat = await BringAPI.catalog(locale: locale)
            if cat.isEmpty { cat = await BringAPI.catalog(locale: "nl-NL") }
            catalog = cat
            var rev: [String: String] = [:]
            for (k, v) in cat { rev[v.lowercased()] = k; rev[k.lowercased()] = rev[k.lowercased()] ?? k }
            reverseCatalog = rev
        }
        do {
            let r = try await withAuth { try await api.items(listUUID: id) }
            purchase = r.purchase
            recently = r.recently
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    func displayName(_ key: String) -> String { catalog[key] ?? key }

    /// Parses "Melk, Eieren: 12 stuks, Brood" into (catalogKey, spec) pairs.
    func parse(_ input: String) -> [(name: String, spec: String)] {
        input.split(whereSeparator: { $0 == "," || $0 == "\n" }).compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let raw = pieces.first, !raw.isEmpty else { return nil }
            let key = reverseCatalog[raw.lowercased()] ?? raw.prefix(1).uppercased() + raw.dropFirst()
            return (key, pieces.count > 1 ? pieces[1] : "")
        }
    }

    func suggestions(for text: String) -> [String] {
        let last = text.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard last.count >= 2, !last.contains(":") else { return [] }
        let q = last.lowercased()
        let names = Set(catalog.values)
        let starts = names.filter { $0.lowercased().hasPrefix(q) }.sorted { $0.count < $1.count }
        let contains = names.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }.sorted { $0.count < $1.count }
        return Array((starts + contains).prefix(5))
    }

    func add(_ input: String) async -> Bool {
        guard let id = selectedListID else { show(L("Choose a list first."), error: true); return false }
        let items = parse(input)
        guard !items.isEmpty else { return false }
        busy = true; defer { busy = false }
        do {
            try await withAuth {
                try await api.change(listUUID: id, items: items.map { ($0.name, $0.spec, nil) }, op: .purchase)
            }
            let names = items.map { displayName($0.name) }.joined(separator: ", ")
            show(L("Added: %@", names))
            await reloadListContent()
            return true
        } catch {
            show(error.localizedDescription, error: true)
            return false
        }
    }

    /// Removes the item from the list completely (not "checked off" into recently bought).
    func remove(_ item: BringItem) async {
        guard let id = selectedListID else { return }
        purchase.removeAll { $0 == item }
        do {
            if let uuid = item.uuid {
                try await withAuth {
                    try await api.change(listUUID: id, items: [(item.name, item.spec, uuid)], op: .remove)
                }
                // The server needs a moment; if the item is still there, use the by-name call too.
                try? await Task.sleep(for: .milliseconds(800))
                let r = try await withAuth { try await api.items(listUUID: id) }
                if r.purchase.contains(where: { $0.name == item.name }) {
                    try await withAuth { try await api.legacyRemove(listUUID: id, name: item.name) }
                }
            } else {
                // Lists in the classic format have no item uuids; remove by name.
                try await withAuth { try await api.legacyRemove(listUUID: id, name: item.name) }
            }
            try? await Task.sleep(for: .milliseconds(400))
            show(L("Removed: %@", displayName(item.name)))
        } catch { show(error.localizedDescription, error: true) }
        await reloadListContent()
    }

    private var messageTask: Task<Void, Never>?
    func show(_ text: String?, error: Bool = false) {
        message = text; isError = error
        messageTask?.cancel()
        guard text != nil else { return }
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 6 : 3))
            if !Task.isCancelled { self?.message = nil }
        }
    }
}
