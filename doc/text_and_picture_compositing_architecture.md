# **Text & Picture Compositing Architecture in GPU-Sliced AGI**

## **1. Background & The Vector Text vs. Pixel Slices Tension**

In original Sierra AGI interpreters (1984–1989), the display was driven by a single 320×200 software video framebuffer:
1. **Background Picture**: `draw.pic(n)` drew vector lines and flood fills directly into the framebuffer and priority buffer.
2. **Text / Character Output**: Opcodes like `display(row, col, msg)`, `clear.text.rect(...)`, and `set.text.attribute(...)` wrote character glyphs directly into the video framebuffer on top of whatever background pixels existed.
3. **Actor Sprites**: Animated objects were blitted onto the framebuffer during the draw cycle (`blists_draw`), drawing sprite pixels directly over the framebuffer (and over any previously drawn text).

In our modern Flutter engine, picture graphics are decomposed into **16 GPU-accelerated priority slices** (layers $0\text{–}15$) to leverage Flutter Impeller for hardware compositing, while the text layer is maintained as a high-resolution text screen buffer (`AgiTextScreenBuffer`).

This creates a subtle architectural challenge: **where does on-screen text fit into the multi-layer GPU depth stack?**

---

## **2. Three Crucial Case Studies**

### **Case 1: Space Quest 2 – Room 22 (Rope Swing Chasm)**
- **Scenario**: In Room 22, Roger Wilco swings on a rope across a sheer gorge. LOGIC 22 calls:
  ```text
  display(21, 5, "F6 to release grip on rope")
  ```
- **The Challenge**: Room 22's picture contains foreground cliff and rock formations categorized at **Priority 5** on the left side of the playfield ($x \in [20, 36], y \in [160, 168]$).
- **Failure Mode**: If all playfield text is hardcoded to Priority 4 (base horizon), the subsequent Priority 5 foreground rock slice is painted over columns 5–10, clipping out `"F6 to "` and leaving only `"release grip on rope"` visible.

### **Case 2: Police Quest 1 – Room 116 (The Lytton Tribune Newspaper)**
- **Scenario**: In Room 116, the player reads a full-screen newspaper. LOGIC 116 calls:
  ```text
  clear.text.rect(2, 1, 21, 38, 15) // Fills newspaper with white background (bg = 15)
  display(5, 1, "The city of Lytton, |")
  ...
  position(o1, 93, 91)
  draw(o1) // Photo of President Hickle (View 96, cel 0)
  ```
- **The Challenge**: The photo of President Hickle is an **actor sprite** (`%o1`), positioned inside the white newspaper area where the right text column has empty space.
- **Failure Mode**: If the text overlay is composited after all actors, the solid white background fill (`bg = 15`) of the text buffer paints directly over Actor `%o1`, leaving a blank white box instead of the photograph.

### **Case 3: Space Quest 1 – Room 65 (Star Generator Keypad & Detonation Countdown)**
- **Scenario**: In Room 65, the player views the Star Generator keypad. LOGIC 65 calls:
  ```text
  display(6, 16, "........")
  ```
  When the player enters the detonation code `6858` and presses ENTER, the script begins the detonation countdown. It clears the bottom prompt line (`clear.lines(23, 24, 0)`) and launches Actors `%o2`, `%o3`, `%o4` (View 246 scrolling LED readout banner) continuously moving across `y=46` (directly covering Row 6).
- **The Challenge**: The moving banner sprites are animated objects (actors at Priority 4) intended to visually replace and scroll over the keypad readout.
- **Failure Mode**: If text glyphs float unconditionally on top of all actor sprites at the very end of the frame, the white dots `........` stay permanently visible floating over the moving LED banner cels.

---

## **3. The Solution: Priority-Matched Depth Interleaving**

To resolve all three constraints simultaneously without compromises, the engine matches each character cell's rendering pass to the **underlying picture priority buffer** at that cell's coordinate:

```text
┌───────────────────────────────────────────────────────────┐
│            GPU SCENE COMPOSITING ORDER (IMPELLER)         │
│                                                           │
│  For Priority Band p = 0 to 15:                           │
│    1. Draw Picture Slice p (cached GPU texture)           │
│    2. Draw Text Background Fills where priority == p      │
│    3. Draw Text Glyphs where priority == p                │
│    4. Draw Actor Sprites where actor.priority == p        │
│                                                           │
│  Final Pass:                                              │
│    5. Draw Non-Playfield Text (Row 0 Status Bar,          │
│       Row 22-24 Bottom Prompts/Notices)                   │
└───────────────────────────────────────────────────────────┘
```

### **How It Operates**

1. **Per-Cell Priority Determination (`_getCellPriority`)**:
   - For any cell at `(row, col)`, the compositor queries the underlying `PriorityBuffer` at `(col * 4, (row - playfieldRow) * 8)`.
   - Returns the underlying depth band ($4\text{--}15$).
2. **Priority Band Interleaving**:
   - In each band $p$:
     - The background picture slice for priority $p$ is drawn first.
     - Any text background fills and text glyphs that sit on Priority $p$ scenery are drawn on top of the slice.
     - Any actor sprites assigned to Priority $p$ are drawn on top of the slice and on top of that priority's text.
3. **Non-Playfield Floating Layer**:
   - Text outside the playfield (e.g. Row 0 status line, Row 22/23 command prompt, Row 24 notices like `"F6 to fire Pulseray"` or `"F6 to Select Key"`) is drawn with `excludePlayfield: true` at the very end, floating over the full 320×200 viewport.

---

## **4. Results & Verification**

- **Space Quest 2 Room 22**: `"F6 to "` sits on the Priority 5 rock and is drawn in band 5 (after Slice 5), while `"release grip on rope"` sits on Priority 4 background and is drawn in band 4. The entire string is 100% visible and unclipped.
- **Police Quest 1 Room 116**: The white newspaper background fill and text glyphs are drawn in band 4, followed by Actor `%o1` (photo of President Hickle). The photo composites cleanly on the white page.
- **Space Quest 1 Room 65**: Keypad dots `........` are drawn in band 4, followed by Actors `%o2`, `%o3`, `%o4` (detonation banner). The scrolling banner cleanly occludes and draws over the keypad readout.
- **Status Line & Prompts**: Non-playfield UI text (status bar, bottom prompts) remains crystal clear and unobstructed across all games.
