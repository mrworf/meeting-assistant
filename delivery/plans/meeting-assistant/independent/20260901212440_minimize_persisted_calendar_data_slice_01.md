# Slice 01: Persist Only Derived Meetings

## Goal and Outcome

After synchronization, Meeting Assistant persists only the meeting fields required to restore its menu, reminder panels, participant labels, and Join action. Raw Calendar API fields are discarded after in-memory qualification, and any legacy raw cache is erased on first load.

## Scope

- Replace raw events in `CalendarSnapshot` with derived meetings keyed by the stable Google occurrence key.
- Preserve full and incremental sync behavior, including cancellation, qualification changes, reschedules, pagination, and sync-token recovery.
- Migrate by invalidating and deleting schema-v2 or undecodable snapshots.
- Add positive and negative persistence/synchronization tests and update the storage disclosure.

## Non-Scope

- Encryption or relocation of the minimized cache.
- Changes to the Google API DTO, meeting qualification rules, UI, OAuth, networking, or reminder behavior.
- Changes to the historical security report for commit `0f31479`.

## Dependencies and Ordering

This is the only slice. The snapshot type and synchronization transaction must change atomically because cached startup and incremental updates share the same stored representation.

## End-to-End Behavior and State Transitions

1. Google Calendar pages decode to full `GoogleCalendarEvent` values in memory.
2. For each response event, compute the stable storage key from event ID and original/current occurrence start.
3. Remove the previously cached derived meeting at that key.
4. If the event is not cancelled and still qualifies, store its `QualifyingMeeting`; otherwise leave it absent.
5. Save the minimized snapshot with sync metadata after all pages succeed.
6. On startup, return the stored derived meetings directly.
7. On schema mismatch or decode failure, delete snapshot data and version metadata, load an empty snapshot, and perform a full sync when connectivity permits.

## Authorization and Permissions

No authorization behavior changes. Google access remains read-only, and cache access remains under the current macOS user-defaults domain.

## Validation and Recovery

- Do not commit a partial pagination result; retain the existing in-memory transaction and save only after all pages succeed.
- Cancellation and unqualified updates must remove stale cached reminders.
- Legacy or corrupt cache deletion is immediate and idempotent.
- A failed first post-upgrade refresh leaves an empty cache and recovers on the next successful refresh.

## Implementation Surfaces

- `Sources/MeetingAssistantCore/CalendarSyncEngine.swift`
- `Tests/MeetingAssistantCoreTests/GoogleServicesTests.swift`
- `README.md`

## Tests and Commands

- Positive: qualifying event persists as an equivalent `QualifyingMeeting` and restores through `cachedMeetings()`.
- Negative: sentinel values in unused raw fields are absent from serialized snapshot data.
- Negative: cancellation and qualification loss remove an existing cached meeting.
- Replacement: a rescheduled recurring occurrence replaces the stable cache entry without duplication.
- Migration: schema-v2 and malformed snapshots are deleted; schema-v3 round-trips.
- Regression: expired sync-token recovery remains passing.
- Required commands: `swift test --disable-sandbox`, then `./scripts/build-app.sh`; if unavailable off macOS, perform static checks and rely on macOS CI for executable validation.

## Acceptance Criteria

- No persisted snapshot property contains `GoogleCalendarEvent`.
- Existing visible behavior is unchanged online and across offline relaunches.
- Old raw snapshots are removed rather than merely ignored.
- Incremental updates cannot leave stale cancelled or newly unqualified meetings.
- Focused and full validation pass, or platform limitations are explicitly recorded before commit.

## Commit Boundary

Commit the governing plan, this slice plan, sync implementation, tests, and README together as one independently revertible change. Exclude the pre-existing untracked `SECURITY_REVIEW.md`.

## Delivery Result

- Static validation passed: `git diff --check`, stale snapshot-property reference scan, and persisted-model boundary scan.
- `swift test --disable-sandbox` could not start because `swift` is not installed on this Linux host (exit 127).
- `./scripts/build-app.sh` could not start because `/bin/zsh` is unavailable on this Linux host (exit 126).
- The added macOS tests and universal build remain required CI validation when the commit reaches GitHub.
- Commit provenance is the commit that first adds this slice plan; resolve it with `git log --diff-filter=A --format=%H -- delivery/plans/meeting-assistant/independent/20260901212440_minimize_persisted_calendar_data_slice_01.md`.
