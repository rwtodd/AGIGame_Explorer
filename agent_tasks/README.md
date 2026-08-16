# Sierra AGI Parallel Implementation Tasks

### Current Milestone Tasks (Tasks 4–6)

| Task File | Subsystem | Focus | Primary Outputs |
| :--- | :--- | :--- | :--- |
| [`task_4_fix_opcodes_and_input_prompts.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_4_fix_opcodes_and_input_prompts.md) | **View Querying Opcodes & Input Prompts** | `last.cel`, `number.of.loops` VIEW queries, `get.string`, `get.num` modal prompts, `word.to.string`, `parse` | `lib/logic/interpreter/`, `lib/ui/widgets/input_prompt_dialog.dart`, `test/interpreter/` |
| [`task_5_inventory_screen_and_show_obj.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_5_inventory_screen_and_show_obj.md) | **Interactive Inventory Screen & Item Viewer** | `status()` / TAB inventory list, item selection, `show.obj` sprite cel and description viewer | `lib/ui/widgets/inventory_dialog.dart`, `lib/ui/widgets/object_inspection_dialog.dart`, `test/ui/` |
| [`task_6_controllers_and_save_load.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_6_controllers_and_save_load.md) | **Controller Keys & Save / Restore / Restart State** | `set.key` F1–F10 mapping, `controller(c)`, `save.game` / `restore.game` `.sav` serialization, Save/Restore slot dialog, `restart.game` | `lib/engine/state/`, `lib/engine/controllers/`, `lib/ui/widgets/save_load_dialog.dart`, `test/engine/` |

---

### Previous Milestone Tasks (Tasks 1–3, Merged)

| Task File | Subsystem | Focus | Status |
| :--- | :--- | :--- | :--- |
| [`task_1_motion_and_collision.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_1_motion_and_collision.md) | Sprite Motion & Collision | Pure physics, motion modes (`wander`, `follow`, `moveObj`), boundary & `PriorityBuffer` collision | Merged |
| [`task_2_text_parser_and_said.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_2_text_parser_and_said.md) | Text Parser & `said()` Matcher | Text tokenization against `WORDS.TOK`, noise filtering, contraction handling, `said()` matching | Merged |
| [`task_3_game_engine_and_screen.md`](file:///Users/rtodd/src/flutter_agigame/agent_tasks/task_3_game_engine_and_screen.md) | `AgiGameEngine` & `GameScreen` UI | 20 Hz cycle coordinator, composite playfield canvas, status bar, command prompt, dialog popups | Merged |
