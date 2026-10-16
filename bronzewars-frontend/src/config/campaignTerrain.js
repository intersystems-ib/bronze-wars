export const TERRAIN_TYPES = {
  water: { attritionRate: 0, difficult: false, maxMovement: 0, production: 1 },
  coast: { attritionRate: 0, difficult: false, maxMovement: null, production: 1 },
  fertile: { attritionRate: 0, difficult: false, maxMovement: null, production: 1 },
  desert: { attritionRate: 0.03, difficult: true, maxMovement: 1, production: 0 },
  mountain: { attritionRate: 0.03, difficult: true, maxMovement: 1, production: 0 },
};

export function inPolygon(x, y, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const [xi, yi] = polygon[i];
    const [xj, yj] = polygon[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// Authored approximate terrain regions in the illustration's 1024 × 1536 coordinates.
const DELTA = [[180,319],[225,275],[310,258],[372,291],[423,334],[364,382],[313,403],[265,365]];
const NILE = [[317,377],[335,435],[303,501],[283,571],[301,665],[343,713],[345,776],[389,854],[414,923],[393,1003],[361,1080],[348,1155],[372,1216],[350,1289],[387,1375],[439,1455],[473,1536]];
const EUPHRATES = [[798,28],[815,47],[853,43],[900,52],[931,73],[949,103],[929,126],[904,139],[910,158],[909,181],[932,199],[980,208],[1024,225]];
const JORDAN = [[847,112],[819,141],[789,166],[786,198],[765,215],[750,230],[740,265],[722,292],[706,325],[700,355]];
export const RIVERS = [
  { id: 'nile', path: NILE, width: 23 },
  { id: 'euphrates', path: EUPHRATES, width: 23 },
  { id: 'jordan', path: JORDAN, width: 20 },
];
const MOUNTAINS = [
  [[370,385],[413,407],[460,506],[510,586],[532,666],[576,729],[607,836],[655,950],[679,1040],[706,1104],[662,1119],[621,1037],[575,940],[532,855],[490,776],[449,694],[416,605],[381,526],[359,454]],
  [[736,48],[804,96],[762,170],[727,243],[695,286],[682,244],[700,166]],
  [[665,365],[690,398],[661,484],[623,574],[592,610],[567,566],[591,503],[625,450]],
  [[741,454],[798,499],[834,557],[779,588],[716,524]],
  [[772,650],[849,692],[891,780],[822,808],[769,759]],
  [[829,874],[902,933],[953,1039],[907,1089],[858,993]],
  [[496,1211],[606,1253],[666,1322],[721,1397],[744,1514],[666,1536],[586,1428],[542,1344]],
  [[224,1115],[274,1154],[272,1231],[202,1285],[109,1250],[150,1180]],
  [[24,372],[84,362],[143,392],[187,444],[121,460],[47,421]],
  [[12,543],[108,565],[190,598],[231,648],[165,660],[85,627],[9,598]],
  [[19,801],[104,801],[193,861],[227,915],[149,936],[61,896]],
];

function segmentDistance(x, y, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const fraction = Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - a[0] - fraction * dx, y - a[1] - fraction * dy);
}

export function terrainAt(x, y, land) {
  if (!land) return 'water';
  if (inPolygon(x, y, DELTA) || riverAt(x, y)) return 'fertile';
  if (MOUNTAINS.some((polygon) => inPolygon(x, y, polygon))) return 'mountain';
  return 'desert';
}

export function riverAt(x, y) {
  return RIVERS.find((river) => river.path.slice(1).some((point, index) => segmentDistance(x, y, river.path[index], point) <= river.width))?.id || null;
}

export function isNileValley(x, y) {
  return inPolygon(x, y, DELTA) || riverAt(x, y) === 'nile';
}
