import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:6790",
    },
  },
  build: {
    // Preserve the browser support of the Vite 6 production build.
    target: ["es2020", "edge88", "firefox78", "chrome87", "safari14"],
    outDir: "dist",
    emptyOutDir: true,
  },
});
