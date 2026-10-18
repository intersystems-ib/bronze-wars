import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_HEXES, CAMPAIGN_CITIES, HEX_BY_ID, newCampaign, neighbors, armyTroops, remainingMovement, nextSeason, loadCampaign } from './campaignRules.js';
import { engageArmy, applyEncounterResult, movementContext, needsMovementDecision } from './campaignMovement.js';
import { advanceCampaignRetreats, hasRetreatMovements, retreatAfterBattle } from './campaignRetreat.js';
import { resolveAIEncounter } from './campaignCombat.js';
import { campaignView, hexDistance } from './campaignVisibility.js';
import { initializeCampaignAI } from './campaignAI.js';

const unit = { code: 'LIGHT_INFANTRY', quantity: 2, initialStrength: 60, strengths: [60, 60], speed: 2, grainCost: 6, attack: 4, defense: 4, damage: 5 };
const army = (id, designId, hexId) => ({ id, designId, hexId, name: `Army ${id}`, units: [structuredClone(unit)], morale: 80, moved: 0 });
const initial = () => engageArmy(initializeCampaignAI({ ...newCampaign('nubia'), nextArmyId: 3, armies: [army(1, 'nubia', neighbors('8,32')[0].id), army(2, 'egypt', '8,32')] }), 1, 2);
const slots = (strengths, active, morale) => strengths.map((currentStrength, index) => ({ campaignSlot: `LIGHT_INFANTRY:${index}`, currentStrength, active, morale }));
const battle = (campaign) => ({ id: '9', status: 'FINISHED', finishReason: 'WITHDRAWAL', campaign: { gameId: 'test', encounterId: campaign.pendingEncounter.id }, outcome: { winnerArmyId: '101' }, armies: [
  { id: '101', campaignArmyId: 1, units: slots([50, 50], true, 80) },
  { id: '102', campaignArmyId: 2, units: slots([15, 15], false, 17) },
] });

test('escaped tactical formations return with their exact troops, morale and identity, with an exhausted retreat towards the nearest safe friendly city', () => {
  const campaign = initial(), result = applyEncounterResult(campaign, battle(campaign), 'test');
  const loser = result.armies.find((army) => army.id === 2);
  assert.equal(result.armies.length, 2);
  assert.equal(armyTroops(loser), 30);
  assert.equal(loser.morale, 17);
  assert.equal(loser.name, 'Army 2');
  assert.deepEqual(loser.units[0].strengths, [15, 15]);
  assert.equal(loser.campaignMission.intent, 'RETREAT');
  assert.equal(loser.campaignMission.targetCityId, 'egypt-5');
  assert.ok(hexDistance('8,32', loser.hexId) <= 3);
  assert.ok(hexDistance('8,32', loser.hexId) >= 2);
  assert.equal(remainingMovement(loser), 0);
  assert.equal(result.nextArmyId, campaign.nextArmyId);
  assert.equal(result.pendingEncounter, null);
  assert.equal(new Set(result.armies.map((army) => army.hexId)).size, 2);
  assert.deepEqual(result.aiMovement.egypt.processed, [2]);
  assert.equal(needsMovementDecision(result, 'egypt'), false);
  assert.deepEqual(movementContext(result, 'egypt').armies, []);
  assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(result) }, 'nubia', { fallbackToNew: false }), result);
  assert.equal(advanceCampaignRetreats(result), result);
  assert.throws(() => applyEncounterResult(result, battle(campaign), 'test'), /RESULT/);
});

test('prisoners and dead troops do not become fleeing armies, and corrupt fleeing strengths are rejected', () => {
  const campaign = initial(), outcome = battle(campaign);
  outcome.finishReason = 'SURRENDER';
  outcome.armies[1].units = [slots([10], false, 12)[0], slots([0, 20], true, 20)[1]];
  const result = applyEncounterResult(campaign, outcome, 'test');
  const loser = result.armies.find((army) => army.id === 2);
  assert.equal(armyTroops(loser), 10);
  assert.deepEqual(loser.units[0].strengths, [10, 0]);
  assert.equal(loser.morale, 12);
  outcome.armies[1].units = slots([10, 20], true, 20);
  assert.equal(applyEncounterResult(campaign, outcome, 'test').armies.length, 1);
  outcome.armies[1].units = slots([0, 0], false, 0);
  assert.equal(applyEncounterResult(campaign, outcome, 'test').armies.length, 1);
  outcome.armies[1].units = slots([61, 0], false, 17);
  assert.throws(() => applyEncounterResult(campaign, outcome, 'test'), /STRENGTH/);
});

