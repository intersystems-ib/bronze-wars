import { TERRAIN_TYPES, inPolygon, terrainAt, riverAt, isNileValley } from './campaignTerrain.js';
import { MIN_ARMY_DIVISIONS } from './armyRules.js';
import { assignTerritories, adjacentCoordinates, buildBorders } from './campaignBorders.js';
import { CAMPAIGN_CITIES } from './campaignCities.js';
import { assignCityRegions } from './campaignRegions.js';
import { LEGACY_HATTI_ID, normalizeNationId, normalizeCampaignIdentity } from './nationIdentity.js';
export { CAMPAIGN_CITIES } from './campaignCities.js';
import { activeUnitCount, armyTroops, applyCasualties, recoverCasualties, wearMorale, recoverMorale, mergedArmyUnits } from './campaignStrength.js';
import { cityOwner, cityIncomeNation, cityProduction, campaignCapital, settleCityAssault, validCityState } from './campaignCityActions.js';
export { activeUnitCount, armyTroops, unitTroops, applyCasualties, recoverCasualties, migrateCampaignStrength } from './campaignStrength.js';

export const CAMPAIGN_STORAGE_KEY = 'bronzewars.campaign.egypt.v1';
export const UPKEEP_RATE = 0.1;
export const SUPPLY_ATTRITION_RATE = 0.05;
export const RECOVERY_RATE = 0.05;
export const INITIAL_GRAIN = 100;
export const SEASONS = ['inundation', 'emergence', 'harvest'];
export const MAP_WIDTH = 1024;
export const MAP_HEIGHT = 1536;
export const PLAYABLE_NATIONS = ['egypt', 'hatti', 'nubia'];

export function campaignStorageKey(nation) {
  return nation === 'egypt' ? CAMPAIGN_STORAGE_KEY : `bronzewars.campaign.${nation}.v1`;
}

export function availableGrain(grain) {
  return Math.max(0, Math.ceil(grain - 1e-9));
}
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
  hex.production = 0;
}
const territories = assignTerritories(CAMPAIGN_HEXES);
for (const hex of CAMPAIGN_HEXES) hex.territory = territories.get(hex.id);
for (const city of CAMPAIGN_CITIES) {
  const hex = HEX_BY_ID.get(city.hexId);
  hex.city = city;
  hex.production = city.grain;
}
const cityRegions = assignCityRegions(CAMPAIGN_HEXES);
const regionCities = new Map(CAMPAIGN_CITIES.map((city) => [city.id, city]));
for (const hex of CAMPAIGN_HEXES) hex.regionId = cityRegions.get(hex.id) ?? null;
export const CAMPAIGN_REGIONS = CAMPAIGN_CITIES.map((city) => ({
  id: city.id, city, hexIds: CAMPAIGN_HEXES.filter((hex) => hex.regionId === city.id).map((hex) => hex.id),
}));
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
  const count = units.reduce((sum, unit) => sum + activeUnitCount(unit), 0);
  return count ? units.reduce((sum, unit) => sum + activeUnitCount(unit) * unit.speed, 0) / count : 0;
}

export function remainingMovement(army) {
  const remaining = Math.max(0, Math.floor(armyMovement(army.units) - army.moved + 1e-9));
  return TERRAIN_TYPES[HEX_BY_ID.get(army.hexId)?.terrain]?.difficult
    ? (army.moved > 0 ? 0 : Math.min(1, remaining)) : remaining;
}

export function armyUpkeep(army) {
  return Math.round(army.units.reduce((sum, unit) => sum + activeUnitCount(unit) * unit.grainCost, 0) * UPKEEP_RATE * 100) / 100;
}

export function campaignUpkeep(campaign) {
  return Math.round(campaign.armies.filter((army) => army.designId === (campaign.nation || 'egypt')).reduce((sum, army) => sum + armyUpkeep(army), 0) * 100) / 100;
}

export function campaignTerritory(campaign, hex) {
  const city = regionCities.get(hex.regionId) ?? hex.city;
  return city ? cityOwner(campaign, city) : hex.territory;
}

export function campaignTerritoryInfo(campaign, hex) {
  const originalOwner = (regionCities.get(hex.regionId) ?? hex.city)?.nation ?? hex.territory;
  const controller = campaignTerritory(campaign, hex);
  return { originalOwner, controller, occupied: Boolean(originalOwner && controller && originalOwner !== controller) };
}

