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

## Rich Text Editor (Frontend Assets)

The rich-text note editor (`assets/editor/index.html`) is built from `editor_web/` (Tiptap + DOMPurify bundled via Vite as a single offline HTML file). Build artifacts are not committed to the repository, so build them before running or packaging the Flutter app:

```bash
cd editor_web
npm ci
npm run build
```
