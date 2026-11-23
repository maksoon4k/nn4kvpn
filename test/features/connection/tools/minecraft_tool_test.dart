import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/minecraft_tool.dart';
import 'package:flux/features/connection/tools/voxel_renderer.dart';
import 'package:flux/features/connection/tools/voxel_world.dart';

import '../../../support/tool_host.dart';

VoxelSandbox fixtureSandbox() {
  final world = VoxelWorld(width: 8, height: 8, depth: 8, generate: false);
  for (var x = 0; x < 8; x++) {
    for (var z = 0; z < 8; z++) {
      world.setBlock(BlockCell(x, 0, z), VoxelMaterial.stone);
    }
  }
  world.setBlock(const BlockCell(3, 2, 4), VoxelMaterial.stone);
  world.setBlock(const BlockCell(3, 2, 6), VoxelMaterial.brick);
  return VoxelSandbox(
    world: world,
    player: VoxelPlayer(
      position: const VoxelVector(3.5, 1, 1.5),
      yaw: 0,
      pitch: 0,
    ),
  );
}

void main() {
  testWidgets(
    'perspective viewport paints, buttons really edit targeted voxels and material/day settings work',
    (tester) async {
      final sandbox = fixtureSandbox();
      await tester.pumpWidget(
        toolHost(MinecraftTool(createSandbox: () => sandbox), width: 600),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('minecraft-3d-render')),
            )
            .painter,
        isA<VoxelWorldPainter>(),
      );
      await tapToolKey(tester, 'minecraft-material');
      await tapToolKey(tester, 'minecraft-place');
      expect(
        sandbox.world.materialAt(const BlockCell(3, 2, 3)),
        VoxelMaterial.stone,
      );
      await tapToolKey(tester, 'minecraft-break');
      expect(sandbox.world.materialAt(const BlockCell(3, 2, 3)), isNull);
      await tapToolKey(tester, 'minecraft-day-night');
      expect(sandbox.night, true);
      expect(find.text('Сделать день'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WASD, number hotkeys and jump operate on the 3D player, not a grid',
    (tester) async {
      final sandbox = fixtureSandbox();
      await tester.pumpWidget(
        toolHost(MinecraftTool(createSandbox: () => sandbox), width: 600),
      );
      await tester.pumpAndSettle();
      final start = sandbox.player.position;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      expect(sandbox.player.position.z, greaterThan(start.z));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.pump();
      expect(sandbox.material, VoxelMaterial.brick);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sandbox.player.position.y, greaterThan(1));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(sandbox.player.grounded(sandbox.world), true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'primary and secondary mouse clicks dig and place actual cubes; drag only looks',
    (tester) async {
      final sandbox = fixtureSandbox();
      await tester.pumpWidget(
        toolHost(MinecraftTool(createSandbox: () => sandbox), width: 600),
      );
      await tester.pumpAndSettle();
      final viewport = find.byKey(const ValueKey('minecraft-viewport'));
      await tester.tap(viewport, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(sandbox.world.materialAt(const BlockCell(3, 2, 4)), isNull);
      await tester.tap(
        viewport,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        sandbox.world.materialAt(const BlockCell(3, 2, 5)),
        VoxelMaterial.grass,
      );
      final blocks = sandbox.world.blockCount;
      await tester.drag(
        viewport,
        const Offset(40, 12),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(sandbox.player.yaw, greaterThan(0));
      expect(sandbox.player.pitch, lessThan(0));
      expect(sandbox.world.blockCount, blocks);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'losing application focus stops held movement; disposal always stops the ticker',
    (tester) async {
      final sandbox = fixtureSandbox();
      await tester.pumpWidget(
        toolHost(MinecraftTool(createSandbox: () => sandbox), width: 600),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 32));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final paused = sandbox.player.position;
      await tester.pump(const Duration(seconds: 1));
      expect(sandbox.player.position, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      expect(sandbox.player.position, paused);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
