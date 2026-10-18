import { armyMovement, armyTroops, applyCasualties, campaignTerritory, neighbors } from './campaignRules.js';
import { hexDistance } from './campaignVisibility.js';
import { startCityAction } from './campaignCityActions.js';

export function campaignArmyPower(army) {
  return army.units.reduce((sum, unit) => sum + unit.strengths.reduce((total, strength) => total + strength, 0)
    * (unit.attack + unit.defense + unit.damage) / 3, 0) * (0.5 + (army.morale ?? 100) / 200);
}

function retreatHex(campaign, loser, winner, armies) {
  const occupied = new Set(armies.filter((army) => army.id !== loser.id).map((army) => army.hexId));
  const queue = [{ id: loser.hexId, distance: 0 }];
  const visited = new Set([loser.hexId]);
  const candidates = [];
  for (let index = 0; index < queue.length; index += 1) {
    const entry = queue[index];
    if (entry.distance >= 3) continue;
    for (const hex of neighbors(entry.id)) {
      if (visited.has(hex.id) || occupied.has(hex.id)) continue;
      visited.add(hex.id);
      const distance = entry.distance + 1;
      queue.push({ id: hex.id, distance });
      if (hexDistance(hex.id, winner.hexId) >= 2) candidates.push({ hex, distance });
    }
  }
  candidates.sort((a, b) => Number(campaignTerritory(campaign, b.hex) === loser.designId) - Number(campaignTerritory(campaign, a.hex) === loser.designId)
    || a.distance - b.distance || hexDistance(b.hex.id, winner.hexId) - hexDistance(a.hex.id, winner.hexId));
  return candidates[0]?.hex.id ?? null;
}

export function resolveAIEncounter(campaign) {
  const encounter = campaign.pendingEncounter;
  if (!encounter) return campaign;
  const attacker = campaign.armies.find((army) => army.id === encounter.attackerId);
  const defender = campaign.armies.find((army) => army.id === encounter.defenderId);
  if (!attacker || !defender || [attacker.designId, defender.designId].includes(campaign.nation || 'egypt')) throw new Error('AI_COMBAT_REQUIRES_TWO_AI_ARMIES');
  const attackPower = campaignArmyPower(attacker);
  const defensePower = campaignArmyPower(defender) * 1.1;
  const winner = attackPower > defensePower ? attacker : defender;
  const loser = winner.id === attacker.id ? defender : attacker;
  const winnerPower = Math.max(1, winner.id === attacker.id ? attackPower : defensePower);
  const loserPower = Math.max(1, loser.id === attacker.id ? attackPower : defensePower);
  const winnerTroops = armyTroops(winner);
  const winnerRate = Math.min(0.35, 0.1 + 0.25 * loserPower / winnerPower);
  const winnerLoss = applyCasualties(winner.units, Math.min(winnerTroops - 1, Math.ceil(winnerTroops * winnerRate)) / winnerTroops);
  const loserLoss = applyCasualties(loser.units, Math.min(0.85, 0.4 + 0.2 * winnerPower / loserPower));
  const winningArmy = { ...winner, units: winnerLoss.units, morale: Math.max(10, (winner.morale ?? 100) - 5),
    moved: Math.ceil(armyMovement(winner.units)), hexId: winner.id === attacker.id ? encounter.hexId : winner.hexId };
  const losingArmy = { ...loser, units: loserLoss.units, morale: Math.max(10, Math.floor((loser.morale ?? 100) / 2)),
    moved: Math.ceil(armyMovement(loser.units)), campaignMission: { intent: 'RECOVER' } };
  delete losingArmy.cityAction;
  const others = campaign.armies.filter((army) => ![winner.id, loser.id].includes(army.id));
  const retreat = armyTroops(losingArmy) > 0 ? retreatHex(campaign, losingArmy, winningArmy, [...others, winningArmy]) : null;
  if (retreat) losingArmy.hexId = retreat;
  const armies = [...others, winningArmy, ...(retreat ? [losingArmy] : [])].filter((army) => armyTroops(army) > 0);
  const report = { id: encounter.id, turn: campaign.turn, winnerId: winner.id, loserId: loser.id, winnerNation: winner.designId, loserNation: loser.designId,
    winnerLosses: winnerLoss.losses, loserLosses: retreat ? loserLoss.losses : armyTroops(loser), retreatHexId: retreat, hexId: encounter.hexId };
  let next = { ...campaign, armies, pendingEncounter: null, campaignCombats: [...(campaign.campaignCombats || []), report].slice(-50) };
  if (winningArmy.campaignMission?.intent === 'RAID') next = startCityAction(next, winningArmy.id, 'raid', winningArmy.designId);
  if (['CONQUER', 'RECLAIM'].includes(winningArmy.campaignMission?.intent)) next = startCityAction(next, winningArmy.id, 'assault', winningArmy.designId);
  return next;
}
