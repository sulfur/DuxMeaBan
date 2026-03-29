import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { spawnSync } from 'node:child_process';
import { chromium } from 'playwright-core';

const WAIT_TIMEOUT_MS = 30 * 60 * 1000;
const SUBMIT_CONFIRM_TIMEOUT_MS = 45 * 1000;
const FORM_URL = 'https://help.instagram.com/contact/406206379945942';
const CONFIRMATION_TEXT_PATTERNS = [
  'grazie',
  'thank you',
  'abbiamo ricevuto',
  'we received',
  'request submitted',
  'report submitted',
  'richiesta inviata',
  'segnalazione inviata',
  'thanks for contacting'
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
  if (process.env.PLAYWRIGHT_BROWSER_PATH && fsSync.existsSync(process.env.PLAYWRIGHT_BROWSER_PATH)) {
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
    if (fsSync.existsSync(candidate)) {
      return candidate;
    }
  }

  const commandCandidates = [
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

  throw new Error('No supported browser executable found. Set PLAYWRIGHT_BROWSER_PATH or install Chromium/Chrome/Edge for Linux.');
}

async function readPayload(payloadPath) {
  const raw = await fs.readFile(payloadPath, 'utf8');
  return JSON.parse(raw);
}

function cleanUrls(values) {
  const unique = [];
  const seen = new Set();

  for (const value of values ?? []) {
    if (typeof value !== 'string') {
      continue;
    }

    const trimmed = value.trim();

    if (!trimmed || seen.has(trimmed.toLowerCase())) {
      continue;
    }

    seen.add(trimmed.toLowerCase());
    unique.push(trimmed);
  }

  return unique;
}

async function waitForSelector(page, selector, timeout = 20000) {
  await page.waitForSelector(selector, { state: 'visible', timeout });
}

async function ensureParentDirectory(filePath) {
  if (!filePath) {
    return;
  }

  const directory = path.dirname(filePath);

  if (directory && !fsSync.existsSync(directory)) {
    fsSync.mkdirSync(directory, { recursive: true });
  }
}

async function writeJsonArtifact(filePath, value) {
  if (!filePath) {
    return;
  }

  await ensureParentDirectory(filePath);
  await fs.writeFile(filePath, JSON.stringify(value, null, 2));
}

async function dismissCookieBanner(page) {
  const candidates = [
    /Rifiuta cookie facoltativi/i,
    /Reject optional cookies/i,
    /Only allow essential cookies/i,
    /Consenti solo i cookie essenziali/i
  ];

  for (const name of candidates) {
    const locator = page.getByRole('button', { name }).first();

    try {
      if ((await locator.count()) === 0) {
        continue;
      }

      await locator.click({ timeout: 2000 });
      await page.waitForTimeout(250);
      console.log(`Cookie banner chiuso con il bottone ${name}.`);
      return true;
    } catch {
      // Try the next cookie action.
    }
  }

  return false;
}

async function setRadio(page, selector) {
  await page.locator(selector).first().evaluate((node) => {
    node.checked = true;
    node.dispatchEvent(new Event('input', { bubbles: true }));
    node.dispatchEvent(new Event('change', { bubbles: true }));
    node.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

async function fillInput(page, selector, value) {
  await waitForSelector(page, selector);
  await page.locator(selector).first().fill(value);
}

async function selectCountry(page) {
  await waitForSelector(page, 'select[name="gb_country"]');

  for (const value of ['Italy', 'Italia']) {
    try {
      await page.locator('select[name="gb_country"]').selectOption(value);
      return;
    } catch {
      // Try the next value.
    }
  }

  throw new Error('Could not select Italy from the country dropdown.');
}

async function describeLocatorPosition(locator) {
  return locator.evaluate((node) => {
    const rect = node.getBoundingClientRect();
    const viewport = {
      width: window.innerWidth,
      height: window.innerHeight
    };
    const scroll = {
      x: window.scrollX,
      y: window.scrollY
    };
    const absoluteRect = {
      top: rect.top + window.scrollY,
      right: rect.right + window.scrollX,
      bottom: rect.bottom + window.scrollY,
      left: rect.left + window.scrollX
    };
    const center = {
      x: rect.left + (rect.width / 2),
      y: rect.top + (rect.height / 2)
    };
    const isVisibleWithinViewport =
      rect.width > 0 &&
      rect.height > 0 &&
      center.x >= 0 &&
      center.y >= 0 &&
      center.x <= viewport.width &&
      center.y <= viewport.height;

    return {
      text: node.textContent?.trim() ?? '',
      tagName: node.tagName,
      id: node.id || '',
      className: String(node.className || ''),
      viewport,
      scroll,
      rect: {
        top: rect.top,
        right: rect.right,
        bottom: rect.bottom,
        left: rect.left,
        width: rect.width,
        height: rect.height
      },
      absoluteRect,
      center,
      isVisibleWithinViewport
    };
  });
}

async function centerLocatorInViewport(page, locator) {
  await locator.evaluate((node) => {
    const rect = node.getBoundingClientRect();
    const targetTop = Math.max(
      window.scrollY + rect.top - ((window.innerHeight - rect.height) / 2),
      0
    );

    window.scrollTo({
      top: targetTop,
      left: Math.max(window.scrollX + rect.left - ((window.innerWidth - rect.width) / 2), 0),
      behavior: 'auto'
    });
  });

  await page.waitForTimeout(300);
}

async function captureSubmitMap(locator, candidateCount) {
  const position = await describeLocatorPosition(locator);

  return {
    capturedAtUtc: new Date().toISOString(),
    candidateCount,
    button: position
  };
}

async function collectConfirmationState(page, originUrl) {
  return page.evaluate(({ originUrl, patterns }) => {
    const bodyText = (document.body?.innerText || '').replace(/\s+/g, ' ').trim();
    const hasSuccessText = patterns.some((pattern) => new RegExp(pattern, 'i').test(bodyText));
    const signatureField = document.querySelector('input[name="signature"]');
    const visibleSubmitButton = Array.from(document.querySelectorAll('button[type="submit"]'))
      .some((button) => button.offsetParent !== null);

    return {
      currentUrl: window.location.href,
      title: document.title,
      urlChanged: window.location.href !== originUrl,
      hasSuccessText,
      hasSignatureField: Boolean(signatureField),
      hasVisibleSubmitButton: visibleSubmitButton,
      bodyPreview: bodyText.slice(0, 500)
    };
  }, { originUrl, patterns: CONFIRMATION_TEXT_PATTERNS });
}

async function waitForSubmissionConfirmation(page, originUrl) {
  const deadline = Date.now() + SUBMIT_CONFIRM_TIMEOUT_MS;

  while (Date.now() < deadline) {
    const state = await collectConfirmationState(page, originUrl);

    if (state.urlChanged || state.hasSuccessText || (!state.hasSignatureField && !state.hasVisibleSubmitButton)) {
      return state;
    }

    await page.waitForTimeout(500);
  }

  const finalState = await collectConfirmationState(page, originUrl);
  throw new Error(
    `Submit eseguito ma la schermata di conferma non e stata rilevata entro ${SUBMIT_CONFIRM_TIMEOUT_MS} ms. Ultimo stato: ${JSON.stringify(finalState)}`
  );
}

async function completeLegalStep(page, payload) {
  await dismissCookieBanner(page);
  await selectCountry(page);
  await setRadio(page, 'input[name="Other_Countries"][value="OtherTDR_Select"]');

  await fillInput(page, 'textarea[name="Field237366092180898"]', payload.specificLawUrl);
  await fillInput(page, 'textarea[name="legal_explanation"]', payload.why ?? payload.reportText);
  await setRadio(page, 'input[name="continue_report_4"]');
}

async function completeIdentityStep(page, args) {
  await setRadio(page, 'input[name="authorization"][value="I am reporting on behalf of myself"]');

  await fillInput(page, 'input[name="Name"]', args['first-name']);
  await fillInput(page, 'input[name="Surname"]', args['last-name']);
  await fillInput(page, 'input[name="email_address"]', args.email);
  await fillInput(page, 'input[name="email_confirm"]', args.email);
  await setRadio(page, 'input[name="continue_1"]');
}

async function completeUrlsStep(page, urls) {
  const resolvedUrls = cleanUrls(urls);

  if (resolvedUrls.length === 0) {
    throw new Error('No target URLs were provided for the URL section.');
  }

  const urlFieldNames = ['URLs1', 'URLs2', 'URLs3', 'URLs4', 'URLs5'];
  const usableCount = Math.min(resolvedUrls.length, urlFieldNames.length);

  for (let index = 0; index < usableCount; index += 1) {
    await fillInput(page, `input[name="${urlFieldNames[index]}"]`, resolvedUrls[index]);
  }

  if (resolvedUrls.length > urlFieldNames.length) {
    console.log(`Il form espone 5 campi URL visibili in questo flusso. Gli URL extra (${resolvedUrls.length - urlFieldNames.length}) non vengono inviati automaticamente.`);
  }

  await setRadio(page, 'input[name="more_url_ornot"][value="Continue with your report"]');
}

async function completeFinalStep(page, args) {
  await waitForSelector(page, 'input[name="court_order_question"]', WAIT_TIMEOUT_MS);
  await setRadio(
    page,
    `input[name="court_order_question"][value="${args['court-order'] === 'yes' ? 'Yes' : 'No'}"]`
  );

  await waitForSelector(page, 'input[name="Final_agree"]', WAIT_TIMEOUT_MS);
  await setRadio(
    page,
    `input[name="Final_agree"][value="${args.consent === 'yes' || args.consent === 'true' ? 'Yes' : 'No'}"]`
  );

  await fillInput(page, 'input[name="signature"]', args.signature);
  await dismissCookieBanner(page);

  const submitCandidates = page.locator('button[type="submit"]');
  const candidateCount = await submitCandidates.count();

  if (candidateCount === 0) {
    throw new Error('Nessun bottone submit trovato nello step finale.');
  }

  let submitButton = page.locator('button[type="submit"]').filter({ hasText: /Invia|Submit/i }).last();

  if ((await submitButton.count()) === 0) {
    submitButton = submitCandidates.last();
  }

  await submitButton.waitFor({ state: 'visible', timeout: WAIT_TIMEOUT_MS });

  const submitMapPath = typeof args['submit-map'] === 'string' ? args['submit-map'].trim() : '';
  const submitMap = {
    originUrl: page.url(),
    beforeScroll: await captureSubmitMap(submitButton, candidateCount),
    clickAttempts: []
  };
  console.log(`Submit button map before scroll: ${JSON.stringify(submitMap.beforeScroll)}`);
  await writeJsonArtifact(submitMapPath, submitMap);

  await centerLocatorInViewport(page, submitButton);

  submitMap.afterScroll = await captureSubmitMap(submitButton, candidateCount);
  console.log(`Submit button map after scroll: ${JSON.stringify(submitMap.afterScroll)}`);
  await writeJsonArtifact(submitMapPath, submitMap);

  const clickMethods = [
    {
      name: 'locator.click',
      run: async () => {
        await submitButton.click({ timeout: 5000 });
      }
    },
    {
      name: 'mouse.click',
      run: async () => {
        const mapped = submitMap.afterScroll?.button;

        if (!mapped?.isVisibleWithinViewport) {
          throw new Error('Mapped submit button is still outside of the viewport.');
        }

        await page.mouse.move(mapped.center.x, mapped.center.y);
        await page.waitForTimeout(100);
        await page.mouse.click(mapped.center.x, mapped.center.y, { delay: 50 });
      }
    },
    {
      name: 'locator.click(force)',
      run: async () => {
        await submitButton.click({ timeout: 5000, force: true });
      }
    },
    {
      name: 'dom.click',
      run: async () => {
        await submitButton.evaluate((node) => {
          node.click();
        });
      }
    }
  ];

  let lastError = null;

  for (const method of clickMethods) {
    try {
      await method.run();
      submitMap.clickAttempts.push({
        method: method.name,
        status: 'success',
        atUtc: new Date().toISOString()
      });
      submitMap.confirmation = await waitForSubmissionConfirmation(page, submitMap.originUrl);
      submitMap.confirmedAtUtc = new Date().toISOString();
      submitMap.finalUrl = page.url();
      await writeJsonArtifact(submitMapPath, submitMap);
      console.log(`Submit finale confermato con metodo ${method.name}.`);
      return submitMap;
    } catch (error) {
      lastError = error;
      submitMap.clickAttempts.push({
        method: method.name,
        status: 'failed',
        atUtc: new Date().toISOString(),
        message: error.message
      });
      await writeJsonArtifact(submitMapPath, submitMap);
      console.log(`Submit click ${method.name} failed: ${error.message}`);
    }
  }

  throw lastError ?? new Error('Il submit finale non e stato eseguito.');
}

async function saveFinalScreenshot(page, screenshotPath) {
  if (!screenshotPath) {
    return;
  }

  await ensureParentDirectory(screenshotPath);

  await page.screenshot({
    path: screenshotPath,
    fullPage: true
  });
}

async function main() {
  const args = parseArgs(process.argv);
  const payloadPath = assertString(args.payload, 'payload');
  const payload = await readPayload(payloadPath);
  const signature = assertString(args.signature, 'signature');
  const primaryUrl = assertString(args['profile-url'] ?? payload.reportedContentUrls?.[0], 'profile-url');
  const targetUrls = cleanUrls([primaryUrl, ...(payload.reportedContentUrls ?? [])]);
  const screenshotPath = typeof args.screenshot === 'string' ? args.screenshot : '';
  const submitMapPath = typeof args['submit-map'] === 'string' ? args['submit-map'] : '';
  const headless = Boolean(args.headless);

  if (!args['first-name'] || !args['last-name'] || !args.email) {
    throw new Error('Missing required identity values: --first-name, --last-name and --email.');
  }

  if (!args['court-order'] || !args.consent) {
    throw new Error('Missing required case answers: --court-order and --consent.');
  }

  if (!['yes', 'no'].includes(String(args['court-order']).trim().toLowerCase())) {
    throw new Error('--court-order must be yes or no.');
  }

  if (!['yes', 'no', 'true', 'false'].includes(String(args.consent).trim().toLowerCase())) {
    throw new Error('--consent must be yes/no or true/false.');
  }

  if (String(args['court-order']).trim().toLowerCase() === 'yes') {
    throw new Error('The automated flow currently supports only --court-order no. The yes branch requires a court-order upload path.');
  }

  if (!['yes', 'true'].includes(String(args.consent).trim().toLowerCase())) {
    throw new Error('The automated flow currently supports only affirmative consent because the non-consent branch does not reach the signature step.');
  }

  const browser = await chromium.launch({
    headless,
    executablePath: detectBrowserPath(),
    args: headless ? [] : ['--start-maximized']
  });

  const context = await browser.newContext({
    viewport: headless ? { width: 1440, height: 1400 } : null
  });

  const page = await context.newPage();
  page.setDefaultTimeout(20000);

  try {
    await page.goto(payload.officialEntryUrl ?? FORM_URL, { waitUntil: 'domcontentloaded' });
    await dismissCookieBanner(page);

    console.log('Compilo la parte legale del form.');
    await completeLegalStep(page, payload);

    console.log('Compilo i dati del segnalante.');
    await completeIdentityStep(page, args);

    console.log('Compilo i link del profilo e dei post.');
    await completeUrlsStep(page, targetUrls);

    console.log('Compilo ordinanza, consenso e firma.');
    await completeFinalStep(page, {
      ...args,
      'submit-map': submitMapPath,
      signature
    });

    await saveFinalScreenshot(page, screenshotPath);
    console.log('Schermata finale di richiesta inviata salvata.');
  } catch (error) {
    try {
      await saveFinalScreenshot(page, screenshotPath);
    } catch {
      // Ignore screenshot failures in the error path.
    }
    throw error;
  } finally {
    await context.close();
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
