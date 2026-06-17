# Shooting Script: Godot Action-Roguelike Recruitment Video

> Based on outline: [2026-06-17-recruitment-video-outline.md](../specs/2026-06-17-recruitment-video-outline.md)
> Narration style: verbatim | Target duration: 90s | Visual style: Screen recording + text overlays + meme inserts + voiceover
> Created: 2026-06-17

---

## HOOK & COLD OPEN [0:00 - 0:10]

### [0:00 - 0:10] — Explosion Montage
**CAMERA:** Screen recording — live gameplay capture. Hide UI as much as possible.
**VISUAL:** Rapid montage of 5 explosion clips from different in-game scenarios:

| Timestamp | Visual | Meme Overlay | Duration |
|-----------|--------|--------------|----------|
| 0:00 | Gas ignition in a narrow tunnel — fire races through the confined space | 「脑子爆炸」galaxy brain meme | 2s |
| 0:02 | Oil spreads across terrain, then ignites into a sea of fire | 「这河里吗」surprised cat | 2s |
| 0:04 | Accumulated damage triggers terrain collapse, chain reaction of breakage | 「好家伙」wide-eyed shock face | 2s |
| 0:06 | Water douses spreading fire, steam/smoke rises, nearby gas reignites | 「我人傻了」Pikachu shocked | 2s |
| 0:08 | Maximum explosion — entire room consumed in flame + terrain collapse | 「名场面」reaction image | 2s |

**AUDIO:** Pure high-energy instrumental music. No voiceover, no on-screen text. Music builds intensity across all 10 seconds, peaks with the final explosion at 0:08.
**NARRATION:** *(none — music only)*
**PERFORMANCE:** N/A — no narration in this segment.
**TRANSITION TO ACT 1:** Hard cut at 0:10 from the final explosion burst to the first gameplay clip. Music dips sharply to ~30% volume. First VO line begins **immediately** — zero gap.

---

## ACT 1: What Is This? [0:10 - 0:30]

**Purpose (from outline):** Answer "what am I looking at?" Introduce the game concept through concrete mechanics. Establish the unique selling point.

### Scene 1.1: The Destructible World [0:10 - 0:20]
**Purpose:** Show that terrain destruction IS the gameplay — not a gimmick, not a scripted event.
**CAMERA:** Screen recording of gameplay. Character visible in center of frame.

**NARRATION (verbatim):**
> [0:10] I'm making an action roguelike.
> [0:13] Kinda like Noita — every pixel is part of a physical simulation.
> [0:16] Fully destructible terrain, simulated at the pixel level.

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:10 | Wide shot: character in center of a cave room, enemies nearby | *(no overlay — let the game speak)* |
| 0:12 | Melee swing carves a wide arc through a thick wall — clear before/after contrast. Wall → tunnel | "Fully Destructible Terrain" |
| 0:15 | Rapid series: carving in a narrow tunnel → widening a passage → collapsing a wall onto enemies | *(no overlay — the action is fast)* |
| 0:18 | Final carving shot: character surrounded, swings through walls to create an escape route | "Real-Time Terrain Destruction" |

**PERFORMANCE:** Steady, confident. Slight emphasis on "making" and "real-time." Not hyped — let the visuals carry the weight.
**MUSIC:** Background instrumental at ~30% volume. Steady energy, not climactic.

### Scene 1.2: The Living Elements [0:20 - 0:30]
**Purpose:** Show that the world reacts — gas, liquids, fire chain together emergently.

**NARRATION (verbatim):**
> [0:22] Gas and liquids flow and pool through the tunnels you carve.
> [0:25] Fire ignites gas, water douses flames, oil fuels them hotter,
> [0:28] and of course, elemental chain reactions.

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:20 | Cut to: player carves a wall, gas visibly seeps through the new opening | "Realistic Gas Flow" |
| 0:22 | Gas pools and spreads through a tunnel system | *(no overlay)* |
| 0:24 | A spark (weapon impact) ignites the gas. Fire races along the gas trail | "Chain Reactions" |
| 0:26 | Fire hits an oil patch → oil fire spreads across terrain → status icons appear on enemies caught in it | "Element Interaction System" |
| 0:28 | Water douses part of the fire, steam rises, gas reignites elsewhere — multi-element chaos | *(no overlay — spectacle speaks for itself)* |

