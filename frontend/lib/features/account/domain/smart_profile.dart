class SmartProfile {
  const SmartProfile({
    this.isEnabled = false,
    this.defaultLanguage,
    this.defaultTone,
    this.defaultAudience,
    this.defaultChannel,
    this.defaultOutputFormat,
    this.businessContext,
    this.defaultConstraints = const [],
    this.defaultInstructions = const [],
  });

  factory SmartProfile.fromJson(Map<String, dynamic> json) => SmartProfile(
        isEnabled: json['is_enabled'] as bool? ?? false,
        defaultLanguage: json['default_language'] as String?,
        defaultTone: json['default_tone'] as String?,
        defaultAudience: json['default_audience'] as String?,
        defaultChannel: json['default_channel'] as String?,
        defaultOutputFormat: json['default_output_format'] as String?,
        businessContext: json['business_context'] as String?,
        defaultConstraints:
            (json['default_constraints'] as List<dynamic>? ?? const [])
                .cast<String>(),
        defaultInstructions:
            (json['default_instructions'] as List<dynamic>? ?? const [])
                .cast<String>(),
      );

  final bool isEnabled;
  final String? defaultLanguage;
  final String? defaultTone;
  final String? defaultAudience;
  final String? defaultChannel;
  final String? defaultOutputFormat;
  final String? businessContext;
  final List<String> defaultConstraints;
  final List<String> defaultInstructions;

  bool get hasData =>
      [
        defaultLanguage,
        defaultTone,
        defaultAudience,
        defaultChannel,
        defaultOutputFormat,
        businessContext
      ].any((value) => value?.isNotEmpty ?? false) ||
      defaultConstraints.isNotEmpty ||
      defaultInstructions.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'is_enabled': isEnabled,
        'default_language': defaultLanguage,
        'default_tone': defaultTone,
        'default_audience': defaultAudience,
        'default_channel': defaultChannel,
        'default_output_format': defaultOutputFormat,
        'business_context': businessContext,
        'default_constraints': defaultConstraints,
        'default_instructions': defaultInstructions,
      };
}
