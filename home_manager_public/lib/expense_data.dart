/// Pure-Dart parsing and aggregation of bank-export CSV files.
///
/// The row format mirrors what `Finances Monitor/Finances_Monitor_v2.0.py`
/// reads in `read_expenses_grouped`: one transaction per row, columns
/// `date, amount, description, balance`, no header row. Rows whose first
/// column is not a date are skipped, only negative amounts count as expenses,
/// and the description must not be empty. An optional fifth column (E) holds
/// the expense category, typed by hand or filled in later; the script ignores
/// it.
library;

const List<String> monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Collapses runs of whitespace and trims, like the script's
/// `normalize_space`.
String normalizeSpace(String text) {
  return text
      .trim()
      .split(RegExp(r'\s+'))
      .where((String part) => part.isNotEmpty)
      .join(' ');
}

/// Parses an amount the way the script's `parse_amount` does: thousands
/// separators are dropped and `(12.34)` means `-12.34`. Returns null when the
/// text is not a finite number.
double? parseAmount(String value) {
  String text = value.trim().replaceAll(',', '');
  if (text.isEmpty) {
    return null;
  }
  if (text.startsWith('(') && text.endsWith(')')) {
    text = '-${text.substring(1, text.length - 1)}';
  }
  final double? parsed = double.tryParse(text);
  if (parsed == null || !parsed.isFinite) {
    return null;
  }
  return parsed;
}

final RegExp _dayMonthYear = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
final RegExp _dayMonthShortYear = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})$');
final RegExp _yearMonthDayDash = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
final RegExp _yearMonthDaySlash = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$');

/// Accepts the same formats as the script's `parse_date`
/// (`%d/%m/%Y`, `%d/%m/%y`, `%Y-%m-%d`, `%Y/%m/%d`). Returns a UTC date at
/// midnight, or null when the text is not a valid calendar date.
DateTime? parseExpenseDate(String value) {
  final String text = value.trim();
  if (text.isEmpty) {
    return null;
  }

  RegExpMatch? match = _dayMonthYear.firstMatch(text);
  if (match != null) {
    return _validDate(
      int.parse(match[3]!),
      int.parse(match[2]!),
      int.parse(match[1]!),
    );
  }

  match = _dayMonthShortYear.firstMatch(text);
  if (match != null) {
    // Python's %y pivot: 69-99 -> 1969-1999, 00-68 -> 2000-2068.
    final int shortYear = int.parse(match[3]!);
    final int year = shortYear >= 69 ? 1900 + shortYear : 2000 + shortYear;
    return _validDate(year, int.parse(match[2]!), int.parse(match[1]!));
  }

  match =
      _yearMonthDayDash.firstMatch(text) ?? _yearMonthDaySlash.firstMatch(text);
  if (match != null) {
    return _validDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }
  return null;
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null; // e.g. 31/02/2026 rolled over into March.
  }
  return date;
}

/// Minimal RFC 4180 reader: fields separated by commas, optionally wrapped in
/// double quotes (which may contain commas, doubled quotes and line breaks).
/// Blank lines become empty rows, matching Python's `csv.reader`.
List<List<String>> parseCsv(String text) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool inQuotes = false;
  bool fieldStarted = false;
  int i = 0;
  final int length = text.length;

  while (i < length) {
    final String ch = text[i];

    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }

    if (ch == '"' && !fieldStarted) {
      inQuotes = true;
      fieldStarted = true;
      i++;
      continue;
    }

    if (ch == ',') {
      row.add(field.toString());
      field.clear();
      fieldStarted = false;
      i++;
      continue;
    }

    if (ch == '\r' || ch == '\n') {
      if (row.isEmpty && !fieldStarted) {
        rows.add(<String>[]);
      } else {
        row.add(field.toString());
        rows.add(row);
      }
      row = <String>[];
      field.clear();
      fieldStarted = false;
      if (ch == '\r' && i + 1 < length && text[i + 1] == '\n') {
        i++;
      }
      i++;
      continue;
    }

    field.write(ch);
    fieldStarted = true;
    i++;
  }

  if (row.isNotEmpty || fieldStarted) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// One expense (a negative bank movement) taken from a CSV row.
class ExpenseTransaction {
  const ExpenseTransaction({
    required this.date,
    required this.amount,
    required this.description,
    this.balance,
    this.category,
  });

  final DateTime date;

  /// Size of the expense, always positive.
  final double amount;
  final String description;
  final double? balance;

  /// Category from column E, or null when the cell is blank or says
  /// "Uncategorised".
  final String? category;

  YearMonth get period => YearMonth(date.year, date.month);

  /// Identifies the same bank line when it appears in more than one export.
  /// The category is left out so a categorised copy matches a plain one.
  String get dedupeKey =>
      '${date.year}-${date.month}-${date.day}|$amount|$balance|$description';
}

/// Column E values that mean the expense has not been given a category yet.
const Set<String> _noCategoryLabels = <String>{
  'uncategorised',
  'uncategorized',
};

