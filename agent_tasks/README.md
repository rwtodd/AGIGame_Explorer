# Parallel Gameplay Implementation Tasks

These 3 tasks can be executed in parallel worktree conversations to build out the full Sierra AGI playable engine:

| Task File | Subsystem | Focus | Primary Outputs |
| :--- | :--- | :--- | :--- |
| [`task_1_motion_and_collision.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_1_motion_and_collision.md) | **Sprite Motion & Collision** | Pure physics, motion types (`wander`, `follow`, `moveObj`), boundary & `PriorityBuffer` control line collision | `lib/engine/motion/`, `test/engine/` |
| [`task_2_text_parser_and_said.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_2_text_parser_and_said.md) | **Text Parser & `said()` Matcher** | Text tokenization against `WORDS.TOK`, noise filtering, contraction handling, wildcard matching (`ANYWORD`, `ROL`) | `lib/engine/parser/`, `test/engine/` |
| [`task_3_game_engine_and_screen.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_3_game_engine_and_screen.md) | **`AgiGameEngine` & `GameScreen` UI** | 20 Hz cycle coordinator, `AgiInterpreterDelegate` wiring, room transitions, composite viewport canvas, status bar, command prompt, dialog popups | `lib/engine/agi_game_engine.dart`, `lib/ui/screens/game/` |

---

### How to Run Each Task in a Worktree

1. **Agent 1: Motion & Collision**
   - Branch / Worktree: `implement_motion_and_collision`
   - Instructions: Read [`agent_tasks/task_1_motion_and_collision.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_1_motion_and_collision.md)

2. **Agent 2: Text Parser & `said()` Matcher**
   - Branch / Worktree: `implement_text_parser_and_said`
   - Instructions: Read [`agent_tasks/task_2_text_parser_and_said.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_2_text_parser_and_said.md)

3. **Agent 3: `AgiGameEngine` & `GameScreen`**
   - Branch / Worktree: `implement_game_engine_and_screen`
   - Instructions: Read [`agent_tasks/task_3_game_engine_and_screen.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_3_game_engine_and_screen.md)
