import { useI18n } from '../i18n/I18nContext';

export default function LanguageSwitcher() {
  const { language, setLanguage, t } = useI18n();

  return (
    <label className="language-switcher">
      <span>{t('app.language')}</span>
      <select value={language} onChange={(event) => setLanguage(event.target.value)}>
        <option value="es">Español</option>
        <option value="en">English</option>
      </select>
    </label>
  );
}
