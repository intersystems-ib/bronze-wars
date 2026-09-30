import archersEgypt from '../assets/archer_1.jpg';
import chariotsEgypt from '../assets/charioter_1.jpg';
import heavyCavalryEgypt from '../assets/heavy_cavalry_1.jpg';
import heavyInfantryEgypt from '../assets/heavy_infantry_1.jpg';
import lightCavalryEgypt from '../assets/light_cavalry_1.jpg';
import lightInfantryEgypt from '../assets/light_infantry_1.jpg';
import mercenaries from '../assets/mercenary.jpg';
import spearmenEgypt from '../assets/pikeman_1.jpg';
import archersAssyria from '../assets/archer_2.jpg';
import chariotsAssyria from '../assets/charioter_2.jpg';
import heavyCavalryAssyria from '../assets/heavy_cavalry_2.jpg';
import heavyInfantryAssyria from '../assets/heavy_infantry_2.jpg';
import lightCavalryAssyria from '../assets/light_cavalry_2.jpg';
import lightInfantryAssyria from '../assets/light_infantry_2.jpg';
import spearmenAssyria from '../assets/pikeman_2.jpg';
import battlefieldArchersEgypt from '../assets/units/archer_1.png';
import battlefieldChariotsEgypt from '../assets/units/charioter_1.png';
import battlefieldHeavyCavalryEgypt from '../assets/units/heavy_cavalry_1.png';
import battlefieldHeavyInfantryEgypt from '../assets/units/heavy_infantry_1.png';
import battlefieldLightCavalryEgypt from '../assets/units/light_cavalry_1.png';
import battlefieldLightInfantryEgypt from '../assets/units/light_infantry_1.png';
import battlefieldMercenaries from '../assets/units/mercenary.png';
import battlefieldSpearmenEgypt from '../assets/units/pikeman_1.png';
import battlefieldArchersAssyria from '../assets/units/archer_2.png';
import battlefieldChariotsAssyria from '../assets/units/charioter_2.png';
import battlefieldHeavyCavalryAssyria from '../assets/units/heavy_cavalry_2.png';
import battlefieldHeavyInfantryAssyria from '../assets/units/heavy_infantry_2.png';
import battlefieldLightCavalryAssyria from '../assets/units/light_cavalry_2.png';
import battlefieldLightInfantryAssyria from '../assets/units/light_infantry_2.png';
import battlefieldSpearmenAssyria from '../assets/units/pikeman_2.png';

export const DEFAULT_ARMY_DESIGN_ID = 'egypt';

export const ARMY_DESIGNS = [
  {
    id: 'egypt',
    faction: 'EGYPTIAN',
    nameKey: 'armies.egypt.name',
    descriptionKey: 'armies.egypt.description',
    unitArtwork: {
      ARCHERS: archersEgypt,
      CHARIOTS: chariotsEgypt,
      HEAVY_CAVALRY: heavyCavalryEgypt,
      HEAVY_INFANTRY: heavyInfantryEgypt,
      LIGHT_CAVALRY: lightCavalryEgypt,
      LIGHT_INFANTRY: lightInfantryEgypt,
      MERCENARIES: mercenaries,
      SPEARMEN: spearmenEgypt,
    },
    battlefieldArtwork: {
      ARCHERS: battlefieldArchersEgypt,
      CHARIOTS: battlefieldChariotsEgypt,
      HEAVY_CAVALRY: battlefieldHeavyCavalryEgypt,
      HEAVY_INFANTRY: battlefieldHeavyInfantryEgypt,
      LIGHT_CAVALRY: battlefieldLightCavalryEgypt,
      LIGHT_INFANTRY: battlefieldLightInfantryEgypt,
      MERCENARIES: battlefieldMercenaries,
      SPEARMEN: battlefieldSpearmenEgypt,
    },
  },
  {
    id: 'assyria',
    faction: 'ASSYRIAN',
    nameKey: 'armies.assyria.name',
    descriptionKey: 'armies.assyria.description',
    unitArtwork: {
      ARCHERS: archersAssyria,
      CHARIOTS: chariotsAssyria,
      HEAVY_CAVALRY: heavyCavalryAssyria,
      HEAVY_INFANTRY: heavyInfantryAssyria,
      LIGHT_CAVALRY: lightCavalryAssyria,
      LIGHT_INFANTRY: lightInfantryAssyria,
      MERCENARIES: mercenaries,
      SPEARMEN: spearmenAssyria,
    },
    battlefieldArtwork: {
      ARCHERS: battlefieldArchersAssyria,
      CHARIOTS: battlefieldChariotsAssyria,
      HEAVY_CAVALRY: battlefieldHeavyCavalryAssyria,
      HEAVY_INFANTRY: battlefieldHeavyInfantryAssyria,
      LIGHT_CAVALRY: battlefieldLightCavalryAssyria,
      LIGHT_INFANTRY: battlefieldLightInfantryAssyria,
      MERCENARIES: battlefieldMercenaries,
      SPEARMEN: battlefieldSpearmenAssyria,
    },
  },
];

export function getArmyDesign(designId) {
  return ARMY_DESIGNS.find((design) => design.id === designId) || ARMY_DESIGNS[0];
}

export function getArmyDesignForFaction(faction) {
  const normalizedFaction = String(faction || '').toUpperCase();
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
  const profileKey = getArmyDesign(designId).faction.toLowerCase();
  return unitTypes.map((unit) => ({ ...unit, ...(unit.profiles?.[profileKey] || {}) }));
}
