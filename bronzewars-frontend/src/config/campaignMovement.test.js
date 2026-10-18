import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_HEXES, CAMPAIGN_CITIES, HEX_BY_ID, neighbors, newCampaign, armyTroops, remainingMovement, nextSeason, loadCampaign, migrateCampaignStrength, campaignTerritoryInfo } from './campaignRules.js';
import { hexDistance } from './campaignVisibility.js';
import { movementContext, storeMovementDecision, executeMovementOrder, needsMovementDecision, pendingMovementOrder, engageArmy, applyEncounterResult } from './campaignMovement.js';
import { resolveAIEncounter, campaignArmyPower } from './campaignCombat.js';
import { initializeCampaignAI, recruitmentCapacity, applyRecruitmentDecision } from './campaignAI.js';

const type = { code: 'LIGHT_INFANTRY', quantity: 2, initialStrength: 60, strengths: [60, 60], speed: 2, grainCost: 6, attack: 4, defense: 4, damage: 5 };
const army = (id, designId, hexId, overrides = {}) => ({ id, designId, hexId, name: `Army ${id}`, morale: 100, moved: 0, units: [structuredClone(type)], ...overrides });
const state = (armies, nation = 'egypt') => ({ ...newCampaign(nation), armies, nextArmyId: Math.max(...armies.map((army) => army.id), 0) + 1 });
const pair = CAMPAIGN_HEXES.find((hex) => hex.territory === 'hatti' && neighbors(hex.id).length >= 4);
const other = neighbors(pair.id)[0];
const choose = (context, intent) => ({ reason: intent, orders: context.armies.map((army) => ({ optionId: context.options.find((option) => option.armyId === army.id && option.intent === intent)?.id ?? context.options.find((option) => option.armyId === army.id && option.intent === 'HOLD').id })) });

test('old strength saves acquire missing national combat stats without healing or rebalancing existing stats', () => {
  const old = state([army(1, 'hatti', pair.id, { units: [{ ...type, strengths: [15, 30], attack: undefined, defense: undefined, damage: undefined }] })]);
  const catalogue = [{ ...type, profiles: { hittite: { attack: 8, defense: 7, damage: 6 } } }];
  const upgraded = migrateCampaignStrength(old, catalogue);
  assert.equal(armyTroops(upgraded.armies[0]), 45);
  assert.equal(upgraded.armies[0].units[0].attack, 8);
  assert.equal(upgraded.armies[0].units[0].defense, 7);
  assert.ok(Number.isFinite(campaignArmyPower(upgraded.armies[0])));
  assert.equal(migrateCampaignStrength(upgraded, [{ ...type, attack: 50 }]), upgraded);
});

test('strategy observes only detected enemies and requires defending a visible invader', () => {
  const remote = CAMPAIGN_HEXES.find((hex) => hex.land && hexDistance(hex.id, pair.id) > 10);
  const campaign = state([army(1, 'hatti', pair.id), army(2, 'nubia', other.id), army(3, 'egypt', remote.id)]);
  const context = movementContext(campaign, 'hatti');
  assert.equal(context.priority, 'DEFEND');
  assert.equal(context.invaders.length, 1);
  assert.equal(context.invaders[0].unitCount, 2);
  assert.equal(context.invaders[0].troops, undefined);
  assert.ok(!JSON.stringify(context).includes(remote.id));
  assert.ok(context.options.every((option) => !['RAID', 'CONQUER'].includes(option.intent)));
  assert.throws(() => storeMovementDecision(campaign, 'hatti', choose(context, 'HOLD')), /INVASION/);
  const ordered = storeMovementDecision(campaign, 'hatti', choose(context, 'DEFEND'));
  const attacked = executeMovementOrder(ordered, 'hatti');
  assert.equal(attacked.pendingEncounter.defenderId, 2);
  assert.equal(attacked.armies[0].hexId, pair.id);
  assert.equal(nextSeason(attacked), attacked);
  assert.equal(remainingMovement(attacked.armies[0]), 0);
});

