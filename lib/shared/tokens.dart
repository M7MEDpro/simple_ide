import 'package:flutter/material.dart';

/**
 * Design tokens for SimpleIDE.
 *
 * Graphite chrome, cool neutral text, and a single amber accent reserved for
 * the things that act on your program: Run, the active tab, focus.
 */
abstract final class Tk {
  // Surfaces, darkest to lightest.
  static const chrome = Color(0xFF121418); // menu bar, rail, status bar
  static const sidebar = Color(0xFF16181D); // explorer, console
  static const editor = Color(0xFF1B1D23); // editor canvas
  static const raised = Color(0xFF20232B); // menus, dialogs, inputs
  static const hover = Color(0xFF242832);
  static const pressed = Color(0xFF2B303B);
  static const border = Color(0xFF262A33);
  static const borderStrong = Color(0xFF333845);

  // Text.
  static const text = Color(0xFFC9CED8);
  static const textStrong = Color(0xFFE8EBF0);
  static const textMuted = Color(0xFF7B8392);
  static const textFaint = Color(0xFF535A67);

  // Signal colors.
  static const accent = Color(0xFFE8B04B); // amber: run, active, focus
  static const accentInk = Color(0xFF1A1407); // text on amber
  static const success = Color(0xFF6FC38F);
  static const error = Color(0xFFE5686B);
  static const warning = Color(0xFFE0A271);
  static const info = Color(0xFF7FA6F5);

  static const selection = Color(0xFF2C3E5E);
  static const activeLine = Color(0xFF20232B);
  static const listActive = Color(0xFF262C3A);

  // Type.
  static const uiFont = 'Segoe UI Variable Text';
  static const uiFallback = ['Segoe UI', 'Arial'];
  // Cascadia Mono: Cascadia Code without ligatures, so `<=` and `++` stay literal.
  static const codeFont = 'Cascadia Mono';
  static const codeFallback = ['Consolas', 'Courier New'];

  static const ui = TextStyle(
    fontFamily: uiFont,
    fontFamilyFallback: uiFallback,
    fontSize: 13,
    height: 1.3,
    color: text,
  );
  static const uiSmall = TextStyle(
    fontFamily: uiFont,
    fontFamilyFallback: uiFallback,
    fontSize: 12,
    height: 1.3,
    color: textMuted,
  );
  static const code = TextStyle(
    fontFamily: codeFont,
    fontFamilyFallback: codeFallback,
    fontSize: 13,
    height: 1.45,
    color: text,
  );

  static const radius = BorderRadius.all(Radius.circular(4));
  static const radiusLg = BorderRadius.all(Radius.circular(6));
}

/**
 * Syntax palette, tuned against [Tk.editor].
 */
