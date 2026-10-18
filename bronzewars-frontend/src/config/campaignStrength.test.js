import assert from 'node:assert/strict';
import { test } from 'node:test';
import { LEGACY_HATTI_ID, normalizeFaction } from './nationIdentity.js';
import { CAMPAIGN_HEXES, HEX_BY_ID, PLAYABLE_NATIONS, availableGrain, campaignStorageKey, findSpawn, armyTroops, activeUnitCount, unitTroops, migrateCampaignStrength, armyMovement, armyUpkeep, campaignEconomy, campaignProduction, applyCasualties, recoverCasualties, loadCampaign, newCampaign, nextSeason, recruitArmy } from './campaignRules.js';

const catalogue = [
  { code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 6, attack: 4, defense: 2, damage: 5 },
  { code: 'SPEARMEN', initialStrength: 100, speed: 1, grainCost: 6, attack: 5, defense: 6, damage: 7 },
  { code: 'CHARIOTS', initialStrength: 15, speed: 3, grainCost: 25, attack: 6, defense: 4, damage: 18 },
];
// Existing/depleted rosters may be smaller than the new recruitment minimum.
function armyWith(quantities, terrain = 'fertile', grain = 1000) {
  const units = catalogue.filter((unit) => quantities[unit.code]).map((unit) => ({ ...unit, quantity: quantities[unit.code], strengths: Array(quantities[unit.code]).fill(unit.initialStrength) }));
  const cost = units.reduce((sum, unit) => sum + unit.quantity * unit.grainCost, 0);
  return { ...newCampaign(), grain: grain - cost, nextArmyId: 2, armies: [{ id: 1, name: 'Nile', designId: 'egypt', morale: 100, moved: 0, hexId: CAMPAIGN_HEXES.find((hex) => hex.terrain === terrain).id, units }] };
}
const settle = (state, production = 0) => nextSeason(state, { production });

test('troops are the combined force, while unit counters remain formation counts', () => {
  const state = armyWith({ CHARIOTS: 1, LIGHT_INFANTRY: 1 });
  assert.equal(armyTroops(state.armies[0]), 75);
  assert.equal(activeUnitCount(state.armies[0].units[0]), 1);
  assert.equal(activeUnitCount(state.armies[0].units[1]), 1);
  const larger = armyWith({ LIGHT_INFANTRY: 2, SPEARMEN: 3 });
  assert.equal(armyTroops(larger.armies[0]), 420);
});

test('3% wear on 75 troops kills ceil(2.25)=3 troops without deleting either formation', () => {
  const state = armyWith({ CHARIOTS: 1, LIGHT_INFANTRY: 1 }, 'desert');
  const next = settle(state);
  assert.equal(next.lastTurnReport.armies[0].terrainLosses, 3);
  assert.equal(armyTroops(next.armies[0]), 72);
  assert.deepEqual(next.armies[0].units.map(activeUnitCount), [1, 1]);
  assert.equal(armyTroops(state.armies[0]), 75);
});

test('5% famine losses are based on troops, including rounding up and multiple formations', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2 });
  state.grain = 0;
  const next = settle(state);
  assert.equal(next.lastTurnReport.armies[0].supplyLosses, 6);
  assert.equal(armyTroops(next.armies[0]), 114);
  assert.deepEqual(next.armies[0].units[0].strengths, [57,57]);
  assert.equal(activeUnitCount(next.armies[0].units[0]), 2);
  assert.equal(armyUpkeep(next.armies[0]), 1.2);
});

test('terrain and famine apply sequentially to surviving troop strength', () => {
  const state = armyWith({ CHARIOTS: 1, LIGHT_INFANTRY: 1 }, 'mountain');
  state.grain = 0;
  const next = settle(state);
  assert.equal(next.lastTurnReport.armies[0].terrainLosses, 3);
  assert.equal(next.lastTurnReport.armies[0].supplyLosses, 4);
  assert.equal(armyTroops(next.armies[0]), 68);
});

