import { getUnitArtwork, getUnitArtworkForFaction } from '../config/armyDesigns';

export default function UnitArtwork({ unitCode, armyDesignId, faction, className = '', alt = '', loading = 'lazy' }) {
  const source = faction
    ? getUnitArtworkForFaction(unitCode, faction)
    : getUnitArtwork(unitCode, armyDesignId);

  if (!source) return null;

  return (
    <img
      alt={alt}
      className={`unit-artwork ${className}`.trim()}
      draggable="false"
      loading={loading}
      src={source}
    />
  );
}
