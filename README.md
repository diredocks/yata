# yata

Yet Another Todo App

[Microsoft is killing Microsoft To Do on June 30, 2027](https://support.microsoft.com/en-au/planner/to-do-to-planner)

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

## Logs

```dart
final _log = appLogFor('SyncEngine');
_log.info('Phase 10b items=3');
_log.fine('Phase 10b task ...');                 // needs Logger.root.level = Level.ALL
_log.warning('patch failed', error, stackTrace);
```

Repeated lines print once per 3s and report as `(xN)`.
