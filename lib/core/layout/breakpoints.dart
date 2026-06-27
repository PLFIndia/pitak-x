/// Responsive layout breakpoints (single source of truth).
///
/// Layout decisions key off the *available window width* (the constraints a
/// parent hands down), never the physical device or orientation — Flutter apps
/// run resized, split-screen, and on foldables where "is this a tablet?" is the
/// wrong question. See the adaptive-layout guidance: base everything on
/// `LayoutBuilder` constraints / `MediaQuery.sizeOf`, not hardware type.
library;

/// Width (logical px) at or above which a layout is treated as "large".
///
/// 600 is the conventional phone↔tablet boundary used by Material's window
/// size classes. Below it we show the single-column library list; at or above
/// it we switch to the multi-column cover grid.
const double largeScreenMinWidth = 600;
