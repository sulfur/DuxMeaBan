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

function normalizeTarget(value) {
  const normalized = normalizeText(value);

  if (!normalized) {
    return '@profile';
  }

  if (normalized.startsWith('@')) {
    return normalized;
  }

  return `@${normalized}`;
}

function parseJsonArray(value) {
  const raw = normalizeText(value);

  if (!raw) {
    return [];
  }

  const parsed = JSON.parse(raw);

  if (!Array.isArray(parsed)) {
    throw new Error('post-statuses-json must be a JSON array.');
  }

  return parsed;
}

function normalizePostEntries(postUrls, postStatuses) {
  const urls = Array.isArray(postUrls) ? postUrls : [];
  const statuses = Array.isArray(postStatuses) ? postStatuses : [];
  const total = Math.max(urls.length, statuses.length);
  const entries = [];

  for (let index = 0; index < total; index += 1) {
    const statusEntry = statuses[index] || {};

    entries.push({
      label: normalizeText(statusEntry?.label) || `Post ${index + 1}`,
      status: normalizeStatus(statusEntry?.status),
      url: normalizeText(statusEntry?.url) || normalizeText(urls[index])
    });
  }

  return entries;
}

export function buildReportStatusLines({
  target,
  profileStatus,
  postUrls,
  postStatuses,
  dataLine
}) {
  const lines = [];

  lines.push(normalizeTarget(target));
  lines.push(`Profile: ${normalizeStatus(profileStatus)}`);

  for (const entry of normalizePostEntries(postUrls, postStatuses)) {
    lines.push(`${entry.label}: ${entry.status}`);
  }

  lines.push(`Data: ${normalizeText(dataLine) || 'Pending'}`);

  return lines;
}

function main() {
  const args = parseArgs(process.argv);
  const lines = buildReportStatusLines({
    target: args.target,
    profileStatus: args['profile-status'],
    postUrls: parseJsonArray(args['post-urls-json']),
    postStatuses: parseJsonArray(args['post-statuses-json']),
    dataLine: args['data-line']
  });

  process.stdout.write(`${lines.join('\n')}\n`);
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
