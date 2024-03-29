import '/widgets/page.dart';
import 'package:fluent_ui/fluent_ui.dart';

class MedicationPage extends StatefulWidget {
  const MedicationPage({super.key});

  @override
  State<MedicationPage> createState() => _MedicationPageState();
}

class _MedicationPageState extends State<MedicationPage> with PageMixin {
  bool firstChecked = false;
  bool firstDisabled = false;
  bool? secondChecked = false;
  bool secondDisabled = false;
  bool iconDisabled = false;
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('Checkbox')),
      children: [
        const Text(
          'This will host all available medicines in the establishment. With the ability to sort, and add to inventory',
        ),
        subtitle(content: const Text('Additional option to have alerts when threshhold reached')),
        description(
          content: const Text('Mobile alerts *not* planned.'),
        ),
      ],
    );
  }

  final treeViewItems = [
    TreeViewItem(content: const Text('Option 1')),
    TreeViewItem(content: const Text('Option 2')),
    TreeViewItem(content: const Text('Option 3')),
  ];
}
