const BASE_URL = '/api/bronzewars';

async function request(path, options = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: {
      Accept: 'application/json',
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...options.headers,
    },
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error?.message || `HTTP ${response.status}`);
    error.code = payload.error?.code || 'UNKNOWN_ERROR';
    error.details = payload.error?.details || [];
    error.status = response.status;
    throw error;
  }
  return payload;
}

export const api = {
  listUnitTypes: () => request('/unit-types'),
  createBattle: (input) => request('/battles', {
    method: 'POST',
    body: JSON.stringify(input),
  }),
  getBattle: (battleId) => request(`/battles/${battleId}`),
  getDeployment: (battleId) => request(`/battles/${battleId}/deployment`),
  placeUnit: (battleId, unitId, position) => request(`/battles/${battleId}/units/${unitId}/position`, {
    method: 'PUT',
    body: JSON.stringify(position),
  }),
  moveUnit: (battleId, unitId, position) => request(`/battles/${battleId}/units/${unitId}/move`, {
    method: 'PUT',
    body: JSON.stringify(position),
  }),
  startBattle: (battleId) => request(`/battles/${battleId}/start`, { method: 'POST' }),
  nextTurn: (battleId, confirmIncomplete = false) => request(`/battles/${battleId}/next-turn`, {
    method: 'POST',
    body: JSON.stringify({ confirmIncomplete }),
  }),
};
