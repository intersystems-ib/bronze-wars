import { useState } from 'react';
import { ARMY_DESIGNS, getArmyDesign, getUnitTypesForDesign } from '../config/armyDesigns';
import { DEFAULT_ARMY_QUANTITIES, GRAIN_BUDGET } from '../config/armyRules';
import { useI18n } from '../i18n/I18nContext';
import ArmyBuilder from './ArmyBuilder';
import UnitArtwork from './UnitArtwork';

export default function BattleSetup({ unitTypes, loadingUnitTypes, armyDesignId, busy, onArmyDesignChange, onCreate }) {
  const { t } = useI18n();
  const [name, setName] = useState('');
  const [width, setWidth] = useState(15);
  const [height, setHeight] = useState(12);
  const [quantities, setQuantities] = useState(DEFAULT_ARMY_QUANTITIES);
  const selectedArmyIndex = Math.max(0, ARMY_DESIGNS.findIndex((design) => design.id === armyDesignId));
  const selectedArmyDesign = ARMY_DESIGNS[selectedArmyIndex];
  const availableUnitTypes = getUnitTypesForDesign(unitTypes, armyDesignId);
  const spent = availableUnitTypes.reduce((total, unit) => total + ((quantities[unit.code] || 0) * unit.grainCost), 0);
  const unitCount = Object.values(quantities).reduce((total, quantity) => total + quantity, 0);
  const validArmy = !loadingUnitTypes && unitCount > 0 && spent <= GRAIN_BUDGET && unitCount <= Number(width) * 3;

  function submitCreate(event) {
    event.preventDefault();
    onCreate({
      name: name.trim() || undefined,
      boardWidth: Number(width),
      boardHeight: Number(height),
      armyDesignId,
      faction: getArmyDesign(armyDesignId).faction,
      units: availableUnitTypes
        .map((unit) => ({ code: unit.code, quantity: quantities[unit.code] || 0 }))
        .filter((unit) => unit.quantity > 0),
    });
  }

  function showArmy(offset) {
    const nextIndex = (selectedArmyIndex + offset + ARMY_DESIGNS.length) % ARMY_DESIGNS.length;
    onArmyDesignChange(ARMY_DESIGNS[nextIndex].id);
  }

  return (
    <main className="start-page">
      <section className="start-card panel">
        <p className="eyebrow">{t('setup.eyebrow')}</p>
        <h1>{t('setup.title')}</h1>
        <p className="lede">{t('setup.description')}</p>

        <form className="setup-form" onSubmit={submitCreate}>
          <fieldset className="army-picker field--wide">
            <legend>{t('setup.armyType')}</legend>
            <p>{t('setup.armyHelp')}</p>
            <div className="army-gallery">
              <button
                aria-label={t('setup.previousArmy', { army: t(ARMY_DESIGNS[(selectedArmyIndex - 1 + ARMY_DESIGNS.length) % ARMY_DESIGNS.length].nameKey) })}
                className="army-gallery__control"
                onClick={() => showArmy(-1)}
                title={t(ARMY_DESIGNS[(selectedArmyIndex - 1 + ARMY_DESIGNS.length) % ARMY_DESIGNS.length].nameKey)}
                type="button"
              >
                &lt;
              </button>
              <label aria-live="polite" className="army-option is-selected" key={selectedArmyDesign.id}>
                <input
                  checked
                  name="army-design"
                  onChange={() => onArmyDesignChange(selectedArmyDesign.id)}
                  type="radio"
                  value={selectedArmyDesign.id}
                />
                <span className="army-option__art" aria-hidden="true">
                  <UnitArtwork unitCode="ARCHERS" armyDesignId={selectedArmyDesign.id} />
                  <UnitArtwork unitCode="HEAVY_INFANTRY" armyDesignId={selectedArmyDesign.id} />
                  <UnitArtwork unitCode="CHARIOTS" armyDesignId={selectedArmyDesign.id} />
                </span>
                <span className="army-option__body">
                  <strong>{t(selectedArmyDesign.nameKey)}</strong>
                  <small>{t(selectedArmyDesign.descriptionKey)}</small>
                </span>
              </label>
              <button
                aria-label={t('setup.nextArmy', { army: t(ARMY_DESIGNS[(selectedArmyIndex + 1) % ARMY_DESIGNS.length].nameKey) })}
                className="army-gallery__control"
                onClick={() => showArmy(1)}
                title={t(ARMY_DESIGNS[(selectedArmyIndex + 1) % ARMY_DESIGNS.length].nameKey)}
                type="button"
              >
                &gt;
              </button>
            </div>
          </fieldset>
          <label className="field field--wide">
            <span>{t('setup.name')}</span>
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={t('setup.namePlaceholder')}
              maxLength={120}
            />
          </label>
          <label className="field">
            <span>{t('setup.width')}</span>
            <input type="number" min="1" max="30" value={width} onChange={(event) => setWidth(event.target.value)} />
          </label>
          <label className="field">
            <span>{t('setup.height')}</span>
            <input type="number" min="6" max="24" value={height} onChange={(event) => setHeight(event.target.value)} />
          </label>
          <ArmyBuilder
            unitTypes={availableUnitTypes}
            quantities={quantities}
            armyDesignId={armyDesignId}
            loading={loadingUnitTypes}
            onChange={setQuantities}
          />
          <button className="button button--primary field--wide" disabled={busy || !validArmy} type="submit">
            {busy ? t('setup.creating') : t('setup.create')}
          </button>
        </form>

      </section>
    </main>
  );
}
