# Unit artwork

Menu and detail images use the pattern `<unit>_<nation>.jpg`. Transparent
battlefield images use the same base name under `assets/units` with the `.png`
extension. The suffix `_egypt` identifies the Egyptian army and `_hatti` identifies
the Hittite army. Use a named nation suffix for additional armies. The mapping from domain unit codes to image files lives in
`src/config/armyDesigns.js` so that new visual armies can be added without
changing the board components.

`pikeman_seapeople.jpg` and `units/pikeman_seapeople.png` depict Sea Peoples
spearmen. They remain mapped to the `MERCENARIES` domain unit code for existing
battles. Mercenaries are excluded from troop selection when creating an army.

Artwork is displayed in rectangular 3:2 previews and 4:3 battlefield cells.

Nubia (`_nubia`) has archers, light infantry and spearmen. The Sea Peoples
(`_seapeople`) also have heavy infantry. Their nation logos are in `nations`.
Only the matching troop types are offered in army creation. Both factions use
the existing domain unit codes and inherit their combat matchup modifiers.
