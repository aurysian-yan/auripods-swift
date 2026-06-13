import Foundation

struct PairedDevice: Identifiable, Equatable {
    let id: String
    let displayName: String
    let modelIdentifier: String
    let lastConnectedAt: Date?
    let selectedImageName: String?
    let availableImageNames: [String]

    init(
        id: String,
        displayName: String,
        modelIdentifier: String,
        lastConnectedAt: Date?,
        selectedImageName: String?,
        availableImageNames: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.modelIdentifier = modelIdentifier
        self.lastConnectedAt = lastConnectedAt
        self.selectedImageName = selectedImageName
        self.availableImageNames = availableImageNames
    }

    init(state: EarbudsState) {
        let provider = DeviceImageProvider.shared
        let deviceId = provider.selectionKey(for: state)

        self.init(
            id: deviceId,
            displayName: state.deviceName,
            modelIdentifier: state.currentDevice?.address ?? state.deviceName,
            lastConnectedAt: state.currentDevice?.timestamp,
            selectedImageName: provider.selectedImageName(for: state),
            availableImageNames: provider.availableImageNames(for: state)
        )
    }

    var defaultImageName: String? {
        availableImageNames.first
    }

    var lastConnectedText: String {
        guard let lastConnectedAt else {
            return "最近连接：暂无记录"
        }

        return "最近连接：\(Self.dateFormatter.string(from: lastConnectedAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
