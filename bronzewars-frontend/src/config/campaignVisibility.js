import { CAMPAIGN_HEXES, HEX_BY_ID, activeUnitCount, campaignTerritory } from './campaignRules.js';

export function hexDistance(fromId, toId) {
  const from = HEX_BY_ID.get(fromId);
  const to = HEX_BY_ID.get(toId);
  if (!from || !to) return Infinity;
  const q = (hex) => hex.col - (hex.row - hex.row % 2) / 2;
  const dq = q(from) - q(to);
  const dr = from.row - to.row;
  return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2;
}

export function armyUnitCount(army) {
  return army.units.reduce((sum, unit) => sum + activeUnitCount(unit), 0);
}

// The same observation can be used by a human interface or a campaign AI.
// Enemy contacts deliberately omit names, strength, morale and composition.
export function campaignView(campaign, nation = campaign.nation || 'egypt', { reveal = false } = {}) {
  const ownArmies = campaign.armies.filter((army) => army.designId === nation && armyUnitCount(army) > 0);
  const distanceToArmy = (id) => Math.min(...ownArmies.map((army) => hexDistance(army.hexId, id)));
  const visibleHexIds = new Set(CAMPAIGN_HEXES.filter((hex) => reveal || campaignTerritory(campaign, hex) === nation || distanceToArmy(hex.id) <= 1).map((hex) => hex.id));
  const armies = [];
  for (const army of campaign.armies) {
    if (armyUnitCount(army) === 0) continue;
    const own = army.designId === nation;
    const inTerritory = campaignTerritory(campaign, HEX_BY_ID.get(army.hexId)) === nation;
    const distance = distanceToArmy(army.hexId);
    if (!own && !inTerritory && !reveal && distance > 2) continue;
    const unitCount = reveal || own || inTerritory || distance <= 1 ? armyUnitCount(army) : null;
    armies.push(own ? { ...army, own, unitCount }
      : { id: army.id, designId: army.designId, hexId: army.hexId, own, unitCount, ...(army.campaignMission?.intent === 'RETREAT' ? { retreating: true } : {}) });
  }
  const ships = (campaign.seaPeoples?.ships || []).filter((ship) => reveal || nation === 'seapeople' || distanceToArmy(ship.hexId) <= 2)
    .map((ship) => ({ id: ship.id, hexId: ship.hexId, designId: 'seapeople' }));
  return { nation, visibleHexIds, armies, ships };
}
