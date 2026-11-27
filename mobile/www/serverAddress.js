(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.TVMaestroServerAddress = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  const DEFAULT_PORT = "6790";

  function cleanAddress(value) {
    // The iOS URL keyboard inserts invisible direction marks. new URL() rejects those.
    return String(value || "")
      .replace(
        /[\u0000-\u001F\u007F\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\uFFFC\uFFFD]/g,
        "",
      )
      .replace(/[\uFF01-\uFF5E]/g, (ch) => String.fromCharCode(ch.charCodeAt(0) - 0xfee0))
      .replace(/[\u3002\uFF61\uFE52\u2024]/g, ".")
      .trim();
  }

  function isLocalHostname(hostname) {
    const host = String(hostname || "")
      .replace(/^\[|\]$/g, "")
      .toLowerCase();
    if (!host) return false;
    if (host === "localhost" || host === "::1" || host.endsWith(".local")) return true;
    if (/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    if (/^172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    if (/^fc[0-9a-f]{2}:/i.test(host) || /^fd[0-9a-f]{2}:/i.test(host) || /^fe80:/i.test(host)) {
      return true;
    }
    return false;
  }

  function parseServer(rawHost, rawPort) {
    let input = cleanAddress(rawHost);
    const typedPort = cleanAddress(rawPort);
    if (!input) {
      throw new Error("Enter the server address.");
    }
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(input)) {
      input = `http://${input}`;
    }
    let url;
    try {
      url = new URL(input);
    } catch {
      throw new Error("That address is not valid.");
    }
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      throw new Error("Use an http or https address.");
    }
    if (!url.hostname) {
      throw new Error("Enter the server address.");
    }
    let port = url.port;
    if (!port) {
      port = typedPort || DEFAULT_PORT;
    }
    if (!/^\d+$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
      throw new Error("Port must be between 1 and 65535.");
    }
    const local = isLocalHostname(url.hostname);
    if (url.protocol === "http:" && !local) {
      throw new Error("Use https for addresses outside your local network.");
    }
    const hostname = url.hostname.includes(":") ? `[${url.hostname}]` : url.hostname;
    const scheme = url.protocol.slice(0, -1);
    return {
      host: hostname,
      port,
      scheme,
      origin: `${url.protocol}//${hostname}:${port}`,
    };
  }

  return { DEFAULT_PORT, cleanAddress, isLocalHostname, parseServer };
});
