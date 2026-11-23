import 'dart:math' as math;
import 'dart:typed_data';

enum VoxelMaterial { grass, stone, wood, leaves, sand, brick }

class VoxelVector {
  final double x;
  final double y;
  final double z;
  const VoxelVector(this.x, this.y, this.z);
  VoxelVector operator +(VoxelVector other) =>
      VoxelVector(x + other.x, y + other.y, z + other.z);
  VoxelVector operator -(VoxelVector other) =>
      VoxelVector(x - other.x, y - other.y, z - other.z);
  VoxelVector operator *(double scale) =>
      VoxelVector(x * scale, y * scale, z * scale);
  double dot(VoxelVector other) => x * other.x + y * other.y + z * other.z;
  double get length => math.sqrt(dot(this));
  VoxelVector get normalized =>
      length < 1e-9 ? const VoxelVector(0, 0, 0) : this * (1 / length);
  @override
  bool operator ==(Object other) =>
      other is VoxelVector && x == other.x && y == other.y && z == other.z;
  @override
  int get hashCode => Object.hash(x, y, z);
}

class BlockCell {
  final int x;
  final int y;
  final int z;
  const BlockCell(this.x, this.y, this.z);
  BlockCell operator +(BlockCell other) =>
      BlockCell(x + other.x, y + other.y, z + other.z);
  VoxelVector get origin =>
      VoxelVector(x.toDouble(), y.toDouble(), z.toDouble());
  @override
  bool operator ==(Object other) =>
      other is BlockCell && x == other.x && y == other.y && z == other.z;
  @override
  int get hashCode => Object.hash(x, y, z);
}

const blockNormals = [
  BlockCell(1, 0, 0),
  BlockCell(-1, 0, 0),
  BlockCell(0, 1, 0),
  BlockCell(0, -1, 0),
  BlockCell(0, 0, 1),
  BlockCell(0, 0, -1),
];

class VoxelFace {
  final BlockCell cell;
  final int direction;
  final VoxelMaterial material;
  const VoxelFace(this.cell, this.direction, this.material);
  BlockCell get normal => blockNormals[direction];
  VoxelVector get center =>
      cell.origin +
      VoxelVector(.5 + normal.x * .5, .5 + normal.y * .5, .5 + normal.z * .5);
  List<VoxelVector> get corners {
    final offsets = switch (direction) {
      0 => const [
        VoxelVector(1, 0, 0),
        VoxelVector(1, 0, 1),
        VoxelVector(1, 1, 1),
        VoxelVector(1, 1, 0),
      ],
      1 => const [
        VoxelVector(0, 0, 1),
        VoxelVector(0, 0, 0),
        VoxelVector(0, 1, 0),
        VoxelVector(0, 1, 1),
      ],
      2 => const [
        VoxelVector(0, 1, 0),
        VoxelVector(1, 1, 0),
        VoxelVector(1, 1, 1),
        VoxelVector(0, 1, 1),
      ],
      3 => const [
        VoxelVector(0, 0, 1),
        VoxelVector(1, 0, 1),
        VoxelVector(1, 0, 0),
        VoxelVector(0, 0, 0),
      ],
      4 => const [
        VoxelVector(1, 0, 1),
        VoxelVector(0, 0, 1),
        VoxelVector(0, 1, 1),
        VoxelVector(1, 1, 1),
      ],
      _ => const [
        VoxelVector(0, 0, 0),
        VoxelVector(1, 0, 0),
        VoxelVector(1, 1, 0),
        VoxelVector(0, 1, 0),
      ],
    };
    return offsets.map((offset) => cell.origin + offset).toList();
  }
}

class VoxelRayHit {
  final BlockCell cell;
  final BlockCell adjacent;
  final double distance;
  final VoxelMaterial material;
  const VoxelRayHit({
    required this.cell,
    required this.adjacent,
    required this.distance,
    required this.material,
  });
  int get faceDirection =>
      blockNormals.indexWhere((normal) => cell + normal == adjacent);
}

