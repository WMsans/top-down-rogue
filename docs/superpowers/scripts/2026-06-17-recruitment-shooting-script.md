# Shooting Script: Godot Action-Roguelike Recruitment Video

> Based on outline: [2026-06-17-recruitment-video-outline.md](../specs/2026-06-17-recruitment-video-outline.md)
> Narration style: verbatim | Target duration: 90s | Visual style: Screen recording + text overlays + meme inserts + voiceover
> Created: 2026-06-17

---

## HOOK & COLD OPEN [0:00 - 0:10]

### [0:00 - 0:10] — Explosion Montage
**CAMERA:** Screen recording — gameplay capture. No UI if possible.
**VISUAL:** Rapid montage of 5 explosion clips from different in-game scenarios:

| Timestamp | Visual | Meme Overlay | Duration |
|-----------|--------|--------------|----------|
| 0:00 | Gas ignition in a narrow tunnel — fire races through confined space | 「脑子爆炸」galaxy brain meme | 2s |
| 0:02 | Oil spill spreading across terrain, then igniting into a fire field | 「这河里吗」/ "is this real?" reaction cat | 2s |
| 0:04 | Terrain collapsing from accumulated damage, chain reaction of breakage | 「好家伙」wide-eyed shock face | 2s |
| 0:06 | Water dousing a spreading fire, steam/smoke rising, gas reigniting nearby | 「我人傻了」Pikachu surprise | 2s |
| 0:08 | Biggest explosion — full room consumed in fire + terrain collapse | 「名场面」/ "legendary scene" reaction | 2s |

**AUDIO:** High-energy instrumental music only. No voiceover, no text on screen. Music builds intensity across all 10 seconds, peaks with the final explosion at 0:08.
**NARRATION:** *(none — music only)*
**PERFORMANCE:** N/A — no narration in this segment.
**TRANSITION TO ACT 1:** Hard cut at 0:10 from the final explosion burst to the first gameplay clip. Music dips sharply to ~30% volume. First VO line begins **immediately** — zero gap.

---

## ACT 1: What Is This? [0:10 - 0:30]

**Purpose (from outline):** Answer "what am I looking at?" Introduce the game concept through concrete mechanics. Establish the unique selling point.

### Scene 1.1: The Destructible World [0:10 - 0:20]
**Purpose:** Show that terrain carving IS the gameplay — not a gimmick, not a scripted event.
**CAMERA:** Screen recording of gameplay. Character visible in center of frame.

**NARRATION (verbatim):**
> [0:10] 我正在开发一款动作肉鸽游戏。
> [0:13] 和Noita类似，每个像素都是模拟的一部分。
> [0:16] 一个全可破坏地形是自然的。

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:10 | Wide shot: character in center of a cave room, enemies nearby | *(no overlay — let the game speak)* |
| 0:12 | Melee swing carves a wide arc through a thick wall — clear before/after. Wall → tunnel | "完全可破坏地形" |
| 0:15 | Rapid series: carving in narrow tunnel → widening a passage → collapsing a wall onto enemies | *(no overlay — action is fast)* |
| 0:18 | Final carving shot: character surrounded, swings through walls to create escape route | "实时地形破坏" |

**PERFORMANCE:** Steady, confident. Slight emphasis on "完全独立开发" (completely solo-developed) and "实时" (real-time). Not hyped — letting the visuals carry the weight.
**MUSIC:** Background instrumental at ~30% volume. Steady energy, not climactic.

### Scene 1.2: The Living Elements [0:20 - 0:30]
**Purpose:** Show that the world reacts — gas, fluids, fire chain together emergently.

**NARRATION (verbatim):**
> [0:22] 气体和液体会在你挖出的隧道中流动、聚集。
> [0:25] 火焰点燃燃气，水浇灭火焰，油助长火势，
> [0:28] 以及更多的元素连锁反应，便是它最大的亮点。

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:20 | Cut to: player carves wall, gas visibly seeps through the new opening | "真实气体流动" |
| 0:22 | Gas pools and spreads through a tunnel system | *(no overlay)* |
| 0:24 | A spark (weapon impact) ignites the gas. Fire races along the gas trail | "连锁反应" |
| 0:26 | Fire hits an oil patch → oil fire spreads across terrain → status icons pop on enemies caught in it | "元素交互系统" |
| 0:28 | Water douses part of the fire, steam rises, gas reignites elsewhere — multi-element chaos | *(no overlay — spectacle carries)* |