export function occupiedRegions(campaign, nation) {
  return CAMPAIGN_REGIONS.filter(({ city }) => city.nation === nation && cityOwner(campaign, city) !== nation)
    .map(({ id, city, hexIds }) => ({ regionId: id, cityId: city.id, hexId: city.hexId,
      originalOwner: nation, occupiedBy: cityOwner(campaign, city), capital: city.capital,
      annualProduction: cityProduction(campaign, city), baseAnnualProduction: city.grain, hexCount: hexIds.length }));
}

export function occupationGarrison(campaign, army) {
  const territory = campaignTerritoryInfo(campaign, HEX_BY_ID.get(army.hexId));
  return territory.occupied && territory.controller === army.designId;
}

export function terrainAttrition(campaign, hex, nation = campaign.nation || 'egypt') {
  return campaignTerritory(campaign, hex) === nation ? 0 : TERRAIN_TYPES[hex.terrain].attritionRate;
}

export function campaignProduction(campaign, nation = campaign.nation || 'egypt') {
  return CAMPAIGN_CITIES.filter((city) => cityIncomeNation(campaign, city) === nation)
    .reduce((sum, city) => sum + cityProduction(campaign, city), 0);
}

export function campaignEconomy(campaign, production = campaignProduction(campaign)) {
  const consumption = campaignUpkeep(campaign);
  const situation = campaign.grain <= 0 ? 'famine'
    : production > consumption + 1e-9 ? 'abundance' : 'scarcity';
  return { production, consumption, situation };
}

export function reachableHexes(campaign, armyId, nation = campaign.nation || 'egypt') {
  const army = campaign.armies.find((candidate) => candidate.id === armyId);
  if (!army || army.designId !== nation) return new Map();
  const budget = Math.floor(armyMovement(army.units) - army.moved + 1e-9);
  const limit = remainingMovement(army);
  const occupied = new Map(campaign.armies.filter((candidate) => candidate.id !== armyId).map((candidate) => [candidate.hexId, candidate]));
  const distances = new Map([[army.hexId, 0]]);
  const queue = [army.hexId];
  for (let i = 0; i < queue.length; i += 1) {
    const id = queue[i];
    if (distances.get(id) >= limit || (id !== army.hexId && (occupied.has(id) || TERRAIN_TYPES[HEX_BY_ID.get(id).terrain].difficult))) continue;
    for (const neighbor of neighbors(id)) {
      if ((occupied.has(neighbor.id) && occupied.get(neighbor.id).designId !== nation) || distances.has(neighbor.id)) continue;
      distances.set(neighbor.id, distances.get(id) + 1);
      queue.push(neighbor.id);
    }
  }
  distances.delete(army.hexId);
  return new Map([...distances].map(([id, distance]) => [id,
    TERRAIN_TYPES[HEX_BY_ID.get(army.hexId).terrain].difficult || TERRAIN_TYPES[HEX_BY_ID.get(id).terrain].difficult ? budget : distance,
  ]));
}

export function deploymentHexes(campaign) {
  const occupied = new Set(campaign.armies.map((army) => army.hexId));
  const nation = campaign.nation || 'egypt';
  if (!PLAYABLE_NATIONS.includes(nation)) return [];
  const capital = campaignCapital(campaign, nation);
  const hex = HEX_BY_ID.get(capital?.hexId);
  if (!hex?.land || cityOwner(campaign, capital) !== nation) return [];
  const queue = [hex];
  const visited = new Set([hex.id]);
  for (let index = 0; index < queue.length; index += 1) {
    for (const neighbor of neighbors(queue[index].id)) {
      if (neighbor.regionId !== capital.id || visited.has(neighbor.id)) continue;
      visited.add(neighbor.id);
      queue.push(neighbor);
    }
  }
  return queue.filter((candidate) => !occupied.has(candidate.id) && campaignTerritory(campaign, candidate) === nation);
}

export function findSpawn(campaign) {
  return deploymentHexes(campaign)[0]?.id ?? null;
}

export function newCampaign(nation = 'egypt') {
  return { version: 2, nation: normalizeNationId(nation), turn: 0, grain: INITIAL_GRAIN, nextArmyId: 1, armies: [] };
}

export function disbandArmy(campaign, armyId) {
  if (campaign.pendingEncounter) return campaign;
  const army = campaign.armies.find((candidate) => candidate.id === armyId);
  if (!army || army.designId !== (campaign.nation || 'egypt')) return campaign;
  return { ...campaign, armies: campaign.armies.filter((candidate) => candidate.id !== armyId) };
}

