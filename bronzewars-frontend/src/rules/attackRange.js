export function isPositionInAttackRange(origin, target, range) {
  if (!origin || !target) return false;

  const normalizedRange = Math.max(0, Math.trunc(Number(range) || 0));
  const deltaX = Math.abs(Number(target.x) - Number(origin.x));
  const deltaY = Math.abs(Number(target.y) - Number(origin.y));

  if (normalizedRange === 0 || (deltaX === 0 && deltaY === 0)) return false;
  return deltaX + deltaY <= normalizedRange;
}

export function getAttackTargetIds(selectedUnit, armies) {
  const targets = new Set();
  if (!selectedUnit?.position || selectedUnit.side !== 'HUMAN' || selectedUnit.active === false) return targets;

  const attackRange = selectedUnit.type?.attackRange;
  armies.forEach((army) => {
    if (army.side === selectedUnit.side) return;
    army.units.forEach((unit) => {
      if (unit.active === false || !unit.position) return;
      if (isPositionInAttackRange(selectedUnit.position, unit.position, attackRange)) {
        targets.add(String(unit.id));
      }
    });
  });

  return targets;
}