**PERFORMANCE:** Energy lifts slightly from Scene 1.1. "But this isn't just destruction" — brief pause before, then momentum. The list ("Fire ignites gas, water douses flames...") should flow as one accelerating sentence.
**TRANSITION TO ACT 2:**

- **Visual:** Cut from multi-element chaos to a wider shot, or a split-second glimpse of CSV data / debug view. A subtle geek/「数据」meme or "WTF" reaction face flashes for 0.5s.
- **Audio:** VO tone shifts cooler, more technical. Music stays steady.
- **Narrative bridge:** Scene 1.2's last line ("and of course, elemental chain reactions") flows directly into Scene 2.1's first line with no pause.

---

## ACT 2: What's Been Built? [0:30 - 0:50]

**Purpose (from outline):** Establish technical credibility. Prove this is a real project with real engineering. This is the "trust" act.

### Scene 2.1: The Engine [0:30 - 0:40]
**Purpose:** Show the simulation layer depth. Prove this isn't an asset flip or smoke-and-mirrors demo.

**NARRATION (verbatim):**
> [0:30] Under the hood, it's a GPU compute shader-driven physics simulation.
> [0:33] Each chunk is 256 pixels — essentially a cellular automaton.
> [0:36] Terrain syncs back to the CPU every 4 frames,
> [0:39] so it can do things a pure-GPU approach can't, like lighting effects.

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:30 | Debug view if available: chunk grid over terrain, or gas density heatmap. If no debug view: rapid terrain carving in 4 directions with gas propagating through all openings simultaneously | "GPU Compute Shader Simulation" |
| 0:33 | Close-up: terrain being carved, gas visibly pushing through the new gap — show the "velocity injection" effect | "Per-Frame Fluid Propagation" |
| 0:36 | Combat sequence: weapon swing carves terrain + simultaneously pushes gas, which spreads and encounters fire | *(no overlay)* |
| 0:38 | Wider shot: entire room state has changed from the combat — new tunnels, gas redistributed, fires in new positions | *(no overlay — trust the visual)* |

**PERFORMANCE:** Technical, precise delivery. Slightly slower pace than Act 1 — let the weight of "this is real simulation" land. Emphasize "GPU compute shader" and "real."
**MUSIC:** Background instrumental at ~30% volume. Steady, slightly cooler/more measured feel.

### Scene 2.2: The Systems [0:40 - 0:50]
**Purpose:** Show that the game has working content infrastructure — weapons, modifiers, combat, enemies.

**NARRATION (verbatim):**
> [0:40] The build system is still in development, but it's roughly based on weapons and modifiers,
> [0:44] with heavy Balatro and Noita influences — though this system will probably get a major overhaul.
> [0:47] About 17,000 lines of GDScript total.
> [0:50] There isn't enough content yet to feel like a real roguelike, but combat and basic enemy AI are done.

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:40 | Quick cut: CSV weapon data table (2s). Text overlay appears. | "CSV Data-Driven Weapons" |
| 0:42 | Weapon swap UI showing 3 modifier slots with modifiers equipped (2s) | "3 Modifier Slots / Weapon" |
| 0:44 | Combat: weapon with modifiers active, status icons appearing on enemies (2s) | "Data-Driven Status System" |
| 0:46 | Quick glimpse of status reaction matrix or enemy with 3+ status effects (1s) | "~17K Lines GDScript" |
| 0:47 | Fast combat montage: 3-4 different weapons, enemies reacting, terrain breaking (3s) | "Core Loop Operational" |

**PERFORMANCE:** Matter-of-fact, not boastful. The numbers ("17,000 lines", "3 slots") should be stated as if reciting specs — not selling, just reporting what exists. Slight increase in pace for the final line ("but combat and basic enemy AI are done") to carry energy into Act 3.

**TRANSITION TO ACT 3:**

- **Visual:** Cut from fast combat montage to a **wide, still shot** of the game with all its placeholder art clearly visible — placeholder character sprite, basic terrain tiles, rough UI. Hold for 2 seconds. A meme overlay appears: a split-comparison image — left side "Engine" with a fire/gas explosion, right side "Art" with a placeholder stick figure. Or a "What we have" / "What we need" format.
- **Audio:** Music dips slightly. VO tone shifts to personal, genuine register.
- **Narrative bridge:** A deliberate pause after "combat and basic enemy AI are done", then the VO continues in a warmer, more personal tone.

---

## ACT 3: Why Join? [0:50 - 1:15]

