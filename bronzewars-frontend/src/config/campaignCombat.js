import { armyMovement, armyTroops, applyCasualties, HEX_BY_ID, CAMPAIGN_CITIES } from './campaignRules.js';
import { hexDistance } from './campaignVisibility.js';
import { startCityAction } from './campaignCityActions.js';
import { retreatAfterBattle, markBattleArmiesProcessed } from './campaignRetreat.js';

export function campaignBattleLocation(hexId) {
  const hex = HEX_BY_ID.get(hexId);
  const region = CAMPAIGN_CITIES.find((city) => city.id === hex.regionId);
  const city = region ?? [...CAMPAIGN_CITIES].sort((a, b) => hexDistance(hexId, a.hexId) - hexDistance(hexId, b.hexId))[0];
  return { terrain: hex.terrain, cityId: city.id, regional: Boolean(region) };
}

export function pendingCombatReports(campaign) {
  return (campaign.campaignCombats || []).filter((report) => report.presented === false);
}

export function acknowledgeCombatReport(campaign, id) {
  return { ...campaign, campaignCombats: campaign.campaignCombats.map((report) => report.id === id ? { ...report, presented: true } : report) };
}

export function campaignArmyPower(army) {
  return army.units.reduce((sum, unit) => sum + unit.strengths.reduce((total, strength) => total + strength, 0)
    * (unit.attack + unit.defense + unit.damage) / 3, 0) * (0.5 + (army.morale ?? 100) / 200);
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
  const retreating = retreatAfterBattle(campaign, losingArmy, winningArmy, [...others, winningArmy]);
  const retreat = retreating?.hexId ?? null;
  const armies = [...others, winningArmy, ...(retreating ? [retreating] : [])].filter((army) => armyTroops(army) > 0);
  const report = { id: encounter.id, turn: campaign.turn, winnerId: winner.id, loserId: loser.id, winnerNation: winner.designId, loserNation: loser.designId,
    winnerLosses: winnerLoss.losses, loserLosses: retreat ? loserLoss.losses : armyTroops(loser), retreatHexId: retreat, hexId: encounter.hexId,
    retreatCityId: retreating?.campaignMission?.targetCityId ?? null,
    ...campaignBattleLocation(encounter.hexId), attackerNation: attacker.designId, presented: false };
  let next = markBattleArmiesProcessed({ ...campaign, armies, pendingEncounter: null, campaignCombats: [...(campaign.campaignCombats || []), report].slice(-50) }, [winner.id, loser.id]);
  if (winningArmy.campaignMission?.intent === 'RAID') next = startCityAction(next, winningArmy.id, 'raid', winningArmy.designId);
  if (['CONQUER', 'RECLAIM'].includes(winningArmy.campaignMission?.intent)) next = startCityAction(next, winningArmy.id, 'assault', winningArmy.designId);
  return next;
}
