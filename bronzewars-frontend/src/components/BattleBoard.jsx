import { useEffect, useMemo, useState } from 'react';
import { useI18n } from '../i18n/I18nContext';
import { getAttackTargetIds } from '../rules/attackRange';
import { getUnitTurnState } from '../rules/unitTurnState';
import UnitArtwork from './UnitArtwork';

function positionKey(x, y) {
  return `${x}:${y}`;
}

export default function BattleBoard({ battle, armyDesignId, selectedUnitId, animatingUnitId, draggedUnitId, canDeploy, canMove, canAttack, busy, onUnitDragStart, onUnitDragEnd, onUnitDrop, onUnitMove, onUnitSelect, onAttackTarget }) {
  const { t } = useI18n();
  const { width, height } = battle.board;
  const [dropTarget, setDropTarget] = useState(null);

  useEffect(() => {
    if (!draggedUnitId) setDropTarget(null);
  }, [draggedUnitId]);

  const unitsByPosition = useMemo(() => {
    const positions = new Map();
    battle.armies.forEach((army) => {
      army.units.forEach((unit) => {
        if (unit.position) positions.set(positionKey(unit.position.x, unit.position.y), { ...unit, side: army.side, faction: army.faction });
      });
    });
    return positions;
  }, [battle]);

  const selectedUnit = useMemo(() => {
    for (const army of battle.armies) {
      const unit = army.units.find((candidate) => String(candidate.id) === String(selectedUnitId));
      if (unit) return { ...unit, side: army.side, faction: army.faction };
    }
    return null;
  }, [battle, selectedUnitId]);

  const movementTargets = useMemo(() => {
    const targets = new Set();
    if (!canMove || selectedUnit?.side !== 'HUMAN' || !selectedUnit.position || selectedUnit.remainingMovement <= 0) return targets;
    const directions = [[0, -1], [0, 1], [-1, 0], [1, 0]];
    directions.forEach(([stepX, stepY]) => {
      for (let step = 1; step <= selectedUnit.remainingMovement; step += 1) {
        const targetX = selectedUnit.position.x + (stepX * step);
        const targetY = selectedUnit.position.y + (stepY * step);
        if (targetX < 0 || targetX >= width || targetY < 0 || targetY >= height) break;
        const key = positionKey(targetX, targetY);
        if (unitsByPosition.has(key)) break;
        targets.add(key);
      }
    });
    return targets;
  }, [canMove, height, selectedUnit, unitsByPosition, width]);

  const attackTargetIds = useMemo(
    () => (canAttack ? getAttackTargetIds(selectedUnit, battle.armies) : new Set()),
    [battle.armies, canAttack, selectedUnit],
  );

  const cells = [];
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const unit = unitsByPosition.get(positionKey(x, y));
      const zone = y <= 2 ? 'ai' : y >= height - 3 ? 'human' : 'neutral';
      const selected = unit && String(unit.id) === String(selectedUnitId);
      const deploymentDropAllowed = canDeploy && zone === 'human' && (!unit || String(unit.id) === String(draggedUnitId));
      const movementAllowed = movementTargets.has(positionKey(x, y));
      const attackable = Boolean(unit) && attackTargetIds.has(String(unit.id));
      const dropAllowed = deploymentDropAllowed;
      const inspectable = Boolean(unit) && !canDeploy && !busy;
      const cellKey = positionKey(x, y);
      const turnState = unit?.side === 'HUMAN' && !canDeploy
        ? getUnitTurnState(unit, battle.armies, { canMove, canAttack })
        : null;
      const turnStateLabel = turnState ? t(`battle.unitTurnState.${turnState}`) : '';
      cells.push(
        <div
          aria-label={`${t('battle.cell', { x, y })}${unit ? `: ${unit.name}` : ''}${attackable ? `. ${t('battle.attackTarget')}` : ''}`}
          aria-disabled={busy || (canDeploy ? zone !== 'human' : (!unit && !canMove))}
          className={`board-cell zone-${zone} ${canDeploy && zone === 'human' && !busy ? 'is-deployment-target' : ''} ${movementAllowed && !busy ? 'is-movement-target' : ''} ${attackable ? 'is-attack-target' : ''} ${inspectable ? 'is-inspectable' : ''} ${unit ? 'has-unit' : ''} ${selected ? 'is-selected' : ''} ${dropTarget === cellKey ? 'is-drop-target' : ''}`}
          key={cellKey}
          onClick={() => {
            if (attackable && !busy) onAttackTarget(unit);
            else if (inspectable) onUnitSelect(unit);
            if (!busy && movementAllowed && selectedUnit) onUnitMove(selectedUnit.id, { x, y });
          }}
          onDragLeave={(event) => {
            if (!event.currentTarget.contains(event.relatedTarget)) setDropTarget(null);
          }}
          onDragOver={(event) => {
            if (!busy && dropAllowed) {
              event.preventDefault();
              event.dataTransfer.dropEffect = 'move';
              setDropTarget(cellKey);
            }
          }}
          onDrop={(event) => {
            event.preventDefault();
            const unitId = event.dataTransfer.getData('text/plain') || draggedUnitId;
            setDropTarget(null);
            if (!busy && dropAllowed && unitId) {
              if (canDeploy) onUnitDrop(unitId, { x, y });
            }
          }}
          onKeyDown={(event) => {
            if (inspectable && (event.key === 'Enter' || event.key === ' ')) {
              event.preventDefault();
              if (attackable) onAttackTarget(unit);
              else onUnitSelect(unit);
            }
          }}
          role="gridcell"
          tabIndex={inspectable ? 0 : -1}
          title={attackable ? `${unit.name} · ${t('battle.attackTarget')}` : unit?.name || t(`battle.${zone}Zone`)}
        >
          <span className="cell-coordinate">{x},{y}</span>
          {unit && (
            <span
              className={`unit-token side-${unit.side.toLowerCase()} ${attackable ? 'is-attack-target' : ''} ${String(unit.id) === String(animatingUnitId) ? 'is-animating' : ''}`}
              draggable={!busy && unit.side === 'HUMAN' && canDeploy}
              onDragEnd={onUnitDragEnd}
              onDragStart={(event) => {
                if (unit.side !== 'HUMAN' || !canDeploy) return;
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData('text/plain', String(unit.id));
                onUnitDragStart(unit.id);
              }}
            >
              <UnitArtwork
                unitCode={unit.type.code}
                armyDesignId={armyDesignId}
                faction={unit.faction}
                className="unit-token__image"
                alt=""
              />
              <span className="unit-token__shade" />
              {!canDeploy && unit.side === 'HUMAN' && (
                <span
                  aria-label={turnStateLabel}
                  className={`unit-turn-dot is-${turnState}`}
                  title={turnStateLabel}
                />
              )}
              <span className="unit-token__strength">{unit.currentStrength}</span>
            </span>
          )}
        </div>,
      );
    }
  }

  return (
    <section className="board-shell panel">
      <div className="board-legend">
        <span><i className="legend-swatch zone-ai" />{t('battle.aiZone')}</span>
        <span><i className="legend-swatch zone-neutral" />{t('battle.neutralZone')}</span>
        <span><i className="legend-swatch zone-human" />{t('battle.humanZone')}</span>
        {attackTargetIds.size > 0 && <span><i className="legend-swatch attack-range" />{t('battle.attackTarget')}</span>}
      </div>
      <div className="board-scroll">
        <div
          className="battle-board"
          style={{ '--board-width': width }}
          role="grid"
          aria-label={battle.name}
        >
          {cells}
        </div>
      </div>
    </section>
  );
}
