# Changelog

## 1.0.2

- `/tbar wilhelm` toggles the pull scream (on by default). `/tbar wilhelm test` plays it. `/threatbar scream` still works.

## 1.0.1

- Wilhelm scream (`wilhelm.ogg`) when you are about to pull aggro off another player or pet (`threat status == 1`, targettarget is a player/pet, you are not tanking)
- Does not play when you already have aggro (soloing or tanking)
- `/threatbar scream` toggle, `/threatbar scream test`

## 1.0.0

- Player-only threat data bar for WoW Forever (`Interface 16001`)
- Movable and resizable; park it on the cast bar
- Threat status colours (`GetThreatStatusColor`); fill is your % on the current target
- EllesmereUI third-party skin for chrome; fill matches the player cast bar texture
- Combat-only when locked (default); `/threatbar test` for out-of-combat placement
