import { TERRAIN_TYPES, inPolygon, terrainAt, riverAt, isNileValley } from './campaignTerrain.js';
import { assignTerritories, adjacentCoordinates, buildBorders } from './campaignBorders.js';

export const CAMPAIGN_STORAGE_KEY = 'bronzewars.campaign.egypt.v1';
export const UPKEEP_RATE = 0.1;
export const SUPPLY_ATTRITION_RATE = 0.05;
export const RECOVERY_RATE = 0.05;
export const INITIAL_GRAIN = 100;
export const SEASONS = ['inundation', 'emergence', 'harvest'];
export const MAP_WIDTH = 1024;
export const MAP_HEIGHT = 1536;
const RADIUS = 24;
const HEX_WIDTH = Math.sqrt(3) * RADIUS;

// Coastlines in the supplied map's coordinate system. Rivers remain traversable.
const LAND = [[0,292],[80,320],[160,318],[225,280],[290,259],[350,280],[415,315],[480,345],[560,327],[618,300],[650,245],[680,165],[702,80],[738,45],[766,0],[1024,0],[1024,1536],[0,1536]];
const RED_SEA = [[427,378],[440,440],[490,528],[542,610],[576,643],[603,625],[637,540],[657,441],[681,380],[690,327],[711,298],[704,370],[687,450],[661,548],[643,608],[666,652],[712,725],[749,811],[784,882],[822,976],[860,1072],[908,1170],[958,1270],[1000,1350],[1024,1365],[1024,1536],[1014,1536],[979,1400],[922,1328],[867,1311],[822,1289],[788,1268],[751,1229],[730,1172],[696,1129],[666,1120],[641,1094],[618,1040],[605,977],[579,920],[559,860],[540,812],[511,768],[495,724],[487,675],[465,620],[442,562],[433,511],[424,466],[417,416]];

function pointOnLand(x, y) {
  return inPolygon(x, y, LAND) && !inPolygon(x, y, RED_SEA);
}

export const CAMPAIGN_HEXES = [];
for (let row = 0; row < 42; row += 1) {
  for (let col = 0; col < 24; col += 1) {
    const x = HEX_WIDTH * (col + 0.5 + (row % 2) / 2);
    const y = RADIUS + row * RADIUS * 1.5;
    if (x + HEX_WIDTH / 2 > MAP_WIDTH || y + RADIUS > MAP_HEIGHT) continue;
    // Sample the whole hex: a coastal hex with land remains traversable even
    // when its centre falls in the sea. Include corners and edge midpoints.
    const samples = [[x, y], ...Array.from({ length: 12 }, (_, i) => {
      const angle = (Math.PI / 180) * (30 * i - 30);
      const radius = i % 2 ? RADIUS * Math.sqrt(3) / 2 : RADIUS;
      return [x + radius * Math.cos(angle), y + radius * Math.sin(angle)];
    })];
    const land = samples.some(([sx, sy]) => pointOnLand(sx, sy));
    const mixedCoast = land && samples.some(([sx, sy]) => !pointOnLand(sx, sy));
    const river = land ? riverAt(x, y) : null;
    CAMPAIGN_HEXES.push({
      id: `${col},${row}`, col, row, x, y,
      land, mixedCoast, terrain: mixedCoast ? 'coast' : terrainAt(x, y, land), river,
      nileValley: land && isNileValley(x, y),
      points: Array.from({ length: 6 }, (_, i) => {
        const angle = (Math.PI / 180) * (60 * i - 30);
        return `${x + RADIUS * Math.cos(angle)},${y + RADIUS * Math.sin(angle)}`;
      }).join(' '),
    });
  }
}
export const HEX_BY_ID = new Map(CAMPAIGN_HEXES.map((hex) => [hex.id, hex]));
for (const hex of CAMPAIGN_HEXES) {
  if (hex.land && adjacentCoordinates(hex).some((id) => HEX_BY_ID.get(id)?.land === false)) hex.terrain = 'coast';
  hex.waterAccess = hex.terrain === 'water' || hex.terrain === 'coast' || hex.terrain === 'fertile' || Boolean(hex.river);
  hex.production = hex.waterAccess ? 1 : 0;
}
const territories = assignTerritories(CAMPAIGN_HEXES);
for (const hex of CAMPAIGN_HEXES) hex.territory = territories.get(hex.id);
export const CAMPAIGN_BORDERS = buildBorders(CAMPAIGN_HEXES);

export function neighbors(id) {
  const hex = HEX_BY_ID.get(id);
  if (!hex) return [];
  const shift = hex.row % 2;
  return [[-1,0],[1,0],[shift-1,-1],[shift,-1],[shift-1,1],[shift,1]]
    .map(([dc, dr]) => HEX_BY_ID.get(`${hex.col + dc},${hex.row + dr}`))
    .filter((candidate) => candidate?.land);
}

export function armyMovement(units) {
  const count = units.reduce((sum, unit) => sum + unit.quantity, 0);
  return count ? units.reduce((sum, unit) => sum + unit.quantity * unit.speed, 0) / count : 0;
}

