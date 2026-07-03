import SwiftUI

enum OmnipoTheme {
    static let brandRed = Color(red: 0.94, green: 0.16, blue: 0.21)
    static let deepBlack = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let deepRed = Color(red: 0.50, green: 0.09, blue: 0.12)
    static let redTint = Color(red: 0.94, green: 0.16, blue: 0.21).opacity(0.10)
    static let redWash = Color(red: 0.94, green: 0.16, blue: 0.21).opacity(0.055)
    static let infoCyan = Color(red: 0.08, green: 0.70, blue: 0.82)
    static let cardStroke = Color.primary.opacity(0.08)

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandRed, deepRed],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleBrandGradient: LinearGradient {
        LinearGradient(
            colors: [
                brandRed.opacity(0.14),
                deepBlack.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
