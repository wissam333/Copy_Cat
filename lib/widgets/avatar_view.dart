// A shop character in 3D. The camera sits in front of the glTF (models face
// -Z after import) and frames the standing body, with air above the head.
// The model stays still. A horizontal drag turns it with the finger:
// swipe right, the face goes right.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../services/shop_catalog.dart';

class AvatarView extends StatefulWidget {
  final String avatarId;

  /// Width of the portrait. Ignored when [expand] is true.
  final double size;

  /// Portrait height. Defaults to a tall frame so the head is not clipped.
  final double? height;

  /// Fill a bounded parent (shop grid cells).
  final bool expand;

  /// Drag to turn. The character follows the finger.
  final bool interactive;

  /// Which animation clip loops (Idle default, Victory on celebrations…).
  /// Must be one of the kept clips: Idle, Victory, Jump, RecieveHit,
  /// Defeat, Death.
  final String celebration;

  /// Uniform model scale. Camera stays exactly where framing put it; the
  /// character just fills more of the frame. Uniform only (lighting-safe).
  final double modelScale;

  /// Grid thumbnails: cheaper frames.
  final bool lightweight;

  final double? maxFrameRate;

  const AvatarView({
    super.key,
    required this.avatarId,
    this.size = 120,
    this.height,
    this.expand = false,
    this.interactive = false,
    this.lightweight = false,
    this.maxFrameRate,
    this.celebration = 'Idle',
    this.modelScale = 1.0,
  });

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  Scene? _scene;
  Node? _model;
  AnimationClip? _clip;
  vm.Aabb3? _bounds;
  bool _ready = false;
  // Old phones (no Vulkan/GPU) cannot render 3D: show the paw badge
  // instead of a red error screen.
  bool _failed = false;
  int _generation = 0;
  double _aspect = 0.75;

  /// Widget tests run without a GPU; flutter_scene cannot init there.
  /// Render the same footprint as an empty box so layout tests stay honest.
  static bool get _noGpu =>
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Yaw of the model. 0 shows the face. Positive turns the face to screen left.
  double _yaw = 0;

  /// Camera elevation. Small and positive: we look slightly down at the face.
  double _pitch = _restPitch;

  static const double _fov = 34 * math.pi / 180;
  static const double _restPitch = 0.08;

