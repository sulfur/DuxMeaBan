import fs from 'node:fs';
import process from 'node:process';
import { spawnSync } from 'node:child_process';
import { chromium } from 'playwright-core';

const NAVIGATION_TIMEOUT_MS = 25000;
const WAIT_AFTER_LOAD_MS = 1200;
const UNAVAILABLE_PATTERNS = [
  "sorry, this page isn't available",
  'sorry, this page isn\'t available',
  "questa pagina non e disponibile",
  'questa pagina non è disponibile',
  'profile non e disponibile',
  'profilo non disponibile',
  "profile isn't available",
  'profile isnt available',
  'page not found',
  'the link you followed may be broken',
  'il profilo sia stato rimosso',
  'the profile may have been removed',
  'user not found',
  'content unavailable'
];

function parseArgs(argv) {
  const args = {};

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];

    if (!token.startsWith('--')) {
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];

    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    index += 1;
  }

  return args;
}

function assertString(value, name) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing required value: ${name}`);
  }

  return value.trim();
}

function resolveCommandPath(command) {
  const result = spawnSync('which', [command], { encoding: 'utf8' });

  if (result.status !== 0) {
    return '';
  }

  return String(result.stdout || '')
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find(Boolean) || '';
}

function detectBrowserPath() {
  if (process.env.PLAYWRIGHT_BROWSER_PATH && fs.existsSync(process.env.PLAYWRIGHT_BROWSER_PATH)) {
    return process.env.PLAYWRIGHT_BROWSER_PATH;
  }

  const explicitCandidates = [
    '/usr/bin/google-chrome-stable',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/microsoft-edge',
    '/usr/bin/microsoft-edge-stable'
  ];

  for (const candidate of explicitCandidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  const commandCandidates = [
    'msedge',
    'chrome',
    'google-chrome-stable',
    'google-chrome',
    'chromium',
    'chromium-browser',
    'microsoft-edge',
    'microsoft-edge-stable'
  ];

  for (const command of commandCandidates) {
    const resolved = resolveCommandPath(command);

    if (resolved) {
      return resolved;
    }
  }

  throw new Error('No supported browser executable found for Playwright status checks.');
}

function normalizeText(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '');
}

function isBannedState({ statusCode, title, bodyText, finalUrl }) {
  const normalizedTitle = normalizeText(title);
  const normalizedBody = normalizeText(bodyText);
  const normalizedUrl = normalizeText(finalUrl);

  if (statusCode === 404 || statusCode === 410) {
    return true;
  }

  if (normalizedUrl.includes('/accounts/suspended/')) {
    return true;
  }

  return UNAVAILABLE_PATTERNS.some((pattern) => {
    const normalizedPattern = normalizeText(pattern);
    return normalizedTitle.includes(normalizedPattern) || normalizedBody.includes(normalizedPattern);
  });
}

async function main() {
  const args = parseArgs(process.argv);
  const profileUrl = assertString(args['profile-url'], 'profile-url');
  const browserPath = detectBrowserPath();

  const browser = await chromium.launch({
    headless: true,
    executablePath: browserPath
  });

  try {
    const context = await browser.newContext({
      viewport: { width: 1280, height: 1600 }
    });
    const page = await context.newPage();

    const response = await page.goto(profileUrl, {
      waitUntil: 'domcontentloaded',
      timeout: NAVIGATION_TIMEOUT_MS
    });

    await page.waitForTimeout(WAIT_AFTER_LOAD_MS);

    const title = await page.title().catch(() => '');
    const bodyText = await page.locator('body').innerText().catch(() => '');
    const finalUrl = page.url();
    const statusCode = response?.status?.() ?? 0;
    const accountStatus = isBannedState({ statusCode, title, bodyText, finalUrl }) ? 'Banned' : 'Pending';

    process.stdout.write(`${accountStatus}\n`);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
