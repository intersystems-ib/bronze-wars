import { CAMPAIGN_CITIES } from './campaignCities.js';
import { adjacentCoordinates } from './campaignBorders.js';

// Grow fixed regions along land paths inside each city's original nation.
// Every claimed hex has a path back to its city through the same region.
// Seed and neighbor order also make equal-distance ties deterministic.
export function assignCityRegions(hexes) {
  const byId = new Map(hexes.map((hex) => [hex.id, hex]));
  const regions = new Map();
  const queue = [];
  for (const city of CAMPAIGN_CITIES) {
    const hex = byId.get(city.hexId);
    if (!hex?.land || hex.territory !== city.nation) throw new Error(`City outside its original territory: ${city.id}`);
    regions.set(hex.id, city.id);
    queue.push(hex);
  }
  for (let index = 0; index < queue.length; index += 1) {
    const hex = queue[index];
    for (const id of adjacentCoordinates(hex)) {
      const neighbor = byId.get(id);
      if (!neighbor?.land || neighbor.territory !== hex.territory || regions.has(id)) continue;
      regions.set(id, regions.get(hex.id));
      queue.push(neighbor);
    }
  }
  if (hexes.some((hex) => hex.territory && !regions.has(hex.id))) throw new Error('National territory has no connected city region');
  return regions;
}
