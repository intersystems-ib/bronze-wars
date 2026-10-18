import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_HEXES, HEX_BY_ID, newCampaign, neighbors, reachableHexes, moveArmy, campaignUpkeep, nextSeason, campaignTerritory } from './campaignRules.js';
import { armyUnitCount, campaignView, hexDistance } from './campaignVisibility.js';

function army(id, nation, hexId, strengths = [60, 60, 0]) {
  return { id, designId: nation, hexId, name: `Secret ${id}`, morale: 73, moved: 0,
    units: [{ code: 'LIGHT_INFANTRY', quantity: strengths.length, initialStrength: 60, strengths, speed: 2, grainCost: 10 }] };
}

test('hex distance is symmetric, handles odd/even rows and ignores movement obstacles', () => {
  for (const hex of CAMPAIGN_HEXES) {
    assert.equal(hexDistance(hex.id, hex.id), 0);
    for (const other of neighbors(hex.id)) {
      assert.equal(hexDistance(hex.id, other.id), 1);
      assert.equal(hexDistance(other.id, hex.id), 1);
    }
  }
  assert.equal(hexDistance('0,0', '1,1'), 2);
  assert.equal(hexDistance('1,1', '2,2'), 1);
  assert.equal(hexDistance('0,0', '0,2'), 2);
  assert.equal(hexDistance('bad', '0,0'), Infinity);
});

test('every nation sees its own territory even without armies, while Sea Peoples have no territory', () => {
  for (const nation of ['egypt', 'hatti', 'nubia', 'seapeople']) {
    const view = campaignView(newCampaign(nation));
    assert.deepEqual([...view.visibleHexIds], CAMPAIGN_HEXES.filter((hex) => hex.territory === nation).map((hex) => hex.id));
    assert.deepEqual(view.armies, []);
  }
});

test('outside territory, only an army hex and its immediate ring are clear, including water', () => {
  const state = { ...newCampaign(), armies: [army(1, 'egypt', '14,7')] };
  const view = campaignView(state);
  for (const hex of CAMPAIGN_HEXES) {
    assert.equal(view.visibleHexIds.has(hex.id), hex.territory === 'egypt' || hexDistance('14,7', hex.id) <= 1);
  }
  assert.ok(CAMPAIGN_HEXES.some((hex) => !hex.land && view.visibleHexIds.has(hex.id)));
});

test('enemy contact shows a question mark at distance two and unit count only when adjacent', () => {
  const state = { ...newCampaign(), armies: [army(1, 'egypt', '0,20'), army(2, 'nubia', '1,20'), army(3, 'hatti', '2,20'), army(4, 'seapeople', '3,20')] };
  const view = campaignView(state);
  assert.equal(view.armies[0].unitCount, 2);
  assert.deepEqual(view.armies[1], { id: 2, designId: 'nubia', hexId: '1,20', own: false, unitCount: 2 });
  assert.deepEqual(view.armies[2], { id: 3, designId: 'hatti', hexId: '2,20', own: false, unitCount: null });
  assert.equal(view.armies.some((contact) => contact.id === 4), false);
  assert.equal(view.visibleHexIds.has('2,20'), false);
  assert.equal(JSON.stringify(view.armies.slice(1)).includes('Secret'), false);
  for (const contact of view.armies.filter((contact) => !contact.own)) {
    for (const field of ['units', 'morale', 'name', 'strengths']) assert.equal(field in contact, false);
  }
});

test('unit counts count surviving formations, not troops or original quantities', () => {
  const own = army(1, 'egypt', '7,11', [15, 1, 0]);
  own.units.push({ quantity: 2, strengths: [60, 0] });
  assert.equal(armyUnitCount(own), 3);
});

test('the same scene gives separate observations for each human or AI nation', () => {
  const state = { ...newCampaign(), armies: [army(1, 'egypt', '0,20'), army(2, 'nubia', '2,20'), army(3, 'hatti', '3,20')] };
  const human = campaignView(state, 'egypt');
  const ai = campaignView(state, 'nubia');
  assert.equal(human.armies.find((contact) => contact.id === 2).unitCount, null);
  assert.equal(human.armies.some((contact) => contact.id === 3), false);
  assert.equal(ai.armies.find((contact) => contact.id === 1).unitCount, null);
  assert.equal(ai.armies.find((contact) => contact.id === 2).own, true);
  assert.equal(ai.armies.find((contact) => contact.id === 3).unitCount, 2);
});

test('movement refreshes visibility and abandoned foreign terrain becomes shaded again', () => {
  const state = { ...newCampaign(), armies: [army(1, 'egypt', '10,20')] };
  const before = campaignView(state);
  const destination = [...reachableHexes(state, 1).keys()].find((id) => hexDistance(id, '10,20') >= 1);
  assert.ok(destination);
  const moved = moveArmy(state, 1, destination);
  const after = campaignView(moved);
  assert.ok([...before.visibleHexIds].some((id) => HEX_BY_ID.get(id).territory !== 'egypt' && !after.visibleHexIds.has(id)));
});

test('distant invaders are visible in national territory even without friendly armies', () => {
  const enemy = army(2, 'nubia', '7,11');
  const state = { ...newCampaign(), armies: [enemy] };
  const view = campaignView(state);
  assert.equal(view.visibleHexIds.has(enemy.hexId), true);
  assert.equal(view.armies.length, 1);
  assert.equal(view.armies[0].unitCount, 2);
  state.armies = [army(3, 'egypt', '7,11', [0]), enemy];
  assert.equal(campaignView(state).armies.length, 1);
});

test('national invader detection follows conquered regions for every human and AI nation', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const region = CAMPAIGN_HEXES.find((hex) => hex.regionId && hex.territory !== nation);
    const enemy = army(1, region.territory, region.id);
    const state = { ...newCampaign(nation), cityOwners: { [region.regionId]: nation }, armies: [enemy] };
    assert.equal(campaignTerritory(state, region), nation);
    assert.equal(campaignView(state, nation).armies[0].unitCount, 2);
    assert.equal(campaignView({ ...state, cityOwners: {} }, nation).armies.length, 0);
  }
});

test('enemy armies cannot be selected or moved and do not consume the player reserve', () => {
  const enemy = army(2, 'nubia', '8,11');
  const state = { ...newCampaign(), armies: [army(1, 'egypt', '7,11'), enemy] };
  assert.equal(campaignUpkeep(state), 2);
  assert.equal(reachableHexes(state, 2).size, 0);
  assert.equal(moveArmy(state, 2, '7,12'), state);
  const next = nextSeason(state);
  assert.equal(next.armies.find((candidate) => candidate.id === 2), enemy);
  assert.deepEqual(next.lastTurnReport.armies.map((entry) => entry.armyId), [1]);
});
