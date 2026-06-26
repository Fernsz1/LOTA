# Combat Feel Reference

> **Phase 0.3 — throwaway de-risking doc.** Every number here is a *starting
> point to tune*, not law. Feel is locked by playtest at the **3.6 GO/NO-GO**,
> not by this file. Its only jobs are: (1) give everyone a shared vocabulary, and
> (2) seed believable initial values so the first sample move (2.2) and the first
> two characters (Phase 3) don't start from a blank page.

Point any Claude/Codex session that builds or tunes something that *hits* at this
doc. Companion docs: `conventions.md` (how we work), the frame-data resource
format (Phase 2.2, once it exists), `fsm.md` (Phase 1.3).

All timing is in **frames at a fixed 60 Hz tick → 1 frame = 16.67 ms.** We never
express combat timing in seconds.

---

## 1. The one-paragraph north star

A 2D fighter *feels good* when **every hit reads as a physical event and every
input the player meant comes out.** Impact is sold by a brief freeze (hitstop), a
legible reaction (hitstun / knockdown), and the two bodies shoving apart
(pushback). Control feels *fair* when a slightly-early press still works (input
buffer) and when the numbers are consistent enough that players can learn and
trust them. We get all of this from the **data layer**, and sync animation on top
— never the reverse.

---

## 2. Why frame data matters (the project thesis)

This is the decision the whole plan leans on, restated as *feel*:

- **Precision lives in numbers, not drawings.** "Startup 6, +2 on block" is exact,
  loggable, and testable. "It looks fast" is not. Competitive trust comes from the
  former.
- **Determinism.** Same inputs → same combo, every time. A fighter that isn't
  deterministic isn't competitive. Frame data *is* that determinism.
- **Decoupling = we can prove fun before we draw.** Placeholder boxes that carry
  real frame data feel identical to final art. That is the entire reason Phase 3
  (boxes) → 3.6 (is it fun?) comes *before* Phase 5 (art). If feel lived in the
  animation, we couldn't validate it cheaply.
- **Balance is editing numbers, not re-rigging.** A matchup is tuned in the `.tres`,
  not in the Skeleton2D rig.
- **It's a shared language.** "−6 on block" tells every collaborator the same
  thing. The whole team can reason about a move without playing it.

> Corollary, pinned: **animation is cosmetic; the data hits.** If a drawing and its
> frame data disagree, the data wins and the art gets re-timed (that's the 5.4
> reconciliation job).

---

## 3. Frame vocabulary & our counting convention

A move occupies three **disjoint, back-to-back** spans (this is exactly what the
2.2 `.tres` will store as three counts):

```
 frame:  1   2   3   4   5   6   7   8   9  10  11 ...
         |--- startup ---|--- active --|------ recovery ------|
                          ^ hitbox live here only
```

- **Startup** — frames *before* the hitbox exists. Our convention: the **first
  active frame = `startup + 1`**.