/// A real bounded 3D voxel volume (one byte per block), not a screen-space grid.
/// Terrain, exposed-face meshing, collision and picking all use these cells.
class VoxelWorld {
  final int width;
  final int height;
  final int depth;
  late final Uint8List _blocks = Uint8List(width * height * depth);
  int revision = 0;
  int blockCount = 0;
  int _meshRevision = -1;
  List<VoxelFace> _mesh = const [];

  VoxelWorld({
    this.width = 24,
    this.height = 16,
    this.depth = 24,
    int seed = 1337,
    bool generate = true,
  }) {
    if (width < 8 ||
        depth < 8 ||
        height < 8 ||
        width > 48 ||
        depth > 48 ||
        height > 32) {
      throw ArgumentError('Voxel world dimensions are bounded');
    }
    if (generate) _generate(seed);
  }

  bool contains(BlockCell cell) =>
      cell.x >= 0 &&
      cell.x < width &&
      cell.y >= 0 &&
      cell.y < height &&
      cell.z >= 0 &&
      cell.z < depth;
  int _index(BlockCell cell) => (cell.y * depth + cell.z) * width + cell.x;
  VoxelMaterial? materialAt(BlockCell cell) {
    if (!contains(cell)) return null;
    final value = _blocks[_index(cell)];
    return value == 0 ? null : VoxelMaterial.values[value - 1];
  }

  bool setBlock(BlockCell cell, VoxelMaterial? material) {
    if (!contains(cell)) return false;
    final value = material == null ? 0 : material.index + 1;
    final old = _blocks[_index(cell)];
    if (old == value) return false;
    _blocks[_index(cell)] = value;
    if (old == 0) blockCount++;
    if (value == 0) blockCount--;
    revision++;
    return true;
  }

  void _generate(int seed) {
    final random = math.Random(seed);
    for (var z = 0; z < depth; z++) {
      for (var x = 0; x < width; x++) {
        final top = (3 + math.sin(x * .28 + seed % 17) + math.cos(z * .31) * .8)
            .floor()
            .clamp(1, 5);
        for (var y = 0; y <= top; y++) {
          setBlock(
            BlockCell(x, y, z),
            y == top
                ? (x < 3 ? VoxelMaterial.sand : VoxelMaterial.grass)
                : VoxelMaterial.stone,
          );
        }
      }
    }
    for (var tree = 0; tree < 7; tree++) {
      final x = 3 + random.nextInt(width - 6);
      final z = 7 + random.nextInt(depth - 7);
      final base = surfaceY(x, z);
      if (base > height - 6) continue;
      for (var y = base; y < base + 4; y++) {
        setBlock(BlockCell(x, y, z), VoxelMaterial.wood);
      }
      for (var dz = -2; dz <= 2; dz++) {
        for (var dx = -2; dx <= 2; dx++) {
          for (var dy = 2; dy <= 4; dy++) {
            if (dx.abs() + dz.abs() + (dy - 3).abs() > 3 ||
                (dx == 0 && dz == 0 && dy < 4)) {
              continue;
            }
            final cell = BlockCell(x + dx, base + dy, z + dz);
            if (materialAt(cell) == null) setBlock(cell, VoxelMaterial.leaves);
          }
        }
      }
    }
  }

  int surfaceY(int x, int z) {
    for (var y = height - 1; y >= 0; y--) {
      if (materialAt(BlockCell(x, y, z)) != null) return y + 1;
    }
    return 0;
  }

