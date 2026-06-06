import Foundation

/// Evaluates the tiny expression language used by relay `extract` rules against a
/// decoded JSON tree. Supports dotted key-paths, string literals, and a small set
/// of functions: `add(a,b)`, `coalesce(a,b,...)`. This is what lets a non-programmer
/// onboard a new site by editing JSON.
enum RelayJSONExpressionEvaluator {
    /// A decoded JSON value tree we can resolve paths against.
    enum JSONValue: Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        var doubleValue: Double? {
            switch self {
            case .number(let n): return n
            case .string(let s): return Double(s)
            case .bool(let b): return b ? 1 : 0
            default: return nil
            }
        }
        var stringValue: String? {
            switch self {
            case .string(let s): return s
            case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
            case .bool(let b): return String(b)
            default: return nil
            }
        }
        var isNullOrMissing: Bool { self == .null }
    }

    /// Parse raw `Data` (JSON) into a `JSONValue` tree.
    static func parse(_ data: Data) throws -> JSONValue {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return convert(obj)
    }

    static func convert(_ any: Any) -> JSONValue {
        switch any {
        case let s as String: return .string(s)
        case let b as Bool where type(of: any) == type(of: true): return .bool(b)
        case let n as NSNumber:
            // Distinguish bool-backed NSNumber from numeric.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let dict as [String: Any]:
            return .object(dict.mapValues { convert($0) })
        case let arr as [Any]:
            return .array(arr.map { convert($0) })
        case is NSNull:
            return .null
        default:
            return .null
        }
    }

    /// Evaluate an expression string against the root JSON value.
    static func evaluate(_ expression: String, root: JSONValue) -> JSONValue {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        if expr.isEmpty { return .null }

        // String literal: "..."
        if expr.hasPrefix("\""), expr.hasSuffix("\""), expr.count >= 2 {
            let inner = String(expr.dropFirst().dropLast())
            return .string(inner)
        }
        // Numeric literal.
        if let n = Double(expr) { return .number(n) }

        // Function call: name(arg1,arg2,...)
        if let openParen = expr.firstIndex(of: "("), expr.hasSuffix(")") {
            let name = String(expr[expr.startIndex..<openParen])
            let argsString = String(expr[expr.index(after: openParen)..<expr.index(before: expr.endIndex)])
            let args = splitTopLevel(argsString)
            return evaluateFunction(name: name, args: args, root: root)
        }

        // Otherwise treat as a dotted key-path.
        return resolvePath(expr, root: root)
    }

    private static func evaluateFunction(name: String, args: [String], root: JSONValue) -> JSONValue {
        switch name {
        case "add":
            let sum = args.reduce(0.0) { acc, arg in
                acc + (evaluate(arg, root: root).doubleValue ?? 0)
            }
            return .number(sum)
        case "coalesce":
            for arg in args {
                let v = evaluate(arg, root: root)
                if !v.isNullOrMissing { return v }
            }
            return .null
        default:
            return .null
        }
    }

    /// Resolve "data.quota" style paths, supporting numeric array indices.
    static func resolvePath(_ path: String, root: JSONValue) -> JSONValue {
        var current = root
        for component in path.split(separator: ".") {
            switch current {
            case .object(let dict):
                guard let next = dict[String(component)] else { return .null }
                current = next
            case .array(let arr):
                guard let idx = Int(component), arr.indices.contains(idx) else { return .null }
                current = arr[idx]
            default:
                return .null
            }
        }
        return current
    }

    /// Split function args on top-level commas only (so nested calls survive).
    private static func splitTopLevel(_ s: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var inString = false
        var current = ""
        for ch in s {
            switch ch {
            case "\"": inString.toggle(); current.append(ch)
            case "(" where !inString: depth += 1; current.append(ch)
            case ")" where !inString: depth -= 1; current.append(ch)
            case "," where !inString && depth == 0:
                result.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            default: current.append(ch)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { result.append(trimmed) }
        return result
    }
}
