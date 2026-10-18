import { normalizeNationId, normalizeFaction } from './nationIdentity';
import archersEgypt from '../assets/archer_egypt.jpg';
import chariotsEgypt from '../assets/charioter_egypt.jpg';
import heavyCavalryEgypt from '../assets/heavy_cavalry_egypt.jpg';
import heavyInfantryEgypt from '../assets/heavy_infantry_egypt.jpg';
import lightCavalryEgypt from '../assets/light_cavalry_egypt.jpg';
import lightInfantryEgypt from '../assets/light_infantry_egypt.jpg';
import seapeopleSpearmen from '../assets/pikeman_seapeople.jpg';
import spearmenEgypt from '../assets/pikeman_egypt.jpg';
import archersHatti from '../assets/archer_hatti.jpg';
import chariotsHatti from '../assets/charioter_hatti.jpg';
import heavyCavalryHatti from '../assets/heavy_cavalry_hatti.jpg';
import heavyInfantryHatti from '../assets/heavy_infantry_hatti.jpg';
import lightCavalryHatti from '../assets/light_cavalry_hatti.jpg';
import lightInfantryHatti from '../assets/light_infantry_hatti.jpg';
import spearmenHatti from '../assets/pikeman_hatti.jpg';
import battlefieldArchersEgypt from '../assets/units/archer_egypt.png';
import battlefieldChariotsEgypt from '../assets/units/charioter_egypt.png';
import battlefieldHeavyCavalryEgypt from '../assets/units/heavy_cavalry_egypt.png';
import battlefieldHeavyInfantryEgypt from '../assets/units/heavy_infantry_egypt.png';
import battlefieldLightCavalryEgypt from '../assets/units/light_cavalry_egypt.png';
import battlefieldLightInfantryEgypt from '../assets/units/light_infantry_egypt.png';
import battlefieldSeapeopleSpearmen from '../assets/units/pikeman_seapeople.png';
import battlefieldSpearmenEgypt from '../assets/units/pikeman_egypt.png';
import battlefieldArchersHatti from '../assets/units/archer_hatti.png';
import battlefieldChariotsHatti from '../assets/units/charioter_hatti.png';
import battlefieldHeavyCavalryHatti from '../assets/units/heavy_cavalry_hatti.png';
import battlefieldHeavyInfantryHatti from '../assets/units/heavy_infantry_hatti.png';
import battlefieldLightCavalryHatti from '../assets/units/light_cavalry_hatti.png';
import battlefieldLightInfantryHatti from '../assets/units/light_infantry_hatti.png';
import battlefieldSpearmenHatti from '../assets/units/pikeman_hatti.png';
import archersNubia from '../assets/archer_nubia.jpg';
import lightInfantryNubia from '../assets/light_infantry_nubia.jpg';
import spearmenNubia from '../assets/pikeman_nubia.jpg';
import battlefieldArchersNubia from '../assets/units/archer_nubia.png';
import battlefieldLightInfantryNubia from '../assets/units/light_infantry_nubia.png';
import battlefieldSpearmenNubia from '../assets/units/pikeman_nubia.png';
import archersSeaPeoples from '../assets/archer_seapeople.jpg';
import lightInfantrySeaPeoples from '../assets/light_infantry_seapeople.jpg';
import heavyInfantrySeaPeoples from '../assets/heavy_infantry_seapeople.jpg';
import battlefieldArchersSeaPeoples from '../assets/units/archer_seapeople.png';
import battlefieldLightInfantrySeaPeoples from '../assets/units/light_infantry_seapeople.png';
import battlefieldHeavyInfantrySeaPeoples from '../assets/units/heavy_infantry_seapeople.png';
import egyptLogo from '../assets/nations/egypt.png';
import hattiLogo from '../assets/nations/hatti.png';
import nubiaLogo from '../assets/nations/nubia.png';
import seaPeoplesLogo from '../assets/nations/seapeople.png';

export const DEFAULT_ARMY_DESIGN_ID = 'egypt';

