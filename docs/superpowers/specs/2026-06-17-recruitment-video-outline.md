# Video Outline: Godot Action-Roguelike Recruitment Video

> Based on spec: [2026-06-17-recruitment-video-design.md](./2026-06-17-recruitment-video-design.md) | Target duration: 75-90s | Visual style: Screen recording + text overlays + meme inserts + voiceover (no camera)

## Core Concept
A 60-90 second recruitment video that opens with a 10-second explosion-meme montage (pure spectacle, no text), then uses text-narrated gameplay footage to explain the game, what's been built, and why creators should join — a hobby project offering real portfolio work and full creative credit.

## Target Audience
Indie-curious creators on Bilibili — primarily 2D artists, then game designers, then programmers, then sound designers/composers. No prior Godot experience required — just some creative skill to contribute and a desire to work on a real portfolio piece that isn't a 48-hour game jam throwaway. They understand and accept "unpaid hobby project."

## Act Structure Overview
The video has a **hook/cold-open bookend** and **three compact acts** that move from spectacle to substance to invitation:

- **Hook (0:00-0:10)** — Pure visual: explosion montage with meme overlays. Music only. No text, no VO.
- **Act 1: What Is This? (0:10-0:30)** — Text-narrated game intro. Each core mechanic gets one clip and one supporting text overlay.
- **Act 2: What's Been Built? (0:30-0:50)** — Tech credibility. GPU simulation, CSV weapon system, status reactions. Engine stats.
- **Act 3: Why Join? (0:50-1:15)** — Benefits for collaborators: portfolio piece, full credit, creative ownership. Brief role call.
- **CTA (1:15-1:30)** — Discord link, role summary card, final meme.

The energy arc: start at maximum (explosions) → dip slightly for explanation → rebuild with tech credibility → land on a human, honest invitation.

---

## Hook & Cold Open (0:00 - 0:10)

**Purpose:** Create immediate visual curiosity. Signal "this is not a typical Godot game" and "this video won't be boring." The meme overlays communicate "this is a fun project, not a corporate pitch."

**Visual direction:** A rapid montage of explosion footage from different in-game scenarios — gas ignition in a narrow tunnel, oil spreading across terrain and igniting, a chain reaction consuming a room, terrain collapsing from accumulated damage. Each explosion cut gets a different Bilibili-native meme reaction image overlaid for 1-2 seconds (brain galaxy, "this is fine" dog, Pikachu surprise face, wide-eyed cat, "omg" reaction face). The cuts are fast — 1.5-2 seconds each. The final explosion is the biggest, filling the screen.

**Audio/music direction:** High-energy background music only — no voiceover, no text, no narration. Music builds in intensity across the 10 seconds, peaking with the final explosion. When Act 1 begins, the music dips sharply to make space for voiceover.

**Key beat:** The third or fourth explosion, when the viewer realizes "wait, this isn't pre-scripted destruction — the terrain is actually being carved in real-time."

**Transition to Act 1:** Hard cut from the final explosion burst to the first gameplay clip of Act 1. Music dips. First voiceover line begins immediately — no pause, no title card. The energy carries through.

---

## Act 1: What Is This? (0:10 - 0:30)

**Purpose:** Answer the basic question in the viewer's mind after the hook: "Okay, what am I looking at?" Introduce the game concept through concrete mechanics shown on screen, not abstract description. Establish the unique selling point: fully destructible world with reacting elements.

**Act duration:** ~20 seconds (2 scenes of ~10s each)

### Scene 1.1: The Destructible World (0:10 - 0:20)
- **Purpose:** Show that terrain is not static — the player carves through the world and that carving IS the gameplay.
- **Key talking points:**
  - The entire world is destructible — every pixel of terrain
  - Melee swings carve through walls, creating new paths and sightlines
  - Terrain destruction is real-time, GPU-simulated
- **Visual direction:** Screen recording of a melee weapon swing carving a wide arc through terrain. Show the before/after contrast clearly — thick wall → tunnel. Then show a rapid series of terrain carving in different contexts (narrow tunnel widening, creating a shortcut, collapsing a wall onto enemies).
- **Notes:** The first clip of this scene is the first thing the viewer sees after the explosion montage. It must immediately show terrain being carved — no menus, no loading screens, no character idle.

### Scene 1.2: The Living Elements (0:20 - 0:30)
- **Purpose:** Show that the world doesn't just break — it reacts. Gas, fluids, fire, and status effects chain together in emergent ways.
- **Key talking points:**
  - Gas and fluids flow and pool through the tunnels you dig
  - Elements chain-react: fire ignites gas, water douses fire, oil spreads flame
  - A data-driven status system handles cross-reactions (fire, wet, oil, poison) shared between player and enemies
