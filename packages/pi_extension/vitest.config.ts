// Run the tests with the vendored pi's test configuration, which resolves pi's packages to their source.
import { fileURLToPath } from "node:url"
import pi from "../../vendor/pi-mono/packages/coding-agent/vitest.config.ts"

const vendored = (path: string) => fileURLToPath(new URL(`../../vendor/pi-mono/${path}`, import.meta.url))

export default {
  ...pi,
  test: { ...pi.test, include: ["test/**/*.test.ts"], reporters: ["default"] },
  resolve: {
    ...pi.resolve,
    alias: [
      ...(pi.resolve?.alias as { find: RegExp; replacement: string }[]),
      { find: /^typebox$/, replacement: vendored("node_modules/typebox/build/index.mjs") },
    ],
  },
}
