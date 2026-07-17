const { chromium } = require("./node_modules/playwright-core");

(async () => {
  const browser = await chromium.launch({
    executablePath: "/run/current-system/sw/bin/chromium",
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });
  
  const page = await browser.newPage();
  await page.goto('http://localhost:5000/', { waitUntil: 'networkidle' });
  
  // Wait for products to load
  await page.waitForTimeout(2000);
  
  const images = await page.evaluate(() => {
    return Array.from(document.querySelectorAll('img')).map(img => ({
      src: img.src,
      alt: img.alt,
      loading: img.getAttribute('loading')
    }));
  });
  
  console.log('Images with lazy loading:', images.filter(i => i.loading === 'lazy').length, '/', images.length);
  images.forEach(img => {
    console.log(`  - ${img.loading || 'none'}: ${img.alt.substring(0, 30)}...`);
  });
  
  await browser.close();
})();
