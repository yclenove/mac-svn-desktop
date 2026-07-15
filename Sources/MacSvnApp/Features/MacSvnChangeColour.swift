import SwiftUI
import MacSvnCore

extension ColorScheme {
    var svnAppearance: AppAppearance {
        self == .dark ? .dark : .light
    }
}

extension Color {
    init(svnHex: String) {
        let cleaned = svnHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(cleaned, radix: 16), cleaned.count == 6 else {
            self = .secondary
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

func svnChangeColour(
    palette: ChangeColourPalette,
    role: ChangeColourRole,
    colorScheme: ColorScheme
) -> Color {
    Color(svnHex: palette.hex(for: role, appearance: colorScheme.svnAppearance))
}
