import 'package:flutter/material.dart';

/// Small circular "×" overlay used to remove an item from "Continua a
/// guardare". Works with mouse/touch; on Android/TV the long-press on the card
/// is the D-pad fallback. Shared by the film and series continue tiles.
class RemoveButton extends StatelessWidget {
  const RemoveButton({super.key, required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // ExcludeFocus: pointer-only control. On Android the InkWell would be a
    // focusable-but-invisible D-pad stop layered over the tile; a remote
    // removes via the long-press menu instead.
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: Colors.black.withValues(alpha: 0.6),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}
