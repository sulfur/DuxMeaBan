import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
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

function normalizeOptionalString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function resolveCommandPath(command) {
  const resolver = process.platform === 'win32' ? 'where.exe' : 'which';
  const result = spawnSync(resolver, [command], { encoding: 'utf8' });

  if (result.status !== 0) {
    return '';
  }

  return String(result.stdout || '')
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find(Boolean) || '';
}

function browserCandidates() {
  if (process.platform === 'win32') {
    const localAppData = process.env.LOCALAPPDATA || '';

    return [
      'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
      'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
      'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
      localAppData ? path.join(localAppData, 'Google', 'Chrome', 'Application', 'chrome.exe') : '',
      localAppData ? path.join(localAppData, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : ''
    ].filter(Boolean);
  }

  return [
    '/usr/bin/google-chrome-stable',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/microsoft-edge',
    '/usr/bin/microsoft-edge-stable'
  ];
}

function detectBrowserPath() {
  if (process.env.PLAYWRIGHT_BROWSER_PATH && fs.existsSync(process.env.PLAYWRIGHT_BROWSER_PATH)) {
    return process.env.PLAYWRIGHT_BROWSER_PATH;
  }

  for (const candidate of browserCandidates()) {
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

  return '';
}

function parseTargetsJson(rawValue) {
  const raw = normalizeOptionalString(rawValue);

  if (!raw) {
    return [];
  }

  let parsed = [];

  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }

  if (!Array.isArray(parsed)) {
    return [];
  }

  return parsed
    .map((target) => ({
      id: normalizeOptionalString(target?.id),
      kind: normalizeOptionalString(target?.kind) || 'profile',
      label: normalizeOptionalString(target?.label),
      url: normalizeOptionalString(target?.url)
    }))
    .filter((target) => target.url.length > 0);
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

function nowLocalTimestamp() {
  const pad = (value) => String(value).padStart(2, '0');
  const now = new Date();

  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
}

async function checkTargetStatusWithBrowser(context, target) {
  const page = await context.newPage();

  try {
    const response = await page.goto(target.url, {
      waitUntil: 'domcontentloaded',
      timeout: NAVIGATION_TIMEOUT_MS
    });

    await page.waitForTimeout(WAIT_AFTER_LOAD_MS);

    const title = await page.title().catch(() => '');
    const bodyText = await page.locator('body').innerText().catch(() => '');
    const finalUrl = page.url();
    const statusCode = response?.status?.() ?? 0;
    const accountStatus = isBannedState({ statusCode, title, bodyText, finalUrl }) ? 'Banned' : 'Active';

    return {
      id: target.id,
      kind: target.kind,
      label: target.label,
      url: target.url,
      status: accountStatus,
      checkedAtLocal: nowLocalTimestamp()
    };
  } catch (error) {
    return {
      id: target.id,
      kind: target.kind,
      label: target.label,
      url: target.url,
      status: 'Unreachable',
      checkedAtLocal: nowLocalTimestamp(),
      error: error instanceof Error ? error.message : String(error)
    };
  } finally {
    await page.close().catch(() => {});
  }
}

function extractHtmlTitle(html) {
  const match = String(html || '').match(/<title[^>]*>([\s\S]*?)<\/title>/i);

  if (!match) {
    return '';
  }

  return String(match[1] || '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function checkTargetStatusWithFetch(target) {
  try {
    const response = await fetch(target.url, {
      method: 'GET',
      redirect: 'follow',
      headers: {
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      }
    });
    const bodyText = await response.text().catch(() => '');
    const title = extractHtmlTitle(bodyText);
    const finalUrl = response.url || target.url;
    const statusCode = response.status || 0;
    const accountStatus = isBannedState({ statusCode, title, bodyText, finalUrl }) ? 'Banned' : 'Active';

    return {
      id: target.id,
      kind: target.kind,
      label: target.label,
      url: target.url,
      status: accountStatus,
      checkedAtLocal: nowLocalTimestamp()
    };
  } catch (error) {
    return {
      id: target.id,
      kind: target.kind,
      label: target.label,
      url: target.url,
      status: 'Unreachable',
      checkedAtLocal: nowLocalTimestamp(),
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

export async function checkTargets(targets) {
  const browserPath = detectBrowserPath();

  if (!browserPath) {
    return Promise.all(targets.map((target) => checkTargetStatusWithFetch(target)));
  }

  let browser = null;

  try {
    browser = await chromium.launch({
      headless: true,
      executablePath: browserPath
    });
  } catch {
    return Promise.all(targets.map((target) => checkTargetStatusWithFetch(target)));
  }

  try {
    const context = await browser.newContext({
      viewport: { width: 1280, height: 1600 }
    });

    return Promise.all(targets.map((target) => checkTargetStatusWithBrowser(context, target)));
  } finally {
    await browser?.close();
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const targets = parseTargetsJson(args['targets-json']);

  if (targets.length > 0) {
    const results = await checkTargets(targets);
    process.stdout.write(`${JSON.stringify({ results })}\n`);
    return;
  }

  const profileUrl = assertString(args['profile-url'], 'profile-url');
  const [profileResult] = await checkTargets([
    {
      id: 'profile',
      kind: 'profile',
      label: 'Profile',
      url: profileUrl
    }
  ]);

  process.stdout.write(`${profileResult.status}\n`);
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
