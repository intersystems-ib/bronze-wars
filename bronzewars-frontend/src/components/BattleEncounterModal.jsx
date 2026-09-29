import { useEffect, useRef, useState } from 'react';
import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

const STAT_SYMBOLS = {
  attack: '\u{1301C}',
  defense: '\u{1309A}',
  movement: '\u{1321D}',
  projectiles: '\u{13316}',
  damage: '\u{130BF}',
};

const AUTOMATIC_CASUALTY_DELAY_MS = 1000;
const RESULT_DISPLAY_MS = 3000;

function matchupAttackModifier(unit, opponent) {
  const modifier = (unit.type.attackModifiers || [])
    .find((candidate) => candidate.defenderCode === opponent.type.code);
  return Number(modifier?.value) || 0;
}

function defenseModifier(unit, opponent, attackType, isDefender) {
  if (isDefender && attackType === 'RANGED' && unit.type.code === 'LIGHT_CAVALRY') return 2;
  if (unit.type.code === 'SPEARMEN' && ['LIGHT_CAVALRY', 'HEAVY_CAVALRY', 'CHARIOTS'].includes(opponent.type.code)) return 2;
  return 0;
}

function attackDirection(attacker, defender, defenderArmy, result) {
  if (result?.attackDirection) return result.attackDirection;
  if (!attacker.position || !defender.position) return 'FRONT';
  const deltaY = attacker.position.y - defender.position.y;
  if (deltaY === 0) return 'FLANK';
  if (defenderArmy.side === 'AI' && deltaY < 0) return 'REAR';
  if (defenderArmy.side === 'HUMAN' && deltaY > 0) return 'REAR';
  return 'FRONT';
}

function combatBonuses(attacker, defender, defenderArmy, attackType, result) {
  const direction = attackDirection(attacker, defender, defenderArmy, result);
  const attackerAttack = attackType === 'MELEE'
    ? Number(result?.attackerAttackModifier ?? matchupAttackModifier(attacker, defender))
    : 0;
  const defenderAttack = attackType === 'MELEE'
    ? Number(result?.defenderAttackModifier ?? matchupAttackModifier(defender, attacker))
    : 0;
  const attackerDefense = attackType === 'MELEE'
    ? Number(result?.attackerDefenseModifier ?? defenseModifier(attacker, defender, attackType, false))
    : 0;
  const defenderDefense = Number(
    result?.defenderDefenseModifier ?? defenseModifier(defender, attacker, attackType, true),
  );
  const positionalPenalty = Number(
    result?.defenderPositionMoralePenalty ?? (['FLANK', 'REAR'].includes(direction) ? 10 : 0),
  );
  const attackerBonuses = [];
  const defenderBonuses = [];

  if (attackerAttack) attackerBonuses.push({ stat: 'attack', value: attackerAttack, key: 'matchupAttackModifier', target: defender.type.name });
  if (attackerDefense) attackerBonuses.push({ stat: 'defense', value: attackerDefense, key: 'matchupDefenseModifier', target: defender.type.name });
  if (defenderAttack) defenderBonuses.push({ stat: 'attack', value: defenderAttack, key: 'matchupAttackModifier', target: attacker.type.name });
  if (defenderDefense) defenderBonuses.push({ stat: 'defense', value: defenderDefense, key: 'matchupDefenseModifier', target: attacker.type.name });
  if (positionalPenalty) {
    attackerBonuses.push({ stat: 'attack', value: 0, key: direction === 'REAR' ? 'rearAttackBonus' : 'flankAttackBonus' });
    defenderBonuses.push({ stat: 'morale', value: -positionalPenalty, key: direction === 'REAR' ? 'rearMoralePenalty' : 'flankMoralePenalty' });
  }
  return { attacker: attackerBonuses, defender: defenderBonuses };
}