/// Converts a CSV row into an expense using the script's rules, or returns
/// null when the row is a header, a credit, or otherwise not an expense.
ExpenseTransaction? transactionFromRow(List<String> row) {
  if (row.isEmpty) {
    return null;
  }
  final DateTime? date = parseExpenseDate(row[0]);
  if (date == null) {
    return null;
  }

  double? balance;
  if (row.length >= 4) {
    balance = parseAmount(row[3]);
  }

  if (row.length < 3) {
    return null;
  }
  final double? rawAmount = parseAmount(row[1]);
  if (rawAmount == null || rawAmount >= 0) {
    return null;
  }
  final String description = normalizeSpace(row[2]);
  if (description.isEmpty) {
    return null;
  }

  String? category;
  if (row.length >= 5) {
    final String text = normalizeSpace(row[4]);
    if (text.isNotEmpty && !_noCategoryLabels.contains(text.toLowerCase())) {
      category = text;
    }
  }

  return ExpenseTransaction(
    date: date,
    amount: -rawAmount,
    description: description,
    balance: balance,
    category: category,
  );
}

/// Parses a whole CSV file. Files with any name are accepted; a file that
/// yields no expenses is simply an empty list.
List<ExpenseTransaction> parseExpenseFile(String content) {
  String text = content;
  if (text.startsWith('\uFEFF')) {
    text = text.substring(1); // utf-8-sig BOM, as the script tolerates.
  }
  return parseCsv(text)
      .map(transactionFromRow)
      .whereType<ExpenseTransaction>()
      .toList(growable: false);
}

/// A calendar month, comparable and usable as a map key.
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month);

  final int year;
  final int month;

  String get monthName => monthNames[month - 1];
  String get shortLabel => '${monthName.substring(0, 3)} $year';
  String get label => '$monthName $year';

  @override
  int compareTo(YearMonth other) {
    final int byYear = year.compareTo(other.year);
    return byYear != 0 ? byYear : month.compareTo(other.month);
  }

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => label;
}

class MonthExpenses {
  const MonthExpenses({
    required this.period,
    required this.total,
    required this.transactionCount,
    required this.categories,
    required this.uncategorizedTotal,
    required this.uncategorizedCount,
  });

  final YearMonth period;

  /// Sum of expenses, rounded to cents.
  final double total;
  final int transactionCount;

  /// Spending per category, largest total first (ties in name order).
  /// Expenses without a category are not part of this list.
  final List<CategoryExpenses> categories;

  /// Sum of the expenses that have no category, rounded to cents.
  final double uncategorizedTotal;
  final int uncategorizedCount;
}

/// Money spent in one category during a month.
class CategoryExpenses {
  const CategoryExpenses({
    required this.name,
    required this.total,
    required this.transactionCount,
  });

  /// Categories that differ only in letter case are merged; the name is the
  /// spelling used most often across all the loaded files.
  final String name;

  /// Rounded to cents.
  final double total;
  final int transactionCount;
}

/// Average of the months that precede a given month.
class PriorMonthsAverage {
  const PriorMonthsAverage({required this.average, required this.monthsUsed});

  /// Rounded to cents; 0 when [monthsUsed] is empty.
  final double average;

  /// Chronological list of the months averaged (at most the requested count).
  final List<MonthExpenses> monthsUsed;

  bool get hasData => monthsUsed.isNotEmpty;
}

double roundToCents(double value) => (value * 100).round() / 100;

/// Monthly totals built from every loaded file.
class ExpenseSummary {
  ExpenseSummary._(this._months, this.sourceFiles);

  /// Months with at least one expense, in chronological order.
  final Map<YearMonth, MonthExpenses> _months;

  /// Names of the files that contributed at least one expense.
  final List<String> sourceFiles;

