#if os(iOS)
import UIKit
#endif
import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var viewModel: EarbudsViewModel
#if DEBUG
    @ObservedObject var testDeviceStore: DebugTestDeviceStore
#endif
    @AppStorage(AuriBudsPreferenceKey.showsUnavailableDevices) private var showsUnavailableDevices = true
    @State private var priorityList: [String] = StatusBarPriority.load()

    private var devices: [PairedDevice] {
#if DEBUG
        return viewModel.availableDisplayDevices(testDevices: testDeviceStore.devices)
#else
        return viewModel.pairedDevices
#endif
    }

    var body: some View {
        Form {
            Section("设备") {
                ForEach(devices) { device in
                    DeviceSettingsRow(device: device)
                }
            }
            Section("侧边栏") {
                Toggle("显示不可连接设备", isOn: $showsUnavailableDevices)
            }
            Section("状态栏浮窗") {
                StatusBarPriorityView(
                    devices: devices,
                    priorityList: $priorityList
                )
            }
#if DEBUG
            Section("样例设备") {
                DebugTestDeviceManagerView(store: testDeviceStore)
            }
#endif
            Section("外观") {
                LabeledContent("主题", value: "跟随系统")
            }
            Section("关于") {
                AboutAuriBudsView()
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, -8)
    }
}

#if DEBUG
private struct DebugTestDeviceManagerView: View {
    @ObservedObject var store: DebugTestDeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.availableOptions.isEmpty {
                Text("暂无可添加设备")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("支持设备", selection: $store.selectedOptionId) {
                    ForEach(store.availableOptions) { option in
                        Text(option.pickerTitle)
                            .tag(option.id)
                    }
                }

                Button("添加") {
                    store.addSelectedDevice()
                }
                .disabled(store.selectedOptionId.isEmpty)
            }

            if !store.devices.isEmpty {
                Divider()

                ForEach(store.devices) { device in
                    HStack(spacing: 12) {
                        DeviceImageView(
                            imageName: device.imageName,
                            fallbackSystemName: device.fallbackSystemName,
                            size: CGSize(width: 36, height: 36)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(.headline)

                            Text(device.option.colorTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("移除") {
                            store.remove(device)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
#endif

private struct DeviceSettingsRow: View {
    let device: PairedDevice
    @State private var selectedImageName: String

    init(device: PairedDevice) {
        self.device = device
        _selectedImageName = State(initialValue: device.selectedImageName ?? device.defaultImageName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DeviceImageView(
                    imageName: selectedImageName.isEmpty ? device.defaultImageName : selectedImageName,
                    fallbackSystemName: device.fallbackSystemName,
                    size: CGSize(width: 44, height: 44)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.headline)

                    if device.isAppControllable {
                        Text(device.lastConnectedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LabeledContent("蓝牙地址", value: device.modelIdentifier)

            if device.availableImageNames.count > 1 {
                Picker("机身颜色", selection: $selectedImageName) {
                    ForEach(device.availableImageNames, id: \.self) { imageName in
                        Text(DeviceImageProvider.shared.displayTitle(for: imageName))
                            .tag(imageName)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedImageName) { _, imageName in
                    DeviceImageProvider.shared.setSelectedImageName(imageName, for: device.id)
                }
            } else if let imageName = device.defaultImageName {
                LabeledContent("机身颜色", value: DeviceImageProvider.shared.displayTitle(for: imageName))
            }
        }
        .padding(.vertical, 6)
    }
}

struct AboutAuriBudsView: View {
    private let appName = Bundle.main.displayName
    private let versionText = Bundle.main.versionDisplayText
    var body: some View {
        VStack(spacing: 18) {
            AppIconView(size: 96)
            VStack(spacing: 6) {
                Text(appName)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                Text(versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Divider()
                .padding(.vertical, 2)
            VStack(spacing: 6) {
                Text("Multi-brand earbuds control for macOS")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("© 2026 Aurysian Yan")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }
}

private struct AppIconView: View {
    let size: CGFloat
    var body: some View {
#if os(macOS)
        if let image = Bundle.main.bestAppIconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            fallbackIcon
        }
#else
        if let image = Bundle.main.bestAppIconImage {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            fallbackIcon
        }
#endif
    }

    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "earbuds")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "AuriBuds"
    }
    var versionDisplayText: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
        return "Version \(version) (\(build))"
    }
#if os(macOS)
    var bestAppIconImage: NSImage? {
        if let runtimeIcon = NSApp.applicationIconImage {
            return runtimeIcon
        }
        if let iconName = object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let iconImage = NSImage(named: iconName) {
            return iconImage
        }
        if let iconFile = object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let name = iconFile.replacingOccurrences(of: ".icns", with: "")
            if let iconImage = NSImage(named: name) {
                return iconImage
            }
        }
        return nil
    }
#else
    var bestAppIconImage: UIImage? {
        if let iconName = object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let iconImage = UIImage(named: iconName) {
            return iconImage
        }
        return nil
    }
#endif
}

private struct StatusBarPriorityView: View {
    let devices: [PairedDevice]
    @Binding var priorityList: [String]

    @State private var selectedToAdd: String = ""

    private var addableDevices: [PairedDevice] {
        devices.filter { device in
            !priorityList.contains(device.modelIdentifier)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !priorityList.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(priorityList.enumerated()), id: \.offset) { index, address in
                        HStack(spacing: 8) {
                            if let device = devices.first(where: { $0.modelIdentifier == address }) {
                                DeviceImageView(
                                    imageName: device.selectedImageName ?? device.defaultImageName,
                                    fallbackSystemName: device.fallbackSystemName,
                                    size: CGSize(width: 24, height: 24)
                                )

                                Text(device.displayName)
                                    .font(.callout)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "questionmark.circle")
                                    .frame(width: 24, height: 24)

                                Text(address)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                moveUp(index)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)

                            Button {
                                moveDown(index)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == priorityList.count - 1)

                            Button {
                                remove(index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if index < priorityList.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("未设置优先级")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            if !addableDevices.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 8) {
                    Picker("添加设备", selection: $selectedToAdd) {
                        Text("选择设备…").tag("")
                        ForEach(addableDevices) { device in
                            Text(device.displayName)
                                .tag(device.modelIdentifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button("添加") {
                        add()
                    }
                    .disabled(selectedToAdd.isEmpty)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
                .padding(.horizontal, 8)
            }
        }
        .onChange(of: priorityList) { _, newValue in
            StatusBarPriority.save(newValue)
        }
    }

    private func moveUp(_ index: Int) {
        guard index > 0 else { return }
        var list = priorityList
        list.swapAt(index, index - 1)
        priorityList = list
    }

    private func moveDown(_ index: Int) {
        guard index < priorityList.count - 1 else { return }
        var list = priorityList
        list.swapAt(index, index + 1)
        priorityList = list
    }

    private func remove(_ index: Int) {
        var list = priorityList
        list.remove(at: index)
        priorityList = list
    }

    private func add() {
        guard !selectedToAdd.isEmpty else { return }
        var list = priorityList
        list.append(selectedToAdd)
        priorityList = list
        selectedToAdd = ""
    }
}

private struct SettingsPagePreview: View {
    var body: some View {
        Group {
#if DEBUG
            SettingsPageView(
                viewModel: EarbudsViewModel(),
                testDeviceStore: DebugTestDeviceStore.shared
            )
#else
            SettingsPageView(viewModel: EarbudsViewModel())
#endif
        }
        .frame(width: 420, height: 640)
    }
}

#Preview("设置") {
    SettingsPagePreview()
}

#Preview {
    AboutAuriBudsView()
}
