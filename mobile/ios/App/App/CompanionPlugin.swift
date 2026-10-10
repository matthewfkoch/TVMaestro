import Capacitor
import WebKit

@objc(CompanionPlugin)
public class CompanionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CompanionPlugin"
    public let jsName = "Companion"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "load", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getServer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setServer", returnType: CAPPluginReturnPromise)
    ]

    @objc func getServer(_ call: CAPPluginCall) {
        let defaults = UserDefaults.standard
        call.resolve([
            "host": defaults.string(forKey: "serverHost") as Any,
            "port": defaults.string(forKey: "serverPort") as Any,
            "scheme": defaults.string(forKey: "serverScheme") as Any
        ])
    }

    @objc func setServer(_ call: CAPPluginCall) {
        let defaults = UserDefaults.standard
        if let host = call.getString("host") {
            defaults.set(host, forKey: "serverHost")
        }
        if let port = call.getString("port") {
            defaults.set(port, forKey: "serverPort")
        }
        if let scheme = call.getString("scheme") {
            defaults.set(scheme, forKey: "serverScheme")
        }
        call.resolve()
    }

    @objc func load(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"),
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            call.reject("A valid http(s) server URL is required")
            return
        }
        DispatchQueue.main.async {
            self.webView?.load(URLRequest(url: url))
            call.resolve()
        }
    }

    public override func shouldOverrideLoad(_ navigationAction: WKNavigationAction) -> NSNumber? {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return nil
        }
        if scheme == "tvmaestro" {
            DispatchQueue.main.async { [weak self] in
                self?.showConnectForm()
            }
            return NSNumber(value: true)
        }
        if scheme == "http" || scheme == "https" {
            return NSNumber(value: false)
        }
        return nil
    }

    private func showConnectForm() {
        guard let webView = webView, let local = bridge?.config.localURL.absoluteString else {
            return
        }
        let base = local.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/index.html?edit=1") else {
            return
        }
        webView.load(URLRequest(url: url))
    }
}

class CompanionBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginInstance(CompanionPlugin())
    }
}