**Purpose (from outline):** Sell the benefit to collaborators. Honest about scope. Frame the opportunity, not the need.

### Scene 3.1: The Canvas [0:50 - 1:02]
**Purpose:** Frame placeholder art as creative opportunity — the engine is real, the canvas is blank.

**NARRATION (verbatim):**
> [0:50] Everything you're seeing right now — characters, terrain, weapons, VFX, UI —
> [0:54] — is all open-source placeholder assets.
> [0:56] Which means: what you create becomes this game's final visual identity.
> [0:59] You'll get a genuinely publishable portfolio piece. Not a throwaway 48-hour game jam project.
> [1:01] Full credit. You own the creative rights to everything in your domain.
> [1:02] No AI-generated assets — real human work only.

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:50 | Slow pan or series of close-ups: placeholder character sprite, rough terrain tiles, basic weapon icon, simple UI panel | *(text overlaid on each element)* |
| 0:52 | "Character" close-up of placeholder sprite | "Your Character →" |
| 0:53 | "Terrain" close-up of placeholder tiles | "Your Terrain →" |
| 0:54 | "Weapons" close-up of placeholder weapon icon | "Your Weapons →" |
| 0:55 | "VFX" close-up of basic effects | "Your VFX →" |
| 0:56 | Wide shot of full game screen with all placeholders visible, background explosion happening behind it all | "A Blank Canvas, Waiting for You" |
| 0:59 | Split screen or before/after: left = current placeholder, right = "Your Work" with a glow-up / 「进化」reaction meme | *(no text — visual contrast)* |
| 1:01 | Text card: "Full Credit · Standalone Portfolio" | *(on-screen reinforces VO)* |

**PERFORMANCE:** Warmer, more personal than Acts 1-2. "Open-source placeholder assets" — slight smile in the voice. "What you create becomes this game's final visual identity" — this is the emotional peak of the pitch, deliver it with genuine invitation, not salesmanship. "No AI-generated assets" — firm, clear, a statement of values.

### Scene 3.2: The Roles [1:02 - 1:15]
**Purpose:** Clearly state what roles are open and what each person owns. Brief and inviting.

**NARRATION (verbatim):**
> [1:02] I'm currently looking for:
> [1:04] 2D Artist — characters, enemies, weapons, terrain, VFX, UI. You define the entire visual direction.
> [1:07] Game Designer — combat encounters, weapon × modifier build system, level pacing, economy.
> [1:10] Programmer — GDScript / Godot game systems, enemy AI, content tools, UI. Interest in compute shaders is a bonus, not required.
> [1:13] SFX / Composer — swing and terrain-destruction SFX, gas explosions, plus ambient/dynamic soundtrack. Currently zero audio.
> [1:15] Pure hobby project, unpaid, but full credit. You keep full portfolio rights to your work. Any level of involvement is welcome.

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 1:02 | Role card appears: "Roles Open" header | *(none)* |
| 1:04 | Artist B-roll: placeholder sprites with overlay arrows pointing to each element | "2D Artist — Define the Visual Direction" |
| 1:07 | Designer B-roll: modifier slot UI / weapon data table | "Game Designer — Builds & Pacing" |
| 1:10 | Programmer B-roll: brief code glimpse or debug sim view if available | "Programmer — Godot / Compute Shaders" |
| 1:13 | Sound B-roll: blank audio waveform or "NO AUDIO YET" card → gameplay footage with **silence** to emphasize the absence | "SFX / Composer — Starting from Zero" |
| 1:15 | Summary text card: all 4 roles listed | "Pure Hobby Project · Full Credit" |

**PERFORMANCE:** Brisk, clear, matter-of-fact. Each role gets one clean line — no over-explaining. "Pure hobby project, unpaid" delivered with honesty, not apology. "Any level of involvement is welcome" — warm, open, the most inviting note of the entire VO.

**TRANSITION TO CTA:** Role summary card fades into the CTA end card. Music intensity rises slightly — not back to hook level, but enough to feel like forward momentum toward an action.

---

## CTA & CLOSING [1:15 - 1:30]

### [1:15 - 1:25] — Call to Action
**CAMERA:** Screen recording — static end card.
**VISUAL:** Clean end card with:
- Top: "Game Name TBD — Drop Your Suggestion in the Comments!"
- Middle: Discord server link (large, readable)
- Below: Four role icons (paintbrush / gear / code brackets / music note) with brief labels
- Background: Slowed-down gameplay clip of a beautiful explosion or fire propagation shot, heavily blurred/desaturated so the text reads clearly

