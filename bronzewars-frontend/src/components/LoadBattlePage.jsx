import { useState } from 'react';
import { useI18n } from '../i18n/I18nContext';

export default function LoadBattlePage({ busy, onResume }) {
  const { t } = useI18n();
  const [battleId, setBattleId] = useState('');

  function submit(event) {
    event.preventDefault();
    if (battleId.trim()) onResume(battleId.trim());
  }

  return (
    <main className="start-page start-page--compact">
      <section className="start-card panel">
        <p className="eyebrow">{t('load.eyebrow')}</p>
        <h1>{t('load.title')}</h1>
        <p className="lede">{t('load.description')}</p>

        <form className="load-battle-form" onSubmit={submit}>
          <label className="field">
            <span>{t('setup.battleId')}</span>
            <input
              autoFocus
              inputMode="numeric"
              value={battleId}
              onChange={(event) => setBattleId(event.target.value)}
              placeholder={t('load.idPlaceholder')}
            />
          </label>
          <button className="button button--primary" disabled={busy || !battleId.trim()} type="submit">
            {busy ? t('load.loading') : t('setup.resume')}
          </button>
        </form>
      </section>
    </main>
  );
}
