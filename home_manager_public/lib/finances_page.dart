import 'package:flutter/material.dart';

import 'expense_data.dart';
import 'expense_loader.dart';

const Color _titleColor = Color(0xFF263331);
const Color _mutedColor = Color(0xFF68706D);
const Color _accentColor = Color(0xFF1F7A6B);
const Color _borderColor = Color(0xFFE5E0D6);
const double _cellHeight = 80;
const double _cellGap = 12;
const double _maxContentWidth = 560;

// Category cells use the app's blue palette so they stand apart from the
// white total and average cards.
const Color _categoryFill = Color(0xFFE2ECFB);
const Color _categoryBorder = Color(0xFF6E97D6);
const Color _categoryText = Color(0xFF234B86);
const Color _categoryMuted = Color(0xFF4A6285);
const int _topCategoryCount = 5;

/// Opened from the "$" button on the home screen. Shows the current year
/// (always) plus any other year that has expenses in the loaded files.
class FinancesPage extends StatefulWidget {
  const FinancesPage({super.key});

  @override
  State<FinancesPage> createState() => _FinancesPageState();
}

class _FinancesPageState extends State<FinancesPage> {
  late Future<ExpenseSummary> _summary = ExpenseLoader.load();

  void _reload() {
    setState(() {
      _summary = ExpenseLoader.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finances'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload expense files',
            onPressed: _reload,
          ),
        ],
      ),
      body: SafeArea(
        child: _PageBody(
          child: FutureBuilder<ExpenseSummary>(
            future: _summary,
            builder:
                (BuildContext context, AsyncSnapshot<ExpenseSummary> snapshot) {
                  if (snapshot.hasError) {
                    return _Message(
                      'Could not read the expense files.\n${snapshot.error}',
                    );
                  }
                  final ExpenseSummary? summary = snapshot.data;
                  if (summary == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _YearList(summary: summary);
                },
          ),
        ),
      ),
    );
  }
}

class _YearList extends StatelessWidget {
  const _YearList({required this.summary});

  final ExpenseSummary summary;

  void _openYear(BuildContext context, int year) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            FinanceYearPage(year: year, summary: summary),
      ),
    );
  }

  String _subtitle(int monthsWithData) {
    if (monthsWithData == 0) {
      return 'No expenses loaded';
    }
    return '$monthsWithData month${monthsWithData == 1 ? '' : 's'} with data';
  }

  @override
  Widget build(BuildContext context) {
    final int currentYear = DateTime.now().year;
    final List<int> years = <int>[
      currentYear,
      ...summary.years.where((int year) => year != currentYear),
    ];
    final int fileCount = summary.sourceFiles.length;
    final String footer = summary.isEmpty
        ? 'No expense files found in $expensesAssetFolder\n'
              'Add bank CSV exports to that folder and restart the app.'
        : 'Loaded from $fileCount file${fileCount == 1 ? '' : 's'}';

    return ListView(
      children: <Widget>[
        for (int i = 0; i < years.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: _cellGap),
          _FinanceCell(
            icon: Icons.calendar_month_outlined,
            title: '${years[i]}',
            subtitle: _subtitle(summary.monthsWithDataIn(years[i])),
            onTap: () => _openYear(context, years[i]),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          footer,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedColor),
        ),
      ],
    );
  }
}

/// The twelve months of one year.
class FinanceYearPage extends StatelessWidget {
  const FinanceYearPage({required this.year, required this.summary, super.key});

  final int year;
  final ExpenseSummary summary;