- **Visual direction:** A single clean sequence: player carves a wall → gas seeps through the new opening → a spark ignites it → fire races back through the tunnel → it hits an oil patch → oil fire spreads. Show status icons appearing on enemies caught in the chain. Each interaction should be clearly visible and sequential. Text overlays appear alongside each mechanic: "REAL GAS FLOW," "CHAIN REACTIONS," "STATUS COMBOS."
- **Notes:** This is the most important gameplay sequence in the video. It demonstrates the central mechanic that differentiates this project from every other Godot game on Bilibili. Make sure the gas flow and fire propagation are clearly visible against the terrain.

**Transition to Act 2:** Voiceover shifts tone — from "here's what it does" to "here's how it works." Visual shifts from pure gameplay to a wider shot that might include a brief glance at CSV data or the status matrix. A subtle meme overlay (e.g., a data/nerd emoji or "WTF" face) bridges the shift from spectacle to tech.

---

## Act 2: What's Been Built? (0:30 - 0:50)

**Purpose:** Establish technical credibility. The viewer has seen the spectacle — now they need to know this is a real project with real engineering behind it, not a tech demo with smoke and mirrors. This is the "trust" act that makes the recruitment in Act 3 believable.

**Act duration:** ~20 seconds (2 scenes of ~10s each)

### Scene 2.1: The Engine (0:30 - 0:40)
- **Purpose:** Show the depth of the simulation layer. Prove this isn't a Unity asset flip.
- **Key talking points:**
  - Custom compute-shader terrain + gas simulation running on the GPU
  - Chunked cellular grid (256-cell chunks) with per-frame probe budget
  - Gas/fluid propagation through dug geometry
- **Visual direction:** Screen recording of a debug view if available — show the chunk grid, gas density visualization, or probe footprints overlaid on terrain. If no debug view exists, show rapid terrain carving in multiple directions while gas propagates through all openings simultaneously. Text overlay: "GPU COMPUTE SHADER SIMULATION" and "REAL-TIME FLUID PROPAGATION."
- **Notes:** This scene targets the programmer/tech-curious viewer specifically, but the visuals should still be understandable to artists — show the simulation's scale, not just abstract numbers.

### Scene 2.2: The Systems (0:40 - 0:50)
- **Purpose:** Show that the game has working combat, weapons, and content infrastructure — not just a physics sandbox.
- **Key talking points:**
  - Weapons and modifiers defined in CSV with a 3-slot build/synergy system
  - Data-driven status effect system with cross-reactions
  - ~17k lines of GDScript, unit tests around simulation and status layers
  - Working combat feel, enemy AI, and run loop
- **Visual direction:** Quick cuts: CSV weapon table (2s) → weapon swap UI showing modifier slots (2s) → combat sequence showing a weapon with modifiers active (3s) → status reaction matrix or enemy with multiple statuses (2s). Text overlays: "DATA-DRIVEN WEAPONS," "3 MODIFIER SLOTS PER WEAPON," "17K LINES GDScript."
- **Notes:** Keep the CSV/technical shots brief — they're credibility markers, not the focus. The combat clip anchors this scene.

**Transition to Act 3:** Hard pivot in tone and visual. After the tech credibility peak, the voiceover shifts to a more personal, honest register. Visual cuts from combat/CSV to a wider shot of the game with all its placeholder art clearly visible. A meme overlay that contrasts "powerful engine" with "placeholder art" — e.g., a "before/after" style split, or a "we have [badass game] at home" meme format.

---

## Act 3: Why Join? (0:50 - 1:15)

**Purpose:** Make the ask. Sell the benefit of joining — not the project's needs, but what the collaborator gains. Keep it honest about scope (hobby project, unpaid) while making the creative opportunity clear.

**Act duration:** ~25 seconds (2 scenes of ~12s each)

### Scene 3.1: The Canvas (0:50 - 1:02)
- **Purpose:** Show that the project is a blank canvas for artists and creators. Frame the placeholder art as creative opportunity, not a shortcoming.
- **Key talking points:**
  - Every visual in the game is open-source placeholder — characters, terrain, weapons, VFX, UI
  - This means your work IS the visual identity of the game
  - You get a real, shippable portfolio piece — not a game jam throwaway
  - Full creative credit and ownership over your domain
  - No AI-generated assets — real human craft only
- **Visual direction:** A slow pan or series of close-up cuts showing placeholder art elements (character sprite, terrain tiles, weapon icon, UI panel) with text overlays pointing to each: "YOUR ART HERE," "YOUR VFX HERE," "YOUR UI HERE." Then a quick montage showing the contrast — placeholder art in its current context, with the physics engine doing something impressive behind it. The visual message: the engine is real, the canvas is blank. Meme overlay: a "drawing on blank canvas" style reaction or a "potential" meme.
- **Notes:** This is the most important scene for the primary audience (artists). The tone must communicate "this is an opportunity" not "we're desperate." Show the scale of creative ownership — an artist would define the entire visual direction, not just make assets to spec.

