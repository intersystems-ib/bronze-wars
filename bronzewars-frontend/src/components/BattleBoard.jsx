import { useMemo } from 'react';
import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

function positionKey(x, y) {
  return `${x}:${y}`;
}

export default function BattleBoard({ battle, armyDesignId, selectedUnitId, canDeploy, busy, onCellClick }) {
  const { t } = useI18n();
  const { width, height } = battle.board;

  const unitsByPosition = useMemo(() => {
    const positions = new Map();
    battle.armies.forEach((army) => {
      army.units.forEach((unit) => {
        if (unit.position) positions.set(positionKey(unit.position.x, unit.position.y), { ...unit, side: army.side, faction: army.faction });
      });
    });
    return positions;
  }, [battle]);

  const cells = [];
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const unit = unitsByPosition.get(positionKey(x, y));
      const zone = y <= 2 ? 'ai' : y >= height - 3 ? 'human' : 'neutral';
      const selected = unit && String(unit.id) === String(selectedUnitId);
      const clickable = canDeploy && zone === 'human' && (!unit || selected);
      cells.push(
        <button
          aria-label={`${t('battle.cell', { x, y })}${unit ? `: ${unit.name}` : ''}`}
          className={`board-cell zone-${zone} ${unit ? 'has-unit' : ''} ${selected ? 'is-selected' : ''}`}
          disabled={busy || !clickable}
          key={positionKey(x, y)}
          onClick={() => onCellClick({ x, y })}
          title={unit?.name || t(`battle.${zone}Zone`)}
          type="button"
        >
          <span className="cell-coordinate">{x},{y}</span>
          {unit && (
            <span className={`unit-token side-${unit.side.toLowerCase()}`}>
              <UnitArtwork
                unitCode={unit.type.code}
                armyDesignId={armyDesignId}
                faction={unit.faction}
                className="unit-token__image"
                alt=""
              />
              <span className="unit-token__shade" />
              <span className="unit-token__name">{unit.name}</span>
              <span className="unit-token__strength">{unit.currentStrength}</span>
            </span>
          )}
        </button>,
      );
    }
  }

  return (
    <section className="board-shell panel">
      <div className="board-legend">
        <span><i className="legend-swatch zone-ai" />{t('battle.aiZone')}</span>
        <span><i className="legend-swatch zone-neutral" />{t('battle.neutralZone')}</span>
        <span><i className="legend-swatch zone-human" />{t('battle.humanZone')}</span>
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
