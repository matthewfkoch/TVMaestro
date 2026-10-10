const DEFAULT_PORT = "6790";

const form = document.getElementById("form");
const hostInput = document.getElementById("host");
const portInput = document.getElementById("port");
const submitButton = document.getElementById("submit");
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

function parseServer(rawHost, rawPort) {
  let input = String(rawHost || "").trim();
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
    port = String(rawPort || "").trim() || DEFAULT_PORT;
  }
  if (!/^\d+$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
    throw new Error("Port must be between 1 and 65535.");
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

async function connect(server) {
  const { Companion } = plugins();
  setMessage(`Connecting to ${server.origin}…`, true);
  submitButton.disabled = true;
  try {
    await probe(server.origin);
    await Companion.setServer({ host: server.host, port: server.port, scheme: server.scheme });
    await Companion.load({ url: `${server.origin}/` });
  } catch (error) {
    submitButton.disabled = false;
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
