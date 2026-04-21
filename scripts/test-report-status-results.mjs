import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { applyReportStatusResults, formatReportStatusResultSummary } from './report-status-results.mjs';

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'duxmeaban-report-status-'));
const reportsPath = path.join(tempDir, 'reports.json');

const initialReports = [
  {
    id: 'report-1',
    profileUrl: 'https://www.instagram.com/donvitotre',
    postUrls: [
      'https://www.instagram.com/p/post-1',
      'https://www.instagram.com/p/post-2'
    ],
    accountStatus: 'Pending',
    accountStatusCheckedAtLocal: '',
    postStatuses: [],
    postStatusesCheckedAtLocal: ''
  }
];

const payload = {
  results: [
    { kind: 'profile', status: 'Active' },
    { kind: 'post', label: 'Post 1', status: 'Banned' },
    { kind: 'post', label: 'Post 2', status: 'Unreachable' }
  ]
};

const updated = applyReportStatusResults(structuredClone(initialReports), 'report-1', payload, '2026-04-21 20:02:00');
fs.writeFileSync(reportsPath, JSON.stringify(updated.reports, null, 2));

const persisted = JSON.parse(fs.readFileSync(reportsPath, 'utf8'));

assert.equal(
  formatReportStatusResultSummary(payload, '2026-04-21 20:02:00'),
  'Active|2026-04-21 20:02:00|[{"label":"Post 1","url":"","status":"Banned","checkedAtLocal":"2026-04-21 20:02:00"},{"label":"Post 2","url":"","status":"Unreachable","checkedAtLocal":"2026-04-21 20:02:00"}]'
);

assert.equal(persisted[0].accountStatus, 'Active');
assert.equal(persisted[0].accountStatusCheckedAtLocal, '2026-04-21 20:02:00');
assert.deepEqual(persisted[0].postStatuses, [
  {
    label: 'Post 1',
    url: '',
    status: 'Banned',
    checkedAtLocal: '2026-04-21 20:02:00'
  },
  {
    label: 'Post 2',
    url: '',
    status: 'Unreachable',
    checkedAtLocal: '2026-04-21 20:02:00'
  }
]);

process.stdout.write('report-status-results test passed\n');
