import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:flux/features/connection/tools/cassette_audio.dart';

/// No plugin, codec, speaker, microphone, filesystem or background timer.
class FixtureMediaController extends VideoPlayerController {
  final calls = <String>[];
  final holds = <String, Future<void>>{};
  final _entered = <String, Completer<void>>{};
  final volumes = <double>[];
  final loops = <bool>[];
  final seeks = <Duration>[];
  final failStages = <String>{};
  bool failInitialization = false;
  bool disposed = false;
  final bool audioOnly;

  FixtureMediaController(String path, {this.audioOnly = true})
    : super.file(File(path));

  Future<void> entered(String stage) =>
      (_entered[stage] ??= Completer<void>()).future;
  Future<void> _stage(String stage) async {
    calls.add(stage);
    final entered = _entered[stage] ??= Completer<void>();
    if (!entered.isCompleted) entered.complete();
    if (failStages.contains(stage)) throw StateError('Fixture $stage failure');
    await holds[stage];
  }

  @override
  Future<void> initialize() async {
    await _stage('initialize');
    if (failInitialization) throw StateError('Fixture decode failure');
    if (!disposed) {
      value = value.copyWith(
        isInitialized: true,
        duration: const Duration(seconds: 16),
        size: audioOnly ? Size.zero : const Size(16, 16),
      );
    }
  }

  @override
  Future<void> setLooping(bool looping) async {
    loops.add(looping);
    await _stage('loop');
    if (!disposed) value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    await _stage('volume');
    if (!disposed) value = value.copyWith(volume: volume);
  }

  @override
  Future<void> play() async {
    await _stage('play');
    if (!disposed) value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    await _stage('pause');
    if (!disposed) value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    await _stage('seek');
    if (!disposed) {
      value = value.copyWith(position: position, isCompleted: false);
    }
  }

  void advance(Duration position) {
    if (!disposed) value = value.copyWith(position: position);
  }

  @override
  Future<void> dispose() async {
    await _stage('dispose');
    disposed = true;
    await super.dispose();
  }
}

class MemoryCassetteSource implements CassetteAudioSource {
  final prepared = <int>[];
  bool disposed = false;
  Future<String>? hold;
  @override
  Future<String> prepare(int tape) async {
    prepared.add(tape);
    return await hold ?? 'D:/fixtures/tape-$tape.wav';
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
