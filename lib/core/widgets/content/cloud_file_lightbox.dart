import 'package:auto_route/auto_route.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:photo_view/photo_view.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/utils/file_types.dart';
import 'package:solwatt/core/widgets/content/cloud_file_actions_sheet.dart';
import 'package:solwatt/core/widgets/content/file_viewer_contents.dart';
import 'package:solwatt/route.dart';

/// Opens a Drive file where it reads best.
///
/// Images open in [CloudFileLightbox] — zoomable, and swipeable through the
/// other images of [gallery] — while every other type opens the Drive file
/// detail page, which is the only surface that can play, unpack or describe
/// it. [workspaceId] must match the files' workspace or the gateway cannot
/// resolve them; [gallery] entries the lightbox cannot show are ignored.
void openCloudFile(
  BuildContext context,
  IDisplayableCloudFile file, {
  List<IDisplayableCloudFile> gallery = const [],
  String? workspaceId,
}) {
  if (isImageFile(file)) {
    final images = gallery.where(isImageFile).toList(growable: false);
    final index = images.indexWhere((item) => item.id == file.id);
    context.pushTransparentRoute(
      CloudFileLightbox(
        items: index == -1 ? [file] : images,
        initialIndex: index == -1 ? 0 : index,
        workspaceId: workspaceId,
      ),
      rootNavigator: true,
    );
    return;
  }
  context.router.push(FileDetailRoute(id: file.id));
}

/// Full-screen viewer for image attachments.
///
/// The image itself is the Drive viewer's [ImageFileContent], so zoom, rotate,
/// quality switching and EXIF read exactly as they do in the file detail
/// screen; this adds the lightbox frame around it: a black backdrop, one image
/// per page, chrome that toggles on tap, and dismissal by swipe down, Escape
/// or the close button.
class CloudFileLightbox extends HookConsumerWidget {
  const CloudFileLightbox({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.workspaceId,
  });

  /// Images to show. Entries that are not images are skipped by
  /// [openCloudFile]; passing one here shows a broken page.
  final List<IDisplayableCloudFile> items;
  final int initialIndex;
  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    final index = useState(initialIndex);
    final showControls = useState(true);
    final zoomed = useState(false);

    final pageController = useMemoized(
      () => PageController(initialPage: initialIndex),
      const [],
    );
    final scaleControllers = useMemoized(
      () =>
          List.generate(items.length, (_) => PhotoViewScaleStateController()),
      [items.length],
    );
    useEffect(() {
      return () {
        pageController.dispose();
        for (final controller in scaleControllers) {
          controller.dispose();
        }
      };
    }, [pageController, scaleControllers]);

    // A zoomed image owns vertical drags for panning, so only a resting one may
    // be swiped away.
    useEffect(() {
      final controller = scaleControllers[index.value];
      void sync(PhotoViewScaleState state) =>
          zoomed.value = state == PhotoViewScaleState.zoomedIn;
      sync(controller.scaleState);
      final subscription = controller.outputScaleStateStream.listen(sync);
      return subscription.cancel;
    }, [index.value, scaleControllers]);

    final current = items[index.value];

    void goTo(int target) {
      if (target < 0 || target >= items.length) return;
      pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }

    return DismissiblePage(
      isFullScreen: true,
      backgroundColor: Colors.black,
      direction: DismissiblePageDismissDirection.down,
      disabled: zoomed.value,
      onDismissed: () => Navigator.of(context).pop(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            goTo(index.value - 1);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            goTo(index.value + 1);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showControls.value = !showControls.value,
                child: PageView.builder(
                  controller: pageController,
                  itemCount: items.length,
                  onPageChanged: (value) => index.value = value,
                  itemBuilder: (context, page) => ImageFileContent(
                    key: ValueKey('lightbox-${items[page].id}'),
                    item: items[page],
                    workspaceId: workspaceId,
                    scaleStateController: scaleControllers[page],
                  ),
                ),
              ),
              if (showControls.value)
                _LightboxChrome(
                  item: current,
                  index: index.value,
                  count: items.length,
                  serverUrl: serverUrl,
                  onClose: () => Navigator.of(context).pop(),
                  onShowActions: () => CloudFileActionsSheet.show(
                    context: context,
                    item: current,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar of the lightbox: close, the file's name, its position in the
/// gallery, and the Drive actions sheet for the open image.
class _LightboxChrome extends StatelessWidget {
  const _LightboxChrome({
    required this.item,
    required this.index,
    required this.count,
    required this.serverUrl,
    required this.onClose,
    required this.onShowActions,
  });

  final IDisplayableCloudFile item;
  final int index;
  final int count;
  final String serverUrl;
  final VoidCallback onClose;
  final VoidCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'close'.tr(),
                  onPressed: onClose,
                  icon: const Icon(Symbols.close),
                  color: Colors.white,
                ),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                if (count > 1) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${index + 1} / $count',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'more'.tr(),
                  onPressed: onShowActions,
                  icon: const Icon(Symbols.more_vert),
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
