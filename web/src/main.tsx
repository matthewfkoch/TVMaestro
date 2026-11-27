import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";

const params = new URLSearchParams(window.location.search);
if (params.get("sample") === "1") {
  window.__TVMAESTRO_SAMPLE__ = true;
  sessionStorage.removeItem("tvmaestroApiOrigin");
} else {
  const origin = sessionStorage.getItem("tvmaestroApiOrigin");
  if (origin) {
    window.__TVMAESTRO_API_ORIGIN__ = origin;
  }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
