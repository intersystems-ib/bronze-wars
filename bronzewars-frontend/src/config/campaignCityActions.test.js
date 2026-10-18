import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_CITIES, HEX_BY_ID, newCampaign, nextSeason, campaignProduction, campaignTerritory, armyTroops, moveArmy, reachableHexes, findSpawn, loadCampaign } from './campaignRules.js';
import { campaignView } from './campaignVisibility.js';
import { assaultDuration, startCityAction, cancelCityAction, cityOwner, cityIncomeNation, cityRaid, nationGrain } from './campaignCityActions.js';
import { createCampaignSave, writeCampaignSave, readCampaignSave } from './campaignSaves.js';

const target = CAMPAIGN_CITIES.find((city) => city.id === 'egypt-6');
function stationed(troops = 1000, nation = 'nubia', city = target) {
  const strengths = Array.from({ length: Math.ceil(troops / 100) }, (_, index) => Math.min(100, troops - index * 100));
  return { ...newCampaign(nation), grain: 10000, nextArmyId: 2, armies: [{ id: 1, name: 'Invaders', designId: nation,
    hexId: city.hexId, moved: 0, morale: 100,
    units: [{ code: 'SPEARMEN', quantity: strengths.length, initialStrength: 100, strengths, speed: 2, grainCost: 1 }] }] };
}
const advance = (state) => nextSeason(state);

test('assault duration follows the initial troop force: 1000 take 3 turns, 500 take 6', () => {
  for (const [troops, turns] of [[3000, 1], [1000, 3], [500, 6], [750, 4], [999, 4], [1, 3000]]) {
    assert.equal(assaultDuration(stationed(troops).armies[0]), turns);
  }
  assert.equal(assaultDuration({ units: [{ strengths: [0] }] }), Infinity);
});

test('actions require a living army on an enemy city, and only the controlling nation may order it', () => {
  const state = stationed();
  assert.equal(startCityAction(state, 99, 'assault'), state);
  assert.equal(startCityAction(state, 1, 'unknown'), state);
  assert.equal(startCityAction(state, 1, 'raid', 'hatti'), state);
  const friendly = stationed(1000, 'egypt');
  assert.equal(startCityAction(friendly, 1, 'raid'), friendly);
  const empty = { ...state, armies: [{ ...state.armies[0], hexId: '8,31' }] };
  assert.equal(startCityAction(empty, 1, 'assault'), empty);
  const legacy = { ...state, version: 1 };
  assert.equal(startCityAction(legacy, 1, 'raid'), legacy);
});

test('raiding transfers one grain haul immediately and disables the city harvest for the whole year', () => {
  const state = stationed();
  const raided = startCityAction(state, 1, 'raid');
  assert.equal(raided.grain, state.grain + target.grain);
  assert.equal(cityOwner(raided, target), 'egypt');
  assert.equal(cityIncomeNation(raided, target), null);
  assert.equal(campaignProduction(raided, 'egypt'), 31 - target.grain);
  assert.equal(campaignProduction(raided, 'nubia'), 20);
  assert.equal(startCityAction(raided, 1, 'raid'), raided);
  const otherArmy = { ...raided, nextArmyId: 3, armies: [{ ...raided.armies[0], id: 2 }] };
  assert.equal(startCityAction(otherArmy, 2, 'raid'), otherArmy);
  assert.equal(reachableHexes(raided, 1).size, 0);
  const renewed = advance(raided);
  const moved = moveArmy(renewed, 1, reachableHexes(renewed, 1).keys().next().value);
  assert.notEqual(moved.armies[0].hexId, target.hexId);
  assert.ok(cityRaid(moved, target));
  assert.equal(campaignProduction(moved, 'egypt'), 26);
  const afterHarvest = advance(advance(moved));
  assert.equal(afterHarvest.turn, 3);
  assert.equal(cityRaid(afterHarvest, target), null);
  assert.equal(campaignProduction(afterHarvest, 'egypt'), 31);
  const returned = { ...afterHarvest, armies: [{ ...afterHarvest.armies[0], hexId: target.hexId }] };
  assert.equal(startCityAction(returned, 1, 'raid').grain, returned.grain + target.grain);
});

