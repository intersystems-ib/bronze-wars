import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_HEXES, CAMPAIGN_BORDERS, CAMPAIGN_STORAGE_KEY, HEX_BY_ID, armyMovement, armyUpkeep, campaignUpkeep, campaignProduction, campaignEconomy, recoverCasualties, applyCasualties, remainingMovement, findSpawn, loadCampaign, moveArmy, neighbors, newCampaign, nextSeason, reachableHexes, recruitArmy } from './campaignRules.js';
import { TERRAIN_TYPES, RIVERS, terrainAt } from './campaignTerrain.js';
import { CAMPAIGN_NATIONS, isSinai } from './campaignBorders.js';

const catalogue = [
  { code: 'LIGHT_INFANTRY', speed: 2, grainCost: 5, attack: 4, defense: 2, damage: 5 },
  { code: 'SPEARMEN', speed: 1, grainCost: 6, attack: 5, defense: 6, damage: 7 },
  { code: 'CHARIOTS', speed: 4, grainCost: 12, attack: 5, defense: 4, damage: 5 },
];
function settle(state, options = {}) {
  return nextSeason(state, { production: 0, ...options });
}
function recruit(state, quantities, designId = 'egypt') {
  return recruitArmy(state, { name: 'Nile army', designId, quantities }, catalogue);
}

test('recruitment spends the shared 100-grain reserve and preserves composition and stats', () => {
  const state = newCampaign();
  const next = recruit(state, { LIGHT_INFANTRY: 2, SPEARMEN: 4 });
  assert.equal(state.grain, 100);
  assert.equal(state.armies.length, 0);
  assert.equal(next.grain, 66);
  assert.equal(next.armies.length, 1);
  assert.equal(next.armies[0].units[1].defense, 6);
  assert.equal(next.armies[0].designId, 'egypt');
  assert.equal(HEX_BY_ID.get(next.armies[0].hexId).land, true);
});

test('empty, fractional, negative and unaffordable armies are rejected', () => {
  const state = newCampaign();
  for (const quantities of [{}, { LIGHT_INFANTRY: 0 }, { SPEARMEN: -1 }, { LIGHT_INFANTRY: 0.5 }, { CHARIOTS: 9 }]) {
    assert.equal(recruit(state, quantities), state);
  }
});

test('several armies share the reserve and never occupy the same hex', () => {
  let state = newCampaign();
  for (let i = 0; i < 20; i += 1) state = recruit(state, { LIGHT_INFANTRY: 1 }, 'nubia');
  assert.equal(state.grain, 0);
  assert.equal(state.armies.length, 20);
  assert.equal(new Set(state.armies.map((army) => army.hexId)).size, 20);
  assert.ok(state.armies.every((army) => army.designId === 'nubia'));
  assert.equal(recruit(state, { LIGHT_INFANTRY: 1 }), state);
});

test('movement is weighted by each troop quantity and only whole hexes can be traversed', () => {
  const state = recruit(newCampaign(), { LIGHT_INFANTRY: 1, SPEARMEN: 3 });
  const army = state.armies[0];
  assert.equal(armyMovement(army.units), 1.25);
  const reachable = reachableHexes(state, army.id);
  assert.ok(reachable.size > 0);
  assert.ok([...reachable.values()].every((cost) => cost === 1));
  const destination = reachable.keys().next().value;
  const moved = moveArmy(state, army.id, destination);
  assert.equal(moved.armies[0].moved, 1);
  assert.equal(reachableHexes(moved, army.id).size, 0);
  assert.equal(moveArmy(moved, army.id, army.hexId), moved);
});