test('fractional losses are rounded once for the total army, not once per formation or type', () => {
  const units = [{ ...catalogue[0], quantity: 3, strengths: [1,1,1] }, { ...catalogue[2], quantity: 1, strengths: [1] }];
  const result = applyCasualties(units, 0.03);
  assert.equal(result.losses, 1);
  assert.equal(armyTroops({ units: result.units }), 3);
  assert.ok(result.units.every((unit) => unit.strengths.every((value) => value >= 0)));
});

test('individual formations only cease being deployed when their force reaches zero', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2, SPEARMEN: 1 });
  state.armies[0].units[0].strengths = [0,1];
  state.armies[0].units[1].strengths = [100];
  assert.equal(activeUnitCount(state.armies[0].units[0]), 1);
  assert.equal(armyTroops(state.armies[0]), 101);
  assert.equal(armyMovement(state.armies[0].units), 1.5);
  assert.equal(armyUpkeep(state.armies[0]), 1.2);
  const result = applyCasualties(state.armies[0].units, 1);
  assert.equal(result.losses, 101);
  assert.ok(result.units.every((unit) => activeUnitCount(unit) === 0));
});

test('abundance restores 5% of missing people and caps every individual unit at its own original force', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2, CHARIOTS: 1 });
  const units = state.armies[0].units;
  units[0].strengths = [20,50];
  units[1].strengths = [10];
  const result = recoverCasualties(units);
  assert.equal(result.recovered, 3); // ceil((40 + 10 + 5) × 0.05)
  assert.equal(armyTroops({ units: result.units }), 83);
  let restored = units;
  for (let turn = 0; turn < 150; turn += 1) restored = recoverCasualties(restored).units;
  assert.deepEqual(restored.map((unit) => unit.strengths), [[60,60],[15]]);
  assert.equal(recoverCasualties(restored).recovered, 0);
});

test('a depleted formation can recover a few people while another formation keeps the army alive', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2 });
  state.armies[0].units[0].strengths = [60,0];
  const next = settle(state, 100);
  assert.deepEqual(next.armies[0].units[0].strengths, [60,3]);
  assert.equal(next.lastTurnReport.armies[0].recoveredUnits, 3);
});

test('scarcity neither heals nor causes supply casualties, while terrain wear remains independent', () => {
  const state = armyWith({ LIGHT_INFANTRY: 1 });
  state.armies[0].units[0].strengths = [40];
  const next = settle(state);
  assert.equal(armyTroops(next.armies[0]), 40);
  assert.equal(next.lastTurnReport.armies[0].supplyLosses, 0);
  assert.equal(next.lastTurnReport.armies[0].recoveredUnits, 0);
  state.armies[0].hexId = CAMPAIGN_HEXES.find((hex) => hex.terrain === 'desert').id;
  assert.equal(armyTroops(settle(state).armies[0]), 38);
});

test('an army with no surviving people is removed and cannot be resurrected by abundance', () => {
  const state = armyWith({ LIGHT_INFANTRY: 1 }, 'desert');
  state.armies[0].units[0].strengths = [1];
  const next = settle(state, 100);
  assert.equal(next.armies.length, 0);
  assert.equal(next.lastTurnReport.armies[0].destroyed, true);
});

test('recruitment requires actual force profiles and records a separate force for every unit', () => {
  const base = newCampaign();
  const input = { name: 'Nile', designId: 'egypt', quantities: { LIGHT_INFANTRY: 4 } };
  const invalid = catalogue.map(({ initialStrength, ...unit }) => unit);
  assert.equal(recruitArmy(base, input, invalid), base);
  const next = recruitArmy(base, input, catalogue);
  assert.deepEqual(next.armies[0].units[0].strengths, [60,60,60,60]);
});

