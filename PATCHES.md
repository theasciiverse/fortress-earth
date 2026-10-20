# Changes in this fork

Fortress Earth is Filip Hracek's keyboard-only grand strategy game on a
map of the whole Earth (github.com/filiph/fortress-earth, MIT, 2019 to
2025), written in Dart for the browser with Bob Nystrom's malison. Its
upstream is a tech demo and is not maintained. This fork makes it a game
and runs it in a text terminal, for the Asciiverse catalog.

His simulation is unchanged: armies spreading over the land like a
cellular automaton, fighting for tiles, units flowing to where they are
needed.

## The game

- `lib/src/campaign.dart` runs a war around the simulation. Ten landings
  come down at shrinking intervals, each 5 to 12 tiles from a city, on
  land connected to a city. Cities show OK, THREAT or LOST. The war is
  lost with six cities in enemy hands at once or every army destroyed,
  and won when all ten landings are gone: destroyed, starved out by a
  siege once they stop producing, or down to a few stragglers.
- Armies get recruits back each day; an army overrun regroups 30 days
  later. The chat panel carries the generals' reports. An end screen
  starts a new war; F1, ? or H shows how to play.
- Armies and cities are new for every war (they were shared), tile
  updates per tick scale with the map, and all random numbers come from
  one generator that `--seed` can set.
- `lib/src/autopilot.dart` is a simple commander for `--demo` and for
  `tool/balance.dart`, which plays wars without a screen to tune the
  numbers.

## The map

Terminal cells are about twice as tall as wide, the browser's 10x14
pixels. The map is regenerated at 186x43 (was 130x43) with
`tool/parse_map.dart` from the same Natural Earth rasters (public
domain, naturalearthdata.com, now served from
naciscdn.org/naturalearth/10m/raster/), so the Earth keeps its shape;
cities and starting positions are scaled to match. The tool printed
colours in the wrong form since the null-safety migration; fixed, it
reproduces the original map byte for byte.

## The terminal build

Everything for the terminal is in `tty/`, a Dart package of its own:

- `tty/malison/`: malison 0.14.0 (Nystrom, MIT) with the canvas terminals
  removed; the screen stack takes keys and frames from its host.
- `tty/howler_stub/`: a silent stand-in for `package:howler`, which is
  browser only. The original's sound (off by default there) is not
  shipped; its music and clicks carry no licence in the repository.
- `tty/lib/`: a 24-bit colour renderer that sends only changed cells, a
  key decoder, Windows console set-up, the quit question, and the
  `--preview` view (the reports panel and a window of the map that cuts
  to the war, 100x30, for the catalog preview).
- `tty/bin/fortress_earth.dart`: the program. The 186x55 screen is drawn
  centred; a smaller terminal gets a message until it is big enough.
  Options: `--demo`, `--preview`, `--seed N`, `--quit-after SECONDS`.

Build: `cd tty && dart pub get && dart compile exe bin/fortress_earth.dart
-o build/fortress-earth`.

`.github/workflows/release.yml` builds the catalog archives, with
`tty/tool/licenses.dart` gathering the licences of everything compiled in
into THIRD-PARTY-LICENSES.txt. `asciiverse/record-preview.sh` records
`asciiverse/fortress-earth.cast`, the catalog preview: `--demo --preview`
at 100x30, seed 1, 55 seconds.
