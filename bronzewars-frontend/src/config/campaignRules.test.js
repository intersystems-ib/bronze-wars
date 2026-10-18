import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_HEXES, CAMPAIGN_BORDERS, CAMPAIGN_STORAGE_KEY, HEX_BY_ID, armyMovement, armyTroops, activeUnitCount, unitTroops, migrateCampaignStrength, armyUpkeep, campaignUpkeep, campaignProduction, campaignEconomy, recoverCasualties, applyCasualties, remainingMovement, findSpawn, loadCampaign, moveArmy, neighbors, newCampaign, nextSeason, reachableHexes, recruitArmy } from './campaignRules.js';
import { TERRAIN_TYPES, RIVERS, terrainAt } from './campaignTerrain.js';
import { CAMPAIGN_NATIONS, isSinai } from './campaignBorders.js';
import { CAMPAIGN_CITIES } from './campaignCities.js';
import { disbandArmy, terrainAttrition } from './campaignRules.js';
import { startCityAction } from './campaignCityActions.js';

const catalogue = [
  { code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 5, attack: 4, defense: 2, damage: 5 },
  { code: 'SPEARMEN', initialStrength: 100, speed: 1, grainCost: 6, attack: 5, defense: 6, damage: 7 },
  { code: 'CHARIOTS', initialStrength: 15, speed: 4, grainCost: 12, attack: 5, defense: 4, damage: 5 },
];
function settle(state, options = {}) {
  return nextSeason(state, { production: 0, ...options });
}
function recruit(state, quantities, designId = 'egypt') {
  return recruitArmy(state, { name: 'Nile army', designId, quantities }, catalogue);
}

test('disbanding removes only the selected friendly army, frees its capital and stops its upkeep without a refund', () => {
  const state = recruit(newCampaign(), { LIGHT_INFANTRY: 4 });
  const capital = state.armies[0].hexId;
  const other = { ...state.armies[0], id: 2, hexId: neighbors(capital)[0].id };
  const enemy = { ...other, id: 3, designId: 'hatti', hexId: '17,0' };
  state.armies.push(other, enemy);
  state.nextArmyId = 4;
  const next = disbandArmy(state, 1);
  assert.deepEqual(next.armies, [other, enemy]);
  assert.equal(state.armies.length, 3);
  assert.equal(next.grain, state.grain);
  assert.equal(next.turn, state.turn);
  assert.equal(next.nextArmyId, 4);
  assert.equal(campaignUpkeep(state), 4);
  assert.equal(campaignUpkeep(next), 2);
  assert.equal(findSpawn(next), capital);
  assert.equal(settle(next).grain, state.grain - 2);
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(next) }), next);
  assert.equal(disbandArmy(next, 3), next);
  assert.equal(disbandArmy(next, 999), next);
});

test('disbanding the last army abandons its assault without capturing the city or changing raid history', () => {
  let state = recruit(newCampaign(), { SPEARMEN: 5 });
  const city = CAMPAIGN_CITIES.find((candidate) => candidate.nation === 'hatti');
  state.armies[0].hexId = city.hexId;
  state = startCityAction(state, 1, 'raid');
  state = startCityAction(state, 1, 'assault');
  assert.ok(state.armies[0].cityAction);
  const next = disbandArmy(state, 1);
  assert.deepEqual(next.armies, []);
  assert.equal(campaignUpkeep(next), 0);
  assert.equal(next.cityRaids, state.cityRaids);
  assert.equal(next.cityOwners, state.cityOwners);
  assert.equal(settle(next).grain, state.grain);
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(next) }), next);
});

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
  for (const quantities of [{}, { LIGHT_INFANTRY: 0 }, { LIGHT_INFANTRY: 1 }, { LIGHT_INFANTRY: 2 }, { LIGHT_INFANTRY: 3 }, { LIGHT_INFANTRY: 1, SPEARMEN: 2 }, { SPEARMEN: -1 }, { LIGHT_INFANTRY: 0.5 }, { CHARIOTS: 9 }]) {
    assert.equal(recruit(state, quantities), state);
  }
});

test('recruitment uses free capital-region hexes and subsequent armies share reserves without stacking', () => {
  let state = newCampaign('nubia');
  const capital = findSpawn(state);
  state = recruit(state, { LIGHT_INFANTRY: 4 }, 'nubia');
  assert.equal(state.armies[0].hexId, capital);
  const nearby = findSpawn(state);
  assert.notEqual(nearby, capital);
  assert.equal(HEX_BY_ID.get(nearby).regionId, HEX_BY_ID.get(capital).regionId);
  const expanded = recruit(state, { LIGHT_INFANTRY: 4 }, 'nubia');
  assert.equal(expanded.armies[1].hexId, nearby);
  assert.equal(expanded.grain, 60);
  state = moveArmy(state, 1, reachableHexes(state, 1).keys().next().value);
  assert.equal(findSpawn(state), capital);
  state = recruit(state, { LIGHT_INFANTRY: 4 }, 'nubia');
  assert.equal(state.grain, 60);
  assert.equal(state.armies.length, 2);
  assert.equal(state.armies[1].hexId, capital);
  assert.equal(new Set(state.armies.map((army) => army.hexId)).size, 2);
  assert.ok(state.armies.every((army) => army.designId === 'nubia'));
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(state) }, 'nubia'), state);
  assert.equal(recruit(state, { LIGHT_INFANTRY: 4 }), state);
});

