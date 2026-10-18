import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mergedArmyUnits, wearMorale, recoverMorale } from './campaignStrength.js';
import { CAMPAIGN_HEXES, CAMPAIGN_CITIES, HEX_BY_ID, neighbors, newCampaign, armyTroops, armyUpkeep, remainingMovement, reachableHexes, mergeArmies, moveArmy, nextSeason, campaignProduction, loadCampaign, campaignTerritoryInfo } from './campaignRules.js';
import { movementContext, storeMovementDecision, executeMovementOrder, needsMovementDecision } from './campaignMovement.js';
import { cityProduction, startCityAction } from './campaignCityActions.js';
import { campaignView, hexDistance } from './campaignVisibility.js';

const unit = (strengths, code = 'SPEARMEN') => ({ code, initialStrength: 100, strengths, quantity: strengths.length, speed: 2, grainCost: 6, attack: 5, defense: 6, damage: 7 });
const army = (id, hexId, strengths, designId = 'hatti', morale = 100) => ({ id, hexId, name: `Army ${id}`, designId, morale, moved: 0, units: [unit(strengths)] });
const state = (armies, nation = 'egypt') => ({ ...newCampaign(nation), nextArmyId: Math.max(...armies.map((army) => army.id), 0) + 1, armies });
const origin = CAMPAIGN_HEXES.find((hex) => hex.territory === 'hatti' && hex.terrain === 'fertile' && neighbors(hex.id).filter((hex) => hex.territory === 'hatti').length >= 2);
const adjacent = neighbors(origin.id).filter((hex) => hex.territory === 'hatti');

test('30 and 50 combine to 80, overflow stays separate, and types and troops are preserved', () => {
  assert.deepEqual(mergedArmyUnits([unit([30])], [unit([50])])[0].strengths, [80]);
  assert.deepEqual(mergedArmyUnits([unit([30])], [unit([80])])[0].strengths, [30, 80]);
  assert.deepEqual(mergedArmyUnits([unit([30])], [unit([70])])[0].strengths, [100]);
  const existing = [unit([30, 100, 0]), unit([20], 'ARCHERS')];
  const incoming = [unit([50, 80, 0]), unit([40], 'ARCHERS'), unit([100], 'LIGHT_INFANTRY')];
  const result = mergedArmyUnits(existing, incoming);
  assert.equal(armyTroops({ units: result }), armyTroops({ units: existing }) + armyTroops({ units: incoming }));
  assert.deepEqual(result.map((group) => group.strengths), [[80, 100, 80], [60], [100]]);
  assert.ok(result.every((group) => group.quantity === group.strengths.length && group.strengths.every((strength) => strength > 0 && strength <= group.initialStrength)));
  assert.deepEqual(existing[0].strengths, [30, 100, 0]);
});

test('merging preserves the destination identity, weights morale by troops, saves and exhausts both armies', () => {
  const original = state([army(1, origin.id, [50], 'hatti', 60), army(2, adjacent[0].id, [30], 'hatti', 100)]);
  assert.equal(reachableHexes(original, 1, 'hatti').has(adjacent[0].id), true);
  const combined = mergeArmies(original, 1, 2, 'hatti');
  assert.equal(combined.armies.length, 1);
  assert.equal(combined.armies[0].id, 2);
  assert.equal(combined.armies[0].hexId, adjacent[0].id);
  assert.equal(combined.armies[0].name, 'Army 2');
  assert.equal(armyTroops(combined.armies[0]), 80);
  assert.equal(combined.armies[0].morale, 75);
  assert.equal(combined.armies[0].units[0].quantity, 1);
  assert.equal(armyUpkeep(combined.armies[0]), 0.6);
  assert.equal(remainingMovement(combined.armies[0]), 0);
  assert.equal(combined.nextArmyId, original.nextArmyId);
  assert.equal(combined.grain, original.grain);
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(combined) }, 'egypt', { fallbackToNew: false }), combined);
  assert.equal(original.armies.length, 2);
  assert.deepEqual(moveArmy(original, 1, adjacent[0].id, 'hatti'), combined);
});