test('invaders reveal formation counts throughout national territory', () => {
  const distant = CAMPAIGN_HEXES.find((hex) => hex.land && hexDistance(pair.id, hex.id) === 2 && hex.territory === 'hatti');
  const context = movementContext(state([army(1, 'hatti', pair.id), army(2, 'nubia', distant.id)]), 'hatti');
  assert.equal(context.invaders[0].unitCount, 2);
  assert.equal(context.invaders[0].morale, undefined);
});

test('AI recruitment and strategy detect distant national invaders even without nearby defenders', () => {
  const far = CAMPAIGN_HEXES.find((hex) => hex.territory === 'hatti' && hexDistance(hex.id, pair.id) > 4);
  const campaign = initializeCampaignAI(state([army(1, 'hatti', pair.id), army(2, 'nubia', far.id)]));
  const context = movementContext(campaign, 'hatti');
  assert.equal(context.priority, 'DEFEND');
  assert.equal(context.invaders[0].id, 2);
  assert.equal(context.invaders[0].unitCount, 2);
  assert.ok(context.options.some((option) => option.intent === 'DEFEND' && option.targetArmyId === 2));
  assert.equal(recruitmentCapacity(campaign, 'hatti', [type]).visibleInvaders, 1);
  const withoutDefenders = { ...campaign, armies: campaign.armies.filter((army) => army.id === 2) };
  assert.equal(movementContext(withoutDefenders, 'hatti').invaders.length, 1);
  assert.equal(recruitmentCapacity(withoutDefenders, 'hatti', [type]).visibleInvaders, 1);
});

test('orders are complete, unique, legal and processed once across saved campaigns', () => {
  const campaign = state([army(1, 'hatti', pair.id), army(2, 'hatti', other.id)]);
  const context = movementContext(campaign, 'hatti');
  const orders = choose(context, 'HOLD');
  assert.throws(() => storeMovementDecision(campaign, 'hatti', { ...orders, orders: orders.orders.slice(0, 1) }));
  assert.throws(() => storeMovementDecision(campaign, 'hatti', { ...orders, orders: [orders.orders[0], orders.orders[0]] }));
  assert.throws(() => storeMovementDecision(campaign, 'hatti', { ...orders, orders: [{ optionId: 'invented' }, orders.orders[1]] }));
  let current = executeMovementOrder(storeMovementDecision(campaign, 'hatti', orders), 'hatti');
  const saved = loadCampaign({ getItem: () => JSON.stringify(current) }, 'egypt', { fallbackToNew: false });
  assert.ok(saved);
  assert.equal(pendingMovementOrder(saved, 'hatti').armyId, 2);
  current = executeMovementOrder(saved, 'hatti');
  assert.equal(needsMovementDecision(current, 'hatti'), false);
  assert.equal(executeMovementOrder(current, 'hatti'), current);
  assert.deepEqual(current.armies, campaign.armies.map((army) => ({ ...army, campaignMission: { intent: 'HOLD' } })));
});

test('recover orders preserve casualties until normal seasonal recovery and difficult movement stays one hex', () => {
  const desert = CAMPAIGN_HEXES.find((hex) => hex.land && hex.terrain === 'desert' && hex.territory === 'hatti');
  let campaign = state([army(1, 'hatti', desert.id, { units: [{ ...type, strengths: [20, 30] }] })]);
  const recovery = choose(movementContext(campaign, 'hatti'), 'RECOVER');
  const recovering = executeMovementOrder(storeMovementDecision(campaign, 'hatti', recovery), 'hatti');
  assert.equal(armyTroops(recovering.armies[0]), 50);
  assert.equal(recovering.armies[0].hexId, desert.id);
  const context = movementContext(campaign, 'hatti');
  const moving = executeMovementOrder(storeMovementDecision(campaign, 'hatti', choose(context, 'CONQUER')), 'hatti');
  assert.equal(hexDistance(moving.armies[0].hexId, desert.id), 1);
  assert.equal(remainingMovement(moving.armies[0]), 0);
});

