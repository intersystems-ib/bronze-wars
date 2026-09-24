import { useI18n } from '../i18n/I18nContext';
import { getArmyDesignForFaction } from '../config/armyDesigns';
import UnitArtwork from './UnitArtwork';

export default function UnitRoster({ army, selectedUnitId, disabled, onSelect }) {
  const { t } = useI18n();
  const armyDesign = getArmyDesignForFaction(army?.faction);

  return (
    <section className="roster panel">
      <div className="section-heading section-heading--inline">
        <div>
          <p className="eyebrow">{t(armyDesign.nameKey)}</p>
          <h2>{t('battle.human')}</h2>
        </div>
        <span className={`readiness ${army?.units.every((unit) => unit.isDeployed) ? 'is-ready' : ''}`}>
          {army?.units.every((unit) => unit.isDeployed) ? t('battle.ready') : t('battle.notReady')}
        </span>
      </div>

      <div className="roster-list">
        {army?.units.map((unit) => {
          const selected = String(unit.id) === String(selectedUnitId);
          return (
            <button
              className={`roster-unit ${selected ? 'is-selected' : ''}`}
              disabled={disabled || !unit.active}
              key={unit.id}
              onClick={() => onSelect(unit)}
              type="button"
            >
              <span className="roster-unit__mark">
                <UnitArtwork unitCode={unit.type.code} faction={army?.faction} alt="" />
              </span>
              <span className="roster-unit__body">
                <strong>{unit.name}</strong>
                <small>
                  {unit.position
                    ? t('battle.position', unit.position)
                    : t('battle.undeployed')}
                </small>
              </span>
              <span className={`deployment-dot ${unit.isDeployed ? 'is-deployed' : ''}`} title={unit.isDeployed ? t('battle.deployed') : t('battle.undeployed')} />
            </button>
          );
        })}
      </div>
    </section>
  );
}