function Combatant({ unit, army, sideLabel, casualties, bonuses }) {
  const { t } = useI18n();
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
    <article className={`encounter-combatant side-${army.side.toLowerCase()}`}>
      <p className="eyebrow">{sideLabel}</p>
      <h3>{unit.type.name}</h3>
      <div className="encounter-combatant__art">
        <UnitArtwork unitCode={unit.type.code} faction={army.faction} alt={unit.type.name} loading="eager" />
        {Number(casualties) > 0 && (
          <span className="encounter-combatant__damage" aria-live="assertive">-{casualties}</span>
        )}
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
          <dd>{availableMovement}</dd>
        </div>
        <div className="is-projectiles" title={t('battle.projectilesAvailable')}>
          <dt aria-label={t('battle.projectilesAvailable')}>{STAT_SYMBOLS.projectiles}</dt>
          <dd>{availableProjectiles}</dd>
        </div>
        <div className="is-damage" title={t('battle.damage')}>
          <dt aria-label={t('battle.damage')}>{STAT_SYMBOLS.damage}</dt>
          <dd>{unit.type.damage}</dd>
        </div>
      </dl>
      <dl className="encounter-combatant__details">
        <div><dt>{t('battle.strength')}</dt><dd>{unit.currentStrength} / {unit.type.initialStrength}</dd></div>
        <div><dt>{t('battle.range')}</dt><dd>{unit.type.attackRange}</dd></div>
      </dl>
      {bonuses.length > 0 && (
        <section className="encounter-combatant__bonuses">
          <strong>{t('battle.combatBonuses')}</strong>
          <ul>
            {bonuses.map((bonus, index) => (
              <li className={`is-${bonus.stat}`} key={`${bonus.key}-${index}`}>
                <span aria-hidden="true">{STAT_SYMBOLS[bonus.stat] || '−'}</span>
                <span>{t(`battle.${bonus.key}`, { target: bonus.target })}</span>
                {bonus.value !== 0 && <b>{bonus.value > 0 ? `+${bonus.value}` : bonus.value}</b>}
              </li>
            ))}
          </ul>
        </section>
      )}
      <div className="encounter-combatant__morale">
        <div className="encounter-combatant__morale-heading">
          <span>{t('battle.morale')}</span>
          <strong>{morale}</strong>
        </div>
        <div className="morale-meter" aria-label={t('battle.moraleValue', { value: morale })}>
          <span style={{ width: `${moralePercent}%` }} />
        </div>
      </div>
    </article>
  );
}

export default function BattleEncounterModal({ attacker, attackerArmy, defender, defenderArmy, busy, attackType, result, automatic = false, onResolve, onClose }) {
  const { t } = useI18n();
  const onCloseRef = useRef(onClose);
  const [showCasualties, setShowCasualties] = useState(!automatic);

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    function closeOnEscape(event) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [onClose]);

  useEffect(() => {
    if (!result) return undefined;
    const timeoutId = window.setTimeout(
      () => onCloseRef.current(),
      RESULT_DISPLAY_MS + (automatic ? AUTOMATIC_CASUALTY_DELAY_MS : 0),
    );
    return () => window.clearTimeout(timeoutId);
  }, [automatic, result]);

  useEffect(() => {
    if (!result || !automatic) {
      setShowCasualties(Boolean(result));
      return undefined;
    }

    setShowCasualties(false);
    const timeoutId = window.setTimeout(() => setShowCasualties(true), AUTOMATIC_CASUALTY_DELAY_MS);
    return () => window.clearTimeout(timeoutId);
  }, [automatic, result]);

  if (!attacker || !attackerArmy || !defender || !defenderArmy) return null;
  const bonuses = combatBonuses(attacker, defender, defenderArmy, attackType, result);

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
        <p className="encounter-modal__description" id="encounter-description">
          {attackType === 'RANGED' ? t('battle.rangedEncounterDescription') : t('battle.encounterDescription')}
        </p>
        <div className="encounter-modal__combatants">
          <Combatant
            unit={attacker}
            army={attackerArmy}
            sideLabel={t('battle.attacker')}
            casualties={result && showCasualties ? result.attackerCasualties : undefined}
            bonuses={bonuses.attacker}
          />
          <div className="encounter-modal__versus" aria-hidden="true">{t('battle.versus')}</div>
          <Combatant
            unit={defender}
            army={defenderArmy}
            sideLabel={t('battle.defender')}
            casualties={result && showCasualties ? result.defenderCasualties : undefined}
            bonuses={bonuses.defender}
          />
        </div>
        {!automatic && (
          <footer aria-hidden={result ? 'true' : undefined} className={`encounter-modal__footer${result ? ' is-result' : ''}`}>
            <span>{t('battle.combatPending')}</span>
            <button autoFocus={!result} className="button button--primary" disabled={busy || Boolean(result)} onClick={onResolve} type="button">
              {busy ? t('battle.resolvingCombat') : t('battle.resolveCombat')}
            </button>
          </footer>
        )}
      </section>
    </div>
  );
}
