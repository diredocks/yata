import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/data/todo_settings_sync.dart';
import 'package:yata/data/todo_state.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_models.dart';
import 'package:yata/sync/microsoft/substrate_sync_mappers.dart';

void main() {
  test('mergeFoldersDelta clears customBackgroundPath when remote theme changes and preserves it otherwise', () {
    const localList = TodoList(
      id: 'list_1',
      title: 'Work',
      remoteId: 'remote_1',
      themeColor: ListThemeColor.blue,
      customBackgroundPath: '/tmp/custom.jpg',
    );

    final renamedOnly = mergeFoldersDelta(
      localLists: const [localList],
      remoteDelta: const [
        RemoteTodoFolder(
          id: 'remote_1',
          name: 'Work Renamed',
          themeColor: 'dark_blue',
        ),
      ],
      dirtyListIds: const {},
      groupLocalIdByRemoteId: const {},
      idGenerator: (p) => '${p}_new',
    );
    expect(renamedOnly.single.title, 'Work Renamed');
    expect(renamedOnly.single.customBackgroundPath, '/tmp/custom.jpg');

    final themeChanged = mergeFoldersDelta(
      localLists: const [localList],
      remoteDelta: const [
        RemoteTodoFolder(id: 'remote_1', name: 'Work', themeColor: 'dark_red'),
      ],
      dirtyListIds: const {},
      groupLocalIdByRemoteId: const {},
      idGenerator: (p) => '${p}_new',
    );
    expect(themeChanged.single.themeColor, ListThemeColor.red);
    expect(themeChanged.single.customBackgroundPath, isNull);
  });

  test('applySyncedSettingsPatch clears smart list customBackgroundPath when remote theme changes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = TodoSettingsStore(prefs);
    const myDay = TodoList(
      id: 'my_day',
      title: 'My Day',
      smartType: SmartListType.myDay,
      themeColor: ListThemeColor.blue,
      customBackgroundPath: '/tmp/custom_myday.jpg',
    );
    final state = TodoState(
      lists: [myDay],
      groups: const [],
      tasks: const [],
      selectedListId: myDay.id,
    );

    final unchanged = applySyncedSettingsPatch(
      settings: store,
      current: state,
      snapshot: null,
      patch: const SyncedSettingsPatch(
        smartListPatches: {
          'my_day': SmartListSettingsPatch(
            hasTheme: true,
            themeColor: ListThemeColor.blue,
            clearThemePhoto: true,
          ),
        },
      ),
      lists: [myDay],
      dirtySettings: const {},
    );
    expect(
      unchanged.lists.single.customBackgroundPath,
      '/tmp/custom_myday.jpg',
    );

    final changed = applySyncedSettingsPatch(
      settings: store,
      current: state,
      snapshot: null,
      patch: const SyncedSettingsPatch(
        smartListPatches: {
          'my_day': SmartListSettingsPatch(
            hasTheme: true,
            themeColor: ListThemeColor.green,
            clearThemePhoto: true,
          ),
        },
      ),
      lists: [myDay],
      dirtySettings: const {},
    );
    expect(changed.lists.single.themeColor, ListThemeColor.green);
    expect(changed.lists.single.customBackgroundPath, isNull);
  });
}
