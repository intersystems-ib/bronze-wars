import {
  getBattlefieldUnitArtwork,
  getBattlefieldUnitArtworkForFaction,
  getUnitArtwork,
  getUnitArtworkForFaction,
} from '../config/armyDesigns';

export default function UnitArtwork({ unitCode, armyDesignId, faction, variant = 'menu', className = '', alt = '', loading = 'lazy' }) {
  const battlefield = variant === 'battlefield';
  const source = faction
    ? (battlefield ? getBattlefieldUnitArtworkForFaction(unitCode, faction) : getUnitArtworkForFaction(unitCode, faction))
    : (battlefield ? getBattlefieldUnitArtwork(unitCode, armyDesignId) : getUnitArtwork(unitCode, armyDesignId));

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