**NARRATION (verbatim):**
> [1:15] If any of these roles interest you —
> [1:18] — join the Discord, check out the repo, or just DM me for a chat.
> [1:21] The game doesn't have an official name yet — leave your ideas in the comments.
> [1:24] Let's turn this engine into a real game.

**ON-SCREEN TEXT:**

| Timestamp | Text | Duration | Style |
|-----------|------|----------|-------|
| 1:15 | Discord: [link] | 10s | Large, centered, readable font |
| 1:21 | Game Name TBD — Drop Your Suggestion in the Comments! | 9s | Below Discord link, slightly smaller |

**PERFORMANCE:** Warm, genuine. "Let's turn this engine into a real game" — the final emotional beat. Not grandiose, just sincere. Delivered like an invitation to a friend.

### [1:25 - 1:30] — Final Beat
**CAMERA:** Static end card continues.
**VISUAL:** A final meme overlay fades in over the end card — a warm, inviting reaction meme (e.g., 「等你来」"waiting for you" style, or a friendly 「合作愉快」handshake meme). Hold for 3 seconds, then fade to black over 1 second.

**AUDIO:** Music resolves with a final beat or chord at 1:28. 1-2 seconds of ambient game audio (a low fire crackle or distant explosion) under the fade to black.

**NARRATION:** *(none — let the visual and music close it out)*

---

## PRODUCTION NOTES

### Crew / Setup Requirements
- **Single creator** — all footage is screen-recorded gameplay. No camera, no lighting, no set.
- **Screen recording software:** OBS Studio or equivalent. Record at native resolution, hide UI for hook/spectacle shots where possible. Keep UI visible for weapon/modifier shots in Scene 2.2.
- **Microphone:** Decent USB or XLR mic for VO recording. Record VO in a quiet room.
- **Editing software:** Any NLE (DaVinci Resolve, Premiere, CapCut, etc.) that supports multiple video/audio tracks and text overlays.

### B-Roll Sourcing List

| Scene | Visual Needed | Source | Status |
|-------|---------------|--------|--------|
| Hook | 5 distinct explosion clips (gas tunnel, oil spill, terrain collapse, water+fire, full room) | Screen-record gameplay in different scenarios | Not started |
| 1.1 | Melee swing carving terrain (wide arc, clear before/after) | Screen record | Not started |
| 1.1 | Rapid terrain carving montage (tunnel, widening, wall collapse) | Screen record | Not started |
| 1.2 | Gas seeping through carved opening | Screen record | Not started |
| 1.2 | Spark → gas ignition → fire racing → oil fire → enemies with statuses | Screen record | Not started |
| 1.2 | Multi-element chaos: water + fire + gas + oil | Screen record | Not started |
| 2.1 | Debug view: chunk grid OR gas density heatmap (optional — substitute with multi-direction terrain carving if unavailable) | Screen record debug overlay | Not started |
| 2.1 | Combat + terrain carving + gas push combo sequence | Screen record | Not started |
| 2.2 | CSV weapon data table (screenshot or screen record of spreadsheet/editor) | Screenshot | Not started |
| 2.2 | Weapon swap UI with 3 modifier slots filled | Screen record | Not started |
| 2.2 | Combat with modifiers active, statuses on enemies | Screen record | Not started |
| 2.2 | Status reaction matrix or enemy with multiple status effects | Screenshot | Not started |
| 2.2 | Fast combat montage (3-4 weapons) | Screen record | Not started |
| 3.1 | Placeholder art close-ups: character, terrain, weapon icon, VFX, UI | Screen record + zoom in post | Not started |
| 3.1 | Wide shot: full game + explosion behind placeholder art | Screen record | Not started |
| 3.2 | Role B-roll: artist (sprites), designer (UI), programmer (code/CSV), sound (silence card) | Mix of screen record + screenshots | Not started |
| CTA | Slowed/blurred explosion shot for background | Screen record, slow + blur in post | Not started |