test('a looted city provides no harvest even if its owner recovers or captures the city', () => {
  let state = startCityAction(stationed(3000), 1, 'raid');
  state = { ...state, turn: 2 };
  state = startCityAction(state, 1, 'assault');
  const captured = advance(state);
  assert.equal(cityOwner(captured, target), 'nubia');
  assert.equal(captured.lastTurnReport.producedGrain, 20);
  assert.equal(campaignProduction(captured, 'nubia'), 25); // New year: city harvest resumes.
});

test('assault takes exactly 3 turns at 1000 troops despite casualties, with no abundance recovery', () => {
  let state = startCityAction(stationed(), 1, 'assault');
  assert.equal(armyTroops(state.armies[0]), 1000);
  assert.equal(state.armies[0].cityAction.turnsRequired, 3);
  assert.equal(reachableHexes(state, 1).size, 0);
  assert.equal(startCityAction(state, 1, 'assault'), state);
  for (const [index, force, losses] of [[1, 950, 50], [2, 902, 48], [3, 856, 46]]) {
    state = advance(state);
    assert.equal(armyTroops(state.armies[0]), force);
    assert.equal(state.lastTurnReport.armies[0].assaultLosses, losses);
    assert.equal(state.lastTurnReport.armies[0].recoveredUnits, 0);
    if (index < 3) {
      assert.equal(cityOwner(state, target), 'egypt');
      assert.equal(state.armies[0].cityAction.turnsElapsed, index);
      assert.equal(state.armies[0].cityAction.turnsRequired, 3);
    }
  }
  assert.equal(cityOwner(state, target), 'nubia');
  assert.equal(state.armies[0].cityAction, undefined);
  assert.equal(state.lastTurnReport.producedGrain, 25);
  assert.equal(state.lastTurnReport.armies[0].capturedCityId, target.id);
  assert.equal(campaignProduction(state, 'egypt'), 26);
});

test('500 troops take 6 turns and assault losses round up once per army each turn', () => {
  let state = startCityAction(stationed(500), 1, 'assault');
  let force = 500;
  for (let turn = 1; turn <= 6; turn += 1) {
    const losses = Math.ceil(force * .05);
    state = advance(state);
    force -= losses;
    assert.equal(state.lastTurnReport.armies[0].assaultLosses, losses);
    assert.equal(armyTroops(state.armies[0]), force);
    assert.equal(cityOwner(state, target), turn < 6 ? 'egypt' : 'nubia');
  }
});

test('leaving or cancelling an assault loses its progress and never refunds spent movement', () => {
  const begun = startCityAction(stationed(), 1, 'assault');
  const cancelled = cancelCityAction(begun, 1);
  assert.equal(cancelled.armies[0].cityAction, undefined);
  assert.equal(reachableHexes(cancelled, 1).size, 0);
  const progressed = advance(begun);
  const moved = moveArmy(progressed, 1, reachableHexes(progressed, 1).keys().next().value);
  assert.equal(moved.armies[0].cityAction, undefined);
  assert.equal(cityOwner(moved, target), 'egypt');
  assert.equal(cancelCityAction(begun, 1, 'egypt'), begun);
});

test('a destroyed attacking army never captures the city or recovers through abundance', () => {
  const desertCity = CAMPAIGN_CITIES.find((city) => HEX_BY_ID.get(city.hexId).terrain === 'desert');
  const state = startCityAction(stationed(1, 'egypt', desertCity), 1, 'assault');
  const next = advance(state);
  assert.equal(next.armies.length, 0);
  assert.equal(cityOwner(next, desertCity), desertCity.nation);
  assert.equal(next.lastTurnReport.armies[0].destroyed, true);
});

