import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/voxel_renderer.dart';
import 'package:flux/features/connection/tools/voxel_world.dart';

Future<Uint8List> frame(VoxelSandbox sandbox) async {
  final recording = ui.PictureRecorder();
  final canvas = Canvas(recording);
  VoxelWorldPainter(sandbox).paint(canvas, const Size(320, 200));
  final picture = recording.endRecording();
  final image = await picture.toImage(320, 200);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'camera basis is orthonormal and projection has genuine perspective',
    () {
      final player = VoxelPlayer(
        position: const VoxelVector(4.5, 2, 3.5),
        yaw: .4,
        pitch: -.3,
      );
      final camera = VoxelCamera(player);
      expect(camera.forward.length, closeTo(1, 1e-9));
      expect(camera.right.dot(camera.forward), closeTo(0, 1e-9));
      expect(camera.up.dot(camera.forward), closeTo(0, 1e-9));
      final ahead = camera.transform(player.eye + player.forward * 5);
      expect(ahead.x, closeTo(0, 1e-9));
      expect(ahead.y, closeTo(0, 1e-9));
      expect(ahead.z, closeTo(5, 1e-9));
      expect(
        camera.project(ahead, const Size(320, 200)).dx,
        closeTo(160, 1e-9),
      );
      final near = camera.project(
        const VoxelVector(1, 0, 2),
        const Size(320, 200),
      );
      final far = camera.project(
        const VoxelVector(1, 0, 4),
        const Size(320, 200),
      );
      expect(near.dx - 160, closeTo((far.dx - 160) * 2, 1e-9));
    },
  );

  test(
    'exposed voxel faces alter the rendered image beyond just sky and crosshair',
    () async {
      final world = VoxelWorld(width: 8, height: 8, depth: 8, generate: false);
      final player = VoxelPlayer(
        position: const VoxelVector(3.5, 1, 1.5),
        yaw: 0,
        pitch: 0,
      );
      final sandbox = VoxelSandbox(world: world, player: player);
      final sky = await frame(sandbox);
      world.setBlock(const BlockCell(3, 2, 4), VoxelMaterial.brick);
      final blocks = await frame(sandbox);
      var differences = 0;
      for (var i = 0; i < sky.length; i += 4) {
        if (sky[i] != blocks[i] ||
            sky[i + 1] != blocks[i + 1] ||
            sky[i + 2] != blocks[i + 2]) {
          differences++;
        }
      }
      expect(differences, greaterThan(500));
      sandbox.night = true;
      final night = await frame(sandbox);
      expect(night, isNot(blocks));
    },
  );

  test(
    'near-plane intersections, behind-camera faces and tiny viewports do not produce invalid paths',
    () async {
      final world = VoxelWorld(width: 8, height: 8, depth: 8, generate: false);
      for (var z = 0; z < 8; z++) {
        world.setBlock(BlockCell(3, 2, z), VoxelMaterial.wood);
      }
      final sandbox = VoxelSandbox(
        world: world,
        player: VoxelPlayer(
          position: const VoxelVector(3.5, 1, 3.98),
          yaw: .35,
          pitch: 0,
        ),
      );
      expect((await frame(sandbox)).length, 320 * 200 * 4);
      final recording = ui.PictureRecorder();
      final painter = VoxelWorldPainter(sandbox);
      painter.paint(Canvas(recording), const Size(1, 1));
      recording.endRecording().dispose();
      final empty = ui.PictureRecorder();
      painter.paint(Canvas(empty), Size.zero);
      empty.endRecording().dispose();
    },
  );

  test(
    'idle view does not repaint; world, camera and day edits invalidate its captured state',
    () {
      final sandbox = VoxelSandbox();
      final original = VoxelWorldPainter(sandbox);
      expect(VoxelWorldPainter(sandbox).shouldRepaint(original), false);
      sandbox.player.look(.1, 0);
      expect(VoxelWorldPainter(sandbox).shouldRepaint(original), true);
      final rotated = VoxelWorldPainter(sandbox);
      sandbox.night = true;
      expect(VoxelWorldPainter(sandbox).shouldRepaint(rotated), true);
      final night = VoxelWorldPainter(sandbox);
      sandbox.world.setBlock(const BlockCell(1, 12, 1), VoxelMaterial.brick);
      expect(VoxelWorldPainter(sandbox).shouldRepaint(night), true);
    },
  );
}
