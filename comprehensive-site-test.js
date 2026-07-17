const { chromium } = require("./node_modules/playwright-core");
const fs = require('fs');

const RESULTS = {
  url: 'http://localhost:5000',
  timestamp: new Date().toISOString(),
  summary: {},
  performance: {},
  content: {},
  links: [],
  images: [],
  forms: [],
  consoleLogs: [],
  networkRequests: [],
  accessibility: {},
  seo: {},
  issues: []
};

(async () => {
  console.log("🔍 Starting comprehensive site evaluation...\n");
  
  const browser = await chromium.launch({
    executablePath: "/run/current-system/sw/bin/chromium",
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });
  
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
  });
  
  const page = await context.newPage();
  
  // Capture console logs - store as plain objects
  page.on('console', msg => {
    RESULTS.consoleLogs.push({ type: msg.type(), text: msg.text() });
    if (msg.type() === 'error') {
      console.log(`⚠️  Console Error: ${msg.text()}`);
    }
  });
  
  // Capture network requests
  page.on('request', request => {
    RESULTS.networkRequests.push({
      url: request.url(),
      method: request.method(),
      resourceType: request.resourceType()
    });
  });
  
  // Capture responses with errors
  page.on('response', response => {
    if (response.status() >= 400) {
      RESULTS.issues.push({
        type: 'failed_request',
        url: response.url(),
        status: response.status()
      });
    }
  });
  
  // Navigate to site
  console.log("📡 Navigating to http://localhost:5000/");
  const startTime = Date.now();
  const response = await page.goto('http://localhost:5000/', {
    waitUntil: 'networkidle',
    timeout: 30000
  });
  const loadTime = Date.now() - startTime;
  
  RESULTS.summary.status = response.status();
  RESULTS.summary.loadTime = loadTime;
  console.log(`✅ Status: ${response.status()} | Load time: ${loadTime}ms`);
  
  // Get page info
  const title = await page.title();
  const url = page.url();
  RESULTS.content.title = title;
  RESULTS.content.url = url;
  console.log(`📄 Title: ${title}`);
  console.log(`🔗 URL: ${url}\n`);
  
  // Get ALL page data using page.evaluate to avoid strict mode issues
  console.log("🏷️  SEO & Meta Tags:");
  const pageData = await page.evaluate(() => {
    const metaTags = {};
    document.querySelectorAll('meta').forEach(m => {
      const name = m.getAttribute('name') || m.getAttribute('property');
      if (name) {
        if (!metaTags[name]) metaTags[name] = [];
        metaTags[name].push(m.getAttribute('content'));
      }
    });
    
    const descriptions = metaTags['description'] || [];
    
    return {
      metaTags,
      descriptions,
      canonical: document.querySelector('link[rel="canonical"]')?.getAttribute('href') || null,
      viewport: document.querySelector('meta[name="viewport"]')?.getAttribute('content') || null,
      charset: document.querySelector('meta[charset]')?.getAttribute('charset') || document.characterSet || null,
      lang: document.documentElement.lang || null,
      ogTitle: metaTags['og:title']?.[0] || null,
      ogDescription: metaTags['og:description']?.[0] || null,
      ogImage: metaTags['og:image']?.[0] || null,
      ogType: metaTags['og:type']?.[0] || null
    };
  });
  
  RESULTS.seo = pageData;
  
  // Check for duplicate descriptions
  if (pageData.descriptions.length > 1) {
    RESULTS.issues.push({
      type: 'seo',
      severity: 'warning',
      message: `Duplicate meta descriptions (${pageData.descriptions.length} found)`,
      details: pageData.descriptions
    });
    console.log(`   ⚠️  DUPLICATE meta descriptions (${pageData.descriptions.length} found)`);
    pageData.descriptions.forEach((d, i) => {
      console.log(`      ${i + 1}. ${d.substring(0, 80)}...`);
    });
  } else if (pageData.descriptions.length === 1) {
    console.log(`   ✅ Description: ${pageData.descriptions[0].substring(0, 100)}...`);
  } else {
    console.log(`   ❌ No meta description`);
    RESULTS.issues.push({
      type: 'seo',
      severity: 'error',
      message: 'Missing meta description'
    });
  }
  
  console.log(`   Viewport: ${pageData.viewport || '❌ Missing'}`);
  console.log(`   Charset: ${pageData.charset}`);
  console.log(`   Lang: ${pageData.lang || '❌ Missing'}`);
  console.log(`   Canonical: ${pageData.canonical || '⚠️  Not set'}`);
  console.log(`   Open Graph: ${pageData.ogTitle ? '✅' : '⚠️  ' + (pageData.ogType || 'not set')}`);
  
  // Check all headings
  console.log("\n📝 Headings Structure:");
  const headingData = await page.evaluate(() => {
    const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
    return Array.from(headings).map(h => ({
      tag: h.tagName,
      text: h.textContent?.trim() || ''
    }));
  });
  
  headingData.forEach(h => {
    const truncated = h.text.length > 60 ? h.text.substring(0, 60) + '...' : h.text;
    console.log(`   ${h.tag}: ${truncated}`);
  });
  RESULTS.content.headings = headingData;
  
  // Count heading levels
  const h1Count = headingData.filter(h => h.tag === 'H1').length;
  const h2Count = headingData.filter(h => h.tag === 'H2').length;
  const h3Count = headingData.filter(h => h.tag === 'H3').length;
  console.log(`   Structure: ${h1Count} H1, ${h2Count} H2, ${h3Count} H3`);
  
  if (h1Count === 0) {
    RESULTS.issues.push({ type: 'seo', severity: 'warning', message: 'No H1 tag found' });
  } else if (h1Count > 1) {
    RESULTS.issues.push({ type: 'seo', severity: 'warning', message: `Multiple H1 tags (${h1Count} found)` });
  }
  
  // Note the spacing issue in H1
  if (headingData.some(h => h.tag === 'H1' && h.text.includes('MeetsArtisan'))) {
    RESULTS.issues.push({ type: 'content', severity: 'minor', message: 'H1 has spacing issue: "MeetsArtisan" should be "Meets Artisan"' });
  }
  
  // Analyze links
  console.log("\n🔗 Link Analysis:");
  const linkData = await page.evaluate(() => {
    const links = Array.from(document.querySelectorAll('a'));
    return links.map(a => ({
      href: a.getAttribute('href'),
      text: a.textContent?.trim().substring(0, 50) || '',
      title: a.getAttribute('title') || null,
      target: a.getAttribute('target') || null
    }));
  });
  
  let internalLinks = 0;
  let externalLinks = 0;
  let emptyLinks = 0;
  let newWindowLinks = 0;
  
  linkData.forEach(link => {
    if (!link.href || link.href === '#' || link.href === 'javascript:void(0)') {
      emptyLinks++;
    } else if (link.href.startsWith('http')) {
      externalLinks++;
      if (link.target === '_blank') {
        newWindowLinks++;
      }
    } else {
      internalLinks++;
    }
    if (link.href && link.href.length < 200) {
      RESULTS.links.push(link);
    }
  });
  
  console.log(`   Total: ${linkData.length} | Internal: ${internalLinks} | External: ${externalLinks} | Empty/JS: ${emptyLinks}`);
  console.log(`   Links opening in new tab: ${newWindowLinks}`);
  RESULTS.content.linkStats = { total: linkData.length, internal: internalLinks, external: externalLinks, empty: emptyLinks, newTab: newWindowLinks };
  
  // Check for broken-looking internal links
  const brokenInternal = linkData.filter(l => l.href && !l.href.startsWith('http') && !l.href.startsWith('/') && !l.href.startsWith('#') && !l.href.startsWith('mailto:') && !l.href.startsWith('tel:'));
  if (brokenInternal.length > 0) {
    console.log(`   ⚠️  Potentially malformed internal links: ${brokenInternal.length}`);
    RESULTS.issues.push({
      type: 'link',
      severity: 'warning',
      message: `${brokenInternal.length} potentially malformed links`,
      examples: brokenInternal.slice(0, 3)
    });
  }
  
  // Analyze images
  console.log("\n🖼️  Image Analysis:");
  const imageData = await page.evaluate(() => {
    const images = Array.from(document.querySelectorAll('img'));
    return images.map(img => ({
      src: img.getAttribute('src'),
      alt: img.getAttribute('alt'),
      loading: img.getAttribute('loading'),
      width: img.width,
      height: img.height
    }));
  });
  
  let imagesWithAlt = 0;
  let imagesWithoutAlt = 0;
  let lazyImages = 0;
  let veryLargeImages = 0;
  
  imageData.forEach(img => {
    if (img.alt && img.alt.trim() !== '') {
      imagesWithAlt++;
    } else {
      imagesWithoutAlt++;
    }
    if (img.loading === 'lazy') lazyImages++;
    if (img.width > 1000 || img.height > 1000) veryLargeImages++;
    RESULTS.images.push(img);
  });
  
  console.log(`   Total: ${imageData.length} | With alt: ${imagesWithAlt} | Without alt: ${imagesWithoutAlt}`);
  console.log(`   Lazy loaded: ${lazyImages} | Large (>1000px): ${veryLargeImages}`);
  RESULTS.content.imageStats = { total: imageData.length, withAlt: imagesWithAlt, withoutAlt: imagesWithoutAlt, lazyLoaded: lazyImages, large: veryLargeImages };
  
  if (imagesWithoutAlt > 0) {
    RESULTS.issues.push({
      type: 'accessibility',
      severity: 'warning',
      message: `${imagesWithoutAlt} images missing alt text`
    });
  }
  
  if (lazyImages === 0 && imageData.length > 0) {
    RESULTS.issues.push({
      type: 'performance',
      severity: 'info',
      message: 'No images use lazy loading - consider adding loading="lazy"'
    });
  }
  
  // Analyze forms
  console.log("\n📋 Form Analysis:");
  const formData = await page.evaluate(() => {
    const forms = Array.from(document.querySelectorAll('form'));
    return forms.map(f => ({
      action: f.getAttribute('action'),
      method: f.getAttribute('method') || 'GET',
      inputCount: f.querySelectorAll('input, select, textarea').length,
      hasSubmit: f.querySelector('button[type="submit"], input[type="submit"]') !== null,
      id: f.id || f.className || null
    }));
  });
  
  formData.forEach(f => {
    console.log(`   ${f.method} → ${f.action || '(same page)'} (${f.inputCount} fields) ${f.hasSubmit ? '✅' : '⚠️  No submit'}`);
    if (!f.hasSubmit) {
      RESULTS.issues.push({
        type: 'form',
        severity: 'warning',
        message: 'Form without submit button',
        details: f
      });
    }
    RESULTS.forms.push(f);
  });
  
  console.log(`   Total forms: ${formData.length}`);
  
  // Performance metrics
  console.log("\n⚡ Performance Metrics:");
  const perfMetrics = await page.evaluate(() => {
    const navigation = performance.getEntriesByType('navigation')[0];
    const paints = performance.getEntriesByType('paint');
    const fcp = paints.find(p => p.name === 'first-contentful-paint')?.startTime || 0;
    const fp = paints.find(p => p.name === 'first-paint')?.startTime || 0;
    
    return {
      domContentLoaded: Math.round(navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart),
      loadComplete: Math.round(navigation.loadEventEnd - navigation.loadEventStart),
      domInteractive: Math.round(navigation.domInteractive - navigation.fetchStart),
      firstPaint: Math.round(fp),
      firstContentfulPaint: Math.round(fcp),
      transferSize: navigation.transferSize,
      encodedBodySize: navigation.encodedBodySize,
      decodedBodySize: navigation.decodedBodySize
    };
  });
  
  RESULTS.performance = perfMetrics;
  console.log(`   First Paint: ${perfMetrics.firstPaint}ms`);
  console.log(`   First Contentful Paint: ${perfMetrics.firstContentfulPaint}ms`);
  console.log(`   DOM Interactive: ${perfMetrics.domInteractive}ms`);
  console.log(`   DOM Content Loaded: ${perfMetrics.domContentLoaded}ms`);
  console.log(`   Load Complete: ${perfMetrics.loadComplete}ms`);
  console.log(`   Transfer: ${(perfMetrics.transferSize / 1024).toFixed(1)} KB`);
  
  // Performance grades
  const perfGrade = {
    fcp: perfMetrics.firstContentfulPaint < 1800 ? 'good' : perfMetrics.firstContentfulPaint < 3000 ? 'fair' : 'poor',
    lcp: perfMetrics.loadComplete < 2500 ? 'good' : perfMetrics.loadComplete < 4000 ? 'fair' : 'poor',
    size: perfMetrics.transferSize < 1000000 ? 'good' : perfMetrics.transferSize < 2500000 ? 'fair' : 'poor'
  };
  console.log(`   Grade: FCP=${perfGrade.fcp.toUpperCase()}, Size=${perfGrade.size.toUpperCase()}`);
  
  if (perfGrade.fcp === 'poor') {
    RESULTS.issues.push({
      type: 'performance',
      severity: 'warning',
      message: `FCP is ${perfMetrics.firstContentfulPaint}ms (target: <1800ms)`
    });
  }
  
  // Accessibility checks
  console.log("\n♿ Accessibility Checks:");
  const a11yChecks = await page.evaluate(() => {
    const getElements = (sel) => document.querySelectorAll(sel).length;
    return {
      skipLink: getElements('a[href^="#main"], a[href^="#content"], a[href^="#main-content"]') > 0,
      langAttribute: document.documentElement.lang !== null,
      ariaLabels: getElements('[aria-label], [aria-labelledby]'),
      mainLandmark: getElements('main, [role="main"]'),
      navLandmark: getElements('nav, [role="navigation"]'),
      footerLandmark: getElements('footer, [role="contentinfo"]'),
      headerLandmark: getElements('header, [role="banner"]'),
      buttonsWithoutLabel: Array.from(document.querySelectorAll('button:not([aria-label]):not([aria-labelledby])')).filter(b => !b.textContent?.trim()).length,
      imagesWithoutAlt: getElements('img:not([alt])'),
      linksWithoutText: Array.from(document.querySelectorAll('a')).filter(a => !a.textContent?.trim() && !a.getAttribute('aria-label')).length
    };
  });
  
  RESULTS.accessibility = a11yChecks;
  console.log(`   Skip link: ${a11yChecks.skipLink ? '✅' : '⚠️  Not found'}`);
  console.log(`   Lang attribute: ${a11yChecks.langAttribute ? '✅' : '❌ Missing'}`);
  console.log(`   ARIA labels: ${a11yChecks.ariaLabels}`);
  console.log(`   Landmarks: main=${a11yChecks.mainLandmark > 0 ? '✅' : '❌'} nav=${a11yChecks.navLandmark > 0 ? '✅' : '❌'} footer=${a11yChecks.footerLandmark > 0 ? '✅' : '❌'} header=${a11yChecks.headerLandmark > 0 ? '✅' : '❌'}`);
  console.log(`   Buttons without label: ${a11yChecks.buttonsWithoutLabel}`);
  console.log(`   Links without text: ${a11yChecks.linksWithoutText}`);
  
  if (a11yChecks.buttonsWithoutLabel > 0) {
    RESULTS.issues.push({
      type: 'accessibility',
      severity: 'error',
      message: `${a11yChecks.buttonsWithoutLabel} buttons without accessible labels`
    });
  }
  
  if (!a11yChecks.skipLink) {
    RESULTS.issues.push({
      type: 'accessibility',
      severity: 'info',
      message: 'Consider adding a skip navigation link for keyboard users'
    });
  }
  
  // Check for JavaScript errors
  const jsErrors = RESULTS.consoleLogs.filter(l => l.type === 'error');
  if (jsErrors.length > 0) {
    console.log(`\n❌ JavaScript Errors: ${jsErrors.length}`);
    jsErrors.forEach(e => console.log(`   - ${e.text}`));
    RESULTS.issues.push({
      type: 'javascript',
      severity: 'error',
      message: `${jsErrors.length} console errors`,
      details: jsErrors
    });
  } else {
    console.log(`\n✅ No JavaScript errors detected`);
  }
  
  // Check for warnings
  const jsWarnings = RESULTS.consoleLogs.filter(l => l.type === 'warning');
  if (jsWarnings.length > 0) {
    console.log(`⚠️  JavaScript Warnings: ${jsWarnings.length}`);
    jsWarnings.forEach(e => console.log(`   - ${e.text}`));
  }
  
  // Take screenshots
  console.log("\n📸 Capturing screenshots...");
  await page.screenshot({ path: 'screenshot-full.png', fullPage: true });
  await page.screenshot({ path: 'screenshot-viewport.png', fullPage: false });
  console.log("   ✅ Desktop screenshots saved");
  
  // Mobile viewport test
  console.log("\n📱 Testing mobile viewport (375x667)...");
  await page.setViewportSize({ width: 375, height: 667 });
  await page.screenshot({ path: 'screenshot-mobile.png' });
  console.log("   ✅ Mobile screenshot saved");
  
  // Check responsive behavior
  const mobileCheck = await page.evaluate(() => {
    return {
      mobileNavElements: document.querySelectorAll('[class*="menu" i], [class*="hamburger" i], button[aria-expanded*="menu" i]').length,
      hasMobileNav: document.querySelector('[class*="menu" i], [class*="hamburger" i]') !== null,
      overflowX: document.body.scrollWidth > window.innerWidth
    };
  });
  console.log(`   Mobile nav elements: ${mobileCheck.mobileNavElements}`);
  console.log(`   Horizontal overflow: ${mobileCheck.overflowX ? '❌ Yes' : '✅ No'}`);
  
  if (mobileCheck.overflowX) {
    RESULTS.issues.push({
      type: 'responsive',
      severity: 'warning',
      message: 'Horizontal overflow detected on mobile'
    });
  }
  
  // Color analysis
  console.log("\n🎨 Visual Analysis:");
  const visualAnalysis = await page.evaluate(() => {
    const body = getComputedStyle(document.body);
    const headings = getComputedStyle(document.querySelector('h1') || document.body);
    
    return {
      backgroundColor: body.backgroundColor,
      textColor: body.color,
      headingColor: headings.color,
      fontFamily: body.fontFamily,
      fontSize: body.fontSize,
      lineHeight: body.lineHeight
    };
  });
  
  RESULTS.content.visuals = visualAnalysis;
  console.log(`   Background: ${visualAnalysis.backgroundColor}`);
  console.log(`   Text: ${visualAnalysis.textColor}`);
  console.log(`   Font: ${visualAnalysis.fontFamily.split(',')[0]}`);
  console.log(`   Base size: ${visualAnalysis.fontSize}`);
  
  await browser.close();
  
  // Save results
  fs.writeFileSync('site-evaluation-results.json', JSON.stringify(RESULTS, null, 2));
  console.log("\n✅ Evaluation complete! Results saved to site-evaluation-results.json");
  
  // Final Summary
  console.log("\n" + "=".repeat(55));
  console.log("📊 EVALUATION SUMMARY");
  console.log("=".repeat(55));
  
  const checks = [
    { name: 'HTTP Status', pass: response.status() === 200, value: response.status() },
    { name: 'Load Time', pass: loadTime < 3000, value: `${loadTime}ms` },
    { name: 'Page Size', pass: perfMetrics.transferSize < 1500000, value: `${(perfMetrics.transferSize / 1024).toFixed(0)}KB` },
    { name: 'FCP', pass: perfMetrics.firstContentfulPaint < 2000, value: `${perfMetrics.firstContentfulPaint}ms` },
    { name: 'Meta Description', pass: pageData.descriptions.length === 1, value: pageData.descriptions.length },
    { name: 'H1 Tags', pass: h1Count === 1, value: h1Count },
    { name: 'Image Alt Text', pass: imagesWithoutAlt === 0, value: `${imagesWithAlt}/${imageData.length}` },
    { name: 'Lang Attribute', pass: a11yChecks.langAttribute, value: a11yChecks.langAttribute ? 'Yes' : 'No' },
    { name: 'Main Landmark', pass: a11yChecks.mainLandmark > 0, value: a11yChecks.mainLandmark },
    { name: 'JS Errors', pass: jsErrors.length === 0, value: jsErrors.length }
  ];
  
  checks.forEach(c => {
    const status = c.pass ? '✅' : '⚠️ ';
    console.log(`${status} ${c.name.padEnd(18)} ${c.value}`);
  });
  
  const passing = checks.filter(c => c.pass).length;
  const score = Math.round((passing / checks.length) * 100);
  
  console.log("\n" + "─".repeat(55));
  console.log(`🏆 Overall Score: ${score}/100 (${passing}/${checks.length} checks passing)`);
  console.log(`⚠️  Issues found: ${RESULTS.issues.length}`);
  
  if (RESULTS.issues.length > 0) {
    console.log("\n📋 Issues to address:");
    RESULTS.issues.forEach((issue, i) => {
      const icon = issue.severity === 'error' ? '❌' : issue.severity === 'warning' ? '⚠️  ' : '💡 ';
      console.log(`${icon} ${i + 1}. [${issue.type}] ${issue.message}`);
    });
  }
  
  console.log("\n" + "=".repeat(55));
  
})().catch(err => {
  console.error("❌ Fatal Error:", err.message);
  process.exit(1);
});
