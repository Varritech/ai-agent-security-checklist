const playwright = require('playwright');
const path = require('path');

async function render() {
  const browser = await playwright.chromium.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1200, height: 1200 });
  
  const htmlPath = path.join(__dirname, 'post.html');
  await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
  
  // Wait for fonts to load
  await page.waitForTimeout(2000);
  
  await page.screenshot({ 
    path: path.join(__dirname, 'post.png'),
    type: 'png',
    fullPage: true,
    deviceScaleFactor: 2
  });
  
  await browser.close();
  console.log('✅ Image rendered: post.png');
}

render().catch(console.error);