test('arriving at a rival city starts a raid or an assault and continuing preserves its progress', () => {
  const city = CAMPAIGN_CITIES.find((city) => city.nation === 'egypt');
  for (const intent of ['RAID', 'CONQUER']) {
    let campaign = state([army(1, 'hatti', city.hexId)]);
    campaign = executeMovementOrder(storeMovementDecision(campaign, 'hatti', choose(movementContext(campaign, 'hatti'), intent)), 'hatti');
    if (intent === 'RAID') assert.equal(campaign.cityRaids[city.id].nation, 'hatti');
    else {
      assert.equal(campaign.armies[0].cityAction.cityId, city.id);
      const advanced = nextSeason(campaign);
      const continued = executeMovementOrder(storeMovementDecision(advanced, 'hatti', choose(movementContext(advanced, 'hatti'), 'CONTINUE')), 'hatti');
      assert.deepEqual(continued.armies[0].cityAction, advanced.armies[0].cityAction);
    }
  }
});

test('automatic AI combat uses force and morale, reports casualties and forces a legal retreat', () => {
  const powerful = army(1, 'hatti', pair.id, { units: [{ ...type, quantity: 10, strengths: Array(10).fill(60) }] });
  const weak = army(2, 'nubia', other.id);
  assert.ok(campaignArmyPower(powerful) > campaignArmyPower(weak));
  const initial = engageArmy(state([powerful, weak]), 1, 2, 'hatti');
  const result = resolveAIEncounter(initial);
  const report = result.campaignCombats.at(-1);
  assert.equal(report.winnerId, 1);
  assert.ok(report.winnerLosses > 0 && report.loserLosses > 0);
  assert.equal(result.armies.find((army) => army.id === 1).hexId, other.id);
  assert.ok(hexDistance(report.retreatHexId, other.id) >= 2);
  assert.ok(HEX_BY_ID.get(report.retreatHexId).land);
  assert.equal(new Set(result.armies.map((army) => army.hexId)).size, result.armies.length);
  assert.equal(armyTroops(result.armies.find((army) => army.id === 1)), 600 - report.winnerLosses);
  assert.equal(armyTroops(result.armies.find((army) => army.id === 2)), 120 - report.loserLosses);
  assert.equal(result.pendingEncounter, null);
  assert.equal(resolveAIEncounter(result), result);
  assert.ok(loadCampaign({ getItem: () => JSON.stringify(result) }, 'egypt', { fallbackToNew: false }));
});

test('human encounters cannot be autoresolved; tactical survivors map back to their exact formations', () => {
  const initial = engageArmy(state([army(1, 'egypt', pair.id, { units: [{ ...type, strengths: [42, 0] }] }), army(2, 'hatti', other.id)]), 1, 2);
  assert.throws(() => resolveAIEncounter(initial), /TWO_AI/);
  const battle = { id: '9', status: 'FINISHED', campaign: { gameId: 'test', encounterId: initial.pendingEncounter.id }, outcome: { winnerArmyId: '101' }, armies: [{ id: '101', campaignArmyId: 1, units: [{ campaignSlot: 'LIGHT_INFANTRY:0', currentStrength: 30, morale: 70, active: true }] }] };
  const result = applyEncounterResult(initial, battle, 'test');
  assert.equal(result.armies.length, 1);
  assert.deepEqual(result.armies[0].units[0].strengths, [30, 0]);
  assert.equal(result.armies[0].morale, 70);
  assert.equal(result.armies[0].hexId, other.id);
  assert.equal(result.pendingEncounter, null);
  assert.throws(() => applyEncounterResult(initial, battle, 'different'));
  assert.throws(() => applyEncounterResult(initial, { ...battle, status: 'IN_PROGRESS' }, 'test'));
  battle.armies[0].units[0].currentStrength = 43;
  assert.throws(() => applyEncounterResult(initial, battle, 'test'), /STRENGTH/);
});

