import assert from 'node:assert/strict';
import { buildReportStatusLines } from './report-status-lines.mjs';
import { extractReportStatusResultSummary, formatReportStatusResultSummary } from './report-status-results.mjs';

function runCase(name, input, expected) {
  const actual = buildReportStatusLines(input);
  assert.deepEqual(actual, expected, `${name} failed`);
}

runCase(
  'profile with posts',
  {
    target: '@donvitotre',
    profileStatus: 'Pending',
    postUrls: [
      'https://www.instagram.com/p/DXYc2IViL_A/?img_index=1',
      'https://www.instagram.com/p/DXYc2IViL_A/?img_index=2'
    ],
    postStatuses: [
      { label: 'Post 1', status: 'Banned' },
      { label: 'Post 2', status: 'Pending' }
    ],
    dataLine: '2026-04-21 11:59:55'
  },
  [
    '@donvitotre',
    'Profile: Pending',
    'Post 1: Banned',
    'Post 2: Pending',
    'Data: 2026-04-21 11:59:55'
  ]
);

runCase(
  'posts fallback to unreachable',
  {
    target: '@donvitotre',
    profileStatus: 'Unreachable',
    postUrls: [
      'https://www.instagram.com/p/DXYc2IViL_A/?img_index=1',
      'https://www.instagram.com/p/DXYc2IViL_A/?img_index=2'
    ],
    postStatuses: [],
    dataLine: '2026-04-21 11:59:55'
  },
  [
    '@donvitotre',
    'Profile: Unreachable',
    'Post 1: Unreachable',
    'Post 2: Unreachable',
    'Data: 2026-04-21 11:59:55'
  ]
);

const backendPayload = {
  results: [
    { kind: 'profile', status: 'Pending', checkedAtLocal: '2026-04-21 11:59:55' },
    { kind: 'post', label: 'Post 1', status: 'Banned', checkedAtLocal: '2026-04-21 11:59:55' },
    { kind: 'post', label: 'Post 2', status: 'Pending', checkedAtLocal: '2026-04-21 11:59:55' }
  ]
};

assert.deepEqual(
  extractReportStatusResultSummary(backendPayload, '2026-04-21 11:59:55'),
  {
    profileStatus: 'Pending',
    checkedAtLocal: '2026-04-21 11:59:55',
    postStatuses: [
      { label: 'Post 1', url: '', status: 'Banned', checkedAtLocal: '2026-04-21 11:59:55' },
      { label: 'Post 2', url: '', status: 'Pending', checkedAtLocal: '2026-04-21 11:59:55' }
    ]
  }
);

assert.equal(
  formatReportStatusResultSummary(backendPayload, '2026-04-21 11:59:55'),
  'Pending|2026-04-21 11:59:55|[{"label":"Post 1","url":"","status":"Banned","checkedAtLocal":"2026-04-21 11:59:55"},{"label":"Post 2","url":"","status":"Pending","checkedAtLocal":"2026-04-21 11:59:55"}]'
);

runCase(
  'fallback target and status',
  {
    target: '',
    profileStatus: '',
    postStatuses: [],
    dataLine: ''
  },
  [
    '@profile',
    'Profile: Unreachable',
    'Data: Pending'
  ]
);

process.stdout.write('report-status-lines test passed\n');