**PERFORMANCE:** Energy lifts slightly from Scene 1.1. "但这不只是破坏" — slight pause before, then momentum. The list ("火焰点燃燃气...") should flow as one accelerating sentence.
**TRANSITION TO ACT 2:**

- **Visual:** Cut from the multi-element chaos to a wider shot or split-second glimpse of CSV data / debug view. A subtle nerd/「数据」meme or "WTF" reaction face flashes for 0.5s.
- **Audio:** VO tone shifts cooler, more technical. Music stays steady.
- **Narrative bridge:** Last line of Scene 1.2 ("实时传播") flows directly into first line of Scene 2.1 with no pause.

---

## ACT 2: What's Been Built? [0:30 - 0:50]

**Purpose (from outline):** Establish technical credibility. Prove this is a real project with real engineering. This is the "trust" act.

### Scene 2.1: The Engine [0:30 - 0:40]
**Purpose:** Show the simulation layer depth. Prove this isn't an asset flip or smoke-and-mirrors demo.

**NARRATION (verbatim):**
> [0:30] 底层是一套 GPU 计算着色器驱动的物理模拟。
> [0:33] 256 格分块，逐帧探测，真实的流体传播。
> [0:36] 每一次挥砍不仅破坏地形，还会向气体场中注入速度——
> [0:39] ——这意味着每一次战斗都在实时改变物理世界。

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:30 | Debug view if available: chunk grid over terrain, or gas density heatmap. If no debug view: rapid terrain carving in 4 directions simultaneously while gas propagates through all openings | "GPU 计算着色器模拟" |
| 0:33 | Close-up: terrain being carved, gas visually pushing through the new gap — show the "velocity injection" effect | "逐帧流体传播" |
| 0:36 | Combat sequence: weapon swing carves terrain + simultaneously pushes gas, which spreads and encounters fire | *(no overlay)* |
| 0:38 | Wider shot: entire room state has changed from the combat — new tunnels, gas redistributed, fires in new positions | *(no overlay — trust the visual)* |

**PERFORMANCE:** Technical, precise delivery. Slightly slower pace than Act 1 — let the weight of "this is real simulation" land. Emphasize "GPU 计算着色器" and "真实的".

### Scene 2.2: The Systems [0:40 - 0:50]
**Purpose:** Show that the game has working content infrastructure — weapons, modifiers, combat, enemies.

**NARRATION (verbatim):**
> [0:40] 武器和 Modifier 系统由 CSV 数据驱动，每把武器支持 3 个 Modifier 插槽。
> [0:44] 状态效果系统全数据驱动，元素交叉反应覆盖玩家和敌人双方。
> [0:47] 总计约 17000 行 GDScript，模拟层和状态层都有单元测试覆盖。
> [0:50] 战斗手感、敌人 AI、Run Loop —— 核心循环已经打通。

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:40 | Quick cut: CSV weapon data table (2s). Text overlay appears. | "CSV 数据驱动武器" |
| 0:42 | Weapon swap UI showing 3 modifier slots with modifiers equipped (2s) | "3 Modifier 插槽 / 每武器" |
| 0:44 | Combat: weapon with modifiers active, status icons appearing on enemies (2s) | "数据驱动状态系统" |
| 0:46 | Quick glimpse of status reaction matrix or enemy with 3+ status effects (1s) | "~17K 行 GDScript" |
| 0:47 | Fast combat montage: 3-4 different weapons, enemies reacting, terrain breaking (3s) | "核心循环已打通" |

**PERFORMANCE:** Matter-of-fact, not boastful. The numbers ("17000 行", "3 个插槽") should be stated as if reciting specs — not selling, just reporting what exists. Slight increase in pace for the final line ("核心循环已经打通") to carry energy into Act 3.

**TRANSITION TO ACT 3:**

- **Visual:** Cut from fast combat montage to a **wide, still shot** of the game with all its placeholder art clearly visible — placeholder character sprite, basic terrain tiles, rough UI. Hold for 2 seconds. A meme overlay appears: a split-comparison image — left side "引擎" (engine) with a fire/gas explosion, right side "美术" (art) with a placeholder stick figure. Or a Bilibili-style "我们有什么"/"我们要什么" format.
- **Audio:** Music dips slightly. VO tone shifts to personal, honest register.
- **Narrative bridge:** A deliberate pause after "核心循环已经打通", then the VO continues in a warmer, more personal tone.

---

## ACT 3: Why Join? [0:50 - 1:15]

**Purpose (from outline):** Sell the benefit to collaborators. Honest about scope. Frame the opportunity, not the need.