test('a stronger defender holds its hex and trapped losers cannot remain stacked or cross occupied hexes', () => {
  const weak = army(1, 'hatti', pair.id);
  const strong = army(2, 'nubia', other.id, { units: [{ ...type, quantity: 10, strengths: Array(10).fill(60) }] });
  const blockade = neighbors(pair.id).filter((hex) => hex.id !== other.id).map((hex, index) => army(index + 3, 'nubia', hex.id));
  const result = resolveAIEncounter(engageArmy(state([weak, strong, ...blockade]), 1, 2, 'hatti'));
  assert.equal(result.campaignCombats[0].winnerId, 2);
  assert.equal(result.campaignCombats[0].retreatHexId, null);
  assert.equal(result.campaignCombats[0].loserLosses, 120);
  assert.equal(result.armies.find((army) => army.id === 1), undefined);
  assert.equal(result.armies.find((army) => army.id === 2).hexId, other.id);
});

test('even a one-troop victorious army retains a survivor', () => {
  const strong = army(1, 'hatti', pair.id, { units: [{ ...type, quantity: 1, strengths: [1], attack: 10000, defense: 10000, damage: 10000 }] });
  const weak = army(2, 'nubia', other.id, { units: [{ ...type, quantity: 1, strengths: [1] }] });
  const result = resolveAIEncounter(engageArmy(state([strong, weak]), 1, 2, 'hatti'));
  assert.equal(armyTroops(result.armies.find((army) => army.id === 1)), 1);
  assert.equal(result.campaignCombats[0].winnerLosses, 0);
});

test('a finished encounter with the defender winning keeps its position and removes the attacker', () => {
  const initial = engageArmy(state([army(1, 'egypt', pair.id), army(2, 'hatti', other.id)]), 1, 2);
  const battle = { status: 'FINISHED', campaign: { gameId: 'test', encounterId: initial.pendingEncounter.id }, outcome: { winnerArmyId: '102' }, armies: [{ id: '102', campaignArmyId: 2, units: [0, 1].map((slot) => ({ campaignSlot: `LIGHT_INFANTRY:${slot}`, currentStrength: 20, morale: 80, active: true })) }] };
  const result = applyEncounterResult(initial, battle, 'test');
  assert.equal(result.armies[0].id, 2);
  assert.equal(result.armies[0].hexId, other.id);
});

test('pending battles survive saves and malformed or nonadjacent encounters are rejected', () => {
  const initial = engageArmy(state([army(1, 'egypt', pair.id), army(2, 'hatti', other.id)]), 1, 2);
  assert.ok(loadCampaign({ getItem: () => JSON.stringify(initial) }, 'egypt', { fallbackToNew: false }));
  initial.pendingEncounter.attackerId = 300;
  assert.equal(loadCampaign({ getItem: () => JSON.stringify(initial) }, 'egypt', { fallbackToNew: false }), null);
});

test('fast raid recruitment options are affordable and preserve their chosen mission', () => {
  const catalogue = [{ ...type, speed: 2 }, { ...type, code: 'SPEARMEN', speed: 1 }];
  const campaign = initializeCampaignAI(newCampaign());
  const context = recruitmentCapacity(campaign, 'hatti', catalogue);
  const raid = context.options.find((option) => option.id === 'raid');
  assert.ok(raid && raid.cost <= context.reserve);
  assert.deepEqual(Object.keys(raid.quantities), ['LIGHT_INFANTRY']);
  const recruited = applyRecruitmentDecision(campaign, 'hatti', { action: 'recruit', optionId: 'raid', quantities: raid.quantities, reason: 'Saquear' }, catalogue);
  assert.equal(recruited.armies[0].campaignMission.intent, 'RAID');
});

