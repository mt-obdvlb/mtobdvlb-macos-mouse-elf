import { defineConfig, devices } from "@playwright/test";

const localNoProxy = "localhost,127.0.0.1,::1";
process.env.NO_PROXY = [process.env.NO_PROXY, localNoProxy].filter(Boolean).join(",");
process.env.no_proxy = [process.env.no_proxy, localNoProxy].filter(Boolean).join(",");

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: "http://127.0.0.1:3100",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "pnpm dev --hostname 127.0.0.1 --port 3100",
    env: {
      NO_PROXY: localNoProxy,
      no_proxy: localNoProxy,
    },
    url: "http://127.0.0.1:3100",
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    {
      name: "desktop-chromium",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1280, height: 820 },
      },
    },
  ],
});
