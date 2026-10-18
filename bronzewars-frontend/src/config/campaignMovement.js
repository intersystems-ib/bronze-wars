import { CAMPAIGN_CITIES, HEX_BY_ID, armyMovement, armyTroops, activeUnitCount, campaignProduction, campaignTerritory, occupiedRegions, moveArmy, neighbors, remainingMovement } from './campaignRules.js';
import { campaignView, hexDistance } from './campaignVisibility.js';
import { cityOwner, cityRaid, startCityAction } from './campaignCityActions.js';

export const CAMPAIGN_INTENTS = ['DEFEND', 'RECLAIM', 'RECOVER', 'RAID', 'CONQUER', 'CONTINUE', 'HOLD'];
export const ORDER_BATCH_SIZE = 4;
const progress = (campaign, nation) => campaign.aiMovement?.[nation]?.turn === campaign.turn
  ? campaign.aiMovement[nation] : { turn: campaign.turn, decisions: [], processed: [] };

export function needsMovementDecision(campaign, nation) {
  const processed = new Set(progress(campaign, nation).processed);
  return campaign.armies.some((army) => army.designId === nation && armyTroops(army) > 0 && !processed.has(army.id));
}

function pathsFrom(campaign, army, observation) {
  const occupied = new Map(observation.armies.filter((other) => other.id !== army.id).map((other) => [other.hexId, other]));
  const parents = new Map([[army.hexId, null]]);
  const queue = [army.hexId];
  for (let index = 0; index < queue.length; index += 1) {
    const id = queue[index];
    if (id !== army.hexId && occupied.has(id)) continue;
    for (const hex of neighbors(id)) {
      if (parents.has(hex.id)) continue;
      parents.set(hex.id, id);
      queue.push(hex.id);
    }
  }
  return (destination) => {
    if (!parents.has(destination)) return null;
    const result = [];
    for (let id = destination; id !== army.hexId; id = parents.get(id)) result.unshift(id);
    return result;
  };
}

function armyOptions(campaign, army, observation, invaders, occupied) {
  const pathTo = pathsFrom(campaign, army, observation);
  const options = [];
  const add = (intent, destination, target = {}) => {
    const path = pathTo(destination);
    if (!path) return;
    options.push({ id: `${army.id}:${intent}:${target.targetArmyId ?? target.cityId ?? destination}`, armyId: army.id,
      intent, targetHexId: destination, ...target, distance: path.length });
  };
  const visibleEnemies = observation.armies.filter((other) => !other.own);
  const threats = invaders.length ? invaders : visibleEnemies.filter((other) => hexDistance(army.hexId, other.hexId) <= 1);
  for (const threat of [...threats].sort((a, b) => hexDistance(army.hexId, a.hexId) - hexDistance(army.hexId, b.hexId)).slice(0, 2)) {
    add('DEFEND', threat.hexId, { targetArmyId: threat.id });
  }
  const maximum = army.units.reduce((sum, unit) => sum + unit.quantity * unit.initialStrength, 0);
  if (armyTroops(army) < maximum) {
    const ownHex = HEX_BY_ID.get(army.hexId);
    if (campaignTerritory(campaign, ownHex) === army.designId) add('RECOVER', army.hexId);
    else {
      const friendlyCities = CAMPAIGN_CITIES.filter((city) => cityOwner(campaign, city) === army.designId)
        .sort((a, b) => hexDistance(army.hexId, a.hexId) - hexDistance(army.hexId, b.hexId));
      for (const city of friendlyCities) {
        const destination = [HEX_BY_ID.get(city.hexId), ...neighbors(city.hexId)].find((hex) => campaignTerritory(campaign, hex) === army.designId
          && !observation.armies.some((other) => other.id !== army.id && other.hexId === hex.id) && pathTo(hex.id));
        if (destination) { add('RECOVER', destination.id); break; }
      }
    }
  }
  if (!invaders.length) {
    if (army.cityAction?.type === 'assault') add('CONTINUE', army.hexId, { cityId: army.cityAction.cityId });
    const lost = [...occupied].sort((a, b) => Number(b.capital) - Number(a.capital)
      || hexDistance(army.hexId, a.hexId) - hexDistance(army.hexId, b.hexId));
    for (const region of lost.filter((region) => pathTo(region.hexId)).slice(0, 2)) {
      add('RECLAIM', region.hexId, { cityId: region.cityId });
    }
    if (!occupied.length) {
      const cities = CAMPAIGN_CITIES.filter((city) => {
        const owner = observation.visibleHexIds.has(city.hexId) ? cityOwner(campaign, city) : city.nation;
        return owner !== army.designId;
      }).sort((a, b) => hexDistance(army.hexId, a.hexId) - hexDistance(army.hexId, b.hexId));
      const missionCity = army.campaignMission?.targetCityId;
      const targetCities = [...new Set([cities.find((city) => city.id === missionCity), ...cities].filter(Boolean))];
      for (const intent of ['RAID', 'CONQUER']) {
        const city = targetCities.find((candidate) => pathTo(candidate.hexId)
          && (intent !== 'RAID' || !observation.visibleHexIds.has(candidate.hexId) || !cityRaid(campaign, candidate)));
        if (city) add(intent, city.hexId, { cityId: city.id });
      }
    }
  }
  add('HOLD', army.hexId);
  return { maximum, options };
}

