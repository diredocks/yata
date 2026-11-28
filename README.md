# yata

Yet Another Todo App

[Microsoft is killing Microsoft To Do on June 30, 2027](https://support.microsoft.com/en-au/planner/to-do-to-planner)

## Layout

Every folder under `lib/` is either a feature or a shared module. A feature owns
everything only it uses; anything used by two or more features belongs to a
shared module.

| Kind | Folders |
| --- | --- |
| Shared modules | `core/` (errors, logging, result, time, network guard, uuid), `models/` (domain types), `data/` (state, persistence, sync seam — grouped into `account/`, `storage/`, `state/`, `tasks/`, `lists/`, `ordering/`, `sync/`, `attachments/`), `sync/` (Microsoft Graph/Substrate engine), `auth/` (token acquisition), `theme/`, `l10n/`, `ui/` (shared widgets plus cross-view presentation helpers) |
| Features | `account/`, `onboarding/`, `homeview/`, `tasksview/`, `detailview/`, `search/`, `settings/`, `notifications/`, `homewidget/` |
| Composition roots | `main.dart`, `app/` (app shell and the headless background entrypoint) |

Rules of thumb:

- Features may depend on shared modules and, for navigation, on another feature's
  screens. They must not reach into another feature's presenter or internals.
- Mutating tasks (create/complete/important/recurrence) goes through
  `data/tasks/task_mutations.dart`; multi-select batch actions belong to the
  tasks view (`tasksview/task_batch_actions.dart`).
- Shared UI used by more than one feature (task tiles, pickers, checkboxes) lives
  in `ui/`, not inside the feature that happened to need it first.
- Data that only one feature consumes stays with that feature; only state,
  persistence and the sync seam are shared. Example: `AttachmentStorage` owns the
  on-disk layout in `data/attachments/` (account deletion needs it), while the
  detail view's `AttachmentService` owns staging/opening files.

## Codegen

Run manually after editing `.arb` or `@freezed` / `@JsonSerializable` / `@DriftDatabase` files:

```bash
flutter gen-l10n
flutter pub run build_runner build
```

## Storage

- **Drift (SQLite)**: Lists, groups, tasks/steps, and sync dirty/deletion queues.
- **SharedPreferences**: Accounts, app/UI settings, active/last list ID, and sync delta links.
- **FlutterSecureStorage**: Microsoft OAuth tokens.

## Dev

```bash
flutter analyze
flutter test
dart format lib test
```
