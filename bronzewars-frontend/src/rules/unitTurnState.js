import { getAttackTargetIds, hasUnitAttacked } from './attackRange.js';

export function getUnitTurnState(unit, armies, { canMove, canAttack }) {
  const attackSpent = hasUnitAttacked(unit);
  if (!unit?.hasMoved && !attackSpent) return 'pending';

  const movementAvailable = canMove && Number(unit.remainingMovement) > 0;
  const attackAvailable = canAttack
    && !attackSpent
    && getAttackTargetIds(unit, armies).size > 0;

  return movementAvailable || attackAvailable ? 'actionable' : 'finished';
}
