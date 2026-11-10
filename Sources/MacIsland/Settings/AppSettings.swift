import Foundation
import Observation

/// The one place settings live. Every key and default is defined here; nothing else touches UserDefaults.
///
/// Views and services read it (it is `@Observable`), and anything that must react to a change registers
/// `onFeatureChange`. New sections (appearance, ...) add their keys to `Keys` and `Defaults` below.
@MainActor
@Observable
final class AppSettings {
    enum Keys {
        static func featureEnabled(_ feature: FeatureFlag) -> String { "feature.\(feature.rawValue).enabled" }
        static let displaySelection = "appearance.display"
        static let expandTrigger = "appearance.expandTrigger"
        static let compactPreference = "appearance.compactPreference"
        static let accent = "appearance.accent"
        static let hapticsEnabled = "feel.haptics"
        static let playfulAnimations = "feel.playfulAnimations"
        static let chargingAnimation = "feel.chargingAnimation"
        static let swipeToSkip = "feel.swipeToSkip"
    }

    enum Defaults {
        /// Every feature is on out of the box.
        static let featureEnabled = true
        static let displaySelection = DisplaySelection.builtIn
        static let expandTrigger = ExpandTrigger.click
        static let compactPreference = CompactPreference.automatic
        static let accent = AccentOption.white
        static let hapticsEnabled = true
        static let playfulAnimations = true
        static let chargingAnimation = true
        static let swipeToSkip = true
    }

    private(set) var enabledFeatures: Set<FeatureFlag>
    private(set) var displaySelection: DisplaySelection
    private(set) var expandTrigger: ExpandTrigger
    private(set) var compactPreference: CompactPreference
    private(set) var accent: AccentOption
    private(set) var hapticsEnabled: Bool
    private(set) var playfulAnimationsEnabled: Bool
    private(set) var chargingAnimationEnabled: Bool
    private(set) var swipeToSkipEnabled: Bool

    /// Runtime status, never persisted: no display without a camera notch is connected, so the notch is
    /// hidden. Lives here so Settings can explain it.
    var isHiddenOnNotchedDisplay = false

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after a feature is switched on or off (not for the initial load).
    @ObservationIgnored var onFeatureChange: (@MainActor (FeatureFlag, Bool) -> Void)?
    /// Called after any appearance or feel setting changes, so the notch can re-apply what it owns
    /// (display, hover, ...). Views and the feature store simply read the observable values.
    @ObservationIgnored var onAppearanceChange: (@MainActor () -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map {
            (Keys.featureEnabled($0), Defaults.featureEnabled)
        }))
        defaults.register(defaults: [
            Keys.displaySelection: Defaults.displaySelection.rawValue,
            Keys.expandTrigger: Defaults.expandTrigger.rawValue,
            Keys.compactPreference: Defaults.compactPreference.rawValue,
            Keys.accent: Defaults.accent.rawValue,
            Keys.hapticsEnabled: Defaults.hapticsEnabled,
            Keys.playfulAnimations: Defaults.playfulAnimations,
            Keys.chargingAnimation: Defaults.chargingAnimation,
            Keys.swipeToSkip: Defaults.swipeToSkip,
        ])
        enabledFeatures = Set(FeatureFlag.allCases.filter { defaults.bool(forKey: Keys.featureEnabled($0)) })
        displaySelection = Self.read(DisplaySelection.self, Keys.displaySelection, Defaults.displaySelection, defaults)
        expandTrigger = Self.read(ExpandTrigger.self, Keys.expandTrigger, Defaults.expandTrigger, defaults)
        compactPreference = Self.read(CompactPreference.self, Keys.compactPreference, Defaults.compactPreference, defaults)
        accent = Self.read(AccentOption.self, Keys.accent, Defaults.accent, defaults)
        hapticsEnabled = defaults.bool(forKey: Keys.hapticsEnabled)
        playfulAnimationsEnabled = defaults.bool(forKey: Keys.playfulAnimations)
        chargingAnimationEnabled = defaults.bool(forKey: Keys.chargingAnimation)
        swipeToSkipEnabled = defaults.bool(forKey: Keys.swipeToSkip)
    }

    /// An unknown stored value (for example from a newer version) falls back to the default.
    private static func read<T: RawRepresentable>(_ type: T.Type, _ key: String, _ fallback: T, _ defaults: UserDefaults) -> T
    where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return fallback }
        return value
    }

    func setDisplaySelection(_ value: DisplaySelection) {
        guard value != displaySelection else { return }
        displaySelection = value
        defaults.set(value.rawValue, forKey: Keys.displaySelection)
        onAppearanceChange?()
    }

    func setExpandTrigger(_ value: ExpandTrigger) {
        guard value != expandTrigger else { return }
        expandTrigger = value
        defaults.set(value.rawValue, forKey: Keys.expandTrigger)
        onAppearanceChange?()
    }

    func setCompactPreference(_ value: CompactPreference) {
        guard value != compactPreference else { return }
        compactPreference = value
        defaults.set(value.rawValue, forKey: Keys.compactPreference)
        onAppearanceChange?()
    }

    func setAccent(_ value: AccentOption) {
        guard value != accent else { return }
        accent = value
        defaults.set(value.rawValue, forKey: Keys.accent)
        onAppearanceChange?()
    }

    func setHapticsEnabled(_ value: Bool) {
        guard value != hapticsEnabled else { return }
        hapticsEnabled = value
        defaults.set(value, forKey: Keys.hapticsEnabled)
        onAppearanceChange?()
    }

    func setPlayfulAnimationsEnabled(_ value: Bool) {
        guard value != playfulAnimationsEnabled else { return }
        playfulAnimationsEnabled = value
        defaults.set(value, forKey: Keys.playfulAnimations)
        onAppearanceChange?()
    }

    func setChargingAnimationEnabled(_ value: Bool) {
        guard value != chargingAnimationEnabled else { return }
        chargingAnimationEnabled = value
        defaults.set(value, forKey: Keys.chargingAnimation)
        onAppearanceChange?()
    }

    func setSwipeToSkipEnabled(_ value: Bool) {
        guard value != swipeToSkipEnabled else { return }
        swipeToSkipEnabled = value
        defaults.set(value, forKey: Keys.swipeToSkip)
        onAppearanceChange?()
    }

    /// Compact preferences that can be offered right now: automatic, plus pins whose feature is enabled.
    var availableCompactPreferences: [CompactPreference] {
        CompactPreference.allCases.filter { choice in
            guard let required = choice.requiredFeatures else { return true }
            return required.contains { isEnabled($0) }
        }
    }

    /// The stored pin, or automatic when that feature has since been turned off.
    var effectiveCompactPreference: CompactPreference {
        availableCompactPreferences.contains(compactPreference) ? compactPreference : .automatic
    }

    func isEnabled(_ feature: FeatureFlag) -> Bool { enabledFeatures.contains(feature) }

    func setEnabled(_ feature: FeatureFlag, _ enabled: Bool) {
        guard enabled != isEnabled(feature) else { return }
        defaults.set(enabled, forKey: Keys.featureEnabled(feature))
        if enabled { enabledFeatures.insert(feature) } else { enabledFeatures.remove(feature) }
        onFeatureChange?(feature, enabled)
    }
}