export function recruitArmy(campaign, { name, designId, quantities }, unitTypes) {
  if (campaign.pendingEncounter) return campaign;
  if (!PLAYABLE_NATIONS.includes(designId) || designId !== (campaign.nation || 'egypt')) return campaign;
  const units = unitTypes.filter((unit) => quantities[unit.code] > 0).map((unit) => ({
    code: unit.code, quantity: quantities[unit.code], speed: unit.speed,
    attack: unit.attack, defense: unit.defense, damage: unit.damage, grainCost: unit.grainCost,
    initialStrength: unit.initialStrength,
    strengths: Array.from({ length: Math.max(0, Math.min(99, Math.floor(quantities[unit.code]))) }, () => unit.initialStrength),
  }));
  if (campaign.version !== 2 || !units.length || units.some((unit) => !Number.isInteger(unit.quantity) || unit.quantity < 1 || unit.quantity > 99 || !Number.isInteger(unit.initialStrength) || unit.initialStrength <= 0 || !Number.isFinite(unit.speed) || unit.speed <= 0 || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0)) return campaign;
  if (units.reduce((sum, unit) => sum + unit.quantity, 0) < MIN_ARMY_DIVISIONS) return campaign;
  const cost = units.reduce((sum, unit) => sum + unit.quantity * unit.grainCost, 0);
  const hexId = findSpawn(campaign);
  const budget = availableGrain(campaign.grain);
  if (cost > budget || !hexId) return campaign;
  return {
    ...campaign, grain: budget - cost, nextArmyId: campaign.nextArmyId + 1,
    armies: [...campaign.armies, { id: campaign.nextArmyId, name: name.trim().slice(0,80), designId, units, morale: 100, hexId, moved: 0 }],
  };
}

export function moveArmy(campaign, armyId, destination, nation = campaign.nation || 'egypt') {
  if (campaign.pendingEncounter) return campaign;
  const target = campaign.armies.find((army) => army.id !== armyId && army.hexId === destination);
  if (target) return mergeArmies(campaign, armyId, target.id, nation);
  const cost = reachableHexes(campaign, armyId, nation).get(destination);
  if (!cost) return campaign;
  return { ...campaign, armies: campaign.armies.map((army) => {
    if (army.id !== armyId) return army;
    const { cityAction, ...rest } = army;
    return { ...rest, hexId: destination, moved: army.moved + cost };
  }) };
}

export function mergeArmies(campaign, sourceId, targetId, nation = campaign.nation || 'egypt') {
  if (campaign.pendingEncounter || sourceId === targetId) return campaign;
  const source = campaign.armies.find((army) => army.id === sourceId && army.designId === nation);
  const target = campaign.armies.find((army) => army.id === targetId && army.designId === nation);
  if (!source || !target || armyTroops(source) <= 0 || armyTroops(target) <= 0 || !reachableHexes(campaign, sourceId, nation).has(target.hexId)) return campaign;
  const units = mergedArmyUnits(target.units, source.units);
  if (!units?.length) return campaign;
  const troops = armyTroops(source) + armyTroops(target);
  const morale = Math.round(((source.morale ?? 100) * armyTroops(source) + (target.morale ?? 100) * armyTroops(target)) / troops);
  const { initialUnits, ...base } = target;
  const combined = { ...base, units, morale, moved: Math.ceil(armyMovement(units)) };
  if (combined.campaignMission?.intent === 'MERGE') delete combined.campaignMission;
  const aiMovement = { ...campaign.aiMovement };
  if (aiMovement[nation]?.turn === campaign.turn) aiMovement[nation] = { ...aiMovement[nation], processed: [...new Set([...aiMovement[nation].processed, sourceId, targetId])] };
  return { ...campaign, armies: campaign.armies.filter((army) => army.id !== sourceId).map((army) => army.id === targetId ? combined : army),
    ...(campaign.aiMovement ? { aiMovement } : {}) };
}

