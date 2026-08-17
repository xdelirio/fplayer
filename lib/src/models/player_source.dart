import 'package:flutter/foundation.dart';

/// Streaming container of a source.
///
/// [auto] is almost always the right choice: the engine infers the format from the URI and from
/// the response `Content-Type`, which is more reliable than guessing from the path. Force a value
/// only when the endpoint serves a manifest behind an extensionless URL *and* a wrong
/// `Content-Type`.
enum FSourceType { auto, hls, dash, smoothStreaming, progressive }

/// Where the media bytes come from.
enum FSourceKind { network, file, asset }

/// An external subtitle track supplied by the app.
///
/// Side-loaded rather than muxed: the player fetches it separately and renders it in Flutter, so
/// it can carry its own headers and outlive a source change.
@immutable
class FSubtitleSource {
  const FSubtitleSource.network(
    this.uri, {
    this.label,
    this.language,
    this.mimeType,
    this.headers = const {},
    this.selectedByDefault = false,
  }) : kind = FSourceKind.network;

  const FSubtitleSource.file(
    this.uri, {
    this.label,
    this.language,
    this.mimeType,
    this.selectedByDefault = false,
  })  : kind = FSourceKind.file,
        headers = const {};

  final FSourceKind kind;

  /// URL or absolute file path of the subtitle file.
  final String uri;

  /// Name shown in the track picker. Falls back to [language] when null.
  final String? label;

  /// BCP-47 language tag, e.g. `es`, `es-419`, `en`.
  final String? language;

  /// Explicit MIME type. Inferred from the extension when null.
  final String? mimeType;

  /// Headers used to fetch this file, independent of the media's own headers.
  final Map<String, String> headers;

  /// Whether this track should be selected as soon as the media loads.
  final bool selectedByDefault;

  Map<String, Object?> toMap() => {
        'kind': kind.name,
        'uri': uri,
        'label': label,
        'language': language,
        'mimeType': mimeType,
        'headers': headers,
        'selectedByDefault': selectedByDefault,
      };
}

/// Thumbnail track used to preview frames while scrubbing.
///
/// A WebVTT index whose cues point into sprite sheets, which is how every player that shows a
/// preview above the seek bar does it.
@immutable
class FStoryboardSource {
  /// WebVTT index whose cues point at sprite sheets, optionally with `#xywh=` fragments.
  const FStoryboardSource.vtt(this.uri, {this.headers = const {}}) : format = 'vtt';

  final String format;
  final String uri;
  final Map<String, String> headers;

  Map<String, Object?> toMap() => {
        'format': format,
        'uri': uri,
        'headers': headers,
      };
}

/// A marked span of the timeline: a chapter, an intro to skip, closing credits.
@immutable
class FChapter {
  const FChapter({
    required this.start,
    required this.title,
    this.end,
    this.kind = FChapterKind.chapter,
  });

  final Duration start;
  final Duration? end;
  final String title;
  final FChapterKind kind;
}

enum FChapterKind { chapter, intro, recap, credits, ad }

/// DRM parameters for protected content.
///
/// Only Widevine is offered: it is the scheme Android devices actually ship, and PlayReady
/// support would be a claim this package cannot honour on the platforms it targets.
@immutable
class FDrmConfig {
  const FDrmConfig.widevine({
    required this.licenseUrl,
    this.headers = const {},
    this.multiSession = false,
    this.playClearContentWithoutKey = false,
    this.forceDefaultLicenseUri = false,
  }) : scheme = 'widevine';

  final String scheme;

  /// Where license requests go.
  final String licenseUrl;

  /// Headers for the license request — typically the auth the CDN itself does not need.
  ///
  /// Kept separate from the media's headers because a license server is usually a different
  /// service with different credentials.
  final Map<String, String> headers;

  /// Keep a session per media period instead of reusing one.
  ///
  /// Needed for content whose periods carry different keys; wasteful otherwise, since each
  /// session is a round trip to the license server.
  final bool multiSession;

  /// Start playing the unencrypted opening of the media without waiting for a license.
  ///
  /// Worth turning on when the content has a clear lead-in — a logo sting, an advert — because it
  /// hides the license round trip behind something the viewer is already watching.
  final bool playClearContentWithoutKey;

  /// Ignore any license URI the manifest carries and always use [licenseUrl].
  ///
  /// Manifests are often packaged once and served to several apps; this is how you make sure the
  /// license request lands on *your* server rather than whichever one the packager baked in.
  final bool forceDefaultLicenseUri;

  Map<String, Object?> toMap() => {
        'scheme': scheme,
        'licenseUrl': licenseUrl,
        'headers': headers,
        'multiSession': multiSession,
        'playClearContentWithoutKey': playClearContentWithoutKey,
        'forceDefaultLicenseUri': forceDefaultLicenseUri,
      };
}