  List<VoxelFace> get exposedFaces {
    if (_meshRevision == revision) return _mesh;
    final faces = <VoxelFace>[];
    for (var y = 0; y < height; y++) {
      for (var z = 0; z < depth; z++) {
        for (var x = 0; x < width; x++) {
          final cell = BlockCell(x, y, z);
          final material = materialAt(cell);
          if (material == null) continue;
          for (var direction = 0; direction < 6; direction++) {
            if (materialAt(cell + blockNormals[direction]) == null) {
              faces.add(VoxelFace(cell, direction, material));
            }
          }
        }
      }
    }
    _mesh = List.unmodifiable(faces);
    _meshRevision = revision;
    return _mesh;
  }

  /// Amanatides/Woo traversal selects the actual cube and its outward face.
  VoxelRayHit? raycast(
    VoxelVector origin,
    VoxelVector ray, {
    double reach = 6,
  }) {
    if (!origin.x.isFinite ||
        !origin.y.isFinite ||
        !origin.z.isFinite ||
        !ray.length.isFinite ||
        ray.length < 1e-9 ||
        !reach.isFinite ||
        reach <= 0) {
      return null;
    }
    final direction = ray.normalized;
    var cell = BlockCell(origin.x.floor(), origin.y.floor(), origin.z.floor());
    var previous = cell;
    final sx = direction.x.sign.toInt();
    final sy = direction.y.sign.toInt();
    final sz = direction.z.sign.toInt();
    final dx = direction.x == 0 ? double.infinity : (1 / direction.x).abs();
    final dy = direction.y == 0 ? double.infinity : (1 / direction.y).abs();
    final dz = direction.z == 0 ? double.infinity : (1 / direction.z).abs();
    double boundary(double p, int c, double d, int step) =>
        d == 0 ? double.infinity : ((step > 0 ? c + 1 : c) - p) / d;
    var tx = boundary(origin.x, cell.x, direction.x, sx);
    var ty = boundary(origin.y, cell.y, direction.y, sy);
    var tz = boundary(origin.z, cell.z, direction.z, sz);
    var distance = 0.0;
    for (var iteration = 0; iteration < 192 && distance <= reach; iteration++) {
      final material = materialAt(cell);
      if (material != null) {
        return VoxelRayHit(
          cell: cell,
          adjacent: previous,
          distance: distance,
          material: material,
        );
      }
      previous = cell;
      if (tx <= ty && tx <= tz) {
        cell = BlockCell(cell.x + sx, cell.y, cell.z);
        distance = tx;
        tx += dx;
      } else if (ty <= tz) {
        cell = BlockCell(cell.x, cell.y + sy, cell.z);
        distance = ty;
        ty += dy;
      } else {
        cell = BlockCell(cell.x, cell.y, cell.z + sz);
        distance = tz;
        tz += dz;
      }
    }
    return null;
  }
}

class VoxelPlayer {
  static const radius = .28;
  static const height = 1.8;
  static const eyeHeight = 1.62;
  VoxelVector position;
  double yaw;
  double pitch;
  double verticalVelocity = 0;

  VoxelPlayer({required this.position, this.yaw = .25, this.pitch = -.32});
  VoxelVector get eye => position + const VoxelVector(0, eyeHeight, 0);
  VoxelVector get forward => VoxelVector(
    math.sin(yaw) * math.cos(pitch),
    math.sin(pitch),
    math.cos(yaw) * math.cos(pitch),
  );
  VoxelVector get right => VoxelVector(math.cos(yaw), 0, -math.sin(yaw));
  VoxelVector get up => VoxelVector(
    -math.sin(yaw) * math.sin(pitch),
    math.cos(pitch),
    -math.cos(yaw) * math.sin(pitch),
  );

  bool overlaps(BlockCell cell) =>
      position.x + radius > cell.x &&
      position.x - radius < cell.x + 1 &&
      position.z + radius > cell.z &&
      position.z - radius < cell.z + 1 &&
      position.y + height > cell.y &&
      position.y < cell.y + 1;