export function nextSeason(campaign, { production } = {}) {
  if (campaign.version !== 2 || campaign.pendingEncounter) return campaign;
  const { consumption: requiredGrain, situation } = campaignEconomy(campaign, production ?? campaignProduction(campaign));
  const startingGrain = availableGrain(campaign.grain);
  const shortage = situation === 'famine';
  const reports = [];
  const foreignEconomies = new Map(PLAYABLE_NATIONS.filter((nation) => nation !== (campaign.nation || 'egypt') && campaign.aiRecruitment).map((nation) => {
    const reserve = campaign.foreignGrain?.[nation] ?? INITIAL_GRAIN;
    const economy = campaignEconomy({ ...campaign, nation, grain: reserve });
    economy.situation = reserve <= 0 ? 'famine' : economy.production > economy.consumption * 3 ? 'abundance' : 'scarcity';
    return [nation, economy];
  }));
  const cityOwners = { ...campaign.cityOwners };
  const capturedCities = [];
  function capture(city, nation) {
    capturedCities.push({ cityId: city.id, previousOwner: cityOwner({ cityOwners }, city), newOwner: nation });
    cityOwners[city.id] = nation;
  }
  const armies = campaign.armies.map((army) => {
    const own = army.designId === (campaign.nation || 'egypt');
    const foreignEconomy = foreignEconomies.get(army.designId);
    if (!own && !foreignEconomy) {
      const assault = settleCityAssault({ ...campaign, cityOwners }, army);
      if (assault.capturedCity) capture(assault.capturedCity, army.designId);
      return assault.army;
    }
    const hex = HEX_BY_ID.get(army.hexId);
    const terrain = hex.terrain;
    const wearRate = terrainAttrition(campaign, hex, army.designId);
    const wear = applyCasualties(army.units, wearRate);
    const armySituation = own ? situation : foreignEconomy.situation;
    const hunger = applyCasualties(wear.units, armySituation === 'famine' ? SUPPLY_ATTRITION_RATE : 0);
    const startingMorale = army.morale ?? 100;
    const morale = wearMorale(wearMorale(startingMorale, wearRate), armySituation === 'famine' ? SUPPLY_ATTRITION_RATE : 0);
    const assault = settleCityAssault({ ...campaign, cityOwners }, { ...army, units: hunger.units, morale });
    const canRecover = armySituation === 'abundance' && !occupationGarrison(campaign, army) && army.cityAction?.type !== 'assault' && armyTroops(assault.army) > 0;
    const finalMorale = canRecover ? recoverMorale(assault.army.morale, RECOVERY_RATE) : assault.army.morale;
    const recovery = canRecover
      ? recoverCasualties(assault.army.units, RECOVERY_RATE) : { recovered: 0, units: assault.army.units };
    if (assault.capturedCity) capture(assault.capturedCity, army.designId);
    if (own) reports.push({ armyId: army.id, name: army.name, terrain, terrainLosses: wear.losses, supplyLosses: hunger.losses, assaultLosses: assault.losses, moraleLosses: startingMorale - assault.army.morale, recoveredMorale: finalMorale - assault.army.morale, ...(assault.capturedCity ? { capturedCityId: assault.capturedCity.id } : {}), recoveredUnits: recovery.recovered, destroyed: armyTroops({ units: recovery.units }) === 0 });
    return { ...assault.army, units: recovery.units, morale: finalMorale, moved: 0 };
  }).filter((army) => armyTroops(army) > 0);
  const endingProduction = production ?? campaignProduction({ ...campaign, armies, cityOwners });
  const producedGrain = campaign.turn % SEASONS.length === SEASONS.indexOf('harvest') ? endingProduction : 0;
  const consumedGrain = Math.min(startingGrain + producedGrain, requiredGrain);
  const foreignGrain = { ...campaign.foreignGrain };
  for (const [nation, economy] of foreignEconomies) {
    const harvest = campaign.turn % 3 === 2 ? campaignProduction({ ...campaign, cityOwners }, nation) : 0;
    foreignGrain[nation] = availableGrain(availableGrain(foreignGrain[nation] ?? INITIAL_GRAIN) + harvest - economy.consumption);
  }
  return {
    ...campaign, cityOwners, turn: campaign.turn + 1, grain: availableGrain(startingGrain + producedGrain - consumedGrain), armies,
    ...(foreignEconomies.size ? { foreignGrain } : {}),
    lastTurnReport: { turn: campaign.turn, requiredGrain, consumedGrain, producedGrain, production: endingProduction, situation, shortage, capturedCities, armies: reports },
  };
}

