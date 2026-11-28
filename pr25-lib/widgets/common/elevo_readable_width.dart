import 'package:flutter/material.dart';

/// Keeps a phone-width column centered on a wide desktop window.
///
/// heightFactor: 1 makes the Align only as tall as its child. Without it,
/// Align grows to the full height it is offered. Scaffold offers
/// bottomNavigationBar the whole screen height, so the nav bar filled the
/// screen, sat at the top, and hid the page body on every shell.
class ElevoReadableWidth extends StatelessWidget {
  static const double maxWidth = 720;

  final Widget child;

  const ElevoReadableWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