  bool canOccupy(VoxelWorld world, VoxelVector feet) {
    if (!feet.x.isFinite || !feet.y.isFinite || !feet.z.isFinite) return false;
    if (feet.x - radius < 0 ||
        feet.x + radius > world.width ||
        feet.z - radius < 0 ||
        feet.z + radius > world.depth ||
        feet.y < 0 ||
        feet.y + height > world.height) {
      return false;
    }
    for (var y = feet.y.floor(); y <= (feet.y + height - 1e-6).floor(); y++) {
      for (
        var z = (feet.z - radius).floor();
        z <= (feet.z + radius - 1e-6).floor();
        z++
      ) {
        for (
          var x = (feet.x - radius).floor();
          x <= (feet.x + radius - 1e-6).floor();
          x++
        ) {
          if (world.materialAt(BlockCell(x, y, z)) != null) return false;
        }
      }
    }
    return true;
  }

  bool grounded(VoxelWorld world) =>
      !canOccupy(world, position - const VoxelVector(0, .055, 0));
  bool jump(VoxelWorld world) {
    if (verticalVelocity > 0 || !grounded(world)) return false;
    verticalVelocity = 7;
    return true;
  }

  void look(double horizontal, double vertical) {
    yaw = (yaw + horizontal) % (math.pi * 2);
    pitch = (pitch + vertical).clamp(-1.35, 1.35);
  }

  void step(
    VoxelWorld world,
    double seconds, {
    double forwardInput = 0,
    double strafeInput = 0,
  }) {
    if (!seconds.isFinite ||
        seconds <= 0 ||
        !forwardInput.isFinite ||
        !strafeInput.isFinite) {
      return;
    }
    final dt = seconds.clamp(0.0, .05);
    final magnitude = math.max(
      1.0,
      math.sqrt(forwardInput * forwardInput + strafeInput * strafeInput),
    );
    final movement =
        VoxelVector(
          math.sin(yaw) * forwardInput + math.cos(yaw) * strafeInput,
          0,
          math.cos(yaw) * forwardInput - math.sin(yaw) * strafeInput,
        ) *
        (4.2 * dt / magnitude);
    _move(world, VoxelVector(movement.x, 0, 0));
    _move(world, VoxelVector(0, 0, movement.z));
    verticalVelocity = math.max(-20, verticalVelocity - 18 * dt);
    if (!_move(world, VoxelVector(0, verticalVelocity * dt, 0))) {
      verticalVelocity = 0;
    }
  }

  bool _move(VoxelWorld world, VoxelVector delta) {
    final pieces = math.max(1, (delta.length / .08).ceil());
    final piece = delta * (1 / pieces);
    for (var i = 0; i < pieces; i++) {
      final next = position + piece;
      if (!canOccupy(world, next)) return false;
      position = next;
    }
    return true;
  }
}

class VoxelSandbox {
  final VoxelWorld world;
  final VoxelPlayer player;
  VoxelMaterial material = VoxelMaterial.grass;
  bool night = false;
  factory VoxelSandbox({VoxelWorld? world, VoxelPlayer? player}) {
    final volume = world ?? VoxelWorld();
    return VoxelSandbox._(volume, player ?? _spawn(volume));
  }
  VoxelSandbox._(this.world, this.player);
  static VoxelPlayer _spawn(VoxelWorld world) {
    final x = world.width ~/ 2;
    const z = 4;
    return VoxelPlayer(
      position: VoxelVector(x + .5, world.surfaceY(x, z).toDouble(), z + .5),
    );
  }

  VoxelRayHit? get target => world.raycast(player.eye, player.forward);
  bool removeTarget() {
    final hit = target;
    if (hit == null || hit.cell.y == 0) return false;
    return world.setBlock(hit.cell, null);
  }

  bool placeTarget() {
    final hit = target;
    if (hit == null ||
        !world.contains(hit.adjacent) ||
        world.materialAt(hit.adjacent) != null ||
        player.overlaps(hit.adjacent)) {
      return false;
    }
    return world.setBlock(hit.adjacent, material);
  }
}
