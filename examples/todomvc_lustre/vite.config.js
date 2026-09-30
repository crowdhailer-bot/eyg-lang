import { defineConfig } from 'vite'
import gleam from 'vite-gleam'

// The hub and Ollama send no CORS headers, so the page reaches both through the dev server.
const hub = process.env.EYG_HUB ?? 'https://eyg.run'

export default defineConfig({
  plugins: [gleam()],
  server: {
    host: '127.0.0.1',
    port: 5192,
    strictPort: true,
    fs: { allow: ['../..'] },
    proxy: {
      '/packages': { target: hub, changeOrigin: true },
      '/modules': { target: hub, changeOrigin: true },
      '/api': 'http://localhost:11434',
    },
  },
})