test('movement tracks the distance of multi-hex paths and rejects occupied, sea and distant hexes', () => {
  let state = recruit(newCampaign(), { CHARIOTS: 1 });
  state = recruit(state, { LIGHT_INFANTRY: 1 });
  const army = state.armies[0];
  const reachable = reachableHexes(state, army.id);
  const destination = [...reachable].find(([, cost]) => cost === 3)?.[0];
  assert.ok(destination);
  assert.equal(reachable.has(state.armies[1].hexId), false);
  assert.equal(moveArmy(state, army.id, state.armies[1].hexId), state);
  assert.equal(moveArmy(state, army.id, CAMPAIGN_HEXES.find((hex) => !hex.land).id), state);
  assert.equal(moveArmy(state, army.id, '0,40'), state);
  assert.equal(moveArmy(state, army.id, 'invalid'), state);
  assert.equal(moveArmy(state, army.id, destination).armies[0].moved, 3);
  assert.ok([...reachable.keys()].every((id) => HEX_BY_ID.get(id).land));
});

test('hex adjacency is symmetric and an army can return to its previous position for another movement point', () => {
  for (const hex of CAMPAIGN_HEXES.filter((hex) => hex.land)) {
    for (const other of neighbors(hex.id)) assert.ok(neighbors(other.id).some((candidate) => candidate.id === hex.id));
  }
  let state = recruit(newCampaign(), { LIGHT_INFANTRY: 1 });
  const origin = state.armies[0].hexId;
  const target = [...reachableHexes(state, 1).keys()].find((id) => HEX_BY_ID.get(id).terrain === 'fertile');
  state = moveArmy(state, 1, target);
  state = moveArmy(state, 1, origin);
  assert.equal(state.armies[0].hexId, origin);
  assert.equal(state.armies[0].moved, 2);
  assert.equal(reachableHexes(state, 1).size, 0);
});

test('seasons restore movement and advance to 1299 BC after the third turn while charging upkeep', () => {
  let state = recruit(newCampaign(), { LIGHT_INFANTRY: 1 });
  const grain = state.grain;
  const fertile = [...reachableHexes(state, 1).keys()].find((id) => HEX_BY_ID.get(id).terrain === 'fertile');
  state = moveArmy(state, 1, fertile);
  state = settle(state);
  assert.equal(state.turn, 1);
  assert.equal(state.armies[0].moved, 0);
  state = settle(settle(state));
  assert.equal(state.turn % 3, 0);
  assert.equal(1300 - Math.floor(state.turn / 3), 1299);
  assert.equal(state.grain, grain - 1.5);
});

test('saved campaigns restore their reserve, troops, position and spent movement', () => {
  let state = recruit(newCampaign(), { LIGHT_INFANTRY: 1 });
  state = moveArmy(state, 1, reachableHexes(state, 1).keys().next().value);
  const storage = { getItem(key) { assert.equal(key, CAMPAIGN_STORAGE_KEY); return JSON.stringify(state); } };
  assert.deepEqual(loadCampaign(storage), state);
  assert.ok(findSpawn(state));
});

test('missing, corrupted or incompatible saves recover to a new campaign', () => {
  for (const value of [null, '{bad', '{}', JSON.stringify({ ...newCampaign(), grain: -1 }), JSON.stringify({ ...newCampaign(), armies: [{}] })]) {
    assert.deepEqual(loadCampaign({ getItem: () => value }), newCampaign());
  }
  assert.deepEqual(loadCampaign({ getItem() { throw new Error('Storage denied'); } }), newCampaign());
});

function stationed(terrain, quantity = 100, grain = 1000) {
  const hexId = CAMPAIGN_HEXES.find((hex) => hex.terrain === terrain).id;
  return { ...newCampaign(), grain, nextArmyId: 2, armies: [{ id: 1, name: 'Test army', designId: 'egypt', hexId, moved: 0, units: [{ ...catalogue[0], quantity }] }] };
}

