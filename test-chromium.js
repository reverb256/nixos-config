const { chromium } = require("./node_modules/playwright-core");

(async () => {
  try {
    const browser = await chromium.launch({
      executablePath: "/run/current-system/sw/bin/chromium",
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    });
    const page = await browser.newPage();
    const response = await page.goto("http://localhost:5000/", {
      waitUntil: "domcontentloaded",
      timeout: 10000
    });
    console.log("Status:", response.status());
    console.log("Title:", await page.title());
    console.log("URL:", page.url());
    
    // Take a screenshot
    await page.screenshot({ path: "screenshot.png" });
    console.log("Screenshot saved to screenshot.png");
    
    await browser.close();
  } catch (err) {
    console.error("Error:", err.message);
    process.exit(1);
  }
})();
