// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class Books extends Table with TableInfo<Books, BooksData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Books(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<String> itemUid = GeneratedColumn<String>(
    'book_uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> titleTransliteration =
      GeneratedColumn<String>(
        'title_transliteration',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> titleSort = GeneratedColumn<String>(
    'title_sort',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'\''),
  );
  late final GeneratedColumn<String> authorSort = GeneratedColumn<String>(
    'author_sort',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'\''),
  );
  late final GeneratedColumn<String> isbn = GeneratedColumn<String>(
    'isbn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> publishedYear = GeneratedColumn<int>(
    'published_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sourceDetail = GeneratedColumn<String>(
    'source_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> ageGroup = GeneratedColumn<String>(
    'age_group',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> addedDate = GeneratedColumn<int>(
    'added_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> copyCount = GeneratedColumn<int>(
    'copy_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('1'),
  );
  late final GeneratedColumn<bool> needsMetadata = GeneratedColumn<bool>(
    'needs_metadata',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_metadata" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<bool> removed = GeneratedColumn<bool>(
    'removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("removed" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> removedAt = GeneratedColumn<int>(
    'removed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> addedBy = GeneratedColumn<String>(
    'added_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'book\''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    itemUid,
    title,
    titleTransliteration,
    author,
    titleSort,
    authorSort,
    isbn,
    publisher,
    publishedYear,
    genre,
    coverUrl,
    pageCount,
    language,
    notes,
    location,
    sourceType,
    sourceDetail,
    ageGroup,
    addedDate,
    copyCount,
    needsMetadata,
    removed,
    removedAt,
    addedBy,
    kind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BooksData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BooksData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      itemUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_uid'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleTransliteration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_transliteration'],
      ),
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      titleSort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_sort'],
      )!,
      authorSort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_sort'],
      )!,
      isbn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isbn'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      publishedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}published_year'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      ),
      sourceDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_detail'],
      ),
      ageGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_group'],
      ),
      addedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_date'],
      )!,
      copyCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}copy_count'],
      )!,
      needsMetadata: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_metadata'],
      )!,
      removed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}removed'],
      )!,
      removedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}removed_at'],
      ),
      addedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_by'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
    );
  }

  @override
  Books createAlias(String alias) {
    return Books(attachedDatabase, alias);
  }
}

