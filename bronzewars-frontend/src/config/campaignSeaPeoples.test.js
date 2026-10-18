import assert from 'node:assert/strict';
import { test } from 'node:test';
import { advanceSeaInvasions, invasionCoasts, invasionRoster, validSeaPeoples, INVASION_ARMY_BUDGET } from './campaignSeaPeoples.js';
import { CAMPAIGN_CITIES, HEX_BY_ID, PLAYABLE_NATIONS, armyTroops, campaignProduction, campaignTerritory, deploymentHexes, loadCampaign, newCampaign, nextSeason } from './campaignRules.js';
import { campaignCapital, cityOwner, startCityAction } from './campaignCityActions.js';
import { initializeCampaignAI, rivalNations, recruitmentCapacity, automaticRecruitmentDecision, applyRecruitmentDecision } from './campaignAI.js';
import { campaignView, hexDistance } from './campaignVisibility.js';
import { movementContext, needsMovementDecision, storeMovementDecision, executeMovementOrder } from './campaignMovement.js';

const catalogue = [
  { code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 6, attack: 5, defense: 3, damage: 5 },
  { code: 'SPEARMEN', initialStrength: 100, speed: 1, grainCost: 8, attack: 6, defense: 6, damage: 7 },
  { code: 'ARCHERS', initialStrength: 60, speed: 2, grainCost: 7, attack: 4, defense: 2, damage: 5 },
  { code: 'HEAVY_INFANTRY', initialStrength: 100, speed: 1, grainCost: 10, attack: 6, defense: 6, damage: 9 },
];
const advance = (state, random = () => 0) => advanceSeaInvasions(state, catalogue, { random });
const restore = (state) => loadCampaign({ getItem: () => JSON.stringify(state) }, 'egypt', { fallbackToNew: false });
function wave(random = () => 0) {
  const state = advance(newCampaign(), random);
  return advance({ ...state, turn: state.seaPeoples.nextInvasionTurn }, random);
}

test('first invasions and subsequent waves are scheduled 2–10 years apart, without making Sea Peoples playable', () => {
  assert.equal(PLAYABLE_NATIONS.includes('seapeople'), false);
  for (const [random, interval, count] of [[() => 0, 6, 1], [() => 0.999, 30, 3]]) {
    const state = advance(newCampaign(), random);
    assert.equal(state.seaPeoples.nextInvasionTurn, interval);
    assert.equal(state.seaPeoples.ships.length, 0);
    assert.equal(rivalNations(state).includes('seapeople'), false);
    const invaded = advance({ ...state, turn: interval }, random);
    assert.equal(invaded.seaPeoples.nextInvasionTurn, interval * 2);
    assert.equal(invaded.seaPeoples.ships.length, count);
    assert.equal(new Set(invaded.seaPeoples.ships.map((ship) => ship.targetHexId)).size, count);
    assert.ok(rivalNations(invaded).includes('seapeople'));
    assert.equal(advance(invaded, random), invaded);
    assert.deepEqual(restore(invaded), invaded);
  }
});

test('each ship carries at least four national divisions costing no more than 50 grain', () => {
  for (let index = 0; index < 100; index += 1) {
    const units = invasionRoster(catalogue, () => index / 100);
    assert.ok(units.reduce((sum, unit) => sum + unit.quantity, 0) >= 4);
    assert.ok(units.reduce((sum, unit) => sum + unit.quantity * unit.grainCost, 0) <= INVASION_ARMY_BUDGET);
    assert.ok(units.every((unit) => unit.strengths.every((strength) => strength === unit.initialStrength)));
  }
  assert.deepEqual(invasionRoster([{ ...catalogue[0], grainCost: 13 }]), []);
});

