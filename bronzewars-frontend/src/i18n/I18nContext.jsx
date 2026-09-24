import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import en from '../locales/en.json';
import es from '../locales/es.json';

const dictionaries = { es, en };
const I18nContext = createContext(null);

function readPath(dictionary, path) {
  return path.split('.').reduce((value, key) => value?.[key], dictionary);
}

function interpolate(message, values = {}) {
  return message.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? `{{${key}}}`);
}

export function I18nProvider({ children }) {
  const browserLanguage = navigator.language?.toLowerCase().startsWith('en') ? 'en' : 'es';
  const [language, setLanguageState] = useState(() => localStorage.getItem('bronzewars.language') || browserLanguage);

  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);

  const value = useMemo(() => ({
    language,
    setLanguage(nextLanguage) {
      if (!dictionaries[nextLanguage]) return;
      localStorage.setItem('bronzewars.language', nextLanguage);
      document.documentElement.lang = nextLanguage;
      setLanguageState(nextLanguage);
    },
    t(key, values) {
      const message = readPath(dictionaries[language], key) ?? readPath(dictionaries.es, key) ?? key;
      return typeof message === 'string' ? interpolate(message, values) : key;
    },
  }), [language]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const context = useContext(I18nContext);
  if (!context) throw new Error('useI18n must be used inside I18nProvider');
  return context;
}
