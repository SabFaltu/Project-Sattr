import 'package:fluent_ui/fluent_ui.dart';

class PatientWidget extends StatefulWidget {
  const PatientWidget({super.key});

  @override
  _PatientWidgetState createState() => _PatientWidgetState();
}

class _PatientWidgetState extends State<PatientWidget> {
  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasFluentTheme(context));
    final theme = FluentTheme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Card(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeIn,
                    width: 350, // Consider making this dynamic if needed
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min, // Changed to min
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.start, // Added to align items at the start
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  'https://images.unsplash.com/photo-1681668385364-af51bce51c18?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=687&q=80',
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(left: 8.0),
                                  child: Text(
                                    'Devinder\nSingh',
                                    textAlign: TextAlign.start,
                                    maxLines: 2,
                                    style: TextStyle(fontSize: 28),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Age: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          // color: Colors.black,
                                          fontSize: 17,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '42',
                                        style: TextStyle(
                                          // color: Colors.black,
                                        ),
                                      )
                                    ],
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Gender: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Male',
                                        style: TextStyle(fontSize: 15),
                                      )
                                    ],
                                    style: TextStyle(fontSize: 17),
                                  ),
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Last Checkup: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '12 Jan 2023',
                                        style: TextStyle(fontSize: 15),
                                      )
                                    ],
                                    style: TextStyle(fontSize: 17),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}