test('a victorious defender stays in place and the defeated human attacker also retains its escaped troops', () => {
  const campaign = initial(), outcome = battle(campaign);
  outcome.outcome.winnerArmyId = '102';
  outcome.armies[0].units = slots([15, 15], false, 17);
  outcome.armies[1].units = slots([50, 50], true, 80);
  const result = applyEncounterResult(campaign, outcome, 'test');
  assert.equal(result.armies.find((army) => army.id === 2).hexId, '8,32');
  const human = result.armies.find((army) => army.id === 1);
  assert.ok(human && armyTroops(human) === 30);
  assert.notEqual(human.hexId, '8,32');
  assert.equal(human.morale, 17);
  assert.ok(['RETREAT', 'RECOVER'].includes(human.campaignMission.intent));
});

test('retreats advance once per season using ordinary movement, remain saved under fog, and switch to recovery only on reaching the city', () => {
  const campaign = initial();
  let current = applyEncounterResult(campaign, battle(campaign), 'test');
  let turns = 0;
  while (current.armies.find((army) => army.id === 2).campaignMission.intent === 'RETREAT' && turns < 20) {
    current = nextSeason(current);
    assert.equal(hasRetreatMovements(current), true);
    const before = current.armies.find((army) => army.id === 2);
    const next = advanceCampaignRetreats(current), after = next.armies.find((army) => army.id === 2);
    assert.ok(hexDistance(before.hexId, after.hexId) <= (HEX_BY_ID.get(before.hexId).terrain === 'desert' ? 1 : 2));
    assert.equal(armyTroops(after), armyTroops(before));
    assert.equal(remainingMovement(after), 0);
    assert.equal(advanceCampaignRetreats(next), next);
    assert.ok(loadCampaign({ getItem: () => JSON.stringify(next) }, 'nubia', { fallbackToNew: false }));
    current = next; turns += 1;
  }
  const survivor = current.armies.find((army) => army.id === 2);
  assert.ok(turns < 20);
  assert.equal(survivor.hexId, CAMPAIGN_CITIES.find((city) => city.id === 'egypt-5').hexId);
  assert.equal(survivor.campaignMission.intent, 'RECOVER');
});

test('a captured destination is replaced and friendly city garrisons use a free adjacent hex without stacking', () => {
  const campaign = initial();
  let current = applyEncounterResult(campaign, battle(campaign), 'test');
  current = { ...current, cityOwners: { 'egypt-5': 'nubia' } };
  const rerouted = advanceCampaignRetreats(nextSeason(current));
  assert.notEqual(rerouted.armies.find((army) => army.id === 2).campaignMission.targetCityId, 'egypt-5');
  const withGarrison = { ...applyEncounterResult(campaign, battle(campaign), 'test'), nextArmyId: 4 };
  withGarrison.armies.push(army(3, 'egypt', '9,26'));
  let moved = withGarrison;
  for (let index = 0; index < 15 && moved.armies.find((army) => army.id === 2).campaignMission.intent === 'RETREAT'; index += 1) moved = advanceCampaignRetreats(nextSeason(moved));
  const loser = moved.armies.find((army) => army.id === 2);
  assert.equal(loser.campaignMission.intent, 'RECOVER');
  assert.equal(hexDistance(loser.hexId, '9,26'), 1);
  assert.equal(new Set(moved.armies.map((army) => army.hexId)).size, moved.armies.length);
});

test('survivors without cities remain on a legal escape hex, while truly trapped troops cannot cross an occupied ring', () => {
  const campaign = initial(), winner = { ...campaign.armies[0], hexId: '8,32' }, loser = campaign.armies[1];
  const cityOwners = Object.fromEntries(CAMPAIGN_CITIES.filter((city) => city.nation === 'egypt').map((city) => [city.id, 'hatti']));
  const escape = retreatAfterBattle({ ...campaign, cityOwners }, loser, winner, [winner]);
  assert.ok(escape && HEX_BY_ID.get(escape.hexId).land);
  assert.equal(escape.campaignMission.intent, 'RETREAT');
  assert.equal(escape.campaignMission.targetCityId, undefined);
  const blocked = neighbors(loser.hexId).map((hex, index) => army(index + 3, 'nubia', hex.id));
  assert.equal(retreatAfterBattle(campaign, loser, winner, [winner, ...blocked]), null);
});

test('AI versus AI defeats keep their survivors and use the same city retreat mission', () => {
  const campaign = initial();
  campaign.nation = 'hatti';
  campaign.armies[0].units[0] = { ...unit, quantity: 10, strengths: Array(10).fill(60) };
  const result = resolveAIEncounter(campaign), loser = result.armies.find((army) => army.id === 2);
  assert.ok(loser && armyTroops(loser) > 0);
  assert.equal(loser.campaignMission.targetCityId, 'egypt-5');
  assert.equal(loser.campaignMission.intent, 'RETREAT');
  assert.equal(result.campaignCombats.at(-1).retreatCityId, 'egypt-5');
  assert.ok(result.aiMovement.egypt.processed.includes(2));
  const observation = campaignView({ ...result, nation: 'egypt' }, 'egypt');
  assert.ok(observation.armies.some((army) => army.id === 2));
});