test('all hexes have terrain metadata and only deserts and mountains cause 3% attrition', () => {
  assert.deepEqual(new Set(CAMPAIGN_HEXES.map((hex) => hex.terrain)), new Set(['water', 'coast', 'fertile', 'desert', 'mountain']));
  for (const hex of CAMPAIGN_HEXES) {
    const terrain = TERRAIN_TYPES[hex.terrain];
    assert.equal(terrain.attritionRate, terrain.difficult ? 0.03 : 0);
    assert.equal(hex.land, hex.terrain !== 'water');
  }
  assert.equal(HEX_BY_ID.get('7,11').terrain, 'fertile');
});

test('desert and mountain movement is limited to one neighboring hex and cannot be repeated', () => {
  for (const terrain of ['desert', 'mountain']) {
    const state = stationed(terrain);
    assert.equal(remainingMovement(state.armies[0]), 1);
    const reachable = reachableHexes(state, 1);
    assert.ok(reachable.size > 0);
    assert.ok([...reachable.keys()].every((id) => neighbors(state.armies[0].hexId).some((hex) => hex.id === id)));
    const moved = moveArmy(state, 1, reachable.keys().next().value);
    assert.equal(remainingMovement(moved.armies[0]), 0);
    assert.equal(reachableHexes(moved, 1).size, 0);
  }
});

test('entering difficult terrain exhausts movement and paths cannot jump across it', () => {
  const state = recruit(newCampaign(), { CHARIOTS: 1 });
  const target = [...reachableHexes(state, 1).keys()].find((id) => TERRAIN_TYPES[HEX_BY_ID.get(id).terrain].difficult);
  assert.ok(target);
  const moved = moveArmy(state, 1, target);
  assert.equal(remainingMovement(moved.armies[0]), 0);
  assert.equal(reachableHexes(moved, 1).size, 0);
});

test('terrain losses apply even without movement and are rounded up once per army', () => {
  for (const terrain of ['desert', 'mountain']) {
    const state = stationed(terrain, 101);
    const next = settle(state);
    assert.equal(next.armies[0].units[0].quantity, 97);
    assert.equal(next.lastTurnReport.armies[0].terrainLosses, 4);
    assert.equal(state.armies[0].units[0].quantity, 101);
  }
  assert.equal(settle(stationed('fertile', 101)).armies[0].units[0].quantity, 101);
  const mixed = applyCasualties([{ quantity: 10 }, { quantity: 10 }, { quantity: 10 }], 0.03);
  assert.equal(mixed.losses, 1);
  assert.equal(mixed.units.reduce((sum, unit) => sum + unit.quantity, 0), 29);
});

test('upkeep is 10% of every deployed unit cost and preserves fractional grain', () => {
  const state = recruit(newCampaign(), { LIGHT_INFANTRY: 3, SPEARMEN: 2 });
  assert.equal(armyUpkeep(state.armies[0]), 2.7);
  assert.equal(campaignUpkeep(state), 2.7);
  const next = settle(state);
  assert.equal(next.grain, 70.3);
  assert.equal(next.lastTurnReport.requiredGrain, 2.7);
  assert.equal(next.lastTurnReport.shortage, false);
});

test('positive reserves avoid famine this turn even if consumption exhausts them; zero reserves cause 5% losses', () => {
  const enough = settle(stationed('fertile', 21, 10.5));
  assert.equal(enough.grain, 0);
  assert.equal(enough.armies[0].units[0].quantity, 21);
  assert.equal(enough.lastTurnReport.shortage, false);
  for (const grain of [0, 10.49]) {
    const next = settle(stationed('fertile', 21, grain));
    assert.equal(next.grain, 0);
    assert.equal(next.armies[0].units[0].quantity, grain === 0 ? 19 : 21);
    assert.equal(next.lastTurnReport.armies[0].supplyLosses, grain === 0 ? 2 : 0);
    assert.equal(next.lastTurnReport.consumedGrain, grain);
  }
});

