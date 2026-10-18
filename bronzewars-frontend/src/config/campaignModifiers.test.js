import assert from 'node:assert/strict';
import { test } from 'node:test';
import { campaignModifiers } from './campaignModifiers.js';
import { newCampaign, CAMPAIGN_HEXES } from './campaignRules.js';

const unit = { quantity: 1, initialStrength: 60, strengths: [40], grainCost: 6, speed: 2 };
const army = (hexId = '7,10', designId = 'egypt') => ({ id: 1, designId, hexId, morale: 70, moved: 0, units: [unit] });
const state = (selected = army()) => ({ ...newCampaign(selected.designId), armies: [selected] });

test('global supply modifiers show positive abundance, negative famine and neutral scarcity', () => {
  const campaign = state();
  assert.deepEqual(campaignModifiers(campaign), [{ kind: 'recovery', value: 5 }]);
  assert.deepEqual(campaignModifiers({ ...campaign, grain: 0 }), [{ kind: 'supply', value: -5 }]);
  const expensive = { ...army(), units: [{ ...unit, grainCost: 1000 }] };
  assert.deepEqual(campaignModifiers(state(expensive)), [{ kind: 'none', value: 0 }]);
});

test('foreign difficult terrain has its negative modifier separately from recovery or famine', () => {
  const desert = CAMPAIGN_HEXES.find((hex) => hex.land && hex.terrain === 'desert' && !hex.territory);
  const selected = army(desert.id), campaign = state(selected);
  assert.deepEqual(campaignModifiers(campaign, selected), [{ kind: 'terrain', value: -3 }, { kind: 'recovery', value: 5 }]);
  assert.deepEqual(campaignModifiers({ ...campaign, grain: 0 }, selected), [{ kind: 'terrain', value: -3 }, { kind: 'supply', value: -5 }]);
  const native = CAMPAIGN_HEXES.find((hex) => hex.territory === 'egypt' && hex.terrain === 'desert');
  assert.deepEqual(campaignModifiers(campaign, army(native.id)), [{ kind: 'recovery', value: 5 }]);
});

test('occupied garrisons show no terrain attrition or recovery while still displaying famine', () => {
  const selected = army('8,32', 'nubia'), campaign = { ...state(selected), cityOwners: { 'egypt-6': 'nubia' } };
  assert.deepEqual(campaignModifiers(campaign, selected), [{ kind: 'none', value: 0 }]);
  assert.deepEqual(campaignModifiers({ ...campaign, grain: 0 }, selected), [{ kind: 'supply', value: -5 }]);
});

test('assault losses replace recovery and can coexist with supply losses', () => {
  const selected = { ...army('15,6'), cityAction: { type: 'assault', cityId: 'hatti-5' } }, campaign = state(selected);
  assert.deepEqual(campaignModifiers(campaign, selected), [{ kind: 'assault', value: -5 }]);
  assert.deepEqual(campaignModifiers({ ...campaign, grain: 0 }, selected), [{ kind: 'supply', value: -5 }, { kind: 'assault', value: -5 }]);
});
