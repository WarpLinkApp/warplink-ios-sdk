import Foundation

/// When this install of the app was made, read without any permission prompt.
///
/// The source is the creation date of the app container's `Documents` and
/// `Library` directories. The system makes both when it makes the container,
/// at install. An app update keeps the container, so the date survives
/// updates, and a delete and reinstall makes a new container, so the date
/// resets. Other dates are worse: the bundle's date moves on every update, and
/// the SDK's own files only date from the first launch with the SDK in the app,
/// which would make every upgrading user look new.
///
/// The newer of the two directories is used. A wrong date that is too old would
/// skip the check for a person who just installed, which costs their
/// attribution. A wrong date that is too new only costs one request.
///
/// Reading a file creation date is a required-reason API: `PrivacyInfo.xcprivacy`
/// declares `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`
/// (timestamps of files inside the app's own container). The date is compared
/// on the device and never sent.
enum InstallDate {

    /// Dates before the first iPhone are a broken file system, not an install.
    private static let earliestPlausible = Date(timeIntervalSince1970: 1_167_609_600)

    /// The install date of the running app, or nil where there is no app
    /// container (the macOS test host) or the dates cannot be read.
    static func ofRunningApp(fileManager: FileManager = .default) -> Date? {
        #if canImport(UIKit)
        let directories: [FileManager.SearchPathDirectory] = [.documentDirectory, .libraryDirectory]
        let urls = directories.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
        return newestCreation(of: urls)
        #else
        return nil
        #endif
    }

    /// The newest plausible creation date among `urls`. Nil when none has one.
    static func newestCreation(of urls: [URL]) -> Date? {
        urls
            .compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }
            .filter { $0 >= earliestPlausible }
            .max()
    }
}