export function movementContext(campaign, nation) {
  const observation = campaignView(campaign, nation);
  const invaders = observation.armies.filter((army) => !army.own && campaignTerritory(campaign, HEX_BY_ID.get(army.hexId)) === nation);
  const occupied = occupiedRegions(campaign, nation);
  const state = progress(campaign, nation);
  const pending = observation.armies.filter((army) => army.own && !state.processed.includes(army.id)).slice(0, ORDER_BATCH_SIZE);
  const options = [];
  const armies = pending.map((army) => {
    const planned = armyOptions(campaign, army, observation, invaders, occupied);
    options.push(...planned.options);
    return { id: army.id, hexId: army.hexId, troops: armyTroops(army), maximumTroops: planned.maximum,
      morale: army.morale ?? 100, speed: armyMovement(army.units), remainingMovement: remainingMovement(army),
      mission: army.campaignMission?.intent ?? null,
      units: army.units.filter((unit) => activeUnitCount(unit) > 0).map((unit) => ({ code: unit.code, count: activeUnitCount(unit), speed: unit.speed,
        troops: unit.strengths.reduce((sum, strength) => sum + strength, 0), attack: unit.attack, defense: unit.defense, damage: unit.damage })) };
  });
  return { nation, turn: campaign.turn, priority: invaders.length ? 'DEFEND' : occupied.length ? 'RECLAIM' : 'FREE',
    reserve: campaign.foreignGrain?.[nation] ?? 0, annualProduction: campaignProduction(campaign, nation),
    occupiedRegions: occupied, invaders: invaders.map(({ id, hexId, unitCount }) => ({ id, hexId, unitCount })), armies, options };
}

export function storeMovementDecision(campaign, nation, decision) {
  const context = movementContext(campaign, nation);
  if (!decision || !Array.isArray(decision.orders) || decision.orders.length !== context.armies.length || typeof decision.reason !== 'string') throw new Error('INVALID_CAMPAIGN_ORDERS');
  const seen = new Set();
  const orders = decision.orders.map((order) => {
    const option = context.options.find((candidate) => candidate.id === order.optionId);
    if (!option || seen.has(option.armyId)) throw new Error('INVALID_CAMPAIGN_ORDER_OPTION');
    seen.add(option.armyId);
    return option;
  });
  if (context.priority === 'DEFEND' && context.options.some((option) => option.intent === 'DEFEND') && !orders.some((order) => order.intent === 'DEFEND')) throw new Error('INVASION_MUST_BE_DEFENDED');
  if (context.priority === 'RECLAIM' && context.options.some((option) => option.intent === 'RECLAIM') && !orders.some((order) => order.intent === 'RECLAIM')) throw new Error('OCCUPIED_TERRITORY_MUST_BE_RECLAIMED');
  const state = progress(campaign, nation);
  return { ...campaign, aiMovement: { ...campaign.aiMovement, [nation]: { ...state,
    decisions: [...state.decisions, ...orders], reason: decision.reason.slice(0, 500), source: 'LLM' } } };
}

export function pendingMovementOrder(campaign, nation) {
  const state = progress(campaign, nation);
  return state.decisions.find((order) => !state.processed.includes(order.armyId));
}

export function skipMovement(campaign, nation) {
  const state = progress(campaign, nation);
  return { ...campaign, aiMovement: { ...campaign.aiMovement, [nation]: { ...state,
    processed: campaign.armies.filter((army) => army.designId === nation).map((army) => army.id), source: 'SKIPPED' } } };
}

export function engageArmy(campaign, attackerId, defenderId, nation = campaign.nation || 'egypt') {
  if (campaign.pendingEncounter) return campaign;
  const attacker = campaign.armies.find((army) => army.id === attackerId && army.designId === nation);
  const defender = campaign.armies.find((army) => army.id === defenderId && army.designId !== nation);
  if (!attacker || !defender || !remainingMovement(attacker) || hexDistance(attacker.hexId, defender.hexId) !== 1) return campaign;
  const serial = (campaign.encounterSerial || 0) + 1;
  return { ...campaign, encounterSerial: serial, pendingEncounter: { id: `${campaign.turn}:${attackerId}:${defenderId}:${serial}`,
    turn: campaign.turn, attackerId, defenderId, hexId: defender.hexId },
    armies: campaign.armies.map((army) => {
      if (army.id !== attackerId) return army;
      const { cityAction, ...rest } = army;
      return { ...rest, moved: Math.ceil(armyMovement(army.units)) };
    }) };
}

