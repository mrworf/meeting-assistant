# Minimize Persisted Calendar Data

## Summary

Replace the raw Google Calendar event cache with a minimal cache of derived `QualifyingMeeting` records. Preserve current reminders, participant display, Join behavior, incremental synchronization, and offline startup behavior while removing unused calendar details from persistent storage.

## Implementation Changes

- Change `CalendarSnapshot.events: [String: GoogleCalendarEvent]` to `meetings: [String: QualifyingMeeting]`.
- Decode full `GoogleCalendarEvent` objects only in memory during API synchronization.
- For each incremental event, remove its previous stable occurrence entry, then retain only a newly qualified meeting when the event remains active and qualifying.
- Return cached meetings directly without requalifying raw events.
- Persist only event/occurrence IDs, title, start/end, action URL/type, and participant display strings.
- Increment the snapshot schema version. On mismatch or decoding failure, immediately delete the old snapshot and force a full synchronization.
- Update the README storage disclosure. Keep `SECURITY_REVIEW.md` unchanged as the historical review of commit `0f31479`.

## Interface Changes

- Rename the public `CalendarSnapshot.events` property and initializer argument to `meetings`.
- Keep `GoogleCalendarEvent` as the in-memory Calendar API DTO.
- Make no UI, OAuth, network, reminder-policy, or Google API contract changes.

## Test Plan

- Verify the stored snapshot round-trips every field required by reminders, menus, participant display, and Join actions.
- Prove unused descriptions, locations, organizer/attendee metadata, and conference payloads never appear in serialized storage.
- Verify incremental cancellation, newly unqualified events, and removed join links delete prior cached meetings.
- Verify rescheduled recurring occurrences replace prior cached values without duplication.
- Verify schema-v2 and corrupt snapshots are deleted and force a full synchronization.
- Preserve expired-sync-token recovery, cached startup, disconnect clearing, pagination, and qualification behavior.
- Run `swift test --disable-sandbox` and `./scripts/build-app.sh` on macOS; record the platform limitation when unavailable.

## Assumptions

- Offline launches retain current reminder behavior through the minimal cache.
- Titles, participant display strings, and actionable URLs remain because the existing UI requires them.
- The first launch after upgrading discards the legacy raw cache; if offline, meetings remain empty until synchronization succeeds.

## Slice Index

- [Slice 01: Persist only derived meetings](20260901212440_minimize_persisted_calendar_data_slice_01.md)
