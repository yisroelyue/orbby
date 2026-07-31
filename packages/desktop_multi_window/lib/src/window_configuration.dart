class WindowConfiguration {
  const WindowConfiguration({
    required this.arguments,
    this.hiddenAtLaunch = true,
    this.initialWidth = 800,
    this.initialHeight = 600,
  })  : assert(initialWidth > 0),
        assert(initialHeight > 0);

  /// The arguments passed to the new window.
  final String arguments;

  final bool hiddenAtLaunch;

  /// Logical size used when the native Flutter surface is first created.
  final int initialWidth;
  final int initialHeight;

  factory WindowConfiguration.fromJson(Map<String, dynamic> json) {
    return WindowConfiguration(
      arguments: json['arguments'] as String? ?? '',
      hiddenAtLaunch: json['hiddenAtLaunch'] as bool? ?? false,
      initialWidth: json['initialWidth'] as int? ?? 800,
      initialHeight: json['initialHeight'] as int? ?? 600,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arguments': arguments,
      'hiddenAtLaunch': hiddenAtLaunch,
      'initialWidth': initialWidth,
      'initialHeight': initialHeight,
    };
  }

  @override
  String toString() {
    return 'WindowConfiguration(arguments: $arguments, '
        'hiddenAtLaunch: $hiddenAtLaunch, '
        'initialSize: ${initialWidth}x$initialHeight)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WindowConfiguration &&
        other.arguments == arguments &&
        other.hiddenAtLaunch == hiddenAtLaunch &&
        other.initialWidth == initialWidth &&
        other.initialHeight == initialHeight;
  }

  @override
  int get hashCode {
    return Object.hash(
      arguments,
      hiddenAtLaunch,
      initialWidth,
      initialHeight,
    );
  }
}
