import 'package:flutter_test/flutter_test.dart';
import 'package:home_manager_1/expense_data.dart';

void main() {
  group('parseCsv', () {
    test('splits plain and quoted fields, including commas and quotes', () {
      final List<List<String>> rows = parseCsv(
        '28/02/2026,"-65.34","CAFE, SPRINGFIELD ""QL""","+2410.55"\r\n'
        '26/02/2026,-21.30,GROCER SPRINGFIELD,+2475.85\n',
      );
      expect(rows, <List<String>>[
        <String>['28/02/2026', '-65.34', 'CAFE, SPRINGFIELD "QL"', '+2410.55'],
        <String>['26/02/2026', '-21.30', 'GROCER SPRINGFIELD', '+2475.85'],
      ]);
    });

    test('keeps a final row without a trailing newline and empty rows', () {
      final List<List<String>> rows = parseCsv('a,b\n\nc,d');
      expect(rows, <List<String>>[
        <String>['a', 'b'],
        <String>[],
        <String>['c', 'd'],
      ]);
    });
  });

  group('parseExpenseDate', () {
    test('accepts the formats the Python script accepts', () {
      expect(parseExpenseDate('28/02/2026'), DateTime.utc(2026, 2, 28));
      expect(parseExpenseDate('1/3/2026'), DateTime.utc(2026, 3, 1));
      expect(parseExpenseDate('01/03/26'), DateTime.utc(2026, 3, 1));
      expect(parseExpenseDate('01/03/99'), DateTime.utc(1999, 3, 1));
      expect(parseExpenseDate('2026-03-01'), DateTime.utc(2026, 3, 1));
      expect(parseExpenseDate('2026/03/01'), DateTime.utc(2026, 3, 1));
      expect(parseExpenseDate(' 2026-03-01 '), DateTime.utc(2026, 3, 1));
    });

    test('rejects headers, impossible dates and other layouts', () {
      expect(parseExpenseDate('Date'), isNull);
      expect(parseExpenseDate(''), isNull);
      expect(parseExpenseDate('31/02/2026'), isNull);
      expect(parseExpenseDate('13/13/2026'), isNull);
      expect(parseExpenseDate('02-28-2026'), isNull);
      expect(parseExpenseDate('28/02/2026 10:00'), isNull);
    });
  });

  group('parseAmount', () {
    test('reads signs, thousands separators and parentheses', () {
      expect(parseAmount('-65.34'), -65.34);
      expect(parseAmount('+2410.55'), 2410.55);
      expect(parseAmount('1,234.56'), 1234.56);
      expect(parseAmount('(12.50)'), -12.5);
      expect(parseAmount(' 7 '), 7);
    });

    test('returns null for empty or non-numeric text', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('\$5'), isNull);
    });
  });

  group('transactionFromRow', () {
    test('keeps negative amounts only, with a normalised description', () {
      final ExpenseTransaction? tx = transactionFromRow(<String>[
        '26/02/2026',
        '-21.30',
        '  GROCER   0123  SPRINGFIELD ',
        '+2475.85',
      ]);
      expect(tx, isNotNull);
      expect(tx!.date, DateTime.utc(2026, 2, 26));
      expect(tx.amount, 21.30);
      expect(tx.description, 'GROCER 0123 SPRINGFIELD');
      expect(tx.balance, 2475.85);
      expect(tx.period, const YearMonth(2026, 2));
    });

    test('skips headers, credits, empty descriptions and short rows', () {
      expect(
        transactionFromRow(<String>['Date', 'Amount', 'Description']),
        isNull,
      );
      expect(
        transactionFromRow(<String>['28/05/2026', '+1767.00', 'Transfer in']),
        isNull,
      );
      expect(
        transactionFromRow(<String>['28/05/2026', '-5.00', '   ']),
        isNull,
      );
      expect(transactionFromRow(<String>['28/05/2026', '-5.00']), isNull);
      expect(transactionFromRow(<String>['28/05/2026', 'n/a', 'x']), isNull);
      expect(transactionFromRow(<String>[]), isNull);
    });

    test('tolerates a missing balance column', () {
      final ExpenseTransaction? tx = transactionFromRow(<String>[
        '2026-05-28',
        '-5.00',
        'Coffee',
      ]);
      expect(tx?.amount, 5);
      expect(tx?.balance, isNull);
      expect(tx?.category, isNull);
    });

    test('reads the category from column E', () {
      final ExpenseTransaction? tx = transactionFromRow(<String>[
        '26/02/2026',
        '-21.30',
        'GROCER SPRINGFIELD',
        '+2475.85',
        '  Food   & Groceries ',
      ]);
      expect(tx?.category, 'Food & Groceries');
      expect(
        transactionFromRow(<String>[
          '26/02/2026',
          '-21.30',
          'GROCER SPRINGFIELD',
          '+2475.85',
          '   ',
        ])?.category,
        isNull,
      );
      expect(
        transactionFromRow(<String>[
          '26/02/2026',
          '-21.30',
          'GROCER SPRINGFIELD',
          '+2475.85',
        ])?.category,
        isNull,
      );
      for (final String placeholder in <String>[
        'Uncategorised',
        ' UNCATEGORIZED ',
      ]) {
        expect(
          transactionFromRow(<String>[
            '26/02/2026',
            '-21.30',
            'GROCER SPRINGFIELD',
            '+2475.85',
            placeholder,
          ])?.category,
          isNull,
        );
      }
    });
  });

  test('parseExpenseFile ignores a BOM and non-expense rows', () {
    const String content =
        '\uFEFF30/05/2026,"-90.62","EG GROUP","+1980.40"\n'
        '28/05/2026,"+1767.00","Transfer from savings","+2190.65"\n'
        '\n'
        'not,a,row\n'
        '27/05/2026,"-61.36","ULTRA PETROLEUM","+1210.25"\n';
    final List<ExpenseTransaction> txs = parseExpenseFile(content);
    expect(txs.map((ExpenseTransaction t) => t.amount), <double>[90.62, 61.36]);
  });

  test('parseExpenseFile reads categories as Excel saves them', () {
    // Excel drops the quotes and the "+" and pads short rows with commas.
    const String content =
        '16/09/2026,-237,Lighting Store,1320.10,"Home, garden"\r\n'
        '15/09/2026,-62.41,GROCER 0123 SPRINGFIELD,1557.10,Groceries\r\n'
        '15/09/2026,-53.97,FRUIT MARKET SPRINGFIELD,1619.51,\r\n';
    final List<ExpenseTransaction> txs = parseExpenseFile(content);
    expect(txs.map((ExpenseTransaction t) => t.category), <String?>[
      'Home, garden',
      'Groceries',
      null,
    ]);
    expect(txs.first.amount, 237);
  });

  group('ExpenseSummary', () {
    ExpenseTransaction tx(
      String date,
      double amount,
      String description, {
      double? balance,
      String? category,
    }) {
      return ExpenseTransaction(
        date: parseExpenseDate(date)!,
        amount: amount,
        description: description,
        balance: balance,
        category: category,
      );
    }

    test('counts a line found in several files once', () {
      final ExpenseTransaction shared = tx(
        '10/03/2026',
        50,
        'Shared',
        balance: 100,
      );
      final ExpenseSummary summary = ExpenseSummary.fromFiles(
        <String, List<ExpenseTransaction>>{
          'a.csv': <ExpenseTransaction>[shared, tx('11/03/2026', 20, 'Only A')],
          'b.csv': <ExpenseTransaction>[shared, tx('12/03/2026', 30, 'Only B')],
          'empty.csv': <ExpenseTransaction>[],
        },
      );
      final MonthExpenses? march = summary.month(const YearMonth(2026, 3));
      expect(march?.total, 100);
      expect(march?.transactionCount, 3);
      expect(summary.sourceFiles, <String>['a.csv', 'b.csv']);
    });

    test('keeps genuine duplicates that sit together in one file', () {
      final ExpenseTransaction twice = tx('10/03/2026', 4.5, 'Coffee');
      final ExpenseSummary summary = ExpenseSummary.fromFiles(
        <String, List<ExpenseTransaction>>{
          'a.csv': <ExpenseTransaction>[twice, twice],
          'b.csv': <ExpenseTransaction>[twice],
        },
      );
      final MonthExpenses? march = summary.month(const YearMonth(2026, 3));
      expect(march?.total, 9);
      expect(march?.transactionCount, 2);
    });

    test('groups by month and reports years and months with data', () {
      final ExpenseSummary summary = ExpenseSummary.fromFiles(
        <String, List<ExpenseTransaction>>{
          'a.csv': <ExpenseTransaction>[
            tx('30/12/2025', 10, 'Dec'),
            tx('05/01/2026', 20, 'Jan'),
            tx('20/01/2026', 0.1, 'Jan again'),
            tx('01/03/2026', 40, 'Mar'),
          ],
        },
      );
      expect(summary.years, <int>[2026, 2025]);
      expect(summary.monthsWithDataIn(2026), 2);
      expect(summary.monthsWithDataIn(2024), 0);
      expect(summary.month(const YearMonth(2026, 1))?.total, 20.1);
      expect(summary.month(const YearMonth(2026, 2)), isNull);
      expect(summary.months.map((MonthExpenses m) => m.period), <YearMonth>[
        const YearMonth(2025, 12),
        const YearMonth(2026, 1),
        const YearMonth(2026, 3),
      ]);
    });

    test('averages the three most recent earlier months with data', () {
      final ExpenseSummary summary = ExpenseSummary.fromFiles(
        <String, List<ExpenseTransaction>>{
          'a.csv': <ExpenseTransaction>[
            tx('15/10/2025', 100, 'Oct'),
            tx('15/11/2025', 200, 'Nov'),
            tx('15/12/2025', 300, 'Dec'),
            // January has no data and is skipped.
            tx('15/02/2026', 400, 'Feb'),
            tx('15/03/2026', 999, 'Mar'),
          ],
        },
      );

      final PriorMonthsAverage march = summary.priorAverage(
        const YearMonth(2026, 3),
      );
      expect(march.hasData, isTrue);
      expect(march.average, 300);
      expect(
        march.monthsUsed.map((MonthExpenses m) => m.period.shortLabel),
        <String>['Nov 2025', 'Dec 2025', 'Feb 2026'],
      );

      // The selected month itself never counts, even when it has data.
      final PriorMonthsAverage april = summary.priorAverage(
        const YearMonth(2026, 4),
      );
      expect(april.average, 566.33); // (300 + 400 + 999) / 3, to cents
    });

    test('uses fewer months when fewer are available', () {
      final ExpenseSummary summary = ExpenseSummary.fromFiles(
        <String, List<ExpenseTransaction>>{
          'a.csv': <ExpenseTransaction>[
            tx('15/10/2025', 100, 'Oct'),
            tx('15/11/2025', 250, 'Nov'),
          ],
        },
      );
      expect(summary.priorAverage(const YearMonth(2025, 11)).average, 100);
      expect(
        summary.priorAverage(const YearMonth(2025, 11)).monthsUsed.length,
        1,
      );
      expect(summary.priorAverage(const YearMonth(2025, 12)).average, 175);
      expect(summary.priorAverage(const YearMonth(2026, 6)).average, 175);

      final PriorMonthsAverage none = summary.priorAverage(
        const YearMonth(2025, 10),
      );
      expect(none.hasData, isFalse);
      expect(none.average, 0);
    });

    test('ranks a month\'s categories by amount, apart from uncategorised', () {
      final ExpenseSummary summary = ExpenseSummary.fromFiles(
        <String, List<ExpenseTransaction>>{
          'a.csv': <ExpenseTransaction>[
            tx('01/03/2026', 50, 'Coles', category: 'GROCERIES'),
            tx('02/03/2026', 30.25, 'Woolworths', category: 'Groceries'),
            tx('03/03/2026', 100, 'Origin', category: 'Utilities'),
            tx('04/03/2026', 20, 'Cafe', category: 'Dining'),
            tx('05/03/2026', 20, 'Bakery', category: 'Bakery'),
            tx('06/03/2026', 45.5, 'Kmart'),
            tx('07/03/2026', 4.5, 'Parking'),
            tx('08/04/2026', 12, 'IGA', category: 'groceries'),
            tx('09/04/2026', 9, 'Aldi', category: 'Groceries'),
          ],
        },
      );

      final MonthExpenses march = summary.month(const YearMonth(2026, 3))!;
      expect(
        march.categories.map((CategoryExpenses c) => c.name),
        // Case variants are merged; equal totals fall back to name order.
        <String>['Utilities', 'Groceries', 'Bakery', 'Dining'],
      );
      expect(march.categories[1].total, 80.25);
      expect(march.categories[1].transactionCount, 2);
      expect(march.uncategorizedTotal, 50);
      expect(march.uncategorizedCount, 2);
      expect(march.total, 270.25);
      expect(march.transactionCount, 7);

      // The most used spelling across all months names the category.
      final MonthExpenses april = summary.month(const YearMonth(2026, 4))!;
      expect(april.categories.single.name, 'Groceries');
      expect(april.categories.single.total, 21);
      expect(april.uncategorizedCount, 0);
    });

    test('takes the category from whichever copy of a line has one', () {
      final ExpenseTransaction plain = tx(
        '10/03/2026',
        50,
        'Shared',
        balance: 100,
      );
      final ExpenseTransaction tagged = tx(
        '10/03/2026',
        50,
        'Shared',
        balance: 100,
        category: 'Home',
      );
      for (final Map<String, List<ExpenseTransaction>> files
          in <Map<String, List<ExpenseTransaction>>>[
            <String, List<ExpenseTransaction>>{
              'a.csv': <ExpenseTransaction>[tagged],
              'b.csv': <ExpenseTransaction>[plain],
            },
            <String, List<ExpenseTransaction>>{
              'a.csv': <ExpenseTransaction>[plain],
              'b.csv': <ExpenseTransaction>[tagged],
            },
          ]) {
        final MonthExpenses march = ExpenseSummary.fromFiles(
          files,
        ).month(const YearMonth(2026, 3))!;
        expect(march.transactionCount, 1);
        expect(march.categories.single.name, 'Home');
        expect(march.categories.single.total, 50);
        expect(march.uncategorizedCount, 0);
      }
    });
  });

  test('formatMoney groups thousands and keeps two decimals', () {
    expect(formatMoney(0), '\$0.00');
    expect(formatMoney(5), '\$5.00');
    expect(formatMoney(1234.5), '\$1,234.50');
    expect(formatMoney(1234567.891), '\$1,234,567.89');
    expect(formatMoney(-42.1), '-\$42.10');
  });

  test('YearMonth compares and labels correctly', () {
    expect(
      const YearMonth(2025, 12).compareTo(const YearMonth(2026, 1)),
      lessThan(0),
    );
    expect(const YearMonth(2026, 3), const YearMonth(2026, 3));
    expect(const YearMonth(2026, 3).label, 'March 2026');
    expect(const YearMonth(2026, 3).shortLabel, 'Mar 2026');
  });
}
