import { useEffect } from 'react';
import { useI18n } from '../i18n/I18nContext';
import LanguageSwitcher from './LanguageSwitcher';

const ITEMS = [
  { id: 'create', icon: '+', labelKey: 'navigation.createBattle' },
  { id: 'load', icon: '↗', labelKey: 'navigation.loadBattle' },
];

export default function AppNavigation({ activeView, open, onChange, onClose }) {
  const { t } = useI18n();

  useEffect(() => {
    if (!open) return undefined;
    const closeOnEscape = (event) => {
      if (event.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', closeOnEscape);
    return () => document.removeEventListener('keydown', closeOnEscape);
  }, [open, onClose]);

  return (
    <div
      className={`navigation-overlay ${open ? 'is-open' : ''}`}
      onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}
    >
    <aside className="app-navigation" aria-hidden={!open}>
      <div className="navigation-brand">
        <span className="brand-mark"><i>BW</i></span>
        <span className="navigation-brand__text">
          <strong>{t('app.title')}</strong>
          <small>{t('app.subtitle')}</small>
        </span>
      </div>

      <button className="navigation-close" type="button" onClick={onClose} aria-label={t('navigation.close')}>×</button>

      <nav className="navigation-items" aria-label={t('navigation.main')}>
        {ITEMS.map((item) => (
          <button
            className={`navigation-item ${activeView === item.id ? 'is-active' : ''}`}
            key={item.id}
            onClick={() => { onChange(item.id); onClose(); }}
            type="button"
          >
            <span className="navigation-item__icon" aria-hidden="true">{item.icon}</span>
            <span className="navigation-item__label">{t(item.labelKey)}</span>
          </button>
        ))}
      </nav>

      <div className="navigation-footer">
        <LanguageSwitcher />
        <small>InterSystems IRIS</small>
      </div>
    </aside>
    </div>
  );
}
