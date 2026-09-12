import Foundation

struct PathInfo: Decodable { let directory: String }

struct OCMessage: Decodable {
    let id: String
    let sessionID: String
    let role: String
}

struct OCSession: Decodable {
    let id: String
    let directory: String
    let title: String
    let time: Time
    struct Time: Decodable { let created: Double; let updated: Double }
}

struct MessageWithParts: Decodable {
    let info: OCMessage
    let parts: [Part]
}

enum Part: Decodable {
    case text(id: String, messageID: String, text: String)
    case reasoning(id: String, messageID: String, text: String)
    case tool(id: String, messageID: String, tool: String, status: String)
    case other(id: String, messageID: String, type: String)

    var id: String {
        switch self {
        case let .text(id, _, _), let .reasoning(id, _, _), let .tool(id, _, _, _), let .other(id, _, _): id
        }
    }
    var messageID: String {
        switch self {
        case let .text(_, m, _), let .reasoning(_, m, _), let .tool(_, m, _, _), let .other(_, m, _): m
        }
    }

    private enum Keys: String, CodingKey { case id, messageID, type, text, tool, state }
    private enum StateKeys: String, CodingKey { case status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let id = try c.decode(String.self, forKey: .id)
        let messageID = try c.decode(String.self, forKey: .messageID)
        switch try c.decode(String.self, forKey: .type) {
        case "text":
            self = .text(id: id, messageID: messageID, text: try c.decode(String.self, forKey: .text))
        case "reasoning":
            self = .reasoning(id: id, messageID: messageID, text: try c.decode(String.self, forKey: .text))
        case "tool":
            let tool = try c.decode(String.self, forKey: .tool)
            let status = (try? c.nestedContainer(keyedBy: StateKeys.self, forKey: .state)
                .decode(String.self, forKey: .status)) ?? "unknown"
            self = .tool(id: id, messageID: messageID, tool: tool, status: status)
        case let t:
            self = .other(id: id, messageID: messageID, type: t)
        }
    }
}

struct Permission: Decodable {
    let id: String
    let sessionID: String
    let title: String
}

enum ServerEvent {
    case messageUpdated(OCMessage)
    case partUpdated(Part)
    case sessionStatus(sessionID: String, status: String)
    case sessionIdle(sessionID: String)
    case permissionAsked(Permission)
    case other(String)
}

enum OCError: Error, LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case let .http(code, body): "HTTP \(code): \(body.prefix(300))"
        }
    }
}

struct OpencodeClient: Sendable {
    let baseURL: URL

    private static let decoder = JSONDecoder()

    private func request(_ path: String) -> URLRequest {
        URLRequest(url: baseURL.appending(path: path))
    }

    @discardableResult
    private func check(_ data: Data, _ resp: URLResponse) throws -> Data {
        let code = (resp as! HTTPURLResponse).statusCode
        guard (200..<300).contains(code) else {
            throw OCError.http(code, String(decoding: data, as: UTF8.self))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as _: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: request(path))
        return try Self.decoder.decode(T.self, from: try check(data, resp))
    }

    func post<B: Encodable>(_ path: String, body: B) async throws {
        var req = request(path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        _ = try check(data, resp)
    }

    // MARK: endpoints used

    func pathInfo() async throws -> PathInfo { try await get("/path", as: PathInfo.self) }

    func sessions() async throws -> [OCSession] { try await get("/session", as: [OCSession].self) }

    func createSession(title: String) async throws -> OCSession {
        struct B: Encodable { let title: String }
        struct R: Decodable { let id: String; let directory: String; let title: String; let time: OCSession.Time }
        var req = request("/session")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(B(title: title))
        let (data, resp) = try await URLSession.shared.data(for: req)
        let r = try Self.decoder.decode(R.self, from: try check(data, resp))
        return OCSession(id: r.id, directory: r.directory, title: r.title, time: r.time)
    }

    func messages(sessionID: String) async throws -> [MessageWithParts] {
        try await get("/session/\(sessionID)/message", as: [MessageWithParts].self)
    }

    struct PromptBody: Encodable {
        struct TextPart: Encodable { let type = "text"; let text: String }
        struct Model: Encodable { let providerID: String; let modelID: String }
        let parts: [TextPart]
        let model: Model?
        let agent: String?
    }

    func promptAsync(sessionID: String, text: String, model: PromptBody.Model? = nil, agent: String? = nil) async throws {
        try await post("/session/\(sessionID)/prompt_async",
                       body: PromptBody(parts: [.init(text: text)], model: model, agent: agent))
    }

    func abort(sessionID: String) async throws {
        struct Empty: Encodable {}
        try await post("/session/\(sessionID)/abort", body: Empty())
    }

    func respondPermission(sessionID: String, permissionID: String, response: String) async throws {
        struct B: Encodable { let response: String }
        try await post("/session/\(sessionID)/permissions/\(permissionID)", body: B(response: response))
    }

    struct ProvidersResponse: Decodable {
        let providers: [Provider]
        let `default`: [String: String]
        struct Provider: Decodable {
            let id: String
            let models: [String: ModelInfo]
            struct ModelInfo: Decodable { let name: String }
        }
    }
    func providers() async throws -> ProvidersResponse {
        try await get("/config/providers", as: ProvidersResponse.self)
    }

    struct Agent: Decodable { let name: String; let hidden: Bool? }
    func agents() async throws -> [Agent] { try await get("/agent", as: [Agent].self) }

    struct Config: Decodable { let model: String? }
    func config() async throws -> Config { try await get("/config", as: Config.self) }

    // MARK: SSE

    func eventStream() -> AsyncThrowingStream<ServerEvent, Error> {
        let url = baseURL.appending(path: "/event")
        return AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: url)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: req)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).drop(while: { $0 == " " })
                        guard let data = payload.data(using: .utf8),
                              let event = Self.decodeEvent(data) else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func decodeEvent(_ data: Data) -> ServerEvent? {
        struct Envelope: Decodable { let type: String }
        guard let type = try? decoder.decode(Envelope.self, from: data).type else { return nil }
        struct Box<P: Decodable>: Decodable { let properties: P }
        func props<P: Decodable>(as _: P.Type) -> P? {
            do { return try decoder.decode(Box<P>.self, from: data).properties } catch { return nil }
        }
        switch type {
        case "message.updated":
            struct P: Decodable { let info: OCMessage }
            return props(as: P.self).map { .messageUpdated($0.info) }
        case "message.part.updated":
            struct P: Decodable { let part: Part }
            return props(as: P.self).map { .partUpdated($0.part) }
        case "session.status":
            struct P: Decodable { let sessionID: String; let status: S }
            struct S: Decodable { let type: String }
            return props(as: P.self).map { .sessionStatus(sessionID: $0.sessionID, status: $0.status.type) }
        case "session.idle":
            struct P: Decodable { let sessionID: String }
            return props(as: P.self).map { .sessionIdle(sessionID: $0.sessionID) }
        case "permission.updated":
            return props(as: Permission.self).map { .permissionAsked($0) }
        default:
            return .other(type)
        }
    }
}
