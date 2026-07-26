// lib/widgets/swipe_nav.dart
//
// Wrapper de navigation par swipe horizontal.
// Swipe vers la gauche  → push (avancer dans la hiérarchie, ex: ouvrir une note)
// Swipe vers la droite  → pop  (revenir à l'écran précédent)
//
// Usage :
//   SwipeNav(
//     onSwipeBack:    () => Navigator.maybePop(context),       // optionnel
//     onSwipeForward: () => _openSelected(context),            // optionnel
//     child: ...,
//   )
//
// Le seuil de détection combine distance ET vélocité pour éviter les faux
// positifs lors d'un simple scroll vertical ou d'un tap.
import 'package:flutter/material.dart';

class SwipeNav extends StatelessWidget {
  /// Appelé sur swipe vers la droite (retour). Si null, utilise Navigator.maybePop.
  final VoidCallback? onSwipeBack;

  /// Appelé sur swipe vers la gauche (avancer / ouvrir le dernier élément consulté).
  final VoidCallback? onSwipeForward;

  final Widget child;

  /// Si false, le swipe retour (droite) n'est pas intercepté (laisse le
  /// comportement par défaut, ex: écran racine sans parent).
  final bool enableBack;

  /// Si false, le swipe avant (gauche) n'est pas intercepté.
  final bool enableForward;

  const SwipeNav({
    super.key,
    required this.child,
    this.onSwipeBack,
    this.onSwipeForward,
    this.enableBack = true,
    this.enableForward = false,
  });

  static const double _kMinVelocity = 250.0; // px/s
  static const double _kMinDistance = 60.0;  // px

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < _kMinVelocity) return;

        if (velocity > 0 && enableBack) {
          // Swipe vers la droite → retour
          if (onSwipeBack != null) {
            onSwipeBack!();
          } else {
            Navigator.maybePop(context);
          }
        } else if (velocity < 0 && enableForward) {
          // Swipe vers la gauche → avancer
          onSwipeForward?.call();
        }
      },
      child: child,
    );
  }
}
