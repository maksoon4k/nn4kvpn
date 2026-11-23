import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'voxel_world.dart';

class VoxelCamera {
  final VoxelVector eye;
  final VoxelVector forward;
  final VoxelVector right;
  final VoxelVector up;
  VoxelCamera(VoxelPlayer player)
    : eye = player.eye,
      forward = player.forward,
      right = player.right,
      up = player.up;
  VoxelVector transform(VoxelVector point) {
    final relative = point - eye;
    return VoxelVector(
      relative.dot(right),
      relative.dot(up),
      relative.dot(forward),
    );
  }

  Offset project(VoxelVector point, Size size) {
    final focal = size.height * .5 / math.tan(70 * math.pi / 360);
    return Offset(
      size.width * .5 + point.x * focal / point.z,
      size.height * .5 - point.y * focal / point.z,
    );
  }
}

/// Perspective projection of exposed 3D faces, with back-face/frustum culling,
/// near/far clipping, depth sorting, fog and small procedural pixel textures.
/// Idle views do not animate; there is no bundled 3D engine or game download.
class VoxelWorldPainter extends CustomPainter {
  final VoxelWorld world;
  final VoxelCamera camera;
  final int revision;
  final double yaw;
  final double pitch;
  final bool night;
  final VoxelRayHit? target;
  VoxelWorldPainter(VoxelSandbox sandbox)
    : world = sandbox.world,
      camera = VoxelCamera(sandbox.player),
      revision = sandbox.world.revision,
      yaw = sandbox.player.yaw,
      pitch = sandbox.player.pitch,
      night = sandbox.night,
      target = sandbox.target;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final sky = night ? const Color(0xFF142343) : const Color(0xFF96CDEA);
    final skyTop = night ? const Color(0xFF071124) : const Color(0xFF4A9DD5);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
          skyTop,
          sky,
        ]),
    );
    canvas.drawCircle(
      Offset(size.width * .80, size.height * .17),
      night ? 13 : 19,
      Paint()
        ..color = night ? const Color(0xFFE4EAF7) : const Color(0xFFFFF0B5),
    );

    final visible = <_VisibleFace>[];
    for (final face in world.exposedFaces) {
      final toEye = camera.eye - face.center;
      if (face.normal.origin.dot(toEye) <= 0) continue;
      final center = camera.transform(face.center);
      if (center.z < -.8 || center.z > 20 || toEye.length > 21) continue;
      final path = _path(face.corners, size);
      if (path == null || !path.getBounds().overlaps(Offset.zero & size)) {
        continue;
      }
      visible.add(_VisibleFace(face, center.z, toEye.length, path));
    }
    visible.sort((a, b) => b.depth.compareTo(a.depth));
    final paint = Paint()..isAntiAlias = false;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = const Color(0x25000000);
    for (final projected in visible) {
      final face = projected.face;
      paint.color = _shade(
        _base(face.material, face.direction),
        face.direction,
        projected.distance,
        sky,
      );
      canvas.drawPath(projected.path, paint);
      if (projected.distance < 7) _pixels(canvas, size, projected, paint, sky);
      canvas.drawPath(projected.path, edge);
    }

    final selected = target;
    if (selected != null && selected.faceDirection >= 0) {
      final path = _path(
        VoxelFace(
          selected.cell,
          selected.faceDirection,
          selected.material,
        ).corners,
        size,
      );
      if (path != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    final crosshair = Paint()
      ..color = const Color(0xEEFFFFFF)
      ..strokeWidth = 1.5;
    final center = size.center(Offset.zero);
    canvas.drawLine(
      center - const Offset(6, 0),
      center + const Offset(6, 0),
      crosshair,
    );
    canvas.drawLine(
      center - const Offset(0, 6),
      center + const Offset(0, 6),
      crosshair,
    );
  }

  Path? _path(List<VoxelVector> points, Size size) {
    var polygon = points.map(camera.transform).toList();
    polygon = _clip(polygon, .08, true);
    polygon = _clip(polygon, 20, false);
    if (polygon.length < 3) return null;
    final path = Path();
    for (var i = 0; i < polygon.length; i++) {
      final projected = camera.project(polygon[i], size);
      if (i == 0) {
        path.moveTo(projected.dx, projected.dy);
      } else {
        path.lineTo(projected.dx, projected.dy);
      }
    }
    return path..close();
  }

  List<VoxelVector> _clip(List<VoxelVector> polygon, double plane, bool near) {
    if (polygon.isEmpty) return polygon;
    final output = <VoxelVector>[];
    var previous = polygon.last;
    var previousInside = near ? previous.z >= plane : previous.z <= plane;
    for (final point in polygon) {
      final inside = near ? point.z >= plane : point.z <= plane;
      if (inside != previousInside) {
        final amount = (plane - previous.z) / (point.z - previous.z);
        output.add(previous + (point - previous) * amount);
      }
      if (inside) output.add(point);
      previous = point;
      previousInside = inside;
    }
    return output;
  }

  void _pixels(
    Canvas canvas,
    Size size,
    _VisibleFace projected,
    Paint paint,
    Color sky,
  ) {
    final face = projected.face;
    final corners = face.corners;
    final along = corners[1] - corners[0];
    final vertical = corners[3] - corners[0];
    const grid = 4;
    for (var v = 0; v < grid; v++) {
      for (var u = 0; u < grid; u++) {
        final start = corners[0] + along * (u / grid) + vertical * (v / grid);
        final path = _path([
          start,
          start + along * (1 / grid),
          start + along * (1 / grid) + vertical * (1 / grid),
          start + vertical * (1 / grid),
        ], size);
        if (path == null) continue;
        final hash =
            (face.cell.x * 37 +
                face.cell.z * 59 +
                face.cell.y * 13 +
                u * 17 +
                v * 29) %
            11;
        var color = _base(face.material, face.direction);
        if (face.material == VoxelMaterial.grass && face.direction != 2) {
          color = v == 3 ? const Color(0xFF4D943A) : const Color(0xFF806047);
        }
        if (face.material == VoxelMaterial.wood && face.direction != 2) {
          color = u.isEven ? const Color(0xFF735338) : const Color(0xFF926544);
        }
        if (face.material == VoxelMaterial.brick &&
            (v.isEven && u == ((v ~/ 2).isEven ? 1 : 0))) {
          color = const Color(0xFFC4A698);
        }
        final variation = .84 + hash * .027;
        color = color.withValues(
          red: (color.r * variation).clamp(0.0, 1.0),
          green: (color.g * variation).clamp(0.0, 1.0),
          blue: (color.b * variation).clamp(0.0, 1.0),
        );
        paint.color = _shade(color, face.direction, projected.distance, sky);
        canvas.drawPath(path, paint);
      }
    }
  }

  Color _base(VoxelMaterial material, int direction) => switch (material) {
    VoxelMaterial.grass =>
      direction == 2 ? const Color(0xFF5AA344) : const Color(0xFF846146),
    VoxelMaterial.stone => const Color(0xFF8D9297),
    VoxelMaterial.wood =>
      direction == 2 ? const Color(0xFFC89A62) : const Color(0xFF87613E),
    VoxelMaterial.leaves => const Color(0xFF427C36),
    VoxelMaterial.sand => const Color(0xFFE2CB86),
    VoxelMaterial.brick => const Color(0xFFB66450),
  };
  Color _shade(Color color, int direction, double distance, Color sky) {
    final light =
        const [.84, .65, 1.0, .48, .73, .91][direction] * (night ? .48 : 1);
    final shaded = color.withValues(
      red: color.r * light,
      green: color.g * light,
      blue: color.b * light,
    );
    return Color.lerp(shaded, sky, ((distance - 8) / 13).clamp(0.0, .87))!;
  }

  @override
  bool shouldRepaint(VoxelWorldPainter old) =>
      old.world != world ||
      old.revision != revision ||
      old.camera.eye != camera.eye ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.night != night;
}

class _VisibleFace {
  final VoxelFace face;
  final double depth;
  final double distance;
  final Path path;
  const _VisibleFace(this.face, this.depth, this.distance, this.path);
}
