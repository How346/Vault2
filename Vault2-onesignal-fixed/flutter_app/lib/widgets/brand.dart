import 'package:flutter/material.dart';

/// Brand palette used by the logo mark and premium surfaces.
class BrandColors {
  static const ink = Color(0xFF1F2E45);
  static const inkDeep = Color(0xFF16223A);
  static const blue = Color(0xFF2F6FE4);
  static const blueLight = Color(0xFF3D95F5);
}

/// The app logo (wallet mark) rendered from the bundled asset with an
/// optional soft "premium" plate behind it.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88, this.plated = true});

  final double size;
  final bool plated;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/logo.png',
      width: size * (plated ? 0.62 : 1),
      height: size * (plated ? 0.62 : 1),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.account_balance_wallet_rounded,
        size: size * 0.55,
        color: BrandColors.blue,
      ),
    );
    if (!plated) return image;

    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F8FF), Color(0xFFDCE8FB)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: BrandColors.blue.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: image,
    );
  }
}

/// Wordmark used in the lock screen and settings footer.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.fontSize = 30});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Wallet',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Real-world identity of a document category: authority colours, an emblem
/// glyph and the short code printed on the actual card.
class CategoryBrand {
  const CategoryBrand({
    required this.code,
    required this.authority,
    required this.icon,
    required this.start,
    required this.end,
  });

  final String code;
  final String authority;
  final IconData icon;
  final Color start;
  final Color end;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      );

  static const _map = <String, CategoryBrand>{
    'aadhaar': CategoryBrand(
      code: 'UIDAI',
      authority: 'Unique Identification Authority',
      icon: Icons.fingerprint_rounded,
      start: Color(0xFFE05A2B),
      end: Color(0xFFB8341C),
    ),
    'pan': CategoryBrand(
      code: 'PAN',
      authority: 'Income Tax Department',
      icon: Icons.credit_card_rounded,
      start: Color(0xFF2F6FE4),
      end: Color(0xFF16408F),
    ),
    'dl': CategoryBrand(
      code: 'DL',
      authority: 'Regional Transport Office',
      icon: Icons.directions_car_filled_rounded,
      start: Color(0xFFF08C00),
      end: Color(0xFFC25E00),
    ),
    'rc': CategoryBrand(
      code: 'RC',
      authority: 'Vehicle Registration',
      icon: Icons.two_wheeler_rounded,
      start: Color(0xFF7A45D6),
      end: Color(0xFF4B2296),
    ),
    'passport': CategoryBrand(
      code: 'PASSPORT',
      authority: 'Ministry of External Affairs',
      icon: Icons.flight_takeoff_rounded,
      start: Color(0xFF1F6E5A),
      end: Color(0xFF0C3F33),
    ),
    'marksheet': CategoryBrand(
      code: 'EDU',
      authority: 'Board / University',
      icon: Icons.school_rounded,
      start: Color(0xFF0091A7),
      end: Color(0xFF00636F),
    ),
    'insurance': CategoryBrand(
      code: 'POLICY',
      authority: 'Insurer',
      icon: Icons.health_and_safety_rounded,
      start: Color(0xFF4E4AC8),
      end: Color(0xFF2A278A),
    ),
    'other': CategoryBrand(
      code: 'DOC',
      authority: 'Personal document',
      icon: Icons.folder_copy_rounded,
      start: Color(0xFF546274),
      end: Color(0xFF32404F),
    ),
  };

  static CategoryBrand of(String categoryId, {int? fallbackColor}) {
    final hit = _map[categoryId];
    if (hit != null) return hit;
    final base = Color(fallbackColor ?? 0xFF0F766E);
    return CategoryBrand(
      code: 'DOC',
      authority: 'Custom category',
      icon: Icons.folder_rounded,
      start: base,
      end: Color.lerp(base, Colors.black, 0.35)!,
    );
  }
}

/// Square emblem tile with the authority glyph over a branded gradient.
class CategoryEmblem extends StatelessWidget {
  const CategoryEmblem({
    super.key,
    required this.categoryId,
    this.fallbackColor,
    this.size = 48,
    this.showCode = false,
  });

  final String categoryId;
  final int? fallbackColor;
  final double size;
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    final brand = CategoryBrand.of(categoryId, fallbackColor: fallbackColor);
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: brand.gradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: brand.end.withValues(alpha: 0.32),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -size * 0.18,
            bottom: -size * 0.18,
            child: Icon(
              brand.icon,
              size: size * 0.78,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Icon(brand.icon, size: size * 0.44, color: Colors.white),
          if (showCode)
            Positioned(
              bottom: size * 0.08,
              child: Text(
                brand.code,
                style: TextStyle(
                  fontSize: size * 0.14,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
