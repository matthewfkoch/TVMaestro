const { DEFAULT_PORT, parseServer } = window.TVMaestroServerAddress;
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
