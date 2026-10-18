// Authored city hexes use zero-based map coordinates. Grain is collected once
// per year into the nation's shared reserve, rather than from surrounding land.
export const CAMPAIGN_CITIES = [
  { id: 'egypt-1', nation: 'egypt', hexId: '7,10', capital: true, grain: 6, number: 1 },
  { id: 'egypt-2', nation: 'egypt', hexId: '5,8', capital: false, grain: 5, number: 2 },
  { id: 'egypt-3', nation: 'egypt', hexId: '6,16', capital: false, grain: 4, number: 3 },
  { id: 'egypt-4', nation: 'egypt', hexId: '8,22', capital: false, grain: 5, number: 4 },
  { id: 'egypt-5', nation: 'egypt', hexId: '9,26', capital: false, grain: 6, number: 5 },
  { id: 'egypt-6', nation: 'egypt', hexId: '8,32', capital: false, grain: 5, number: 6 },
  { id: 'hatti-1', nation: 'hatti', hexId: '21,1', capital: true, grain: 6, number: 1 },
  { id: 'hatti-2', nation: 'hatti', hexId: '17,0', capital: false, grain: 4, number: 2 },
  { id: 'hatti-3', nation: 'hatti', hexId: '15,3', capital: false, grain: 5, number: 3 },
  { id: 'hatti-4', nation: 'hatti', hexId: '19,4', capital: false, grain: 5, number: 4 },
  { id: 'hatti-5', nation: 'hatti', hexId: '15,6', capital: false, grain: 5, number: 5 },
  { id: 'hatti-6', nation: 'hatti', hexId: '16,7', capital: false, grain: 5, number: 6 },
  // West-bank land hexes keep the city artwork clear of the painted Nile.
  { id: 'nubia-1', nation: 'nubia', hexId: '7,34', capital: true, grain: 8, number: 1 },
  { id: 'nubia-2', nation: 'nubia', hexId: '8,38', capital: false, grain: 6, number: 2 },
  { id: 'nubia-3', nation: 'nubia', hexId: '9,40', capital: false, grain: 6, number: 3 },
];
