export const GRAIN_BUDGET = 100;
export const MIN_ARMY_DIVISIONS = 4;

export function minimumArmyCost(unitTypes) {
  return MIN_ARMY_DIVISIONS * Math.min(...unitTypes.map((unit) => unit.grainCost).filter((cost) => Number.isFinite(cost) && cost > 0));
}

export const DEFAULT_ARMY_QUANTITIES = {
  SPEARMEN: 4,
  HEAVY_INFANTRY: 2,
  LIGHT_INFANTRY: 2,
  LIGHT_CAVALRY: 2,
};