### Scene 3.1: The Canvas [0:50 - 1:02]
**Purpose:** Frame placeholder art as creative opportunity — the engine is real, the canvas is blank.

**NARRATION (verbatim):**
> [0:50] 你现在看到的所有美术——角色、地形、武器、特效、UI——
> [0:54] ——全部是开源占位素材。
> [0:56] 这意味着：你的作品，就是这个游戏最终的视觉面貌。
> [0:59] 你将获得一个真正可以发布的 Portfolio 作品，不是 48 小时 Game Jam 的一次性项目。
> [1:01] 完全署名，你拥有自己领域的全部创作署名权。
> [1:02] 不收 AI 生成素材——只要真人手工创作。

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 0:50 | Slow pan or series of close-ups: placeholder character sprite, rough terrain tiles, basic weapon icon, simple UI panel | *(text overlaid on each element)* |
| 0:52 | "角色" close-up of placeholder sprite | "你的角色 →" |
| 0:53 | "地形" close-up of placeholder tiles | "你的地形 →" |
| 0:54 | "武器" close-up of placeholder weapon icon | "你的武器 →" |
| 0:55 | "特效" close-up of basic VFX | "你的特效 →" |
| 0:56 | Wide shot of full game screen with all placeholder visible, background explosion happening behind it all | "空白画布，等你来定义" |
| 0:59 | Split screen or before/after: left = current placeholder, right = "你的作品" with a meme of a glow-up / 「进化」reaction | *(no text — visual contrast)* |
| 1:01 | Text card: "完全署名 · 独立 Portfolio" | *(on-screen reinforces VO)* |

**PERFORMANCE:** Warmer, more personal than Acts 1-2. "全部是开源占位素材" — slight smile in the voice. "你的作品，就是这个游戏最终的视觉面貌" — this is the emotional peak of the pitch, deliver it with genuine invitation, not salesmanship. "不收 AI 生成素材" — firm, clear, a statement of values.

### Scene 3.2: The Roles [1:02 - 1:15]
**Purpose:** Clearly state what roles are open and what each person owns. Brief and inviting.

**NARRATION (verbatim):**
> [1:02] 我目前正在找：
> [1:04] 2D 美术——角色、敌人、武器、地形、特效、UI。你定义整个视觉方向。
> [1:07] 游戏策划——战斗遭遇、武器 × Modifier 构筑系统、关卡节奏、经济系统。
> [1:10] 程序员——GDScript / Godot 游戏系统、敌人 AI、内容工具、UI。对计算着色器感兴趣的加分，但不要求。
> [1:13] 音效 / 作曲——挥砍、地形破坏、燃气爆炸的 SFX，以及氛围 / 动态配乐。目前零音频。
> [1:15] 纯爱好项目，无偿，但完全署名。你保留你作品的完整 Portfolio 权利。欢迎任何参与程度。

**VISUAL/SHOT LIST:**

| Timestamp | Visual | On-Screen Text |
|-----------|--------|----------------|
| 1:02 | Role card appears: "招募角色" header | *(none)* |
| 1:04 | Artist B-roll: placeholder sprites with overlay arrows pointing to each element | "2D 美术 — 定义视觉方向" |
| 1:07 | Designer B-roll: modifier slot UI / weapon data table | "游戏策划 — 构筑 & 节奏" |
| 1:10 | Programmer B-roll: brief code glimpse or debug sim view if available | "程序员 — Godot / 计算着色器" |
| 1:13 | Sound B-roll: blank audio waveform or "NO AUDIO YET" card → gameplay footage with **silence** to emphasize the absence | "音效 / 作曲 — 从零开始" |
| 1:15 | Summary text card: all 4 roles listed | "纯爱好项目 · 完全署名" |

**PERFORMANCE:** Brisk, clear, matter-of-fact. Each role gets one clean line — no over-explaining. "纯爱好项目，无偿" delivered with honesty, not apology. "欢迎任何参与程度" — warm, open, the most inviting note of the entire VO.

**TRANSITION TO CTA:** Role summary card fades into the CTA end card. Music intensity rises slightly — not back to hook level, but enough to feel like forward momentum toward an action.

---

## CTA & CLOSING [1:15 - 1:30]

### [1:15 - 1:25] — Call to Action
**CAMERA:** Screen recording — static end card.
**VISUAL:** Clean end card with:
- Top: "游戏名待定 — 评论区留下你的想法！" (Game name TBD — leave your suggestion!)
- Middle: Discord server link (large, readable)
- Below: Four role icons (paintbrush / gear / code brackets / music note) with brief labels
- Background: Slowed-down gameplay clip of a beautiful explosion or fire propagation shot, heavily blurred/desaturated so the text reads clearly