export function remainingMovement(army) {
  const remaining = Math.max(0, Math.floor(armyMovement(army.units) - army.moved + 1e-9));
  return TERRAIN_TYPES[HEX_BY_ID.get(army.hexId)?.terrain]?.difficult
    ? (army.moved > 0 ? 0 : Math.min(1, remaining)) : remaining;
}

export function armyUpkeep(army) {
  return Math.round(army.units.reduce((sum, unit) => sum + unit.quantity * unit.grainCost, 0) * UPKEEP_RATE * 100) / 100;
}

export function campaignUpkeep(campaign) {
  return Math.round(campaign.armies.reduce((sum, army) => sum + armyUpkeep(army), 0) * 100) / 100;
}

export function campaignProduction(campaign) {
  const nation = campaign.nation || 'egypt';
  return CAMPAIGN_HEXES.filter((hex) => hex.land && hex.territory === nation)
    .reduce((sum, hex) => sum + hex.production, 0);
}

export function campaignEconomy(campaign, production = campaignProduction(campaign)) {
  const consumption = campaignUpkeep(campaign);
  const situation = campaign.grain <= 0 ? 'famine'
    : production > consumption + 1e-9 ? 'abundance' : 'scarcity';
  return { production, consumption, situation };
}

export function reachableHexes(campaign, armyId) {
  const army = campaign.armies.find((candidate) => candidate.id === armyId);
  if (!army) return new Map();
  const budget = Math.floor(armyMovement(army.units) - army.moved + 1e-9);
  const limit = remainingMovement(army);
  const occupied = new Set(campaign.armies.filter((candidate) => candidate.id !== armyId).map((candidate) => candidate.hexId));
  const distances = new Map([[army.hexId, 0]]);
  const queue = [army.hexId];
  for (let i = 0; i < queue.length; i += 1) {
    const id = queue[i];
    if (distances.get(id) >= limit || (id !== army.hexId && TERRAIN_TYPES[HEX_BY_ID.get(id).terrain].difficult)) continue;
    for (const neighbor of neighbors(id)) {
      if (occupied.has(neighbor.id) || distances.has(neighbor.id)) continue;
      distances.set(neighbor.id, distances.get(id) + 1);
      queue.push(neighbor.id);
    }
  }
  distances.delete(army.hexId);
  return new Map([...distances].map(([id, distance]) => [id,
    TERRAIN_TYPES[HEX_BY_ID.get(army.hexId).terrain].difficult || TERRAIN_TYPES[HEX_BY_ID.get(id).terrain].difficult ? budget : distance,
  ]));
}

export function findSpawn(campaign) {
  const occupied = new Set(campaign.armies.map((army) => army.hexId));
  // Muster near the Nile delta, expanding to the nearest unoccupied land hex.
  const queue = ['7,11'];
  const visited = new Set(queue);
  for (let i = 0; i < queue.length; i += 1) {
    const id = queue[i];
    if (!occupied.has(id) && HEX_BY_ID.get(id)?.land) return id;
    for (const neighbor of neighbors(id)) {
      if (visited.has(neighbor.id)) continue;
      visited.add(neighbor.id);
      queue.push(neighbor.id);
    }
  }
  return null;
}

export function newCampaign() {
  return { version: 1, turn: 0, grain: INITIAL_GRAIN, nextArmyId: 1, armies: [] };
}

export function recruitArmy(campaign, { name, designId, quantities }, unitTypes) {
  const units = unitTypes.filter((unit) => quantities[unit.code] > 0).map((unit) => ({
    code: unit.code, quantity: quantities[unit.code], speed: unit.speed,
    attack: unit.attack, defense: unit.defense, damage: unit.damage, grainCost: unit.grainCost,
  }));
  if (!units.length || units.some((unit) => !Number.isInteger(unit.quantity) || unit.quantity < 1 || unit.quantity > 99 || !Number.isFinite(unit.speed) || unit.speed <= 0 || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0)) return campaign;
  const cost = units.reduce((sum, unit) => sum + unit.quantity * unit.grainCost, 0);
  const hexId = findSpawn(campaign);
  if (cost > campaign.grain || !hexId) return campaign;
  return {
    ...campaign, grain: campaign.grain - cost, nextArmyId: campaign.nextArmyId + 1,
    armies: [...campaign.armies, { id: campaign.nextArmyId, name: name.trim().slice(0,80), designId, units, initialUnits: units.map((unit) => ({ ...unit })), hexId, moved: 0 }],
  };
}

export function moveArmy(campaign, armyId, destination) {
  const cost = reachableHexes(campaign, armyId).get(destination);
  if (!cost) return campaign;
  return { ...campaign, armies: campaign.armies.map((army) => army.id === armyId ? { ...army, hexId: destination, moved: army.moved + cost } : army) };
}

