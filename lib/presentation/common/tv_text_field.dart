import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui_mode.dart';
import '../../data/services/device_mode_service.dart';

/// A [TextFormField] that plays nice with a TV remote.
///
/// In TV mode (Android + saved [DeviceMode.tv]) a bare text field is a focus
/// trap: the D-pad focus walks straight into it, the keyboard pops up, and
/// the arrows start moving the caret instead of navigating. Here the field is
/// wrapped in a navigation node instead: arrows move between fields, OK opens
/// the keyboard (editing), and Up/Down/Done leave editing and resume
/// navigation. Everywhere else (Windows, phone/tablet touch) it builds a
/// plain [TextFormField] with identical behavior to before.
class TvTextFormField extends StatefulWidget {
  const TvTextFormField({
    super.key,
    this.controller,
    this.decoration,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.style,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;

  /// In TV mode this focuses the inner field (keyboard open, editing) right
  /// away — used by the search screens where typing is the whole point.
  final bool autofocus;

  final TextStyle? style;
  final List<TextInputFormatter>? inputFormatters;

  /// Test hook: forces TV mode regardless of the host platform.
  @visibleForTesting
  static bool? debugTvModeOverride;

  @override
  State<TvTextFormField> createState() => _TvTextFormFieldState();
}

class _TvTextFormFieldState extends State<TvTextFormField> {
  static bool get _tvMode => TvTextFormField.debugTvModeOverride ?? isTvMode();

  final FocusNode _wrapperNode = FocusNode(debugLabel: 'TvTextFormField.wrapper');
  // skipTraversal: the D-pad can never wander into the field by itself — the
  // only ways in are OK on the wrapper or a direct tap.
  final FocusNode _fieldNode =
      FocusNode(skipTraversal: true, debugLabel: 'TvTextFormField.field');

  @override
  void initState() {
    super.initState();
    if (_tvMode) {
      _fieldNode.onKeyEvent = _handleFieldKey;
      if (widget.autofocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fieldNode.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _wrapperNode.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleWrapperKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _fieldNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// While editing (IME closed — an open IME consumes the D-pad itself),
  /// Up/Down/Escape leave the field and hand the focus back to navigation.
  KeyEventResult _handleFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.escape) {
      _wrapperNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!_tvMode) {
      return TextFormField(
        controller: widget.controller,
        decoration: widget.decoration,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        validator: widget.validator,
        onChanged: widget.onChanged,
        autofocus: widget.autofocus,
        style: widget.style,
        inputFormatters: widget.inputFormatters,
      );
    }

    return Focus(
      focusNode: _wrapperNode,
      onKeyEvent: _handleWrapperKey,
      child: Builder(
        builder: (context) {
          final navFocused = Focus.of(context).hasPrimaryFocus;
          // Focus is shown by recolouring the field's OWN outline, never with
          // a ring drawn around it: the floating label ("Nome Playlist") sits
          // in the gap of that outline and an outer ring cut straight through
          // the text. Material leaves the gap for us, so nothing overlaps.
          var decoration = widget.decoration ?? const InputDecoration();
          if (navFocused) {
            final ring = OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.focusRing, width: 2.5),
            );
            decoration = decoration.copyWith(enabledBorder: ring, border: ring);
          }

          return TextFormField(
            controller: widget.controller,
            focusNode: _fieldNode,
            decoration: decoration,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            validator: widget.validator,
            onChanged: widget.onChanged,
            style: widget.style,
            inputFormatters: widget.inputFormatters,
            // Done/Next on the TV keyboard: close the IME and resume navigation
            // on this field (Down then moves on).
            onEditingComplete: () => _wrapperNode.requestFocus(),
          );
        },
      ),
    );
  }
}
