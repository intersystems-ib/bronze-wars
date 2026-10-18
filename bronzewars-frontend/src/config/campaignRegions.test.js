import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_HEXES, CAMPAIGN_REGIONS, HEX_BY_ID, neighbors, newCampaign, campaignTerritory, campaignTerritoryInfo, occupiedRegions, terrainAttrition, nextSeason, loadCampaign } from './campaignRules.js';
import { assignCityRegions } from './campaignRegions.js';
import { startCityAction } from './campaignCityActions.js';
import { campaignView } from './campaignVisibility.js';
import { buildBorders } from './campaignBorders.js';

test('fixed city regions cover all national land exactly once and every hex connects back to its own city', () => {
  const assigned = new Set();
  for (const region of CAMPAIGN_REGIONS) {
    const remaining = new Set(region.hexIds);
    assert.ok(remaining.delete(region.city.hexId));
    const queue = [region.city.hexId];
    for (let index = 0; index < queue.length; index += 1) {
      for (const neighbor of neighbors(queue[index])) if (remaining.delete(neighbor.id)) queue.push(neighbor.id);
    }
    assert.equal(remaining.size, 0, `Disconnected region: ${region.id}`);
    assert.ok(region.hexIds.length > 1);
    for (const id of region.hexIds) {
      assert.equal(assigned.has(id), false);
      assigned.add(id);
      const hex = HEX_BY_ID.get(id);
      assert.equal(hex.land, true);
      assert.equal(hex.territory, region.city.nation);
      assert.equal(hex.regionId, region.id);
    }
  }
  for (const hex of CAMPAIGN_HEXES) assert.equal(assigned.has(hex.id), Boolean(hex.territory));
  assert.deepEqual(assignCityRegions(CAMPAIGN_HEXES), assignCityRegions([...CAMPAIGN_HEXES].reverse()));
});

test('conquering any city transfers its entire fixed region, borders, vision and terrain protection together', () => {
  for (const region of CAMPAIGN_REGIONS) {
    const winner = region.city.nation === 'nubia' ? 'egypt' : 'nubia';
    const original = { ...newCampaign(winner), grain: 100, nextArmyId: 2, armies: [{
      id: 1, name: 'Conquerors', designId: winner, hexId: region.city.hexId, moved: 0,
      units: [{ code: 'SPEARMEN', quantity: 1, initialStrength: 3000, strengths: [3000], speed: 2, grainCost: 1 }],
    }] };
    const conquered = nextSeason(startCityAction(original, 1, 'assault'));
    assert.equal(conquered.cityOwners[region.id], winner);
    const noArmies = { ...conquered, armies: [] };
    const winnerView = campaignView(noArmies, winner);
    const loserView = campaignView(noArmies, region.city.nation);
    for (const hex of CAMPAIGN_HEXES) {
      const expected = hex.regionId === region.id ? winner : hex.territory;
      assert.equal(campaignTerritory(conquered, hex), expected);
      assert.equal(campaignTerritory(original, hex), hex.territory);
      if (hex.regionId === region.id) {
        assert.equal(winnerView.visibleHexIds.has(hex.id), true);
        assert.equal(loserView.visibleHexIds.has(hex.id), false);
        assert.equal(terrainAttrition(conquered, hex, winner), 0);
      }
    }
    const borders = buildBorders(CAMPAIGN_HEXES.map((hex) => ({ ...hex, territory: campaignTerritory(conquered, hex) })));
    assert.ok(borders.some((border) => border.territory === winner && region.hexIds.includes(border.hexId)));
    const restored = loadCampaign({ getItem: () => JSON.stringify(conquered) }, winner);
    assert.deepEqual(restored, conquered);
    for (const id of region.hexIds) assert.equal(campaignTerritory(restored, HEX_BY_ID.get(id)), winner);
  }
});

test('existing city-only saves acquire whole regions and recapture restores the original region without changing its assignment', () => {
  const region = CAMPAIGN_REGIONS.find((entry) => entry.id === 'egypt-6');
  const legacy = { ...newCampaign('nubia'), cityOwners: { [region.id]: 'nubia' } };
  const restored = loadCampaign({ getItem: () => JSON.stringify(legacy) }, 'nubia');
  const recaptured = { ...restored, cityOwners: { [region.id]: 'egypt' } };
  for (const id of region.hexIds) {
    const hex = HEX_BY_ID.get(id);
    assert.equal(campaignTerritory(restored, hex), 'nubia');
    assert.equal(campaignTerritory(recaptured, hex), 'egypt');
    assert.equal(hex.regionId, region.id);
  }
});

test('occupation covers the whole conquered region and preserves original ownership through successive conquerors', () => {
  const region = CAMPAIGN_REGIONS.find((entry) => entry.id === 'egypt-6');
  const campaign = { ...newCampaign(), cityOwners: { [region.id]: 'nubia' } };
  for (const id of region.hexIds) {
    assert.deepEqual(campaignTerritoryInfo(campaign, HEX_BY_ID.get(id)), { originalOwner: 'egypt', controller: 'nubia', occupied: true });
  }
  assert.deepEqual(occupiedRegions(campaign, 'egypt').map((entry) => entry.cityId), [region.id]);
  assert.equal(occupiedRegions(campaign, 'nubia').length, 0);
  const transferred = { ...campaign, cityOwners: { [region.id]: 'hatti' } };
  assert.equal(occupiedRegions(transferred, 'egypt')[0].occupiedBy, 'hatti');
  assert.equal(occupiedRegions(transferred, 'nubia').length, 0);
  const restored = { ...campaign, cityOwners: { [region.id]: 'egypt' } };
  assert.equal(occupiedRegions(restored, 'egypt').length, 0);
  for (const id of region.hexIds) assert.equal(campaignTerritoryInfo(restored, HEX_BY_ID.get(id)).occupied, false);
  const neutral = CAMPAIGN_HEXES.find((hex) => hex.land && !hex.territory);
  assert.equal(campaignTerritoryInfo(campaign, neutral).occupied, false);
});
