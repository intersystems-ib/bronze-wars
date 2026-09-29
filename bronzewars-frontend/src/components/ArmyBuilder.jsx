import { GRAIN_BUDGET } from '../config/armyRules';
import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

export default function ArmyBuilder({ unitTypes, quantities, armyDesignId, loading, onChange }) {
  const { t } = useI18n();
  const spent = unitTypes.reduce(
    (total, unit) => total + ((quantities[unit.code] || 0) * unit.grainCost),
    0,
  );
  const remaining = GRAIN_BUDGET - spent;
  const unitCount = Object.values(quantities).reduce((total, quantity) => total + quantity, 0);

  function setQuantity(unit, nextQuantity) {
    const quantity = Math.max(0, Math.min(99, Number.isFinite(nextQuantity) ? nextQuantity : 0));
    onChange({ ...quantities, [unit.code]: quantity });
  }

  if (loading) {
    return <div className="army-builder-loading"><span className="loader" />{t('armyBuilder.loading')}</div>;
  }

  return (
    <fieldset className="army-builder field--wide">
      <div className="army-builder__heading">
        <div>
          <legend>{t('armyBuilder.title')}</legend>
          <p>{t('armyBuilder.help')}</p>
        </div>
        <div className={`grain-budget ${remaining < 0 ? 'is-over' : ''}`}>
          <strong>{remaining}</strong>
          <span>{t('armyBuilder.grainRemaining')}</span>
          <small>{t('armyBuilder.summary', { spent, total: GRAIN_BUDGET, units: unitCount })}</small>
        </div>
      </div>

      <div className="grain-progress" aria-hidden="true">
        <span style={{ width: `${Math.min(100, spent)}%` }} />
      </div>

      <div className="army-unit-grid">
        {unitTypes.map((unit) => {
          const quantity = quantities[unit.code] || 0;
          const canAdd = spent + unit.grainCost <= GRAIN_BUDGET;
          return (
            <article className={`army-unit ${quantity > 0 ? 'is-selected' : ''}`} key={unit.code}>
              <UnitArtwork unitCode={unit.code} armyDesignId={armyDesignId} className="army-unit__image" alt="" />
              <div className="army-unit__body">
                <strong>{unit.name}</strong>
                <span className="army-unit__cost">{t('armyBuilder.unitCost', { cost: unit.grainCost })}</span>
                <dl className="army-unit__stats">
                  <div
                    className="army-unit__stat army-unit__stat--attack"
                    aria-label={t('armyBuilder.attackStat', { value: unit.attack })}
                    title={t('armyBuilder.attackStat', { value: unit.attack })}
                  >
                    <dt aria-hidden="true">&#x1301C;</dt><dd>{unit.attack}</dd>
                  </div>
                  <div
                    className="army-unit__stat army-unit__stat--defense"
                    aria-label={t('armyBuilder.defenseStat', { value: unit.defense })}
                    title={t('armyBuilder.defenseStat', { value: unit.defense })}
                  >
                    <dt aria-hidden="true">&#x1309A;</dt><dd>{unit.defense}</dd>
                  </div>
                  <div
                    className="army-unit__stat army-unit__stat--movement"
                    aria-label={t('armyBuilder.movementStat', { value: unit.speed })}
                    title={t('armyBuilder.movementStat', { value: unit.speed })}
                  >
                    <dt aria-hidden="true">&#x1321D;</dt><dd>{unit.speed}</dd>
                  </div>
                  <div
                    className="army-unit__stat army-unit__stat--projectiles"
                    aria-label={t('armyBuilder.projectilesStat', { value: unit.initialProjectiles })}
                    title={t('armyBuilder.projectilesStat', { value: unit.initialProjectiles })}
                  >
                    <dt aria-hidden="true">&#x13316;</dt><dd>{unit.initialProjectiles}</dd>
                  </div>
                  <div
                    className="army-unit__stat army-unit__stat--damage"
                    aria-label={t('armyBuilder.damageStat', { value: unit.damage })}
                    title={t('armyBuilder.damageStat', { value: unit.damage })}
                  >
                    <dt aria-hidden="true">&#x130BF;</dt><dd>{unit.damage}</dd>
                  </div>
                </dl>
              </div>
              <div className="quantity-control">
                <button
                  disabled={quantity === 0}
                  onClick={() => setQuantity(unit, quantity - 1)}
                  type="button"
                  aria-label={t('armyBuilder.removeUnit', { unit: unit.name })}
                >−</button>
                <input
                  aria-label={t('armyBuilder.unitQuantity', { unit: unit.name })}
                  min="0"
                  max="99"
                  onChange={(event) => setQuantity(unit, Number.parseInt(event.target.value, 10))}
                  type="number"
                  value={quantity}
                />
                <button
                  disabled={!canAdd}
                  onClick={() => setQuantity(unit, quantity + 1)}
                  type="button"
                  aria-label={t('armyBuilder.addUnit', { unit: unit.name })}
                >+</button>
              </div>
            </article>
          );
        })}
      </div>
      {remaining < 0 && <p className="field-error">{t('armyBuilder.overBudget')}</p>}
      {unitCount === 0 && <p className="field-error">{t('armyBuilder.emptyArmy')}</p>}
    </fieldset>
  );
}
