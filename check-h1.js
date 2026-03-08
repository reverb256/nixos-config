const { chromium } = require("./node_modules/playwright-core");

(async () => {
  const browser = await chromium.launch({
    executablePath: "/run/current-system/sw/bin/chromium",
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });
  
  const page = await browser.newPage();
  await page.goto('http://localhost:5000/', { waitUntil: 'networkidle' });
  
  const h1Text = await page.locator('h1').textContent();
  console.log('H1 Text:', h1Text);
  
  const h1HTML = await page.locator('h1').innerHTML();
  console.log('H1 HTML:', h1HTML.substring(0, 300));
  
  await browser.close();
})();
