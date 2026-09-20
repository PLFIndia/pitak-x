/// Pure rules for a book's **language name** (Session 33).
///
/// Why this exists: the Language field was free text, so `English`,
/// `english` and Google Books' ISO code `en` were stored as three different
/// languages and the catalogue filter grew three chips. This class states
/// the ONE rule every write path (form, import, merge, restore) and the
/// schema-2 migration follow: **one spelling per language**.
///
/// The rule, in plain English:
///  1. blank → no language (`null`);
///  2. a two-letter ISO 639-1 code (what Google Books emits, e.g. `en`,
///     `hi`, `en-GB`) → its English name (`English`, `Hindi`);
///  3. otherwise, if the library already has a spelling that matches
///     ignoring case and spacing, reuse THAT spelling verbatim;
///  4. otherwise the trimmed input becomes the new canonical spelling.
///
/// Why the comparison key is built in Dart and not in SQL: SQLite's
/// `lower()` is ASCII-only, so `Ελληνικά` vs `ελληνικά` would never match
/// there. Dart's `toLowerCase()` is Unicode-aware.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

/// Canonical-spelling helpers for a book language.
abstract final class LanguageName {
  /// Languages offered when the library has none yet (empty-library seed).
  static const List<String> defaults = ['English'];

  /// Comparison key: trimmed, inner whitespace collapsed to one space,
  /// Unicode lower-cased. Two spellings are "the same language" when their
  /// keys are equal. Never stored — only compared.
  static String key(String raw) =>
      raw.trim().replaceAll(_whitespaceRun, ' ').toLowerCase();

  /// The English name for a two-letter ISO 639-1 [code] (case-insensitive;
  /// a BCP-47 tag such as `en-GB` or `pt_BR` is reduced to its primary
  /// subtag). Null when [code] is not a known two-letter code — including
  /// anything longer than two letters, which is treated as a name.
  static String? nameForIsoCode(String code) {
    final trimmed = code.trim();
    final dash = trimmed.indexOf(_subtagSeparator);
    final primary = (dash == -1 ? trimmed : trimmed.substring(0, dash))
        .toLowerCase();
    if (primary.length != 2) return null;
    return _isoNames[primary];
  }

  /// Applies the one-spelling rule to [raw] against the [existing] stored
  /// spellings. Returns null for blank input; otherwise a string that is
  /// EITHER already in [existing], an ISO name from the built-in table, or
  /// the trimmed input — it can never mint content the user did not type.
  ///
  /// The FIRST matching entry of [existing] wins, so callers that care about
  /// precedence (the migration) order the list themselves.
  static String? canonicalise(String? raw, Iterable<String> existing) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final isoName = nameForIsoCode(trimmed);
    final wanted = key(isoName ?? trimmed);
    for (final candidate in existing) {
      if (key(candidate) == wanted) return candidate;
    }
    return isoName ?? trimmed;
  }

  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _subtagSeparator = RegExp('[-_]');
}

