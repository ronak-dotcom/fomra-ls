import 'land_lead.dart';

/// Land owner profile: what kind of person owns the land, what exactly they
/// do, where they live and who decides on selling. Captured when a Land Owner
/// meeting is logged. Type and decision are short keys (owner_occupation /
/// owner_decision); profession, locality and town are typed text. Empty =
/// not recorded yet.
abstract final class OwnerProfile {
  /// Owner type keys, in the order offered.
  static const types = <(String, String)>[
    ('farmer', 'Farmer / Agriculturist'),
    ('business', 'Business / Trader'),
    ('politician', 'Politician / Public figure'),
    ('salaried', 'Salaried / Professional'),
    ('retired', 'Retired'),
    ('nri', 'NRI / Lives outside India'),
    ('real_estate', 'Real estate / Developer'),
    ('institution', 'Institution / Trust / Temple'),
    ('government', 'Government / Ex-servicemen'),
  ];

  static const decisionOptions = <(String, String)>[
    ('alone', 'Owner decides alone'),
    ('family', 'Family decides together'),
    ('others_consent', "Needs others' consent"),
  ];

  static String _label(List<(String, String)> options, String key) {
    final k = key.trim();
    for (final (value, label) in options) {
      if (value == k) return label;
    }
    // Free text saved before the list existed is shown as written.
    return k;
  }

  static String typeLabel(String key) => _label(types, key);
  static String decisionLabel(String key) => _label(decisionOptions, key);

  /// Short type label for chips and filters ("Farmer", "Business", …).
  static String typeShort(String key) => typeLabel(key).split(' / ').first;
}

/// One owner profile as edited in a form.
class OwnerProfileValues {
  final String type;
  final String profession;
  final String lives;
  final String town;
  final String decision;

  const OwnerProfileValues({
    this.type = '',
    this.profession = '',
    this.lives = '',
    this.town = '',
    this.decision = '',
  });

  factory OwnerProfileValues.of(LandLead l) => OwnerProfileValues(
        type: l.ownerOccupation.trim(),
        profession: l.ownerProfession.trim(),
        lives: l.ownerLives.trim(),
        town: l.ownerTown.trim(),
        decision: l.ownerDecision.trim(),
      );

  OwnerProfileValues copyWith({
    String? type,
    String? profession,
    String? lives,
    String? town,
    String? decision,
  }) =>
      OwnerProfileValues(
        type: type ?? this.type,
        profession: profession ?? this.profession,
        lives: lives ?? this.lives,
        town: town ?? this.town,
        decision: decision ?? this.decision,
      );

  LandLead applyTo(LandLead l) => l.copyWith(
        ownerOccupation: type,
        ownerProfession: profession,
        ownerLives: lives,
        ownerTown: town,
        ownerDecision: decision,
      );

  /// "Velachery, Chennai" — locality and town, whichever are filled.
  String get livesAt =>
      [lives.trim(), town.trim()].where((s) => s.isNotEmpty).join(', ');

  @override
  bool operator ==(Object o) =>
      o is OwnerProfileValues &&
      o.type == type &&
      o.profession == profession &&
      o.lives == lives &&
      o.town == town &&
      o.decision == decision;

  @override
  int get hashCode => Object.hash(type, profession, lives, town, decision);
}
