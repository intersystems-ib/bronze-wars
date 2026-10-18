import { CAMPAIGN_CITIES, CAMPAIGN_HEXES, HEX_BY_ID, INITIAL_GRAIN, armyMovement, armyTroops } from './campaignRules.js';
import { adjacentCoordinates } from './campaignBorders.js';
import { randomArmyName } from './campaignArmyNames.js';
import { MIN_ARMY_DIVISIONS } from './armyRules.js';

export const INVASION_ARMY_BUDGET = 50;
export const SHIP_MOVEMENT = 2;
const roll = (random, min, max) => min + Math.floor(random() * (max - min + 1));
const adjacent = (id) => adjacentCoordinates(HEX_BY_ID.get(id)).map((key) => HEX_BY_ID.get(key)).filter(Boolean);

// Only the Mediterranean component is navigable for invasions, never the Red Sea.
export function invasionCoasts() {
  const sea = new Set(['0,0']), queue = ['0,0'];
  for (let index = 0; index < queue.length; index += 1) {
    for (const hex of adjacent(queue[index])) if (!hex.land && !sea.has(hex.id)) {
      sea.add(hex.id); queue.push(hex.id);
    }
  }
  return { sea, coasts: CAMPAIGN_HEXES.filter((hex) => hex.land && adjacent(hex.id).some((other) => sea.has(other.id))) };
}

function seaPaths(origin, sea, blocked = new Set()) {
  const parents = new Map([[origin, null]]), queue = [origin];
  for (let index = 0; index < queue.length; index += 1) {
    for (const hex of adjacent(queue[index])) if (sea.has(hex.id) && !blocked.has(hex.id) && !parents.has(hex.id)) {
      parents.set(hex.id, queue[index]); queue.push(hex.id);
    }
  }
  return (destination) => {
    if (!parents.has(destination)) return null;
    const route = [];
    for (let id = destination; id !== origin; id = parents.get(id)) route.unshift(id);
    return route;
  };
}

export function invasionRoster(catalogue, random = Math.random) {
  const available = catalogue.filter((unit) => ['LIGHT_INFANTRY', 'HEAVY_INFANTRY', 'SPEARMEN', 'ARCHERS'].includes(unit.code)
    && Number.isInteger(unit.initialStrength) && unit.initialStrength > 0 && Number.isFinite(unit.grainCost) && unit.grainCost > 0 && unit.speed > 0);
  const cheapest = [...available].sort((a, b) => a.grainCost - b.grainCost)[0];
  if (!cheapest || cheapest.grainCost * MIN_ARMY_DIVISIONS > INVASION_ARMY_BUDGET) return [];
  const budget = roll(random, Math.ceil(cheapest.grainCost * MIN_ARMY_DIVISIONS), INVASION_ARMY_BUDGET);
  const counts = new Map([[cheapest.code, MIN_ARMY_DIVISIONS]]);
  let remaining = budget - cheapest.grainCost * MIN_ARMY_DIVISIONS;
  for (;;) {
    const choices = available.filter((unit) => unit.grainCost <= remaining && (counts.get(unit.code) || 0) < 99);
    if (!choices.length) break;
    const unit = choices[roll(random, 0, choices.length - 1)];
    counts.set(unit.code, (counts.get(unit.code) || 0) + 1);
    remaining -= unit.grainCost;
  }
  return available.filter((unit) => counts.has(unit.code)).map((unit) => ({ ...unit, quantity: counts.get(unit.code),
    strengths: Array(counts.get(unit.code)).fill(unit.initialStrength) }));
}

