# Fix Declined Organizer Reminders and Popup Dragging

## Summary

Do not remind an organizer who explicitly declined their own meeting, and restore reliable popup dragging on macOS Golden Gate while preserving button interactions and saved per-display positions.

## Implementation Changes

- Check the self-attendee RSVP before automatically qualifying an organizer-owned event. Reject an explicit `declined` response while retaining the existing hosted-meeting behavior for all other or missing statuses.
- Preserve the accepted-only rule for meetings organized by someone else.
- Explicitly make reminder panels movable and add an AppKit-backed drag surface over the non-interactive countdown region on Golden Gate.
- Preserve meeting actions, clamping, per-display position persistence, multi-Space behavior, and the existing visual design.

## Interface Changes

- No public API, model, persistence schema, or user-facing configuration changes.

## Test Plan

- Cover declined and non-declined organizer RSVP states in meeting qualification tests.
- Verify an incremental organizer-declined update removes a cached reminder.
- Run the complete Swift test suite and application build on macOS.
- Manually confirm countdown dragging, button clicks, position restoration, and multi-display behavior on Golden Gate.

## Assumptions

- Only an explicit organizer response of `declined` suppresses a hosted meeting.
- Interactive meeting rows remain click targets; the countdown region is the drag target.
- Existing saved popup positions remain valid.

## Slice Index

- [Slice 01: Respect organizer declines and restore popup dragging](20261020153616_fix_declined_organizer_and_popup_dragging_slice_01.md)
