import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import process from 'node:process';

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

function normalizeText(value) {
  return String(value || '').trim();
}

function normalizeStatus(value, fallback = 'Unreachable') {
  const normalized = normalizeText(value);
  return normalized || fallback;
}

function nowLocalTimestamp() {
  const pad = (value) => String(value).padStart(2, '0');
  const now = new Date();

  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
}

export function extractReportStatusResultSummary(payload, fallbackCheckedAtLocal = nowLocalTimestamp()) {
  const results = Array.isArray(payload?.results) ? payload.results : [];
  const checkedAtLocal = normalizeText(payload?.checkedAtLocal) || normalizeText(fallbackCheckedAtLocal) || nowLocalTimestamp();
  const profileResult = results.find((entry) => String(entry?.kind || '') === 'profile') || results[0] || null;
  const profileStatus = normalizeStatus(profileResult?.status);

  const postStatuses = results
    .filter((entry) => String(entry?.kind || '') === 'post')
    .map((entry, index) => ({
      label: normalizeText(entry?.label) || `Post ${index + 1}`,
      url: normalizeText(entry?.url),
      status: normalizeStatus(entry?.status),
      checkedAtLocal: normalizeText(entry?.checkedAtLocal) || checkedAtLocal
    }));

  return {
    profileStatus,
    checkedAtLocal,
    postStatuses
  };
}

export function formatReportStatusResultSummary(payload, fallbackCheckedAtLocal) {
  const summary = extractReportStatusResultSummary(payload, fallbackCheckedAtLocal);
  return `${summary.profileStatus}|${summary.checkedAtLocal}|${JSON.stringify(summary.postStatuses)}`;
}

export function applyReportStatusResults(reports, targetId, payload, fallbackCheckedAtLocal) {
  const nextReports = Array.isArray(reports) ? reports : [];
  const summary = extractReportStatusResultSummary(payload, fallbackCheckedAtLocal);

  for (const report of nextReports) {
    if (String(report?.id || '') !== String(targetId || '')) {
      continue;
    }

    report.accountStatus = summary.profileStatus;
    report.accountStatusCheckedAtLocal = summary.checkedAtLocal;
    report.postStatuses = summary.postStatuses;
    report.postStatusesCheckedAtLocal = summary.checkedAtLocal;

    if (!report.reportedUsername) {
      const rawUrl = String(report.profileUrl || '').trim();

      if (rawUrl) {
        try {
          const parsed = new URL(rawUrl);
          const parts = parsed.pathname.split('/').filter(Boolean);
          report.reportedUsername = parts[0] ? `@${parts[0]}` : rawUrl;
        } catch {
          report.reportedUsername = rawUrl;
        }
      }
    }
  }

  return {
    reports: nextReports,
    summary
  };
}

function main() {
  const args = parseArgs(process.argv);
  let payload = { results: [] };
  const reportsPath = normalizeText(args['reports-path']);
  const targetId = normalizeText(args['target-id']);

  try {
    payload = JSON.parse(String(args['result-json'] || '{}'));
  } catch {
    payload = { results: [] };
  }

  if (reportsPath && targetId) {
    let raw = '[]';

    if (fs.existsSync(reportsPath)) {
      raw = fs.readFileSync(reportsPath, 'utf8').trim() || '[]';
    }

    let reports = [];

    try {
      reports = JSON.parse(raw);
    } catch {
      reports = [];
    }

    const updated = applyReportStatusResults(reports, targetId, payload, args['checked-at-local']);
    fs.writeFileSync(reportsPath, JSON.stringify(updated.reports, null, 2));
    process.stdout.write(`${formatReportStatusResultSummary(payload, args['checked-at-local'])}\n`);
    return;
  }

  process.stdout.write(`${formatReportStatusResultSummary(payload, args['checked-at-local'])}\n`);
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
