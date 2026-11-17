extends Node2D
## One extra `CanvasItem` used only to give a pass its own `CanvasItemMaterial`.
##
## Godot 4 has no per-draw blend mode (Godot 3's `draw_set_blend_mode` is gone):
## the blend mode belongs to the item. The snake halo and the food glow must be
## **additive** (`globalCompositeOperation='lighter'` on the web), so `PSWorldView`
## adds one of these children with `BLEND_MODE_ADD` and forwards its `_draw` back
## through `host.draw_additive(item)`.
##
## Ordering: a child draws after its parent's own content by default, so the halo
## lands on top of the floor/food/bodies. Geometry is built as the *outer* annulus
## only (`r .. r+15`), which is exactly the part of the web's halo that is never
## covered by its own body — so the two orders agree pixel for pixel, and a
## translucent layer still cannot double over itself.

var host = null


func _process(_dt: float) -> void:
	# The host is redrawn every frame by main.gd; keep both in lockstep.
	if host != null and visible:
		queue_redraw()


func _draw() -> void:
	if host != null:
		host.draw_additive(self)