/// Everything needed to play one piece of media.
///
/// A source is immutable and cheap to build, so it is fine to construct one per playback and hand
/// it to [FPlayerController.open].
@immutable
class FPlayerSource {
  /// Media served over HTTP(S): a progressive file, an HLS master playlist, a DASH manifest.
  const FPlayerSource.network(
    this.uri, {
    this.type = FSourceType.auto,
    this.headers = const {},
    this.title,
    this.subtitle,
    this.posterUrl,
    this.startAt,
    this.isLive = false,
    this.subtitles = const [],
    this.storyboard,
    this.chapters = const [],
    this.drm,
    this.metadata,
  })  : kind = FSourceKind.network,
        package = null;

  /// A file on the device. [uri] must be an absolute path.
  const FPlayerSource.file(
    this.uri, {
    this.title,
    this.subtitle,
    this.posterUrl,
    this.startAt,
    this.subtitles = const [],
    this.storyboard,
    this.chapters = const [],
    this.metadata,
  })  : kind = FSourceKind.file,
        type = FSourceType.auto,
        headers = const {},
        isLive = false,
        drm = null,
        package = null;

  /// A Flutter asset bundled with the app.
  const FPlayerSource.asset(
    this.uri, {
    this.package,
    this.title,
    this.subtitle,
    this.startAt,
    this.subtitles = const [],
    this.chapters = const [],
    this.metadata,
  })  : kind = FSourceKind.asset,
        type = FSourceType.auto,
        headers = const {},
        posterUrl = null,
        isLive = false,
        storyboard = null,
        drm = null;

  final FSourceKind kind;

  /// URL, absolute file path, or asset key depending on [kind].
  final String uri;

  /// Package the asset belongs to, for `FPlayerSource.asset` inside another package.
  final String? package;

  final FSourceType type;

  /// Headers sent with every request for this media, including its segments.
  final Map<String, String> headers;

  final String? title;
  final String? subtitle;
  final String? posterUrl;

  /// Position to start at. Used for "resume where you left off".
  final Duration? startAt;

  /// Hint that this is a live stream. The engine detects it on its own for HLS/DASH; set it when
  /// the UI must commit to the live layout before the manifest is parsed.
  final bool isLive;

  final List<FSubtitleSource> subtitles;
  final FStoryboardSource? storyboard;
  final List<FChapter> chapters;
  final FDrmConfig? drm;

  /// Free-form payload owned by the host app — content ids, analytics tags, anything.
  ///
  /// The player never reads it; observers and your own callbacks do.
  final Object? metadata;

  FPlayerSource copyWith({Duration? startAt}) => _copy(startAt: startAt ?? this.startAt);

  FPlayerSource _copy({Duration? startAt}) {
    switch (kind) {
      case FSourceKind.network:
        return FPlayerSource.network(
          uri,
          type: type,
          headers: headers,
          title: title,
          subtitle: subtitle,
          posterUrl: posterUrl,
          startAt: startAt,
          isLive: isLive,
          subtitles: subtitles,
          storyboard: storyboard,
          chapters: chapters,
          drm: drm,
          metadata: metadata,
        );
      case FSourceKind.file:
        return FPlayerSource.file(
          uri,
          title: title,
          subtitle: subtitle,
          posterUrl: posterUrl,
          startAt: startAt,
          subtitles: subtitles,
          storyboard: storyboard,
          chapters: chapters,
          metadata: metadata,
        );
      case FSourceKind.asset:
        return FPlayerSource.asset(
          uri,
          package: package,
          title: title,
          subtitle: subtitle,
          startAt: startAt,
          subtitles: subtitles,
          chapters: chapters,
          metadata: metadata,
        );
    }
  }

  /// Wire format for the platform channel. Only the fields the engine consumes are included.
  Map<String, Object?> toMap() => {
        'kind': kind.name,
        'uri': uri,
        'package': package,
        'type': type.name,
        'headers': headers,
        'startAtMs': startAt?.inMilliseconds ?? 0,
        'drm': drm?.toMap(),
        'isLive': isLive,
        'subtitles': subtitles.map((s) => s.toMap()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FPlayerSource &&
          other.uri == uri &&
          other.kind == kind &&
          other.type == type &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.posterUrl == posterUrl &&
          other.startAt == startAt &&
          other.isLive == isLive &&
          other.package == package &&
          mapEquals(other.headers, headers) &&
          listEquals(other.subtitles, subtitles) &&
          listEquals(other.chapters, chapters);

  @override
  int get hashCode => Object.hash(
        uri,
        kind,
        type,
        title,
        subtitle,
        posterUrl,
        startAt,
        isLive,
        package,
        Object.hashAll(headers.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(subtitles),
        Object.hashAll(chapters),
      );

  @override
  String toString() => 'FPlayerSource.${kind.name}($uri)';
}