test('combined terrain and supply losses apply sequentially; upkeep uses the pre-loss composition', () => {
  const next = settle(stationed('desert', 101, 0));
  assert.equal(next.lastTurnReport.requiredGrain, 50.5);
  assert.equal(next.lastTurnReport.armies[0].terrainLosses, 4);
  assert.equal(next.lastTurnReport.armies[0].supplyLosses, 5);
  assert.equal(next.armies[0].units[0].quantity, 92);
  assert.equal(next.armies[0].moved, 0);
  assert.equal(campaignUpkeep(next), 46);
});

test('all deployed armies suffer supply losses when the shared reserve starts empty', () => {
  const state = stationed('fertile', 21, 0);
  state.armies.push({ ...state.armies[0], id: 2, hexId: '7,10' });
  state.nextArmyId = 3;
  const next = settle(state);
  assert.equal(next.lastTurnReport.requiredGrain, 21);
  assert.deepEqual(next.armies.map((army) => army.units[0].quantity), [19, 19]);
});

test('armies with no surviving units are removed, free their hex and remain in the turn report', () => {
  const state = stationed('desert', 1);
  const next = settle(state);
  assert.equal(next.armies.length, 0);
  assert.equal(next.lastTurnReport.armies[0].destroyed, true);
  assert.equal(campaignUpkeep(next), 0);
  const empty = settle(newCampaign());
  assert.equal(empty.grain, 100);
  assert.deepEqual(empty.lastTurnReport.armies, []);
});

test('supply and terrain results survive saving without resetting existing campaigns', () => {
  const next = settle(stationed('mountain', 101, 1));
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(next) }), next);
});

test('Euphrates and Jordan valleys override difficult terrain and have no attrition', () => {
  for (const river of RIVERS.filter((entry) => entry.id !== 'nile')) {
    for (const [x, y] of river.path) assert.equal(terrainAt(x, y, true), 'fertile');
    const hexes = CAMPAIGN_HEXES.filter((hex) => hex.river === river.id);
    assert.ok(hexes.length > 3);
    for (const hex of hexes) {
      assert.ok(['fertile', 'coast'].includes(hex.terrain));
      assert.equal(TERRAIN_TYPES[hex.terrain].attritionRate, 0);
      assert.equal(TERRAIN_TYPES[hex.terrain].production, 1);
    }
  }
});

test('water, coastal access and rivers produce one grain and Egyptian production accumulates', () => {
  for (const [id, terrain] of Object.entries(TERRAIN_TYPES)) assert.equal(terrain.production, ['fertile', 'coast', 'water'].includes(id) ? 1 : 0);
  for (const hex of CAMPAIGN_HEXES) assert.equal(hex.production, hex.waterAccess ? 1 : 0);
  assert.equal(nextSeason(newCampaign()).grain, 100 + campaignProduction(newCampaign()));
});

test('Egypt includes the Nile corridor through visible row 34; Nubia begins at row 35 and Sinai is neutral', () => {
  for (const id of ['10,9','10,10','11,9','11,10']) assert.equal(HEX_BY_ID.get(id).territory, null);
  assert.equal(HEX_BY_ID.get('7,33').territory, 'egypt');
  assert.equal(HEX_BY_ID.get('7,34').territory, 'nubia');
  assert.ok(CAMPAIGN_HEXES.filter((hex) => hex.territory === 'egypt').every((hex) => hex.row <= 33));
  assert.ok(CAMPAIGN_HEXES.filter((hex) => hex.territory === 'nubia').every((hex) => hex.row >= 34));
  assert.ok(CAMPAIGN_HEXES.filter((hex) => !hex.land).every((hex) => hex.territory === null));
});

test('national border paths are unique and use yellow, blue and purple on their respective sides', () => {
  assert.equal(new Set(CAMPAIGN_BORDERS.map((border) => border.id)).size, CAMPAIGN_BORDERS.length);
  assert.deepEqual(CAMPAIGN_NATIONS, { egypt: { color: '#f5d52b' }, assyria: { color: '#428fff' }, nubia: { color: '#b55de8' } });
  for (const id of ['egypt', 'assyria', 'nubia']) assert.ok(CAMPAIGN_BORDERS.some((border) => border.territory === id));
  assert.ok(CAMPAIGN_BORDERS.every((border) => !isSinai(HEX_BY_ID.get(border.hexId))));
  assert.ok(CAMPAIGN_BORDERS.some((border) => border.hexId === '7,33' && border.territory === 'egypt'));
  assert.ok(CAMPAIGN_BORDERS.some((border) => border.hexId === '7,34' && border.territory === 'nubia'));
});

