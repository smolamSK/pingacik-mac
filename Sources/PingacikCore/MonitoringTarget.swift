import Foundation

public struct MonitoringTarget: Equatable, Sendable {
    public var host: String
    public var interval: Int
    public var timeout: Int

    public init(host: String, interval: Int, timeout: Int) {
        self.host = host
        self.interval = interval
        self.timeout = timeout
    }

    public static func normalizedHost(_ input: String) -> String? {
        let host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, host.utf8.count <= 253 else { return nil }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            guard labels.count == 4, labels.allSatisfy({
                !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
                    && (Int($0).map { (0...255).contains($0) } ?? false)
            }) else { return nil }
        }
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return nil }
        return host
    }
}
