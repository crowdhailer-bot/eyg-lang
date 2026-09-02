import { defineConfig } from 'vite'
import gleam from 'vite-gleam'

// The hub the page resolves contexts and packages from. Set EYG_HUB to point at
// a hub running locally.
const hub = process.env.EYG_HUB ?? 'https://eyg.run'

export default defineConfig({
  base: '/overlay/',
  plugins: [gleam()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      '/api': {
        target: 'https://ollama.com',
        changeOrigin: true,
      },
      '/guides': {
        target: 'https://eyg.run',
        changeOrigin: true,
      },
      '/modules': {
        target: hub,
        changeOrigin: true,
      },
      '/packages': {
        target: hub,
        changeOrigin: true,
      },
    },
    watch: {
      usePolling: true, // needed in Docker
    },
  },
})
