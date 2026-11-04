import Foundation

/// Minimal client for the (unofficial) Bring! REST API, as used by the Bring! web app.
struct BringSession: Codable {
    var uuid: String
    var accessToken: String
    var defaultListUUID: String?
    var name: String?
}

struct BringList: Identifiable, Hashable {
    let id: String   // listUuid
    let name: String
}

struct BringItem: Identifiable, Hashable {
    var id: String { (uuid ?? "") + "|" + name + "|" + spec }
    let uuid: String?
    let name: String      // catalog key (often German, e.g. "Milch") or free text
    let spec: String
}

enum BringError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return L("Sign-in failed or session expired.")
        case .http(let code, let body): return L("The Bring! server returned error %d.", code) + " " + String(body.prefix(120))
        case .decoding(let what): return L("Unexpected response from Bring! (%@).", what)
        }
    }
}

final class BringAPI {
    static let base = URL(string: "https://api.getbring.com/rest/")!
    private let apiKey = "cof4Nc6D8saplXjE3h3HXqHH8m7VU2i1Gs0g85Sp"
    var session: BringSession?

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: Self.base)!)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(apiKey, forHTTPHeaderField: "X-BRING-API-KEY")
        req.setValue("webApp", forHTTPHeaderField: "X-BRING-CLIENT")
        req.setValue("webApp", forHTTPHeaderField: "X-BRING-CLIENT-SOURCE")
        req.setValue("bring", forHTTPHeaderField: "X-BRING-APPLICATION")
        req.setValue("NL", forHTTPHeaderField: "X-BRING-COUNTRY")
        if let s = session {
            req.setValue(s.uuid, forHTTPHeaderField: "X-BRING-USER-UUID")
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private static func formBody(_ params: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)!
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw BringError.unauthorized }
        guard (200..<300).contains(code) else {
            throw BringError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BringError.decoding("no JSON object")
        }
        return obj
    }

    // MARK: Auth

    func login(email: String, password: String) async throws -> BringSession {
        var req = request("v2/bringauth", method: "POST")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody([("email", email), ("password", password)])
        let obj = try json(try await send(req))
        guard let uuid = obj["uuid"] as? String, let token = obj["access_token"] as? String else {
            throw BringError.decoding("login")
        }
        let s = BringSession(uuid: uuid, accessToken: token,
                             defaultListUUID: obj["bringListUUID"] as? String,
                             name: obj["name"] as? String)
        session = s
        return s
    }

    // MARK: Lists

    func lists() async throws -> [BringList] {
        guard let s = session else { throw BringError.unauthorized }
        let obj = try json(try await send(request("v2/bringusers/\(s.uuid)/lists")))
        let arr = obj["lists"] as? [[String: Any]] ?? []
        return arr.compactMap { d in
            guard let id = d["listUuid"] as? String else { return nil }
            return BringList(id: id, name: d["name"] as? String ?? L("List"))
        }
    }

    func items(listUUID: String) async throws -> (purchase: [BringItem], recently: [BringItem]) {
        let obj = try json(try await send(request("v2/bringlists/\(listUUID)")))
        // Newer responses nest under "items"; older ones are flat.
        let container = (obj["items"] as? [String: Any]) ?? obj
        func parse(_ key: String) -> [BringItem] {
            (container[key] as? [[String: Any]] ?? []).compactMap { d in
                guard let name = (d["itemId"] as? String) ?? (d["name"] as? String) else { return nil }
                return BringItem(uuid: d["uuid"] as? String, name: name,
                                 spec: d["specification"] as? String ?? "")
            }
        }
        return (parse("purchase"), parse("recently"))
    }

    enum Operation: String { case purchase = "TO_PURCHASE", recently = "TO_RECENTLY", remove = "REMOVE" }

    func change(listUUID: String, items: [(name: String, spec: String, uuid: String?)], op: Operation) async throws {
        var req = request("v2/bringlists/\(listUUID)/items", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let changes: [[String: Any]] = items.map { it in
            var c: [String: Any] = [
                "accuracy": "0.0", "altitude": "0.0", "latitude": "0.0", "longitude": "0.0",
                "itemId": it.name, "spec": it.spec, "operation": op.rawValue,
            ]
            c["uuid"] = it.uuid ?? UUID().uuidString.lowercased()
            return c
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["changes": changes, "sender": ""])
        try await send(req)
    }

    /// Older form-based endpoint; removes an item by name from purchase and recently.
    func legacyRemove(listUUID: String, name: String) async throws {
        var req = request("v2/bringlists/\(listUUID)", method: "PUT")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody([("uuid", listUUID), ("purchase", ""), ("recently", ""),
                                      ("specification", ""), ("remove", name), ("sender", "null")])
        try await send(req)
    }

    // MARK: Settings & catalog

    /// Article language configured for each list, e.g. "nl-NL".
    func listLanguages() async throws -> [String: String] {
        guard let s = session else { return [:] }
        let obj = try json(try await send(request("bringusersettings/\(s.uuid)")))
        var result: [String: String] = [:]
        for entry in obj["userlistsettings"] as? [[String: Any]] ?? [] {
            guard let id = entry["listUuid"] as? String else { continue }
            for st in entry["usersettings"] as? [[String: Any]] ?? []
            where st["key"] as? String == "listArticleLanguage" {
                if let v = st["value"] as? String { result[id] = v }
            }
        }
        return result
    }

    /// Map of catalog key (German) -> localized name.
    static func catalog(locale: String) async -> [String: String] {
        guard let url = URL(string: "https://web.getbring.com/locale/articles.\(locale).json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        func walk(_ d: [String: Any]) {
            for (k, v) in d {
                if let s = v as? String { out[k] = s } else if let sub = v as? [String: Any] { walk(sub) }
            }
        }
        walk(obj)
        return out
    }
}
