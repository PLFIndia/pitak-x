/// The note that names the items whose cover picture was left out (backup
/// presentation).
///
/// WHY THIS FILE EXISTS (beginner note): two pages say the same kind of
/// thing. The create-backup page says which items' pictures are NOT inside
/// the finished backup (decision D10), and the restore page says which
/// items' pictures were NOT restored (decisions D18 and D23). The layout is
/// the same on both: one sentence, the first few titles, and how many more
/// there are. So the layout lives here once, and each page passes in its
/// own sentence.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/backup/presentation/create_backup_messages.dart';

/// One sentence, then the first [coversLeftOutTitlesShown] titles, then
/// "and N more" when there are more.
class LeftOutCoversNote extends StatelessWidget {
  /// Creates the note. [sentence] is the page's own line above the titles.
  const LeftOutCoversNote({
    required this.sentence,
    required this.titles,
    super.key,
  });

  /// The line above the list. Each page words it for what it did.
  final String sentence;

  /// One title per item whose cover picture was left out. Never empty.
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final more = coversLeftOutMoreMessage(titles.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sentence, style: style),
        // One line per title, shortened by the Text widget itself. A title
        // can be very long, and cutting a string by hand can split a letter
        // in scripts that build one letter from several code units.
        for (final title in titles.take(coversLeftOutTitlesShown))
          Text(
            '• $title',
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (more != null) Text(more, style: style),
      ],
    );
  }
}
