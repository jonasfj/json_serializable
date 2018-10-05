import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder docThingy([_]) => _DocThingy();

final _ref = RegExp(r'\[(\w+)\]');

class _FieldThing {
  final FieldElement field;

  ClassElement get owner => field.enclosingElement;

  String get description {
    var description = LineSplitter.split(field.documentationComment)
        .map((line) {
          if (line.startsWith('///')) {
            line = line.substring(3).trim();
          }
          return line;
        })
        .takeWhile((line) => line.isNotEmpty)
        .join(' ');

    return description.replaceAllMapped(_ref, (m) {
      return '`${m[1]}`';
    });
  }

  String get defaultValue => owner.constructors.single.parameters
      .singleWhere((pe) => pe.name == field.name)
      .defaultValueCode;

  _FieldThing(this.field);
}

class _DocThingy extends Builder {
  @override
  FutureOr<void> build(BuildStep buildStep) async {
    var lib = LibraryReader(await buildStep.inputLibrary);

    //LibraryReader(await buildStep.resolver
    //    .libraryFor(AssetId('json_annotation', 'lib/json_annotation.dart')));

    var descriptions = <String, String>{};
    var fieldMap = <String, List<String>>{};

    void processField(FieldElement fe) {
      var description = LineSplitter.split(fe.documentationComment)
          .map((line) {
            if (line.startsWith('///')) {
              line = line.substring(3).trim();
            }
            return line;
          })
          .takeWhile((line) => line.isNotEmpty)
          .join(' ');

      description = description.replaceAllMapped(_ref, (m) {
        return '`${m[1]}`';
      });

      descriptions[fe.name] = description;

      var owner = fe.enclosingElement;

      var params = owner.constructors
          .singleWhere((c) => c.name.isEmpty)
          .parameters
          .toList();

      print([owner.name, params, fe.name]);

      var param = params.singleWhere((pe) => pe.name == fe.name);
      log.warning([
        owner,
        param,
        param.defaultValueCode,
        param.defaultValueCode == null
      ]);
    }

    void processClass(ClassElement ce) {
      for (var fe in ce.fields.where((fe) => !fe.isStatic)) {
        var list = fieldMap.putIfAbsent(ce.name, () => <String>[]);
        list.add(fe.name);
        list.sort();
        processField(fe);
      }
    }

    for (var ce in [
      lib.findType('JsonSerializable'),
      lib.findType('JsonKey')
    ]) {
      processClass(ce);
    }

    var buffer = StringBuffer('# fields\n\n');

    void writeRow(List<String> row) {
      buffer.writeln('| ${row.join(' | ')} |');
    }

    writeRow(['Field']
      ..addAll(fieldMap.keys)
      ..add('Description'));

    writeRow(['---']
      ..addAll(fieldMap.keys.map((k) => ':---:'))
      ..add('---'));

    for (var description in descriptions.entries) {
      writeRow(['`${description.key}`']
        ..addAll(fieldMap.keys.map((clazz) {
          return fieldMap[clazz].contains(description.key) ? '\u2713' : '';
        }))
        ..add(description.value));
    }

    await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'doc/doc.md'), buffer.toString());
  }

  @override
  final buildExtensions = const {
    r'lib/json_annotation.dart': ['doc/doc.md']
  };
}