test('friendly hexes are merge endpoints but cannot be crossed; hostile, exhausted and remote armies cannot merge', () => {
  const blockers = neighbors(origin.id).map((hex, index) => army(index + 2, hex.id, [50]));
  const original = state([army(1, origin.id, [50]), ...blockers]);
  assert.ok([...reachableHexes(original, 1, 'hatti').keys()].every((id) => neighbors(origin.id).some((hex) => hex.id === id)));
  assert.equal(mergeArmies(original, 1, 1, 'hatti'), original);
  const enemy = { ...original, armies: original.armies.map((army) => army.id === 2 ? { ...army, designId: 'nubia' } : army) };
  assert.equal(mergeArmies(enemy, 1, 2, 'hatti'), enemy);
  const exhausted = { ...original, armies: original.armies.map((army) => army.id === 1 ? { ...army, moved: 2 } : army) };
  assert.equal(mergeArmies(exhausted, 1, 2, 'hatti'), exhausted);
  const pending = { ...original, pendingEncounter: { id: 'pending' } };
  assert.equal(mergeArmies(pending, 1, 2, 'hatti'), pending);
  const remote = CAMPAIGN_HEXES.find((hex) => hex.land && hexDistance(hex.id, origin.id) > 5);
  const distant = state([army(1, origin.id, [50]), army(2, remote.id, [50])]);
  assert.equal(mergeArmies(distant, 1, 2, 'hatti'), distant);
});

test('merged armies can exceed the per-recruitment limit without losing full formations', () => {
  const combined = mergeArmies(state([army(1, origin.id, Array(99).fill(100)), army(2, adjacent[0].id, Array(99).fill(100))]), 1, 2, 'hatti');
  assert.equal(combined.armies[0].units[0].quantity, 198);
  assert.equal(armyTroops(combined.armies[0]), 19800);
  assert.ok(loadCampaign({ getItem: () => JSON.stringify(combined) }, 'egypt', { fallbackToNew: false }));
});

test('advice compares divisions rather than troops and permits autonomous defensive consolidation once', () => {
  const original = state([army(1, origin.id, [50]), army(2, adjacent[0].id, [30]), army(3, adjacent[1].id, [1, 1], 'nubia')]);
  const context = movementContext(original, 'hatti');
  const advice = context.reinforcementAdvice.find((entry) => entry.armyId === 1);
  assert.equal(context.priority, 'DEFEND');
  assert.equal(advice.recommendMerge, true);
  assert.equal(advice.strongerEnemies[0].unitCount, 2);
  const merge = context.options.find((option) => option.armyId === 1 && option.intent === 'MERGE' && option.targetArmyId === 2);
  const hold = context.options.find((option) => option.armyId === 2 && option.intent === 'HOLD');
  const ordered = storeMovementDecision(original, 'hatti', { orders: [{ optionId: merge.id }, { optionId: hold.id }], reason: 'Reunir divisiones' });
  const combined = executeMovementOrder(ordered, 'hatti');
  assert.equal(combined.armies.filter((army) => army.designId === 'hatti').length, 1);
  assert.equal(needsMovementDecision(combined, 'hatti'), false);
  assert.equal(executeMovementOrder(combined, 'hatti'), combined);
  assert.equal(remainingMovement(combined.armies.find((army) => army.id === 2)), 0);
});

test('unknown foreign contacts at two hexes never prove numerical superiority', () => {
  const home = CAMPAIGN_HEXES.find((hex) => hex.land && !hex.territory && neighbors(hex.id).length >= 2);
  const buddy = neighbors(home.id)[0];
  const contact = CAMPAIGN_HEXES.find((hex) => hex.land && !hex.territory && hexDistance(hex.id, home.id) === 2 && hexDistance(hex.id, buddy.id) > 1);
  const campaign = state([army(1, home.id, [100]), army(2, buddy.id, [100]), army(3, contact.id, Array(20).fill(100), 'nubia')]);
  const context = movementContext(campaign, 'hatti');
  const advice = context.reinforcementAdvice.find((entry) => entry.armyId === 1);
  assert.equal(campaignView(campaign, 'hatti').armies.find((army) => army.id === 3).unitCount, null);
  assert.equal(advice.recommendMerge, false);
  assert.deepEqual(advice.strongerEnemies, []);
  assert.equal(JSON.stringify(context).includes('Secret'), false);
});

