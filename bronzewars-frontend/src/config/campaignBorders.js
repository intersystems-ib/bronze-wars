import { inPolygon } from './campaignTerrain.js';

export const CAMPAIGN_NATIONS = {
  egypt: { color: '#f5d52b' },
  hatti: { color: '#428fff' },
  nubia: { color: '#b55de8' },
  seapeople: { color: '#43c7bf' },
};

const SINAI = [[415,339],[500,340],[560,330],[618,310],[650,300],[675,340],[690,385],[650,480],[600,610],[570,640],[540,600],[490,515],[445,445]];
const LEVANT = [[620,0],[1024,0],[1024,300],[760,340],[700,390],[650,330],[620,300]];

export function isSinai(hex) {
  return inPolygon(hex.x, hex.y, SINAI);
}

export function adjacentCoordinates(hex) {
  const shift = hex.row % 2;
  return [[-1,0],[1,0],[shift-1,-1],[shift,-1],[shift-1,1],[shift,1]]
    .map(([dc, dr]) => `${hex.col + dc},${hex.row + dr}`);
}

export function assignTerritories(hexes) {
  const byId = new Map(hexes.map((hex) => [hex.id, hex]));
  const distance = new Map();
  const queue = [];
  for (const hex of hexes) {
    if (hex.land && hex.nileValley && !isSinai(hex)) { distance.set(hex.id, 0); queue.push(hex.id); }
  }
  for (let i = 0; i < queue.length; i += 1) {
    const id = queue[i];
    if (distance.get(id) >= 2) continue;
    for (const neighborId of adjacentCoordinates(byId.get(id))) {
      const neighbor = byId.get(neighborId);
      if (!neighbor?.land || isSinai(neighbor) || distance.has(neighborId)) continue;
      distance.set(neighborId, distance.get(id) + 1);
      queue.push(neighborId);
    }
  }
  return new Map(hexes.map((hex) => {
    if (!hex.land || isSinai(hex)) return [hex.id, null];
    if (distance.has(hex.id)) return [hex.id, hex.row <= 33 ? 'egypt' : 'nubia'];
    if (inPolygon(hex.x, hex.y, LEVANT) || ['euphrates', 'jordan'].includes(hex.river)) return [hex.id, 'hatti'];
    return [hex.id, null];
  }));
}

export function buildBorders(hexes) {
  const edges = new Map();
  for (const hex of hexes) {
    const vertices = hex.points.split(' ').map((point) => point.split(',').map(Number));
    for (let i = 0; i < vertices.length; i += 1) {
      const from = vertices[i];
      const to = vertices[(i + 1) % vertices.length];
      const key = [from, to].map((point) => point.map((value) => value.toFixed(5)).join(',')).sort().join('|');
      if (!edges.has(key)) edges.set(key, []);
      edges.get(key).push({ hex, from, to });
    }
  }
  const borders = [];
  for (const [key, entries] of edges) {
    for (const { hex, from, to } of entries) {
      if (!hex.territory || entries.some((entry) => entry.hex.id !== hex.id && entry.hex.territory === hex.territory)) continue;
      const midX = (from[0] + to[0]) / 2;
      const midY = (from[1] + to[1]) / 2;
      const length = Math.hypot(hex.x - midX, hex.y - midY);
      // Separate shared boundaries into parallel lines inside each nation's hex.
      const dx = (hex.x - midX) / length * 2.7;
      const dy = (hex.y - midY) / length * 2.7;
      borders.push({ id: `${key}:${hex.territory}`, territory: hex.territory, hexId: hex.id, path: `M${from[0] + dx},${from[1] + dy} L${to[0] + dx},${to[1] + dy}` });
    }
  }
  return borders;
}
