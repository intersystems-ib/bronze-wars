import { useEffect, useMemo, useState } from 'react';
import { useI18n } from '../i18n/I18nContext';
import sandTexture from '../assets/dessert/sand.jpg';
import sandBushesTexture from '../assets/dessert/sand_bushes.jpg';
import sandStonesTexture from '../assets/dessert/sand_stones.jpg';
import grassTexture from '../assets/plains/grass.jpg';
import grassBushesTexture from '../assets/plains/grass_bushes.jpg';
import grassStonesTexture from '../assets/plains/grass_stones.jpg';
import { getAttackTargetIds } from '../rules/attackRange';
import { getUnitTurnState } from '../rules/unitTurnState';
import UnitArtwork from './UnitArtwork';

function positionKey(x, y) {
  return `${x}:${y}`;
}

const TERRAIN_TEXTURES = {
  DESERT: { base: sandTexture, bushes: sandBushesTexture, stones: sandStonesTexture },
  PLAINS: { base: grassTexture, bushes: grassBushesTexture, stones: grassStonesTexture },
};

const DEFAULT_CELL_WIDTH = 104;
const MIN_ZOOM = 50;
const MAX_ZOOM = 150;
const ZOOM_STEP = 10;

function hashSeed(value) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function seededRandom(seed) {
  let state = seed;
  return () => {
    state += 0x6D2B79F5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function buildTerrainFeatures(width, height, seed) {
  const random = seededRandom(hashSeed(seed));
  const features = new Map();
  const regions = [];
  const regionCount = Math.max(2, Math.min(4, Math.floor((width * height) / 45)));

  for (let index = 0; index < regionCount; index += 1) {
    const radiusX = 1 + Math.floor(random() * 2);
    const radiusY = 1 + Math.floor(random() * 2);
    let center = null;

    for (let attempt = 0; attempt < 40 && !center; attempt += 1) {
      const x = radiusX + Math.floor(random() * Math.max(1, width - (radiusX * 2)));
      const y = radiusY + Math.floor(random() * Math.max(1, height - (radiusY * 2)));
      const separated = regions.every((region) => (
        Math.abs(region.x - x) + Math.abs(region.y - y)
          > Math.max(region.radiusX, region.radiusY) + Math.max(radiusX, radiusY) + 2
      ));
      if (separated) center = { x, y, radiusX, radiusY };
    }

    if (!center) continue;
    regions.push(center);
    const feature = index % 2 === 0 ? 'bushes' : 'stones';
    for (let y = center.y - radiusY; y <= center.y + radiusY; y += 1) {
      for (let x = center.x - radiusX; x <= center.x + radiusX; x += 1) {
        const distance = ((x - center.x) ** 2) / (radiusX ** 2)
          + ((y - center.y) ** 2) / (radiusY ** 2);
        if (distance <= 1.15) features.set(positionKey(x, y), feature);
      }
    }
  }

  return features;
}

export default function BattleBoard({ battle, armyDesignId, selectedUnitId, animatingUnitId, draggedUnitId, canDeploy, canMove, canAttack, busy, onUnitDragStart, onUnitDragEnd, onUnitDrop, onUnitMove, onUnitSelect, onAttackTarget }) {
  const { t } = useI18n();
  const { width, height } = battle.board;
  const [dropTarget, setDropTarget] = useState(null);
  const [zoom, setZoom] = useState(100);
  const cellWidth = Math.round(DEFAULT_CELL_WIDTH * (zoom / 100));
  const terrain = TERRAIN_TEXTURES[battle.terrain] ? battle.terrain : 'DESERT';
  const terrainTextures = TERRAIN_TEXTURES[terrain];
  const terrainFeatures = useMemo(
    () => buildTerrainFeatures(width, height, `${battle.id}:${terrain}`),
    [battle.id, height, terrain, width],
  );

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
          style={{
            '--terrain-image': `url(${terrainTextures[terrainFeatures.get(cellKey) || 'base']})`,
            '--terrain-position': `${(x * 37 + y * 11) % 101}% ${(y * 43 + x * 7) % 101}%`,
          }}
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
                variant="battlefield"
                className="unit-token__image"
                alt=""
              />
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
        <div className="board-zoom" role="group" aria-label={t('battle.zoomControls')}>
          <button
            type="button"
            aria-label={t('battle.zoomOut')}
            title={t('battle.zoomOut')}
            disabled={zoom <= MIN_ZOOM}
            onClick={() => setZoom((value) => Math.max(MIN_ZOOM, value - ZOOM_STEP))}
          >−</button>
          <button
            type="button"
            className="board-zoom__level"
            aria-label={t('battle.resetZoom')}
            title={t('battle.resetZoom')}
            disabled={zoom === 100}
            onClick={() => setZoom(100)}
          >{zoom}%</button>
          <button
            type="button"
            aria-label={t('battle.zoomIn')}
            title={t('battle.zoomIn')}
            disabled={zoom >= MAX_ZOOM}
            onClick={() => setZoom((value) => Math.min(MAX_ZOOM, value + ZOOM_STEP))}
          >+</button>
        </div>
      </div>
      <div className="board-scroll">
        <div
          className={`battle-board terrain-${terrain.toLowerCase()}`}
          style={{
            '--board-width': width,
            '--board-cell-width': `${cellWidth}px`,
            '--board-min-width': `${width * cellWidth}px`,
          }}
          role="grid"
          aria-label={battle.name}
        >
          {cells}
        </div>
      </div>
    </section>
  );
}