class BooksData extends DataClass implements Insertable<BooksData> {
  final int id;
  final String? itemUid;
  final String title;
  final String? titleTransliteration;
  final String? author;
  final String titleSort;
  final String authorSort;
  final String? isbn;
  final String? publisher;
  final int? publishedYear;
  final String? genre;
  final String? coverUrl;
  final int? pageCount;
  final String? language;
  final String? notes;
  final String? location;
  final String? sourceType;
  final String? sourceDetail;
  final String? ageGroup;
  final int addedDate;
  final int copyCount;
  final bool needsMetadata;
  final bool removed;
  final int? removedAt;
  final String? addedBy;
  final String kind;
  const BooksData({
    required this.id,
    this.itemUid,
    required this.title,
    this.titleTransliteration,
    this.author,
    required this.titleSort,
    required this.authorSort,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.genre,
    this.coverUrl,
    this.pageCount,
    this.language,
    this.notes,
    this.location,
    this.sourceType,
    this.sourceDetail,
    this.ageGroup,
    required this.addedDate,
    required this.copyCount,
    required this.needsMetadata,
    required this.removed,
    this.removedAt,
    this.addedBy,
    required this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || itemUid != null) {
      map['book_uid'] = Variable<String>(itemUid);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || titleTransliteration != null) {
      map['title_transliteration'] = Variable<String>(titleTransliteration);
    }
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    map['title_sort'] = Variable<String>(titleSort);
    map['author_sort'] = Variable<String>(authorSort);
    if (!nullToAbsent || isbn != null) {
      map['isbn'] = Variable<String>(isbn);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || publishedYear != null) {
      map['published_year'] = Variable<int>(publishedYear);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    if (!nullToAbsent || pageCount != null) {
      map['page_count'] = Variable<int>(pageCount);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || sourceType != null) {
      map['source_type'] = Variable<String>(sourceType);
    }
    if (!nullToAbsent || sourceDetail != null) {
      map['source_detail'] = Variable<String>(sourceDetail);
    }
    if (!nullToAbsent || ageGroup != null) {
      map['age_group'] = Variable<String>(ageGroup);
    }
    map['added_date'] = Variable<int>(addedDate);
    map['copy_count'] = Variable<int>(copyCount);
    map['needs_metadata'] = Variable<bool>(needsMetadata);
    map['removed'] = Variable<bool>(removed);
    if (!nullToAbsent || removedAt != null) {
      map['removed_at'] = Variable<int>(removedAt);
    }
    if (!nullToAbsent || addedBy != null) {
      map['added_by'] = Variable<String>(addedBy);
    }
    map['kind'] = Variable<String>(kind);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      itemUid: itemUid == null && nullToAbsent
          ? const Value.absent()
          : Value(itemUid),
      title: Value(title),
      titleTransliteration: titleTransliteration == null && nullToAbsent
          ? const Value.absent()
          : Value(titleTransliteration),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      titleSort: Value(titleSort),
      authorSort: Value(authorSort),
      isbn: isbn == null && nullToAbsent ? const Value.absent() : Value(isbn),
      publisher: publisher == null && nullToAbsent
          ? const Value.absent()
          : Value(publisher),
      publishedYear: publishedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedYear),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      pageCount: pageCount == null && nullToAbsent
          ? const Value.absent()
          : Value(pageCount),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      sourceType: sourceType == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceType),
      sourceDetail: sourceDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDetail),
      ageGroup: ageGroup == null && nullToAbsent
          ? const Value.absent()
          : Value(ageGroup),
      addedDate: Value(addedDate),
      copyCount: Value(copyCount),
      needsMetadata: Value(needsMetadata),
      removed: Value(removed),
      removedAt: removedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(removedAt),
      addedBy: addedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(addedBy),
      kind: Value(kind),
    );
  }

  factory BooksData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BooksData(
      id: serializer.fromJson<int>(json['id']),
      itemUid: serializer.fromJson<String?>(json['itemUid']),
      title: serializer.fromJson<String>(json['title']),
      titleTransliteration: serializer.fromJson<String?>(
        json['titleTransliteration'],
      ),
      author: serializer.fromJson<String?>(json['author']),
      titleSort: serializer.fromJson<String>(json['titleSort']),
      authorSort: serializer.fromJson<String>(json['authorSort']),
      isbn: serializer.fromJson<String?>(json['isbn']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      publishedYear: serializer.fromJson<int?>(json['publishedYear']),
      genre: serializer.fromJson<String?>(json['genre']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      pageCount: serializer.fromJson<int?>(json['pageCount']),
      language: serializer.fromJson<String?>(json['language']),
      notes: serializer.fromJson<String?>(json['notes']),
      location: serializer.fromJson<String?>(json['location']),
      sourceType: serializer.fromJson<String?>(json['sourceType']),
      sourceDetail: serializer.fromJson<String?>(json['sourceDetail']),
      ageGroup: serializer.fromJson<String?>(json['ageGroup']),
      addedDate: serializer.fromJson<int>(json['addedDate']),
      copyCount: serializer.fromJson<int>(json['copyCount']),
      needsMetadata: serializer.fromJson<bool>(json['needsMetadata']),
      removed: serializer.fromJson<bool>(json['removed']),
      removedAt: serializer.fromJson<int?>(json['removedAt']),
      addedBy: serializer.fromJson<String?>(json['addedBy']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'itemUid': serializer.toJson<String?>(itemUid),
      'title': serializer.toJson<String>(title),
      'titleTransliteration': serializer.toJson<String?>(titleTransliteration),
      'author': serializer.toJson<String?>(author),
      'titleSort': serializer.toJson<String>(titleSort),
      'authorSort': serializer.toJson<String>(authorSort),
      'isbn': serializer.toJson<String?>(isbn),
      'publisher': serializer.toJson<String?>(publisher),
      'publishedYear': serializer.toJson<int?>(publishedYear),
      'genre': serializer.toJson<String?>(genre),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'pageCount': serializer.toJson<int?>(pageCount),
      'language': serializer.toJson<String?>(language),
      'notes': serializer.toJson<String?>(notes),
      'location': serializer.toJson<String?>(location),
      'sourceType': serializer.toJson<String?>(sourceType),
      'sourceDetail': serializer.toJson<String?>(sourceDetail),
      'ageGroup': serializer.toJson<String?>(ageGroup),
      'addedDate': serializer.toJson<int>(addedDate),
      'copyCount': serializer.toJson<int>(copyCount),
      'needsMetadata': serializer.toJson<bool>(needsMetadata),
      'removed': serializer.toJson<bool>(removed),
      'removedAt': serializer.toJson<int?>(removedAt),
      'addedBy': serializer.toJson<String?>(addedBy),
      'kind': serializer.toJson<String>(kind),
    };
  }

  BooksData copyWith({
    int? id,
    Value<String?> itemUid = const Value.absent(),
    String? title,
    Value<String?> titleTransliteration = const Value.absent(),
    Value<String?> author = const Value.absent(),
    String? titleSort,
    String? authorSort,
    Value<String?> isbn = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<int?> publishedYear = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<String?> coverUrl = const Value.absent(),
    Value<int?> pageCount = const Value.absent(),
    Value<String?> language = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> sourceType = const Value.absent(),
    Value<String?> sourceDetail = const Value.absent(),
    Value<String?> ageGroup = const Value.absent(),
    int? addedDate,
    int? copyCount,
    bool? needsMetadata,
    bool? removed,
    Value<int?> removedAt = const Value.absent(),
    Value<String?> addedBy = const Value.absent(),
    String? kind,
  }) => BooksData(
    id: id ?? this.id,
    itemUid: itemUid.present ? itemUid.value : this.itemUid,
    title: title ?? this.title,
    titleTransliteration: titleTransliteration.present
        ? titleTransliteration.value
        : this.titleTransliteration,
    author: author.present ? author.value : this.author,
    titleSort: titleSort ?? this.titleSort,
    authorSort: authorSort ?? this.authorSort,
    isbn: isbn.present ? isbn.value : this.isbn,
    publisher: publisher.present ? publisher.value : this.publisher,
    publishedYear: publishedYear.present
        ? publishedYear.value
        : this.publishedYear,
    genre: genre.present ? genre.value : this.genre,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    pageCount: pageCount.present ? pageCount.value : this.pageCount,
    language: language.present ? language.value : this.language,
    notes: notes.present ? notes.value : this.notes,
    location: location.present ? location.value : this.location,
    sourceType: sourceType.present ? sourceType.value : this.sourceType,
    sourceDetail: sourceDetail.present ? sourceDetail.value : this.sourceDetail,
    ageGroup: ageGroup.present ? ageGroup.value : this.ageGroup,
    addedDate: addedDate ?? this.addedDate,
    copyCount: copyCount ?? this.copyCount,
    needsMetadata: needsMetadata ?? this.needsMetadata,
    removed: removed ?? this.removed,
    removedAt: removedAt.present ? removedAt.value : this.removedAt,
    addedBy: addedBy.present ? addedBy.value : this.addedBy,
    kind: kind ?? this.kind,
  );
  BooksData copyWithCompanion(BooksCompanion data) {
    return BooksData(
      id: data.id.present ? data.id.value : this.id,
      itemUid: data.itemUid.present ? data.itemUid.value : this.itemUid,
      title: data.title.present ? data.title.value : this.title,
      titleTransliteration: data.titleTransliteration.present
          ? data.titleTransliteration.value
          : this.titleTransliteration,
      author: data.author.present ? data.author.value : this.author,
      titleSort: data.titleSort.present ? data.titleSort.value : this.titleSort,
      authorSort: data.authorSort.present
          ? data.authorSort.value
          : this.authorSort,
      isbn: data.isbn.present ? data.isbn.value : this.isbn,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      publishedYear: data.publishedYear.present
          ? data.publishedYear.value
          : this.publishedYear,
      genre: data.genre.present ? data.genre.value : this.genre,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      language: data.language.present ? data.language.value : this.language,
      notes: data.notes.present ? data.notes.value : this.notes,
      location: data.location.present ? data.location.value : this.location,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      sourceDetail: data.sourceDetail.present
          ? data.sourceDetail.value
          : this.sourceDetail,
      ageGroup: data.ageGroup.present ? data.ageGroup.value : this.ageGroup,
      addedDate: data.addedDate.present ? data.addedDate.value : this.addedDate,
      copyCount: data.copyCount.present ? data.copyCount.value : this.copyCount,
      needsMetadata: data.needsMetadata.present
          ? data.needsMetadata.value
          : this.needsMetadata,
      removed: data.removed.present ? data.removed.value : this.removed,
      removedAt: data.removedAt.present ? data.removedAt.value : this.removedAt,
      addedBy: data.addedBy.present ? data.addedBy.value : this.addedBy,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BooksData(')
          ..write('id: $id, ')
          ..write('itemUid: $itemUid, ')
          ..write('title: $title, ')
          ..write('titleTransliteration: $titleTransliteration, ')
          ..write('author: $author, ')
          ..write('titleSort: $titleSort, ')
          ..write('authorSort: $authorSort, ')
          ..write('isbn: $isbn, ')
          ..write('publisher: $publisher, ')
          ..write('publishedYear: $publishedYear, ')
          ..write('genre: $genre, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('pageCount: $pageCount, ')
          ..write('language: $language, ')
          ..write('notes: $notes, ')
          ..write('location: $location, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceDetail: $sourceDetail, ')
          ..write('ageGroup: $ageGroup, ')
          ..write('addedDate: $addedDate, ')
          ..write('copyCount: $copyCount, ')
          ..write('needsMetadata: $needsMetadata, ')
          ..write('removed: $removed, ')
          ..write('removedAt: $removedAt, ')
          ..write('addedBy: $addedBy, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    itemUid,
    title,
    titleTransliteration,
    author,
    titleSort,
    authorSort,
    isbn,
    publisher,
    publishedYear,
    genre,
    coverUrl,
    pageCount,
    language,
    notes,
    location,
    sourceType,
    sourceDetail,
    ageGroup,
    addedDate,
    copyCount,
    needsMetadata,
    removed,
    removedAt,
    addedBy,
    kind,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BooksData &&
          other.id == this.id &&
          other.itemUid == this.itemUid &&
          other.title == this.title &&
          other.titleTransliteration == this.titleTransliteration &&
          other.author == this.author &&
          other.titleSort == this.titleSort &&
          other.authorSort == this.authorSort &&
          other.isbn == this.isbn &&
          other.publisher == this.publisher &&
          other.publishedYear == this.publishedYear &&
          other.genre == this.genre &&
          other.coverUrl == this.coverUrl &&
          other.pageCount == this.pageCount &&
          other.language == this.language &&
          other.notes == this.notes &&
          other.location == this.location &&
          other.sourceType == this.sourceType &&
          other.sourceDetail == this.sourceDetail &&
          other.ageGroup == this.ageGroup &&
          other.addedDate == this.addedDate &&
          other.copyCount == this.copyCount &&
          other.needsMetadata == this.needsMetadata &&
          other.removed == this.removed &&
          other.removedAt == this.removedAt &&
          other.addedBy == this.addedBy &&
          other.kind == this.kind);
}

class BooksCompanion extends UpdateCompanion<BooksData> {
  final Value<int> id;
  final Value<String?> itemUid;
  final Value<String> title;
  final Value<String?> titleTransliteration;
  final Value<String?> author;
  final Value<String> titleSort;
  final Value<String> authorSort;
  final Value<String?> isbn;
  final Value<String?> publisher;
  final Value<int?> publishedYear;
  final Value<String?> genre;
  final Value<String?> coverUrl;
  final Value<int?> pageCount;
  final Value<String?> language;
  final Value<String?> notes;
  final Value<String?> location;
  final Value<String?> sourceType;
  final Value<String?> sourceDetail;
  final Value<String?> ageGroup;
  final Value<int> addedDate;
  final Value<int> copyCount;
  final Value<bool> needsMetadata;
  final Value<bool> removed;
  final Value<int?> removedAt;
  final Value<String?> addedBy;
  final Value<String> kind;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.itemUid = const Value.absent(),
    this.title = const Value.absent(),
    this.titleTransliteration = const Value.absent(),
    this.author = const Value.absent(),
    this.titleSort = const Value.absent(),
    this.authorSort = const Value.absent(),
    this.isbn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedYear = const Value.absent(),
    this.genre = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.language = const Value.absent(),
    this.notes = const Value.absent(),
    this.location = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceDetail = const Value.absent(),
    this.ageGroup = const Value.absent(),
    this.addedDate = const Value.absent(),
    this.copyCount = const Value.absent(),
    this.needsMetadata = const Value.absent(),
    this.removed = const Value.absent(),
    this.removedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.kind = const Value.absent(),
  });
  BooksCompanion.insert({
    this.id = const Value.absent(),
    this.itemUid = const Value.absent(),
    required String title,
    this.titleTransliteration = const Value.absent(),
    this.author = const Value.absent(),
    this.titleSort = const Value.absent(),
    this.authorSort = const Value.absent(),
    this.isbn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedYear = const Value.absent(),
    this.genre = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.language = const Value.absent(),
    this.notes = const Value.absent(),
    this.location = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceDetail = const Value.absent(),
    this.ageGroup = const Value.absent(),
    required int addedDate,
    this.copyCount = const Value.absent(),
    this.needsMetadata = const Value.absent(),
    this.removed = const Value.absent(),
    this.removedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.kind = const Value.absent(),
  }) : title = Value(title),
       addedDate = Value(addedDate);
  static Insertable<BooksData> custom({
    Expression<int>? id,
    Expression<String>? itemUid,
    Expression<String>? title,
    Expression<String>? titleTransliteration,
    Expression<String>? author,
    Expression<String>? titleSort,
    Expression<String>? authorSort,
    Expression<String>? isbn,
    Expression<String>? publisher,
    Expression<int>? publishedYear,
    Expression<String>? genre,
    Expression<String>? coverUrl,
    Expression<int>? pageCount,
    Expression<String>? language,
    Expression<String>? notes,
    Expression<String>? location,
    Expression<String>? sourceType,
    Expression<String>? sourceDetail,
    Expression<String>? ageGroup,
    Expression<int>? addedDate,
    Expression<int>? copyCount,
    Expression<bool>? needsMetadata,
    Expression<bool>? removed,
    Expression<int>? removedAt,
    Expression<String>? addedBy,
    Expression<String>? kind,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemUid != null) 'book_uid': itemUid,
      if (title != null) 'title': title,
      if (titleTransliteration != null)
        'title_transliteration': titleTransliteration,
      if (author != null) 'author': author,
      if (titleSort != null) 'title_sort': titleSort,
      if (authorSort != null) 'author_sort': authorSort,
      if (isbn != null) 'isbn': isbn,
      if (publisher != null) 'publisher': publisher,
      if (publishedYear != null) 'published_year': publishedYear,
      if (genre != null) 'genre': genre,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (pageCount != null) 'page_count': pageCount,
      if (language != null) 'language': language,
      if (notes != null) 'notes': notes,
      if (location != null) 'location': location,
      if (sourceType != null) 'source_type': sourceType,
      if (sourceDetail != null) 'source_detail': sourceDetail,
      if (ageGroup != null) 'age_group': ageGroup,
      if (addedDate != null) 'added_date': addedDate,
      if (copyCount != null) 'copy_count': copyCount,
      if (needsMetadata != null) 'needs_metadata': needsMetadata,
      if (removed != null) 'removed': removed,
      if (removedAt != null) 'removed_at': removedAt,
      if (addedBy != null) 'added_by': addedBy,
      if (kind != null) 'kind': kind,
    });
  }

  BooksCompanion copyWith({
    Value<int>? id,
    Value<String?>? itemUid,
    Value<String>? title,
    Value<String?>? titleTransliteration,
    Value<String?>? author,
    Value<String>? titleSort,
    Value<String>? authorSort,
    Value<String?>? isbn,
    Value<String?>? publisher,
    Value<int?>? publishedYear,
    Value<String?>? genre,
    Value<String?>? coverUrl,
    Value<int?>? pageCount,
    Value<String?>? language,
    Value<String?>? notes,
    Value<String?>? location,
    Value<String?>? sourceType,
    Value<String?>? sourceDetail,
    Value<String?>? ageGroup,
    Value<int>? addedDate,
    Value<int>? copyCount,
    Value<bool>? needsMetadata,
    Value<bool>? removed,
    Value<int?>? removedAt,
    Value<String?>? addedBy,
    Value<String>? kind,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      itemUid: itemUid ?? this.itemUid,
      title: title ?? this.title,
      titleTransliteration: titleTransliteration ?? this.titleTransliteration,
      author: author ?? this.author,
      titleSort: titleSort ?? this.titleSort,
      authorSort: authorSort ?? this.authorSort,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
      publishedYear: publishedYear ?? this.publishedYear,
      genre: genre ?? this.genre,
      coverUrl: coverUrl ?? this.coverUrl,
      pageCount: pageCount ?? this.pageCount,
      language: language ?? this.language,
      notes: notes ?? this.notes,
      location: location ?? this.location,
      sourceType: sourceType ?? this.sourceType,
      sourceDetail: sourceDetail ?? this.sourceDetail,
      ageGroup: ageGroup ?? this.ageGroup,
      addedDate: addedDate ?? this.addedDate,
      copyCount: copyCount ?? this.copyCount,
      needsMetadata: needsMetadata ?? this.needsMetadata,
      removed: removed ?? this.removed,
      removedAt: removedAt ?? this.removedAt,
      addedBy: addedBy ?? this.addedBy,
      kind: kind ?? this.kind,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (itemUid.present) {
      map['book_uid'] = Variable<String>(itemUid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleTransliteration.present) {
      map['title_transliteration'] = Variable<String>(
        titleTransliteration.value,
      );
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (titleSort.present) {
      map['title_sort'] = Variable<String>(titleSort.value);
    }
    if (authorSort.present) {
      map['author_sort'] = Variable<String>(authorSort.value);
    }
    if (isbn.present) {
      map['isbn'] = Variable<String>(isbn.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (publishedYear.present) {
      map['published_year'] = Variable<int>(publishedYear.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (sourceDetail.present) {
      map['source_detail'] = Variable<String>(sourceDetail.value);
    }
    if (ageGroup.present) {
      map['age_group'] = Variable<String>(ageGroup.value);
    }
    if (addedDate.present) {
      map['added_date'] = Variable<int>(addedDate.value);
    }
    if (copyCount.present) {
      map['copy_count'] = Variable<int>(copyCount.value);
    }
    if (needsMetadata.present) {
      map['needs_metadata'] = Variable<bool>(needsMetadata.value);
    }
    if (removed.present) {
      map['removed'] = Variable<bool>(removed.value);
    }
    if (removedAt.present) {
      map['removed_at'] = Variable<int>(removedAt.value);
    }
    if (addedBy.present) {
      map['added_by'] = Variable<String>(addedBy.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('itemUid: $itemUid, ')
          ..write('title: $title, ')
          ..write('titleTransliteration: $titleTransliteration, ')
          ..write('author: $author, ')
          ..write('titleSort: $titleSort, ')
          ..write('authorSort: $authorSort, ')
          ..write('isbn: $isbn, ')
          ..write('publisher: $publisher, ')
          ..write('publishedYear: $publishedYear, ')
          ..write('genre: $genre, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('pageCount: $pageCount, ')
          ..write('language: $language, ')
          ..write('notes: $notes, ')
          ..write('location: $location, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceDetail: $sourceDetail, ')
          ..write('ageGroup: $ageGroup, ')
          ..write('addedDate: $addedDate, ')
          ..write('copyCount: $copyCount, ')
          ..write('needsMetadata: $needsMetadata, ')
          ..write('removed: $removed, ')
          ..write('removedAt: $removedAt, ')
          ..write('addedBy: $addedBy, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }
}

class WishlistBooks extends Table
    with TableInfo<WishlistBooks, WishlistBooksData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  WishlistBooks(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> titleTransliteration =
      GeneratedColumn<String>(
        'title_transliteration',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> isbn = GeneratedColumn<String>(
    'isbn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> publishedYear = GeneratedColumn<int>(
    'published_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<double> priceEstimate = GeneratedColumn<double>(
    'price_estimate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('1'),
  );
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'MANUAL\''),
  );
  late final GeneratedColumn<int> addedDate = GeneratedColumn<int>(
    'added_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> purchased = GeneratedColumn<bool>(
    'purchased',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("purchased" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> purchasedDate = GeneratedColumn<int>(
    'purchased_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<bool> needsMetadata = GeneratedColumn<bool>(
    'needs_metadata',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_metadata" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    titleTransliteration,
    author,
    isbn,
    publisher,
    publishedYear,
    coverUrl,
    priceEstimate,
    priority,
    notes,
    source,
    addedDate,
    purchased,
    purchasedDate,
    needsMetadata,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wishlist_books';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WishlistBooksData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WishlistBooksData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleTransliteration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_transliteration'],
      ),
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      isbn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isbn'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      publishedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}published_year'],
      ),
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      priceEstimate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price_estimate'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      addedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_date'],
      )!,
      purchased: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}purchased'],
      )!,
      purchasedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}purchased_date'],
      ),
      needsMetadata: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_metadata'],
      )!,
    );
  }

  @override
  WishlistBooks createAlias(String alias) {
    return WishlistBooks(attachedDatabase, alias);
  }
}

class WishlistBooksData extends DataClass
    implements Insertable<WishlistBooksData> {
  final int id;
  final String title;
  final String? titleTransliteration;
  final String? author;
  final String? isbn;
  final String? publisher;
  final int? publishedYear;
  final String? coverUrl;
  final double? priceEstimate;
  final int priority;
  final String? notes;
  final String source;
  final int addedDate;
  final bool purchased;
  final int? purchasedDate;
  final bool needsMetadata;
  const WishlistBooksData({
    required this.id,
    required this.title,
    this.titleTransliteration,
    this.author,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.coverUrl,
    this.priceEstimate,
    required this.priority,
    this.notes,
    required this.source,
    required this.addedDate,
    required this.purchased,
    this.purchasedDate,
    required this.needsMetadata,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || titleTransliteration != null) {
      map['title_transliteration'] = Variable<String>(titleTransliteration);
    }
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || isbn != null) {
      map['isbn'] = Variable<String>(isbn);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || publishedYear != null) {
      map['published_year'] = Variable<int>(publishedYear);
    }
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    if (!nullToAbsent || priceEstimate != null) {
      map['price_estimate'] = Variable<double>(priceEstimate);
    }
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['source'] = Variable<String>(source);
    map['added_date'] = Variable<int>(addedDate);
    map['purchased'] = Variable<bool>(purchased);
    if (!nullToAbsent || purchasedDate != null) {
      map['purchased_date'] = Variable<int>(purchasedDate);
    }
    map['needs_metadata'] = Variable<bool>(needsMetadata);
    return map;
  }

  WishlistBooksCompanion toCompanion(bool nullToAbsent) {
    return WishlistBooksCompanion(
      id: Value(id),
      title: Value(title),
      titleTransliteration: titleTransliteration == null && nullToAbsent
          ? const Value.absent()
          : Value(titleTransliteration),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      isbn: isbn == null && nullToAbsent ? const Value.absent() : Value(isbn),
      publisher: publisher == null && nullToAbsent
          ? const Value.absent()
          : Value(publisher),
      publishedYear: publishedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedYear),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      priceEstimate: priceEstimate == null && nullToAbsent
          ? const Value.absent()
          : Value(priceEstimate),
      priority: Value(priority),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      source: Value(source),
      addedDate: Value(addedDate),
      purchased: Value(purchased),
      purchasedDate: purchasedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(purchasedDate),
      needsMetadata: Value(needsMetadata),
    );
  }

  factory WishlistBooksData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WishlistBooksData(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      titleTransliteration: serializer.fromJson<String?>(
        json['titleTransliteration'],
      ),
      author: serializer.fromJson<String?>(json['author']),
      isbn: serializer.fromJson<String?>(json['isbn']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      publishedYear: serializer.fromJson<int?>(json['publishedYear']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      priceEstimate: serializer.fromJson<double?>(json['priceEstimate']),
      priority: serializer.fromJson<int>(json['priority']),
      notes: serializer.fromJson<String?>(json['notes']),
      source: serializer.fromJson<String>(json['source']),
      addedDate: serializer.fromJson<int>(json['addedDate']),
      purchased: serializer.fromJson<bool>(json['purchased']),
      purchasedDate: serializer.fromJson<int?>(json['purchasedDate']),
      needsMetadata: serializer.fromJson<bool>(json['needsMetadata']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'titleTransliteration': serializer.toJson<String?>(titleTransliteration),
      'author': serializer.toJson<String?>(author),
      'isbn': serializer.toJson<String?>(isbn),
      'publisher': serializer.toJson<String?>(publisher),
      'publishedYear': serializer.toJson<int?>(publishedYear),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'priceEstimate': serializer.toJson<double?>(priceEstimate),
      'priority': serializer.toJson<int>(priority),
      'notes': serializer.toJson<String?>(notes),
      'source': serializer.toJson<String>(source),
      'addedDate': serializer.toJson<int>(addedDate),
      'purchased': serializer.toJson<bool>(purchased),
      'purchasedDate': serializer.toJson<int?>(purchasedDate),
      'needsMetadata': serializer.toJson<bool>(needsMetadata),
    };
  }

  WishlistBooksData copyWith({
    int? id,
    String? title,
    Value<String?> titleTransliteration = const Value.absent(),
    Value<String?> author = const Value.absent(),
    Value<String?> isbn = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<int?> publishedYear = const Value.absent(),
    Value<String?> coverUrl = const Value.absent(),
    Value<double?> priceEstimate = const Value.absent(),
    int? priority,
    Value<String?> notes = const Value.absent(),
    String? source,
    int? addedDate,
    bool? purchased,
    Value<int?> purchasedDate = const Value.absent(),
    bool? needsMetadata,
  }) => WishlistBooksData(
    id: id ?? this.id,
    title: title ?? this.title,
    titleTransliteration: titleTransliteration.present
        ? titleTransliteration.value
        : this.titleTransliteration,
    author: author.present ? author.value : this.author,
    isbn: isbn.present ? isbn.value : this.isbn,
    publisher: publisher.present ? publisher.value : this.publisher,
    publishedYear: publishedYear.present
        ? publishedYear.value
        : this.publishedYear,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    priceEstimate: priceEstimate.present
        ? priceEstimate.value
        : this.priceEstimate,
    priority: priority ?? this.priority,
    notes: notes.present ? notes.value : this.notes,
    source: source ?? this.source,
    addedDate: addedDate ?? this.addedDate,
    purchased: purchased ?? this.purchased,
    purchasedDate: purchasedDate.present
        ? purchasedDate.value
        : this.purchasedDate,
    needsMetadata: needsMetadata ?? this.needsMetadata,
  );
  WishlistBooksData copyWithCompanion(WishlistBooksCompanion data) {
    return WishlistBooksData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      titleTransliteration: data.titleTransliteration.present
          ? data.titleTransliteration.value
          : this.titleTransliteration,
      author: data.author.present ? data.author.value : this.author,
      isbn: data.isbn.present ? data.isbn.value : this.isbn,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      publishedYear: data.publishedYear.present
          ? data.publishedYear.value
          : this.publishedYear,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      priceEstimate: data.priceEstimate.present
          ? data.priceEstimate.value
          : this.priceEstimate,
      priority: data.priority.present ? data.priority.value : this.priority,
      notes: data.notes.present ? data.notes.value : this.notes,
      source: data.source.present ? data.source.value : this.source,
      addedDate: data.addedDate.present ? data.addedDate.value : this.addedDate,
      purchased: data.purchased.present ? data.purchased.value : this.purchased,
      purchasedDate: data.purchasedDate.present
          ? data.purchasedDate.value
          : this.purchasedDate,
      needsMetadata: data.needsMetadata.present
          ? data.needsMetadata.value
          : this.needsMetadata,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WishlistBooksData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('titleTransliteration: $titleTransliteration, ')
          ..write('author: $author, ')
          ..write('isbn: $isbn, ')
          ..write('publisher: $publisher, ')
          ..write('publishedYear: $publishedYear, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('priceEstimate: $priceEstimate, ')
          ..write('priority: $priority, ')
          ..write('notes: $notes, ')
          ..write('source: $source, ')
          ..write('addedDate: $addedDate, ')
          ..write('purchased: $purchased, ')
          ..write('purchasedDate: $purchasedDate, ')
          ..write('needsMetadata: $needsMetadata')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    titleTransliteration,
    author,
    isbn,
    publisher,
    publishedYear,
    coverUrl,
    priceEstimate,
    priority,
    notes,
    source,
    addedDate,
    purchased,
    purchasedDate,
    needsMetadata,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WishlistBooksData &&
          other.id == this.id &&
          other.title == this.title &&
          other.titleTransliteration == this.titleTransliteration &&
          other.author == this.author &&
          other.isbn == this.isbn &&
          other.publisher == this.publisher &&
          other.publishedYear == this.publishedYear &&
          other.coverUrl == this.coverUrl &&
          other.priceEstimate == this.priceEstimate &&
          other.priority == this.priority &&
          other.notes == this.notes &&
          other.source == this.source &&
          other.addedDate == this.addedDate &&
          other.purchased == this.purchased &&
          other.purchasedDate == this.purchasedDate &&
          other.needsMetadata == this.needsMetadata);
}

class WishlistBooksCompanion extends UpdateCompanion<WishlistBooksData> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> titleTransliteration;
  final Value<String?> author;
  final Value<String?> isbn;
  final Value<String?> publisher;
  final Value<int?> publishedYear;
  final Value<String?> coverUrl;
  final Value<double?> priceEstimate;
  final Value<int> priority;
  final Value<String?> notes;
  final Value<String> source;
  final Value<int> addedDate;
  final Value<bool> purchased;
  final Value<int?> purchasedDate;
  final Value<bool> needsMetadata;
  const WishlistBooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.titleTransliteration = const Value.absent(),
    this.author = const Value.absent(),
    this.isbn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedYear = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.priceEstimate = const Value.absent(),
    this.priority = const Value.absent(),
    this.notes = const Value.absent(),
    this.source = const Value.absent(),
    this.addedDate = const Value.absent(),
    this.purchased = const Value.absent(),
    this.purchasedDate = const Value.absent(),
    this.needsMetadata = const Value.absent(),
  });
  WishlistBooksCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.titleTransliteration = const Value.absent(),
    this.author = const Value.absent(),
    this.isbn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedYear = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.priceEstimate = const Value.absent(),
    this.priority = const Value.absent(),
    this.notes = const Value.absent(),
    this.source = const Value.absent(),
    required int addedDate,
    this.purchased = const Value.absent(),
    this.purchasedDate = const Value.absent(),
    this.needsMetadata = const Value.absent(),
  }) : title = Value(title),
       addedDate = Value(addedDate);
  static Insertable<WishlistBooksData> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? titleTransliteration,
    Expression<String>? author,
    Expression<String>? isbn,
    Expression<String>? publisher,
    Expression<int>? publishedYear,
    Expression<String>? coverUrl,
    Expression<double>? priceEstimate,
    Expression<int>? priority,
    Expression<String>? notes,
    Expression<String>? source,
    Expression<int>? addedDate,
    Expression<bool>? purchased,
    Expression<int>? purchasedDate,
    Expression<bool>? needsMetadata,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (titleTransliteration != null)
        'title_transliteration': titleTransliteration,
      if (author != null) 'author': author,
      if (isbn != null) 'isbn': isbn,
      if (publisher != null) 'publisher': publisher,
      if (publishedYear != null) 'published_year': publishedYear,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (priceEstimate != null) 'price_estimate': priceEstimate,
      if (priority != null) 'priority': priority,
      if (notes != null) 'notes': notes,
      if (source != null) 'source': source,
      if (addedDate != null) 'added_date': addedDate,
      if (purchased != null) 'purchased': purchased,
      if (purchasedDate != null) 'purchased_date': purchasedDate,
      if (needsMetadata != null) 'needs_metadata': needsMetadata,
    });
  }

  WishlistBooksCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? titleTransliteration,
    Value<String?>? author,
    Value<String?>? isbn,
    Value<String?>? publisher,
    Value<int?>? publishedYear,
    Value<String?>? coverUrl,
    Value<double?>? priceEstimate,
    Value<int>? priority,
    Value<String?>? notes,
    Value<String>? source,
    Value<int>? addedDate,
    Value<bool>? purchased,
    Value<int?>? purchasedDate,
    Value<bool>? needsMetadata,
  }) {
    return WishlistBooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      titleTransliteration: titleTransliteration ?? this.titleTransliteration,
      author: author ?? this.author,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
      publishedYear: publishedYear ?? this.publishedYear,
      coverUrl: coverUrl ?? this.coverUrl,
      priceEstimate: priceEstimate ?? this.priceEstimate,
      priority: priority ?? this.priority,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      addedDate: addedDate ?? this.addedDate,
      purchased: purchased ?? this.purchased,
      purchasedDate: purchasedDate ?? this.purchasedDate,
      needsMetadata: needsMetadata ?? this.needsMetadata,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleTransliteration.present) {
      map['title_transliteration'] = Variable<String>(
        titleTransliteration.value,
      );
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (isbn.present) {
      map['isbn'] = Variable<String>(isbn.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (publishedYear.present) {
      map['published_year'] = Variable<int>(publishedYear.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (priceEstimate.present) {
      map['price_estimate'] = Variable<double>(priceEstimate.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (addedDate.present) {
      map['added_date'] = Variable<int>(addedDate.value);
    }
    if (purchased.present) {
      map['purchased'] = Variable<bool>(purchased.value);
    }
    if (purchasedDate.present) {
      map['purchased_date'] = Variable<int>(purchasedDate.value);
    }
    if (needsMetadata.present) {
      map['needs_metadata'] = Variable<bool>(needsMetadata.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WishlistBooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('titleTransliteration: $titleTransliteration, ')
          ..write('author: $author, ')
          ..write('isbn: $isbn, ')
          ..write('publisher: $publisher, ')
          ..write('publishedYear: $publishedYear, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('priceEstimate: $priceEstimate, ')
          ..write('priority: $priority, ')
          ..write('notes: $notes, ')
          ..write('source: $source, ')
          ..write('addedDate: $addedDate, ')
          ..write('purchased: $purchased, ')
          ..write('purchasedDate: $purchasedDate, ')
          ..write('needsMetadata: $needsMetadata')
          ..write(')'))
        .toString();
  }
}

class NetworkLibraries extends Table
    with TableInfo<NetworkLibraries, NetworkLibrariesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NetworkLibraries(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<String> siteUrl = GeneratedColumn<String>(
    'site_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'\''),
  );
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> precision = GeneratedColumn<String>(
    'precision',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> isMember = GeneratedColumn<bool>(
    'is_member',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_member" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<bool> memberVerified = GeneratedColumn<bool>(
    'member_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("member_verified" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<String> listedByHubUrl = GeneratedColumn<String>(
    'listed_by_hub_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> membership = GeneratedColumn<String>(
    'membership',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'none\''),
  );
  late final GeneratedColumn<String> fetchStatus = GeneratedColumn<String>(
    'fetch_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'never\''),
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> confirmedByMember = GeneratedColumn<bool>(
    'confirmed_by_member',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("confirmed_by_member" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    siteUrl,
    name,
    fingerprint,
    lat,
    lng,
    precision,
    source,
    isMember,
    memberVerified,
    listedByHubUrl,
    membership,
    fetchStatus,
    fetchedAt,
    createdAt,
    sortOrder,
    confirmedByMember,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'network_libraries';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {fingerprint},
  ];
  @override
  NetworkLibrariesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NetworkLibrariesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      siteUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_url'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      precision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}precision'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      isMember: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_member'],
      )!,
      memberVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}member_verified'],
      )!,
      listedByHubUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}listed_by_hub_url'],
      ),
      membership: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}membership'],
      )!,
      fetchStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fetch_status'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      confirmedByMember: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}confirmed_by_member'],
      )!,
    );
  }

  @override
  NetworkLibraries createAlias(String alias) {
    return NetworkLibraries(attachedDatabase, alias);
  }
}

