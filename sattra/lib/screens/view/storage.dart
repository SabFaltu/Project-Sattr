import '/widgets/page.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> with PageMixin {
  bool disabled = false;
  bool firstValue = false;
  bool secondValue = true;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: PageHeader(
        title: const Text('Storage'),
        commandBar: ToggleSwitch(
          checked: disabled,
          onChanged: (v) => setState(() => disabled = v),
          content: const Text('Disabled'),
        ),
      ),
      children: [
        const Text(
          'Will show the storage utilized by the company '
          'Including local storage and the cloud '
          'Additional option to export all data in the form of <TBA>',
        ),
        subtitle(content: const Text('WIP')),
        description(
          content: const Text('May be worked on after semester.'),
        ),
      ],
    );
  }
}
