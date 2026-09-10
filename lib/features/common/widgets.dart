import 'package:fluent_ui/fluent_ui.dart';

import '../../theme.dart';

/// A titled panel. The interface is mostly made of these.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Card(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: theme.typography.subtitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// A single headline number on the dashboard.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.tone,
    this.onPressed,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final Color? tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = tone ?? theme.accentColor.normal;
    final card = Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.typography.title?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
    if (onPressed == null) return card;
    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) => card,
    );
  }
}

/// Shown wherever a list has nothing in it yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.resources.textFillColorTertiary),
            const SizedBox(height: 12),
            Text(title, style: theme.typography.bodyStrong),
            if (message != null) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 380,
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.typography.body?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Small coloured label: a status, a role, a stock warning.
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tone = color ?? theme.resources.textFillColorSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.typography.caption?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label above a field, used throughout the forms.
///
/// Named to avoid colliding with Flutter's own `FormField`, which fluent_ui
/// re-exports.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.width,
  });

  final String label;
  final Widget child;
  final String? hint;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = InfoLabel(
      label: label,
      child: child,
    );
    final wrapped = hint == null
        ? field
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              field,
              const SizedBox(height: 4),
              Text(
                hint!,
                style: FluentTheme.of(context).typography.caption?.copyWith(
                      color:
                          FluentTheme.of(context).resources.textFillColorSecondary,
                    ),
              ),
            ],
          );
    return width == null ? wrapped : SizedBox(width: width, child: wrapped);
  }
}

/// One row of a read-only detail list.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.valueWidget});

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ),
          Expanded(
            child: valueWidget ??
                Text(value.isEmpty ? '—' : value, style: theme.typography.body),
          ),
        ],
      ),
    );
  }
}

/// Banner used for validation and operation results inside dialogs and pages.
class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.message,
    this.severity = InfoBarSeverity.error,
    this.title,
  });

  final String message;
  final InfoBarSeverity severity;
  final String? title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InfoBar(
          title: Text(title ?? _defaultTitle),
          content: Text(message),
          severity: severity,
          isLong: message.length > 70,
        ),
      );

  String get _defaultTitle => switch (severity) {
        InfoBarSeverity.error => 'That did not work',
        InfoBarSeverity.warning => 'Careful',
        InfoBarSeverity.success => 'Done',
        InfoBarSeverity.info => 'Note',
      };
}

/// Pops a transient notification in the corner of the window.
void notify(
  BuildContext context,
  String message, {
  String? title,
  InfoBarSeverity severity = InfoBarSeverity.success,
}) {
  displayInfoBar(
    context,
    duration: const Duration(seconds: 4),
    builder: (context, close) => InfoBar(
      title: Text(title ?? _titleFor(severity)),
      content: Text(message),
      severity: severity,
      isLong: message.length > 70,
      onClose: close,
    ),
  );
}

String _titleFor(InfoBarSeverity severity) => switch (severity) {
      InfoBarSeverity.error => 'Something went wrong',
      InfoBarSeverity.warning => 'Careful',
      InfoBarSeverity.success => 'Done',
      InfoBarSeverity.info => 'Note',
    };

/// Standard yes/no, used before anything destructive.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? ButtonStyle(
                  backgroundColor:
                      WidgetStatePropertyAll(SattraTheme.danger),
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A table that keeps its header while the body scrolls.
class DataList extends StatelessWidget {
  const DataList({
    super.key,
    required this.columns,
    required this.rows,
    this.onSelect,
    this.emptyState,
  });

  final List<DataListColumn> columns;
  final List<DataListRow> rows;
  final ValueChanged<int>? onSelect;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    if (rows.isEmpty && emptyState != null) return emptyState!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.resources.subtleFillColorSecondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          child: Row(
            children: [
              for (final column in columns)
                Expanded(
                  flex: column.flex,
                  child: Text(
                    column.label.toUpperCase(),
                    style: theme.typography.caption?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return HoverButton(
                onPressed: onSelect == null ? null : () => onSelect!(index),
                builder: (context, states) {
                  final hovered = states.isHovered || states.isPressed;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: hovered
                          ? theme.resources.subtleFillColorSecondary
                          : null,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.resources.dividerStrokeColorDefault,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < columns.length; i++)
                          Expanded(
                            flex: columns[i].flex,
                            child: i < row.cells.length
                                ? row.cells[i]
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class DataListColumn {
  const DataListColumn(this.label, {this.flex = 1});
  final String label;
  final int flex;
}

class DataListRow {
  const DataListRow(this.cells);
  final List<Widget> cells;
}

/// Plain text cell, so callers do not repeat the ellipsis handling.
Widget cell(BuildContext context, String text,
    {bool strong = false, Color? color}) {
  final theme = FluentTheme.of(context);
  return Text(
    text.isEmpty ? '—' : text,
    overflow: TextOverflow.ellipsis,
    style: (strong ? theme.typography.bodyStrong : theme.typography.body)
        ?.copyWith(color: color),
  );
}