test('existing saves migrate national force profiles without losing date, grain, names or locations', () => {
  const state = armyWith({ CHARIOTS: 1, LIGHT_INFANTRY: 2 });
  state.version = 1;
  state.turn = 12;
  state.lastTurnReport = { armies: [{ terrainLosses: 1 }] };
  state.armies[0].designId = 'hatti';
  state.armies[0].units = state.armies[0].units.map(({ strengths, initialStrength, ...unit }) => unit);
  const national = catalogue.map((unit) => ({ ...unit, initialStrength: 999, profiles: { hittite: { initialStrength: unit.initialStrength } } }));
  const loaded = loadCampaign({ getItem: () => JSON.stringify(state) });
  const next = migrateCampaignStrength(loaded, national);
  assert.equal(next.version, 2);
  assert.equal(next.turn, 12);
  assert.equal(next.grain, state.grain);
  assert.equal(next.armies[0].hexId, state.armies[0].hexId);
  assert.equal(next.armies[0].name, 'Nile');
  assert.equal(armyTroops(next.armies[0]), 135);
  assert.equal(next.lastTurnReport, undefined);
  assert.equal(migrateCampaignStrength(next, national), next);
  assert.equal(migrateCampaignStrength(loaded, []), loaded);
  assert.equal(nextSeason(loaded), loaded);
});

test('legacy casualty history preserves missing formations as zero-force recovery slots', () => {
  const unit = { ...catalogue[0], quantity: 1 };
  const legacy = { ...newCampaign(), version: 1, nextArmyId: 2, armies: [{ id: 1, name: 'Old', designId: 'egypt', hexId: '7,11', moved: 0, units: [unit], initialUnits: [{ ...unit, quantity: 2 }] }] };
  const next = migrateCampaignStrength(legacy, catalogue);
  assert.deepEqual(next.armies[0].units[0].strengths, [60,0]);
  assert.equal(armyTroops(next.armies[0]), 60);
  assert.equal(unitTroops(recoverCasualties(next.armies[0].units).units[0]), 63);
});

test('saved individual strength and caps restore exactly and invalid forces are rejected', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2 });
  state.armies[0].units[0].strengths = [40,12];
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(state) }), state);
  for (const values of [[61,12],[-1,12],[2.5,12],[40], [0,0]]) {
    const invalid = { ...state, armies: [{ ...state.armies[0], units: [{ ...state.armies[0].units[0], strengths: values }] }] };
    assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(invalid) }), newCampaign());
  }
});

test('situation and grain settlement remain independent of individual troop losses', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2 });
  assert.equal(campaignEconomy(state, 2).situation, 'abundance');
  assert.equal(campaignEconomy(state, 1).situation, 'scarcity');
  state.grain = 0;
  assert.equal(campaignEconomy(state, 2).situation, 'famine');
  const production = campaignProduction(state);
  state.turn = 2;
  const next = nextSeason(state);
  assert.equal(next.grain, Math.ceil(production - 1.2));
  assert.equal(armyTroops(next.armies[0]), 114);
  assert.equal(armyUpkeep(next.armies[0]), 1.2);
});

test('27.8 grain funds a 28-grain army, leaves zero and cannot fund a 29-grain army', () => {
  const state = { ...newCampaign(), grain: 27.8 };
  const input = { name: 'Rounded budget', designId: 'egypt', quantities: { LIGHT_INFANTRY: 4 } };
  const next = recruitArmy(state, input, [{ ...catalogue[0], grainCost: 7 }]);
  assert.equal(availableGrain(state.grain), 28);
  assert.equal(next.armies.length, 1);
  assert.equal(next.grain, 0);
  assert.equal(recruitArmy(state, input, [{ ...catalogue[0], grainCost: 7.25 }]), state);
  assert.equal(availableGrain(28), 28);
  assert.equal(availableGrain(0), 0);
});

test('fractional saved reserves and turn balances round up to whole spendable grain', () => {
  const state = armyWith({ LIGHT_INFANTRY: 2 });
  state.grain = 27.8;
  const restored = loadCampaign({ getItem: () => JSON.stringify(state) });
  assert.equal(restored.grain, 28);
  const next = settle(restored);
  assert.equal(next.lastTurnReport.consumedGrain, 1.2);
  assert.equal(next.grain, 27);
  assert.ok(Number.isInteger(next.grain));
});