// Round losses once per army, then distribute them proportionally across troop types.
// Rounding each troop type separately would multiply attrition for mixed armies.
export function applyCasualties(units, rate) {
  const total = units.reduce((sum, unit) => sum + unit.quantity, 0);
  const losses = Math.min(total, Math.max(0, Math.ceil(total * rate - 1e-9)));
  const allocations = units.map((unit, index) => {
    const share = total ? losses * unit.quantity / total : 0;
    return { index, lost: Math.floor(share), remainder: share - Math.floor(share) };
  });
  let extra = losses - allocations.reduce((sum, entry) => sum + entry.lost, 0);
  for (const entry of [...allocations].sort((a, b) => b.remainder - a.remainder || a.index - b.index)) {
    if (extra <= 0) break;
    if (entry.lost < units[entry.index].quantity) { entry.lost += 1; extra -= 1; }
  }
  return { losses, units: units.map((unit, index) => ({ ...unit, quantity: unit.quantity - allocations[index].lost })).filter((unit) => unit.quantity > 0) };
}

export function recoverCasualties(units, initialUnits) {
  const current = new Map(units.map((unit) => [unit.code, unit.quantity]));
  const missing = initialUnits.map((unit) => ({ ...unit, quantity: Math.max(0, unit.quantity - (current.get(unit.code) || 0)) }));
  const remainingMissing = new Map(applyCasualties(missing, RECOVERY_RATE).units.map((unit) => [unit.code, unit.quantity]));
  const recovered = missing.reduce((sum, unit) => sum + unit.quantity - (remainingMissing.get(unit.code) || 0), 0);
  return { recovered, units: initialUnits.map((unit) => ({ ...unit, quantity: unit.quantity - (remainingMissing.get(unit.code) || 0) })).filter((unit) => unit.quantity > 0) };
}

export function nextSeason(campaign, { production = campaignProduction(campaign) } = {}) {
  const { consumption: requiredGrain, situation } = campaignEconomy(campaign, production);
  const producedGrain = production;
  const consumedGrain = Math.min(campaign.grain + producedGrain, requiredGrain);
  const shortage = situation === 'famine';
  const reports = [];
  const armies = campaign.armies.map((army) => {
    const terrain = HEX_BY_ID.get(army.hexId).terrain;
    const initialUnits = army.initialUnits || army.units.map((unit) => ({ ...unit }));
    const wear = applyCasualties(army.units, TERRAIN_TYPES[terrain].attritionRate);
    const hunger = applyCasualties(wear.units, shortage ? SUPPLY_ATTRITION_RATE : 0);
    const recovery = situation === 'abundance' && hunger.units.length > 0
      ? recoverCasualties(hunger.units, initialUnits) : { recovered: 0, units: hunger.units };
    reports.push({ armyId: army.id, name: army.name, terrain, terrainLosses: wear.losses, supplyLosses: hunger.losses, recoveredUnits: recovery.recovered, destroyed: recovery.units.length === 0 });
    return { ...army, initialUnits, units: recovery.units, moved: 0 };
  }).filter((army) => army.units.length > 0);
  return {
    ...campaign, turn: campaign.turn + 1, grain: Math.round((campaign.grain + producedGrain - consumedGrain) * 100) / 100, armies,
    lastTurnReport: { turn: campaign.turn, requiredGrain, consumedGrain, producedGrain, production, situation, shortage, armies: reports },
  };
}

export function loadCampaign(storage) {
  try {
    const state = JSON.parse(storage.getItem(CAMPAIGN_STORAGE_KEY));
    if (state?.version !== 1 || !Number.isInteger(state.turn) || state.turn < 0 || !Number.isFinite(state.grain) || state.grain < 0 || !Number.isInteger(state.nextArmyId) || state.nextArmyId < 1 || !Array.isArray(state.armies)) return newCampaign();
    const ids = new Set();
    const positions = new Set();
    for (const army of state.armies) {
      if (!Number.isInteger(army.id) || army.id < 1 || army.id >= state.nextArmyId || ids.has(army.id) || positions.has(army.hexId) || !HEX_BY_ID.get(army.hexId)?.land || typeof army.name !== 'string' || !['egypt','assyria','nubia','seapeople'].includes(army.designId) || !Number.isInteger(army.moved) || army.moved < 0 || !Array.isArray(army.units) || !army.units.length || army.units.some((unit) => !Number.isInteger(unit.quantity) || unit.quantity < 1 || !Number.isFinite(unit.speed) || unit.speed <= 0 || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0)) return newCampaign();
      ids.add(army.id);
      positions.add(army.hexId);
      if (army.initialUnits) {
        if (!Array.isArray(army.initialUnits) || !army.initialUnits.length || army.initialUnits.some((unit) => !Number.isInteger(unit.quantity) || unit.quantity < 1 || !Number.isFinite(unit.speed) || unit.speed <= 0 || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0)) return newCampaign();
        const originals = new Map(army.initialUnits.map((unit) => [unit.code, unit.quantity]));
        if (originals.size !== army.initialUnits.length || army.units.some((unit) => !originals.has(unit.code) || unit.quantity > originals.get(unit.code))) return newCampaign();
      }
    }
    return state;
  } catch {
    return newCampaign();
  }
}
