/// Land owner profile: what kind of person owns the land, where they live and
/// who decides on selling. Captured when a Land Owner meeting is logged and
/// stored on the lead as short keys (owner_occupation / owner_lives /
/// owner_decision); empty = not recorded yet.
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

  static const livesOptions = <(String, String)>[
    ('local_village', 'In the village'),
    ('nearby_town', 'Nearby town'),
    ('chennai', 'Chennai'),
    ('other_state', 'Other state'),
    ('abroad', 'Abroad'),
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
  static String livesLabel(String key) => _label(livesOptions, key);
  static String decisionLabel(String key) => _label(decisionOptions, key);

  /// Short type label for chips and filters ("Farmer", "Business", …).
  static String typeShort(String key) => typeLabel(key).split(' / ').first;
}
