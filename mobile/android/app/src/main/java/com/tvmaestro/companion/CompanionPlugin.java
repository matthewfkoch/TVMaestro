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
    public void openGuide(PluginCall call) {
        boolean sample = Boolean.TRUE.equals(call.getBoolean("sample", false));
        WebView webView = getBridge().getWebView();
        webView.post(() -> {
            showGuide(sample);
            call.resolve();
        });
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
        if (isLocalAppUrl(url)) {
            return false;
        }
        // Keep the WebView on the bundled UI. API calls use fetch, not navigation.
        return true;
    }

    private boolean isLocalAppUrl(Uri url) {
        Uri local = Uri.parse(getBridge().getLocalUrl());
        String localHost = local.getHost();
        String urlHost = url.getHost();
        String localScheme = local.getScheme();
        String urlScheme = url.getScheme();
        if (localScheme != null && urlScheme != null && !localScheme.equalsIgnoreCase(urlScheme)) {
            if (!("http".equalsIgnoreCase(urlScheme) || "https".equalsIgnoreCase(urlScheme)
                    || "capacitor".equalsIgnoreCase(urlScheme) || "ionic".equalsIgnoreCase(urlScheme))) {
                return false;
            }
        }
        if (localHost != null && urlHost != null && localHost.equalsIgnoreCase(urlHost)) {
            return true;
        }
        if (urlHost != null) {
            String host = urlHost.toLowerCase();
            if ("localhost".equals(host) || "127.0.0.1".equals(host)) {
                return "http".equalsIgnoreCase(urlScheme)
                        || "https".equalsIgnoreCase(urlScheme)
                        || "capacitor".equalsIgnoreCase(urlScheme)
                        || "ionic".equalsIgnoreCase(urlScheme);
            }
        }
        return false;
    }

    private void showGuide(boolean sample) {
        String local = getBridge().getLocalUrl();
        if (local.endsWith("/")) {
            local = local.substring(0, local.length() - 1);
        }
        String target = sample ? local + "/guide/index.html?sample=1" : local + "/guide/index.html";
        WebView webView = getBridge().getWebView();
        webView.post(() -> webView.loadUrl(target));
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
