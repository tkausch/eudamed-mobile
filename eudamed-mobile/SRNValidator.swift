import Foundation

struct SRNValidator {
    private static let pattern = #"^[A-Z]{2}-(IM|MF|AR|PR)-\d{9}$"#

    /// Returns `true` when `srn` is empty (no input to validate) or matches the SRN pattern.
    static func isValid(_ srn: String) -> Bool {
        let trimmed = srn.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
