package com.tvmaestro.companion;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.webkit.WebView;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "Companion")
public class CompanionPlugin extends Plugin {

    @PluginMethod
    public void getServer(PluginCall call) {
        SharedPreferences prefs = prefs();
        JSObject result = new JSObject();
        result.put("host", prefs.getString("serverHost", null));
        result.put("port", prefs.getString("serverPort", null));
        result.put("scheme", prefs.getString("serverScheme", null));
        call.resolve(result);
    }

    @PluginMethod
    public void setServer(PluginCall call) {
        SharedPreferences.Editor editor = prefs().edit();
        if (call.getString("host") != null) {
            editor.putString("serverHost", call.getString("host"));
        }
        if (call.getString("port") != null) {
            editor.putString("serverPort", call.getString("port"));
        }
        if (call.getString("scheme") != null) {
            editor.putString("serverScheme", call.getString("scheme"));
        }
        editor.apply();
        call.resolve();
    }

    private SharedPreferences prefs() {
        return getContext().getSharedPreferences("tvmaestro", Context.MODE_PRIVATE);
    }

    @PluginMethod
    public void load(PluginCall call) {
        String url = call.getString("url");
        if (url == null || !(url.startsWith("http://") || url.startsWith("https://"))) {
            call.reject("A valid http(s) server URL is required");
            return;
        }
        WebView webView = getBridge().getWebView();
        webView.post(() -> webView.loadUrl(url));
        call.resolve();
    }

    @Override
    public Boolean shouldOverrideLoad(Uri url) {
        if (url == null || url.getScheme() == null) {
            return null;
        }
        String scheme = url.getScheme().toLowerCase();
        if ("tvmaestro".equals(scheme)) {
            showConnectForm();
            return true;
        }
        if ("http".equals(scheme) || "https".equals(scheme)) {
            return false;
        }
        return null;
    }

    private void showConnectForm() {
        String local = getBridge().getLocalUrl();
        if (local.endsWith("/")) {
            local = local.substring(0, local.length() - 1);
        }
        String target = local + "/index.html?edit=1";
        WebView webView = getBridge().getWebView();
        webView.post(() -> webView.loadUrl(target));
    }
}
