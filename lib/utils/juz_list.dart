import 'package:flutter/material.dart';

class JuzList extends StatelessWidget {
  final void Function(int pageIndex) onJump;

  const JuzList(void Function(int pageIndex) onJumpToPage, {super.key, required this.onJump});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 30,
      itemBuilder: (_, i) {
        return ListTile(
          title: Text("Juz ${i + 1}"),
          onTap: () {
            Navigator.pop(context);
            onJump(_juzToPage(i + 1));
          },
        );
      },
    );
  }

  int _juzToPage(int juz) {
    // TODO: map juz → mushaf page
    return 0;
  }
}