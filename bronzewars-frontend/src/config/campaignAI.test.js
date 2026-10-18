import assert from 'node:assert/strict';
import { test } from 'node:test';
import { initializeCampaignAI, rivalNations, needsRecruitmentDecision, maxRecruitableTroops, recruitmentCapacity, applyRecruitmentDecision } from './campaignAI.js';
import { CAMPAIGN_HEXES, newCampaign, nextSeason, armyTroops, loadCampaign, campaignUpkeep } from './campaignRules.js';
import { campaignView } from './campaignVisibility.js';

const catalogue = [
  { code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 6, attack: 4, defense: 2, damage: 5 },
  { code: 'SPEARMEN', initialStrength: 100, speed: 1, grainCost: 6, attack: 5, defense: 6, damage: 7 },
];
const recruit = (quantities = { LIGHT_INFANTRY: 2 }) => ({ action: 'recruit', quantities, reason: 'Defender la capital' });

test('each rival starts with an independent reserve, preserving old loot and excluding Sea Peoples', () => {
  const original = { ...newCampaign('nubia'), foreignGrain: { egypt: 12 } };
  const state = initializeCampaignAI(original);
  assert.deepEqual(rivalNations(state), ['egypt', 'hatti']);
  assert.deepEqual(state.foreignGrain, { egypt: 12, hatti: 100 });
  assert.equal(state.grain, 100);
  assert.deepEqual(initializeCampaignAI(state), state);
  assert.equal(original.foreignGrain.hatti, undefined);
});

test('old wait decisions are reconsidered once under regional deployment without duplicating recruited armies or overriding explicit skips', () => {
  const state = applyRecruitmentDecision(initializeCampaignAI(newCampaign('hatti')), 'egypt', recruit(), catalogue);
  delete state.aiRecruitment.egypt.deploymentRuleVersion;
  state.aiRecruitment.nubia = { turn: 0, action: 'wait', source: 'LLM', reason: 'No hay espacio' };
  assert.equal(needsRecruitmentDecision(state, 'egypt'), false);
  assert.equal(needsRecruitmentDecision(state, 'nubia'), true);
  const upgraded = initializeCampaignAI(state);
  assert.equal(upgraded.aiRecruitment.nubia, undefined);
  assert.equal(upgraded.armies, state.armies);
  assert.deepEqual(upgraded.foreignGrain, state.foreignGrain);
  assert.equal(needsRecruitmentDecision(upgraded, 'egypt'), false);
  const capacity = recruitmentCapacity(upgraded, 'egypt', catalogue);
  assert.equal(capacity.capitalAvailable, true);
  assert.ok(capacity.freeDeploymentHexes > 0);
  const decided = applyRecruitmentDecision(upgraded, 'nubia', { action: 'wait', reason: 'Ahorrar reservas' }, catalogue);
  assert.equal(needsRecruitmentDecision(decided, 'nubia'), false);
  assert.deepEqual(initializeCampaignAI(decided), decided);
  const skipped = { ...state, aiRecruitment: { nubia: { turn: 0, action: 'wait', source: 'SKIPPED', reason: 'Omitido' } } };
  assert.equal(needsRecruitmentDecision(skipped, 'nubia'), false);
});

test('capacity maximizes actual force with integer costs and formation limits rather than a greedy ratio', () => {
  const units = [{ grainCost: 4, initialStrength: 6 }, { grainCost: 5, initialStrength: 7 }];
  assert.equal(maxRecruitableTroops(units, 8), 12);
  assert.equal(maxRecruitableTroops(units, 3), 0);
  assert.equal(maxRecruitableTroops([{ grainCost: 1, initialStrength: 100 }], 1000), 9900);
  const state = initializeCampaignAI(newCampaign());
  const capacity = recruitmentCapacity(state, 'nubia', catalogue);
  assert.equal(capacity.reserve, 100);
  assert.equal(capacity.annualProduction, 20);
  assert.equal(capacity.turnsToHarvest, 3);
  assert.equal(capacity.maxAffordableTroops, 1600);
  assert.equal(capacity.maxSustainableTroops, 1100);
  assert.equal(capacity.consumptionPerTurn, 0);
  assert.equal(capacity.troops, 0);
  for (const option of capacity.options) {
    assert.equal(option.cost, Object.entries(option.quantities).reduce((sum, [code, count]) => sum + catalogue.find((unit) => unit.code === code).grainCost * count, 0));
    assert.equal(option.troops, Object.entries(option.quantities).reduce((sum, [code, count]) => sum + catalogue.find((unit) => unit.code === code).initialStrength * count, 0));
    assert.ok(option.cost <= capacity.reserve);
    assert.equal(option.reserveAfterRecruitment, capacity.reserve - option.cost);
    assert.equal(option.consumptionPerTurn, option.cost / 10);
  }
});