  @override
  void initState() {
    super.initState();
    if (_noGpu) return; // No Scene, no load: footprint only.
    _scene ??= Scene();
    if (widget.lightweight) {
      _scene!.renderQuality.tier = RenderQualityTier.low;
      _scene!.renderQuality.adaptive = true;
      _scene!.renderQuality.targetFrameRate = 24;
    }
    // Light travels from the camera side (+Z component) so the face is lit.
    _scene!.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.15, -0.85, 0.55),
      intensity: 3.2,
    );
    _scene!.exposure = 1.08;
    _load();
  }

  @override
  void didUpdateWidget(covariant AvatarView old) {
    super.didUpdateWidget(old);
    if (old.avatarId != widget.avatarId) {
      _load();
      return;
    }
    if (old.celebration != widget.celebration && _model != null) {
      _playClip(_model!, widget.celebration);
    }
    if (old.modelScale != widget.modelScale && _model != null) {
      _model!.scale = vm.Vector3.all(widget.modelScale);
    }
  }

  @override
  void dispose() {
    _generation++;
    _model?.detach();
    _model = null;
    super.dispose();
  }

  Future<void> _load() async {
    final ticket = ++_generation;
    final asset = ShopCatalog.byId(widget.avatarId).asset;
    if (mounted) setState(() => _ready = false);
    try {
      await Scene.initializeStaticResources();
      final model = await loadScene(asset);
      if (!mounted || ticket != _generation) {
        model.detach();
        return;
      }
      _model?.detach();
      _scene?.add(model);
      _model = model;
      _yaw = 0;
      _pitch = _restPitch;
      _bounds = _frameBox(model);
      // Scale AFTER framing: bounds (and therefore the camera) are from
      // the unscaled body, so the character grows in a fixed frame.
      model.scale = vm.Vector3.all(widget.modelScale);
      _playClip(model, widget.celebration);
      _applyYaw();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted && ticket == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  void _playClip(Node model, String name) {
    try {
      _clip?.stop();
    } catch (_) {}
    _clip = null;
    var anim = model.findAnimationByName(name);
    anim ??= model.findAnimationByName('Idle');
    if (anim == null) return;
    final playing = model.createAnimationClip(anim);
    playing.loop = true;
    playing.play();
    _clip = playing;
  }

  void _applyYaw() {
    _model?.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _yaw);
  }

  /// Standing-body box. Skinned rigs often report a T-pose or a jump arc;
  /// those boxes either crop the head or shrink the body to a speck.
  vm.Aabb3 _frameBox(Node model) {
    final raw = model.combinedWorldBounds ?? _meshBounds(model);
    if (raw == null) {
      return vm.Aabb3.minMax(
        vm.Vector3(-0.95, -0.08, -0.55),
        vm.Vector3(0.95, 3.55, 0.55),
      );
    }
    var minX = raw.min.x;
    var maxX = raw.max.x;
    var minY = raw.min.y;
    var maxY = raw.max.y;
    final minZ = raw.min.z;
    final maxZ = raw.max.z;
    final height = maxY - minY;
    final width = maxX - minX;
    final depth = math.max(maxZ - minZ, 0.05);
    // Jump and roll poses blow the box out. These rigs stand between the
    // floor and about 3.2, so frame that window instead of the arc.
    if (height > 4.8 || width > 5) {
      return vm.Aabb3.minMax(
        vm.Vector3(-0.95, -0.1, -0.6),
        vm.Vector3(0.95, 3.65, 0.6),
      );
    }
    // Arms-out bind pose: wide and flat. Frame the body, not the fingertips,
    // so the idle pose fills the portrait instead of floating in it.
    if (width > 2.2 && depth < 1.35 && height > 1.5) {
      final cx = (minX + maxX) * 0.5;
      minX = cx - 0.95;
      maxX = cx + 0.95;
    }
    final body = math.max(maxY - minY, 0.5);
    return vm.Aabb3.minMax(
      vm.Vector3(minX, minY - body * 0.05, minZ),
      vm.Vector3(maxX, maxY + body * 0.12, maxZ),
    );
  }

  vm.Aabb3? _meshBounds(Node model) {
    vm.Aabb3? box;
    for (final node in model.meshNodes) {
      final local = node.mesh?.localBounds;
      if (local == null) continue;
      final placed = vm.Aabb3.copy(local)..transform(node.globalTransform);
      if (box == null) {
        box = placed;
      } else {
        box.hull(placed);
      }
    }
    return box;
  }

  vm.Vector3 get _target {
    final box = _bounds;
    if (box == null) return vm.Vector3(0, 1.65, 0);
    return box.center;
  }

  double _distance() {
    final box = _bounds;
    if (box == null) return 7;
    final halfH = math.max(box.max.y - box.min.y, 0.3) * 0.5;
    final halfW = math.max(box.max.x - box.min.x, 0.3) * 0.5;
    final depth = math.max(box.max.z - box.min.z, 0.2);
    final halfFov = _fov / 2;
    final distV = halfH / math.tan(halfFov);
    final aspect = _aspect.clamp(0.4, 2.2);
    final halfHFov = math.atan(math.tan(halfFov) * aspect);
    final distH = halfW / math.max(math.tan(halfHFov), 1e-3);
    return math.max(distV, distH) * 1.16 + depth * 0.2;
  }

  PerspectiveCamera _camera() {
    final dist = _distance();
    final target = _target;
    final cp = math.cos(_pitch);
    final sp = math.sin(_pitch);
    // Eye on -Z: that is the face, matching PerspectiveCamera's default.
    return PerspectiveCamera(
      fovRadiansY: _fov,
      target: target,
      position: target + vm.Vector3(0, dist * sp, -dist * cp),
      fovNear: math.max(0.04, dist * 0.01),
      fovFar: dist * 6 + 10,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_noGpu) {
      // Same box the real view would take, minus the GPU.
      if (widget.expand) return const SizedBox.expand();
      return Center(
        child: SizedBox(
          width: widget.size,
          height: widget.height ?? widget.size * 1.4,
        ),
      );
    }
    if (_failed) return const _PawFallback();
    final view = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w.isFinite && h.isFinite && h > 1) {
          _aspect = w / h;
        }
        if (_ready) _applyYaw();
        if (!_ready) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: widget.interactive
              ? (d) {
                  setState(() {
                    // Screen right is +X with this camera. A negative yaw
                    // sends the face (local -Z) toward +X. Vertical drags
                    // stay with the shop scroll.
                    _yaw -= d.delta.dx * 0.012;
                  });
                }
              : null,
          child: SceneView(
            _scene!,
            camera: _camera(),
            maxFrameRate: widget.maxFrameRate,
          ),
        );
      },
    );
    if (widget.expand) return view;
    return Center(
      child: SizedBox(
        width: widget.size,
        height: widget.height ?? widget.size * 1.4,
        child: view,
      ),
    );
  }
}
/// Static badge shown when this phone cannot render 3D (old GPU).
class _PawFallback extends StatelessWidget {
  const _PawFallback();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.pets,
            size: 40, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// Cache version: bump when the models change so stale thumbs rebake.
const _thumbCacheVersion = 2;

Future<File> _thumbFile(String avatarId) async {
  final dir = await getTemporaryDirectory();
  final thumbs =
      Directory("${dir.path}/avatar_thumbs_v$_thumbCacheVersion");
  if (!await thumbs.exists()) {
    await thumbs.create(recursive: true);
  }
  return File("${thumbs.path}/$avatarId.png");
}

/// A shop-grid thumbnail: baked PNG when cached, one live render to bake
/// it otherwise. Steady state costs zero GPU views; a failed bake simply
/// keeps the cheap live view.
class BakedAvatar extends StatefulWidget {
  final String avatarId;
  const BakedAvatar({super.key, required this.avatarId});

  @override
  State<BakedAvatar> createState() => _BakedAvatarState();
}

class _BakedAvatarState extends State<BakedAvatar> {
  final _shotKey = GlobalKey();
  File? _png;
  bool _baking = false;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    try {
      final f = await _thumbFile(widget.avatarId);
      if (await f.exists() && mounted) setState(() => _png = f);
    } catch (_) {}
  }

  Future<void> _bake() async {
    if (_baking || _png != null || !mounted) return;
    _baking = true;
    // Let a few frames settle so the Idle pose is actually on screen.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    try {
      final boundary = _shotKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      final f = await _thumbFile(widget.avatarId);
      await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (mounted) setState(() => _png = f);
    } catch (_) {
      // Keep the live view; it is already cheap (low tier, 8 fps).
    }
  }

  @override
  Widget build(BuildContext context) {
    final png = _png;
    if (png != null) {
      return Image.file(png, fit: BoxFit.contain);
    }
    // First sight: live view, and schedule one bake from it.
    Future.microtask(_bake);
    return RepaintBoundary(
      key: _shotKey,
      child: AvatarView(
        avatarId: widget.avatarId,
        expand: true,
        lightweight: true,
        maxFrameRate: 8,
      ),
    );
  }
}
