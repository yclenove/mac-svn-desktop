import Foundation

public enum MacSvnSettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general
    case dialogs
    case colours
    case network
    case externalPrograms
    case savedData
    case finder
    case revisionGraph
    case ai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .dialogs: "Dialogs"
        case .colours: "Colours"
        case .network: "Network"
        case .externalPrograms: "External Programs"
        case .savedData: "Saved Data"
        case .finder: "Finder"
        case .revisionGraph: "Revision Graph"
        case .ai: "AI"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .dialogs: "rectangle.on.rectangle"
        case .colours: "paintpalette"
        case .network: "network"
        case .externalPrograms: "terminal"
        case .savedData: "externaldrive"
        case .finder: "folder"
        case .revisionGraph: "point.3.connected.trianglepath.dotted"
        case .ai: "sparkles"
        }
    }
}