test('all nations fill their capital region without stacking and relocate deployment after losing the original capital', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const state = { ...newCampaign(nation), grain: 10000 };
    const capital = CAMPAIGN_CITIES.find((city) => city.nation === nation && city.capital);
    assert.equal(findSpawn(state), capital.hexId);
    const occupied = recruit(state, { LIGHT_INFANTRY: 4 }, nation);
    occupied.armies[0].designId = nation === 'egypt' ? 'hatti' : 'egypt';
    const reinforced = recruit(occupied, { LIGHT_INFANTRY: 4 }, nation);
    assert.equal(reinforced.armies.length, 2);
    assert.notEqual(reinforced.armies[1].hexId, capital.hexId);
    let filled = state;
    const region = CAMPAIGN_HEXES.filter((hex) => hex.regionId === capital.id);
    for (let index = 0; index < region.length; index += 1) {
      const next = recruit(filled, { LIGHT_INFANTRY: 4 }, nation);
      assert.equal(next.armies.length, index + 1);
      assert.equal(HEX_BY_ID.get(next.armies.at(-1).hexId).regionId, capital.id);
      assert.ok(HEX_BY_ID.get(next.armies.at(-1).hexId).land);
      filled = next;
    }
    assert.equal(new Set(filled.armies.map((army) => army.hexId)).size, region.length);
    assert.equal(findSpawn(filled), null);
    assert.equal(recruit(filled, { LIGHT_INFANTRY: 4 }, nation), filled);
    assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(filled) }, nation), filled);
    const lost = { ...state, cityOwners: { [capital.id]: nation === 'egypt' ? 'hatti' : 'egypt' } };
    assert.ok(findSpawn(lost));
    assert.notEqual(HEX_BY_ID.get(findSpawn(lost)).regionId, capital.id);
    assert.equal(recruit(lost, { LIGHT_INFANTRY: 4 }, nation).armies.length, 1);
  }
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

test('movement tracks multi-hex paths, permits friendly merge destinations and rejects sea and distant hexes', () => {
  let state = recruit(newCampaign(), { CHARIOTS: 4 });
  state = moveArmy(state, 1, neighbors(state.armies[0].hexId).find((hex) => hex.terrain === 'fertile').id);
  state = settle(state);
  state = recruit(state, { LIGHT_INFANTRY: 4 });
  const army = state.armies[0];
  const reachable = reachableHexes(state, army.id);
  const destination = [...reachable].find(([, cost]) => cost === 3)?.[0];
  assert.ok(destination);
  assert.equal(reachable.has(state.armies[1].hexId), true);
  assert.equal(moveArmy(state, army.id, state.armies[1].hexId).armies.length, 1);
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
  let state = recruit(newCampaign(), { LIGHT_INFANTRY: 4 });
  const origin = state.armies[0].hexId;
  const target = [...reachableHexes(state, 1).keys()].find((id) => HEX_BY_ID.get(id).terrain === 'fertile');
  state = moveArmy(state, 1, target);
  state = moveArmy(state, 1, origin);
  assert.equal(state.armies[0].hexId, origin);
  assert.equal(state.armies[0].moved, 2);
  assert.equal(reachableHexes(state, 1).size, 0);
});

test('seasons restore movement and advance to 1299 BC after the third turn while charging upkeep', () => {
  let state = recruit(newCampaign(), { LIGHT_INFANTRY: 4 });
  const grain = state.grain;
  const fertile = [...reachableHexes(state, 1).keys()].find((id) => HEX_BY_ID.get(id).terrain === 'fertile');
  state = moveArmy(state, 1, fertile);
  state = settle(state);
  assert.equal(state.turn, 1);
  assert.equal(state.armies[0].moved, 0);
  state = settle(settle(state));
  assert.equal(state.turn % 3, 0);
  assert.equal(1300 - Math.floor(state.turn / 3), 1299);
  assert.equal(state.grain, grain - 6);
});

