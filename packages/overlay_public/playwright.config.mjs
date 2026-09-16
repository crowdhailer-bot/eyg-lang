import { defineConfig } from '@playwright/test';

// OVERLAY_PORT keeps tests clear of another server already using the dev port.
const port = process.env.OVERLAY_PORT ?? '5173';

export default defineConfig({
  testDir: './test/browser',
  timeout: 30_000,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    launchOptions: { executablePath: process.env.CHROMIUM_PATH },
  },
  webServer: {
    command: `bun --bun run dev -- --host 127.0.0.1 --port ${port} --strictPort`,
    // Wait for Vite to be ready rather than polling a URL,
    // a request made while the Gleam build is running can hang.
    wait: { stdout: /ready in/ },
    stdout: 'pipe',
    // The first start compiles every Gleam dependency.
    timeout: 300_000,
  },
});
