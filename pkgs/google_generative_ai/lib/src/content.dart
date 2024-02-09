// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:typed_data';

/// The base structured datatype containing multi-part content of a message.
final class Content {
  /// The producer of the content.
  ///
  /// Must be either 'user' or 'model'. Useful to set for multi-turn
  /// conversations, otherwise can be left blank or unset.
  final String? role;

  /// Ordered `Parts` that constitute a single message.
  ///
  /// Parts may have different MIME types.
  final List<Part> parts;

  /// Cached JSON representation.
  final Map<String, Object?> _json;

  Content(this.role, this.parts)
      : _json = {
          if (role case final role?) 'role': role,
          'parts': [for (var part in parts) part._json],
        };

  static Content text(String text) =>
      Content('user', List.unmodifiable([TextPart(text)]));
  static Content data(String mimeType, Uint8List bytes) =>
      Content('user', List.unmodifiable([DataPart(mimeType, bytes)]));
  static Content multi(Iterable<Part> parts) =>
      Content('user', List.unmodifiable(parts));
  static Content model(Iterable<Part> parts) =>
      Content('model', List.unmodifiable(parts));

  Map toJson() => _json;
}

Content parseContent(Object jsonObject, Cache cache) {
  return switch (jsonObject) {
    {'parts': final List<Object?> parts} => Content(
        switch (jsonObject) {
          {'role': String role} => role,
          _ => null,
        },
        [for (var part in parts) _parsePart(part, cache)],
      ),
    _ => throw FormatException('Unhandled Content format', jsonObject),
  };
}

Part _parsePart(Object? jsonObject, Cache cache) {
  return switch (jsonObject) {
    {'text': String text} => cache.textPart(text, jsonObject),
    {'inlineData': {'mimeType': String _, 'data': String _}} =>
      throw UnimplementedError('inlineData content part not yet supported'),
    _ => throw FormatException('Unhandled Part format', jsonObject),
  };
}

/// A datatype containing media that is part of a multi-part [Content] message.
sealed class Part {
  final Object _json;
  Part._(this._json);
  Object toJson() => _json;
}

final class TextPart extends Part {
  final String text;
  TextPart(this.text) : super._({'text': text});
  // Reuse existing JSON object.
  TextPart._(this.text, super.json) : super._();
}

final class DataPart extends Part {
  final String mimeType;
  final Uint8List bytes;
  DataPart(this.mimeType, this.bytes)
      : super._({
          'inlineData': {'data': base64Encode(bytes), 'mimeType': mimeType}
        });
}

/// Cache used to avoid repeatedly creating the same content and JSON objects
///
/// Requests contain the entire history, which means generating the same
/// JSON objects repeatedly. This cache tries to recognize repeated
/// values.
// Add more caches as needed.
class Cache {
  final Map<String, TextPart> _textCache = {};

  TextPart textPart(String text, Object json) =>
      _textCache[text] ??= TextPart._(text, json);
}
