# yata

Yet Another Todo App

[Microsoft is killing Microsoft To Do on June 30, 2027](https://support.microsoft.com/en-au/planner/to-do-to-planner)

## Codegen

Run manually after editing `.arb` or `@freezed` / `@JsonSerializable` / `@DriftDatabase` files, and build the rich-text editor from `editor_web/` before running or packaging:

```bash
flutter gen-l10n
flutter pub run build_runner build
npm --prefix editor_web ci
npm --prefix editor_web run build
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
npm --prefix editor_web run build
```