  /// Merges the transactions of several files. Bank exports overlap, so a
  /// line found in more than one file is counted once: for each distinct line
  /// the count kept is the highest count seen inside a single file. A copy
  /// with a category wins over one without, so the category only needs to be
  /// typed into one of the overlapping files.
  factory ExpenseSummary.fromFiles(
    Map<String, List<ExpenseTransaction>> transactionsByFile,
  ) {
    final Map<String, ExpenseTransaction> byKey =
        <String, ExpenseTransaction>{};
    final Map<String, int> keptCount = <String, int>{};
    final List<String> files = <String>[];

    for (final MapEntry<String, List<ExpenseTransaction>> entry
        in transactionsByFile.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      files.add(entry.key);
      final Map<String, int> countsInFile = <String, int>{};
      for (final ExpenseTransaction tx in entry.value) {
        countsInFile[tx.dedupeKey] = (countsInFile[tx.dedupeKey] ?? 0) + 1;
        if (tx.category != null || byKey[tx.dedupeKey]?.category == null) {
          byKey[tx.dedupeKey] = tx;
        }
      }
      for (final MapEntry<String, int> count in countsInFile.entries) {
        if ((keptCount[count.key] ?? 0) < count.value) {
          keptCount[count.key] = count.value;
        }
      }
    }

    final Map<YearMonth, _MonthTally> tallies = <YearMonth, _MonthTally>{};
    // How many expenses use each spelling of a category, keyed in lower case.
    final Map<String, Map<String, int>> spellings =
        <String, Map<String, int>>{};
    for (final MapEntry<String, int> kept in keptCount.entries) {
      final ExpenseTransaction tx = byKey[kept.key]!;
      final _MonthTally tally = tallies.putIfAbsent(tx.period, _MonthTally.new);
      tally.all.add(tx.amount, kept.value);
      final String? category = tx.category;
      if (category == null) {
        tally.uncategorized.add(tx.amount, kept.value);
        continue;
      }
      final String key = category.toLowerCase();
      tally.byCategory.putIfAbsent(key, _Tally.new).add(tx.amount, kept.value);
      final Map<String, int> uses = spellings.putIfAbsent(
        key,
        () => <String, int>{},
      );
      uses[category] = (uses[category] ?? 0) + kept.value;
    }
    final Map<String, String> categoryNames = spellings.map(
      (String key, Map<String, int> uses) =>
          MapEntry<String, String>(key, _mostUsedSpelling(uses)),
    );

    final List<YearMonth> ordered = tallies.keys.toList()..sort();
    final Map<YearMonth, MonthExpenses> months = <YearMonth, MonthExpenses>{};
    for (final YearMonth period in ordered) {
      final _MonthTally tally = tallies[period]!;
      final List<CategoryExpenses> categories = <CategoryExpenses>[
        for (final MapEntry<String, _Tally> category
            in tally.byCategory.entries)
          CategoryExpenses(
            name: categoryNames[category.key]!,
            total: roundToCents(category.value.total),
            transactionCount: category.value.count,
          ),
      ]..sort(_largestFirst);
      months[period] = MonthExpenses(
        period: period,
        total: roundToCents(tally.all.total),
        transactionCount: tally.all.count,
        categories: List<CategoryExpenses>.unmodifiable(categories),
        uncategorizedTotal: roundToCents(tally.uncategorized.total),
        uncategorizedCount: tally.uncategorized.count,
      );
    }
    files.sort();
    return ExpenseSummary._(months, files);
  }

  bool get isEmpty => _months.isEmpty;

  List<MonthExpenses> get months => _months.values.toList(growable: false);

  /// Years that have at least one expense, most recent first.
  List<int> get years {
    final Set<int> seen = <int>{};
    for (final YearMonth period in _months.keys) {
      seen.add(period.year);
    }
    return seen.toList()..sort((int a, int b) => b.compareTo(a));
  }

  MonthExpenses? month(YearMonth period) => _months[period];

  int monthsWithDataIn(int year) =>
      _months.keys.where((YearMonth p) => p.year == year).length;

  /// Averages the (up to) [maxMonths] most recent months that have data and
  /// come before [period]. Months without data are skipped, as the script's
  /// `get_previous_month_total_values_actuals` does. When fewer months exist
  /// the average is over those that do.
  PriorMonthsAverage priorAverage(YearMonth period, {int maxMonths = 3}) {
    final List<MonthExpenses> earlier = _months.values
        .where((MonthExpenses m) => m.period.compareTo(period) < 0)
        .toList();
    final List<MonthExpenses> used = earlier.length > maxMonths
        ? earlier.sublist(earlier.length - maxMonths)
        : earlier;
    if (used.isEmpty) {
      return const PriorMonthsAverage(
        average: 0,
        monthsUsed: <MonthExpenses>[],
      );
    }
    final double sum = used.fold<double>(
      0,
      (double acc, MonthExpenses m) => acc + m.total,
    );
    return PriorMonthsAverage(
      average: roundToCents(sum / used.length),
      monthsUsed: List<MonthExpenses>.unmodifiable(used),
    );
  }
}

/// Running sum and count while [ExpenseSummary.fromFiles] adds up a month.
class _Tally {
  double total = 0;
  int count = 0;

  void add(double amount, int times) {
    total += amount * times;
    count += times;
  }
}

class _MonthTally {
  final _Tally all = _Tally();
  final _Tally uncategorized = _Tally();

  /// Keyed by the lower-case category name.
  final Map<String, _Tally> byCategory = <String, _Tally>{};
}

/// The spelling with the most uses; the first one seen wins a tie.
String _mostUsedSpelling(Map<String, int> uses) {
  String best = uses.keys.first;
  for (final MapEntry<String, int> entry in uses.entries) {
    if (entry.value > uses[best]!) {
      best = entry.key;
    }
  }
  return best;
}

int _largestFirst(CategoryExpenses a, CategoryExpenses b) {
  final int byTotal = b.total.compareTo(a.total);
  return byTotal != 0
      ? byTotal
      : a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Formats an amount as `$1,234.56`.
String formatMoney(double value) {
  final String fixed = value.abs().toStringAsFixed(2);
  final int dot = fixed.indexOf('.');
  final String whole = fixed.substring(0, dot);
  final String cents = fixed.substring(dot + 1);
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      grouped.write(',');
    }
    grouped.write(whole[i]);
  }
  final String sign = value < 0 ? '-' : '';
  return '$sign\$$grouped.$cents';
}