export function executeMovementOrder(campaign, nation) {
  if (campaign.pendingEncounter) return campaign;
  const order = pendingMovementOrder(campaign, nation);
  if (!order) return campaign;
  const state = progress(campaign, nation);
  let current = { ...campaign, aiMovement: { ...campaign.aiMovement, [nation]: { ...state, processed: [...state.processed, order.armyId] } } };
  let army = current.armies.find((candidate) => candidate.id === order.armyId && candidate.designId === nation);
  if (!army) return current;
  const { cityId, targetArmyId, intent } = order;
  army = { ...army, campaignMission: { intent, ...(cityId ? { targetCityId: cityId } : {}) } };
  current = { ...current, armies: current.armies.map((candidate) => candidate.id === army.id ? army : candidate) };
  const observation = campaignView(current, nation);
  const target = targetArmyId ? observation.armies.find((other) => other.id === targetArmyId && !other.own)?.hexId : order.targetHexId;
  const path = target && pathsFrom(current, army, observation)(target);
  if (path) for (const destination of path) {
    army = current.armies.find((candidate) => candidate.id === order.armyId);
    if (!remainingMovement(army)) break;
    const occupant = current.armies.find((candidate) => candidate.hexId === destination);
    if (occupant) {
      if (occupant.designId !== nation) current = engageArmy(current, army.id, occupant.id, nation);
      break;
    }
    const next = moveArmy(current, army.id, destination, nation);
    if (next === current) break;
    current = next;
  }
  if (current.pendingEncounter) return current;
  army = current.armies.find((candidate) => candidate.id === order.armyId);
  if (cityId && army?.hexId === CAMPAIGN_CITIES.find((city) => city.id === cityId)?.hexId) {
    if (intent === 'RAID') current = startCityAction(current, army.id, 'raid', nation);
    if (['CONQUER', 'RECLAIM'].includes(intent)) current = startCityAction(current, army.id, 'assault', nation);
  }
  return current;
}

export function encounterPayload(campaign, gameId) {
  const encounter = campaign.pendingEncounter;
  if (!encounter) return null;
  const participant = (id) => { const army = campaign.armies.find((candidate) => candidate.id === id); return army ? { ...army, morale: army.morale ?? 100 } : null; };
  return { gameId, encounter, playerNation: campaign.nation,
    attacker: participant(encounter.attackerId),
    defender: participant(encounter.defenderId),
    terrain: HEX_BY_ID.get(encounter.hexId).terrain === 'desert' ? 'DESERT' : 'PLAINS' };
}

export function applyEncounterResult(campaign, battle, gameId) {
  const encounter = campaign.pendingEncounter;
  if (!encounter || battle.status !== 'FINISHED' || battle.campaign?.gameId !== gameId || battle.campaign?.encounterId !== encounter.id
    || (encounter.battleId && String(encounter.battleId) !== String(battle.id))) throw new Error('INVALID_CAMPAIGN_BATTLE_RESULT');
  const winner = battle.armies.find((army) => String(army.id) === String(battle.outcome.winnerArmyId));
  const winnerId = winner?.campaignArmyId;
  if (![encounter.attackerId, encounter.defenderId].includes(winnerId)) throw new Error('INVALID_CAMPAIGN_BATTLE_WINNER');
  const updated = campaign.armies.filter((army) => ![encounter.attackerId, encounter.defenderId].includes(army.id) || army.id === winnerId).map((army) => {
    if (army.id !== winnerId) return army;
    const units = army.units.map((unit) => ({ ...unit, strengths: unit.strengths.map((old, index) => {
      if (old <= 0) return 0;
      const result = winner.units.find((candidate) => candidate.campaignSlot === `${unit.code}:${index}`);
      if (!result || !Number.isInteger(result.currentStrength) || result.currentStrength < 0 || result.currentStrength > old) throw new Error('INVALID_CAMPAIGN_BATTLE_STRENGTH');
      return result.active ? result.currentStrength : 0;
    }) }));
    const troops = armyTroops({ units });
    const morale = troops ? Math.round(winner.units.filter((unit) => unit.active).reduce((sum, unit) => sum + unit.currentStrength * unit.morale, 0) / troops) : 0;
    return { ...army, units, morale, hexId: winnerId === encounter.attackerId ? encounter.hexId : army.hexId };
  }).filter((army) => armyTroops(army) > 0);
  let next = { ...campaign, armies: updated, pendingEncounter: null };
  const survivor = next.armies.find((army) => army.id === winnerId);
  if (survivor?.campaignMission?.targetCityId) {
    if (['CONQUER', 'RECLAIM'].includes(survivor.campaignMission.intent)) next = startCityAction(next, survivor.id, 'assault', survivor.designId);
    if (survivor.campaignMission.intent === 'RAID') next = startCityAction(next, survivor.id, 'raid', survivor.designId);
  }
  return next;
}
