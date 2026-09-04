import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/theme/app_theme.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('dark theme semantic text and controls meet contrast targets', () {
    final scheme = AppTheme.dark().colorScheme;

    expect(_contrastRatio(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(7));
    expect(
      _contrastRatio(scheme.onSurfaceVariant, scheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(scheme.onSurface, scheme.surfaceContainerHigh),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(scheme.onPrimary, scheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(scheme.onPrimaryContainer, scheme.primaryContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(scheme.outline, scheme.surface),
      greaterThanOrEqualTo(3),
    );
  });
}