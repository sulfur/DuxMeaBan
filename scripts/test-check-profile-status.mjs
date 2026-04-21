import assert from 'node:assert/strict';
import { checkTargets } from './check-profile-status.mjs';

const results = await checkTargets([
  {
    id: 'profile',
    kind: 'profile',
    label: 'Profile',
    url: 'http://127.0.0.1:65535/unavailable'
  }
]);

assert.equal(results.length, 1, 'checker did not return one result');
assert.equal(results[0].status, 'Unreachable', 'load failure must be marked Unreachable');

process.stdout.write('check-profile-status test passed\n');