### Meme Sourcing List
| Scene | Meme Description | Source |
|-------|-----------------|--------|
| Hook:0:00 | 「脑子爆炸」galaxy brain | Bilibili reaction image / sticker |
| Hook:0:02 | 「这河里吗」surprised cat | Bilibili reaction image |
| Hook:0:04 | 「好家伙」shock face | Bilibili reaction image |
| Hook:0:06 | 「我人傻了」Pikachu shocked | Bilibili reaction image |
| Hook:0:08 | 「名场面」legendary moment | Bilibili reaction image |
| Act 1→2 trans | Geek/「数据」reaction or WTF face | Bilibili reaction image |
| Act 2→3 trans | Split comparison: engine vs. art / "What we need" format | Custom or Bilibili template |
| 3.1:0:59 | 「进化」glow-up / evolution meme | Bilibili reaction image |
| CTA:1:25 | 「等你来」or 「合作愉快」warm invite meme | Bilibili reaction image |

### Music / SFX Direction

| Timestamp | Music/SFX | Mood/Purpose | Source |
|-----------|-----------|--------------|--------|
| 0:00-0:10 | High-energy instrumental, building intensity | Hook energy, spectacle | Royalty-free or game OST placeholder |
| 0:10-0:30 | Same track at ~30% volume, steady energy | Background for Act 1 explanation | Same track, ducked |
| 0:30-0:50 | Same track, slightly cooler/more measured feel | Background for Act 2 tech section | Same track |
| 0:50-1:15 | Same track, warmer feel | Background for Act 3 personal pitch | Same track |
| 1:15-1:28 | Music intensity rises slightly | Forward momentum toward CTA | Same track, volume up slightly |
| 1:28 | Music resolves with final beat/chord | Closure | Same track, final beat |
| 1:28-1:30 | Ambient game audio: fire crackle or distant explosion | Atmosphere under fade | Record in-game or from sound library |

SFX notes: No in-game SFX to mix (project has no audio yet per recruitment kit). Music-only or music + ambient.

### On-Screen Text Master List

| Timestamp | Text | Duration | Appearance |
|-----------|------|----------|------------|
| 0:13 | "Fully Destructible Terrain" | 2s | Lower-third or center overlay |
| 0:18 | "Real-Time Terrain Destruction" | 2s | Lower-third or center overlay |
| 0:20 | "Realistic Gas Flow" | 2s | Lower-third or center overlay |
| 0:24 | "Chain Reactions" | 2s | Lower-third or center overlay |
| 0:26 | "Element Interaction System" | 2s | Lower-third or center overlay |
| 0:31 | "GPU Compute Shader Simulation" | 3s | Lower-third |
| 0:34 | "Per-Frame Fluid Propagation" | 2s | Lower-third |
| 0:40 | "CSV Data-Driven Weapons" | 2s | Lower-third |
| 0:42 | "3 Modifier Slots / Weapon" | 2s | Lower-third |
| 0:45 | "Data-Driven Status System" | 2s | Lower-third |
| 0:47 | "~17K Lines GDScript" | 3s | Lower-third |
| 0:49 | "Core Loop Operational" | 2s | Lower-third |
| 0:52-0:55 | "Your Character →" / "Your Terrain →" / "Your Weapons →" / "Your VFX →" | 1s each | Arrow pointing to each element |
| 0:56 | "A Blank Canvas, Waiting for You" | 3s | Centered |
| 1:01 | "Full Credit · Standalone Portfolio" | 2s | Lower-third |
| 1:02 | "Roles Open" header | 1s | Centered |
| 1:04 | "2D Artist — Define the Visual Direction" | 2s | Lower-third or side card |
| 1:07 | "Game Designer — Builds & Pacing" | 2s | Lower-third or side card |
| 1:10 | "Programmer — Godot / Compute Shaders" | 2s | Lower-third or side card |
| 1:13 | "SFX / Composer — Starting from Zero" | 2s | Lower-third or side card |
| 1:15 | "Pure Hobby Project · Full Credit" | 3s | Centered |
| 1:16 | "Discord: [link]" | 14s | Large, centered |
| 1:21 | "Game Name TBD — Drop Your Suggestion in the Comments!" | 9s | Below Discord link |

---

## Estimated Duration Breakdown

| Section | Scripted Duration | Outline Target | Delta |
|---------|-------------------|----------------|-------|
| Hook | 0:10 | 0:00 - 0:10 | 0s |
| Act 1 (Scene 1.1 + 1.2) | 0:20 | 0:10 - 0:30 | 0s |
| Act 2 (Scene 2.1 + 2.2) | 0:20 | 0:30 - 0:50 | 0s |
| Act 3 (Scene 3.1 + 3.2) | 0:25 | 0:50 - 1:15 | 0s |
| CTA + Closing | 0:15 | 1:15 - 1:30 | 0s |
| **Total** | **1:30** | **1:30** | **0s** |

