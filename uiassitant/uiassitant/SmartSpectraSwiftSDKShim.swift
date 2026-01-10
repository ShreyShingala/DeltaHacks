import Foundation

#if canImport(SmartSpectraSwiftSDK)
// If the real SDK exists, do nothing here and let the real import be used elsewhere.
#else

// MARK: - SmartSpectraSwiftSDK Shim
// This shim provides the minimal surface used by AudioAssistant so the app can compile
// without the actual SmartSpectraSwiftSDK. Replace with the real SDK when available.

final class SmartSpectraSwiftSDK {
    static let shared = SmartSpectraSwiftSDK()

    // Minimal metrics buffer model matching usage in AudioAssistant
    struct MetricsBuffer {
        struct Sample { let value: Double }
        struct Pulse { let rate: [Sample] }
        struct Attention { let score: [Sample] }
        let pulse: Pulse
        let attention: Attention
    }

    // Expose an optional metricsBuffer property
    var metricsBuffer: MetricsBuffer? = nil

    private init() {}

    func setApiKey(_ key: String) {
        // No-op in shim. In the real SDK this would configure the client.
    }
}

#endif