test('saved campaigns restore their reserve, troops, position and spent movement', () => {
  let state = recruit(newCampaign(), { LIGHT_INFANTRY: 4 });
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
  return { ...newCampaign(), grain, nextArmyId: 2, armies: [{ id: 1, name: 'Test army', designId: 'egypt', hexId, moved: 0, units: [{ ...catalogue[0], quantity, strengths: Array(quantity).fill(60) }] }] };
}

test('own difficult terrain protects every playable nation without changing movement or famine losses', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const ownHexes = CAMPAIGN_HEXES.filter((hex) => hex.territory === nation && TERRAIN_TYPES[hex.terrain].difficult);
    assert.ok(ownHexes.length > 0);
    for (const hex of ownHexes) {
      const state = stationed(hex.terrain, 1);
      state.nation = nation;
      state.armies[0].designId = nation;
      state.armies[0].hexId = hex.id;
      assert.equal(terrainAttrition(state, hex), 0);
      assert.equal(remainingMovement(state.armies[0]), 1);
      const next = settle(state);
      assert.equal(next.lastTurnReport.armies[0].terrainLosses, 0);
      assert.equal(armyTroops(next.armies[0]), 60);
      const hungry = settle({ ...state, grain: 0 });
      assert.equal(hungry.lastTurnReport.armies[0].terrainLosses, 0);
      assert.equal(hungry.lastTurnReport.armies[0].supplyLosses, 3);
      assert.equal(armyTroops(hungry.armies[0]), 57);
    }
  }
});

test('neutral and enemy difficult terrain still cause rounded 3% losses, and city protection follows current ownership', () => {
  for (const territory of [null, 'hatti']) {
    for (const terrain of ['desert', 'mountain']) {
      const hex = CAMPAIGN_HEXES.find((candidate) => (territory ? candidate.territory === territory : !candidate.territory) && candidate.terrain === terrain);
      assert.ok(hex);
      const state = stationed(terrain, 1);
      state.armies[0].hexId = hex.id;
      assert.equal(terrainAttrition(state, hex), 0.03);
      const next = settle(state);
      assert.equal(next.lastTurnReport.armies[0].terrainLosses, 2);
      assert.equal(armyTroops(next.armies[0]), 58);
    }
  }
  const city = CAMPAIGN_CITIES.find((candidate) => candidate.nation === 'hatti');
  const hex = { ...HEX_BY_ID.get(city.hexId), terrain: 'mountain' };
  const state = { ...newCampaign(), cityOwners: { [city.id]: 'egypt' } };
  assert.equal(terrainAttrition(state, hex), 0);
  assert.equal(terrainAttrition(state, hex, 'hatti'), 0.03);
  assert.equal(terrainAttrition({ ...state, cityOwners: {} }, hex), 0.03);
});

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
  const state = recruit(newCampaign(), { CHARIOTS: 4 });
  const target = [...reachableHexes(state, 1).keys()].find((id) => TERRAIN_TYPES[HEX_BY_ID.get(id).terrain].difficult);
  assert.ok(target);
  const moved = moveArmy(state, 1, target);
  assert.equal(remainingMovement(moved.armies[0]), 0);
  assert.equal(reachableHexes(moved, 1).size, 0);
});

test('Euphrates and Jordan valleys override difficult terrain and have no attrition', () => {
  for (const river of RIVERS.filter((entry) => entry.id !== 'nile')) {
    for (const [x, y] of river.path) assert.equal(terrainAt(x, y, true), 'fertile');
    const hexes = CAMPAIGN_HEXES.filter((hex) => hex.river === river.id);
    assert.ok(hexes.length > 3);
    for (const hex of hexes) {
      assert.ok(['fertile', 'coast'].includes(hex.terrain));
      assert.equal(TERRAIN_TYPES[hex.terrain].attritionRate, 0);
      assert.equal(TERRAIN_TYPES[hex.terrain].production, 0);
    }
  }
});

test('only cities produce grain and Egyptian production accumulates annually', () => {
  for (const terrain of Object.values(TERRAIN_TYPES)) assert.equal(terrain.production, 0);
  for (const hex of CAMPAIGN_HEXES) assert.equal(hex.production, hex.city?.grain || 0);
  let state = newCampaign();
  const production = campaignProduction(state);
  for (let turn = 1; turn <= 6; turn += 1) {
    state = nextSeason(state);
    assert.equal(state.grain, 100 + Math.floor(turn / 3) * production);
    assert.equal(state.lastTurnReport.producedGrain, turn % 3 === 0 ? production : 0);
  }
});

test('annual harvest pays once across saved games while upkeep remains seasonal for every playable nation', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    let state = recruitArmy(newCampaign(nation), { name: 'Guard', designId: nation, quantities: { LIGHT_INFANTRY: 4 } }, [{ ...catalogue[0], grainCost: 10 }]);
    const production = campaignProduction(state);
    for (let turn = 1; turn <= 4; turn += 1) {
      state = nextSeason(loadCampaign({ getItem: () => JSON.stringify(state) }, nation));
      assert.equal(state.grain, 60 - turn * 4 + Math.floor(turn / 3) * production);
      assert.equal(state.lastTurnReport.consumedGrain, 4);
      assert.equal(state.lastTurnReport.producedGrain, turn === 3 ? production : 0);
    }
  }
});