test('the Nile corridor extends two neighboring hexes to either side and excludes remote deserts', () => {
  // Visible row 21: Nile valley at column 9, buffers at 7/8 and 10/11.
  for (const col of [6,7,8,9,10]) assert.equal(HEX_BY_ID.get(`${col},20`).territory, 'egypt');
  for (const col of [0,1,2,3,4,5,11,18,19,20,21,22,23]) assert.equal(HEX_BY_ID.get(`${col},20`).territory, null);
  for (const hex of CAMPAIGN_HEXES.filter((candidate) => ['egypt','nubia'].includes(candidate.territory))) {
    const nearby = new Set([hex.id, ...neighbors(hex.id).map((candidate) => candidate.id)]);
    for (const id of [...nearby]) for (const candidate of neighbors(id)) nearby.add(candidate.id);
    assert.ok([...nearby].some((id) => HEX_BY_ID.get(id).nileValley));
  }
  assert.ok(CAMPAIGN_HEXES.filter((hex) => hex.land && isSinai(hex)).every((hex) => hex.territory === null));
});

test('Assyria includes both river corridors and the Levant coast without annexing Sinai or Arabia', () => {
  for (const hex of CAMPAIGN_HEXES.filter((candidate) => ['euphrates','jordan'].includes(candidate.river))) assert.equal(hex.territory, 'assyria');
  const coasts = CAMPAIGN_HEXES.filter((hex) => hex.territory === 'assyria' && hex.terrain === 'coast');
  assert.ok(coasts.length > 5);
  for (const hex of coasts) { assert.equal(hex.land, true); assert.equal(hex.production, 1); }
  assert.ok(CAMPAIGN_HEXES.filter((hex) => hex.territory === 'assyria').every((hex) => hex.y < 400));
});

test('mixed land/sea hexes remain coastal land and are traversable, while open sea remains blocked', () => {
  const coasts = CAMPAIGN_HEXES.filter((hex) => hex.mixedCoast);
  assert.ok(coasts.length > 10);
  for (const hex of coasts) {
    assert.equal(hex.terrain, 'coast');
    assert.equal(hex.land, true);
    assert.equal(hex.production, 1);
  }
  const coastal = coasts.find((hex) => hex.territory === 'assyria' && neighbors(hex.id).length);
  assert.ok(coastal);
  const state = stationed('fertile', 1);
  state.armies[0].hexId = neighbors(coastal.id)[0].id;
  assert.ok(reachableHexes(state, 1).has(coastal.id));
  for (const hex of CAMPAIGN_HEXES.filter((hex) => !hex.land)) assert.equal(hex.terrain, 'water');
});

test('situation prioritizes empty reserves; positive reserves distinguish surplus, deficit and equality', () => {
  const state = stationed('fertile', 20, 1);
  assert.equal(campaignEconomy(state, 11).situation, 'abundance');
  assert.equal(campaignEconomy(state, 9).situation, 'scarcity');
  assert.equal(campaignEconomy(state, 10).situation, 'scarcity');
  assert.equal(campaignEconomy({ ...state, grain: 0 }, 100).situation, 'famine');
});

test('only productive Egyptian territory contributes to the campaign grain reserve', () => {
  const state = newCampaign();
  const expected = CAMPAIGN_HEXES.filter((hex) => hex.land && hex.territory === 'egypt' && hex.waterAccess).length;
  assert.ok(expected > 0);
  assert.equal(campaignProduction(state), expected);
  const next = nextSeason(state);
  assert.equal(next.lastTurnReport.producedGrain, expected);
  assert.equal(next.grain, 100 + expected);
});

