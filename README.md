<!-- coderabbit-ai-generated:v1 -->

# Before the Citadel — Godot prototype

<!-- coderabbit-ai-generated:v1 -->

<!-- coderabbit-ai-generated-section:v1:5a6a774e26b126a53118ab0a4dd03cc0d6623ba8aac8f7cde6d1338b6bbc629c -->

Target: Godot 4.6.1 stable, Compatibility renderer. Open `project.godot` with Godot 4.6.1 (standard build) and press F6/F5. All model assets are local; no network or plugins required.

<!-- /coderabbit-ai-generated:v1 -->

## Controls

- WASD: walk; E: draw sword.
- Space: attack; press again during the attack to queue a second strike.
- Hold right mouse button and drag: camera orbit.
- R: restart.

## Implementation

`main.tscn` runs `battle.gd`, which constructs the battlefield, lights, camera and characters. `assets/` contains the original metric GLBs. <!-- coderabbit-ai-generated:v1 -->

<!-- coderabbit-ai-generated-section:v1:b2144f707e1f7cec70f417bd1155412a2178aacef619680c4bd3b44f7f82b88a -->

Heavy diagonal cuts take 1.36 seconds: gathering and loading (0–0.43s), cutting arc (0.43–0.74s), then weighted follow-through and return to guard. <!-- coderabbit-ai-generated:v1 -->

<!-- coderabbit-ai-generated-section:v1:81224ccd8abe9c35b80117955678c3dec539eb3202548f64243b3f0b7b593156 -->

Damage requires the swept blade to intersect an enemy torso capsule during the active cutting arc; each enemy can be hit once per swing. The third combo strike is an overhead chop. A leading-foot step and body weight shift support each cut; struck enemies stagger before attacking again.

<!-- /coderabbit-ai-generated:v1 --> Alternating cuts rotate pelvis and chest, lower the body over planted feet, and use two-bone arm and leg IK. A shared reachable grip control keeps both hands attached. Confirmed hits add 55ms of reduced-speed contact and visible enemy recoil. Locomotion blends to the one-handed trailing sword pose; attacks first recover the second hand. Use the mouse wheel to inspect closer or farther.

<!-- /coderabbit-ai-generated:v1 -->

The current prototype uses rigid mesh parts, not weighted skin animation. Hits use a directional distance check; enemies use simple pursuit and contact damage. Ground movement is constrained to a flat arena, without a full physics controller or pathfinding. The castle is a lightweight reconstruction. No audio assets yet.

## Automated smoke check

`godot --headless --path . -- --smoke-test`

Runs the same draw/attack methods and movement branch with a deterministic scripted input vector. It must end with 3 defeated enemies and exits nonzero otherwise. It is not a manual keyboard playthrough. For a rendered check on Linux: `xvfb-run -a godot --path . --audio-driver Dummy -- --smoke-test --capture` saves a frame under `/tmp/godot-berserk-preview.png`.