const Map<String, TextStyle> kSyntaxTheme = {
  'root': TextStyle(color: Tk.text),
  'keyword': TextStyle(color: Color(0xFF7FA6F5)),
  'built_in': TextStyle(color: Color(0xFF7DCFE0)),
  'type': TextStyle(color: Color(0xFF6FC3C0)),
  'class': TextStyle(color: Color(0xFF6FC3C0)),
  'title': TextStyle(color: Color(0xFFE6D38A)),
  'title.class': TextStyle(color: Color(0xFF6FC3C0)),
  'title.class_': TextStyle(color: Color(0xFF6FC3C0)),
  'title.function': TextStyle(color: Color(0xFFE6D38A)),
  'title.function_': TextStyle(color: Color(0xFFE6D38A)),
  'title.function.invoke__': TextStyle(color: Color(0xFFE6D38A)),
  'function': TextStyle(color: Color(0xFFE6D38A)),
  'literal': TextStyle(color: Color(0xFFE0A271)),
  'number': TextStyle(color: Color(0xFFE0A271)),
  'string': TextStyle(color: Color(0xFF9CC995)),
  'char.escape': TextStyle(color: Color(0xFFE0A271)),
  'regexp': TextStyle(color: Color(0xFF9CC995)),
  'symbol': TextStyle(color: Color(0xFFE0A271)),
  'comment': TextStyle(color: Color(0xFF6A7385), fontStyle: FontStyle.italic),
  'doctag': TextStyle(color: Color(0xFF8B95A7)),
  'meta': TextStyle(color: Color(0xFFC792C9)),
  'meta keyword': TextStyle(color: Color(0xFFC792C9)),
  'meta string': TextStyle(color: Color(0xFF9CC995)),
  'meta-keyword': TextStyle(color: Color(0xFFC792C9)),
  'meta-string': TextStyle(color: Color(0xFF9CC995)),
  'attr': TextStyle(color: Color(0xFFD4A3A3)),
  'attribute': TextStyle(color: Color(0xFFD4A3A3)),
  'variable': TextStyle(color: Color(0xFFD4A3A3)),
  'variable.language': TextStyle(color: Color(0xFF7FA6F5)),
  'variable.constant_': TextStyle(color: Color(0xFFE0A271)),
  'params': TextStyle(color: Tk.text),
  'property': TextStyle(color: Color(0xFFD4A3A3)),
  'operator': TextStyle(color: Color(0xFFA8B0BE)),
  'punctuation': TextStyle(color: Color(0xFF8A92A0)),
  'tag': TextStyle(color: Color(0xFF7FA6F5)),
  'name': TextStyle(color: Color(0xFF7FA6F5)),
  'selector-tag': TextStyle(color: Color(0xFF7FA6F5)),
  'selector-class': TextStyle(color: Color(0xFFE6D38A)),
  'selector-id': TextStyle(color: Color(0xFFE6D38A)),
  'section': TextStyle(color: Color(0xFFE6D38A), fontWeight: FontWeight.w600),
  'bullet': TextStyle(color: Color(0xFFE0A271)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.w600),
  'link': TextStyle(color: Color(0xFF7FA6F5)),
  'addition': TextStyle(color: Color(0xFF6FC38F)),
  'deletion': TextStyle(color: Color(0xFFE5686B)),
  'subst': TextStyle(color: Tk.text),
};

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: Tk.uiFont,
    fontFamilyFallback: Tk.uiFallback,
    scaffoldBackgroundColor: Tk.editor,
    canvasColor: Tk.sidebar,
    colorScheme: const ColorScheme.dark(
      primary: Tk.accent,
      onPrimary: Tk.accentInk,
      secondary: Tk.info,
      surface: Tk.raised,
      onSurface: Tk.text,
      error: Tk.error,
      outline: Tk.borderStrong,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Tk.hover,
    focusColor: Tk.hover,
    dividerColor: Tk.border,
    visualDensity: VisualDensity.compact,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Tk.text, displayColor: Tk.textStrong),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(fontFamily: Tk.uiFont, fontSize: 12, color: Tk.textStrong),
      decoration: BoxDecoration(
        color: Tk.raised,
        borderRadius: Tk.radius,
        border: Border.fromBorderSide(BorderSide(color: Tk.borderStrong)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Tk.textFaint.withValues(alpha: 0.45)),
      thickness: const WidgetStatePropertyAll(8),
      radius: Radius.zero,
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Tk.raised),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
        minimumSize: WidgetStatePropertyAll(Size(240, 0)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: Tk.radiusLg,
          side: BorderSide(color: Tk.borderStrong),
        )),
        elevation: WidgetStatePropertyAll(8),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(Tk.ui),
        foregroundColor: const WidgetStatePropertyAll(Tk.text),
        minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
              ? Tk.listActive
              : Colors.transparent,
        ),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    menuBarTheme: const MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Tk.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Tk.radiusLg,
        side: BorderSide(color: Tk.borderStrong),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Tk.accent,
      selectionColor: Tk.selection,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Tk.editor,
      hintStyle: TextStyle(color: Tk.textFaint),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: Tk.radius, borderSide: BorderSide(color: Tk.borderStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: Tk.radius, borderSide: BorderSide(color: Tk.borderStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: Tk.radius, borderSide: BorderSide(color: Tk.accent)),
    ),
  );
}
