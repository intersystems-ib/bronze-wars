import assert from 'node:assert/strict';
import { test } from 'node:test';
import { armySurrenderMetrics } from './battleMetrics.js';

const unit = (currentStrength, maximum = 60, morale = 100, active = true) => ({ currentStrength, type: { initialStrength: maximum }, morale, active });

test('32 of 60 troops displays 53 percent instead of treating arriving wounded strength as full', () => {
  const metrics = armySurrenderMetrics({ units: [unit(32)] });
  assert.equal(Math.round(metrics.troopPercentage), 53);
  assert.equal(Math.round(metrics.moralePercentage), 53);
  assert.equal(armySurrenderMetrics({ units: [unit(60)] }).troopPercentage, 100);
  assert.equal(armySurrenderMetrics({ units: [unit(32, 80)] }).troopPercentage, 40);
});

test('mixed national unit maxima and troop-weighted morale share the theoretical army denominator', () => {
  const metrics = armySurrenderMetrics({ units: [unit(32, 60, 80), unit(10, 20, 60)] });
  assert.equal(metrics.troopPercentage, 52.5);
  assert.equal(metrics.moralePercentage, 39.5);
  assert.equal(armySurrenderMetrics({ units: [unit(15, 15)] }).troopPercentage, 100);
});

test('destroyed and withdrawn formations remain in theoretical capacity but contribute neither fighting force nor morale', () => {
  for (const inactive of [false, 0]) {
    const metrics = armySurrenderMetrics({ units: [unit(32), unit(20, 60, 100, inactive), unit(0)] });
    assert.equal(metrics.troopPercentage, 32 / 180 * 100);
    assert.equal(metrics.moralePercentage, 3200 / 180);
  }
  assert.deepEqual(armySurrenderMetrics(null), { troopPercentage: 0, moralePercentage: 0 });
});
