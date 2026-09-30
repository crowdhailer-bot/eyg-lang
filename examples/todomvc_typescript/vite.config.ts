import { defineConfig } from "vite";

// The hub and Ollama send no CORS headers, so the page reaches both through the dev server.
const hub = process.env.EYG_HUB ?? "https://eyg.run";

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: 5193,
    strictPort: true,
    fs: { allow: ["../.."] },
    proxy: {
      "/packages": { target: hub, changeOrigin: true },
      "/modules": { target: hub, changeOrigin: true },
      "/api": "http://localhost:11434",
    },
  },
});
