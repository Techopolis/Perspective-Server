import Foundation

struct ApprovedClient: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var token: String
    var allowedOriginHosts: [String]
    var allowedPathPrefixes: [String]
    var isEnabled: Bool
    var isSystemClient: Bool
    let createdAt: Date

    func allowsOrigin(_ originHost: String?) -> Bool {
        guard let originHost else { return true }
        return allowedOriginHosts.contains(originHost.lowercased())
    }

    func allowsPath(_ path: String) -> Bool {
        allowedPathPrefixes.contains { path.hasPrefix($0) }
    }
}

enum AccessDecision: Sendable {
    case allow
    case deny(status: Int, message: String)
}

actor AccessControlManager {
    static let shared = AccessControlManager()

    private let defaultsKey = "approvedApiClientsV1"
    private var clients: [ApprovedClient] = []

    init() {
        clients = Self.loadClients(defaultsKey: defaultsKey)
        if clients.isEmpty {
            clients = Self.defaultClients()
            Self.saveClients(clients, defaultsKey: defaultsKey)
        }
    }

    func listClients() -> [ApprovedClient] {
        clients.sorted { lhs, rhs in
            if lhs.isSystemClient != rhs.isSystemClient {
                return lhs.isSystemClient && !rhs.isSystemClient
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func createClient(name: String, allowedOriginHosts: [String], allowedPathPrefixes: [String] = ["/v1/", "/api/"]) -> ApprovedClient {
        let client = ApprovedClient(
            id: UUID(),
            name: name,
            token: Self.generateToken(),
            allowedOriginHosts: Self.normalizeOrigins(allowedOriginHosts),
            allowedPathPrefixes: allowedPathPrefixes,
            isEnabled: true,
            isSystemClient: false,
            createdAt: Date()
        )
        clients.append(client)
        persist()
        return client
    }

    @discardableResult
    func rotateToken(id: UUID) -> String? {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return nil }
        let newToken = Self.generateToken()
        clients[index].token = newToken
        persist()
        return newToken
    }

    func deleteClient(id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        if clients[index].isSystemClient { return }
        clients.remove(at: index)
        persist()
    }

    func setClientEnabled(id: UUID, enabled: Bool) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].isEnabled = enabled
        persist()
    }

    func tokenForLocalApp() -> String? {
        clients.first(where: { $0.isSystemClient && $0.name == "Local App" })?.token
    }

    func tokenForOrigin(_ originHost: String?) -> String? {
        guard let originHost = originHost?.lowercased() else { return nil }
        return clients.first(where: { $0.isEnabled && $0.allowedOriginHosts.contains(originHost) })?.token
    }

    func allowedBrowserOrigins() -> Set<String> {
        Set(clients.filter { $0.isEnabled }.flatMap { $0.allowedOriginHosts })
    }

    func authorize(path: String, authHeader: String?, originHost: String?) -> AccessDecision {
        guard isProtectedPath(path) else { return .allow }

        guard let token = Self.bearerToken(from: authHeader) else {
            return .deny(status: 401, message: "Unauthorized: missing bearer token")
        }

        guard let client = clients.first(where: { $0.token == token }) else {
            return .deny(status: 401, message: "Unauthorized: invalid bearer token")
        }

        guard client.isEnabled else {
            return .deny(status: 403, message: "Forbidden: client is disabled")
        }

        guard client.allowsPath(path) else {
            return .deny(status: 403, message: "Forbidden: token not allowed for this endpoint")
        }

        guard client.allowsOrigin(originHost) else {
            return .deny(status: 403, message: "Forbidden: origin not approved for this token")
        }

        return .allow
    }

    private func persist() {
        Self.saveClients(clients, defaultsKey: defaultsKey)
    }

    private static func loadClients(defaultsKey: String) -> [ApprovedClient] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([ApprovedClient].self, from: data)) ?? []
    }

    private static func saveClients(_ clients: [ApprovedClient], defaultsKey: String) {
        if let data = try? JSONEncoder().encode(clients) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func defaultClients() -> [ApprovedClient] {
        let localOrigins = ["localhost", "127.0.0.1", "[::1]", "::1"]

        let localAppClient = ApprovedClient(
            id: UUID(),
            name: "Local App",
            token: Self.generateToken(),
            allowedOriginHosts: localOrigins,
            allowedPathPrefixes: ["/v1/", "/api/"],
            isEnabled: true,
            isSystemClient: true,
            createdAt: Date()
        )

        let webClient = ApprovedClient(
            id: UUID(),
            name: "Perspective Intelligence Web",
            token: Self.generateToken(),
            allowedOriginHosts: ["perspectiveintelligence.app", "www.perspectiveintelligence.app"],
            allowedPathPrefixes: ["/v1/", "/api/"],
            isEnabled: true,
            isSystemClient: true,
            createdAt: Date()
        )

        return [localAppClient, webClient]
    }

    private func isProtectedPath(_ path: String) -> Bool {
        path.hasPrefix("/v1/") || path.hasPrefix("/api/")
    }

    private static func normalizeOrigins(_ origins: [String]) -> [String] {
        var set: Set<String> = []
        for value in origins {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty {
                set.insert(trimmed)
            }
        }
        return Array(set).sorted()
    }

    private static func bearerToken(from header: String?) -> String? {
        guard let header else { return nil }
        guard header.lowercased().hasPrefix("bearer ") else { return nil }
        let token = String(header.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private static func generateToken() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var value = "pi_"
        value.reserveCapacity(35)
        for _ in 0..<32 {
            value.append(chars[Int.random(in: 0..<chars.count)])
        }
        return value
    }
}
