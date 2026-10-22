# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning.

## [2.0.0] - 2026-10-22

This release is focused on correctness and predictability. The v1 positional API
is still supported, but several failure modes now raise errors instead of being
ignored, so downstream projects should review [MIGRATION.md](MIGRATION.md).

### Added

- `timer.lua` as the canonical module. `init.lua` is now a compatibility shim
  for projects that still `require 'init'`.
- Script handles. `timer.script` now returns an object accepted by
  `cancel`, `pause`, `resume`, `exists`, `remaining`, and `isPaused`, including
  scripts created without a tag.
- Private, untagged wait tasks for scripts. A script's waits no longer collide
  with public tags used by other tasks.
- `timer.exists`, `timer.remaining`, `timer.count`, `timer.isPaused`.
- `timer.setTimeScale`, `timer.getTimeScale`, `timer.pauseAll`, and
  `timer.resumeAll` for pool-wide control.
- `timer.registerEasing` for custom easing functions.
- Function easings are accepted directly by `timer.tween`.
- Easing aliases for case, separators, and direction placement:
  `quadinout`, `in-out-quad`, `easeInOutQuad`, and `backOut` all resolve
  correctly.
- Deterministic same-frame callback ordering (registration order).
- Input validation for delays, ranges, counts, actions, tween tables, `dt`, and
  time scales.
- A busted test suite, Makefile targets, editor/lint/formatter configuration,
  and a GitHub Actions workflow.
- An MIT license and explicit HUMP attribution.
- `CHANGELOG.md` and `MIGRATION.md`.

### Changed

- `tasks` is now an insertion-ordered array with tombstone compaction instead of
  a hash set. This removes per-frame snapshot allocations and fixes callback
  order. Treat it as internal.
- `cancel`, `pause`, and `resume` return booleans.
- `timer.script` returns a handle and no longer stores internal waits under the
  public tag.
- A same-tag timer replaces a script immediately (tag ownership semantics),
  rather than freezing it with a dangling internal wait.
- Completion callbacks no longer run when the task was cancelled by its own
  action, by `clear`, or by a same-tag replacement.
- Unknown easing names raise an error at tween creation rather than silently
  falling back to linear.
- Invalid delay/count/table values raise at the call site rather than later in
  `update`.
- Script errors are re-thrown with a traceback instead of being discarded.
- `wait(nil)` and non-number yields raise errors instead of silently abandoning
  the coroutine.
- Zero-duration tweens complete on the next update; they no longer produce NaN
  on PUC Lua or leave a permanent task behind.
- Task removal uses ownership-aware tag cleanup, so cancelling a stale handle
  cannot clear a newer task's tag.

### Fixed

- Zero, negative, NaN, and infinite tween durations.
- Silent script errors, invalid waits, and abandoned coroutines.
- Completion callbacks running after self-cancellation.
- Script waits sharing the public tag namespace and cancelling unrelated tasks.
- Tag cleanup race when a stale handle was cancelled.
- Malformed `{min, max}` ranges causing arithmetic errors inside `update`.
- Nondeterministic callback order and per-frame table allocations in `update`.
- Misleading easing documentation; the documented aliases now work.
- Tweens snap to the exact endpoint value at completion instead of retaining
  floating-point residue.
- Handles from another pool are rejected by `cancel`, `pause`, `resume`,
  `exists`, `remaining`, and `isPaused` instead of corrupting pool counters.
- NaN tags are rejected with a clear error instead of failing as invalid table
  keys.

### Removed

- The v1 file layout in which the entire library lived in `init.lua`. The file
  remains as a one-line compatibility module.

## [1.0.0] - 2026-06-10

Initial public version based on the original `init.lua` implementation:

- Global and local timer pools.
- `after`, `every`, `during`, `tween`, and coroutine scripts.
- Tag-based replacement, pause/resume, and `clear`.
- Fixed and randomised interval delays, execution counts, and completion
  callbacks.
- Linear, quad, cubic, sine, expo, and back easings.