test('cities have unique land hexes in their nation and exactly one capital per civilization', () => {
  assert.equal(new Set(CAMPAIGN_CITIES.map((city) => city.hexId)).size, CAMPAIGN_CITIES.length);
  assert.equal(new Set(CAMPAIGN_CITIES.map((city) => city.id)).size, CAMPAIGN_CITIES.length);
  for (const [nation, count, grain] of [['egypt', 6, 31], ['hatti', 6, 30], ['nubia', 3, 20]]) {
    const cities = CAMPAIGN_CITIES.filter((city) => city.nation === nation);
    assert.equal(cities.length, count);
    assert.equal(cities.filter((city) => city.capital).length, 1);
    assert.equal(campaignProduction(newCampaign(nation)), grain);
    for (const city of cities) {
      const hex = HEX_BY_ID.get(city.hexId);
      assert.equal(hex.land, true);
      assert.equal(hex.territory, nation);
      assert.equal(hex.city, city);
      assert.equal(hex.production, city.grain);
      assert.equal(Number.isInteger(city.grain), true);
      assert.ok(city.grain >= 2 && city.grain <= 8);
      if (nation === 'nubia') assert.equal(hex.river, null);
    }
  }
  assert.equal(campaignProduction(newCampaign('seapeople')), 0);
});

test('city positions preserve north-south order and the requested Hittite coastal relocations', () => {
  const cityHex = (id) => HEX_BY_ID.get(CAMPAIGN_CITIES.find((city) => city.id === id).hexId);
  for (const ids of [
    ['nubia-1', 'nubia-2', 'nubia-3'],
    ['egypt-2', 'egypt-1', 'egypt-3', 'egypt-4', 'egypt-5', 'egypt-6'],
    ['hatti-2', 'hatti-3', 'hatti-5'],
  ]) {
    for (let index = 1; index < ids.length; index += 1) assert.ok(cityHex(ids[index - 1]).row < cityHex(ids[index]).row);
  }
  for (const id of ['hatti-2', 'hatti-3', 'hatti-5']) assert.equal(cityHex(id).terrain, 'coast');
  assert.equal(cityHex('hatti-5').id, '15,6'); // Visible hex 16,7: Gaza.
  assert.equal(cityHex('hatti-6').id, '16,7'); // Visible hex 17,8: Megiddo.
  assert.ok(cityHex('hatti-4').row < cityHex('hatti-6').row);
  assert.equal(CAMPAIGN_CITIES.find((city) => city.id === 'hatti-1').capital, true);
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
  assert.deepEqual(CAMPAIGN_NATIONS, { egypt: { color: '#f5d52b' }, hatti: { color: '#428fff' }, nubia: { color: '#b55de8' } });
  for (const id of ['egypt', 'hatti', 'nubia']) assert.ok(CAMPAIGN_BORDERS.some((border) => border.territory === id));
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

test('Hatti includes both river corridors and the Levant coast without annexing Sinai or Arabia', () => {
  for (const hex of CAMPAIGN_HEXES.filter((candidate) => ['euphrates','jordan'].includes(candidate.river))) assert.equal(hex.territory, 'hatti');
  const coasts = CAMPAIGN_HEXES.filter((hex) => hex.territory === 'hatti' && hex.terrain === 'coast');
  assert.ok(coasts.length > 5);
  for (const hex of coasts) { assert.equal(hex.land, true); assert.equal(hex.production, hex.city?.grain || 0); }
  assert.ok(CAMPAIGN_HEXES.filter((hex) => hex.territory === 'hatti').every((hex) => hex.y < 400));
});

test('mixed land/sea hexes remain coastal land and are traversable, while open sea remains blocked', () => {
  const coasts = CAMPAIGN_HEXES.filter((hex) => hex.mixedCoast);
  assert.ok(coasts.length > 10);
  for (const hex of coasts) {
    assert.equal(hex.terrain, 'coast');
    assert.equal(hex.land, true);
    assert.equal(hex.production, hex.city?.grain || 0);
  }
  const coastal = coasts.find((hex) => hex.territory === 'hatti' && neighbors(hex.id).length);
  assert.ok(coastal);
  const state = stationed('fertile', 1);
  state.armies[0].hexId = neighbors(coastal.id)[0].id;
  assert.ok(reachableHexes(state, 1).has(coastal.id));
  for (const hex of CAMPAIGN_HEXES.filter((hex) => !hex.land)) assert.equal(hex.terrain, 'water');
});
