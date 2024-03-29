import '/widgets/page.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SliderPage extends StatefulWidget {
  const SliderPage({super.key});

  @override
  State<SliderPage> createState() => _SliderPageState();
}

class _SliderPageState extends State<SliderPage> with PageMixin {
  bool disabled = false;
  double firstValue = 23.0;
  double verticalValue = 50.0;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: PageHeader(
        title: const Text('Appointments'),
        commandBar: ToggleSwitch(
          checked: disabled,
          onChanged: (v) => setState(() => disabled = v),
          content: const Text('Disabled'),
        ),
      ),
      children: [
        const Text(
          'Ability to look at appointment of future past '
          'TBD ability to allow syncing with usual calendar softwares (outlook/gcal) '
          'Alerts for upcoming appointments.\n\n'
          'Planned view of a calendar or column style view '
          'with option to switch between them. '
          'Calendar design pending with column view a work in progress ',
        ),
        subtitle(content: const Text('A WIP')),
        description(
          content: const Text('May be worked on after semester.'),
        ),
      ],
    );
  }
}
