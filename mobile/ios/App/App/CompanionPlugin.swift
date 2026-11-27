import Capacitor
import WebKit

@objc(CompanionPlugin)
public class CompanionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CompanionPlugin"
    public let jsName = "Companion"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "openGuide", returnType: CAPPluginReturnPromise),
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

    @objc func openGuide(_ call: CAPPluginCall) {
        let sample = call.getBool("sample") ?? false
        DispatchQueue.main.async {
            self.showGuide(sample: sample)
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
        if isLocalAppURL(url) {
            return NSNumber(value: false)
        }
        // Keep the WebView on the bundled UI. API calls use fetch, not navigation.
        return NSNumber(value: true)
    }

    private func isLocalAppURL(_ url: URL) -> Bool {
        guard let local = bridge?.config.localURL else {
            return false
        }
        let localHost = local.host?.lowercased()
        let urlHost = url.host?.lowercased()
        let localScheme = local.scheme?.lowercased()
        let urlScheme = url.scheme?.lowercased()
        if localScheme != nil, urlScheme != localScheme {
            return false
        }
        if let localHost, let urlHost, urlHost == localHost {
            return true
        }
        // Capacitor may serve as capacitor://localhost or http://localhost.
        if urlHost == "localhost" || urlHost == "127.0.0.1" {
            return urlScheme == "capacitor" || urlScheme == "http" || urlScheme == "ionic"
        }
        return false
    }

    func showGuidePublic(sample: Bool) {
        showGuide(sample: sample)
    }

    func showConnectFormPublic() {
        showConnectForm()
    }

    private func showGuide(sample: Bool) {
        guard let webView = webView, let local = bridge?.config.localURL.absoluteString else {
            return
        }
        let base = local.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = sample ? "/guide/index.html?sample=1" : "/guide/index.html"
        guard let url = URL(string: base + path) else {
            return
        }
        webView.load(URLRequest(url: url))
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
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--sample-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openSampleSettings()
            }
        } else if args.contains("--sample") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openSampleGuide()
            }
        }
    }

    func openSampleGuide() {
        guard let plugin = bridge?.plugin(withName: "Companion") as? CompanionPlugin else {
            loadLocalPath("/guide/index.html?sample=1")
            return
        }
        plugin.showGuidePublic(sample: true)
    }

    func openSampleSettings() {
        openSampleGuide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.webView?.evaluateJavaScript(
                """
                (function () {
                  var buttons = document.querySelectorAll('button');
                  for (var i = 0; i < buttons.length; i++) {
                    if ((buttons[i].textContent || '').trim() === 'Settings') {
                      buttons[i].click();
                      return true;
                    }
                  }
                  return false;
                })();
                """,
                completionHandler: nil
            )
        }
    }

    func openConnectForm() {
        guard let plugin = bridge?.plugin(withName: "Companion") as? CompanionPlugin else {
            loadLocalPath("/index.html?edit=1")
            return
        }
        plugin.showConnectFormPublic()
    }

    private func loadLocalPath(_ path: String) {
        guard let local = bridge?.config.localURL.absoluteString else { return }
        let base = local.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { return }
        webView?.load(URLRequest(url: url))
    }
}
