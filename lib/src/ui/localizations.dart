import 'package:flutter/foundation.dart';

/// Every string the bundled controls can show.
///
/// A plain value class rather than a `LocalizationsDelegate`: apps already have their own
/// localisation setup, and asking them to register a delegate for fifteen words is friction. Pass
/// an instance built from your own translations, or override a few strings on top of a preset.
///
/// ```dart
/// FPlayerLocalizations.spanish().copyWith(quality: 'Resolución')
/// ```
@immutable
class FPlayerLocalizations {
  const FPlayerLocalizations({
    this.play = 'Play',
    this.pause = 'Pause',
    this.replay = 'Replay',
    this.forward = 'Forward',
    this.rewind = 'Rewind',
    this.seconds = 'seconds',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.settings = 'Settings',
    this.audio = 'Audio',
    this.subtitles = 'Subtitles',
    this.audioAndSubtitles = 'Audio & Subtitles',
    this.audioAndSubsShort = 'Audio & Subs',
    this.quality = 'Quality',
    this.speed = 'Speed',
    this.off = 'Off',
    this.auto = 'Auto',
    this.normal = 'Normal',
    this.live = 'LIVE',
    this.goLive = 'Go live',
    this.lock = 'Lock controls',
    this.unlock = 'Unlock',
    this.lockedHint = 'Controls locked',
    this.enterFullscreen = 'Fullscreen',
    this.exitFullscreen = 'Exit fullscreen',
    this.pictureInPicture = 'Picture in picture',
    this.back = 'Back',
    this.next = 'Next',
    this.previous = 'Previous',
    this.nextUp = 'Up next',
    this.playNow = 'Play now',
    this.skipIntro = 'Skip intro',
    this.skipRecap = 'Skip recap',
    this.skipCredits = 'Skip credits',
    this.skipAd = 'Skip ad',
    this.waitingForNetwork = 'Waiting for a connection…',
    this.retry = 'Try again',
    this.cancel = 'Cancel',
    this.apply = 'Apply',
    this.errorTitle = 'Playback failed',
    this.errorNetwork = 'Check your connection and try again.',
    this.errorUnauthorized = 'Your session expired. Sign in again.',
    this.errorNotFound = 'This video is no longer available.',
    this.errorUnsupported = 'This device cannot play this video.',
    this.errorGeneric = 'Something went wrong playing this video.',
  });

  /// Spanish preset.
  const FPlayerLocalizations.spanish()
      : this(
          play: 'Reproducir',
          pause: 'Pausar',
          replay: 'Volver a ver',
          forward: 'Avanzar',
          rewind: 'Retroceder',
          seconds: 'segundos',
          mute: 'Silenciar',
          unmute: 'Activar sonido',
          settings: 'Ajustes',
          audio: 'Audio',
          subtitles: 'Subtítulos',
          audioAndSubtitles: 'Audio & Subtítulos',
          audioAndSubsShort: 'Audio & Subs',
          quality: 'Calidad',
          speed: 'Velocidad',
          off: 'Desactivados',
          auto: 'Automática',
          normal: 'Normal',
          live: 'EN VIVO',
          goLive: 'Ir al directo',
          lock: 'Bloquear controles',
          unlock: 'Desbloquear',
          lockedHint: 'Controles bloqueados',
          enterFullscreen: 'Pantalla completa',
          exitFullscreen: 'Salir de pantalla completa',
          pictureInPicture: 'Imagen en imagen',
          back: 'Atrás',
          next: 'Siguiente',
          previous: 'Anterior',
          nextUp: 'A continuación',
          playNow: 'Reproducir ya',
          skipIntro: 'Saltar intro',
          skipRecap: 'Saltar resumen',
          skipCredits: 'Saltar créditos',
          skipAd: 'Saltar anuncio',
          waitingForNetwork: 'Esperando conexión…',
          retry: 'Reintentar',
          cancel: 'Cancelar',
          apply: 'Aplicar',
          errorTitle: 'No se pudo reproducir',
          errorNetwork: 'Revisa tu conexión y vuelve a intentarlo.',
          errorUnauthorized: 'Tu sesión expiró. Inicia sesión de nuevo.',
          errorNotFound: 'Este video ya no está disponible.',
          errorUnsupported: 'Este dispositivo no puede reproducir este video.',
          errorGeneric: 'Ocurrió un problema al reproducir este video.',
        );

  final String play;
  final String pause;
  final String replay;
  final String forward;
  final String rewind;

  /// Unit shown under the double-tap seek ripple, after the number: "10 seconds".
  final String seconds;
  final String mute;
  final String unmute;
  final String settings;
  final String audio;
  final String subtitles;

