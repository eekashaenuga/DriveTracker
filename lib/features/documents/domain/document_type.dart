enum DocumentType {
  mot('MOT', 'MOT certificate', true),
  insurance('Insurance', 'Insurance policy', true),
  tax('Vehicle tax', 'Vehicle tax', true),
  v5c('V5C / Logbook', 'V5C / Logbook', false),
  receipt('Receipt / Invoice', 'Receipt / Invoice', false),
  other('Other / Custom', 'Document', false);

  const DocumentType(this.label, this.defaultTitle, this.requiresDate);
  final String label;
  final String defaultTitle;
  final bool requiresDate;

  static DocumentType classify(String category) =>
      switch (category.trim().toLowerCase()) {
        'mot' => mot,
        'insurance' => insurance,
        'tax' || 'vehicle tax' => tax,
        'v5c' || 'logbook' || 'v5c / logbook' => v5c,
        'receipt' ||
        'invoice' ||
        'receipt / invoice' ||
        'purchase receipt' => receipt,
        _ => other,
      };

  String get dateLabel => this == tax ? 'Due date' : 'Expiry date';
  String get issueLabel => switch (this) {
    mot => 'Test / issue date',
    insurance => 'Start / issue date',
    receipt => 'Date',
    _ => 'Issue date',
  };
  String get providerLabel => switch (this) {
    mot => 'Test centre',
    insurance => 'Insurer',
    _ => 'Provider',
  };
  String get referenceLabel => switch (this) {
    mot => 'Certificate / reference',
    insurance => 'Policy / reference',
    _ => 'Reference number',
  };
}
