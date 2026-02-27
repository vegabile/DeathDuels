Overview
A plot-based building system for Roblox where players can select objects from a UI menu, preview and place them onto a snappable grid, and persist their builds across sessions. The system supports multi-floor construction, surface placement (objects on other objects), and a freecam for navigation.

Core Mechanics:
Wall Construction:
Walls use a drag-to-place input mode. The player clicks to set a start point, drags to set an end point, and the system fills the gap with wall segments snapped to the grid along an axis-aligned line. The place in between will become the wall, the client can either draw straight or diagonally, compliant with the grid. The client handles the drag state machine and renders a live ghost preview during the drag. On release, the start and end points are sent to WallService, which computes segment positions, validates them against CollisionService, and batch-writes to the Central Object Repository if legal, when the client lets go. Walls are tagged as a distinct category so other objects (e.g., furniture) cannot clip through or overhang past them.

Plot System:
Plots are essentially a pre-defined chunk of land, NxN grid, where the player can construct. All land inside the plot is their land. The plot saves, loads, etc.

- Each plot is owned by exactly one player. Ownership is assigned on join or claim.
- Plot bounds are defined by a center point, X size, and Z size. Nothing can be placed outside these bounds.
- The plot holds a reference to its GridModule, which handles all snap logic within the bounds.
- The plot owns a Repository instance containing all PlacedObjects on it.
- Plots are independent — objects on one plot have no interaction with objects on another.
- On save, the entire Repository (list of PlacedObjects) is serialized and written to DataStore.
- On load, the saved data is deserialized, validated, and the objects are spawned back in.
- If a plot has no owner (player leaves), it can be cleared or held depending on config.
- Plot state (empty, building, saved) should be trackable for future features like visiting other players' plots.

Camera System:
The camera is a free-moving view that the player controls while in build mode. WASD moves 
the camera relative to the direction it's currently facing. Holding Shift slows movement 
for precision. Right mouse button held with mouse movement pans and tilts the view, with 
tilt clamped to prevent flipping. Q and E snap-rotate the camera by a configurable angle. 
Scroll wheel zooms in and out within a clamped range. Page Up and Page Down step between 
elevation levels for multi-floor building. Holding Space gives a temporary top-down view 
that releases back to the previous angle. The camera is bounded to the plot area and cannot 
pan outside it. Movement is slightly smoothed rather than instant. The camera passes through 
placed objects with no collision. All controls, speeds, zoom limits, elevation levels, and 
lerp parameters are configurable. Keybinds are defined per device (PC, Console, Mobile) and 
injected at runtime based on detected input type.