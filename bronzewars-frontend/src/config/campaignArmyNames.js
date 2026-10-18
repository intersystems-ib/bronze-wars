// Repertoires span the history of each civilization, rather than individual reigns.
// Names are chosen once at recruitment and persisted as ordinary army names.
export const CAMPAIGN_ARMY_NAMES = {
  seapeople: [
    { es: 'los Shardana', en: 'the Sherden' }, { es: 'los Peleset', en: 'the Peleset' },
    { es: 'los Tjekker', en: 'the Tjekker' }, { es: 'los Denyen', en: 'the Denyen' },
    { es: 'los Shekelesh', en: 'the Shekelesh' }, { es: 'los Weshesh', en: 'the Weshesh' },
  ],
  egypt: [
    { es: 'Ra', en: 'Ra' }, { es: 'Ramsés', en: 'Ramesses' },
    { es: 'Amón', en: 'Amun' }, { es: 'Horus', en: 'Horus' },
    { es: 'Osiris', en: 'Osiris' }, { es: 'Isis', en: 'Isis' },
    { es: 'Ptah', en: 'Ptah' }, { es: 'Sekhmet', en: 'Sekhmet' },
    { es: 'Seti', en: 'Seti' }, { es: 'Tutmosis', en: 'Thutmose' },
    { es: 'Ahmose', en: 'Ahmose' }, { es: 'Hatshepsut', en: 'Hatshepsut' },
  ],
  hatti: [
    { es: 'Tarhunna', en: 'Tarhunna' }, { es: 'Telepinu', en: 'Telepinu' },
    { es: 'Arinna', en: 'Arinna' }, { es: 'Teshub', en: 'Teshub' },
    { es: 'Hattusili', en: 'Hattusili' }, { es: 'Mursili', en: 'Mursili' },
    { es: 'Suppiluliuma', en: 'Suppiluliuma' }, { es: 'Muwatalli', en: 'Muwatalli' },
    { es: 'Tudhaliya', en: 'Tudhaliya' }, { es: 'Puduhepa', en: 'Puduhepa' },
  ],
  nubia: [
    { es: 'Apedemak', en: 'Apedemak' }, { es: 'Amón', en: 'Amun' },
    { es: 'Dedun', en: 'Dedun' }, { es: 'Amesemi', en: 'Amesemi' },
    { es: 'Piye', en: 'Piye' }, { es: 'Taharqa', en: 'Taharqa' },
    { es: 'Amanirenas', en: 'Amanirenas' }, { es: 'Shabaka', en: 'Shabaka' },
  ],
};

const formats = { es: (name) => `Ejército de ${name}`, en: (name) => `Army of ${name}` };

export function randomArmyName(nation, armies = [], { language = 'es', random = Math.random } = {}) {
  const repertoire = CAMPAIGN_ARMY_NAMES[nation];
  if (!repertoire) throw new Error('UNKNOWN_ARMY_NAME_NATION');
  const locale = language.startsWith('en') ? 'en' : 'es';
  const used = new Set(armies.filter((army) => army.designId === nation).map((army) => army.name?.trim()));
  // Recognize both languages, including when the UI language changes mid-campaign.
  for (let suffix = 1; ; suffix += 1) {
    const candidates = repertoire.filter((entry) => !Object.entries(formats).some(([key, format]) =>
      used.has(`${format(entry[key])}${suffix === 1 ? '' : ` (${suffix})`}`)));
    if (!candidates.length) continue;
    const entry = candidates[Math.floor(random() * candidates.length)];
    return `${formats[locale](entry[locale])}${suffix === 1 ? '' : ` (${suffix})`}`;
  }
}