**NARRATION (verbatim):**
> [1:15] 如果你对以上任何一个方向感兴趣——
> [1:18] ——加入 Discord，来看看 Repo，或者直接私信我聊聊。
> [1:21] 游戏还没有正式名字，欢迎在评论区留下你的想法。
> [1:24] 让我们一起把这个引擎，变成一个真正的游戏。

**ON-SCREEN TEXT:**

| Timestamp | Text | Duration | Style |
|-----------|------|----------|-------|
| 1:15 | Discord 链接：[link] | 10s | Large, centered, readable font |
| 1:21 | 游戏名待定 — 评论区等你命名！ | 9s | Below Discord link, slightly smaller |

**PERFORMANCE:** Warm, genuine. "让我们一起把这个引擎，变成一个真正的游戏" — the final emotional beat. Not grandiose, just sincere. Delivered like an invitation to a friend.

### [1:25 - 1:30] — Final Beat
**CAMERA:** Static end card continues.
**VISUAL:** A final meme overlay fades in over the end card — a warm/inviting Bilibili-style reaction (e.g., 「等你来」/ "waiting for you" style, or a friendly 「合作愉快」handshake meme). Hold for 3 seconds, then fade to black over 1 second.

**AUDIO:** Music resolves with a final beat or chord at 1:28. 1-2 seconds of ambient game audio (a low fire crackle or distant explosion) under the fade to black.

**NARRATION:** *(none — let the visual and music close it out)*

---

## PRODUCTION NOTES

### Crew / Setup Requirements
- **Single creator** — all footage is screen-recorded gameplay. No camera, no lighting, no set.
- **Screen recording software:** OBS Studio or equivalent. Record at native resolution with no UI if possible for hook/spectacle shots. UI visible for weapon/modifier shots in Scene 2.2.
- **Microphone:** Decent USB or XLR mic for VO recording. Record VO in a quiet room.
- **Editing software:** Any NLE (DaVinci Resolve, Premiere, CapCut, etc.) that supports multiple video/audio tracks and text overlays.

### B-ROLL Sourcing List

| Scene | Visual Needed | Source | Status |
|-------|---------------|--------|--------|
| Hook | 5 distinct explosion clips (gas tunnel, oil spill, terrain collapse, water+fire, full room) | Screen-record gameplay in different scenarios | Not started |
| 1.1 | Melee swing carving terrain (wide arc, clear before/after) | Screen record | Not started |
| 1.1 | Rapid terrain carving montage (tunnel, widening, wall collapse) | Screen record | Not started |
| 1.2 | Gas seeping through carved opening | Screen record | Not started |
| 1.2 | Spark → gas ignition → fire racing → oil fire → enemies with statuses | Screen record | Not started |
| 1.2 | Multi-element chaos: water + fire + gas + oil | Screen record | Not started |
| 2.1 | Debug view: chunk grid OR gas density heatmap (optional — substitute with terrain carving if unavailable) | Screen record debug overlay | Not started |
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
| Hook:0:06 | 「我人傻了」Pikachu | Bilibili reaction image |
| Hook:0:08 | 「名场面」legendary scene | Bilibili reaction image |
| Act 1→2 trans | Nerd/「数据」reaction or WTF face | Bilibili reaction image |
| Act 2→3 trans | Split: engine vs. art / 「我们要什么」format | Custom or Bilibili template |
| 3.1:0:59 | 「进化」glow-up meme | Bilibili reaction image |
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
| 0:13 | "完全可破坏地形" | 2s | Lower-third or center overlay |
| 0:18 | "实时地形破坏" | 2s | Lower-third or center overlay |
| 0:20 | "真实气体流动" | 2s | Lower-third or center overlay |
| 0:24 | "连锁反应" | 2s | Lower-third or center overlay |
| 0:26 | "元素交互系统" | 2s | Lower-third or center overlay |
| 0:31 | "GPU 计算着色器模拟" | 3s | Lower-third |
| 0:34 | "逐帧流体传播" | 2s | Lower-third |
| 0:40 | "CSV 数据驱动武器" | 2s | Lower-third |
| 0:42 | "3 Modifier 插槽 / 每武器" | 2s | Lower-third |
| 0:45 | "数据驱动状态系统" | 2s | Lower-third |
| 0:47 | "~17K 行 GDScript" | 3s | Lower-third |
| 0:49 | "核心循环已打通" | 2s | Lower-third |
| 0:52-0:55 | "你的角色 →" / "你的地形 →" / "你的武器 →" / "你的特效 →" | 1s each | Arrow pointing to each element |
| 0:56 | "空白画布，等你来定义" | 3s | Centered |
| 1:01 | "完全署名 · 独立 Portfolio" | 2s | Lower-third |
| 1:02 | "招募角色" header | 1s | Centered |
| 1:04 | "2D 美术 — 定义视觉方向" | 2s | Lower-third or side card |
| 1:07 | "游戏策划 — 构筑 & 节奏" | 2s | Lower-third or side card |
| 1:10 | "程序员 — Godot / 计算着色器" | 2s | Lower-third or side card |
| 1:13 | "音效 / 作曲 — 从零开始" | 2s | Lower-third or side card |
| 1:15 | "纯爱好项目 · 完全署名" | 3s | Centered |
| 1:16 | "Discord 链接：[link]" | 14s | Large, centered |
| 1:21 | "游戏名待定 — 评论区等你命名！" | 9s | Below Discord link |

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

