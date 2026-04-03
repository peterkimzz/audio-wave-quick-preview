import Foundation

struct AudioDocument: Sendable {
    let url: URL
    let fileName: String
    let duration: Double
    let sampleRate: Double
    let samples: [Float]
}
