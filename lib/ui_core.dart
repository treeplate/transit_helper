import 'dart:async';

import 'package:flutter/material.dart';

class ContinuousBuilder extends StatefulWidget {
  const ContinuousBuilder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<ContinuousBuilder> createState() => _ContinuousBuilderState();
}

class _ContinuousBuilderState extends State<ContinuousBuilder>
    with SingleTickerProviderStateMixin {
  late final Timer ticker;
  @override
  void initState() {
    ticker =Timer.periodic(Duration(milliseconds: 100), (t) => setState(() {
      
    }));
    super.initState();
  }

  @override
  void dispose() {
    ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}