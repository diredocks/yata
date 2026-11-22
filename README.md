# YATA (Yet Another Todo App)

A Flutter task management application modeled after Microsoft To Do, featuring multi-account support (local & Microsoft Account cloud sync), smart lists, custom list groups, rich task details, reminders, and Material You dynamic theming.

## Project Structure

```text
lib/
├── account/        # Multi-account state & account management UI
├── auth/           # Microsoft Account OAuth & browser/WebView sign-in
├── data/           # Local storage, TodoState, settings sync patch, and TodoNotifier
├── detailview/     # Task detail view, steps, recurrence pickers, and notes
├── homeview/       # Sidebar/home list navigation, account header, and list groups
├── l10n/           # Localization ARB files (English & Chinese)
├── models/         # Core domain models (Account, TodoList, ListGroup, TaskItem)
├── notifications/  # Local reminder scheduling & snooze bottom sheet
├── onboarding/     # Welcome / account sign-in landing screen
├── search/         # Task search presenter & screen
├── settings/       # Application settings presenter & screen
├── sync/           # Microsoft To Do Substrate API client, wire codecs, & sync engine
├── tasksview/      # Task list screen, batch actions, grouping, and animated slivers
├── theme/          # Color palettes, dynamic theming, and theme picker sheet
└── view/           # Main responsive shell & reusable UI widgets
```

## Development

```bash
# Analyze code
flutter analyze

# Run test suite
flutter test

# Format code
dart format lib test
```
