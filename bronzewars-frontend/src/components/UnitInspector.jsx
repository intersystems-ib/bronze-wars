import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

function Stat({ className, symbol, label, value, remaining }) {
  return (
    <div className={`unit-inspector__stat ${className}`} aria-label={`${label}: ${value}`} title={`${label}: ${value}`}>
      <dt aria-hidden="true">{symbol}</dt>
      <dd>{value}{remaining !== undefined ? ` (${remaining})` : ''}</dd>
    </div>
  );
}

export default function UnitInspector({ unit, army }) {
  const { t } = useI18n();

  if (!unit || !army) {
    return (
      <aside className="unit-inspector panel">
        <p className="eyebrow">{t('battle.unitInformation')}</p>
        <h2>{t('battle.noUnitSelected')}</h2>
        <p className="unit-inspector__empty">{t('battle.inspectInstruction')}</p>
      </aside>
    );
  }

  const morale = Number.isFinite(Number(unit.morale)) ? Number(unit.morale) : 100;
  const moralePercent = Math.max(0, Math.min(100, morale));

  return (
    <aside className="unit-inspector panel">
      <p className="eyebrow">{t(`battle.${army.side.toLowerCase()}`)}</p>
      <h2>{unit.type.name}</h2>

      <div className="unit-inspector__art">
        <UnitArtwork unitCode={unit.type.code} faction={army.faction} alt={unit.type.name} loading="eager" />
      </div>

      <dl className="unit-inspector__stats">
        <Stat className="is-attack" symbol="𓀜" label={t('battle.attack')} value={unit.type.attack} />
        <Stat className="is-defense" symbol="𓂚" label={t('battle.defense')} value={unit.type.defense} />
        <Stat className="is-movement" symbol="𓂻" label={t('battle.movement')} value={unit.type.speed} remaining={unit.remainingMovement} />
      </dl>

      <dl className="unit-inspector__details">
        <div><dt>{t('battle.strength')}</dt><dd>{unit.currentStrength} / {unit.type.initialStrength}</dd></div>
        <div><dt>{t('battle.morale')}</dt><dd>{morale}</dd></div>
        <div><dt>{t('battle.range')}</dt><dd>{unit.type.attackRange}</dd></div>
        <div><dt>{t('battle.damage')}</dt><dd>{unit.type.damage}</dd></div>
      </dl>

      <div className="morale-meter" aria-label={t('battle.moraleValue', { value: morale })}>
        <span style={{ width: `${moralePercent}%` }} />
      </div>
      <p className="unit-inspector__description">{unit.type.description}</p>
    </aside>
  );
}
