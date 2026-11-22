import 'dart:io';

import 'package:flutter/widgets.dart';

/// Неподвижный пользовательский фон. `cover` заполняет любое окно без полос;
/// лишние края мягко кадрируются при изменении пропорций окна.
class ImageBackground extends StatelessWidget {
  final String filePath;
  const ImageBackground({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) => Image.file(
    File(filePath),
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
