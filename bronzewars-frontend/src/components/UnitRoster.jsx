import { useI18n } from '../i18n/I18nContext';
import { getArmyDesignForFaction } from '../config/armyDesigns';
import UnitArtwork from './UnitArtwork';

export default function UnitRoster({ army, selectedUnitId, disabled, onSelect, onDragStart, onDragEnd }) {
  const { t } = useI18n();
  const armyDesign = getArmyDesignForFaction(army?.faction);
  const undeployedUnits = army?.units.filter((unit) => !unit.isDeployed) || [];
  const ready = Boolean(army?.units.every((unit) => unit.isDeployed));

  return (
    <section className="roster panel">
      <div className="section-heading section-heading--inline">
        <div>
          <p className="eyebrow">{t(armyDesign.nameKey)}</p>
          <h2>{t('battle.human')}</h2>
        </div>
        <span className={`readiness ${ready ? 'is-ready' : ''}`}>
          {ready ? t('battle.ready') : t('battle.notReady')}
        </span>
      </div>

      <div className="roster-list">
        {undeployedUnits.map((unit) => {
          const selected = String(unit.id) === String(selectedUnitId);
          return (
            <article
              aria-label={t('battle.dragUnit', { unit: unit.type.name })}
              className={`roster-unit ${selected ? 'is-selected' : ''}`}
              draggable={!disabled && Boolean(unit.active)}
              key={unit.id}
              onDragEnd={onDragEnd}
              onDragStart={(event) => {
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData('text/plain', String(unit.id));
                const dragImage = event.currentTarget.querySelector('.roster-unit__drag-preview');
                if (dragImage) {
                  event.dataTransfer.setDragImage(dragImage, dragImage.clientWidth / 2, dragImage.clientHeight / 2);
                }
                onSelect(unit);
                onDragStart(unit.id);
              }}
              title={t('battle.dragUnit', { unit: unit.type.name })}
            >
              <span className="roster-unit__mark">
                <UnitArtwork unitCode={unit.type.code} faction={army?.faction} alt="" />
              </span>
              <span className="roster-unit__drag-preview" aria-hidden="true">
                <UnitArtwork
                  unitCode={unit.type.code}
                  faction={army?.faction}
                  variant="battlefield"
                  alt=""
                  loading="eager"
                />
              </span>
              <span className="roster-unit__body">
                <strong>{unit.type.name}</strong>
              </span>
            </article>
          );
        })}
        {ready && <p className="roster-empty">{t('battle.allUnitsDeployed')}</p>}
      </div>
    </section>
  );
}