test('lost original regions are known under fog and drive recruitment and reconquest without exposing garrisons', () => {
  const capital = CAMPAIGN_CITIES.find((city) => city.nation === 'egypt' && city.capital);
  const lost = CAMPAIGN_CITIES.find((city) => city.id === 'egypt-6');
  const campaign = initializeCampaignAI({ ...state([army(1, 'egypt', capital.hexId), army(2, 'nubia', lost.hexId)], 'hatti'), cityOwners: { [lost.id]: 'nubia' } });
  const context = movementContext(campaign, 'egypt');
  assert.equal(context.priority, 'RECLAIM');
  assert.equal(context.occupiedRegions[0].originalOwner, 'egypt');
  assert.equal(context.occupiedRegions[0].occupiedBy, 'nubia');
  assert.deepEqual(context.invaders, []);
  assert.equal(context.armies.length, 1);
  assert.ok(context.options.some((option) => option.intent === 'RECLAIM' && option.cityId === lost.id));
  assert.ok(context.options.every((option) => !['RAID', 'CONQUER'].includes(option.intent)));
  assert.equal(recruitmentCapacity(campaign, 'egypt', [type]).occupiedRegions[0].cityId, lost.id);
  assert.throws(() => storeMovementDecision(campaign, 'egypt', choose(context, 'HOLD')), /OCCUPIED_TERRITORY/);
  const ordered = storeMovementDecision(campaign, 'egypt', choose(context, 'RECLAIM'));
  const moved = executeMovementOrder(ordered, 'egypt');
  assert.equal(moved.armies[0].campaignMission.intent, 'RECLAIM');
  assert.ok(loadCampaign({ getItem: () => JSON.stringify(moved) }, 'hatti', { fallbackToNew: false }));
});

test('invaders still take priority over reclaiming occupied cities', () => {
  const lost = CAMPAIGN_CITIES.find((city) => city.nation === 'hatti' && ![pair.regionId, other.regionId].includes(city.id));
  const campaign = { ...state([army(1, 'hatti', pair.id), army(2, 'nubia', other.id)]), cityOwners: { [lost.id]: 'nubia' } };
  const context = movementContext(campaign, 'hatti');
  assert.equal(context.priority, 'DEFEND');
  assert.equal(context.occupiedRegions.length, 1);
  assert.ok(!context.options.some((option) => option.intent === 'RECLAIM'));
});

test('reconquest prioritizes the original capital and restores an entire region through the existing assault rules', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const cities = CAMPAIGN_CITIES.filter((city) => city.nation === nation);
    const capital = cities.find((city) => city.capital);
    const rival = nation === 'nubia' ? 'egypt' : 'nubia';
    let campaign = { ...state([army(1, nation, capital.hexId, { units: [{ ...type, quantity: 50, strengths: Array(50).fill(60) }] })], nation === 'hatti' ? 'egypt' : 'hatti'), cityOwners: Object.fromEntries(cities.map((city) => [city.id, rival])) };
    const context = movementContext(campaign, nation);
    assert.equal(context.options.find((option) => option.intent === 'RECLAIM').cityId, capital.id);
    campaign = executeMovementOrder(storeMovementDecision(campaign, nation, choose(context, 'RECLAIM')), nation);
    assert.equal(campaign.armies[0].cityAction.cityId, capital.id);
    campaign = nextSeason(campaign);
    assert.equal(campaign.cityOwners[capital.id], nation);
    assert.equal(campaignTerritoryInfo(campaign, HEX_BY_ID.get(capital.hexId)).occupied, false);
    assert.equal(movementContext(campaign, nation).occupiedRegions.some((region) => region.cityId === capital.id), false);
  }
});

test('winning an AI battle on a city under occupation starts the reconquest siege', () => {
  const city = CAMPAIGN_CITIES.find((city) => city.id === 'egypt-6');
  const attacker = army(1, 'egypt', neighbors(city.hexId)[0].id, { campaignMission: { intent: 'RECLAIM', targetCityId: city.id }, units: [{ ...type, quantity: 50, strengths: Array(50).fill(60) }] });
  const defender = army(2, 'nubia', city.hexId);
  const campaign = { ...state([attacker, defender], 'hatti'), cityOwners: { [city.id]: 'nubia' } };
  const result = resolveAIEncounter(engageArmy(campaign, 1, 2, 'egypt'));
  const survivor = result.armies.find((army) => army.id === 1);
  assert.equal(survivor.cityAction?.type, 'assault');
  assert.equal(survivor.cityAction?.cityId, city.id);
  assert.equal(result.cityOwners[city.id], 'nubia');
});
