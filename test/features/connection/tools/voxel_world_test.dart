import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/voxel_world.dart';

VoxelWorld emptyWorld() =>
    VoxelWorld(width: 8, height: 8, depth: 8, generate: false);

void main() {
  test(
    'terrain is deterministic, bounded and genuinely has three dimensions',
    () {
      final first = VoxelWorld(seed: 1337);
      final second = VoxelWorld(seed: 1337);
      expect(first.blockCount, greaterThan(1000));
      expect(first.blockCount, second.blockCount);
      for (var y = 0; y < first.height; y++) {
        for (var z = 0; z < first.depth; z++) {
          for (var x = 0; x < first.width; x++) {
            expect(
              first.materialAt(BlockCell(x, y, z)),
              second.materialAt(BlockCell(x, y, z)),
            );
          }
        }
      }
      final sandbox = VoxelSandbox(world: first);
      expect(identical(sandbox.world, first), true);
      expect(sandbox.player.canOccupy(first, sandbox.player.position), true);
      expect(sandbox.player.grounded(first), true);
    },
  );

  test(
    'adjacent cubes omit hidden faces and rebuild the mesh only on edits',
    () {
      final world = emptyWorld();
      expect(
        world.setBlock(const BlockCell(3, 2, 3), VoxelMaterial.stone),
        true,
      );
      final first = world.exposedFaces;
      expect(first.length, 6);
      expect(identical(first, world.exposedFaces), true);
      expect(
        world.setBlock(const BlockCell(4, 2, 3), VoxelMaterial.wood),
        true,
      );
      expect(world.exposedFaces.length, 10);
      expect(identical(first, world.exposedFaces), false);
      expect(
        world.setBlock(const BlockCell(4, 2, 3), VoxelMaterial.wood),
        false,
      );
      expect(world.blockCount, 2);
      world.setBlock(const BlockCell(4, 2, 3), null);
      expect(world.blockCount, 1);
      expect(world.exposedFaces.length, 6);
    },
  );

  test(
    'ray picking returns the nearest actual cube and outward adjacent cell',
    () {
      final world = emptyWorld();
      world.setBlock(const BlockCell(3, 2, 4), VoxelMaterial.brick);
      world.setBlock(const BlockCell(3, 2, 6), VoxelMaterial.stone);
      final hit = world.raycast(
        const VoxelVector(3.5, 2.5, 1.5),
        const VoxelVector(0, 0, 1),
      );
      expect(hit?.cell, const BlockCell(3, 2, 4));
      expect(hit?.adjacent, const BlockCell(3, 2, 3));
      expect(hit?.distance, closeTo(2.5, 1e-9));
      expect(hit?.material, VoxelMaterial.brick);
      expect(hit?.faceDirection, 5);
      expect(
        world.raycast(
          const VoxelVector(3.5, 2.5, 1.5),
          const VoxelVector(0, 0, 1),
          reach: 2,
        ),
        isNull,
      );
    },
  );

  test(
    'negative rays and exact voxel boundaries traverse without an infinite loop',
    () {
      final world = emptyWorld()
        ..setBlock(const BlockCell(2, 2, 2), VoxelMaterial.grass);
      final hit = world.raycast(
        const VoxelVector(3, 2.5, 2.5),
        const VoxelVector(-1, 0, 0),
      );
      expect(hit?.cell, const BlockCell(2, 2, 2));
      expect(hit?.distance, 0);
      expect(
        world.raycast(const VoxelVector(1, 1, 1), const VoxelVector(0, 0, 0)),
        isNull,
      );
      expect(
        world.raycast(
          const VoxelVector(double.nan, 1, 1),
          const VoxelVector(1, 0, 0),
        ),
        isNull,
      );
    },
  );

  test(
    'movement collides with cubes, gravity lands and Space jumps without flight',
    () {
      final world = emptyWorld();
      for (var x = 0; x < 8; x++) {
        for (var z = 0; z < 8; z++) {
          world.setBlock(BlockCell(x, 0, z), VoxelMaterial.stone);
        }
      }
      for (var y = 1; y <= 3; y++) {
        world.setBlock(BlockCell(3, y, 4), VoxelMaterial.brick);
      }
      final player = VoxelPlayer(
        position: const VoxelVector(3.5, 1, 2.5),
        yaw: 0,
        pitch: 0,
      );
      for (var i = 0; i < 60; i++) {
        player.step(world, 1 / 60, forwardInput: 1);
      }
      expect(player.position.z + VoxelPlayer.radius, lessThanOrEqualTo(4));
      expect(player.canOccupy(world, player.position), true);
      expect(player.jump(world), true);
      expect(
        player.jump(world),
        false,
      ); // Velocity already upward, still on ground until first step.
    },
  );

  test(
    'jump height is finite, lands again and falling never tunnels through floor',
    () {
      final world = emptyWorld();
      for (var x = 0; x < 8; x++) {
        for (var z = 0; z < 8; z++) {
          world.setBlock(BlockCell(x, 0, z), VoxelMaterial.stone);
        }
      }
      final player = VoxelPlayer(position: const VoxelVector(3.5, 1, 2.5));
      player.jump(world);
      var highest = player.position.y;
      for (var i = 0; i < 160; i++) {
        player.step(world, 1 / 60);
        highest = math.max(highest, player.position.y);
      }
      expect(highest, inInclusiveRange(2.0, 2.8));
      expect(player.position.y, inInclusiveRange(1, 1.06));
      expect(player.grounded(world), true);
      expect(player.verticalVelocity, 0);
    },
  );

  test('placement and digging edit the voxel hit, not a 2D cell list', () {
    final world = emptyWorld()
      ..setBlock(const BlockCell(3, 2, 4), VoxelMaterial.stone);
    final sandbox = VoxelSandbox(
      world: world,
      player: VoxelPlayer(
        position: const VoxelVector(3.5, 1, 1.5),
        yaw: 0,
        pitch: 0,
      ),
    );
    sandbox.material = VoxelMaterial.wood;
    expect(sandbox.placeTarget(), true);
    expect(world.materialAt(const BlockCell(3, 2, 3)), VoxelMaterial.wood);
    expect(sandbox.target?.cell, const BlockCell(3, 2, 3));
    expect(sandbox.removeTarget(), true);
    expect(world.materialAt(const BlockCell(3, 2, 3)), isNull);
  });

  test('world bounds, foundation and player volume are protected', () {
    final world = emptyWorld()
      ..setBlock(const BlockCell(3, 2, 2), VoxelMaterial.stone);
    final sandbox = VoxelSandbox(
      world: world,
      player: VoxelPlayer(
        position: const VoxelVector(3.5, 1, 1.5),
        yaw: 0,
        pitch: 0,
      ),
    );
    expect(sandbox.placeTarget(), false);
    expect(
      world.setBlock(const BlockCell(-1, 1, 1), VoxelMaterial.grass),
      false,
    );
    expect(world.materialAt(const BlockCell(8, 1, 1)), isNull);
    sandbox.player.look(0, 999);
    expect(sandbox.player.pitch, 1.35);
    expect(() => VoxelWorld(width: 999), throwsArgumentError);
  });
}
