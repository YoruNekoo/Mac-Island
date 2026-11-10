import SwiftUI

/// Settings sections. Add a case (and its view) to add a section, for example Appearance.
enum SettingsSection: CaseIterable, Identifiable {
    case general, features, appearance, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .features: "Features"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .features: "switch.2"
        case .about: "info.circle"
        }
    }
}

/// Native-styled settings content (tabs, grouped forms). Deliberately not styled like the black notch.
struct SettingsView: View {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginModel

    static let size = CGSize(width: 480, height: 700)

    var body: some View {
        TabView {
            ForEach(SettingsSection.allCases) { section in
                content(for: section)
                    .tabItem { Label(section.title, systemImage: section.symbolName) }
                    .tag(section)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder
    private func content(for section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettingsView(launchAtLogin: launchAtLogin)
        case .appearance: AppearanceSettingsView(settings: settings)
        case .features: FeaturesSettingsView(settings: settings)
        case .about: AboutSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isOn },
                    set: { launchAtLogin.setEnabled($0) }))
                switch launchAtLogin.state {
                case .requiresApproval:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Allow Mac Island in System Settings to finish turning this on.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open Login Items Settings…") { launchAtLogin.openLoginItemsSettings() }
                    }
                case .unavailable:
                    Text("macOS can't register this copy of the app. Move Mac Island to the Applications folder and try again.")
                        .font(.callout).foregroundStyle(.secondary)
                case .on, .off:
                    EmptyView()
                }
                if let message = launchAtLogin.errorMessage {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FeaturesSettingsView: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(FeatureFlag.allCases) { feature in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(feature) },
                        set: { settings.setEnabled(feature, $0) })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                            Text(feature.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("A feature that is turned off stops completely and never asks for permissions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text(AppInfo.name).font(.title2.weight(.semibold))
            Text("Version \(AppInfo.version) (\(AppInfo.build))").foregroundStyle(.secondary)
            Text("Made for MacBooks without a notch.")
            if let copyright = AppInfo.copyright {
                Text(copyright).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Name, version and build, read from the bundle.
enum AppInfo {
    static var name: String { string("CFBundleDisplayName") ?? string("CFBundleName") ?? "Mac Island" }
    static var version: String { string("CFBundleShortVersionString") ?? "development" }
    static var build: String { string("CFBundleVersion") ?? "0" }

    static var copyright: String? { string("NSHumanReadableCopyright") }

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