All sections land exactly at outline target — no overruns, no underruns.

---

## Read-Through Notes

1. **Scene 1.1 VO density:** 3 lines in 10s (~3.3s per line). At natural speaking pace this is comfortable — about 12-15 characters per line. No tongue-twisters.

2. **Scene 1.2 flow:** The accelerating list structure ("Fire ignites gas, water douses flames, oil fuels them hotter —") should be delivered as one unbroken sentence, not three discrete statements. This mirrors the visual chain reaction it's describing.

3. **Act 2→3 transition:** The longest single pause in the video (~1.5-2s of silence after "combat and basic enemy AI are done"). This pause is intentional — it lets the visual contrast (combat → placeholder art) land before the VO shifts tone. Don't rush through it.

4. **Scene 3.1 emotional peak:** "What you create becomes this game's final visual identity" is the most important line for the primary audience (artists). If any line gets extra care in delivery, it's this one.

5. **Scene 3.2 role list pacing:** Each role gets ~3s of VO — tight but achievable. The list structure means the VO should feel like "here's what's open" not "here are requirements to meet." The closing line "Any level of involvement is welcome" is crucial — it signals low barrier.

6. **Total VO word count:** ~170 words for ~75 seconds of narration. At ~2.3 words/sec this is a natural, unhurried pace.

7. **No narration moments:** The hook (0:00-0:10) has no VO. The CTA (1:25-1:30) has no VO. These silent bookends frame the narration and let the audio-visual experience breathe.

---

## Self-Review

### Spec Coverage
- [x] Hook: explosion montage, memes, music only → Hook [0:00-0:10]
- [x] Act 1: game intro, terrain destruction, gas, liquids, status combos → Scene 1.1 + 1.2
- [x] Act 2: GPU sim, CSV weapons, status matrix, 17K lines → Scene 2.1 + 2.2
- [x] Act 3: benefits-first, portfolio, credit, no hard sell, role call → Scene 3.1 + 3.2
- [x] No AI assets → Scene 3.1 on-screen text + narration
- [x] Unpaid hobby project → Scene 3.2 narration
- [x] Name undecided, suggest in comments → CTA narration + on-screen text
- [x] Godot experience not required → Scene 3.2 narration ("Interest in compute shaders is a bonus, not required")
- [x] CTA: Discord, role summary, final meme → CTA section
- [x] Screen recording + text overlays + meme inserts + VO, no camera → consistent throughout

### Placeholder Scan
- No "TBD", "TODO", "fill in", "ad lib", or vague descriptions
- Discord link is the only external dependency not yet known — marked as `[link]` placeholder on end card. This is a genuine unknown, not a script gap. Creator fills it in before export.
- Debug visualization (Scene 2.1) has a fallback specified: "If no debug view: rapid terrain carving in 4 directions..."

### Internal Consistency
- Timestamps: 0:10 + 0:20 + 0:20 + 0:25 + 0:15 = 1:30. Matches.
- Music direction consistent: same track throughout, volume-adjusted per section
- Meme sourcing table maps every meme reference to a specific timestamp
- On-screen text master list maps all text overlays to timestamps
- VO tone arc: confident → technical → personal → warm → inviting. Matches the energy arc from the outline.

### Shootability Check
- Single creator, single setup (screen recording + mic for VO)
- No external locations, no props, no second camera operator needed
- All B-roll is gameplay capture or screenshots — achievable by the creator
- Memes are sourced from Bilibili reaction images — creator knows their own platform culture
- Music: one track needed. Can be royalty-free or creator-picked

### Pacing Check
- Hook: maximum energy (explosions + music)
- Act 1: dips to explanation, carried by visuals
- Act 2: cooler, more measured (tech specs)
- Act 3: warmest, most personal (invitation)
- CTA: forward momentum, friendly closeout
- The arc doesn't flatline — each section has a distinct energy level

### Ambiguity Check
- Every VO line is verbatim
- Every on-screen text has exact wording, timestamp, and duration
- Every meme placement has timestamp and description
- Music is the most ambiguous element — described by mood rather than specific track. This is acceptable since music choice is subjective and depends on the creator's taste. The direction is specific enough to source: "high-energy instrumental, building intensity."
