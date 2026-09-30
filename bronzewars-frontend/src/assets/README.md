# Unit artwork

Menu and detail images use the pattern `<unit>_<design-number>.jpg`. Transparent
battlefield images use the same base name under `assets/units` with the `.png`
extension. Design `1` is the
Egyptian army and design `2` is the Assyrian army. The mapping from domain unit codes to image files lives in
`src/config/armyDesigns.js` so that new visual armies can be added without
changing the board components.

`mercenary.jpg` and `units/mercenary.png` are shared by every army because mercenaries are available to
all factions.

Artwork is displayed in rectangular 3:2 previews and 4:3 battlefield cells.