test('recruitment is locked to the chosen nation and deploys to that nation’s land', () => {
  for (const nation of PLAYABLE_NATIONS) {
    const state = newCampaign(nation);
    const next = recruitArmy(state, { name: 'National army', designId: nation, quantities: { LIGHT_INFANTRY: 4 } }, catalogue);
    assert.equal(next.nation, nation);
    assert.equal(next.armies[0].designId, nation);
    const hex = HEX_BY_ID.get(next.armies[0].hexId);
    assert.equal(hex.territory, nation);
    assert.equal(hex.city.capital, true);
    const different = nation === 'egypt' ? 'nubia' : 'egypt';
    assert.equal(recruitArmy(state, { name: '', designId: different, quantities: { LIGHT_INFANTRY: 4 } }, catalogue), state);
    assert.equal(HEX_BY_ID.get(findSpawn(next)).regionId, hex.regionId);
    assert.notEqual(findSpawn(next), hex.id);
  }
});

test('each nation uses an independent save and legacy Egyptian progress is preserved', () => {
  assert.equal(new Set(PLAYABLE_NATIONS.map(campaignStorageKey)).size, 3);
  const states = new Map(PLAYABLE_NATIONS.map((nation, index) => [campaignStorageKey(nation), JSON.stringify({ ...newCampaign(nation), grain: 100 + index, turn: index })]));
  for (const [index, nation] of PLAYABLE_NATIONS.entries()) {
    const state = loadCampaign({ getItem: (key) => states.get(key) }, nation);
    assert.equal(state.nation, nation);
    assert.equal(state.grain, 100 + index);
    assert.equal(state.turn, index);
  }
  const old = armyWith({ LIGHT_INFANTRY: 1 });
  delete old.nation;
  const restored = loadCampaign({ getItem: () => JSON.stringify(old) });
  assert.equal(restored.nation, 'egypt');
  assert.deepEqual(restored.armies, old.armies);
  assert.equal(loadCampaign({ getItem: () => null }, 'nubia').nation, 'nubia');
});

test('Sea Peoples cannot be selected for campaigns, recruit armies or own productive territory', () => {
  assert.deepEqual(PLAYABLE_NATIONS, ['egypt', 'hatti', 'nubia']);
  const state = newCampaign('seapeople');
  assert.equal(findSpawn(state), null);
  assert.equal(recruitArmy(state, { name: 'Invaders', designId: 'seapeople', quantities: { LIGHT_INFANTRY: 4 } }, catalogue), state);
  assert.equal(campaignProduction(state), 0);
  assert.ok(CAMPAIGN_HEXES.every((hex) => hex.territory !== 'seapeople'));
});

test('legacy Hatti saves keep armies, calendar and reserves while adopting the new identity', () => {
  const recruited = recruitArmy(newCampaign('hatti'), { name: 'Veterans', designId: 'hatti', quantities: { LIGHT_INFANTRY: 4 } }, catalogue);
  const legacy = { ...recruited, nation: LEGACY_HATTI_ID, turn: 14, grain: 27.8,
    armies: recruited.armies.map((army) => ({ ...army, designId: LEGACY_HATTI_ID })) };
  const oldKey = campaignStorageKey(LEGACY_HATTI_ID);
  const saves = new Map([[oldKey, JSON.stringify(legacy)]]);
  const restored = loadCampaign({ getItem: (key) => saves.get(key) ?? null }, 'hatti');
  assert.equal(restored.nation, 'hatti');
  assert.equal(restored.turn, 14);
  assert.equal(restored.grain, 28);
  assert.equal(restored.armies[0].designId, 'hatti');
  assert.equal(restored.armies[0].hexId, recruited.armies[0].hexId);
  assert.deepEqual(restored.armies[0].units, recruited.armies[0].units);
  assert.equal(restored.armies[0].name, 'Veterans');
  assert.equal(saves.get(oldKey), JSON.stringify(legacy));
  saves.set(campaignStorageKey('hatti'), JSON.stringify({ ...restored, turn: 18 }));
  assert.equal(loadCampaign({ getItem: (key) => saves.get(key) }, 'hatti').turn, 18);
  assert.equal(normalizeFaction(LEGACY_HATTI_ID + 'n'), 'HITTITE');
});

test('legacy enemy identities in another nation’s save also become Hittite', () => {
  const state = armyWith({ LIGHT_INFANTRY: 1 });
  state.armies[0].designId = LEGACY_HATTI_ID;
  const restored = loadCampaign({ getItem: () => JSON.stringify(state) });
  assert.equal(restored.nation, 'egypt');
  assert.equal(restored.armies[0].designId, 'hatti');
});