/// ISO 639-1 two-letter code → English language name. Adapted from the
/// public ISO 639-1 code table (Wikipedia, "List of ISO 639-1 codes"). Only
/// the codes Google Books can emit matter in practice (`en`, `hi`, …), but
/// the whole table is small and `const`, so it is included in full rather
/// than guessing which codes a library will meet. Keys are lowercase.
const Map<String, String> _isoNames = {
  'aa': 'Afar',
  'ab': 'Abkhazian',
  'ae': 'Avestan',
  'af': 'Afrikaans',
  'ak': 'Akan',
  'am': 'Amharic',
  'an': 'Aragonese',
  'ar': 'Arabic',
  'as': 'Assamese',
  'av': 'Avaric',
  'ay': 'Aymara',
  'az': 'Azerbaijani',
  'ba': 'Bashkir',
  'be': 'Belarusian',
  'bg': 'Bulgarian',
  'bh': 'Bihari',
  'bi': 'Bislama',
  'bm': 'Bambara',
  'bn': 'Bengali',
  'bo': 'Tibetan',
  'br': 'Breton',
  'bs': 'Bosnian',
  'ca': 'Catalan',
  'ce': 'Chechen',
  'ch': 'Chamorro',
  'co': 'Corsican',
  'cr': 'Cree',
  'cs': 'Czech',
  'cu': 'Church Slavonic',
  'cv': 'Chuvash',
  'cy': 'Welsh',
  'da': 'Danish',
  'de': 'German',
  'dv': 'Divehi',
  'dz': 'Dzongkha',
  'ee': 'Ewe',
  'el': 'Greek',
  'en': 'English',
  'eo': 'Esperanto',
  'es': 'Spanish',
  'et': 'Estonian',
  'eu': 'Basque',
  'fa': 'Persian',
  'ff': 'Fulah',
  'fi': 'Finnish',
  'fj': 'Fijian',
  'fo': 'Faroese',
  'fr': 'French',
  'fy': 'Western Frisian',
  'ga': 'Irish',
  'gd': 'Scottish Gaelic',
  'gl': 'Galician',
  'gn': 'Guarani',
  'gu': 'Gujarati',
  'gv': 'Manx',
  'ha': 'Hausa',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'ho': 'Hiri Motu',
  'hr': 'Croatian',
  'ht': 'Haitian',
  'hu': 'Hungarian',
  'hy': 'Armenian',
  'hz': 'Herero',
  'ia': 'Interlingua',
  'id': 'Indonesian',
  'ie': 'Interlingue',
  'ig': 'Igbo',
  'ii': 'Sichuan Yi',
  'ik': 'Inupiaq',
  'io': 'Ido',
  'is': 'Icelandic',
  'it': 'Italian',
  'iu': 'Inuktitut',
  'ja': 'Japanese',
  'jv': 'Javanese',
  'ka': 'Georgian',
  'kg': 'Kongo',
  'ki': 'Kikuyu',
  'kj': 'Kuanyama',
  'kk': 'Kazakh',
  'kl': 'Kalaallisut',
  'km': 'Khmer',
  'kn': 'Kannada',
  'ko': 'Korean',
  'kr': 'Kanuri',
  'ks': 'Kashmiri',
  'ku': 'Kurdish',
  'kv': 'Komi',
  'kw': 'Cornish',
  'ky': 'Kyrgyz',
  'la': 'Latin',
  'lb': 'Luxembourgish',
  'lg': 'Ganda',
  'li': 'Limburgish',
  'ln': 'Lingala',
  'lo': 'Lao',
  'lt': 'Lithuanian',
  'lu': 'Luba-Katanga',
  'lv': 'Latvian',
  'mg': 'Malagasy',
  'mh': 'Marshallese',
  'mi': 'Maori',
  'mk': 'Macedonian',
  'ml': 'Malayalam',
  'mn': 'Mongolian',
  'mr': 'Marathi',
  'ms': 'Malay',
  'mt': 'Maltese',
  'my': 'Burmese',
  'na': 'Nauru',
  'nb': 'Norwegian Bokmål',
  'nd': 'North Ndebele',
  'ne': 'Nepali',
  'ng': 'Ndonga',
  'nl': 'Dutch',
  'nn': 'Norwegian Nynorsk',
  'no': 'Norwegian',
  'nr': 'South Ndebele',
  'nv': 'Navajo',
  'ny': 'Chichewa',
  'oc': 'Occitan',
  'oj': 'Ojibwa',
  'om': 'Oromo',
  'or': 'Odia',
  'os': 'Ossetian',
  'pa': 'Punjabi',
  'pi': 'Pali',
  'pl': 'Polish',
  'ps': 'Pashto',
  'pt': 'Portuguese',
  'qu': 'Quechua',
  'rm': 'Romansh',
  'rn': 'Rundi',
  'ro': 'Romanian',
  'ru': 'Russian',
  'rw': 'Kinyarwanda',
  'sa': 'Sanskrit',
  'sc': 'Sardinian',
  'sd': 'Sindhi',
  'se': 'Northern Sami',
  'sg': 'Sango',
  'si': 'Sinhala',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'sm': 'Samoan',
  'sn': 'Shona',
  'so': 'Somali',
  'sq': 'Albanian',
  'sr': 'Serbian',
  'ss': 'Swati',
  'st': 'Southern Sotho',
  'su': 'Sundanese',
  'sv': 'Swedish',
  'sw': 'Swahili',
  'ta': 'Tamil',
  'te': 'Telugu',
  'tg': 'Tajik',
  'th': 'Thai',
  'ti': 'Tigrinya',
  'tk': 'Turkmen',
  'tl': 'Tagalog',
  'tn': 'Tswana',
  'to': 'Tongan',
  'tr': 'Turkish',
  'ts': 'Tsonga',
  'tt': 'Tatar',
  'tw': 'Twi',
  'ty': 'Tahitian',
  'ug': 'Uyghur',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'uz': 'Uzbek',
  've': 'Venda',
  'vi': 'Vietnamese',
  'vo': 'Volapük',
  'wa': 'Walloon',
  'wo': 'Wolof',
  'xh': 'Xhosa',
  'yi': 'Yiddish',
  'yo': 'Yoruba',
  'za': 'Zhuang',
  'zh': 'Chinese',
  'zu': 'Zulu',
};
