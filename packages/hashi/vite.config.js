import { defineConfig } from 'vite'
import gleam from 'vite-gleam'

export default defineConfig({
  plugins: [gleam()],
  server: {
    host: '0.0.0.0',
    port: 5174,
    proxy: {
      // Ollama Cloud does not allow browser CORS requests, so calls to it go
      // through the deployment's own origin. Mistral is called directly.
      //
      // HASHI_LLM points this somewhere else, which is how the recording is
      // made: a model that always says the same thing, so the video is the
      // same every time.
      '/api': {
        target: process.env.HASHI_LLM ?? 'https://ollama.com',
        changeOrigin: true,
      },
    },
    watch: {
      usePolling: true, // needed in Docker
    },
    fs: {
      // main.css imports the board's stylesheet from the cloned original
      // project, which is outside this directory.
      allow: ['..', '../../../hashi'],
    },
  },
})
