/// Нормализация запроса поиска: латиница → кириллица для эмулятора/англ. раскладки.
String normalizeSearchQuery(String raw) {
  final q = raw.trim();
  if (q.isEmpty) return q;
  if (RegExp(r'[а-яА-ЯёЁ]').hasMatch(q)) return q;

  final lower = q.toLowerCase();
  const shortcuts = {
    'omlet': 'омлет',
    'grechka': 'гречка',
    'gretchka': 'гречка',
    'tvorog': 'творог',
    'kurica': 'курица',
    'kuritsa': 'курица',
    'ovsyanka': 'овсянка',
    'moloko': 'молоко',
    'yabloko': 'яблоко',
    'banan': 'банан',
    'ris': 'рис',
    'hleb': 'хлеб',
    'borsch': 'борщ',
    'syr': 'сыр',
    'yajco': 'яйцо',
    'yaico': 'яйцо',
  };
  if (shortcuts.containsKey(lower)) return shortcuts[lower]!;

  return _latinToCyrillic(lower);
}

String _latinToCyrillic(String input) {
  const multi = [
    ('shch', 'щ'),
    ('sch', 'щ'),
    ('yo', 'ё'),
    ('zh', 'ж'),
    ('kh', 'х'),
    ('ts', 'ц'),
    ('ch', 'ч'),
    ('sh', 'ш'),
    ('yu', 'ю'),
    ('ya', 'я'),
    ('ye', 'е'),
    ('iu', 'ю'),
    ('ia', 'я'),
    ('ij', 'ий'),
    ('yi', 'ый'),
  ];
  const single = {
    'a': 'а',
    'b': 'б',
    'v': 'в',
    'g': 'г',
    'd': 'д',
    'e': 'е',
    'z': 'з',
    'i': 'и',
    'j': 'й',
    'k': 'к',
    'l': 'л',
    'm': 'м',
    'n': 'н',
    'o': 'о',
    'p': 'п',
    'r': 'р',
    's': 'с',
    't': 'т',
    'u': 'у',
    'f': 'ф',
    'h': 'х',
    'c': 'к',
    'q': 'к',
    'w': 'в',
    'x': 'кс',
    'y': 'ы',
  };

  final buffer = StringBuffer();
  var i = 0;
  while (i < input.length) {
    var matched = false;
    for (final (latin, cyr) in multi) {
      if (input.startsWith(latin, i)) {
        buffer.write(cyr);
        i += latin.length;
        matched = true;
        break;
      }
    }
    if (matched) continue;
    final ch = input[i];
    if (ch == ' ' || ch == '-' || ch == ',') {
      buffer.write(ch);
      i++;
      continue;
    }
    buffer.write(single[ch] ?? ch);
    i++;
  }
  return buffer.toString();
}