test('LLM may spend reserves above sustainable capacity and in scarcity, without spending the human grain', () => {
  const initial = initializeCampaignAI(newCampaign());
  let state = applyRecruitmentDecision(initial, 'nubia', recruit({ SPEARMEN: 16 }), catalogue);
  assert.equal(state.grain, 100);
  assert.equal(state.foreignGrain.nubia, 4);
  assert.equal(armyTroops(state.armies[0]), 1600);
  assert.equal(state.armies[0].designId, 'nubia');
  assert.equal(campaignUpkeep(state), 0);
  assert.equal(recruitmentCapacity(state, 'nubia', catalogue).situation, 'scarcity');
  assert.equal(recruitmentCapacity(state, 'nubia', catalogue).maxSustainableTroops, 0);
  assert.equal(recruitmentCapacity(state, 'nubia', catalogue).capitalAvailable, true);
  assert.equal(recruitmentCapacity(state, 'nubia', catalogue).maxAffordableTroops, 0);
  assert.equal(applyRecruitmentDecision(state, 'nubia', recruit(), catalogue), state);
  state = { ...state, turn: 1, foreignGrain: { ...state.foreignGrain, nubia: 100 } };
  state.armies = state.armies.map((army) => ({ ...army, hexId: CAMPAIGN_HEXES.find((hex) => hex.territory === 'nubia' && !hex.city).id }));
  const next = applyRecruitmentDecision(state, 'nubia', recruit(), catalogue);
  assert.equal(next.armies.length, 2);
  assert.equal(next.foreignGrain.nubia, 88);
  assert.equal(next.grain, 100);
});

test('wait, invalid orders, full capital regions and duplicate decisions never create or overspend armies', () => {
  const state = initializeCampaignAI(newCampaign());
  for (const decision of [recruit({ SPEARMEN: 17 }), recruit({ CHARIOTS: 1 }), recruit({ SPEARMEN: 0.5 }), recruit({ SPEARMEN: -1 }), recruit({ SPEARMEN: 100 }), recruit({}), { action: 'move', reason: '' }]) {
    assert.throws(() => applyRecruitmentDecision(state, 'nubia', decision, catalogue));
  }
  const waiting = applyRecruitmentDecision(state, 'nubia', { action: 'wait', reason: 'Ahorrar' }, catalogue);
  assert.equal(waiting.armies.length, 0);
  assert.equal(waiting.foreignGrain.nubia, 100);
  assert.equal(applyRecruitmentDecision(waiting, 'nubia', recruit(), catalogue), waiting);
  assert.equal(applyRecruitmentDecision(state, 'egypt', recruit(), catalogue), state);
  assert.equal(applyRecruitmentDecision(state, 'seapeople', recruit(), catalogue), state);
  const occupied = applyRecruitmentDecision(state, 'nubia', recruit(), catalogue);
  const second = applyRecruitmentDecision({ ...occupied, turn: 1 }, 'nubia', recruit(), catalogue);
  assert.equal(second.armies.length, 2);
  assert.notEqual(second.armies[0].hexId, second.armies[1].hexId);
  const regionId = CAMPAIGN_HEXES.find((hex) => hex.id === occupied.armies[0].hexId).regionId;
  const full = { ...occupied, turn: 1, armies: CAMPAIGN_HEXES.filter((hex) => hex.regionId === regionId).map((hex, index) => ({ ...occupied.armies[0], id: index + 1, hexId: hex.id })) };
  assert.equal(recruitmentCapacity(full, 'nubia', catalogue).capitalAvailable, false);
  assert.equal(recruitmentCapacity(full, 'nubia', catalogue).maxAffordableTroops, 0);
  assert.throws(() => applyRecruitmentDecision(full, 'nubia', recruit(), catalogue));
});

test('rivals pay upkeep every season, harvest only annually and preserve independent economic state in saves', () => {
  let state = applyRecruitmentDecision(initializeCampaignAI(newCampaign()), 'hatti', recruit(), catalogue);
  assert.equal(state.foreignGrain.hatti, 88);
  for (const expected of [87, 86, 115]) {
    state = nextSeason(state);
    assert.equal(state.foreignGrain.hatti, expected);
    assert.equal(state.lastTurnReport.requiredGrain, 0);
    assert.equal(state.lastTurnReport.armies.length, 0);
  }
  assert.equal(state.foreignGrain.nubia, 120);
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(state) }), state);
  const invalid = { ...state, aiRecruitment: { hatti: { turn: 999, action: 'wait', reason: '' } } };
  assert.equal(loadCampaign({ getItem: () => JSON.stringify(invalid) }, 'egypt', { fallbackToNew: false }), null);
});

test('rival famine and home-territory protection affect troop force without leaking reports to the player', () => {
  let state = applyRecruitmentDecision(initializeCampaignAI(newCampaign()), 'nubia', recruit({ LIGHT_INFANTRY: 1 }), catalogue);
  state.foreignGrain.nubia = 0;
  state.armies[0].hexId = CAMPAIGN_HEXES.find((hex) => hex.territory === 'nubia' && hex.terrain === 'desert').id;
  state = nextSeason(state);
  assert.equal(armyTroops(state.armies[0]), 57);
  assert.deepEqual(state.lastTurnReport.armies, []);
});

test('debug reveal shows remote enemy formations without changing normal human or AI visibility', () => {
  const state = applyRecruitmentDecision(initializeCampaignAI(newCampaign()), 'nubia', recruit(), catalogue);
  const normal = campaignView(state);
  assert.equal(normal.armies.length, 0);
  const debug = campaignView(state, 'egypt', { reveal: true });
  assert.equal(debug.visibleHexIds.size, CAMPAIGN_HEXES.length);
  assert.equal(debug.armies[0].unitCount, 2);
  assert.equal(debug.armies[0].own, false);
  assert.equal(debug.armies[0].units, undefined);
  assert.deepEqual(campaignView(state), normal);
  assert.equal(campaignView(state, 'hatti').armies.length, 0);
});
