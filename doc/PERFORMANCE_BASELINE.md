# vimember Performance Baseline

This file keeps the first profiling pass narrow. Each run should capture one flow only, then compare the same flow after each optimization commit.

## Signposts

- `HomePerformance / Home Appeared`: home view first appeared.
- `HomePerformance / Home Seed Videos`: full sample + bundled seed task.
- `HomePerformance / Home Seed Sample Videos`: sample seed task only.
- `HomePerformance / Home Seed Bundled Videos`: bundled imported video seed task only.
- `HomePerformance / Home Active Video`: delayed home active-video selection fired.
- `HomePerformance / Home Open Import`: plus button opened the import flow.
- `VideoPlayerPerformance / VideoPlayer Configure`: a player surface configured a new URL.
- `VideoPlayerPerformance / VideoPlayer Play`: a player surface started playback.
- `VideoPlayerPerformance / VideoPlayer Pause`: a player surface paused playback.

## Manual Checks

1. Home launch with existing data
   - Start: tap the app icon from a cold launch.
   - Stop: the first home video is visible and starts moving.
   - Watch: time from launch to visible playable video, blank/color-block-only duration, and whether the first playback flashes.

2. Home timeline scroll
   - Start: home timeline is idle with one active video.
   - Action: scroll down and up across at least five videos.
   - Stop: scrolling stops and the main visible video starts.
   - Watch: dropped frames while dragging, any flash before playback, and whether more than one video visibly plays.

3. Detail playback
   - Start: tap a home video.
   - Stop: detail view is open.
   - Watch: video autoplays with sound, loops, progress bar moves, and seek still works.

4. Gallery scroll
   - Start: switch to three-column gallery.
   - Action: scroll through several rows.
   - Stop: gallery is idle.
   - Watch: frame rate, thumbnail popping, and context menu still opening on long press.

5. Import entry
   - Start: home is idle.
   - Action: tap the plus button.
   - Stop: video selection grid is visible.
   - Watch: time until first selectable videos appear and whether selection / next still works.

## Instrument Targets

- Use a Release or Profile build when possible.
- In SwiftUI Instruments, watch for long body updates during home timeline scroll.
- In Time Profiler, compare main-thread samples around `VideoPlayerSurface`, `PlayerSurfaceView`, `AVPlayer`, and SwiftUI layout.
- In Points of Interest, use the signpost names above as start/stop anchors.