  void _openMonth(BuildContext context, YearMonth period) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            FinanceMonthPage(period: period, summary: summary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$year'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: _PageBody(
          child: ListView.separated(
            itemCount: monthNames.length,
            separatorBuilder: (_, _) => const SizedBox(height: _cellGap),
            itemBuilder: (BuildContext context, int index) {
              final YearMonth period = YearMonth(year, index + 1);
              final MonthExpenses? month = summary.month(period);
              final String subtitle = month == null
                  ? 'No transactions'
                  : '${month.transactionCount} '
                        'transaction${month.transactionCount == 1 ? '' : 's'}';
              return _FinanceCell(
                icon: Icons.event_outlined,
                title: period.monthName,
                subtitle: subtitle,
                onTap: () => _openMonth(context, period),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Total for one month, the average of the months before it and the month's
/// top spending categories.
class FinanceMonthPage extends StatelessWidget {
  const FinanceMonthPage({
    required this.period,
    required this.summary,
    super.key,
  });

  final YearMonth period;
  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final MonthExpenses? month = summary.month(period);
    final PriorMonthsAverage prior = summary.priorAverage(period);
    final int used = prior.monthsUsed.length;

    final String totalCaption = month == null
        ? 'No transactions loaded for this month'
        : '${month.transactionCount} '
              'transaction${month.transactionCount == 1 ? '' : 's'}';

    final String averageTitle = used == 1
        ? 'Previous month'
        : 'Average of previous ${used == 0 ? 3 : used} months';
    final String monthsUsed = prior.monthsUsed
        .map((MonthExpenses m) => m.period.shortLabel)
        .join(', ');
    final String averageCaption = !prior.hasData
        ? 'No earlier months with data'
        : used < 3
        ? 'Only $used month${used == 1 ? '' : 's'} with data: $monthsUsed'
        : monthsUsed;

    return Scaffold(
      appBar: AppBar(
        title: Text(period.label),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: _PageBody(
          child: ListView(
            children: <Widget>[
              _SummaryCard(
                icon: Icons.receipt_long_outlined,
                title: 'Total expenses',
                amount: formatMoney(month?.total ?? 0),
                caption: totalCaption,
              ),
              const SizedBox(height: _cellGap),
              _SummaryCard(
                icon: Icons.show_chart,
                title: averageTitle,
                amount: prior.hasData ? formatMoney(prior.average) : '—',
                caption: averageCaption,
              ),
              if (month != null) ...<Widget>[
                const SizedBox(height: 28),
                _TopCategories(month: month),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: child,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: _mutedColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Tappable row styled like the home screen cells.
class _FinanceCell extends StatelessWidget {
  const _FinanceCell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cellHeight,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(icon, color: _accentColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _titleColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: _mutedColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _mutedColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A figure with its label and a short explanation underneath.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.amount,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String amount;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: _accentColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      color: _titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              amount,
              style: textTheme.headlineMedium?.copyWith(
                color: _titleColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: textTheme.bodySmall?.copyWith(color: _mutedColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month's largest categories by amount spent, with a note about any
/// categories left out and any expenses that have no category.
class _TopCategories extends StatelessWidget {
  const _TopCategories({required this.month});

  final MonthExpenses month;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final List<CategoryExpenses> top = month.categories
        .take(_topCategoryCount)
        .toList(growable: false);
    final int categoryCount = month.categories.length;
    final int uncategorized = month.uncategorizedCount;
    final List<String> notes = <String>[
      if (categoryCount > _topCategoryCount)
        'Largest $_topCategoryCount of $categoryCount categories',
      if (top.isNotEmpty && uncategorized > 0)
        '$uncategorized transaction${uncategorized == 1 ? '' : 's'} '
            '(${formatMoney(month.uncategorizedTotal)}) without a category',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Top categories',
          style: textTheme.titleMedium?.copyWith(
            color: _titleColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (top.isEmpty)
          const _NoCategoriesCell()
        else
          for (int i = 0; i < top.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: _cellGap),
            _CategoryCell(
              rank: i + 1,
              category: top[i],
              monthTotal: month.total,
            ),
          ],
        if (notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            notes.join('\n'),
            style: textTheme.bodySmall?.copyWith(color: _mutedColor),
          ),
        ],
      ],
    );
  }
}

/// One ranked category: name, amount, share of the month and a share bar.
class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.rank,
    required this.category,
    required this.monthTotal,
  });

  final int rank;
  final CategoryExpenses category;
  final double monthTotal;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double share = monthTotal > 0
        ? (category.total / monthTotal).clamp(0.0, 1.0)
        : 0;
    final String percent = share > 0 && share < 0.01
        ? '<1%'
        : '${(share * 100).round()}%';
    final int count = category.transactionCount;
    final TextStyle? strong = textTheme.bodyLarge?.copyWith(
      color: _categoryText,
      fontWeight: FontWeight.w700,
    );

    return _CategorySurface(
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _categoryBorder),
            ),
            child: Text(
              '$rank',
              style: textTheme.labelLarge?.copyWith(
                color: _categoryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: strong,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatMoney(category.total), style: strong),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$percent of expenses · '
                  '$count transaction${count == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: _categoryMuted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: ColoredBox(
                      color: Colors.white,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: share,
                        child: const ColoredBox(color: _categoryBorder),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the ranking while a month's expenses have no category.
class _NoCategoriesCell extends StatelessWidget {
  const _NoCategoriesCell();

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return _CategorySurface(
      child: Row(
        children: <Widget>[
          const Icon(Icons.sell_outlined, color: _categoryText),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No categories yet',
                  style: textTheme.bodyLarge?.copyWith(
                    color: _categoryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Type each expense\'s category in column E of the CSV '
                  'file, then restart the app.',
                  style: textTheme.bodySmall?.copyWith(color: _categoryMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySurface extends StatelessWidget {
  const _CategorySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: _categoryFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _categoryBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
        child: child,
      ),
    );
  }
}