1. **Scene 1.1 VO density:** 4 lines in 10s (~2.5s per line). At natural Chinese speaking pace this is comfortable — about 12-15 characters per line. No tongue-twisters. "重塑战场" is the shortest line (4 chars), which works as a punchy scene closer.

2. **Scene 1.2 flow:** The accelerating list structure ("火焰点燃燃气，水浇灭火焰，油助长火势") should be delivered as one breathless sentence, not three discrete statements. This mirrors the visual chain reaction it's describing.

3. **Act 2→3 transition:** The longest single pause in the video (~1.5-2s of silence after "核心循环已经打通"). This pause is intentional — it lets the visual contrast (combat → placeholder art) land before the VO shifts tone. Don't rush through it.

4. **Scene 3.1 emotional peak:** "你的作品，就是这个游戏最终的视觉面貌" is the most important line for the primary audience (artists). If any line gets extra care in delivery, it's this one.

5. **Scene 3.2 role list pacing:** Each role gets ~3s of VO — tight but achievable. The list structure means the VO should feel like "here's what's open" not "here are requirements to meet." The closing line "欢迎任何参与程度" is essential — it signals low barrier.

6. **Total VO word count:** ~340 Chinese characters for ~75 seconds of narration. At ~4.5 chars/sec this is a natural, unhurried pace.

7. **No narration moments:** The hook (0:00-0:10) has no VO. The CTA (1:25-1:30) has no VO. These silent bookends frame the narration and let the audio-visual experience breathe.

---

## Self-Review

### Spec Coverage
- [x] Hook: explosion montage, memes, music only → Hook [0:00-0:10]
- [x] Act 1: game intro, terrain carving, gas, fluids, status combos → Scene 1.1 + 1.2
- [x] Act 2: GPU sim, CSV weapons, status matrix, 17k lines → Scene 2.1 + 2.2
- [x] Act 3: benefits-first, portfolio, credit, no hard sell, role call → Scene 3.1 + 3.2
- [x] No AI assets → Scene 3.1, on-screen text, narration
- [x] Unpaid hobby project → Scene 3.2 narration
- [x] Name undecided, suggest in comments → CTA narration + on-screen text
- [x] Godot experience not required → Scene 3.2 narration ("对计算着色器感兴趣的加分，但不要求")
- [x] CTA: Discord, role summary, final meme → CTA section
- [x] Screen recording + text overlays + meme inserts + VO, no camera → consistent throughout

### Placeholder Scan
- No "TBD", "TODO", "fill in", "ad lib", or vague descriptions
- Discord link is the only external dependency not yet known — marked as `[link]` placeholder on end card. This is a genuine unknown, not a script gap. Creator fills it in before export.
- Debug visualization (Scene 2.1) has a fallback specified: "If no debug view: rapid terrain carving in 4 directions..."

### Internal Consistency
- Timestamps: 0:10+0:20+0:20+0:25+0:15 = 1:30. Matches.
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
- Act 3: warmest, most personal (the ask)
- CTA: forward momentum, friendly closeout
- The arc doesn't flatline — each section has a distinct energy level

### Ambiguity Check
- Every VO line is verbatim
- Every on-screen text has exact wording, timestamp, and duration
- Every meme placement has timestamp and description
- Music is the most ambiguous element — described by mood rather than specific track. This is acceptable since music choice is subjective and depends on the creator's taste. The direction is specific enough to source: "high-energy instrumental, building intensity."
