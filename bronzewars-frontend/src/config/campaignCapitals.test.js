import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_CITIES, CAMPAIGN_HEXES, HEX_BY_ID, newCampaign, findSpawn, deploymentHexes, recruitArmy, nextSeason, loadCampaign } from './campaignRules.js';
import { campaignCapital, isCampaignCapital, cityOwner, startCityAction } from './campaignCityActions.js';
import { initializeCampaignAI, recruitmentCapacity, applyRecruitmentDecision, needsRecruitmentDecision } from './campaignAI.js';
import { movementContext } from './campaignMovement.js';

const catalogue = [{ code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 6, attack: 4, defense: 2, damage: 5 }];
const cities = (nation) => CAMPAIGN_CITIES.filter((city) => city.nation === nation);
const original = (nation) => cities(nation).find((city) => city.capital);
const loss = (campaign, nation, city = original(nation)) => ({ ...campaign, cityOwners: { ...campaign.cityOwners, [city.id]: nation === 'egypt' ? 'hatti' : 'egypt' } });
const recruit = (campaign) => recruitArmy(campaign, { name: 'New army', designId: campaign.nation, quantities: { LIGHT_INFANTRY: 4 } }, catalogue);

test('every nation relocates to its highest-producing controlled city, and the original always resumes on reconquest', () => {
  for (const [nation, replacement] of [['egypt', 'egypt-5'], ['hatti', 'hatti-3'], ['nubia', 'nubia-2']]) {
    const initial = newCampaign(nation);
    assert.equal(campaignCapital(initial).id, original(nation).id);
    const lost = loss(initial, nation);
    assert.equal(campaignCapital(lost).id, replacement);
    assert.equal(isCampaignCapital(lost, original(nation)), false);
    assert.equal(isCampaignCapital(lost, campaignCapital(lost)), true);
    assert.equal(findSpawn(lost), campaignCapital(lost).hexId);
    assert.ok(deploymentHexes(lost).every((hex) => hex.regionId === replacement));
    assert.equal(CAMPAIGN_CITIES.filter((city) => cityOwner(lost, city) === nation && isCampaignCapital(lost, city)).length, 1);
    const restored = { ...lost, cityOwners: { ...lost.cityOwners, [original(nation).id]: nation } };
    assert.equal(campaignCapital(restored).id, original(nation).id);
    assert.equal(isCampaignCapital(restored, CAMPAIGN_CITIES.find((city) => city.id === replacement)), false);
    assert.equal(findSpawn(restored), original(nation).hexId);
    assert.deepEqual(loadCampaign({ getItem: () => JSON.stringify(lost) }, nation, { fallbackToNew: false }), lost);
  }
});

test('human recruitment uses the provisional capital region, including a free neighboring hex when its city is occupied', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const lost = loss({ ...newCampaign(nation), grain: 100 }, nation);
    const first = recruit(lost), second = recruit(first);
    assert.equal(first.armies[0].hexId, campaignCapital(lost).hexId);
    assert.equal(second.armies.length, 2);
    assert.notEqual(second.armies[1].hexId, first.armies[0].hexId);
    assert.ok(second.armies.every((army) => HEX_BY_ID.get(army.hexId).regionId === campaignCapital(lost).id));
    assert.equal(second.grain, 52);
  }
});

test('a provisional capital falls back again after conquest, without moving merely because of raids or a full deployment region', () => {
  const lost = loss(newCampaign('nubia'), 'nubia');
  const twice = loss(lost, 'nubia', campaignCapital(lost));
  assert.equal(campaignCapital(twice).id, 'nubia-3');
  const raided = { ...lost, cityRaids: { 'nubia-2': { year: 0, nation: 'hatti' } } };
  assert.equal(campaignCapital(raided).id, 'nubia-2');
  assert.equal(campaignCapital({ ...raided, turn: 3 }).id, 'nubia-2');
  const full = { ...lost, armies: CAMPAIGN_HEXES.filter((hex) => hex.regionId === 'nubia-2').map((hex, index) => ({ id: index + 1, hexId: hex.id })) };
  assert.equal(campaignCapital(full).id, 'nubia-2');
  assert.equal(findSpawn(full), null);
});

