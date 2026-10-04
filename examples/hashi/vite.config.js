import { defineConfig } from 'vite'
import gleam from 'vite-gleam'

export default defineConfig({
  plugins: [gleam()],
  server: {
    host: '127.0.0.1',
    port: 5191,
    strictPort: true,
    fs: { allow: ['../..'] },
    // Ollama does not send CORS headers, so the page reaches it through the dev server.
    proxy: { '/api': 'http://localhost:11434' },
  },
})