test('ships travel through Mediterranean water and land once without duplicating armies on reload', () => {
  let state = wave(() => 0.5);
  const ids = state.seaPeoples.ships.map((ship) => ship.army.id);
  const { sea, coasts } = invasionCoasts();
  const initial = state.seaPeoples.ships.map((ship) => ship.hexId);
  state = advance({ ...state, turn: state.turn + 1 }, () => 0.5);
  assert.ok(state.armies.length || state.seaPeoples.ships.some((ship, index) => ship.hexId !== initial[index]));
  for (let turn = 0; turn < 6 && state.seaPeoples.ships.length; turn += 1) {
    assert.ok(state.seaPeoples.ships.every((ship) => sea.has(ship.hexId)));
    assert.deepEqual(restore(state), state);
    state = advance({ ...restore(state), turn: state.turn + 1 }, () => 0.5);
  }
  assert.equal(state.seaPeoples.ships.length, 0);
  assert.deepEqual(state.armies.map((army) => army.id).sort(), ids.sort());
  assert.ok(state.armies.every((army) => coasts.some((hex) => hex.id === army.hexId) && army.moved > 0 && army.designId === 'seapeople'));
  assert.equal(new Set(state.armies.map((army) => army.hexId)).size, ids.length);
  assert.ok(state.armies.every((army) => armyTroops(army) > 0));
  const justLanded = state.aiMovement.seapeople.processed;
  assert.ok(justLanded.length > 0);
  assert.ok(movementContext(state, 'seapeople').armies.every((army) => !justLanded.includes(army.id)));
  assert.equal(needsMovementDecision(nextSeason(initializeCampaignAI(state)), 'seapeople'), true);
  assert.deepEqual(restore(state), state);
});

test('occupied landing sites are retargeted without overwriting friendly or enemy armies', () => {
  let state = wave();
  const ship = state.seaPeoples.ships[0];
  const blocker = { ...ship.army, id: state.nextArmyId, designId: 'egypt', name: 'Guard', hexId: ship.targetHexId };
  state = { ...state, armies: [blocker], nextArmyId: state.nextArmyId + 1 };
  for (let turn = 0; turn < 7 && state.seaPeoples.ships.length; turn += 1) state = advance({ ...state, turn: state.turn + 1 });
  assert.equal(state.seaPeoples.ships.length, 0);
  assert.equal(state.armies.length, 2);
  assert.equal(state.armies.find((army) => army.id === blocker.id).hexId, blocker.hexId);
  assert.notEqual(state.armies.find((army) => army.designId === 'seapeople').hexId, blocker.hexId);
  assert.ok(restore(state));
});

test('fog hides distant ships and observations never expose embarked armies or destinations', () => {
  const state = wave();
  assert.equal(campaignView(state).ships.length, 0);
  const revealed = campaignView(state, 'egypt', { reveal: true }).ships;
  assert.equal(revealed.length, 1);
  assert.deepEqual(Object.keys(revealed[0]).sort(), ['designId', 'hexId', 'id']);
  const ship = state.seaPeoples.ships[0];
  const coastal = invasionCoasts().coasts[0];
  const water = [...invasionCoasts().sea].find((id) => hexDistance(coastal.id, id) === 1);
  const observer = { ...ship.army, designId: 'egypt', hexId: coastal.id };
  const visible = { ...state, armies: [observer], seaPeoples: { ...state.seaPeoples, ships: [{ ...ship, hexId: water }] } };
  assert.equal(campaignView(visible).ships.length, 1);
});

