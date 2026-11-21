import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';

/// Bottom sheet matching `theme_picker_bottom_sheet.xml` (`customizations/ThemePickerBottomSheet`).
Future<void> showThemePickerBottomSheet({
  required BuildContext context,
  required ListThemeColor currentColor,
  ListThemePhoto? currentPhoto,
  required void Function(ListThemeColor color, ListThemePhoto? photo)
      onSelectTheme,
}) async {
  final l10n = AppLocalizations.of(context);
  var selectedColor = currentColor;
  var selectedPhoto = currentPhoto;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
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
                            ? TodoColors.secondaryTextDark
                                .withValues(alpha: 0.4)
                            : TodoColors.secondaryTextLight
                                .withValues(alpha: 0.35),
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
                      onSelectTheme: (color, photo) {
                        setModalState(() {
                          selectedColor = color;
                          selectedPhoto = photo;
                        });
                        onSelectTheme(color, photo);
                      },
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
}

/// Horizontal theme picker matching `theme_picker_view.xml` (`customizations/ThemePickerView`).
class ThemePickerView extends StatefulWidget {
  const ThemePickerView({
    super.key,
    required this.selectedColor,
    this.selectedPhoto,
    required this.onSelectTheme,
  });

  final ListThemeColor selectedColor;
  final ListThemePhoto? selectedPhoto;
  final void Function(ListThemeColor color, ListThemePhoto? photo)
      onSelectTheme;

  @override
  State<ThemePickerView> createState() => _ThemePickerViewState();
}

class _ThemePickerViewState extends State<ThemePickerView> {
  late bool _showPhotos;

  @override
  void initState() {
    super.initState();
    _showPhotos = widget.selectedPhoto != null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChoiceChip(
              label: Text(l10n.themeTabColor),
              selected: !_showPhotos,
              onSelected: (_) => setState(() => _showPhotos = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(l10n.themeTabPhoto),
              selected: _showPhotos,
              onSelected: (_) => setState(() => _showPhotos = true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !_showPhotos
                ? ListView.separated(
                    key: const ValueKey('theme_colors_list'),
                    scrollDirection: Axis.horizontal,
                    itemCount: ListThemeColor.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final color = ListThemeColor.values[index];
                      final isSelected = widget.selectedPhoto == null &&
                          widget.selectedColor == color;
                      return Center(
                        child: GestureDetector(
                          onTap: () => widget.onSelectTheme(color, null),
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
                              border: isSelected
                                  ? Border.all(
                                      color: theme.colorScheme.onSurface,
                                      width: 2.5,
                                    )
                                  : (TodoColors.isLightTheme(color) &&
                                          theme.brightness == Brightness.light
                                      ? Border.all(
                                          color: TodoColors.accentFor(color)
                                              .withValues(alpha: 0.45),
                                          width: 1,
                                        )
                                      : null),
                            ),
                            child: AnimatedScale(
                              scale: isSelected ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutBack,
                              child: Icon(
                                Icons.check,
                                size: 18,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.black
                                    : (TodoColors.isLightTheme(color)
                                        ? TodoColors.accentFor(color)
                                        : Colors.white),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : ListView.separated(
                    key: const ValueKey('theme_photos_list'),
                    scrollDirection: Axis.horizontal,
                    itemCount: ListThemePhoto.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final photo = ListThemePhoto.values[index];
                      final isSelected = widget.selectedPhoto == photo;
                      return Center(
                        child: GestureDetector(
                          key: ValueKey('photo_theme_${photo.name}'),
                          onTap: () =>
                              widget.onSelectTheme(widget.selectedColor, photo),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 2.5,
                                    )
                                  : null,
                              image: DecorationImage(
                                image:
                                    AssetImage(TodoColors.photoAssetFor(photo)),
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: Center(
                              child: AnimatedScale(
                                scale: isSelected ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOutBack,
                                child: const Icon(
                                  Icons.check,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
