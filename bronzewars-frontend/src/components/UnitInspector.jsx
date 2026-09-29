import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

const STAT_SYMBOLS = {
  attack: '\u{1301C}',
  defense: '\u{1309A}',
  movement: '\u{1321D}',
  projectiles: '\u{13316}',
  damage: '\u{130BF}',
};

function Stat({ className, symbol, label, value }) {
  return (
    <div className={`unit-inspector__stat ${className}`} aria-label={`${label}: ${value}`} title={`${label}: ${value}`}>
      <dt aria-hidden="true">{symbol}</dt>
      <dd>{value}</dd>
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
  const totalProjectiles = Math.max(0, Number(unit.type.initialProjectiles) || 0);
  const availableProjectiles = Number.isFinite(Number(unit.projectiles))
    ? Math.max(0, Math.min(totalProjectiles, Number(unit.projectiles)))
    : totalProjectiles;
  const availableMovement = Number.isFinite(Number(unit.remainingMovement))
    ? Math.max(0, Number(unit.remainingMovement))
    : Number(unit.type.speed);

  return (
    <aside className="unit-inspector panel">
      <p className="eyebrow">{t(`battle.${army.side.toLowerCase()}`)}</p>
      <h2>{unit.type.name}</h2>

      <div className="unit-inspector__art">
        <UnitArtwork unitCode={unit.type.code} faction={army.faction} alt={unit.type.name} loading="eager" />
      </div>

      <dl className="unit-inspector__stats">
        <Stat className="is-attack" symbol={STAT_SYMBOLS.attack} label={t('battle.attack')} value={unit.type.attack} />
        <Stat className="is-defense" symbol={STAT_SYMBOLS.defense} label={t('battle.defense')} value={unit.type.defense} />
        <Stat className="is-movement" symbol={STAT_SYMBOLS.movement} label={t('battle.movement')} value={availableMovement} />
        <Stat
          className="is-projectiles"
          symbol={STAT_SYMBOLS.projectiles}
          label={t('battle.projectilesAvailable')}
          value={availableProjectiles}
        />
        <Stat className="is-damage" symbol={STAT_SYMBOLS.damage} label={t('battle.damage')} value={unit.type.damage} />
      </dl>

      <dl className="unit-inspector__details">
        <div><dt>{t('battle.strength')}</dt><dd>{unit.currentStrength} / {unit.type.initialStrength}</dd></div>
        <div><dt>{t('battle.range')}</dt><dd>{unit.type.attackRange}</dd></div>
      </dl>

      <div className="unit-inspector__morale">
        <div className="unit-inspector__morale-heading">
          <span>{t('battle.morale')}</span>
          <strong>{morale}</strong>
        </div>
        <div className="morale-meter" aria-label={t('battle.moraleValue', { value: morale })}>
          <span style={{ width: `${moralePercent}%` }} />
        </div>
      </div>
      <p className="unit-inspector__description">{unit.type.description}</p>
    </aside>
  );
}