export const ARMY_DESIGNS = [
  {
    id: 'egypt',
    faction: 'EGYPTIAN',
    logo: egyptLogo,
    nameKey: 'armies.egypt.name',
    descriptionKey: 'armies.egypt.description',
    unitArtwork: {
      ARCHERS: archersEgypt,
      CHARIOTS: chariotsEgypt,
      HEAVY_CAVALRY: heavyCavalryEgypt,
      HEAVY_INFANTRY: heavyInfantryEgypt,
      LIGHT_CAVALRY: lightCavalryEgypt,
      LIGHT_INFANTRY: lightInfantryEgypt,
      MERCENARIES: seapeopleSpearmen,
      SPEARMEN: spearmenEgypt,
    },
    battlefieldArtwork: {
      ARCHERS: battlefieldArchersEgypt,
      CHARIOTS: battlefieldChariotsEgypt,
      HEAVY_CAVALRY: battlefieldHeavyCavalryEgypt,
      HEAVY_INFANTRY: battlefieldHeavyInfantryEgypt,
      LIGHT_CAVALRY: battlefieldLightCavalryEgypt,
      LIGHT_INFANTRY: battlefieldLightInfantryEgypt,
      MERCENARIES: battlefieldSeapeopleSpearmen,
      SPEARMEN: battlefieldSpearmenEgypt,
    },
  },
  {
    id: 'hatti',
    faction: 'HITTITE',
    logo: hattiLogo,
    nameKey: 'armies.hatti.name',
    descriptionKey: 'armies.hatti.description',
    unitArtwork: {
      ARCHERS: archersHatti,
      CHARIOTS: chariotsHatti,
      HEAVY_CAVALRY: heavyCavalryHatti,
      HEAVY_INFANTRY: heavyInfantryHatti,
      LIGHT_CAVALRY: lightCavalryHatti,
      LIGHT_INFANTRY: lightInfantryHatti,
      MERCENARIES: seapeopleSpearmen,
      SPEARMEN: spearmenHatti,
    },
    battlefieldArtwork: {
      ARCHERS: battlefieldArchersHatti,
      CHARIOTS: battlefieldChariotsHatti,
      HEAVY_CAVALRY: battlefieldHeavyCavalryHatti,
      HEAVY_INFANTRY: battlefieldHeavyInfantryHatti,
      LIGHT_CAVALRY: battlefieldLightCavalryHatti,
      LIGHT_INFANTRY: battlefieldLightInfantryHatti,
      MERCENARIES: battlefieldSeapeopleSpearmen,
      SPEARMEN: battlefieldSpearmenHatti,
    },
  },
  {
    id: 'nubia',
    faction: 'NUBIAN',
    logo: nubiaLogo,
    nameKey: 'armies.nubia.name',
    descriptionKey: 'armies.nubia.description',
    defaultQuantities: { SPEARMEN: 5, LIGHT_INFANTRY: 7, ARCHERS: 5 },
    unitArtwork: {
      ARCHERS: archersNubia,
      LIGHT_INFANTRY: lightInfantryNubia,
      SPEARMEN: spearmenNubia,
    },
    battlefieldArtwork: {
      ARCHERS: battlefieldArchersNubia,
      LIGHT_INFANTRY: battlefieldLightInfantryNubia,
      SPEARMEN: battlefieldSpearmenNubia,
    },
  },
  {
    id: 'seapeople',
    faction: 'SEA_PEOPLES',
    logo: seaPeoplesLogo,
    nameKey: 'armies.seapeople.name',
    descriptionKey: 'armies.seapeople.description',
    defaultQuantities: { SPEARMEN: 5, HEAVY_INFANTRY: 4, LIGHT_INFANTRY: 4, ARCHERS: 2 },
    unitArtwork: {
      ARCHERS: archersSeaPeoples,
      LIGHT_INFANTRY: lightInfantrySeaPeoples,
      HEAVY_INFANTRY: heavyInfantrySeaPeoples,
      SPEARMEN: seapeopleSpearmen,
    },
    battlefieldArtwork: {
      ARCHERS: battlefieldArchersSeaPeoples,
      LIGHT_INFANTRY: battlefieldLightInfantrySeaPeoples,
      HEAVY_INFANTRY: battlefieldHeavyInfantrySeaPeoples,
      SPEARMEN: battlefieldSeapeopleSpearmen,
    },
  },
];

export function getArmyDesign(designId) {
  return ARMY_DESIGNS.find((design) => design.id === normalizeNationId(designId)) || ARMY_DESIGNS[0];
}

export function getArmyDesignForFaction(faction) {
  const normalizedFaction = normalizeFaction(faction);
  return ARMY_DESIGNS.find((design) => design.faction === normalizedFaction) || ARMY_DESIGNS[0];
}

export function getUnitArtwork(unitCode, designId = DEFAULT_ARMY_DESIGN_ID) {
  return getArmyDesign(designId).unitArtwork[unitCode] || null;
}

export function getUnitArtworkForFaction(unitCode, faction) {
  return getArmyDesignForFaction(faction).unitArtwork[unitCode] || null;
}

export function getBattlefieldUnitArtwork(unitCode, designId = DEFAULT_ARMY_DESIGN_ID) {
  return getArmyDesign(designId).battlefieldArtwork[unitCode] || null;
}

export function getBattlefieldUnitArtworkForFaction(unitCode, faction) {
  return getArmyDesignForFaction(faction).battlefieldArtwork[unitCode] || null;
}

export function getUnitTypesForDesign(unitTypes, designId) {
  const design = getArmyDesign(designId);
  const profileKey = design.faction.toLowerCase();
  return unitTypes
    .filter((unit) => Boolean(design.unitArtwork[unit.code]))
    .map((unit) => ({ ...unit, ...(unit.profiles?.[profileKey] || {}) }));
}
