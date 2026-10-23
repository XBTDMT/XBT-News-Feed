import Foundation

struct WebSearchItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let url: String
    let source: String
}
