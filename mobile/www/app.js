const DEFAULT_PORT = "6790";
const API_ORIGIN_KEY = "tvmaestroApiOrigin";

const form = document.getElementById("form");
const hostInput = document.getElementById("host");
const portInput = document.getElementById("port");
const submitButton = document.getElementById("submit");
const sampleButton = document.getElementById("sample");
const message = document.getElementById("message");

function setMessage(text, pending) {
  message.textContent = text;
  message.classList.toggle("pending", Boolean(pending));
}

function plugins() {
  const cap = window.Capacitor;
  if (!cap || typeof cap.nativePromise !== "function") {
    throw new Error("Open this screen in the TVMaestro app.");
  }
  const Companion = new Proxy(
    {},
    {
      get(_target, method) {
        return (options) => cap.nativePromise("Companion", String(method), options);
      },
    },
  );
  return { Companion };
}

function cleanAddress(value) {
  // The iOS URL keyboard inserts invisible direction marks. new URL() rejects those.
  return String(value || "")
    .replace(/[\u0000-\u001F\u007F\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\uFFFC\uFFFD]/g, "")
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

async function probe(origin) {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(`${origin}/api/status`, { signal: controller.signal });
    if (!res.ok) {
      throw new Error(`The server responded with ${res.status}.`);
    }
    let body;
    try {
      body = await res.json();
    } catch {
      throw new Error("That address is not a TVMaestro server.");
    }
    if (!body || typeof body.version !== "string") {
      throw new Error("That address is not a TVMaestro server.");
    }
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error("Could not reach the server.");
    }
    if (error instanceof Error && error.message.startsWith("The server")) {
      throw error;
    }
    if (error instanceof Error && error.message.startsWith("That address")) {
      throw error;
    }
    throw new Error("Could not reach the server.");
  } finally {
    window.clearTimeout(timer);
  }
}

async function openGuide(options) {
  const { Companion } = plugins();
  if (options.sample) {
    sessionStorage.removeItem(API_ORIGIN_KEY);
  } else {
    sessionStorage.setItem(API_ORIGIN_KEY, options.origin);
  }
  await Companion.openGuide({ sample: Boolean(options.sample) });
}

async function connect(server) {
  setMessage(`Connecting to ${server.origin}…`, true);
  submitButton.disabled = true;
  sampleButton.disabled = true;
  try {
    await probe(server.origin);
    const { Companion } = plugins();
    await Companion.setServer({ host: server.host, port: server.port, scheme: server.scheme });
    await openGuide({ sample: false, origin: server.origin });
  } catch (error) {
    submitButton.disabled = false;
    sampleButton.disabled = false;
    setMessage(error instanceof Error ? error.message : "Could not reach the server.");
  }
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  let server;
  try {
    server = parseServer(hostInput.value, portInput.value);
  } catch (error) {
    setMessage(error instanceof Error ? error.message : "That address is not valid.");
    return;
  }
  void connect(server);
});

sampleButton.addEventListener("click", () => {
  setMessage("Opening sample guide…", true);
  submitButton.disabled = true;
  sampleButton.disabled = true;
  void openGuide({ sample: true }).catch((error) => {
    submitButton.disabled = false;
    sampleButton.disabled = false;
    setMessage(error instanceof Error ? error.message : "Could not open the sample guide.");
  });
});

async function restore() {
  const editing = new URLSearchParams(window.location.search).get("edit") === "1";
  let saved = null;
  try {
    const { Companion } = plugins();
    const stored = await Companion.getServer();
    if (stored.host) {
      const storedScheme = stored.scheme === "https" ? "https" : "http";
      saved = {
        host: stored.host,
        port: stored.port || DEFAULT_PORT,
        scheme: storedScheme,
      };
      hostInput.value = storedScheme === "https" ? `https://${saved.host}` : saved.host;
      portInput.value = saved.port;
    }
  } catch (error) {
    setMessage(error instanceof Error ? error.message : "Could not read the saved server.");
    return;
  }

  if (saved && !editing) {
    await connect({
      host: saved.host,
      port: saved.port,
      scheme: saved.scheme,
      origin: `${saved.scheme}://${saved.host}:${saved.port}`,
    });
  }
}

void restore();
