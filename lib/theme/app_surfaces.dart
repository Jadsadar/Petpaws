import 'package:flutter/material.dart';
import 'app_tokens.dart';

enum AppBg { login, other }

/// Original artwork remains a quiet backdrop to the content.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.bg = AppBg.other});
  final Widget child;
  final AppBg bg;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final portrait = box.maxHeight > box.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background,
            image: DecorationImage(
              image: AssetImage(
                  'assets/images/bg_${bg == AppBg.other ? '' : '${bg.name}_'}${portrait ? 'mobile' : 'web'}.jpg'),
              fit: BoxFit.cover,
              opacity: 0.18,
            ),
          ),
          child: child,
        );
      });
}

/// Readable widths on desktop; full available width on small screens.
class AppPageFrame extends StatelessWidget {
  const AppPageFrame(
      {super.key, required this.child, this.maxWidth = AppLayout.contentWidth});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox.expand(child: child),
        ),
      );
}

class TextPanel extends StatelessWidget {
  const TextPanel(
      {super.key, required this.child, this.center = false, this.pill = true});
  final Widget child;
  final bool center;
  final bool pill;
  @override
  Widget build(BuildContext context) => Align(
        alignment: center ? Alignment.center : AlignmentDirectional.centerStart,
        child: Container(
          padding: pill
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
              : const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(
                  pill ? AppRadius.chip : AppRadius.card)),
          child: child,
        ),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.section,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.sand)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
            ],
            ...children,
          ],
        ),
      );
}