  /// Title of the dialog that holds both, and the label of the control that opens it.
  final String audioAndSubtitles;

  /// The same control on a narrow player, where the full name would push the row off screen.
  final String audioAndSubsShort;
  final String quality;
  final String speed;

  /// Shown as the "no subtitles" entry.
  final String off;

  /// Shown as the "let the player decide" entry for audio and quality.
  final String auto;

  /// Label for 1× playback speed.
  final String normal;

  final String live;
  final String goLive;
  final String lock;
  final String unlock;
  final String lockedHint;
  final String enterFullscreen;
  final String exitFullscreen;
  final String pictureInPicture;
  final String back;
  final String next;
  final String previous;

  final String nextUp;
  final String playNow;

  final String skipIntro;
  final String skipRecap;
  final String skipCredits;
  final String skipAd;

  final String waitingForNetwork;

  final String retry;

  /// The two ways out of the audio and subtitles dialog, which holds a choice until it is
  /// confirmed rather than acting on the first row that is tapped.
  final String cancel;
  final String apply;

  final String errorTitle;
  final String errorNetwork;
  final String errorUnauthorized;
  final String errorNotFound;
  final String errorUnsupported;
  final String errorGeneric;

  FPlayerLocalizations copyWith({
    String? play,
    String? pause,
    String? replay,
    String? forward,
    String? rewind,
    String? seconds,
    String? mute,
    String? unmute,
    String? settings,
    String? audio,
    String? subtitles,
    String? audioAndSubtitles,
    String? audioAndSubsShort,
    String? quality,
    String? speed,
    String? off,
    String? auto,
    String? normal,
    String? live,
    String? goLive,
    String? lock,
    String? unlock,
    String? lockedHint,
    String? enterFullscreen,
    String? exitFullscreen,
    String? pictureInPicture,
    String? back,
    String? next,
    String? previous,
    String? nextUp,
    String? playNow,
    String? skipIntro,
    String? skipRecap,
    String? skipCredits,
    String? skipAd,
    String? waitingForNetwork,
    String? retry,
    String? cancel,
    String? apply,
    String? errorTitle,
    String? errorNetwork,
    String? errorUnauthorized,
    String? errorNotFound,
    String? errorUnsupported,
    String? errorGeneric,
  }) =>
      FPlayerLocalizations(
        play: play ?? this.play,
        pause: pause ?? this.pause,
        replay: replay ?? this.replay,
        forward: forward ?? this.forward,
        rewind: rewind ?? this.rewind,
        seconds: seconds ?? this.seconds,
        mute: mute ?? this.mute,
        unmute: unmute ?? this.unmute,
        settings: settings ?? this.settings,
        audio: audio ?? this.audio,
        subtitles: subtitles ?? this.subtitles,
        audioAndSubtitles: audioAndSubtitles ?? this.audioAndSubtitles,
        audioAndSubsShort: audioAndSubsShort ?? this.audioAndSubsShort,
        quality: quality ?? this.quality,
        speed: speed ?? this.speed,
        off: off ?? this.off,
        auto: auto ?? this.auto,
        normal: normal ?? this.normal,
        live: live ?? this.live,
        goLive: goLive ?? this.goLive,
        lock: lock ?? this.lock,
        unlock: unlock ?? this.unlock,
        lockedHint: lockedHint ?? this.lockedHint,
        enterFullscreen: enterFullscreen ?? this.enterFullscreen,
        exitFullscreen: exitFullscreen ?? this.exitFullscreen,
        pictureInPicture: pictureInPicture ?? this.pictureInPicture,
        back: back ?? this.back,
        next: next ?? this.next,
        previous: previous ?? this.previous,
        nextUp: nextUp ?? this.nextUp,
        playNow: playNow ?? this.playNow,
        skipIntro: skipIntro ?? this.skipIntro,
        skipRecap: skipRecap ?? this.skipRecap,
        skipCredits: skipCredits ?? this.skipCredits,
        skipAd: skipAd ?? this.skipAd,
        waitingForNetwork: waitingForNetwork ?? this.waitingForNetwork,
        retry: retry ?? this.retry,
        cancel: cancel ?? this.cancel,
        apply: apply ?? this.apply,
        errorTitle: errorTitle ?? this.errorTitle,
        errorNetwork: errorNetwork ?? this.errorNetwork,
        errorUnauthorized: errorUnauthorized ?? this.errorUnauthorized,
        errorNotFound: errorNotFound ?? this.errorNotFound,
        errorUnsupported: errorUnsupported ?? this.errorUnsupported,
        errorGeneric: errorGeneric ?? this.errorGeneric,
      );
}
