import { CAMPAIGN_CITIES, HEX_BY_ID, CAMPAIGN_FACTIONS, armyMovement, armyTroops, campaignTerritory, moveArmy, neighbors, remainingMovement } from './campaignRules.js';
import { cityOwner } from './campaignCityActions.js';
import { hexDistance } from './campaignVisibility.js';

function pathsFrom(army, armies) {
  const occupied = new Map(armies.filter((other) => other.id !== army.id).map((other) => [other.hexId, other]));
  const parents = new Map([[army.hexId, null]]), queue = [army.hexId];
  for (let index = 0; index < queue.length; index += 1) {
    for (const hex of neighbors(queue[index])) {
      if (parents.has(hex.id) || occupied.has(hex.id)) continue;
      parents.set(hex.id, queue[index]); queue.push(hex.id);
    }
  }
  const path = (destination) => {
    if (!parents.has(destination)) return null;
    const result = [];
    for (let id = destination; id !== army.hexId; id = parents.get(id)) result.unshift(id);
    return result;
  };
  return { occupied, path, reachable: [...parents.keys()] };
}

function cityRoute(campaign, army, armies, allowCurrent = true) {
  const paths = pathsFrom(army, armies), options = [];
  for (const city of CAMPAIGN_CITIES.filter((city) => cityOwner(campaign, city) === army.designId)) {
    const garrison = paths.occupied.get(city.hexId);
    if (garrison && garrison.designId !== army.designId) continue;
    const goals = garrison ? neighbors(city.hexId).filter((hex) => hex.regionId === city.id) : [HEX_BY_ID.get(city.hexId)];
    for (const hex of goals) {
      if (paths.occupied.has(hex.id)) continue;
      const path = paths.path(hex.id);
      if (!path || (!allowCurrent && !path.length)) continue;
      options.push({ city, path, goal: hex.id, cityHex: hex.id === city.hexId });
    }
  }
  options.sort((a, b) => a.path.length - b.path.length || Number(b.cityHex) - Number(a.cityHex) || a.city.number - b.city.number || a.city.id.localeCompare(b.city.id));
  return { route: options[0] ?? null, paths };
}

export function markBattleArmiesProcessed(campaign, ids) {
  const aiMovement = { ...campaign.aiMovement };
  for (const nation of CAMPAIGN_FACTIONS.filter((nation) => nation !== (campaign.nation || 'egypt'))) {
    const matching = campaign.armies.filter((army) => army.designId === nation && ids.includes(army.id)).map((army) => army.id);
    if (!matching.length) continue;
    const previous = aiMovement[nation]?.turn === campaign.turn ? aiMovement[nation] : { turn: campaign.turn, decisions: [], processed: [] };
    aiMovement[nation] = { ...previous, processed: [...new Set([...previous.processed, ...matching])] };
  }
  return { ...campaign, aiMovement };
}

// Immediate disengagement shares the existing limit of three land hexes.
// Subsequent retreat movement uses ordinary seasonal movement and terrain costs.
export function retreatAfterBattle(campaign, loser, winner, armies) {
  if (!armyTroops(loser)) return null;
  const { route, paths } = cityRoute(campaign, loser, armies, false);
  let destination;
  if (route) {
    const steps = route.path.slice(0, 3);
    destination = [...steps].reverse().find((id) => hexDistance(id, winner.hexId) >= 2) ?? steps.at(-1);
  } else {
    const candidates = paths.reachable.filter((id) => id !== loser.hexId && paths.path(id).length <= 3 && hexDistance(id, winner.hexId) >= 2);
    candidates.sort((a, b) => Number(campaignTerritory(campaign, HEX_BY_ID.get(b)) === loser.designId) - Number(campaignTerritory(campaign, HEX_BY_ID.get(a)) === loser.designId)
      || paths.path(a).length - paths.path(b).length || hexDistance(b, winner.hexId) - hexDistance(a, winner.hexId));
    destination = candidates[0];
  }
  if (!destination) return null;
  const { cityAction, ...rest } = loser;
  return { ...rest, hexId: destination, moved: Math.ceil(armyMovement(loser.units)),
    campaignMission: { intent: route?.goal === destination ? 'RECOVER' : 'RETREAT', ...(route ? { targetCityId: route.city.id } : {}) } };
}

export function hasRetreatMovements(campaign) {
  return campaign.armies.some((army) => army.campaignMission?.intent === 'RETREAT' && remainingMovement(army) > 0);
}

export function advanceCampaignRetreats(campaign) {
  if (campaign.pendingEncounter) return campaign;
  let current = campaign;
  for (const id of campaign.armies.filter((army) => army.campaignMission?.intent === 'RETREAT' && remainingMovement(army) > 0).map((army) => army.id)) {
    let army = current.armies.find((army) => army.id === id);
    const { route } = cityRoute(current, army, current.armies);
    if (route) {
      for (const destination of route.path) {
        const next = moveArmy(current, id, destination, army.designId);
        if (next === current) break;
        current = next;
      }
    }
    army = current.armies.find((army) => army.id === id);
    const mission = { intent: route?.goal === army.hexId ? 'RECOVER' : 'RETREAT', ...(route ? { targetCityId: route.city.id } : {}) };
    current = { ...current, armies: current.armies.map((other) => other.id === id ? { ...other, campaignMission: mission, moved: Math.ceil(armyMovement(other.units)) } : other) };
    current = markBattleArmiesProcessed(current, [id]);
  }
  return current;
}
