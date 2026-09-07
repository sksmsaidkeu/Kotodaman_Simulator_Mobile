import 'package:flutter/material.dart';

/// 데스크톱 `Themes/Kotodama.xaml`(WPF)과 `Themes/DataPalette.cs`의 색을 그대로 옮긴
/// 모바일 테마. 데스크톱엔 다크모드가 없어서(WPF 라이트 전용 팔레트) 다크는 같은 시드색으로
/// 새로 파생했다 — PRD_Mobile.md FR-5(§3)가 다크모드 대응을 요구하기 때문.
class AppColors {
  static const bgBackdrop = Color(0xFFE4DED1);
  static const bgPanel = Color(0xFFEFEBE0);
  static const textPrimary = Color(0xFF4A3B28);
  static const accentOrange = Color(0xFFFFA24E);
  static const accentFocus = Color(0xFF2E7D91);

  // 카드·입력창 보더용 — 순수 회색 대신 글자색을 옅게 타서 팔레트 안에서만 움직인다.
  static final borderSubtle = textPrimary.withValues(alpha: 0.18);

  // Themes/DataPalette.cs 그대로 — "속성 색은 의미가 색 자체에 실려 있어 팔레트를
  // 갈아끼워도 바꾸지 않는다"는 원본 주석 규칙을 모바일에도 그대로 적용.
  static const Map<String, Color> attribute = {
    '火': Color(0xFFFF6B6B),
    '水': Color(0xFF63B3FF),
    '木': Color(0xFF70D98B),
    '光': Color(0xFFFFE27A),
    '闇': Color(0xFFB995FF),
    '天': Color(0xFF8FE9FF),
    '冥': Color(0xFFC58A5A),
    '虹': Color(0xFFFF9EDB),
  };

  static Color attributeColor(String value) => attribute[value] ?? const Color(0xFFB5AB93);
}

// 버튼·카드·입력창이 화면마다 M3 기본값(초둥근 필 버튼 vs 각진 아웃라인 입력창 vs
// 기본 라운드 카드)을 제각각 쓰던 걸 하나로 통일한다 — 형태 문법이 흩어져 있으면
// 색이 브랜드화돼 있어도 "손 안 탄 기본 앱"처럼 보인다.
const double _kCornerRadius = 12;
final _kShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kCornerRadius));

// 온글잎 윤우체(pubspec.yaml에 등록, 한글만 커버) — 히라가나 등 이 폰트에 없는 글자는
// Flutter가 자동으로 시스템 폰트로 폴백해서 그린다.
const _kFontFamily = 'OnGeulipYoonWoo';

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accentOrange,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppColors.bgPanel,
    onSurface: AppColors.textPrimary,
    secondary: AppColors.accentFocus,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgBackdrop,
    useMaterial3: true,
    fontFamily: _kFontFamily,
    // AppBarTheme 없이는 M3가 스크롤 가능한 화면에서 surfaceTint를 얹어 화면 전환마다
    // 헤더 톤이 미세하게 흔들린다 — 고정해서 없앤다.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgPanel,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.bgPanel,
      shape: _kShape.copyWith(side: BorderSide(color: AppColors.borderSubtle)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.accentOrange,
        foregroundColor: AppColors.textPrimary,
        shape: _kShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accentFocus,
        side: const BorderSide(color: AppColors.accentFocus),
        shape: _kShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgPanel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kCornerRadius),
        borderSide: BorderSide(color: AppColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kCornerRadius),
        borderSide: BorderSide(color: AppColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kCornerRadius),
        borderSide: const BorderSide(color: AppColors.accentFocus, width: 2),
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accentOrange,
    brightness: Brightness.dark,
  ).copyWith(secondary: AppColors.accentFocus);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: _kFontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: _kShape.copyWith(side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.18))),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(elevation: 0, shape: _kShape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: _kShape)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_kCornerRadius)),
    ),
  );
}
