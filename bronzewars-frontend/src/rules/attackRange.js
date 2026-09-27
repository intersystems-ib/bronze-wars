export function isPositionInAttackRange(origin, target, range) {
  if (!origin || !target) return false;

  const normalizedRange = Math.max(0, Math.trunc(Number(range) || 0));
  const deltaX = Math.abs(Number(target.x) - Number(origin.x));
  const deltaY = Math.abs(Number(target.y) - Number(origin.y));

  if (normalizedRange === 0 || (deltaX === 0 && deltaY === 0)) return false;
  return deltaX + deltaY <= normalizedRange;
}

export function canUnitAttackPosition(unit, targetPosition) {
  if (!unit?.position || !targetPosition) return false;
  if (!isPositionInAttackRange(unit.position, targetPosition, unit.type?.attackRange)) return false;

  const deltaX = Math.abs(Number(targetPosition.x) - Number(unit.position.x));
  const deltaY = Math.abs(Number(targetPosition.y) - Number(unit.position.y));
  const orthogonallyAdjacent = deltaX + deltaY === 1;
  if (orthogonallyAdjacent) return true;

  return Number(unit.type?.initialProjectiles) > 0 && Number(unit.projectiles) > 0;
}

export function hasUnitAttacked(unit) {
  return unit?.hasAttacked === true || Number(unit?.hasAttacked) === 1;
}

export function getAttackTargetIds(selectedUnit, armies) {
  const targets = new Set();
  if (!selectedUnit?.position || selectedUnit.side !== 'HUMAN' || selectedUnit.active === false || Number(selectedUnit.active) === 0 || hasUnitAttacked(selectedUnit)) return targets;

  armies.forEach((army) => {
    if (army.side === selectedUnit.side) return;
    army.units.forEach((unit) => {
      if (unit.active === false || !unit.position) return;
      if (canUnitAttackPosition(selectedUnit, unit.position)) {
        targets.add(String(unit.id));
      }
    });
  });

  return targets;
}
