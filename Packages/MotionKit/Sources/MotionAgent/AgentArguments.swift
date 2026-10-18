import Foundation
import MotionModel

/// A tool's arguments, read leniently (a number may come as a string, an
/// id list as one id) and refused plainly when something needed is
/// missing or wrong.
struct Arguments {
    let value: JSONValue

    init(_ value: JSONValue) { self.value = value }

    subscript(key: String) -> JSONValue? {
        guard let v = value[key], !v.isNull else { return nil }
        return v
    }

    func has(_ key: String) -> Bool { self[key] != nil }

    func string(_ key: String) -> String? {
        switch self[key] {
        case .string(let s)?: return s
        case .number(let n)?: return n.rounded() == n ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    func number(_ key: String) throws -> Double? {
        switch self[key] {
        case nil: return nil
        case .number(let n)?:
            guard n.isFinite else { throw AgentError("\(key) must be a finite number") }
            return n
        case .string(let s)?:
            guard let n = Double(s.trimmingCharacters(in: .whitespaces)), n.isFinite else {
                throw AgentError("\(key) must be a number, not \"\(s)\"")
            }
            return n
        default: throw AgentError("\(key) must be a number")
        }
    }

    func int(_ key: String) throws -> Int? {
        try number(key).map { Int(saturating: $0.rounded()) }
    }

    func bool(_ key: String) throws -> Bool? {
        switch self[key] {
        case nil: return nil
        case .bool(let b)?: return b
        case .string(let s)? where ["true", "yes", "on"].contains(s.lowercased()): return true
        case .string(let s)? where ["false", "no", "off"].contains(s.lowercased()): return false
        default: throw AgentError("\(key) must be true or false")
        }
    }

    func id(_ key: String) throws -> UUID? {
        guard let s = string(key) else { return nil }
        guard let id = UUID(uuidString: s) else { throw AgentError("\(key) is not an id: \(s)") }
        return id
    }

    func requiredID(_ key: String) throws -> UUID {
        guard let id = try id(key) else { throw AgentError("\(key) is needed") }
        return id
    }

    func ids(_ key: String) throws -> [UUID] {
        let items: [JSONValue]
        switch self[key] {
        case nil: return []
        case .array(let a)?: items = a
        case let one?: items = [one]
        }
        return try items.map {
            guard let s = $0.string, let id = UUID(uuidString: s) else { throw AgentError("\(key) holds something that is not an id: \($0.text(pretty: false))") }
            return id
        }
    }

    func strings(_ key: String) -> [String] {
        switch self[key] {
        case .array(let a)?: return a.compactMap(\.string)
        case .string(let s)?: return [s]
        default: return []
        }
    }

    func color(_ key: String) throws -> RGBA? {
        guard let v = self[key] else { return nil }
        if let color = Self.color(v) { return color }
        throw AgentError("\(key) must be a hex colour such as #217FD8 or #217FD880")
    }

    /// `#RRGGBB`, `#RRGGBBAA`, Figma's short forms, or `{r, g, b, a}` from 0 to 1.
    static func color(_ v: JSONValue) -> RGBA? {
        if let s = v.string { return RGBA(typed: s) }
        if let o = v.object, let r = o["r"]?.number, let g = o["g"]?.number, let b = o["b"]?.number {
            return RGBA(r, g, b, o["a"]?.number ?? 1)
        }
        return nil
    }

    /// Objects in a list, as `updates` are.
    func objects(_ key: String) throws -> [Arguments] {
        switch self[key] {
        case nil: return []
        case .array(let a)?:
            return try a.map {
                guard case .object = $0 else { throw AgentError("each of \(key) must be an object") }
                return Arguments($0)
            }
        case let one? where one.object != nil: return [Arguments(one)]
        default: throw AgentError("\(key) must be a list of objects")
        }
    }
}

extension RGBA {
    /// `#RRGGBB`, or `#RRGGBBAA` when not opaque.
    var agentHex: String {
        func byte(_ v: Double) -> String { String(format: "%02X", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#" + byte(r) + byte(g) + byte(b) + (a < 0.999 ? byte(a) : "")
    }
}