test('the first conquered city becomes the founding capital, with ordinary harvest, recruitment and regional control', () => {
  let state = initializeCampaignAI(wave());
  const city = CAMPAIGN_CITIES.find((entry) => entry.id === 'hatti-2');
  const cargo = state.seaPeoples.ships[0].army;
  const units = [{ ...catalogue[1], quantity: 10, strengths: Array(10).fill(100) }];
  state = { ...state, armies: [{ ...cargo, hexId: city.hexId, units }], seaPeoples: { ...state.seaPeoples, ships: [] } };
  assert.equal(campaignCapital(state, 'seapeople'), null);
  assert.equal(automaticRecruitmentDecision(recruitmentCapacity(state, 'seapeople', catalogue)).blockReason, 'NO_CAPITAL');
  state = startCityAction(state, cargo.id, 'assault', 'seapeople');
  assert.equal(state.armies[0].cityAction.turnsRequired, 3);
  for (let index = 0; index < 3; index += 1) state = nextSeason(state);
  assert.equal(cityOwner(state, city), 'seapeople');
  assert.equal(state.seaPeoples.capitalCityId, city.id);
  assert.equal(campaignCapital(state, 'seapeople').id, city.id);
  assert.equal(campaignProduction(state, 'seapeople'), city.grain / 2);
  assert.equal(campaignTerritory(state, HEX_BY_ID.get(city.hexId)), 'seapeople');
  assert.ok(deploymentHexes({ ...state, nation: 'seapeople' }).length);
  const richer = CAMPAIGN_CITIES.find((entry) => entry.grain > city.grain && entry.id !== city.id);
  state.cityOwners[richer.id] = 'seapeople';
  assert.equal(campaignCapital(state, 'seapeople').id, city.id);
  const lost = { ...state, cityOwners: { ...state.cityOwners, [city.id]: city.nation } };
  assert.equal(campaignCapital(lost, 'seapeople').id, richer.id);
  assert.equal(campaignCapital(state, 'seapeople').id, city.id);
  // A small existing garrison permits the normal four-division recruitment gate.
  state.armies[0].units = [{ ...catalogue[0], quantity: 1, strengths: [30] }];
  state.foreignGrain.seapeople = 100;
  const capacity = recruitmentCapacity(state, 'seapeople', catalogue);
  assert.equal(automaticRecruitmentDecision(capacity), null);
  const recruited = applyRecruitmentDecision(state, 'seapeople', { action: 'recruit', quantities: { LIGHT_INFANTRY: 4 }, reason: 'Defensa' }, catalogue);
  assert.equal(recruited.armies.length, 2);
  assert.equal(recruited.foreignGrain.seapeople, 76);
  assert.ok(restore(recruited));
  const atHarvest = { ...state, turn: 2 };
  assert.equal(nextSeason(atHarvest).foreignGrain.seapeople, Math.ceil(100 + campaignProduction(atHarvest, 'seapeople') - 0.3));
});

test('landed armies use the ordinary strategy options and can assault a coastal city', () => {
  let state = initializeCampaignAI(wave());
  const city = CAMPAIGN_CITIES.find((entry) => entry.id === 'hatti-2');
  const army = { ...state.seaPeoples.ships[0].army, hexId: city.hexId, moved: 0 };
  state = { ...state, armies: [army], seaPeoples: { ...state.seaPeoples, ships: [] } };
  assert.equal(needsMovementDecision(state, 'seapeople'), true);
  const context = movementContext(state, 'seapeople');
  assert.equal(context.objective, 'CONQUER_FIRST_CAPITAL');
  const option = context.options.find((entry) => entry.intent === 'CONQUER' && entry.cityId === city.id);
  assert.ok(option);
  state = storeMovementDecision(state, 'seapeople', { orders: [{ optionId: option.id }], reason: 'Establecer capital' });
  state = executeMovementOrder(state, 'seapeople');
  assert.equal(state.armies[0].cityAction.type, 'assault');
  assert.ok(restore(state));
});

test('fleet saves reject impossible routes, excessive cargo, reused IDs and invalid capitals', () => {
  const original = wave();
  for (const mutate of [
    (state) => { state.seaPeoples.ships[0].hexId = '8,30'; },
    (state) => { state.seaPeoples.ships[0].army.units[0].grainCost = 100; },
    (state) => { state.seaPeoples.ships[0].army.id = state.nextArmyId; },
    (state) => { state.seaPeoples.capitalCityId = 'unknown'; },
    (state) => { state.seaPeoples.lastProcessedTurn = state.turn + 1; },
  ]) {
    const invalid = structuredClone(original); mutate(invalid);
    assert.equal(validSeaPeoples(invalid), false);
    assert.equal(restore(invalid), null);
  }
});