test('no controlled city means no capital or recruitment; captured cities can host one and occupation halves their ranking output', () => {
  let campaign = { ...newCampaign('egypt'), cityOwners: Object.fromEntries(cities('egypt').map((city) => [city.id, 'hatti'])) };
  assert.equal(campaignCapital(campaign), null);
  assert.equal(findSpawn(campaign), null);
  assert.equal(recruit(campaign), campaign);
  assert.equal(campaignCapital(campaign, 'seapeople'), null);
  campaign = { ...campaign, cityOwners: { ...campaign.cityOwners, 'nubia-1': 'egypt', 'hatti-1': 'egypt' } };
  assert.equal(campaignCapital(campaign).id, 'nubia-1');
  assert.equal(recruit(campaign).armies[0].hexId, '7,34');
  campaign = { ...campaign, cityOwners: { ...campaign.cityOwners, 'egypt-3': 'egypt', 'egypt-2': 'egypt' } };
  assert.equal(campaignCapital(campaign).id, 'egypt-2'); // 5 native grain beats 8/2 occupied grain.
});

test('AI capacity, deployment and strategy use the provisional capital and do not duplicate earlier recruitment', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    let campaign = loss(initializeCampaignAI(newCampaign(nation === 'egypt' ? 'hatti' : 'egypt')), nation);
    const capacity = recruitmentCapacity(campaign, nation, catalogue);
    assert.equal(capacity.capitalAvailable, true);
    assert.equal(capacity.capitalCityId, campaignCapital(campaign, nation).id);
    assert.equal(capacity.capitalHexId, campaignCapital(campaign, nation).hexId);
    assert.ok(capacity.freeDeploymentHexes > 0 && capacity.options.length > 0);
    assert.equal(movementContext(campaign, nation).capitalCityId, capacity.capitalCityId);
    const oldWait = { ...campaign, aiRecruitment: { ...campaign.aiRecruitment, [nation]: { turn: 0, action: 'wait', source: 'LLM', reason: 'Capital lost', deploymentRuleVersion: 2 } } };
    assert.equal(needsRecruitmentDecision(oldWait, nation), true);
    const enlisted = applyRecruitmentDecision(oldWait, nation, { action: 'recruit', quantities: { LIGHT_INFANTRY: 4 }, reason: 'Use provisional capital' }, catalogue);
    assert.equal(enlisted.armies.length, 1);
    assert.equal(enlisted.armies[0].hexId, capacity.capitalHexId);
    assert.equal(needsRecruitmentDecision(enlisted, nation), false);
    assert.equal(needsRecruitmentDecision({ ...oldWait, aiRecruitment: { [nation]: { ...oldWait.aiRecruitment[nation], action: 'recruit' } } }, nation), false);
    assert.equal(needsRecruitmentDecision({ ...oldWait, aiRecruitment: { [nation]: { ...oldWait.aiRecruitment[nation], source: 'SKIPPED' } } }, nation), false);
  }
});

test('completing an assault restores the original capital immediately without moving existing armies', () => {
  const unit = { ...catalogue[0], quantity: 1, initialStrength: 3000, strengths: [3000] };
  let campaign = { ...loss(newCampaign('egypt'), 'egypt'), nextArmyId: 2, armies: [{ id: 1, name: 'Reconquest', designId: 'egypt', hexId: original('egypt').hexId, units: [unit], moved: 0, morale: 100 }] };
  assert.equal(campaignCapital(campaign).id, 'egypt-5');
  campaign = nextSeason(startCityAction(campaign, 1, 'assault'));
  assert.equal(campaignCapital(campaign).id, original('egypt').id);
  assert.equal(campaign.armies[0].hexId, original('egypt').hexId);
  assert.equal(campaign.lastTurnReport.capturedCities[0].cityId, original('egypt').id);
});
