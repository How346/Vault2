import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../models/doc_category.dart';
import '../models/doc_item.dart';
import '../models/profile.dart';
import '../utils/constants.dart';
import 'storage_service.dart';

const int kTransferPort = 47653;

class TransferException implements Exception {
  TransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Offline device-to-device migration over the local network / hotspot.
class TransferService {
  TransferService._();

  static final TransferService instance = TransferService._();

  HttpServer? _server;

  bool get isHosting => _server != null;

  // ---------------------------------------------------------------- server

  Future<String> startServer({
    required String code,
    void Function(double progress)? onProgress,
    VoidCallback? onCompleted,
  }) async {
    await stopServer();

    final payload = await buildPayload();

    Future<shelf.Response> handler(
      shelf.Request request,
    ) async {
      final path = '/${request.url.path}';
      final given = request.url.queryParameters['code'] ?? '';

      if (path == '/handshake' || path == '/payload') {
        if (given != code) {
          return shelf.Response(
            401,
            body: 'invalid code',
          );
        }
      }

      switch (path) {
        case '/handshake':
          return shelf.Response.ok(
            jsonEncode({
              'app': 'wallet',
              'size': payload.length,
            }),
            headers: {
              'content-type': 'application/json',
            },
          );

        case '/payload':
          var sent = 0;
          const chunkSize = 64 * 1024;

          final chunks = List.generate(
            (payload.length / chunkSize).ceil(),
            (index) {
              final start = index * chunkSize;
              final end = ((index + 1) * chunkSize).clamp(
                0,
                payload.length,
              );

              return payload.sublist(start, end);
            },
          );

          final stream = Stream<List<int>>.fromIterable(
            chunks,
          ).map((chunk) {
            sent += chunk.length;

            if (payload.isNotEmpty) {
              onProgress?.call(
                sent / payload.length,
              );
            }

            if (sent >= payload.length) {
              onCompleted?.call();
            }

            return chunk;
          });

          return shelf.Response.ok(
            stream,
            headers: {
              'content-type': 'application/octet-stream',
              'content-length': '${payload.length}',
            },
          );

        default:
          return shelf.Response.notFound('no');
      }
    }

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        kTransferPort,
      );

      _server!.autoCompress = false;
    } on SocketException catch (e) {
      throw TransferException(
        'Could not start the transfer server '
        '(${e.osError?.message ?? 'port busy'}).',
      );
    }

    final ip = await localIp();

    if (ip == null) {
      await stopServer();

      throw TransferException(
        'No Wi-Fi or hotspot connection found. '
        'Connect both phones to the same network.',
      );
    }