- **Active** — frames the hitbox is live (the only frames a hit can occur).
- **Recovery** — frames after the hitbox is gone until the character is actionable.
- **Total move length = startup + active + recovery** (clean sum — no off-by-one
  because the spans don't overlap).

> **Bridge to outside frame data.** Community sources (Dustloop, SuperCombo) and
> players use **"iN" / "N-frame" notation = the first active frame.** So our
> `startup: 4` is what they call a **"5-frame" move.** When you copy a number off a
> Street Fighter / Guilty Gear wiki, subtract 1 to get our `startup`.

### Frame advantage (the number that defines whose turn it is)

After a move connects, whoever becomes actionable first has the **advantage**.

- **Plus (+)** = attacker recovers first → your pressure continues.
- **Minus (−)** = defender recovers first → they can punish with anything *faster*
  than your deficit. "−6" means a 6-frame-or-faster move punishes you for free.

Because hitstop freezes **both** characters equally, it cancels out and is ignored
for advantage math. Assuming the move lands on its **first** active frame:

```
on-block advantage ≈ blockstun − ((active − 1) + recovery)
on-hit  advantage ≈ hitstun  − ((active − 1) + recovery)
```

Tuning a move = choosing `recovery`, `blockstun`, and `hitstun` until these land
where you want. (Cancelable normals don't need positive *raw* on-hit — you cancel
into a special/another normal before recovery ever plays. See §4.)

---

## 4. Feel primitives (what each is, why it matters, target)

### Hitstop — the impact freeze
On contact, **freeze both characters** for a few frames, then resume. This is the
single biggest "it has weight" lever. Heavier hits = longer freeze.

- Apply hitstop **before** hitstun (freeze, *then* the defender enters stun).
- Hitstop is a **buffer-friendly window** — players queue the next input during it
  (combos feel reactable because of this). Keep buffering alive through hitstop.
- v1 simplification: **equal hitstop on hit and on block.** (Many games add 1–2
  extra on block to widen defensive reactions — note it as a knob, don't build it
  yet.)
- Projectiles: in our 2-box game, freeze both fighters; a projectile may keep
  travelling during hitstop or freeze with them — pick one and be consistent
  (default: it freezes too).

### Hitstun & blockstun — the reaction lock
How many frames the defender is locked after a hit (hitstun) or a block
(blockstun). **Hitstun > blockstun** for the same strength, so blocking trends the
exchange back toward neutral while hitting keeps your turn. For a combo to connect,
the next move's startup must fit inside the remaining hitstun.

### Pushback — the bodies separating
On hit and (more) on block, push the characters apart. **More pushback on block,
scaling slightly with button strength**, so a blocked string naturally spaces
itself out of range — this is the cheapest, most robust anti-infinite-blockstring
mechanic. Tune so a 3–4 hit blocked string ends just outside throw range.

### Input buffer & motion leniency — "the input I meant came out"
Poll inputs every physics frame into a **ring buffer** (the 1.2 system). Two
distinct leniencies sit on top of it:

- **Action buffer**: if the player presses up to **~4 frames** before they're
  actionable, the action fires the instant they can. This is what makes
  cancels/wake-up/links feel responsive instead of frame-perfect-or-nothing.
- **Motion leniency**: a directional motion (236, 623, …) is valid if its
  cardinals land within **~9 frames of each other** and the whole motion completes
  within **~16 frames**. Forgiving enough to be approachable, tight enough that
  motions stay meaningful (per the "deep engine, forgiving execution" decision).

Keep buffering active **during hitstop and the last few recovery frames** of a
move so combos confirm naturally.

### Smaller, still load-bearing
- **Jumpsquat**: ~**4** grounded, throwable frames before leaving the ground — jumps
  are a *commitment*, not instant escape.
- **Landing recovery**: ~**3** frames after a neutral jump (more after an air
  attack) so you can't act the instant you touch down.
- **Dash / backdash**: dash startup ~**3**; backdash gets ~**1–5** invuln frames
  then recovery — a real but punishable escape.
- **Throw tech window**: ~**5** frames to tech a normal throw. Command grabs are
  typically untechable (that's their reward).
- **Super flash / cinematic freeze**: a full-screen freeze (~**30–50** frames) on
  super/ultimate activation. Sells the moment and is a deliberate reactability
  knob (freeze = opponent *can* react; no-freeze = true).
- **KO slow-mo**: brief slowdown on the killing blow (the satisfying button). Lives
  in the 8.1 juice pass — just reserve the hook now.

---

## 5. Starting-point cheat sheet (plug these in, then tune at 3.6)

**Hitstop** (frames, hit & block equal in v1):

| Strength | Hitstop |
|---|---|
| Light | 8 |
| Medium | 10 |
| Heavy | 13 |
| Special | 12–14 |
| Super / Ultimate | 18–24 (+ optional 30–50 activation flash) |

**Hitstun / blockstun** (frames; hitstun > blockstun by design):

| Strength | Hitstun | Blockstun |
|---|---|---|
| Light | 13 | 9 |
| Medium | 17 | 13 |
| Heavy | 21 | 16 |
| Launcher | until landing → knockdown | 16 |

**Buffer & motion:**

| Knob | Target |
|---|---|
| Action buffer (press early → fires when actionable) | 4 frames |
| Motion cardinal gap (236 / 623) | ≤ 9 frames |
| Whole-motion window | ~16 frames |
| Ring-buffer retention (1.2) | ≥ 30 frames |
| Buffer during hitstop & last recovery frames | enabled |

**Movement:**

| Knob | Target |
|---|---|
| Jumpsquat (grounded, throwable) | 4 frames |
| Neutral-jump airtime | ~46 frames |
| Dash startup | 3 frames |
| Backdash invuln / total | 1–5 / ~20 frames |
| Landing recovery (no attack) | 3 frames |
| Throw startup / tech window | 5 / 5 frames |

---

## 6. Reference moves (ballpark targets, ~10)

Archetypal moves with believable frame data to anchor the first kits. These are
**reference points, not the locked movesets** (movesets lock at 3.6). Notation is
*our* convention (`start` = frames before first active). **On-block** is computed
from §3 using the §5 blockstun (light 9 / medium 13 / heavy 16), assuming a
first-active-frame hit. **On-hit** is given as a *category* — set hitstun to dial
the exact number.

| Move (archetype) | Start | Act | Rec | On blk | On hit | Role / why it exists |
|---|---|---|---|---|---|---|
| Light jab (st.LP) | 3 | 2 | 7 | **+1** | + (≈+5), combo starter | Fastest button; defines your fastest punish & pressure reset. Cancelable. |
| Light low (cr.LK) | 4 | 2 | 9 | **−1** | + (≈+3) | Low check; starts low hit-confirms. |
| Standing medium (st.MP) | 6 | 3 | 13 | **−2** | +, then cancel | Footsie/combo-filler button; special-cancel on confirm. |
| Crouch medium (cr.MK) | 7 | 3 | 15 | **−4** | cancel (≈0 raw) | Long low poke / whiff-punish; cancel into fireball (the classic). |
| Heavy (st.HP) | 10 | 4 | 19 | **−6** | combo / knockdown | Big reward, punishable on block. Combo ender. |
| Sweep (cr.HK) | 8 | 3 | 26 | **−12** | hard knockdown | Spacing + whiff-punish → okizeme. Very unsafe; respect it. |
| Anti-air DP (623, inv 1–5) | 4 | 8 | 30 | **−21** | launch → knockdown | Reversal/anti-air. Invincible startup, catastrophic recovery — the risk/reward anchor. |
| Overhead | 20 | 2 | 16 | **−4** | + (≈+1) | Must block high; the mix-up vs crouch-blockers. Slow enough to contest. |
| Projectile (236 — Rainne) | 13 | — | 32 | varies: ~−2 point-blank → ~+4 max range | knockdown / chip | Zoning core; advantage scales with distance (attacker recovers as the ball travels). **Built as a generic, reusable system in 3.2 (Rainne's zoning core).** |
| Command grab (632146) | 6 | 2 | 26 | n/a — unblockable; lose to jump/backdash | hard knockdown | Cracks turtles; beats block, loses to jump. Rushdown closer (Jerb); signature tool of the Buno grappler (Jacob, Phase 6). |
| Jump-in (j.HK) | 8 | 8 | (lands) | + on deep hit | + (≈+4…+8 by height) → combo | Air-to-ground starter; a deep hit buys a full ground combo. Enables offense. |

> Sanity check the archetype contrast (the 3.6 stress test): **Jerb** lives on
> jab / dash / command-grab / jump-in (fast, plus-frames, gets in). **Rainne**
> lives on projectile / long pokes / DP-style anti-air (keeps out, punishes the
> approach). If rushdown-vs-fireball isn't tense and fun with *these* numbers,
> tune the numbers — not the art.

---

## 7. What kills feel (avoid these)

- **Feel that lives in the animation.** If changing a drawing changes how a move
  hits, the data layer has been bypassed. Fix it — this breaks the whole pipeline.
- **No hitstop.** Hits feel like they pass through the opponent. Add the freeze
  before anything else "juice."
- **Zero buffer / frame-perfect-or-nothing.** Reads as "the game dropped my input."
  Tune the action buffer up before assuming a move is too hard.
- **Blockstun ≥ hitstun.** Makes blocking feel better than hitting — inverts the
  incentive. Hitstun must exceed blockstun.
- **Too little block pushback.** Lets blockstrings loop forever (infinite pressure).
  Pushback is the cheap fix.
- **Hitstop counted as hitstun.** Inflates combos and desyncs advantage math. Apply
  hitstop *then* hitstun; ignore hitstop in advantage.
- **Tuning by feel without reading the numbers.** Once 4.x training mode exists,
  read frame advantage off the HUD — don't guess.

---

## 8. Further reading (for shared vocabulary — not gospel on our exact numbers)

- **Infil's Fighting Game Glossary** (`glossary.infil.net`) — the canonical
  terminology reference; align our words to it.
- **Dustloop** (`dustloop.com`) — ArcSys/Guilty Gear frame data; good for seeing
  real startup/active/recovery/advantage tables (remember the −1 startup bridge).
- **SuperCombo Wiki** (`wiki.supercombo.gg`) — Street Fighter–family frame data.
- **Core-A Gaming** (YouTube) — design/feel essays on footsies, execution, and why
  depth and approachability aren't opposites (our engine thesis).