test('terrain and famine reduce morale with the same sequential percentages and upward rounding as troop wear', () => {
  const desert = CAMPAIGN_HEXES.find((hex) => hex.terrain === 'desert' && !hex.territory);
  const campaign = { ...state([army(1, desert.id, [100, 100], 'egypt')]), grain: 0 };
  const next = nextSeason(campaign, { production: 0 });
  assert.equal(armyTroops(next.armies[0]), 184);
  assert.equal(next.armies[0].morale, 92);
  assert.equal(next.lastTurnReport.armies[0].moraleLosses, 8);
  assert.equal(wearMorale(1, 0.03), 0);
  assert.equal(wearMorale(100, 0), 100);
  assert.equal(recoverMorale(99), 100);
  assert.equal(recoverMorale(100), 100);
});

test('assaults reduce morale by 5 percent and native abundance recovers five percent of missing morale', () => {
  const city = CAMPAIGN_CITIES.find((city) => city.nation === 'egypt' && HEX_BY_ID.get(city.hexId).terrain === 'fertile');
  const attacking = { ...state([army(1, city.hexId, [100, 100], 'hatti')], 'hatti'), grain: 0 };
  const next = nextSeason(startCityAction(attacking, 1, 'assault'), { production: 0 });
  assert.equal(next.armies[0].morale, 90);
  const native = state([army(1, origin.id, [50], 'hatti', 60)], 'hatti');
  const recovered = nextSeason(native, { production: 100 });
  assert.equal(recovered.armies[0].morale, 62);
  assert.equal(recovered.lastTurnReport.armies[0].recoveredMorale, 2);
});

test('occupied garrisons have no terrain wear or recovery, while famine remains a supply loss', () => {
  const city = CAMPAIGN_CITIES.find((city) => city.nation === 'hatti');
  const hex = CAMPAIGN_HEXES.find((hex) => hex.regionId === city.id && hex.terrain === 'desert');
  const campaign = { ...state([army(1, hex.id, [50], 'egypt', 60)]), cityOwners: { [city.id]: 'egypt' } };
  assert.equal(campaignTerritoryInfo(campaign, hex).occupied, true);
  const next = nextSeason(campaign, { production: 100 });
  assert.equal(armyTroops(next.armies[0]), 50);
  assert.equal(next.armies[0].morale, 60);
  assert.equal(next.lastTurnReport.armies[0].terrainLosses, 0);
  assert.equal(next.lastTurnReport.armies[0].recoveredUnits, 0);
  const hungry = nextSeason({ ...campaign, grain: 0 }, { production: 0 });
  assert.equal(armyTroops(hungry.armies[0]), 47);
  assert.equal(hungry.armies[0].morale, 57);
  const context = movementContext({ ...campaign, nation: 'nubia' }, 'egypt');
  const recovery = context.options.find((option) => option.intent === 'RECOVER');
  assert.ok(recovery && recovery.targetHexId !== hex.id);
  assert.equal(campaignTerritoryInfo(campaign, HEX_BY_ID.get(recovery.targetHexId)).occupied, false);
});

test('occupied cities produce exactly half until liberation, harvest only annually and preserve fractional yields until balance rounding', () => {
  const city = CAMPAIGN_CITIES.find((city) => city.id === 'egypt-6');
  const campaign = { ...newCampaign('nubia'), cityOwners: { [city.id]: 'nubia' } };
  assert.equal(cityProduction(campaign, city), 2.5);
  assert.equal(campaignProduction(campaign), 22.5);
  let next = nextSeason(campaign);
  assert.equal(next.grain, 100);
  next = nextSeason(next);
  assert.equal(next.grain, 100);
  next = nextSeason(next);
  assert.equal(next.lastTurnReport.producedGrain, 22.5);
  assert.equal(next.grain, 123);
  assert.equal(cityProduction({ ...campaign, cityOwners: {} }, city), 5);
  const raider = { ...state([army(1, city.hexId, [100], 'hatti')], 'hatti'), cityOwners: campaign.cityOwners };
  const raided = startCityAction(raider, 1, 'raid');
  assert.equal(raided.grain, 103);
  assert.equal(cityProduction(raided, city), 0);
});
