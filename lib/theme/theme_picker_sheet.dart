import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import 'custom_background_service.dart';
import 'todo_theme.dart';

enum _ThemeTab { color, photo, custom }

/// Picks a gallery image, validates its size, saves it without compression,
/// and registers it in [todoProvider]. Returns the saved file path on success,
/// or `null` if cancelled or failed.
Future<String?> pickAndSaveCustomBackground({
  required BuildContext context,
  required WidgetRef ref,
  Future<XFile?> Function()? pickImage,
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    final picked = await (pickImage != null
        ? pickImage()
        : ImagePicker().pickImage(source: ImageSource.gallery));
    if (picked == null) return null;
    final accountKey = ref.read(todoSettingsStoreProvider).accountKey;
    final saved = await ref
        .read(customBackgroundServiceProvider)
        .savePickedImage(picked, accountKey: accountKey);
    ref.read(todoProvider.notifier).addCustomBackground(saved);
    return saved.filePath;
  } on CustomBackgroundTooLargeException {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(l10n.customBackgroundTooLargeError),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.done),
            ),
          ],
        ),
      );
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(l10n.customBackgroundFailedError),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.done),
            ),
          ],
        ),
      );
    }
    return null;
  }
}

/// Prompts the user to confirm deleting [background] and removes it if confirmed.
Future<bool> confirmAndDeleteCustomBackground({
  required BuildContext context,
  required WidgetRef ref,
  required CustomBackground background,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deleteCustomBackgroundTitle),
      content: Text(l10n.deleteCustomBackgroundMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  ref.read(todoProvider.notifier).deleteCustomBackground(background);
  return true;
}

/// Bottom sheet matching `theme_picker_bottom_sheet.xml` (`customizations/ThemePickerBottomSheet`).
Future<void> showThemePickerBottomSheet({
  required BuildContext context,
  required ListThemeColor currentColor,
  ListThemePhoto? currentPhoto,
  String? currentCustomBackgroundPath,
  required void Function(
    ListThemeColor color,
    ListThemePhoto? photo,
    String? customBackgroundPath,
  )
  onSelectTheme,
  Future<XFile?> Function()? pickImage,
}) async {
  final l10n = AppLocalizations.of(context);
  var selectedColor = currentColor;
  var selectedPhoto = currentPhoto;
  var selectedCustomBackgroundPath = currentCustomBackgroundPath;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return Consumer(
        builder: (context, ref, _) {
          final customBackgrounds = ref.watch(
            todoProvider.select((s) => s.customBackgrounds),
          );
          return StatefulBuilder(
            builder: (context, setModalState) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

              Future<void> handleAddCustom() async {
                final savedPath = await pickAndSaveCustomBackground(
                  context: context,
                  ref: ref,
                  pickImage: pickImage,
                );
                if (savedPath == null) return;
                if (context.mounted) {
                  setModalState(() {
                    selectedPhoto = null;
                    selectedCustomBackgroundPath = savedPath;
                  });
                }
                onSelectTheme(selectedColor, null, savedPath);
              }

              Future<void> handleDeleteCustom(CustomBackground bg) async {
                final deleted = await confirmAndDeleteCustomBackground(
                  context: context,
                  ref: ref,
                  background: bg,
                );
                if (deleted &&
                    selectedCustomBackgroundPath == bg.filePath &&
                    context.mounted) {
                  setModalState(() {
                    selectedCustomBackgroundPath = null;
                  });
                }
              }

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? TodoColors.secondaryTextDark.withValues(
                                    alpha: 0.4,
                                  )
                                : TodoColors.secondaryTextLight.withValues(
                                    alpha: 0.35,
                                  ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          l10n.theme,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ThemePickerView(
                          selectedColor: selectedColor,
                          selectedPhoto: selectedPhoto,
                          selectedCustomBackgroundPath:
                              selectedCustomBackgroundPath,
                          customBackgrounds: customBackgrounds,
                          onSelectTheme: (color, photo, customPath) {
                            setModalState(() {
                              selectedColor = color;
                              selectedPhoto = photo;
                              selectedCustomBackgroundPath = customPath;
                            });
                            onSelectTheme(color, photo, customPath);
                          },
                          onAddCustomBackground: handleAddCustom,
                          onDeleteCustomBackground: handleDeleteCustom,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// Horizontal theme picker matching `theme_picker_view.xml` (`customizations/ThemePickerView`).
class ThemePickerView extends StatefulWidget {
  const ThemePickerView({
    super.key,
    required this.selectedColor,
    this.selectedPhoto,
    this.selectedCustomBackgroundPath,
    this.customBackgrounds = const [],
    required this.onSelectTheme,
    this.onAddCustomBackground,
    this.onDeleteCustomBackground,
  });

  final ListThemeColor selectedColor;
  final ListThemePhoto? selectedPhoto;
  final String? selectedCustomBackgroundPath;
  final List<CustomBackground> customBackgrounds;
  final void Function(
    ListThemeColor color,
    ListThemePhoto? photo,
    String? customBackgroundPath,
  )
  onSelectTheme;
  final VoidCallback? onAddCustomBackground;
  final void Function(CustomBackground background)? onDeleteCustomBackground;

  @override
  State<ThemePickerView> createState() => _ThemePickerViewState();
}

class _ThemePickerViewState extends State<ThemePickerView> {
  late _ThemeTab _activeTab;

  @override
  void initState() {
    super.initState();
    if (widget.selectedCustomBackgroundPath != null) {
      _activeTab = _ThemeTab.custom;
    } else if (widget.selectedPhoto != null) {
      _activeTab = _ThemeTab.photo;
    } else {
      _activeTab = _ThemeTab.color;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: Text(l10n.themeTabColor),
              selected: _activeTab == _ThemeTab.color,
              onSelected: (_) => setState(() => _activeTab = _ThemeTab.color),
            ),
            ChoiceChip(
              label: Text(l10n.themeTabPhoto),
              selected: _activeTab == _ThemeTab.photo,
              onSelected: (_) => setState(() => _activeTab = _ThemeTab.photo),
            ),
            if (widget.onAddCustomBackground != null ||
                widget.customBackgrounds.isNotEmpty)
              ChoiceChip(
                label: Text(l10n.themeTabCustom),
                selected: _activeTab == _ThemeTab.custom,
                onSelected: (_) =>
                    setState(() => _activeTab = _ThemeTab.custom),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: switch (_activeTab) {
              _ThemeTab.color => ListView.separated(
                key: const ValueKey('theme_colors_list'),
                scrollDirection: Axis.horizontal,
                itemCount: ListThemeColor.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final color = ListThemeColor.values[index];
                  final isSelected =
                      widget.selectedCustomBackgroundPath == null &&
                      widget.selectedPhoto == null &&
                      widget.selectedColor == color;
                  final dotColor = theme.brightness == Brightness.dark
                      ? Colors.black
                      : (TodoColors.isLightTheme(color)
                            ? TodoColors.accentFor(color)
                            : Colors.white);
                  return Center(
                    child: GestureDetector(
                      key: ValueKey('color_theme_${color.name}'),
                      onTap: () => widget.onSelectTheme(color, null, null),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: TodoColors.swatchColorFor(
                            color,
                            brightness: theme.brightness,
                          ),
                          shape: BoxShape.circle,
                          border:
                              TodoColors.isLightTheme(color) &&
                                  theme.brightness == Brightness.light
                              ? Border.all(
                                  color: TodoColors.accentFor(color)
                                      .withValues(alpha: 0.45),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: _SelectionDot(
                          visible: isSelected,
                          color: dotColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
              _ThemeTab.photo => ListView.separated(
                key: const ValueKey('theme_photos_list'),
                scrollDirection: Axis.horizontal,
                itemCount: ListThemePhoto.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final photo = ListThemePhoto.values[index];
                  final isSelected =
                      widget.selectedCustomBackgroundPath == null &&
                      widget.selectedPhoto == photo;
                  return Center(
                    child: GestureDetector(
                      key: ValueKey('photo_theme_${photo.name}'),
                      onTap: () => widget.onSelectTheme(
                        widget.selectedColor,
                        photo,
                        null,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(
                            image: AssetImage(TodoColors.photoAssetFor(photo)),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: _SelectionDot(
                          visible: isSelected,
                          color: Colors.white,
                          withShadow: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
              _ThemeTab.custom => _CustomThemeList(
                key: const ValueKey('theme_custom_list'),
                customBackgrounds: widget.customBackgrounds,
                selectedCustomBackgroundPath:
                    widget.selectedCustomBackgroundPath,
                onAdd: widget.onAddCustomBackground,
                onSelect: (bg) => widget.onSelectTheme(
                  widget.selectedColor,
                  null,
                  bg.filePath,
                ),
                onDelete: widget.onDeleteCustomBackground,
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _CustomThemeList extends StatelessWidget {
  const _CustomThemeList({
    super.key,
    required this.customBackgrounds,
    required this.selectedCustomBackgroundPath,
    this.onAdd,
    required this.onSelect,
    this.onDelete,
  });

  final List<CustomBackground> customBackgrounds;
  final String? selectedCustomBackgroundPath;
  final VoidCallback? onAdd;
  final void Function(CustomBackground background) onSelect;
  final void Function(CustomBackground background)? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final hasAddButton = onAdd != null;
    final totalCount = customBackgrounds.length + (hasAddButton ? 1 : 0);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: totalCount,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        if (hasAddButton && index == 0) {
          return Center(
            child: Tooltip(
              message: l10n.addCustomBackground,
              child: GestureDetector(
                key: const ValueKey('add_custom_background_button'),
                onTap: onAdd,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.06),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        }

        final bg = customBackgrounds[index - (hasAddButton ? 1 : 0)];
        final isSelected = selectedCustomBackgroundPath == bg.filePath;
        return Center(
          child: GestureDetector(
            key: ValueKey('custom_theme_${bg.id}'),
            onTap: () => onSelect(bg),
            onLongPress: onDelete != null ? () => onDelete!(bg) : null,
            child: ClipOval(
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(bg.filePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: isDark ? Colors.white12 : Colors.black12,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    _SelectionDot(
                      visible: isSelected,
                      color: Colors.white,
                      withShadow: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({
    required this.visible,
    required this.color,
    this.withShadow = false,
  });

  final bool visible;
  final Color color;
  final bool withShadow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: withShadow
                ? const [BoxShadow(color: Color(0x40000000), blurRadius: 2)]
                : null,
          ),
        ),
      ),
    );
  }
}
