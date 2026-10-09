import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case hand = "Hand"
    case textSelection = "Text Select"
    case snapshot = "Snapshot"
    case highlight = "Highlight"
    case underline = "Underline"
    case freehand = "Freehand"
    case distance = "Distance"
    case perimeter = "Perimeter"
    case area = "Area"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .hand: "hand.raised"
        case .textSelection: "text.cursor"
        case .snapshot: "viewfinder"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .freehand: "pencil.tip.crop.circle"
        case .distance: "ruler"
        case .perimeter: "point.topleft.down.to.point.bottomright.curvepath"
        case .area: "square.dashed"
        }
    }

    var isMeasurement: Bool { self == .distance || self == .perimeter || self == .area }
}

enum RibbonTab: String, CaseIterable, Identifiable {
    case home = "Home", view = "View", comment = "Comment", measurement = "Measurement", pages = "Pages", tools = "Tools"
    var id: String { rawValue }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case thumbnails = "Thumbnails", bookmarks = "Bookmarks", annotations = "Annotations", attachments = "Attachments", layers = "Layers"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .bookmarks: "bookmark"
        case .annotations: "text.bubble"
        case .attachments: "paperclip"
        case .layers: "square.3.layers.3d"
        }
    }
}