test('income and upkeep settle once per turn and never create negative grain balances', () => {
  const state = stationed('fertile', 20, 1);
  const next = settle(state, { production: 8 });
  assert.equal(next.lastTurnReport.situation, 'scarcity');
  assert.equal(next.lastTurnReport.consumedGrain, 9);
  assert.equal(next.grain, 0);
  assert.equal(next.armies[0].units[0].quantity, 20);
  const famine = settle(next, { production: 8 });
  assert.equal(famine.lastTurnReport.situation, 'famine');
  assert.equal(famine.armies[0].units[0].quantity, 19);
  assert.equal(famine.grain, 0);
});

test('abundance restores 5% of missing troops rounded up, capped at the original troop counts', () => {
  const army = recruit(newCampaign(), { LIGHT_INFANTRY: 10, SPEARMEN: 5 }).armies[0];
  const wounded = [{ ...army.units[0], quantity: 4 }, { ...army.units[1], quantity: 3 }];
  const result = recoverCasualties(wounded, army.initialUnits);
  assert.equal(result.recovered, 1); // ceil(8 missing × 0.05)
  assert.deepEqual(result.units.map((unit) => unit.quantity), [5, 3]);
  let units = wounded;
  for (let turn = 0; turn < 30; turn += 1) units = recoverCasualties(units, army.initialUnits).units;
  assert.deepEqual(units.map((unit) => unit.quantity), [10, 5]);
  assert.equal(recoverCasualties(units, army.initialUnits).recovered, 0);
});

test('abundance restores a depleted troop type from the original roster without exceeding its capacity', () => {
  const army = recruit(newCampaign(), { LIGHT_INFANTRY: 5, SPEARMEN: 5 }).armies[0];
  const result = recoverCasualties([army.units[0]], army.initialUnits);
  assert.equal(result.recovered, 1);
  assert.deepEqual(result.units.map((unit) => unit.quantity), [5, 1]);
});

test('only abundance heals; scarcity leaves wounded troops unchanged and famine causes further losses', () => {
  const state = stationed('fertile', 10, 100);
  state.armies[0].initialUnits = [{ ...state.armies[0].units[0], quantity: 30 }];
  assert.equal(settle(state, { production: 6 }).armies[0].units[0].quantity, 11);
  assert.equal(settle(state, { production: 5 }).armies[0].units[0].quantity, 10);
  assert.equal(settle(state, { production: 4 }).armies[0].units[0].quantity, 10);
  const famine = settle({ ...state, grain: 0 }, { production: 100 });
  assert.equal(famine.armies[0].units[0].quantity, 9);
  assert.equal(famine.lastTurnReport.armies[0].recoveredUnits, 0);
  assert.equal(famine.grain, 95);
});

test('recovery caps survive casualties, saving and loading; legacy armies establish a baseline without resetting', () => {
  const legacy = stationed('fertile', 20, 0);
  const wounded = settle(legacy);
  assert.equal(wounded.armies[0].initialUnits[0].quantity, 20);
  const saved = loadCampaign({ getItem: () => JSON.stringify(wounded) });
  const recovered = settle({ ...saved, grain: 1 }, { production: 100 });
  assert.equal(recovered.armies[0].units[0].quantity, 20);
  assert.equal(recovered.armies[0].initialUnits[0].quantity, 20);
});

test('terrain attrition still applies in scarcity and annihilated armies cannot be resurrected by abundance', () => {
  const scarcity = settle(stationed('mountain', 100), { production: 0 });
  assert.equal(scarcity.armies[0].units[0].quantity, 97);
  const destroyed = settle(stationed('mountain', 1), { production: 100 });
  assert.equal(destroyed.lastTurnReport.situation, 'abundance');
  assert.equal(destroyed.armies.length, 0);
});
