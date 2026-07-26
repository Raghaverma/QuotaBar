import Foundation

/// Builds `application/x-www-form-urlencoded` request bodies.
///
/// Neither string interpolation nor `URLComponents` is safe here. Interpolation
/// leaves `&` and `=` raw, so a token containing either silently truncates or
/// splits the body. `URLComponents` escapes those two but deliberately leaves `+`
/// alone — and a form decoder turns a literal `+` back into a space, corrupting the
/// value. OAuth refresh tokens and client secrets are base64-ish and routinely
/// contain `+`, `/` and `=`, so both bugs are reachable in normal use.
enum FormURLEncoding {
    /// Characters that may appear unescaped in a form body. Everything else —
    /// including `+`, `/`, `=`, `&` and space — is percent-encoded.
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    /// Encode `pairs` into a body string, sorted by key so the output is stable.
    static func body(_ pairs: [String: String]) -> String {
        pairs
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
