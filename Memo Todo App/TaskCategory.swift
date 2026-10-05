import SwiftUI

enum CategoryColor: String, Codable, CaseIterable, Identifiable, Hashable {
    case orange, blue, purple, green, pink, teal, yellow, red, gray

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .orange: return Color(hex: 0xE59A41)
        case .blue: return Color(hex: 0x5182ED)
        case .purple: return Color(hex: 0x906FD6)
        case .green: return Color(hex: 0x5DB867)
        case .pink: return Color(hex: 0xE0679A)
        case .teal: return Color(hex: 0x4FB3BF)
        case .yellow: return Color(hex: 0xD8BC4A)
        case .red: return Color(hex: 0xE5605A)
        case .gray: return Color(hex: 0x909097)
        }
    }
}

struct TaskCategory: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var color: CategoryColor

    init(id: UUID = UUID(), name: String, color: CategoryColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    static let defaults: [TaskCategory] = [
        TaskCategory(name: "Now", color: .orange),
        TaskCategory(name: "Nxt", color: .blue),
        TaskCategory(name: "Ltr", color: .purple),
    ]
}
