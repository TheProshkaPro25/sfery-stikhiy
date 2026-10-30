# Local integration for Сферы Стихий 0.2.8

Upstream: alien-life/gpu-cloth-sim 3.0.0, MIT (see LICENSE).

- Accept custom render shaders exposing the seven v3 substrate uniforms rather
  than restricting compatibility to two hardcoded resource paths. The game's
  cloth shader shares its fragment/light code with the native anime material.
- Extract the strongest four normalized influences when ingesting an eight-weight
  body for collision fitting. Body rendering retains all eight; separately
  authored cape meshes have four influences. Simulated cape geometry is excluded
  from its body collider.
- Reset against current bone/collider data after hiding, teleporting or resetting
  the actor; skip hidden cloth and clamp the simulation frame interval.
- Free uniform sets before their buffers/shaders and detach Texture2DRD wrappers
  before freeing image storage. This fixes invalid-RID errors on Godot 4.7.2.

The editor plugin need not be enabled to instantiate the runtime classes.
`scenes/creature_cloth.gd` configures the solver, body proxy and ground box.
`tools/cloth_review.gd` verifies actual GPU output and lifecycle operations.
Without a RenderingDevice the game retains native cape skinning.
