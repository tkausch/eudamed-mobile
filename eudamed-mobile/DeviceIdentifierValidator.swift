import Foundation

/// Validates a EUDAMED Device Identifier (DI) — used for both Primary DI and
/// Basic UDI-DI — against the three issuing-agency formats recognised by EU MDR:
///
/// - GS1:    14 numeric digits (GTIN-14)
/// - HIBCC:  '+' followed by ≥ 2 uppercase alphanumeric / '.', '-', '/' chars
/// - ICCBBA: '=' followed by ≥ 2 uppercase alphanumeric chars
struct DeviceIdentifierValidator {
    private static let pattern =
        #"^(\d{14}|\+[A-Z0-9/.\-]{2,}|=[A-Z0-9]{2,})$"#

    /// Returns `true` when `di` is empty (nothing to validate) or matches a
    /// recognised DI format.
    static func isValid(_ di: String) -> Bool {
        let trimmed = di.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
