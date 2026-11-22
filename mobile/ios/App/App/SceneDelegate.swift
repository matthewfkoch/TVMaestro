import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        let root = CompanionBridgeViewController()
        window?.rootViewController = root
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)

        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Self.handleCompanionURL(url, root: root)
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
        guard let url = URLContexts.first?.url,
              let root = window?.rootViewController as? CompanionBridgeViewController else {
            return
        }
        Self.handleCompanionURL(url, root: root)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    private static func handleCompanionURL(_ url: URL, root: CompanionBridgeViewController) {
        guard url.scheme?.lowercased() == "tvmaestro" else { return }
        let host = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        if host == "sample" {
            root.openSampleGuide()
        } else if host == "settings" {
            root.openSampleSettings()
        } else if host == "servers" || host == "connect" {
            root.openConnectForm()
        }
    }
}
