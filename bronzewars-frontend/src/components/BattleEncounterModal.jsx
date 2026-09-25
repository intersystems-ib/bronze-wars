import { useEffect } from 'react';
import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

const STAT_SYMBOLS = {
  attack: '\u{1301C}',
  defense: '\u{1309A}',
  movement: '\u{130BB}',
};

function Combatant({ unit, army, sideLabel }) {
  const { t } = useI18n();
  const morale = Number.isFinite(Number(unit.morale)) ? Number(unit.morale) : 100;

  return (
    <article className={`encounter-combatant side-${army.side.toLowerCase()}`}>
      <p className="eyebrow">{sideLabel}</p>
      <h3>{unit.type.name}</h3>
      <div className="encounter-combatant__art">
        <UnitArtwork unitCode={unit.type.code} faction={army.faction} alt={unit.type.name} loading="eager" />
      </div>
      <dl className="encounter-combatant__primary-stats">
        <div className="is-attack" title={t('battle.attack')}>
          <dt aria-label={t('battle.attack')}>{STAT_SYMBOLS.attack}</dt>
          <dd>{unit.type.attack}</dd>
        </div>
        <div className="is-defense" title={t('battle.defense')}>
          <dt aria-label={t('battle.defense')}>{STAT_SYMBOLS.defense}</dt>
          <dd>{unit.type.defense}</dd>
        </div>
        <div className="is-movement" title={t('battle.movement')}>
          <dt aria-label={t('battle.movement')}>{STAT_SYMBOLS.movement}</dt>
          <dd>{unit.type.speed}</dd>
        </div>
      </dl>
      <dl className="encounter-combatant__details">
        <div><dt>{t('battle.strength')}</dt><dd>{unit.currentStrength} / {unit.type.initialStrength}</dd></div>
        <div><dt>{t('battle.morale')}</dt><dd>{morale}</dd></div>
        <div><dt>{t('battle.range')}</dt><dd>{unit.type.attackRange}</dd></div>
        <div><dt>{t('battle.damage')}</dt><dd>{unit.type.damage}</dd></div>
      </dl>
    </article>
  );
}

export default function BattleEncounterModal({ attacker, attackerArmy, defender, defenderArmy, onClose }) {
  const { t } = useI18n();

  useEffect(() => {
    function closeOnEscape(event) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [onClose]);

  if (!attacker || !attackerArmy || !defender || !defenderArmy) return null;

  return (
    <div
      className="encounter-overlay"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
      role="presentation"
    >
      <section
        aria-describedby="encounter-description"
        aria-labelledby="encounter-title"
        aria-modal="true"
        className="encounter-modal panel"
        role="dialog"
      >
        <header className="encounter-modal__header">
          <div>
            <p className="eyebrow">{t('battle.encounterEyebrow')}</p>
            <h2 id="encounter-title">{t('battle.encounterTitle')}</h2>
          </div>
          <button aria-label={t('app.close')} className="encounter-modal__close" onClick={onClose} type="button">×</button>
        </header>
        <p className="encounter-modal__description" id="encounter-description">{t('battle.encounterDescription')}</p>
        <div className="encounter-modal__combatants">
          <Combatant unit={attacker} army={attackerArmy} sideLabel={t('battle.attacker')} />
          <div className="encounter-modal__versus" aria-hidden="true">{t('battle.versus')}</div>
          <Combatant unit={defender} army={defenderArmy} sideLabel={t('battle.defender')} />
        </div>
        <footer className="encounter-modal__footer">
          <span>{t('battle.combatPending')}</span>
          <button autoFocus className="button button--secondary" onClick={onClose} type="button">{t('app.close')}</button>
        </footer>
      </section>
    </div>
  );
}
