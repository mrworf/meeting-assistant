# Slice 01: Respect Organizer Declines and Restore Popup Dragging

## Goal and Outcome

An organizer who explicitly declines their own meeting receives no menu entry or reminder, and users on macOS Golden Gate can again drag reminder popups from non-interactive regions without breaking Join or Open Event actions.

## Scope

- Refine organizer meeting qualification using the current calendar's self-attendee response.
- Remove a previously qualified organizer meeting during incremental sync after it becomes declined.
- Make borderless nonactivating reminder panels explicitly movable.
- Add an explicit AppKit-backed window-drag surface to the non-interactive countdown region.
- Add positive and negative regression coverage for qualification and synchronization.

## Non-Scope

- Changes to external-invitation acceptance rules.
- New popup controls, drag handles, appearance, resizing, or user preferences.
- Changes to panel placement, clamping, saved-position keys, or persistence schemas.
- Changes to reminder timing, Calendar API requests, OAuth, or meeting actions.

## Dependencies and Ordering

This is the only slice. The qualification rule and incremental-sync regression belong in the same transaction so a response update cannot leave a stale reminder. The panel configuration and hosting-view compatibility fix are independent at runtime but ship in the same requested bug-fix release.

## End-to-End Behavior and State Transitions

1. Qualification locates the attendee entry whose `self` field is true.
2. For an organizer-owned event, an explicit `declined` response fails qualification; every other or absent response preserves hosted-meeting qualification.
3. For a non-organizer event, only an explicit `accepted` self response qualifies, as before.
4. During incremental sync, the stable occurrence entry is removed before requalification, so an organizer decline removes an existing cached meeting.
5. Each reminder panel is explicitly movable, and mouse-down events in the countdown region initiate normal AppKit window dragging.
6. Interactive SwiftUI meeting buttons continue consuming their own clicks; successful moves continue through `windowDidMove`, clamping, and saved per-display coordinates.

## Authorization and Permissions

No authorization or permission behavior changes. Calendar access remains read-only, and popup movement uses existing AppKit window APIs without additional macOS permissions.

## Validation and Recovery

- Missing attendee arrays or self-attendee entries must not suppress organizer-owned meetings.
- `tentative` and `needsAction` continue qualifying for organizers but not for external invitations.
- A declined organizer event must not remain in the minimized snapshot after an incremental response.
- Dragging must not convert meeting action clicks into window movement.
- Saved positions continue to be clamped to the current screen's visible frame and restored after the popup returns.

## Implementation Surfaces

- `Sources/MeetingAssistantCore/MeetingQualification.swift`
- `Sources/MeetingAssistant/AlertPanels.swift`
- `Tests/MeetingAssistantCoreTests/MeetingQualificationTests.swift`
- `Tests/MeetingAssistantCoreTests/GoogleServicesTests.swift`

## Tests and Commands

- Positive: organizer meetings with `accepted`, `tentative`, `needsAction`, missing status, or no self-attendee continue to qualify.
- Negative: an organizer meeting with self status `declined` does not qualify.
- Regression: non-organizer invitations remain accepted-only.
- Synchronization: an initially qualified hosted meeting disappears from the cached snapshot after an incremental declined response.
- Static panel check: the panel is explicitly movable and the countdown drag surface hands mouse-down events to AppKit window dragging.
- Required commands: `swift test --disable-sandbox`, then `./scripts/build-app.sh`; when unavailable in the local environment, run static checks and record the macOS CI/manual validation still required.

## Acceptance Criteria

- Declined hosted meetings never produce or retain a `QualifyingMeeting`.
- Hosted meetings with every non-declined or missing self response preserve existing behavior.
- External invitations still require `accepted`.
- Countdown-region dragging is configured explicitly rather than relying on Golden Gate defaults.
- Join and Open Event buttons retain normal click behavior.
- Position persistence and multi-display behavior are unchanged.
- Required validation passes, or environmental limitations are precisely recorded before commit.

## Commit Boundary

Commit the governing plan, this slice plan, both implementation fixes, and their tests together as one independently revertible change. Exclude all unrelated work.

## Delivery Result

- Implemented explicit organizer-decline qualification and incremental removal coverage.
- Implemented an explicit movable panel plus AppKit countdown drag surface, leaving meeting action rows outside the drag target.
- Static validation passed: `git diff --check`, qualification-rule scans, panel drag-configuration scans, and regression-test presence scans.
- `swift test --disable-sandbox` could not start because `swift` is not installed on this Linux host (exit 127).
- `./scripts/build-app.sh` could not start because `/bin/zsh` is unavailable on this Linux host (exit 126).
- macOS CI and manual Golden Gate drag/button/position checks remain required executable validation.
- Commit provenance is the commit that first adds this slice plan and can be resolved with `git log --diff-filter=A --format=%H -- delivery/plans/meeting-assistant/independent/20261020153616_fix_declined_organizer_and_popup_dragging_slice_01.md`.
