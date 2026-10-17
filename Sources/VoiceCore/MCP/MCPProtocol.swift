import Foundation

public struct JSONRPCError: Error, Equatable, Sendable {
    public static let parse = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602

    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// One JSON-RPC 2.0 request, notification or response. A missing `id` means a
/// notification; `.null` is the id of an error reply to a line that could not be read.
public struct JSONRPCMessage: Equatable, Sendable {
    public var id: JSONValue?
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: JSONRPCError?

    public init(
        id: JSONValue? = nil, method: String? = nil, params: JSONValue? = nil,
        result: JSONValue? = nil, error: JSONRPCError? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }

    public static func parse(_ line: Data) -> Result<JSONRPCMessage, JSONRPCError> {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else {
            return .failure(JSONRPCError(code: JSONRPCError.parse, message: "Parse error."))
        }
        guard let object = value.objectValue else {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request."))
        }
        var message = JSONRPCMessage(id: object["id"], params: object["params"], result: object["result"])
        if let method = object["method"] {
            guard let name = method.stringValue else {
                return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request."))
            }
            message.method = name
        }
        if let error = object["error"] {
            message.error = JSONRPCError(
                code: error["code"]?.intValue ?? 0, message: error["message"]?.stringValue ?? "")
        }
        guard message.method != nil || message.result != nil || message.error != nil else {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request."))
        }
        return .success(message)
    }

    public var json: JSONValue {
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0")]
        if let id { object["id"] = id }
        if let method { object["method"] = .string(method) }
        if let params { object["params"] = params }
        if let result { object["result"] = result }
        if let error {
            object["error"] = .object(["code": .number(Double(error.code)), "message": .string(error.message)])
        }
        return .object(object)
    }

    public func encodedLine() -> Data { json.encodedLine() }
}

public enum MCPProtocol {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// The client's version when this server speaks it, otherwise the newest one.
    public static func negotiate(_ requested: String?) -> String {
        if let requested, supportedVersions.contains(requested) { return requested }
        return supportedVersions[0]
    }

    public static func initializeResult(version: String, appVersion: String) -> JSONValue {
        .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(["name": .string("bugvoice"), "version": .string(appVersion)]),
        ])
    }

    public static func toolResult(text: String, isError: Bool) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError),
        ])
    }
}
