import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The words of every live region a screen reader is given just now, in the
/// order of the tree. A live region is a part of the screen that a screen
/// reader reads out by itself when it appears or changes.
///
/// It walks the WHOLE semantics tree, so a test can also ask for "none":
/// a progress line that became a live region by accident would be read out
/// at every step.
///
/// The caller holds a `tester.ensureSemantics()` handle while it asks.
List<String> liveRegionLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isLiveRegion) labels.add(data.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return labels;
}
