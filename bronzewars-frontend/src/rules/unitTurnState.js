import { getAttackTargetIds } from './attackRange.js';

export function getUnitTurnState(unit, armies, { canMove, canAttack }) {
  if (!unit?.hasMoved) return 'pending';

  const movementAvailable = canMove && Number(unit.remainingMovement) > 0;
  const attackAvailable = canAttack
    && unit.hasAttacked !== true
    && getAttackTargetIds(unit, armies).size > 0;

  return movementAvailable || attackAvailable ? 'actionable' : 'finished';
}
