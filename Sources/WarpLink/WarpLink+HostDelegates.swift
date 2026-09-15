#if canImport(UIKit)
import UIKit

/// Drop-in `UIApplicationDelegate` that forwards Universal Links to WarpLink.
///
/// Use it directly with `@UIApplicationMain`, subclass it, or just copy the two
/// forwarding calls into your own delegate. No method swizzling is performed.
///
/// ```swift
/// @main
/// class AppDelegate: WarpLinkAppDelegate {
///     func application(
///         _ application: UIApplication,
///         didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
///     ) -> Bool {
///         WarpLink.configure(apiKey: "wl_live_...", options: WarpLinkOptions(onLink: route))
///         return true
///     }
/// }
/// ```
open class WarpLinkAppDelegate: UIResponder, UIApplicationDelegate {
    open func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        WarpLink.continue(userActivity)
    }

    open func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        WarpLink.open(url)
    }
}

/// Drop-in `UIWindowSceneDelegate` that forwards Universal Links to WarpLink,
/// covering cold launch (`willConnectTo`), warm continue, and URL contexts.
open class WarpLinkSceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?

    open func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        connectionOptions.userActivities.forEach { WarpLink.continue($0) }
        connectionOptions.urlContexts.forEach { WarpLink.open($0.url) }
    }

    open func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        WarpLink.continue(userActivity)
    }

    open func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { WarpLink.open($0.url) }
    }
}
#endif
