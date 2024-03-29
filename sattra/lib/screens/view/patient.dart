// ignore_for_file: prefer_const_constructors

import '/widgets/page.dart';
import '/screens/module/people.dart';
import 'package:fluent_ui/fluent_ui.dart';

const kSplitButtonHeight = 32.0;
const kSplitButtonWidth = 36.0;

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> with PageMixin {
  String filterText = '';
  AccentColor splitButtonColor = Colors.red;
  final splitButtonFlyout = FlyoutController();

  @override
  void dispose() {
    splitButtonFlyout.dispose();
    super.dispose();
  }

  final patientCommands = <CommandBarItem>[
    CommandBarBuilderItem(
      builder: (context, mode, w) => Tooltip(
        message: "Create something new!",
        child: w,
      ),
      wrappedItem: CommandBarButton(
        icon: const Icon(FluentIcons.add),
        label: const Text('New'),
        onPressed: () {},
      ),
    ),
    CommandBarBuilderItem(
      builder: (context, mode, w) => Tooltip(
        message: "Search By Name",
        child: w,
      ),
      wrappedItem: CommandBarButton(
        icon: const Icon(FluentIcons.search),
        label: const Text('Search'),
        onPressed: () {},
      ),
    )
  ];

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasFluentTheme(context));

    double screenWidth = MediaQuery.of(context).size.width;

    // Dynamically calculate the number of columns based on screen width
    int crossAxisCounted = (screenWidth ~/ 320);

    // Adjust childAspectRatio based on your design needs
    // double childAspectRatio = 0.85; // Adjust this value as needed

    return ScaffoldPage.scrollable(
      header: PageHeader(
        title: Text('Patients'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            ...patientCommands,
          ],
        ),
      ),
      children: [
        GridView.builder(
          shrinkWrap: true,

          itemCount: 15, // Adjust based on your data

          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCounted,
            crossAxisSpacing: 8.0,
            mainAxisSpacing: 4.0,
            // childAspectRatio: childAspectRatio,
          ),

          itemBuilder: (BuildContext context, int index) {
            return PatientWidget();
          },
        ),
      ],
    );
  }
}
