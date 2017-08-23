library source_map;

import 'package:source_maps/source_maps.dart';

import 'dart:async';
import 'dart:convert' show LineSplitter, UTF8;
import 'dart:io';

void main(List<String> args) {
  Map<String, List<String>> files = {};
  Map<String, SingleMapping> maps = {};

  List<Future> futures = [];
  //for (var file in ['main.dart', 'main.dart.js', 'main.dart.js.map']) {
  for (var file in ['main.dart', 'web__main.js', 'web__main.js.map']) {
    futures.add(getFile(file).then((lines) => files[file] = lines));
  }
  Future.wait(futures).then((_) {
    for (var file in files.keys) {
      if (file.endsWith('.map')) {
        SingleMapping map = parse(files[file].join());
        maps[file.substring(0, file.length - 4)] = map;
      }
    }
    for (var file in maps.keys) {
      SingleMapping map = maps[file];
      List<String> source = files[file];
      Set<String> unknownUrls = new Set();

      for (var line in map.lines) {
        if (line.entries.isEmpty) continue;
        bool output = false;
        for (var entry in line.entries) {
          if (entry.sourceUrlId == null || entry.sourceUrlId < 0) continue;
          String destinationFile = map.urls[entry.sourceUrlId];
          if (files[destinationFile] != null) {
            if (!output) {
              print('${line.line}:${source[line.line]}');
              output = true;
            }
            List<String> destination = files[destinationFile];
            print('->@${entry.column}[$destinationFile:${entry.sourceLine},${entry.sourceColumn}]'
                '${destination[entry.sourceLine]}');
            if (entry.sourceNameId != null && entry.sourceNameId >= 0) {
              print('  ${map.names[entry.sourceNameId]}');
            }
          } else {
            unknownUrls.add(destinationFile);
          }
        }
      }
      print('UNKNOWN URLS: $unknownUrls');
    }
  }).catchError((e) {
    print(e);
  });
}

Future<List<String>> getFile(String filename) {
  HttpClient client = new HttpClient();
  return client.get('localhost', 8081, filename).then((request) {
    request.headers.contentType
        = new ContentType("text", "plain", charset: "utf-8");
    return request.close();
  }).then((response) {
    return UTF8.decodeStream(response);
  }).then((t) {
    var ret = LineSplitter.split(t).toList();
    print('loaded: $filename (${ret.length})');
    return ret;
  });

}