export function advanceSeaInvasions(campaign, catalogue, { random = Math.random, language = 'es' } = {}) {
  if (campaign.version !== 2 || campaign.pendingEncounter || !catalogue.length) return campaign;
  const state = { nextInvasionTurn: campaign.turn + roll(random, 2, 10) * 3, lastProcessedTurn: -1, invasionCount: 0, ships: [], ...campaign.seaPeoples };
  if (state.lastProcessedTurn === campaign.turn) return campaign;
  const { sea, coasts } = invasionCoasts();
  const armies = [...campaign.armies], ships = [], landedIds = [];
  const occupiedLand = new Set(armies.map((army) => army.hexId));
  const occupiedSea = new Set(state.ships.map((ship) => ship.hexId));
  for (const vessel of state.ships) {
    occupiedSea.delete(vessel.hexId);
    const routeTo = seaPaths(vessel.hexId, sea, occupiedSea);
    const landings = coasts.filter((hex) => !occupiedLand.has(hex.id)).flatMap((hex) => adjacent(hex.id)
      .filter((water) => sea.has(water.id) && !occupiedSea.has(water.id))
      .map((water) => ({ hex, route: routeTo(water.id) })).filter((entry) => entry.route !== null));
    landings.sort((a, b) => Number(b.hex.id === vessel.targetHexId) - Number(a.hex.id === vessel.targetHexId) || a.route.length - b.route.length);
    const landing = landings[0];
    if (!landing) { ships.push(vessel); occupiedSea.add(vessel.hexId); continue; }
    if (landing.route.length <= SHIP_MOVEMENT) {
      // Disembarkation spends the army's movement; land strategy starts next season.
      armies.push({ ...vessel.army, hexId: landing.hex.id, moved: Math.ceil(armyMovement(vessel.army.units)), campaignMission: { intent: 'CONQUER' } });
      landedIds.push(vessel.army.id);
      occupiedLand.add(landing.hex.id);
    } else {
      const hexId = landing.route[SHIP_MOVEMENT - 1];
      ships.push({ ...vessel, hexId, targetHexId: landing.hex.id, army: { ...vessel.army, hexId: landing.hex.id } }); occupiedSea.add(hexId);
    }
  }
  let nextArmyId = campaign.nextArmyId, invasionCount = state.invasionCount, nextInvasionTurn = state.nextInvasionTurn;
  if (campaign.turn >= state.nextInvasionTurn) {
    const destinations = coasts.filter((hex) => !occupiedLand.has(hex.id) && !ships.some((ship) => ship.targetHexId === hex.id));
    const count = roll(random, 1, 3);
    let launched = 0;
    for (let index = 0; index < count && destinations.length; index += 1) {
      const target = destinations.splice(roll(random, 0, destinations.length - 1), 1)[0];
      const water = adjacent(target.id).find((hex) => sea.has(hex.id));
      const pathTo = seaPaths(water.id, sea, occupiedSea);
      const origins = [...sea].filter((id) => !occupiedSea.has(id) && pathTo(id)?.length >= 3 && pathTo(id).length <= 8);
      if (!origins.length) continue;
      const units = invasionRoster(catalogue, random);
      if (!units.length) continue;
      const hexId = origins[roll(random, 0, origins.length - 1)];
      const army = { id: nextArmyId++, name: randomArmyName('seapeople', [...armies, ...ships.map((ship) => ship.army)], { language, random }), designId: 'seapeople',
        units, morale: 100, moved: 0, hexId: target.id };
      ships.push({ id: `sea-${invasionCount + 1}-${index + 1}`, hexId, targetHexId: target.id, army });
      occupiedSea.add(hexId); launched += 1;
    }
    if (launched) { invasionCount += 1; nextInvasionTurn = campaign.turn + roll(random, 2, 10) * 3; }
  }
  const movement = campaign.aiMovement?.seapeople?.turn === campaign.turn ? campaign.aiMovement.seapeople : { turn: campaign.turn, decisions: [], processed: [] };
  return { ...campaign, armies, nextArmyId,
    ...(landedIds.length ? { aiMovement: { ...campaign.aiMovement, seapeople: { ...movement, processed: [...new Set([...movement.processed, ...landedIds])] } } } : {}),
    ...(invasionCount ? { foreignGrain: { ...campaign.foreignGrain, seapeople: campaign.foreignGrain?.seapeople ?? INITIAL_GRAIN } } : {}),
    seaPeoples: { ...state, nextInvasionTurn, invasionCount, ships, lastProcessedTurn: campaign.turn } };
}

export function validSeaPeoples(campaign) {
  const state = campaign.seaPeoples;
  if (state === undefined) return true;
  if (!state || Array.isArray(state) || typeof state !== 'object') return false;
  if (state.capitalCityId !== undefined && !CAMPAIGN_CITIES.some((city) => city.id === state.capitalCityId)) return false;
  if (state.nextInvasionTurn === undefined) return Object.keys(state).every((key) => key === 'capitalCityId');
  if (!Number.isInteger(state.nextInvasionTurn) || state.nextInvasionTurn < 0 || !Number.isInteger(state.lastProcessedTurn) || state.lastProcessedTurn < -1
    || state.lastProcessedTurn > campaign.turn || !Number.isInteger(state.invasionCount) || state.invasionCount < 0 || !Array.isArray(state.ships)) return false;
  const { sea, coasts } = invasionCoasts(), coastIds = new Set(coasts.map((hex) => hex.id));
  const ids = new Set(campaign.armies.map((army) => army.id)), positions = new Set(), shipIds = new Set();
  return state.ships.every((ship) => {
    const army = ship?.army;
    if (!ship || typeof ship.id !== 'string' || !ship.id || shipIds.has(ship.id) || !sea.has(ship.hexId) || positions.has(ship.hexId) || !coastIds.has(ship.targetHexId)
      || !army || army.designId !== 'seapeople' || typeof army.name !== 'string' || !army.name.trim() || !Number.isInteger(army.id) || army.id < 1 || army.id >= campaign.nextArmyId || ids.has(army.id)
      || army.morale !== 100 || army.moved !== 0 || army.hexId !== ship.targetHexId || !Array.isArray(army.units) || !army.units.length
      || army.units.some((unit) => !['LIGHT_INFANTRY', 'HEAVY_INFANTRY', 'SPEARMEN', 'ARCHERS'].includes(unit.code)
        || !Number.isInteger(unit.quantity) || unit.quantity < 1 || unit.quantity > 99 || !Number.isInteger(unit.initialStrength) || unit.initialStrength < 1
        || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0 || !Number.isFinite(unit.speed) || unit.speed <= 0
        || !Array.isArray(unit.strengths) || unit.strengths.length !== unit.quantity || unit.strengths.some((strength) => strength !== unit.initialStrength))
      || army.units.reduce((sum, unit) => sum + unit.quantity, 0) < MIN_ARMY_DIVISIONS
      || army.units.reduce((sum, unit) => sum + unit.quantity * unit.grainCost, 0) > INVASION_ARMY_BUDGET || armyTroops(army) <= 0) return false;
    ids.add(army.id); positions.add(ship.hexId); shipIds.add(ship.id); return true;
  });
}