test('capture changes the city hex ownership and vision without mutating other games or the map', () => {
  const city = CAMPAIGN_CITIES.find((entry) => entry.id === 'hatti-1');
  const baseline = stationed(3000, 'egypt', city);
  let conquered = advance(startCityAction(baseline, 1, 'assault'));
  conquered = { ...conquered, armies: [] };
  assert.equal(campaignTerritory(conquered, HEX_BY_ID.get(city.hexId)), 'egypt');
  assert.equal(campaignView(conquered, 'egypt').visibleHexIds.has(city.hexId), true);
  assert.equal(campaignView(conquered, 'hatti').visibleHexIds.has(city.hexId), false);
  assert.equal(cityOwner(baseline, city), 'hatti');
  assert.equal(HEX_BY_ID.get(city.hexId).territory, 'hatti');
  const defeatedOwner = { ...conquered, nation: 'hatti' };
  assert.equal(findSpawn(defeatedOwner), null);
  assert.notEqual(findSpawn(conquered), city.hexId);
});

test('enemy AI actions use the same rules: raids credit the enemy and assaults capture player cities', () => {
  let state = { ...stationed(1000, 'hatti'), nation: 'egypt' };
  assert.equal(startCityAction(state, 1, 'raid'), state);
  const raided = startCityAction(state, 1, 'raid', 'hatti');
  assert.equal(raided.grain, state.grain);
  assert.equal(nationGrain(raided, 'hatti'), target.grain);
  assert.equal(campaignProduction(raided), 26);
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(raided) }), raided);
  state = startCityAction(state, 1, 'assault', 'hatti');
  for (let turn = 0; turn < 3; turn += 1) state = advance(state);
  assert.equal(cityOwner(state, target), 'hatti');
  assert.equal(armyTroops(state.armies[0]), 856);
  assert.equal(state.lastTurnReport.armies.length, 0); // No hidden enemy forces in player reports.
  assert.deepEqual(state.lastTurnReport.capturedCities, [{ cityId: target.id, previousOwner: 'egypt', newOwner: 'hatti' }]);
});

test('Sea Peoples can raid but cannot gain permanent territory', () => {
  const state = { ...stationed(1000, 'seapeople'), nation: 'egypt' };
  assert.equal(startCityAction(state, 1, 'assault', 'seapeople'), state);
  const raided = startCityAction(state, 1, 'raid', 'seapeople');
  assert.equal(nationGrain(raided, 'seapeople'), target.grain);
  assert.equal(cityOwner(raided, target), 'egypt');
});

test('save/load preserves annual raid markers, siege progress and ownership; malformed actions are rejected', () => {
  let state = startCityAction(stationed(), 1, 'raid');
  state = advance(startCityAction(state, 1, 'assault'));
  const data = new Map();
  const storage = { getItem: (key) => data.get(key) ?? null, setItem: (key, value) => data.set(key, value) };
  const record = createCampaignSave(storage, 'nubia');
  const saved = writeCampaignSave(storage, record, state);
  const restored = readCampaignSave(storage, record.id);
  assert.deepEqual(restored, saved);
  let finished = advance(advance(restored.campaign));
  assert.equal(cityOwner(finished, target), 'nubia');
  writeCampaignSave(storage, record, finished);
  assert.equal(cityOwner(readCampaignSave(storage, record.id).campaign, target), 'nubia');
  for (const invalid of [
    { ...state, cityOwners: { unknown: 'egypt' } },
    { ...state, cityOwners: { [target.id]: 'seapeople' } },
    { ...state, cityRaids: { [target.id]: { year: 100, nation: 'nubia' } } },
    { ...state, armies: [{ ...state.armies[0], cityAction: { ...state.armies[0].cityAction, turnsElapsed: -1 } }] },
    { ...state, armies: [{ ...state.armies[0], cityAction: { ...state.armies[0].cityAction, turnsRequired: 1 } }] },
  ]) {
    assert.equal(loadCampaign({ getItem: () => JSON.stringify(invalid) }, 'nubia', { fallbackToNew: false }), null);
  }
});