    return ip;
  }

  Future<void> stopServer() async {
    final server = _server;

    _server = null;

    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------- network

  static Future<String?> localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback &&
              address.address.startsWith(
                RegExp(r'10\.|192\.168\.|172\.'),
              )) {
            return address.address;
          }
        }
      }

      for (final interface in interfaces) {
        if (interface.addresses.isNotEmpty) {
          return interface.addresses.first.address;
        }
      }
    } catch (_) {}

    return null;
  }

  // ------------------------------------------------------------- discovery

  /// Sweeps the local /24 subnet looking for a sender that accepts [code].
  Future<String> discover(
    String code, {
    void Function(double progress)? onProgress,
  }) async {
    final ip = await localIp();

    if (ip == null) {
      throw TransferException(
        'No Wi-Fi or hotspot connection found.',
      );
    }

    final prefix = ip.substring(
      0,
      ip.lastIndexOf('.') + 1,
    );

    final hosts = <String>[
      for (var i = 1; i < 255; i++) '$prefix$i',
    ]..remove(ip);

    var scanned = 0;
    const batchSize = 32;

    for (
      var start = 0;
      start < hosts.length;
      start += batchSize
    ) {
      final batch = hosts
          .skip(start)
          .take(batchSize)
          .toList();

      final results = await Future.wait(
        batch.map(
          (host) => _probe(host, code),
        ),
      );

      scanned += batch.length;

      if (hosts.isNotEmpty) {
        onProgress?.call(
          scanned / hosts.length,
        );
      }

      for (var i = 0; i < results.length; i++) {
        if (results[i] == _ProbeResult.ok) {
          return batch[i];
        }

        if (results[i] == _ProbeResult.wrongCode) {
          throw TransferException(
            'Invalid code. Check the 6 digits on the old phone.',
          );
        }
      }
    }

    throw TransferException(
      'Sender not found. Keep both phones on the same Wi-Fi / '
      'hotspot and try again.',
    );
  }

  Future<_ProbeResult> _probe(
    String host,
    String code,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(
        milliseconds: 700,
      );

    try {
      final request = await client
          .getUrl(
            Uri.parse(
              'http://$host:$kTransferPort/handshake?code=$code',
            ),
          )
          .timeout(
            const Duration(milliseconds: 900),
          );

      final response = await request.close().timeout(
            const Duration(milliseconds: 900),
          );

      await response.drain<void>();

      if (response.statusCode == 200) {
        return _ProbeResult.ok;
      }

      if (response.statusCode == 401) {
        return _ProbeResult.wrongCode;
      }

      return _ProbeResult.miss;
    } catch (_) {
      return _ProbeResult.miss;
    } finally {
      client.close(force: true);
    }
  }

  // --------------------------------------------------------------- download

  /// Downloads the payload from [host] with live progress.
  Future<Uint8List> download(
    String host,
    String code, {
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.getUrl(
        Uri.parse(
          'http://$host:$kTransferPort/payload?code=$code',
        ),
      );

      final response = await request.close();

      if (response.statusCode == 401) {
        throw TransferException('Invalid code.');
      }

      if (response.statusCode != 200) {
        throw TransferException(
          'Transfer interrupted (${response.statusCode}).',
        );
      }

      final total = response.contentLength;
      final bytes = <int>[];

      await for (final chunk in response) {
        bytes.addAll(chunk);

        if (total > 0) {
          onProgress?.call(
            bytes.length / total,
          );
        }
      }

      if (total > 0 && bytes.length < total) {
        throw TransferException(
          'Transfer interrupted.',
        );
      }

      return Uint8List.fromList(bytes);
    } on TransferException {
      rethrow;
    } catch (_) {
      throw TransferException(
        'Transfer interrupted. Try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  // --------------------------------------------------------------- payload

  /// Zips every record, setting and vault file into a single archive.
  Future<Uint8List> buildPayload() async {
    final storage = StorageService.instance;
    final archive = Archive();

    final manifest = <String, dynamic>{
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'profiles': storage.profiles.values
          .map(_profileJson)
          .toList(),
      'categories': storage.categories.values
          .map(_categoryJson)
          .toList(),
      'documents': storage.documents.values
          .map(_docJson)
          .toList(),
      'settings': <String, dynamic>{
        for (final key in _portableSettingKeys)
          if (storage.settings.get(key) != null)
            key: storage.settings.get(key),
      },
    };

    for (final doc in storage.documents.values) {
      for (final filePath in doc.filePaths) {
        final file = File(filePath);

        if (!file.existsSync()) {
          continue;
        }

        final fileBytes = file.readAsBytesSync();

        archive.addFile(
          ArchiveFile(
            'vault/${doc.id}/${p.basename(filePath)}',
            fileBytes.length,
            fileBytes,
          ),
        );
      }
    }

    final manifestBytes = utf8.encode(
      jsonEncode(manifest),
    );

    archive.addFile(
      ArchiveFile(
        'manifest.json',
        manifestBytes.length,
        manifestBytes,
      ),
    );

    final List<int>? zipped = ZipEncoder().encode(archive);

    // archive package versions may return a nullable List<int>.
    return Uint8List.fromList(
      zipped ?? const <int>[],
    );
  }

  // --------------------------------------------------------------- restore

  /// Replaces all local data with the received payload.
  Future<void> restorePayload(
    Uint8List bytes,
  ) async {
    final Archive archive;

    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw TransferException(
        'The received data is corrupted.',
      );
    }

    final manifestFile = archive.files.firstWhere(
      (file) => file.name == 'manifest.json',
      orElse: () => throw TransferException(
        'The received data is incomplete.',
      ),
    );

    final manifestContent = manifestFile.content;

    if (manifestContent == null) {
      throw TransferException(
        'The received manifest is empty.',
      );
    }

    final manifest = jsonDecode(
      utf8.decode(
        List<int>.from(manifestContent),
      ),
    ) as Map<String, dynamic>;

    final storage = StorageService.instance;

    await storage.replaceAll(
      writeFile: (
        docId,
        name,
        data,
      ) async {
        final dir = Directory(
          p.join(
            storage.vaultDir.path,
            docId,
          ),
        );

        if (!dir.existsSync()) {
          dir.createSync(
            recursive: true,
          );
        }

        final target = File(
          p.join(
            dir.path,
            name,
          ),
        );

        await target.writeAsBytes(data);

        return target.path;
      },
      files: [
        for (final file in archive.files)
          if (file.isFile &&
              file.name.startsWith('vault/') &&
              file.name.split('/').length >= 3)
            (
              docId: file.name.split('/')[1],
              name: p.basename(file.name),
              data: List<int>.from(
                file.content ?? const <int>[],
              ),
            ),
      ],
      manifest: manifest,
    );
  }

  // -------------------------------------------------------------- settings

  static const _portableSettingKeys = [
    SettingsKeys.themeMode,
    SettingsKeys.biometricEnabled,
    SettingsKeys.maskByDefault,
    SettingsKeys.reminderDaysBefore,
    SettingsKeys.onboarded,
    SettingsKeys.activeProfile,
    SettingsKeys.lockOnBackground,
    SettingsKeys.appLockEnabled,
  ];

  // ----------------------------------------------------------- serializers

  static Map<String, dynamic> _profileJson(
    Profile profile,
  ) =>
      {
        'id': profile.id,
        'name': profile.name,
        'relation': profile.relation,
        'color': profile.colorValue,
        'icon': profile.iconCodePoint,
        'isDefault': profile.isDefault,
        'createdAt':
            profile.createdAt.millisecondsSinceEpoch,
      };

  static Map<String, dynamic> _categoryJson(
    DocCategory category,
  ) =>
      {
        'id': category.id,
        'name': category.name,
        'icon': category.iconCodePoint,
        'color': category.colorValue,
        'mask': category.maskSensitive,
        'builtIn': category.isBuiltIn,
      };

  static Map<String, dynamic> _docJson(
    DocItem document,
  ) =>
      {
        'id': document.id,
        'title': document.title,
        'categoryId': document.categoryId,
        'documentNumber': document.documentNumber,
        'profileId': document.profileId,
        'issueDate':
            document.issueDate?.millisecondsSinceEpoch,
        'expiryDate':
            document.expiryDate?.millisecondsSinceEpoch,
        'notes': document.notes,
        'fileNames':
            document.filePaths.map(p.basename).toList(),
        'fileType': document.fileType.index,
        'maskByDefault': document.maskByDefault,
        'favorite': document.favorite,
        'createdAt':
            document.createdAt.millisecondsSinceEpoch,
        'updatedAt':
            document.updatedAt.millisecondsSinceEpoch,
      };
}

enum _ProbeResult {
  ok,
  wrongCode,
  miss,
}

typedef VoidCallback = void Function();
