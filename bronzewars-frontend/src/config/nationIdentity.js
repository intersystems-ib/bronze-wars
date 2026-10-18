// Legacy identifiers are accepted only while reading existing saved games.
export const LEGACY_HATTI_ID = 'assyria';
const LEGACY_HITTITE_FACTION = 'ASSYRIAN';

export function normalizeNationId(nation) {
  return nation === LEGACY_HATTI_ID ? 'hatti' : nation;
}

export function normalizeFaction(faction) {
  const value = String(faction || '').toUpperCase();
  return value === LEGACY_HITTITE_FACTION ? 'HITTITE' : value;
}

export function normalizeCampaignIdentity(state) {
  if (!state || typeof state !== 'object') return state;
  return { ...state, nation: normalizeNationId(state.nation),
    armies: Array.isArray(state.armies) ? state.armies.map((army) => ({ ...army, designId: normalizeNationId(army.designId) })) : state.armies };
}