### Scene 3.2: The Roles (1:02 - 1:15)
- **Purpose:** Clearly state what roles are open and what each person would own. Keep it brief — one line per role.
- **Key talking points:**
  - 2D Artists: characters, enemies, weapons, terrain tilesets, VFX, UI — define the entire visual identity
  - Game Designers: combat encounters, weapon x modifier build system, level/biome pacing, run economy
  - Programmers (GDScript/Godot): gameplay systems, enemy AI, content tooling, UI; bonus for compute-shader interest
  - Sound Designers/Composers: SFX (swings, terrain carving, gas ignition, explosions), ambient/dynamic soundtrack — no audio exists yet
  - Unpaid hobby project — everyone is credited, you keep shippable work for your reel
- **Visual direction:** For each role, a brief visual that shows what they'd work on. Artist: placeholder sprites with an overlay saying "Your characters here." Designer: the modifier slot UI or weapon data table. Programmer: a brief glimpse of code or the debug simulation view. Sound: an audio waveform flatline or "NO AUDIO YET" text card, followed by gameplay footage with silence to make the absence felt. Each role gets 2-3 seconds of visual. End with a text card summarizing all roles.
- **Notes:** Keep the language inviting, not demanding. "Open to any commitment level" should be stated or implied. The tone should feel like "come make cool stuff" not "we have requirements to fill."

**Transition to CTA:** The role summary fades or transitions into the CTA card. Music intensity rises slightly — not to the level of the hook, but enough to signal forward momentum toward action.

---

## CTA & Closing (1:15 - 1:30)

**Purpose:** Give the viewer a concrete next action. End on a positive, memorable note that makes them want to reach out.

**Call to action:** Join the Discord server (link displayed on screen). Direct invitation to DM or join the server to ask questions, see the repo, or claim a role. Also: the game's name is undecided — drop suggestions in the comments.

**Closing beat:** A final meme overlay that's warm/inviting rather than high-energy — e.g., a "come build with us" or "your move" style reaction. The emotional note should be "this could be fun, why not?" rather than "WE NEED YOU."

**Visual direction:** A clean end card showing: "Name TBD — suggest in comments!", "Looking for collaborators" text, Discord link/QR code, and the four role icons. The final meme appears over this card for 2-3 seconds before fade. Background is a slowed-down gameplay clip or a particularly beautiful explosion/fire propagation shot.

**Audio direction:** Music resolves with a final beat or chord. Voiceover delivers the last line and stops. 1-2 seconds of ambient game audio under the end card before total fade.

---

## Duration Budget

| Section      | Target Duration | Notes |
|------------- |-----------------|-------|
| Hook         | 0:00 - 0:10     | 10s, music only |
| Act 1        | 0:10 - 0:30     | 20s, two 10s scenes |
| Act 2        | 0:30 - 0:50     | 20s, two 10s scenes |
| Act 3        | 0:50 - 1:15     | 25s, two ~12s scenes |
| CTA          | 1:15 - 1:30     | 15s |
| **Total**    | **1:30**        | Matches spec target (75-90s range, 90s max) |

## Differentiation Check

1. **"Recruitment as reverse devlog":** Delivered by the hook — no talking head, no preamble, straight into explosions. Scene 1.1 and 1.2 front-load gameplay before any recruitment messaging appears. This is the opposite of every existing Bilibili recruitment video.

2. **Placeholder art as opportunity:** Delivered by Scene 3.1 — explicit framing of placeholder art as "your canvas," with text overlays pointing to specific plug-in points. No apology, no defensiveness. No existing Bilibili recruitment video uses this angle.

3. **Godot + physics = category creation:** Delivered by the entire Act 1 + Act 2 sequence — the terrain carving and gas/fluid propagation are unique Godot content on Bilibili. The CSV/tech credibility in Scene 2.2 adds legitimacy without being the focus.

4. **Meme texture vs. corporate feel:** Delivered by the hook's meme overlays, the Act 2→Act 3 transition meme, and the closing meme. The video reads as "fun project" throughout, not "startup pitch."

5. **Honest about scope:** Delivered by Scene 3.2 — explicit "unpaid hobby project" language. This filters mismatched expectations before anyone joins the Discord.

## Open Questions

- Discord server link — needs to exist before the video is published. Mentioned in the recruitment kit but not yet confirmed.
- Availability of debug visualization footage for Scene 2.1 — if no debug overlay exists for gas density or chunk grid, will need to substitute with pure gameplay footage showing simultaneous multi-direction gas propagation.
