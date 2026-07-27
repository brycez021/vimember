import SwiftData
import SwiftUI
import UIKit

@MainActor
final class VimemberAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        InterfaceOrientationPolicy.supportedOrientations(for: window)
    }
}

@MainActor
enum InterfaceOrientationPolicy {
    private static var landscapeEnabledWindows: Set<ObjectIdentifier> = []

    static func supportedOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let window else {
            return .portrait
        }

        return landscapeEnabledWindows.contains(ObjectIdentifier(window)) ? .allButUpsideDown : .portrait
    }

    static func setLandscapeEnabled(_ isEnabled: Bool, for window: UIWindow) {
        let windowID = ObjectIdentifier(window)
        let didChange: Bool

        if isEnabled {
            didChange = landscapeEnabledWindows.insert(windowID).inserted
        } else {
            didChange = landscapeEnabledWindows.remove(windowID) != nil
        }

        guard didChange else {
            return
        }

        let supportedOrientations = supportedOrientations(for: window)
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        guard let windowScene = window.windowScene else {
            return
        }

        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: supportedOrientations
        )
        windowScene.requestGeometryUpdate(preferences)
    }
}

struct InterfaceOrientationScope: UIViewRepresentable {
    let allowsLandscape: Bool

    func makeUIView(context: Context) -> InterfaceOrientationScopeView {
        InterfaceOrientationScopeView(allowsLandscape: allowsLandscape)
    }

    func updateUIView(_ uiView: InterfaceOrientationScopeView, context: Context) {
        uiView.setAllowsLandscape(allowsLandscape)
    }

    static func dismantleUIView(_ uiView: InterfaceOrientationScopeView, coordinator: Void) {
        uiView.deactivate()
    }
}

@MainActor
final class InterfaceOrientationScopeView: UIView {
    private weak var registeredWindow: UIWindow?
    private var allowsLandscape: Bool

    init(allowsLandscape: Bool) {
        self.allowsLandscape = allowsLandscape
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard registeredWindow !== window else {
            return
        }

        if let registeredWindow {
            InterfaceOrientationPolicy.setLandscapeEnabled(false, for: registeredWindow)
        }

        registeredWindow = window

        if let window {
            InterfaceOrientationPolicy.setLandscapeEnabled(allowsLandscape, for: window)
        }
    }

    func setAllowsLandscape(_ allowsLandscape: Bool) {
        guard self.allowsLandscape != allowsLandscape else {
            return
        }

        self.allowsLandscape = allowsLandscape

        if let registeredWindow {
            InterfaceOrientationPolicy.setLandscapeEnabled(allowsLandscape, for: registeredWindow)
        }
    }

    func deactivate() {
        if let registeredWindow {
            InterfaceOrientationPolicy.setLandscapeEnabled(false, for: registeredWindow)
        }

        registeredWindow = nil
    }
}

@main
struct VimemberApp: App {
    @UIApplicationDelegateAdaptor(VimemberAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [VideoDiaryRecord.self, VideoAlbumRecord.self])
    }
}
