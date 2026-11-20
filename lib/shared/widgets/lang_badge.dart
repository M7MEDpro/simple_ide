import 'package:flutter/material.dart';

import 'package:simple_ide/features/runner/languages.dart';
import 'package:simple_ide/shared/tokens.dart';

/**
 * Small coloured glyph identifying a file's language.
 */
class LangBadge extends StatelessWidget {
  const LangBadge({super.key, required this.path, this.isDir = false, this.open = false});

  final String path;
  final bool isDir;
  final bool open;

  @override
  Widget build(BuildContext context) {
    if (isDir) {
      return Icon(open ? Icons.folder_open_rounded : Icons.folder_rounded, size: 15, color: const Color(0xFF8A9BB8));
    }
    final lang = languageFor(path);
    return SizedBox(
      width: 18,
      child: Text(
        lang.badge,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontFamily: Tk.codeFont,
          fontFamilyFallback: Tk.codeFallback,
          fontSize: lang.badge.length > 2 ? 7.5 : 9.5,
          fontWeight: FontWeight.w700,
          color: lang.badgeColor,
          height: 1,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/**
 * Shortcut accelerator hint text.
 */
class KeyHint extends StatelessWidget {
  const KeyHint(this.keys, {super.key});
  final String keys;

  @override
  Widget build(BuildContext context) => Text(keys, style: Tk.uiSmall.copyWith(color: Tk.textFaint));
}
