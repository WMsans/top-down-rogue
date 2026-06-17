# Recruitment Kit

Packaging for the collaborator-recruitment push. Model: **hobby / portfolio** (unpaid,
credited, shippable portfolio work). Target venues: **UCI VGDC**, **CMU game dev
community**, and **r/godot** (low-stakes test run, anytime).

---

## Timing

Recorded June 2026. Recruit at the start of the academic term, when clubs form teams:

- **r/godot** — post whenever the video is ready (summer is fine; treat it as a test run
  to see how the demo reads to strangers).
- **UCI VGDC** — post at the start of a quarter (late Sep / early Jan / late Mar). Show up
  in their Discord, not just a one-off post.
- **CMU** — post at the start of a semester (late Aug / mid Jan).

Use the summer to **package**, not to build more game: record the video, set up the
Discord/landing point, and finalize the two intros below.

---

## The video (60–90s, gameplay-first)

1. **First 10s — the hook, no preamble.** Lead straight with the gas sim doing something
   dramatic. No logo, no "hi I'm…", no setup.
2. **20–40s — the emergent loop.** Dig terrain → gas flows/pools → status reaction →
   enemy combat feedback. Show that the *systems interact*. This is the differentiator vs.
   every other top-down roguelike.
3. **The honest ask.** "This is a solo Godot prototype. The core sim works; it needs
   content, art, sound, and more hands to become a real roguelike."
4. **Logistics on screen.** Unpaid passion project · everyone is credited · you keep and
   can showcase your own contributions · solo lead / open to contributors.
5. **One CTA** — the Discord/form link, on screen and in the description.

**Do:** keep placeholder art (it shows artists where their work plugs in).
**Don't:** over-explain the 3-year roadmap, or apologize for the art.

---

## Roles I'm looking for

> Solo-built Godot 4.6 action-roguelike prototype with a working GPU-simulated, fully
> destructible terrain + gas/fluid engine. The core mechanic is done; it needs content and
> craft to become a real game. Unpaid passion / portfolio project — everyone is credited,
> and you keep shippable work for your reel.

- **Designers** — combat encounters, the weapon × modifier build system (3 modifier slots
  per weapon, Noita-style synergy), level/biome pacing, run economy.
- **2D artists** — characters, enemies, weapons, terrain tilesets, VFX, UI. Everything is
  open-source placeholder right now, so there's a clean slate and clear plug-in points.
- **Sound designers / composers** — no audio yet: SFX for swings, terrain carving, gas
  ignition/explosions, plus an ambient/dynamic soundtrack.
- **Programmers (GDScript / Godot)** — gameplay systems, enemy AI/behaviors, content
  tooling, UI; bonus for anyone interested in the compute-shader simulation layer.

---

## Intro A — UCI VGDC (team-join framing)

> **[Recruiting] Solo Godot roguelike with a real pixel-physics engine — looking to build a small team**
>
> Hey VGDC! I've been solo-building a top-down action roguelike in Godot 4.6. The hook:
> the whole world is **fully destructible and simulated** — you carve through terrain with
> melee swings, gases and fluids flow and pool through the tunnels you dig, and elements
> chain-react (fire ignites gas, water douses it, oil spreads it). Think Noita's chaos with
> Soul Knight's melee pacing.
>
> The core simulation, status-effect reactions, and combat feel are working. What it needs
> now is a **team to turn a strong prototype into an actual game**: more weapons/modifiers,
> art, sound, enemies, and level design.
>
> This is an unpaid passion project, but everyone's credited and you walk away with a real,
> shippable portfolio piece — not a Game Jam throwaway. Looking for designers, 2D artists,
> sound designers, and Godot programmers. Open to any commitment level.
>
> [video link] · Questions or want in? → [Discord link]

---

## Intro B — CMU (tech-forward framing)

> **[Recruiting] Looking for collaborators on a Godot roguelike built on a GPU-simulated destructible world**
>
> I've been building a top-down action roguelike in Godot 4.6 around a custom
> **compute-shader terrain + gas simulation**. The world is a chunked cellular grid
> (256-cell chunks, GPU compute dispatch with a per-frame probe budget); melee swings inject
> velocity into the gas field and carve the terrain, fluids and gases propagate through the
> dug geometry, and a data-driven status system handles cross-reactions (fire / wet / oil /
> poison, etc.) shared between the player and enemies.
>
> Content is data-driven too — weapons and modifiers are defined in CSV with a 3-slot
> build/synergy system, and there's already a localization pipeline. ~17k lines of GDScript,
> with unit tests around the simulation and status layers.
>
> The engine and combat feel are solid; it now needs game *content* and *craft*. I'm looking
> for collaborators: gameplay/systems programmers (bonus if the compute-sim layer interests
> you), designers, 2D artists, and sound designers. Unpaid/portfolio, fully credited.
>
> [video link] · Repo/demo details → [Discord link]

---

## Before posting — checklist

- [ ] 60–90s video recorded with one reliably reproducible "wow" moment
- [ ] Landing point set up (Discord server or Google Form) and linked everywhere
- [ ] IP/ownership note written once, plainly (lead = maintainer; contributors keep/showcase
      their own work)
- [ ] Fill in `[video link]` and `[Discord link]` placeholders above
- [ ] r/godot test post done before the student-term push