class NetworkLibrariesData extends DataClass
    implements Insertable<NetworkLibrariesData> {
  final int id;
  final String siteUrl;
  final String name;
  final String? fingerprint;
  final double? lat;
  final double? lng;
  final String? precision;
  final String source;
  final bool isMember;
  final bool memberVerified;
  final String? listedByHubUrl;
  final String membership;
  final String fetchStatus;
  final int? fetchedAt;
  final int createdAt;
  final int sortOrder;
  final bool confirmedByMember;
  const NetworkLibrariesData({
    required this.id,
    required this.siteUrl,
    required this.name,
    this.fingerprint,
    this.lat,
    this.lng,
    this.precision,
    required this.source,
    required this.isMember,
    required this.memberVerified,
    this.listedByHubUrl,
    required this.membership,
    required this.fetchStatus,
    this.fetchedAt,
    required this.createdAt,
    required this.sortOrder,
    required this.confirmedByMember,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['site_url'] = Variable<String>(siteUrl);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || fingerprint != null) {
      map['fingerprint'] = Variable<String>(fingerprint);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    if (!nullToAbsent || precision != null) {
      map['precision'] = Variable<String>(precision);
    }
    map['source'] = Variable<String>(source);
    map['is_member'] = Variable<bool>(isMember);
    map['member_verified'] = Variable<bool>(memberVerified);
    if (!nullToAbsent || listedByHubUrl != null) {
      map['listed_by_hub_url'] = Variable<String>(listedByHubUrl);
    }
    map['membership'] = Variable<String>(membership);
    map['fetch_status'] = Variable<String>(fetchStatus);
    if (!nullToAbsent || fetchedAt != null) {
      map['fetched_at'] = Variable<int>(fetchedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['sort_order'] = Variable<int>(sortOrder);
    map['confirmed_by_member'] = Variable<bool>(confirmedByMember);
    return map;
  }

  NetworkLibrariesCompanion toCompanion(bool nullToAbsent) {
    return NetworkLibrariesCompanion(
      id: Value(id),
      siteUrl: Value(siteUrl),
      name: Value(name),
      fingerprint: fingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(fingerprint),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      precision: precision == null && nullToAbsent
          ? const Value.absent()
          : Value(precision),
      source: Value(source),
      isMember: Value(isMember),
      memberVerified: Value(memberVerified),
      listedByHubUrl: listedByHubUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(listedByHubUrl),
      membership: Value(membership),
      fetchStatus: Value(fetchStatus),
      fetchedAt: fetchedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(fetchedAt),
      createdAt: Value(createdAt),
      sortOrder: Value(sortOrder),
      confirmedByMember: Value(confirmedByMember),
    );
  }

  factory NetworkLibrariesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NetworkLibrariesData(
      id: serializer.fromJson<int>(json['id']),
      siteUrl: serializer.fromJson<String>(json['siteUrl']),
      name: serializer.fromJson<String>(json['name']),
      fingerprint: serializer.fromJson<String?>(json['fingerprint']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      precision: serializer.fromJson<String?>(json['precision']),
      source: serializer.fromJson<String>(json['source']),
      isMember: serializer.fromJson<bool>(json['isMember']),
      memberVerified: serializer.fromJson<bool>(json['memberVerified']),
      listedByHubUrl: serializer.fromJson<String?>(json['listedByHubUrl']),
      membership: serializer.fromJson<String>(json['membership']),
      fetchStatus: serializer.fromJson<String>(json['fetchStatus']),
      fetchedAt: serializer.fromJson<int?>(json['fetchedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      confirmedByMember: serializer.fromJson<bool>(json['confirmedByMember']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'siteUrl': serializer.toJson<String>(siteUrl),
      'name': serializer.toJson<String>(name),
      'fingerprint': serializer.toJson<String?>(fingerprint),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'precision': serializer.toJson<String?>(precision),
      'source': serializer.toJson<String>(source),
      'isMember': serializer.toJson<bool>(isMember),
      'memberVerified': serializer.toJson<bool>(memberVerified),
      'listedByHubUrl': serializer.toJson<String?>(listedByHubUrl),
      'membership': serializer.toJson<String>(membership),
      'fetchStatus': serializer.toJson<String>(fetchStatus),
      'fetchedAt': serializer.toJson<int?>(fetchedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'confirmedByMember': serializer.toJson<bool>(confirmedByMember),
    };
  }

  NetworkLibrariesData copyWith({
    int? id,
    String? siteUrl,
    String? name,
    Value<String?> fingerprint = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    Value<String?> precision = const Value.absent(),
    String? source,
    bool? isMember,
    bool? memberVerified,
    Value<String?> listedByHubUrl = const Value.absent(),
    String? membership,
    String? fetchStatus,
    Value<int?> fetchedAt = const Value.absent(),
    int? createdAt,
    int? sortOrder,
    bool? confirmedByMember,
  }) => NetworkLibrariesData(
    id: id ?? this.id,
    siteUrl: siteUrl ?? this.siteUrl,
    name: name ?? this.name,
    fingerprint: fingerprint.present ? fingerprint.value : this.fingerprint,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    precision: precision.present ? precision.value : this.precision,
    source: source ?? this.source,
    isMember: isMember ?? this.isMember,
    memberVerified: memberVerified ?? this.memberVerified,
    listedByHubUrl: listedByHubUrl.present
        ? listedByHubUrl.value
        : this.listedByHubUrl,
    membership: membership ?? this.membership,
    fetchStatus: fetchStatus ?? this.fetchStatus,
    fetchedAt: fetchedAt.present ? fetchedAt.value : this.fetchedAt,
    createdAt: createdAt ?? this.createdAt,
    sortOrder: sortOrder ?? this.sortOrder,
    confirmedByMember: confirmedByMember ?? this.confirmedByMember,
  );
  NetworkLibrariesData copyWithCompanion(NetworkLibrariesCompanion data) {
    return NetworkLibrariesData(
      id: data.id.present ? data.id.value : this.id,
      siteUrl: data.siteUrl.present ? data.siteUrl.value : this.siteUrl,
      name: data.name.present ? data.name.value : this.name,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      precision: data.precision.present ? data.precision.value : this.precision,
      source: data.source.present ? data.source.value : this.source,
      isMember: data.isMember.present ? data.isMember.value : this.isMember,
      memberVerified: data.memberVerified.present
          ? data.memberVerified.value
          : this.memberVerified,
      listedByHubUrl: data.listedByHubUrl.present
          ? data.listedByHubUrl.value
          : this.listedByHubUrl,
      membership: data.membership.present
          ? data.membership.value
          : this.membership,
      fetchStatus: data.fetchStatus.present
          ? data.fetchStatus.value
          : this.fetchStatus,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      confirmedByMember: data.confirmedByMember.present
          ? data.confirmedByMember.value
          : this.confirmedByMember,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NetworkLibrariesData(')
          ..write('id: $id, ')
          ..write('siteUrl: $siteUrl, ')
          ..write('name: $name, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('precision: $precision, ')
          ..write('source: $source, ')
          ..write('isMember: $isMember, ')
          ..write('memberVerified: $memberVerified, ')
          ..write('listedByHubUrl: $listedByHubUrl, ')
          ..write('membership: $membership, ')
          ..write('fetchStatus: $fetchStatus, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('confirmedByMember: $confirmedByMember')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    siteUrl,
    name,
    fingerprint,
    lat,
    lng,
    precision,
    source,
    isMember,
    memberVerified,
    listedByHubUrl,
    membership,
    fetchStatus,
    fetchedAt,
    createdAt,
    sortOrder,
    confirmedByMember,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkLibrariesData &&
          other.id == this.id &&
          other.siteUrl == this.siteUrl &&
          other.name == this.name &&
          other.fingerprint == this.fingerprint &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.precision == this.precision &&
          other.source == this.source &&
          other.isMember == this.isMember &&
          other.memberVerified == this.memberVerified &&
          other.listedByHubUrl == this.listedByHubUrl &&
          other.membership == this.membership &&
          other.fetchStatus == this.fetchStatus &&
          other.fetchedAt == this.fetchedAt &&
          other.createdAt == this.createdAt &&
          other.sortOrder == this.sortOrder &&
          other.confirmedByMember == this.confirmedByMember);
}

class NetworkLibrariesCompanion extends UpdateCompanion<NetworkLibrariesData> {
  final Value<int> id;
  final Value<String> siteUrl;
  final Value<String> name;
  final Value<String?> fingerprint;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<String?> precision;
  final Value<String> source;
  final Value<bool> isMember;
  final Value<bool> memberVerified;
  final Value<String?> listedByHubUrl;
  final Value<String> membership;
  final Value<String> fetchStatus;
  final Value<int?> fetchedAt;
  final Value<int> createdAt;
  final Value<int> sortOrder;
  final Value<bool> confirmedByMember;
  const NetworkLibrariesCompanion({
    this.id = const Value.absent(),
    this.siteUrl = const Value.absent(),
    this.name = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.precision = const Value.absent(),
    this.source = const Value.absent(),
    this.isMember = const Value.absent(),
    this.memberVerified = const Value.absent(),
    this.listedByHubUrl = const Value.absent(),
    this.membership = const Value.absent(),
    this.fetchStatus = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.confirmedByMember = const Value.absent(),
  });
  NetworkLibrariesCompanion.insert({
    this.id = const Value.absent(),
    required String siteUrl,
    this.name = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.precision = const Value.absent(),
    required String source,
    this.isMember = const Value.absent(),
    this.memberVerified = const Value.absent(),
    this.listedByHubUrl = const Value.absent(),
    this.membership = const Value.absent(),
    this.fetchStatus = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    required int createdAt,
    required int sortOrder,
    this.confirmedByMember = const Value.absent(),
  }) : siteUrl = Value(siteUrl),
       source = Value(source),
       createdAt = Value(createdAt),
       sortOrder = Value(sortOrder);
  static Insertable<NetworkLibrariesData> custom({
    Expression<int>? id,
    Expression<String>? siteUrl,
    Expression<String>? name,
    Expression<String>? fingerprint,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? precision,
    Expression<String>? source,
    Expression<bool>? isMember,
    Expression<bool>? memberVerified,
    Expression<String>? listedByHubUrl,
    Expression<String>? membership,
    Expression<String>? fetchStatus,
    Expression<int>? fetchedAt,
    Expression<int>? createdAt,
    Expression<int>? sortOrder,
    Expression<bool>? confirmedByMember,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteUrl != null) 'site_url': siteUrl,
      if (name != null) 'name': name,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (precision != null) 'precision': precision,
      if (source != null) 'source': source,
      if (isMember != null) 'is_member': isMember,
      if (memberVerified != null) 'member_verified': memberVerified,
      if (listedByHubUrl != null) 'listed_by_hub_url': listedByHubUrl,
      if (membership != null) 'membership': membership,
      if (fetchStatus != null) 'fetch_status': fetchStatus,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (confirmedByMember != null) 'confirmed_by_member': confirmedByMember,
    });
  }

  NetworkLibrariesCompanion copyWith({
    Value<int>? id,
    Value<String>? siteUrl,
    Value<String>? name,
    Value<String?>? fingerprint,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<String?>? precision,
    Value<String>? source,
    Value<bool>? isMember,
    Value<bool>? memberVerified,
    Value<String?>? listedByHubUrl,
    Value<String>? membership,
    Value<String>? fetchStatus,
    Value<int?>? fetchedAt,
    Value<int>? createdAt,
    Value<int>? sortOrder,
    Value<bool>? confirmedByMember,
  }) {
    return NetworkLibrariesCompanion(
      id: id ?? this.id,
      siteUrl: siteUrl ?? this.siteUrl,
      name: name ?? this.name,
      fingerprint: fingerprint ?? this.fingerprint,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      precision: precision ?? this.precision,
      source: source ?? this.source,
      isMember: isMember ?? this.isMember,
      memberVerified: memberVerified ?? this.memberVerified,
      listedByHubUrl: listedByHubUrl ?? this.listedByHubUrl,
      membership: membership ?? this.membership,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      confirmedByMember: confirmedByMember ?? this.confirmedByMember,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (siteUrl.present) {
      map['site_url'] = Variable<String>(siteUrl.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (precision.present) {
      map['precision'] = Variable<String>(precision.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (isMember.present) {
      map['is_member'] = Variable<bool>(isMember.value);
    }
    if (memberVerified.present) {
      map['member_verified'] = Variable<bool>(memberVerified.value);
    }
    if (listedByHubUrl.present) {
      map['listed_by_hub_url'] = Variable<String>(listedByHubUrl.value);
    }
    if (membership.present) {
      map['membership'] = Variable<String>(membership.value);
    }
    if (fetchStatus.present) {
      map['fetch_status'] = Variable<String>(fetchStatus.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (confirmedByMember.present) {
      map['confirmed_by_member'] = Variable<bool>(confirmedByMember.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NetworkLibrariesCompanion(')
          ..write('id: $id, ')
          ..write('siteUrl: $siteUrl, ')
          ..write('name: $name, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('precision: $precision, ')
          ..write('source: $source, ')
          ..write('isMember: $isMember, ')
          ..write('memberVerified: $memberVerified, ')
          ..write('listedByHubUrl: $listedByHubUrl, ')
          ..write('membership: $membership, ')
          ..write('fetchStatus: $fetchStatus, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('confirmedByMember: $confirmedByMember')
          ..write(')'))
        .toString();
  }
}

class MagazineIssues extends Table
    with TableInfo<MagazineIssues, MagazineIssuesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MagazineIssues(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> itemId = GeneratedColumn<int>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> periodicalUid = GeneratedColumn<String>(
    'periodical_uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> volume = GeneratedColumn<int>(
    'volume',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> issueNumber = GeneratedColumn<int>(
    'issue_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> issueDate = GeneratedColumn<int>(
    'issue_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> boundUntil = GeneratedColumn<int>(
    'bound_until',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> issueLabel = GeneratedColumn<String>(
    'issue_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    itemId,
    periodicalUid,
    volume,
    issueNumber,
    issueDate,
    boundUntil,
    issueLabel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'magazine_issues';
  @override
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  MagazineIssuesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MagazineIssuesData(
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_id'],
      )!,
      periodicalUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}periodical_uid'],
      )!,
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}volume'],
      ),
      issueNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}issue_number'],
      ),
      issueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}issue_date'],
      ),
      boundUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bound_until'],
      ),
      issueLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issue_label'],
      ),
    );
  }

  @override
  MagazineIssues createAlias(String alias) {
    return MagazineIssues(attachedDatabase, alias);
  }
}

class MagazineIssuesData extends DataClass
    implements Insertable<MagazineIssuesData> {
  final int itemId;
  final String periodicalUid;
  final int? volume;
  final int? issueNumber;
  final int? issueDate;
  final int? boundUntil;
  final String? issueLabel;
  const MagazineIssuesData({
    required this.itemId,
    required this.periodicalUid,
    this.volume,
    this.issueNumber,
    this.issueDate,
    this.boundUntil,
    this.issueLabel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<int>(itemId);
    map['periodical_uid'] = Variable<String>(periodicalUid);
    if (!nullToAbsent || volume != null) {
      map['volume'] = Variable<int>(volume);
    }
    if (!nullToAbsent || issueNumber != null) {
      map['issue_number'] = Variable<int>(issueNumber);
    }
    if (!nullToAbsent || issueDate != null) {
      map['issue_date'] = Variable<int>(issueDate);
    }
    if (!nullToAbsent || boundUntil != null) {
      map['bound_until'] = Variable<int>(boundUntil);
    }
    if (!nullToAbsent || issueLabel != null) {
      map['issue_label'] = Variable<String>(issueLabel);
    }
    return map;
  }

  MagazineIssuesCompanion toCompanion(bool nullToAbsent) {
    return MagazineIssuesCompanion(
      itemId: Value(itemId),
      periodicalUid: Value(periodicalUid),
      volume: volume == null && nullToAbsent
          ? const Value.absent()
          : Value(volume),
      issueNumber: issueNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(issueNumber),
      issueDate: issueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(issueDate),
      boundUntil: boundUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(boundUntil),
      issueLabel: issueLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(issueLabel),
    );
  }

  factory MagazineIssuesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MagazineIssuesData(
      itemId: serializer.fromJson<int>(json['itemId']),
      periodicalUid: serializer.fromJson<String>(json['periodicalUid']),
      volume: serializer.fromJson<int?>(json['volume']),
      issueNumber: serializer.fromJson<int?>(json['issueNumber']),
      issueDate: serializer.fromJson<int?>(json['issueDate']),
      boundUntil: serializer.fromJson<int?>(json['boundUntil']),
      issueLabel: serializer.fromJson<String?>(json['issueLabel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<int>(itemId),
      'periodicalUid': serializer.toJson<String>(periodicalUid),
      'volume': serializer.toJson<int?>(volume),
      'issueNumber': serializer.toJson<int?>(issueNumber),
      'issueDate': serializer.toJson<int?>(issueDate),
      'boundUntil': serializer.toJson<int?>(boundUntil),
      'issueLabel': serializer.toJson<String?>(issueLabel),
    };
  }

  MagazineIssuesData copyWith({
    int? itemId,
    String? periodicalUid,
    Value<int?> volume = const Value.absent(),
    Value<int?> issueNumber = const Value.absent(),
    Value<int?> issueDate = const Value.absent(),
    Value<int?> boundUntil = const Value.absent(),
    Value<String?> issueLabel = const Value.absent(),
  }) => MagazineIssuesData(
    itemId: itemId ?? this.itemId,
    periodicalUid: periodicalUid ?? this.periodicalUid,
    volume: volume.present ? volume.value : this.volume,
    issueNumber: issueNumber.present ? issueNumber.value : this.issueNumber,
    issueDate: issueDate.present ? issueDate.value : this.issueDate,
    boundUntil: boundUntil.present ? boundUntil.value : this.boundUntil,
    issueLabel: issueLabel.present ? issueLabel.value : this.issueLabel,
  );
  MagazineIssuesData copyWithCompanion(MagazineIssuesCompanion data) {
    return MagazineIssuesData(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      periodicalUid: data.periodicalUid.present
          ? data.periodicalUid.value
          : this.periodicalUid,
      volume: data.volume.present ? data.volume.value : this.volume,
      issueNumber: data.issueNumber.present
          ? data.issueNumber.value
          : this.issueNumber,
      issueDate: data.issueDate.present ? data.issueDate.value : this.issueDate,
      boundUntil: data.boundUntil.present
          ? data.boundUntil.value
          : this.boundUntil,
      issueLabel: data.issueLabel.present
          ? data.issueLabel.value
          : this.issueLabel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MagazineIssuesData(')
          ..write('itemId: $itemId, ')
          ..write('periodicalUid: $periodicalUid, ')
          ..write('volume: $volume, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('issueDate: $issueDate, ')
          ..write('boundUntil: $boundUntil, ')
          ..write('issueLabel: $issueLabel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    periodicalUid,
    volume,
    issueNumber,
    issueDate,
    boundUntil,
    issueLabel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MagazineIssuesData &&
          other.itemId == this.itemId &&
          other.periodicalUid == this.periodicalUid &&
          other.volume == this.volume &&
          other.issueNumber == this.issueNumber &&
          other.issueDate == this.issueDate &&
          other.boundUntil == this.boundUntil &&
          other.issueLabel == this.issueLabel);
}

class MagazineIssuesCompanion extends UpdateCompanion<MagazineIssuesData> {
  final Value<int> itemId;
  final Value<String> periodicalUid;
  final Value<int?> volume;
  final Value<int?> issueNumber;
  final Value<int?> issueDate;
  final Value<int?> boundUntil;
  final Value<String?> issueLabel;
  const MagazineIssuesCompanion({
    this.itemId = const Value.absent(),
    this.periodicalUid = const Value.absent(),
    this.volume = const Value.absent(),
    this.issueNumber = const Value.absent(),
    this.issueDate = const Value.absent(),
    this.boundUntil = const Value.absent(),
    this.issueLabel = const Value.absent(),
  });
  MagazineIssuesCompanion.insert({
    this.itemId = const Value.absent(),
    required String periodicalUid,
    this.volume = const Value.absent(),
    this.issueNumber = const Value.absent(),
    this.issueDate = const Value.absent(),
    this.boundUntil = const Value.absent(),
    this.issueLabel = const Value.absent(),
  }) : periodicalUid = Value(periodicalUid);
  static Insertable<MagazineIssuesData> custom({
    Expression<int>? itemId,
    Expression<String>? periodicalUid,
    Expression<int>? volume,
    Expression<int>? issueNumber,
    Expression<int>? issueDate,
    Expression<int>? boundUntil,
    Expression<String>? issueLabel,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (periodicalUid != null) 'periodical_uid': periodicalUid,
      if (volume != null) 'volume': volume,
      if (issueNumber != null) 'issue_number': issueNumber,
      if (issueDate != null) 'issue_date': issueDate,
      if (boundUntil != null) 'bound_until': boundUntil,
      if (issueLabel != null) 'issue_label': issueLabel,
    });
  }

  MagazineIssuesCompanion copyWith({
    Value<int>? itemId,
    Value<String>? periodicalUid,
    Value<int?>? volume,
    Value<int?>? issueNumber,
    Value<int?>? issueDate,
    Value<int?>? boundUntil,
    Value<String?>? issueLabel,
  }) {
    return MagazineIssuesCompanion(
      itemId: itemId ?? this.itemId,
      periodicalUid: periodicalUid ?? this.periodicalUid,
      volume: volume ?? this.volume,
      issueNumber: issueNumber ?? this.issueNumber,
      issueDate: issueDate ?? this.issueDate,
      boundUntil: boundUntil ?? this.boundUntil,
      issueLabel: issueLabel ?? this.issueLabel,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<int>(itemId.value);
    }
    if (periodicalUid.present) {
      map['periodical_uid'] = Variable<String>(periodicalUid.value);
    }
    if (volume.present) {
      map['volume'] = Variable<int>(volume.value);
    }
    if (issueNumber.present) {
      map['issue_number'] = Variable<int>(issueNumber.value);
    }
    if (issueDate.present) {
      map['issue_date'] = Variable<int>(issueDate.value);
    }
    if (boundUntil.present) {
      map['bound_until'] = Variable<int>(boundUntil.value);
    }
    if (issueLabel.present) {
      map['issue_label'] = Variable<String>(issueLabel.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MagazineIssuesCompanion(')
          ..write('itemId: $itemId, ')
          ..write('periodicalUid: $periodicalUid, ')
          ..write('volume: $volume, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('issueDate: $issueDate, ')
          ..write('boundUntil: $boundUntil, ')
          ..write('issueLabel: $issueLabel')
          ..write(')'))
        .toString();
  }
}

class Periodicals extends Table with TableInfo<Periodicals, PeriodicalsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Periodicals(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<String> periodicalUid = GeneratedColumn<String>(
    'periodical_uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> titleTransliteration =
      GeneratedColumn<String>(
        'title_transliteration',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> titleSort = GeneratedColumn<String>(
    'title_sort',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'\''),
  );
  late final GeneratedColumn<String> issn = GeneratedColumn<String>(
    'issn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> frequency = GeneratedColumn<String>(
    'frequency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> subscriptionStart = GeneratedColumn<int>(
    'subscription_start',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> subscriptionEnd = GeneratedColumn<int>(
    'subscription_end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sourceDetail = GeneratedColumn<String>(
    'source_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> ageGroup = GeneratedColumn<String>(
    'age_group',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> addedDate = GeneratedColumn<int>(
    'added_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> removed = GeneratedColumn<bool>(
    'removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("removed" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> removedAt = GeneratedColumn<int>(
    'removed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> addedBy = GeneratedColumn<String>(
    'added_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    periodicalUid,
    title,
    titleTransliteration,
    titleSort,
    issn,
    publisher,
    language,
    coverUrl,
    frequency,
    subscriptionStart,
    subscriptionEnd,
    notes,
    location,
    sourceType,
    sourceDetail,
    ageGroup,
    addedDate,
    removed,
    removedAt,
    addedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'periodicals';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PeriodicalsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeriodicalsData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      periodicalUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}periodical_uid'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleTransliteration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_transliteration'],
      ),
      titleSort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_sort'],
      )!,
      issn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issn'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      frequency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}frequency'],
      ),
      subscriptionStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subscription_start'],
      ),
      subscriptionEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subscription_end'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      ),
      sourceDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_detail'],
      ),
      ageGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_group'],
      ),
      addedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_date'],
      )!,
      removed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}removed'],
      )!,
      removedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}removed_at'],
      ),
      addedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_by'],
      ),
    );
  }

  @override
  Periodicals createAlias(String alias) {
    return Periodicals(attachedDatabase, alias);
  }
}

class PeriodicalsData extends DataClass implements Insertable<PeriodicalsData> {
  final int id;
  final String periodicalUid;
  final String title;
  final String? titleTransliteration;
  final String titleSort;
  final String? issn;
  final String? publisher;
  final String? language;
  final String? coverUrl;
  final String? frequency;
  final int? subscriptionStart;
  final int? subscriptionEnd;
  final String? notes;
  final String? location;
  final String? sourceType;
  final String? sourceDetail;
  final String? ageGroup;
  final int addedDate;
  final bool removed;
  final int? removedAt;
  final String? addedBy;
  const PeriodicalsData({
    required this.id,
    required this.periodicalUid,
    required this.title,
    this.titleTransliteration,
    required this.titleSort,
    this.issn,
    this.publisher,
    this.language,
    this.coverUrl,
    this.frequency,
    this.subscriptionStart,
    this.subscriptionEnd,
    this.notes,
    this.location,
    this.sourceType,
    this.sourceDetail,
    this.ageGroup,
    required this.addedDate,
    required this.removed,
    this.removedAt,
    this.addedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['periodical_uid'] = Variable<String>(periodicalUid);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || titleTransliteration != null) {
      map['title_transliteration'] = Variable<String>(titleTransliteration);
    }
    map['title_sort'] = Variable<String>(titleSort);
    if (!nullToAbsent || issn != null) {
      map['issn'] = Variable<String>(issn);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    if (!nullToAbsent || frequency != null) {
      map['frequency'] = Variable<String>(frequency);
    }
    if (!nullToAbsent || subscriptionStart != null) {
      map['subscription_start'] = Variable<int>(subscriptionStart);
    }
    if (!nullToAbsent || subscriptionEnd != null) {
      map['subscription_end'] = Variable<int>(subscriptionEnd);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || sourceType != null) {
      map['source_type'] = Variable<String>(sourceType);
    }
    if (!nullToAbsent || sourceDetail != null) {
      map['source_detail'] = Variable<String>(sourceDetail);
    }
    if (!nullToAbsent || ageGroup != null) {
      map['age_group'] = Variable<String>(ageGroup);
    }
    map['added_date'] = Variable<int>(addedDate);
    map['removed'] = Variable<bool>(removed);
    if (!nullToAbsent || removedAt != null) {
      map['removed_at'] = Variable<int>(removedAt);
    }
    if (!nullToAbsent || addedBy != null) {
      map['added_by'] = Variable<String>(addedBy);
    }
    return map;
  }

  PeriodicalsCompanion toCompanion(bool nullToAbsent) {
    return PeriodicalsCompanion(
      id: Value(id),
      periodicalUid: Value(periodicalUid),
      title: Value(title),
      titleTransliteration: titleTransliteration == null && nullToAbsent
          ? const Value.absent()
          : Value(titleTransliteration),
      titleSort: Value(titleSort),
      issn: issn == null && nullToAbsent ? const Value.absent() : Value(issn),
      publisher: publisher == null && nullToAbsent
          ? const Value.absent()
          : Value(publisher),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      frequency: frequency == null && nullToAbsent
          ? const Value.absent()
          : Value(frequency),
      subscriptionStart: subscriptionStart == null && nullToAbsent
          ? const Value.absent()
          : Value(subscriptionStart),
      subscriptionEnd: subscriptionEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(subscriptionEnd),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      sourceType: sourceType == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceType),
      sourceDetail: sourceDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDetail),
      ageGroup: ageGroup == null && nullToAbsent
          ? const Value.absent()
          : Value(ageGroup),
      addedDate: Value(addedDate),
      removed: Value(removed),
      removedAt: removedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(removedAt),
      addedBy: addedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(addedBy),
    );
  }

  factory PeriodicalsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeriodicalsData(
      id: serializer.fromJson<int>(json['id']),
      periodicalUid: serializer.fromJson<String>(json['periodicalUid']),
      title: serializer.fromJson<String>(json['title']),
      titleTransliteration: serializer.fromJson<String?>(
        json['titleTransliteration'],
      ),
      titleSort: serializer.fromJson<String>(json['titleSort']),
      issn: serializer.fromJson<String?>(json['issn']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      language: serializer.fromJson<String?>(json['language']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      frequency: serializer.fromJson<String?>(json['frequency']),
      subscriptionStart: serializer.fromJson<int?>(json['subscriptionStart']),
      subscriptionEnd: serializer.fromJson<int?>(json['subscriptionEnd']),
      notes: serializer.fromJson<String?>(json['notes']),
      location: serializer.fromJson<String?>(json['location']),
      sourceType: serializer.fromJson<String?>(json['sourceType']),
      sourceDetail: serializer.fromJson<String?>(json['sourceDetail']),
      ageGroup: serializer.fromJson<String?>(json['ageGroup']),
      addedDate: serializer.fromJson<int>(json['addedDate']),
      removed: serializer.fromJson<bool>(json['removed']),
      removedAt: serializer.fromJson<int?>(json['removedAt']),
      addedBy: serializer.fromJson<String?>(json['addedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'periodicalUid': serializer.toJson<String>(periodicalUid),
      'title': serializer.toJson<String>(title),
      'titleTransliteration': serializer.toJson<String?>(titleTransliteration),
      'titleSort': serializer.toJson<String>(titleSort),
      'issn': serializer.toJson<String?>(issn),
      'publisher': serializer.toJson<String?>(publisher),
      'language': serializer.toJson<String?>(language),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'frequency': serializer.toJson<String?>(frequency),
      'subscriptionStart': serializer.toJson<int?>(subscriptionStart),
      'subscriptionEnd': serializer.toJson<int?>(subscriptionEnd),
      'notes': serializer.toJson<String?>(notes),
      'location': serializer.toJson<String?>(location),
      'sourceType': serializer.toJson<String?>(sourceType),
      'sourceDetail': serializer.toJson<String?>(sourceDetail),
      'ageGroup': serializer.toJson<String?>(ageGroup),
      'addedDate': serializer.toJson<int>(addedDate),
      'removed': serializer.toJson<bool>(removed),
      'removedAt': serializer.toJson<int?>(removedAt),
      'addedBy': serializer.toJson<String?>(addedBy),
    };
  }

  PeriodicalsData copyWith({
    int? id,
    String? periodicalUid,
    String? title,
    Value<String?> titleTransliteration = const Value.absent(),
    String? titleSort,
    Value<String?> issn = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<String?> language = const Value.absent(),
    Value<String?> coverUrl = const Value.absent(),
    Value<String?> frequency = const Value.absent(),
    Value<int?> subscriptionStart = const Value.absent(),
    Value<int?> subscriptionEnd = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> sourceType = const Value.absent(),
    Value<String?> sourceDetail = const Value.absent(),
    Value<String?> ageGroup = const Value.absent(),
    int? addedDate,
    bool? removed,
    Value<int?> removedAt = const Value.absent(),
    Value<String?> addedBy = const Value.absent(),
  }) => PeriodicalsData(
    id: id ?? this.id,
    periodicalUid: periodicalUid ?? this.periodicalUid,
    title: title ?? this.title,
    titleTransliteration: titleTransliteration.present
        ? titleTransliteration.value
        : this.titleTransliteration,
    titleSort: titleSort ?? this.titleSort,
    issn: issn.present ? issn.value : this.issn,
    publisher: publisher.present ? publisher.value : this.publisher,
    language: language.present ? language.value : this.language,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    frequency: frequency.present ? frequency.value : this.frequency,
    subscriptionStart: subscriptionStart.present
        ? subscriptionStart.value
        : this.subscriptionStart,
    subscriptionEnd: subscriptionEnd.present
        ? subscriptionEnd.value
        : this.subscriptionEnd,
    notes: notes.present ? notes.value : this.notes,
    location: location.present ? location.value : this.location,
    sourceType: sourceType.present ? sourceType.value : this.sourceType,
    sourceDetail: sourceDetail.present ? sourceDetail.value : this.sourceDetail,
    ageGroup: ageGroup.present ? ageGroup.value : this.ageGroup,
    addedDate: addedDate ?? this.addedDate,
    removed: removed ?? this.removed,
    removedAt: removedAt.present ? removedAt.value : this.removedAt,
    addedBy: addedBy.present ? addedBy.value : this.addedBy,
  );
  PeriodicalsData copyWithCompanion(PeriodicalsCompanion data) {
    return PeriodicalsData(
      id: data.id.present ? data.id.value : this.id,
      periodicalUid: data.periodicalUid.present
          ? data.periodicalUid.value
          : this.periodicalUid,
      title: data.title.present ? data.title.value : this.title,
      titleTransliteration: data.titleTransliteration.present
          ? data.titleTransliteration.value
          : this.titleTransliteration,
      titleSort: data.titleSort.present ? data.titleSort.value : this.titleSort,
      issn: data.issn.present ? data.issn.value : this.issn,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      language: data.language.present ? data.language.value : this.language,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      frequency: data.frequency.present ? data.frequency.value : this.frequency,
      subscriptionStart: data.subscriptionStart.present
          ? data.subscriptionStart.value
          : this.subscriptionStart,
      subscriptionEnd: data.subscriptionEnd.present
          ? data.subscriptionEnd.value
          : this.subscriptionEnd,
      notes: data.notes.present ? data.notes.value : this.notes,
      location: data.location.present ? data.location.value : this.location,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      sourceDetail: data.sourceDetail.present
          ? data.sourceDetail.value
          : this.sourceDetail,
      ageGroup: data.ageGroup.present ? data.ageGroup.value : this.ageGroup,
      addedDate: data.addedDate.present ? data.addedDate.value : this.addedDate,
      removed: data.removed.present ? data.removed.value : this.removed,
      removedAt: data.removedAt.present ? data.removedAt.value : this.removedAt,
      addedBy: data.addedBy.present ? data.addedBy.value : this.addedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeriodicalsData(')
          ..write('id: $id, ')
          ..write('periodicalUid: $periodicalUid, ')
          ..write('title: $title, ')
          ..write('titleTransliteration: $titleTransliteration, ')
          ..write('titleSort: $titleSort, ')
          ..write('issn: $issn, ')
          ..write('publisher: $publisher, ')
          ..write('language: $language, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('frequency: $frequency, ')
          ..write('subscriptionStart: $subscriptionStart, ')
          ..write('subscriptionEnd: $subscriptionEnd, ')
          ..write('notes: $notes, ')
          ..write('location: $location, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceDetail: $sourceDetail, ')
          ..write('ageGroup: $ageGroup, ')
          ..write('addedDate: $addedDate, ')
          ..write('removed: $removed, ')
          ..write('removedAt: $removedAt, ')
          ..write('addedBy: $addedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    periodicalUid,
    title,
    titleTransliteration,
    titleSort,
    issn,
    publisher,
    language,
    coverUrl,
    frequency,
    subscriptionStart,
    subscriptionEnd,
    notes,
    location,
    sourceType,
    sourceDetail,
    ageGroup,
    addedDate,
    removed,
    removedAt,
    addedBy,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeriodicalsData &&
          other.id == this.id &&
          other.periodicalUid == this.periodicalUid &&
          other.title == this.title &&
          other.titleTransliteration == this.titleTransliteration &&
          other.titleSort == this.titleSort &&
          other.issn == this.issn &&
          other.publisher == this.publisher &&
          other.language == this.language &&
          other.coverUrl == this.coverUrl &&
          other.frequency == this.frequency &&
          other.subscriptionStart == this.subscriptionStart &&
          other.subscriptionEnd == this.subscriptionEnd &&
          other.notes == this.notes &&
          other.location == this.location &&
          other.sourceType == this.sourceType &&
          other.sourceDetail == this.sourceDetail &&
          other.ageGroup == this.ageGroup &&
          other.addedDate == this.addedDate &&
          other.removed == this.removed &&
          other.removedAt == this.removedAt &&
          other.addedBy == this.addedBy);
}

class PeriodicalsCompanion extends UpdateCompanion<PeriodicalsData> {
  final Value<int> id;
  final Value<String> periodicalUid;
  final Value<String> title;
  final Value<String?> titleTransliteration;
  final Value<String> titleSort;
  final Value<String?> issn;
  final Value<String?> publisher;
  final Value<String?> language;
  final Value<String?> coverUrl;
  final Value<String?> frequency;
  final Value<int?> subscriptionStart;
  final Value<int?> subscriptionEnd;
  final Value<String?> notes;
  final Value<String?> location;
  final Value<String?> sourceType;
  final Value<String?> sourceDetail;
  final Value<String?> ageGroup;
  final Value<int> addedDate;
  final Value<bool> removed;
  final Value<int?> removedAt;
  final Value<String?> addedBy;
  const PeriodicalsCompanion({
    this.id = const Value.absent(),
    this.periodicalUid = const Value.absent(),
    this.title = const Value.absent(),
    this.titleTransliteration = const Value.absent(),
    this.titleSort = const Value.absent(),
    this.issn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.language = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.frequency = const Value.absent(),
    this.subscriptionStart = const Value.absent(),
    this.subscriptionEnd = const Value.absent(),
    this.notes = const Value.absent(),
    this.location = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceDetail = const Value.absent(),
    this.ageGroup = const Value.absent(),
    this.addedDate = const Value.absent(),
    this.removed = const Value.absent(),
    this.removedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
  });
  PeriodicalsCompanion.insert({
    this.id = const Value.absent(),
    required String periodicalUid,
    required String title,
    this.titleTransliteration = const Value.absent(),
    this.titleSort = const Value.absent(),
    this.issn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.language = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.frequency = const Value.absent(),
    this.subscriptionStart = const Value.absent(),
    this.subscriptionEnd = const Value.absent(),
    this.notes = const Value.absent(),
    this.location = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceDetail = const Value.absent(),
    this.ageGroup = const Value.absent(),
    required int addedDate,
    this.removed = const Value.absent(),
    this.removedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
  }) : periodicalUid = Value(periodicalUid),
       title = Value(title),
       addedDate = Value(addedDate);
  static Insertable<PeriodicalsData> custom({
    Expression<int>? id,
    Expression<String>? periodicalUid,
    Expression<String>? title,
    Expression<String>? titleTransliteration,
    Expression<String>? titleSort,
    Expression<String>? issn,
    Expression<String>? publisher,
    Expression<String>? language,
    Expression<String>? coverUrl,
    Expression<String>? frequency,
    Expression<int>? subscriptionStart,
    Expression<int>? subscriptionEnd,
    Expression<String>? notes,
    Expression<String>? location,
    Expression<String>? sourceType,
    Expression<String>? sourceDetail,
    Expression<String>? ageGroup,
    Expression<int>? addedDate,
    Expression<bool>? removed,
    Expression<int>? removedAt,
    Expression<String>? addedBy,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (periodicalUid != null) 'periodical_uid': periodicalUid,
      if (title != null) 'title': title,
      if (titleTransliteration != null)
        'title_transliteration': titleTransliteration,
      if (titleSort != null) 'title_sort': titleSort,
      if (issn != null) 'issn': issn,
      if (publisher != null) 'publisher': publisher,
      if (language != null) 'language': language,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (frequency != null) 'frequency': frequency,
      if (subscriptionStart != null) 'subscription_start': subscriptionStart,
      if (subscriptionEnd != null) 'subscription_end': subscriptionEnd,
      if (notes != null) 'notes': notes,
      if (location != null) 'location': location,
      if (sourceType != null) 'source_type': sourceType,
      if (sourceDetail != null) 'source_detail': sourceDetail,
      if (ageGroup != null) 'age_group': ageGroup,
      if (addedDate != null) 'added_date': addedDate,
      if (removed != null) 'removed': removed,
      if (removedAt != null) 'removed_at': removedAt,
      if (addedBy != null) 'added_by': addedBy,
    });
  }

  PeriodicalsCompanion copyWith({
    Value<int>? id,
    Value<String>? periodicalUid,
    Value<String>? title,
    Value<String?>? titleTransliteration,
    Value<String>? titleSort,
    Value<String?>? issn,
    Value<String?>? publisher,
    Value<String?>? language,
    Value<String?>? coverUrl,
    Value<String?>? frequency,
    Value<int?>? subscriptionStart,
    Value<int?>? subscriptionEnd,
    Value<String?>? notes,
    Value<String?>? location,
    Value<String?>? sourceType,
    Value<String?>? sourceDetail,
    Value<String?>? ageGroup,
    Value<int>? addedDate,
    Value<bool>? removed,
    Value<int?>? removedAt,
    Value<String?>? addedBy,
  }) {
    return PeriodicalsCompanion(
      id: id ?? this.id,
      periodicalUid: periodicalUid ?? this.periodicalUid,
      title: title ?? this.title,
      titleTransliteration: titleTransliteration ?? this.titleTransliteration,
      titleSort: titleSort ?? this.titleSort,
      issn: issn ?? this.issn,
      publisher: publisher ?? this.publisher,
      language: language ?? this.language,
      coverUrl: coverUrl ?? this.coverUrl,
      frequency: frequency ?? this.frequency,
      subscriptionStart: subscriptionStart ?? this.subscriptionStart,
      subscriptionEnd: subscriptionEnd ?? this.subscriptionEnd,
      notes: notes ?? this.notes,
      location: location ?? this.location,
      sourceType: sourceType ?? this.sourceType,
      sourceDetail: sourceDetail ?? this.sourceDetail,
      ageGroup: ageGroup ?? this.ageGroup,
      addedDate: addedDate ?? this.addedDate,
      removed: removed ?? this.removed,
      removedAt: removedAt ?? this.removedAt,
      addedBy: addedBy ?? this.addedBy,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (periodicalUid.present) {
      map['periodical_uid'] = Variable<String>(periodicalUid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleTransliteration.present) {
      map['title_transliteration'] = Variable<String>(
        titleTransliteration.value,
      );
    }
    if (titleSort.present) {
      map['title_sort'] = Variable<String>(titleSort.value);
    }
    if (issn.present) {
      map['issn'] = Variable<String>(issn.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (frequency.present) {
      map['frequency'] = Variable<String>(frequency.value);
    }
    if (subscriptionStart.present) {
      map['subscription_start'] = Variable<int>(subscriptionStart.value);
    }
    if (subscriptionEnd.present) {
      map['subscription_end'] = Variable<int>(subscriptionEnd.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (sourceDetail.present) {
      map['source_detail'] = Variable<String>(sourceDetail.value);
    }
    if (ageGroup.present) {
      map['age_group'] = Variable<String>(ageGroup.value);
    }
    if (addedDate.present) {
      map['added_date'] = Variable<int>(addedDate.value);
    }
    if (removed.present) {
      map['removed'] = Variable<bool>(removed.value);
    }
    if (removedAt.present) {
      map['removed_at'] = Variable<int>(removedAt.value);
    }
    if (addedBy.present) {
      map['added_by'] = Variable<String>(addedBy.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeriodicalsCompanion(')
          ..write('id: $id, ')
          ..write('periodicalUid: $periodicalUid, ')
          ..write('title: $title, ')
          ..write('titleTransliteration: $titleTransliteration, ')
          ..write('titleSort: $titleSort, ')
          ..write('issn: $issn, ')
          ..write('publisher: $publisher, ')
          ..write('language: $language, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('frequency: $frequency, ')
          ..write('subscriptionStart: $subscriptionStart, ')
          ..write('subscriptionEnd: $subscriptionEnd, ')
          ..write('notes: $notes, ')
          ..write('location: $location, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceDetail: $sourceDetail, ')
          ..write('ageGroup: $ageGroup, ')
          ..write('addedDate: $addedDate, ')
          ..write('removed: $removed, ')
          ..write('removedAt: $removedAt, ')
          ..write('addedBy: $addedBy')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV7 extends GeneratedDatabase {
  DatabaseAtV7(QueryExecutor e) : super(e);
  late final Books books = Books(this);
  late final WishlistBooks wishlistBooks = WishlistBooks(this);
  late final NetworkLibraries networkLibraries = NetworkLibraries(this);
  late final MagazineIssues magazineIssues = MagazineIssues(this);
  late final Periodicals periodicals = Periodicals(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    wishlistBooks,
    networkLibraries,
    magazineIssues,
    periodicals,
  ];
  @override
  int get schemaVersion => 7;
}