export function loadCampaign(storage, nation = 'egypt', { fallbackToNew = true } = {}) {
  nation = normalizeNationId(nation);
  const invalid = () => fallbackToNew ? newCampaign(nation) : null;
  try {
    const saved = storage.getItem(campaignStorageKey(nation));
    const legacySaved = saved == null && nation === 'hatti' ? storage.getItem(campaignStorageKey(LEGACY_HATTI_ID)) : null;
    const state = normalizeCampaignIdentity(JSON.parse(saved ?? legacySaved));
    if (!PLAYABLE_NATIONS.includes(nation) || (state?.nation && state.nation !== nation)) return invalid();
    if (![1, 2].includes(state?.version) || !Number.isInteger(state.turn) || state.turn < 0 || !Number.isFinite(state.grain) || state.grain < 0 || !Number.isInteger(state.nextArmyId) || state.nextArmyId < 1 || !Array.isArray(state.armies)) return invalid();
    const ids = new Set();
    const positions = new Set();
    for (const army of state.armies) {
      if (!Number.isInteger(army.id) || army.id < 1 || army.id >= state.nextArmyId || ids.has(army.id) || positions.has(army.hexId) || !HEX_BY_ID.get(army.hexId)?.land || typeof army.name !== 'string' || !['egypt','hatti','nubia','seapeople'].includes(army.designId) || !Number.isInteger(army.moved) || army.moved < 0 || !Array.isArray(army.units) || !army.units.length || army.units.some((unit) => !Number.isInteger(unit.quantity) || unit.quantity < 1 || !Number.isFinite(unit.speed) || unit.speed <= 0 || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0)) return invalid();
      ids.add(army.id);
      positions.add(army.hexId);
      if (state.version === 2 && (armyTroops(army) <= 0 || army.units.some((unit) => !Number.isInteger(unit.initialStrength) || unit.initialStrength <= 0 || !Array.isArray(unit.strengths) || unit.strengths.length !== unit.quantity || unit.strengths.some((strength) => !Number.isInteger(strength) || strength < 0 || strength > unit.initialStrength)))) return invalid();
      if (army.initialUnits) {
        if (!Array.isArray(army.initialUnits) || !army.initialUnits.length || army.initialUnits.some((unit) => !Number.isInteger(unit.quantity) || unit.quantity < 1 || !Number.isFinite(unit.speed) || unit.speed <= 0 || !Number.isFinite(unit.grainCost) || unit.grainCost <= 0)) return invalid();
        const originals = new Map(army.initialUnits.map((unit) => [unit.code, unit.quantity]));
        if (originals.size !== army.initialUnits.length || army.units.some((unit) => !originals.has(unit.code) || unit.quantity > originals.get(unit.code))) return invalid();
      }
    }
    const intents = ['DEFEND', 'RECLAIM', 'MERGE', 'RETREAT', 'RECOVER', 'RAID', 'CONQUER', 'CONTINUE', 'HOLD'];
    const validOrder = (order) => order && Number.isInteger(order.armyId) && order.armyId > 0 && typeof order.id === 'string' && intents.includes(order.intent) && HEX_BY_ID.get(order.targetHexId)?.land;
    if (state.aiMovement !== undefined && (!state.aiMovement || typeof state.aiMovement !== 'object' || Array.isArray(state.aiMovement)
      || Object.entries(state.aiMovement).some(([id, entry]) => !PLAYABLE_NATIONS.includes(id) || id === nation || !entry || !Number.isInteger(entry.turn) || entry.turn < 0 || entry.turn > state.turn
        || !Array.isArray(entry.decisions) || !entry.decisions.every(validOrder) || !Array.isArray(entry.processed) || entry.processed.some((id) => !Number.isInteger(id) || id < 1)))) return invalid();
    if (state.armies.some((army) => army.campaignMission && (!intents.includes(army.campaignMission.intent)
      || (army.campaignMission.targetCityId && !CAMPAIGN_CITIES.some((city) => city.id === army.campaignMission.targetCityId))))) return invalid();
    if (state.pendingEncounter) {
      const entry = state.pendingEncounter;
      const attacker = state.armies.find((army) => army.id === entry.attackerId);
      const defender = state.armies.find((army) => army.id === entry.defenderId);
      if (typeof entry.id !== 'string' || !entry.id || entry.turn !== state.turn || !attacker || !defender || attacker.designId === defender.designId || defender.hexId !== entry.hexId
        || !neighbors(attacker.hexId).some((hex) => hex.id === defender.hexId) || (entry.battleId !== undefined && !/^[1-9][0-9]*$/.test(String(entry.battleId)))) return invalid();
    }
    if (!validCityState(state)) return invalid();
    if (state.aiRecruitment !== undefined && (!state.aiRecruitment || typeof state.aiRecruitment !== 'object' || Array.isArray(state.aiRecruitment)
      || Object.entries(state.aiRecruitment).some(([id, entry]) => !PLAYABLE_NATIONS.includes(id) || id === nation || !entry || !Number.isInteger(entry.turn)
        || entry.turn < 0 || entry.turn > state.turn || !['recruit', 'wait'].includes(entry.action) || typeof entry.reason !== 'string'))) return invalid();
    return { ...state, nation, grain: availableGrain(state.grain) };
  } catch {
    return invalid();
  }
}
