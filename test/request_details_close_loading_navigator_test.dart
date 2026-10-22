import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('nested pop does not dismiss root dialog (loader stays)',
      (tester) async {
    await tester.pumpWidget(const _Harness(popLoaderFromRoot: false));

    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.byKey(const Key('details_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('close_details')));
    await tester.pump();

    expect(find.byKey(const Key('loader_dialog')), findsOneWidget);
  });

  testWidgets('root pop dismisses root dialog (loader removed)', (tester) async {
    await tester.pumpWidget(const _Harness(popLoaderFromRoot: true));

    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.byKey(const Key('details_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('close_details')));
    await tester.pump();

    expect(find.byKey(const Key('loader_dialog')), findsNothing);
  });
}

class _Harness extends StatelessWidget {
  final bool popLoaderFromRoot;

  const _Harness({required this.popLoaderFromRoot});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: _NestedHost(popLoaderFromRoot: popLoaderFromRoot),
    );
  }
}

class _NestedHost extends StatelessWidget {
  final bool popLoaderFromRoot;

  const _NestedHost({required this.popLoaderFromRoot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Navigator(
        pages: [
          MaterialPage<void>(
            child: Builder(
              builder: (nestedContext) {
                return Center(
                  child: ElevatedButton(
                    key: const Key('open'),
                    onPressed: () async {
                      showDialog<void>(
                        context: nestedContext,
                        barrierDismissible: false,
                        builder: (_) => const AlertDialog(
                          key: Key('loader_dialog'),
                          content: SizedBox(
                            height: 48,
                            width: 48,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      );

                      await Future<void>.delayed(Duration.zero);

                      if (popLoaderFromRoot) {
                        Navigator.of(nestedContext, rootNavigator: true).pop();
                      } else {
                        Navigator.of(nestedContext).pop();
                      }

                      showDialog<void>(
                        context: nestedContext,
                        builder: (_) => AlertDialog(
                          key: const Key('details_dialog'),
                          actions: [
                            TextButton(
                              key: const Key('close_details'),
                              onPressed: () => Navigator.pop(_),
                              child: const Text('close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ],
        onPopPage: (route, result) => false,
      ),
    );
  }
}
