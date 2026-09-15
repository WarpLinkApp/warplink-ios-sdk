import Foundation

/// A source of link domains the host app declares locally, available before any
/// network call has answered.
///
/// It is a protocol so a test can supply a declaration without an app target:
/// under SwiftPM the "main" bundle is the test runner, whose Info.plist the SDK
/// does not own and cannot add keys to.
protocol LinkDomainDeclaring {
    func declaredLinkDomains() -> [String]
}

/// Reads the host app's `WarpLinkDomains` Info.plist declaration.
enum DeclaredLinkDomains {

    /// The Info.plist key a host app declares its link domains under. An array
    /// of strings, one host per entry.
    static let infoPlistKey = "WarpLinkDomains"

    /// Interpret whatever sits under `WarpLinkDomains`.
    ///
    /// A single comma-separated string is accepted alongside the documented
    /// array because Xcode's plist editor defaults a new row to type String, so
    /// that is the spelling a developer lands on by accident. It is also the
    /// only spelling the Android manifest allows, so a team shipping both
    /// platforms can keep one value. Anything else yields no domains rather
    /// than a crash: an Info.plist typo must not take the app down at launch.
    ///
    /// An array is filtered ENTRY BY ENTRY rather than cast whole. Xcode types
    /// each row independently, so one row left as Boolean or Number would make
    /// an `as? [String]` cast fail and discard every sibling with it. The
    /// developer would then see exactly the symptom this option exists to
    /// remove, with a plist that looks correct at a glance.
    static func parse(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        if let single = value as? String { return single.split(separator: ",").map(String.init) }
        return []
    }
}

extension Bundle: LinkDomainDeclaring {
    func declaredLinkDomains() -> [String] {
        DeclaredLinkDomains.parse(object(forInfoDictionaryKey: DeclaredLinkDomains.infoPlistKey))
    }
}
