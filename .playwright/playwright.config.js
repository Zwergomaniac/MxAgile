const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests',
  timeout: 30000,
  use: {
    channel: 'chrome',   // uses installed system Chrome — no separate download needed
    headless: true,
    locale: 'de-DE',
  },
  projects: [
    { name: 'desktop-1440', use: { viewport: { width: 1440, height: 900  } } },
    { name: 'desktop-1920', use: { viewport: { width: 1920, height: 1080 } } },
    { name: 'tablet',       use: { viewport: { width: 768,  height: 1024 } } },
    { name: 'phone',        use: { viewport: { width: 390,  height: 844  } } },
  ],
});
