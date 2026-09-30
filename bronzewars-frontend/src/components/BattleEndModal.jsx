import assyriaLogo from '../assets/nations/assyria.png';
import egyptLogo from '../assets/nations/egypt.png';
import { useI18n } from '../i18n/I18nContext';

const SUMMARY_GLYPHS = {
  initialForces: '\u{1301C}',
  casualties: '\u{13010}',
  prisoners: '\u{1300F}',
  fled: '\u{1301F}',
};

function nationLogo(faction) {
  return faction === 'ASSYRIAN' ? assyriaLogo : egyptLogo;
}

function nationNameKey(faction) {
  return faction === 'ASSYRIAN' ? 'armies.assyria.name' : 'armies.egypt.name';
}

function ArmyOutcome({ army, summary }) {
  const { t } = useI18n();
  if (!army || !summary) return null;

  return (
    <article className={`battle-end-army ${summary.winner ? 'is-winner' : 'is-defeated'}`}>
      <div className="battle-end-army__nation">
        <img src={nationLogo(army.faction)} alt={t(nationNameKey(army.faction))} />
        <div>
          <span>{t(nationNameKey(army.faction))}</span>
          <strong>{army.name}</strong>
        </div>
      </div>
      <dl className="battle-end-army__summary">
        {Object.entries(SUMMARY_GLYPHS).map(([key, glyph]) => (
          <div key={key}>
            <dt><span aria-hidden="true">{glyph}</span>{t(`battleEnd.${key}`)}</dt>
            <dd>{summary[key] ?? 0}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}

export default function BattleEndModal({ battle, onClose }) {
  const { t } = useI18n();
  const outcome = battle?.outcome;
  if (!outcome) return null;
  const humanArmy = battle.armies.find((army) => army.side === 'HUMAN');
  const aiArmy = battle.armies.find((army) => army.side === 'AI');
  const humanSummary = outcome.armies.find((army) => army.side === 'HUMAN');
  const aiSummary = outcome.armies.find((army) => army.side === 'AI');
  const victory = Boolean(humanSummary?.winner);

  return (
    <div className="battle-end-overlay" role="presentation">
      <section className={`battle-end-modal panel ${victory ? 'is-victory' : 'is-defeat'}`} role="dialog" aria-modal="true" aria-labelledby="battle-end-title">
        <header className="battle-end-modal__header">
          <p className="eyebrow">{t('battleEnd.battleFinished')}</p>
          <h2 id="battle-end-title">{t(victory ? 'battleEnd.victory' : 'battleEnd.defeat')}</h2>
          <span>{t(`battleEnd.reasons.${outcome.reason}`)}</span>
        </header>
        <div className="battle-end-modal__armies">
          <ArmyOutcome army={humanArmy} summary={humanSummary} />
          <ArmyOutcome army={aiArmy} summary={aiSummary} />
        </div>
        <footer className="battle-end-modal__footer">
          <button className="button button--primary" onClick={onClose} type="button">{t('battleEnd.returnToStart')}</button>
        </footer>
      </section>
    </div>
  );
}
