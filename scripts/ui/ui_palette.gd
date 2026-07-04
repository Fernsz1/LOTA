class_name UIPalette
## Brand palette for the "Legends of The Archipelago" menus (sunset-island look).
## art/ui/lota_theme.tres hardcodes the same values — keep the two in sync.
## Consumers should `const Palette := preload(...)` this file rather than use the
## bare class_name, so isolated --script test runs keep working (see docs).

const INK := Color("0b0d12")
const DUSK_PURPLE := Color("1b1230")
const DUSK_MAGENTA := Color("3a1e3a")
const HORIZON_AMBER := Color("e8842c")
const SEA_EMBER := Color("5a2e18")
const GOLD := Color("ffd95e")
const GOLD_DIM := Color("8a6a2f")
const PARCHMENT := Color("ede3ce")
const HINT_MUTED := Color("9a8f7a")
const P1_BLUE := Color("4da6ff")
const P2_RED := Color("ff5a5a")
