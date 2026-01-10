#if canImport(SmartSpectraSwiftSDK)
// Real SDK is available, do nothing here.
#else
import Foundation

public class SmartSpectraSwiftSDK {
    public static let shared = SmartSpectraSwiftSDK()
    
    private init() {
        startUpdatingMetrics()
    }
    
    public func setApiKey(_ key: String) {
        // Stub: do nothing
    }
    
    public var metricsBuffer: MetricsBuffer {
        return _metricsBuffer
    }
    
    private var _metricsBuffer = MetricsBuffer()
    
    private var timer: Timer?
    
    private func startUpdatingMetrics() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
            self?.updateMetrics()
        })
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func updateMetrics() {
        _metricsBuffer.pulse.rate.last.value = Double.random(in: 60...100)
        _metricsBuffer.attention.score.last.value = Double.random(in: 0...1)
    }
    
    deinit {
        timer?.invalidate()
    }
    
    public class MetricsBuffer {
        public let pulse: Pulse
        public let attention: Attention
        
        public init() {
            pulse = Pulse()
            attention = Attention()
        }
        
        public class Pulse {
            public let rate: Rate
            
            public init() {
                rate = Rate()
            }
            
            public class Rate {
                public let last: Last
                
                public init() {
                    last = Last()
                }
                
                public class Last {
                    public var value: Double = 70
                    public init() {}
                }
            }
        }
        
        public class Attention {
            public let score: Score
            
            public init() {
                score = Score()
            }
            
            public class Score {
                public let last: Last
                
                public init() {
                    last = Last()
                }
                
                public class Last {
                    public var value: Double = 0.5
                    public init() {}
                }
            }
        }
    }
}
#endif
