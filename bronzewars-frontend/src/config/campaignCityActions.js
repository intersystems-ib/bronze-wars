import { CAMPAIGN_CITIES } from './campaignCities.js';
import { activeUnitCount, armyTroops, applyCasualties } from './campaignStrength.js';

export const ASSAULT_EFFORT = 3000;
export const ASSAULT_LOSS_RATE = 0.05;
const TERRITORIAL_NATIONS = ['egypt', 'hatti', 'nubia'];
const CITY_BY_ID = new Map(CAMPAIGN_CITIES.map((city) => [city.id, city]));
const CITY_BY_HEX = new Map(CAMPAIGN_CITIES.map((city) => [city.hexId, city]));

export function cityAt(hexId) {
  return CITY_BY_HEX.get(hexId);
}

export function cityOwner(campaign, city) {
  return campaign.cityOwners?.[city.id] ?? city.nation;
}

export function cityIncomeNation(campaign, city) {
  return cityRaid(campaign, city) ? null : cityOwner(campaign, city);
}

export function cityRaid(campaign, city) {
  const raid = campaign.cityRaids?.[city.id];
  return raid?.year === Math.floor(campaign.turn / 3) ? raid : null;
}

export function nationGrain(campaign, nation) {
  return nation === (campaign.nation || 'egypt') ? campaign.grain : campaign.foreignGrain?.[nation] ?? 0;
}

export function assaultDuration(army) {
  const troops = armyTroops(army);
  return troops > 0 ? Math.max(1, Math.ceil(ASSAULT_EFFORT / troops)) : Infinity;
}

export function startCityAction(campaign, armyId, type, nation = campaign.nation || 'egypt') {
  const army = campaign.armies.find((candidate) => candidate.id === armyId);
  const city = cityAt(army?.hexId);
  if (campaign.version !== 2 || !army || army.designId !== nation || (!TERRITORIAL_NATIONS.includes(nation) && nation !== 'seapeople') || armyTroops(army) <= 0 || !city
    || cityOwner(campaign, city) === nation || !['raid', 'assault'].includes(type)
    || (type === 'assault' && !TERRITORIAL_NATIONS.includes(nation))) return campaign;
  if (army.cityAction?.type === type && army.cityAction.cityId === city.id) return campaign;
  if (type === 'raid' && cityRaid(campaign, city)) return campaign;
  // Starting an action spends this season's remaining movement. Moving away
  // after the next season automatically abandons the action and its progress.
  const spentMovement = Math.ceil(Math.max(...army.units.filter((unit) => activeUnitCount(unit) > 0).map((unit) => unit.speed)));
  const changedArmies = campaign.armies.map((candidate) => {
    if (candidate.id !== armyId) return candidate;
    const { cityAction, ...rest } = candidate;
    return { ...rest, moved: Math.max(candidate.moved, spentMovement), ...(type === 'assault' ? {
      cityAction: { type, cityId: city.id, initialTroops: armyTroops(army), turnsRequired: assaultDuration(army), turnsElapsed: 0 },
    } : {}) };
  });
  if (type === 'assault') return { ...campaign, armies: changedArmies };
  const stolenGrain = Math.ceil(nationGrain(campaign, nation) - 1e-9) + city.grain;
  return { ...campaign, armies: changedArmies,
    cityRaids: { ...campaign.cityRaids, [city.id]: { year: Math.floor(campaign.turn / 3), nation } },
    ...(nation === (campaign.nation || 'egypt') ? { grain: stolenGrain }
      : { foreignGrain: { ...campaign.foreignGrain, [nation]: stolenGrain } }) };
}

export function cancelCityAction(campaign, armyId, nation = campaign.nation || 'egypt') {
  const army = campaign.armies.find((candidate) => candidate.id === armyId);
  if (!army?.cityAction || army.designId !== nation) return campaign;
  return { ...campaign, armies: campaign.armies.map((candidate) => {
    if (candidate.id !== armyId) return candidate;
    const { cityAction, ...rest } = candidate;
    return rest;
  }) };
}

export function settleCityAssault(campaign, army) {
  const action = army.cityAction;
  const city = cityAt(army.hexId);
  if (action?.type !== 'assault' || !city || action.cityId !== city.id || cityOwner(campaign, city) === army.designId) {
    return { army, losses: 0, capturedCity: null };
  }
  const casualties = applyCasualties(army.units, ASSAULT_LOSS_RATE);
  const updated = { ...army, units: casualties.units, cityAction: { ...action, turnsElapsed: action.turnsElapsed + 1 } };
  const capturedCity = armyTroops(updated) > 0 && updated.cityAction.turnsElapsed >= action.turnsRequired ? city : null;
  if (capturedCity) delete updated.cityAction;
  return { army: updated, losses: casualties.losses, capturedCity };
}

export function validCityState(campaign) {
  if (campaign.cityOwners !== undefined && (!campaign.cityOwners || typeof campaign.cityOwners !== 'object'
    || Array.isArray(campaign.cityOwners) || Object.entries(campaign.cityOwners).some(([id, nation]) => !CITY_BY_ID.has(id) || !TERRITORIAL_NATIONS.includes(nation)))) return false;
  if (campaign.cityRaids !== undefined && (!campaign.cityRaids || typeof campaign.cityRaids !== 'object' || Array.isArray(campaign.cityRaids)
    || Object.entries(campaign.cityRaids).some(([id, raid]) => !CITY_BY_ID.has(id) || !raid || !Number.isInteger(raid.year) || raid.year < 0
      || raid.year > Math.floor(campaign.turn / 3) || ![...TERRITORIAL_NATIONS, 'seapeople'].includes(raid.nation)))) return false;
  if (campaign.foreignGrain !== undefined && (!campaign.foreignGrain || typeof campaign.foreignGrain !== 'object' || Array.isArray(campaign.foreignGrain)
    || Object.entries(campaign.foreignGrain).some(([nation, grain]) => ![...TERRITORIAL_NATIONS, 'seapeople'].includes(nation) || !Number.isInteger(grain) || grain < 0))) return false;
  return campaign.armies.every((army) => {
    const action = army.cityAction;
    if (action === undefined) return true;
    const city = CITY_BY_ID.get(action?.cityId);
    if (campaign.version !== 2 || !city || city.hexId !== army.hexId || cityOwner(campaign, city) === army.designId) return false;
    return action.type === 'assault' && TERRITORIAL_NATIONS.includes(army.designId)
      && Number.isInteger(action.initialTroops) && action.initialTroops > 0
      && action.turnsRequired === Math.max(1, Math.ceil(ASSAULT_EFFORT / action.initialTroops))
      && Number.isInteger(action.turnsElapsed) && action.turnsElapsed >= 0 && action.turnsElapsed < action.turnsRequired;
  });
}
