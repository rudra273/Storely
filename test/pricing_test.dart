import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';

void main() {
  group('PricingCalculator', () {
    test('calculates non-GST-registered price with purchase GST in cost', () {
      final result = PricingCalculator.resolveProductPrice(
        Product(name: 'Cement', mrp: 0, purchasePrice: 100, quantity: 1),
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          defaultOverheadCost: 20,
          defaultProfitMarginPercent: 50,
          gstRegistered: false,
        ),
        null,
      );

      expect(result.gstRegistered, isFalse);
      expect(result.purchasePrice, 100);
      expect(result.gstAmount, 18);
      expect(result.landedCost, 118);
      expect(result.totalCost, 138);
      expect(result.profitAmount, 69);
      expect(result.preGstSellingPrice, 207);
      expect(result.sellingPrice, 207);
      expect(result.wasDirectPrice, isFalse);
      expect(result.priceSource, 'Formula');
    });

    test('calculates GST-registered price with GST added after margin', () {
      final result = PricingCalculator.resolveProductPrice(
        Product(name: 'Cement', mrp: 0, purchasePrice: 100, quantity: 1),
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          defaultOverheadCost: 20,
          defaultProfitMarginPercent: 50,
          gstRegistered: true,
        ),
        null,
      );

      expect(result.gstRegistered, isTrue);
      expect(result.purchasePrice, 100);
      expect(result.landedCost, 100);
      expect(result.totalCost, 120);
      expect(result.profitAmount, 60);
      expect(result.preGstSellingPrice, 180);
      expect(result.gstAmount, closeTo(32.4, 0.0001));
      expect(result.sellingPrice, closeTo(212.4, 0.0001));
      expect(result.wasDirectPrice, isFalse);
    });

    test('product overrides category and global GST, overhead, and margin', () {
      final result = PricingCalculator.resolveProductPrice(
        Product(
          name: 'Tile',
          mrp: 0,
          purchasePrice: 200,
          gstPercent: 5,
          overheadCost: 10,
          profitMarginPercent: 25,
          quantity: 1,
        ),
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          defaultOverheadCost: 50,
          defaultProfitMarginPercent: 100,
          gstRegistered: false,
        ),
        const CategoryPricingSettings(
          name: 'Flooring',
          gstPercent: 12,
          overheadCost: 30,
          profitMarginPercent: 40,
        ),
      );

      expect(result.gstPercent, 5);
      expect(result.overheadCost, 10);
      expect(result.profitMarginPercent, 25);
      expect(result.landedCost, 210);
      expect(result.totalCost, 220);
      expect(result.profitAmount, 55);
      expect(result.sellingPrice, 275);
    });

    test(
      'category overrides global defaults when product has no overrides',
      () {
        final result = PricingCalculator.resolveProductPrice(
          Product(name: 'Pipe', mrp: 0, purchasePrice: 100, quantity: 1),
          const GlobalPricingSettings(
            defaultGstPercent: 18,
            defaultOverheadCost: 20,
            defaultProfitMarginPercent: 50,
            gstRegistered: false,
          ),
          const CategoryPricingSettings(
            name: 'Plumbing',
            gstPercent: 12,
            overheadCost: 8,
            profitMarginPercent: 25,
          ),
        );

        expect(result.gstPercent, 12);
        expect(result.overheadCost, 8);
        expect(result.profitMarginPercent, 25);
        expect(result.landedCost, 112);
        expect(result.totalCost, 120);
        expect(result.profitAmount, 30);
        expect(result.sellingPrice, 150);
      },
    );

    test(
      'direct price for non-GST shop reverse-calculates margin from selling price',
      () {
        final result = PricingCalculator.resolveProductPrice(
          Product(
            name: 'Paint',
            mrp: 200,
            purchasePrice: 100,
            directPriceToggle: true,
            manualPrice: 200,
            quantity: 1,
          ),
          const GlobalPricingSettings(
            defaultGstPercent: 18,
            defaultOverheadCost: 20,
            defaultProfitMarginPercent: 50,
            gstRegistered: false,
          ),
          null,
        );

        expect(result.wasDirectPrice, isTrue);
        expect(result.sellingPrice, 200);
        expect(result.totalCost, 138);
        expect(result.profitAmount, 62);
        expect(result.profitMarginPercent, closeTo(44.9275, 0.0001));
        expect(result.gstAmount, 18);
      },
    );

    test('direct price for GST shop treats manual price as GST-inclusive', () {
      final result = PricingCalculator.resolveProductPrice(
        Product(
          name: 'Paint',
          mrp: 212.4,
          purchasePrice: 100,
          directPriceToggle: true,
          manualPrice: 212.4,
          quantity: 1,
        ),
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          defaultOverheadCost: 20,
          defaultProfitMarginPercent: 10,
          gstRegistered: true,
        ),
        null,
      );

      expect(result.wasDirectPrice, isTrue);
      expect(result.sellingPrice, closeTo(212.4, 0.0001));
      expect(result.preGstSellingPrice, closeTo(180, 0.0001));
      expect(result.gstAmount, closeTo(32.4, 0.0001));
      expect(result.totalCost, 120);
      expect(result.profitAmount, closeTo(60, 0.0001));
      expect(result.profitMarginPercent, closeTo(50, 0.0001));
    });

    test('category direct price toggle is ignored', () {
      final result = PricingCalculator.resolveProductPrice(
        Product(
          name: 'Sand',
          mrp: 0,
          purchasePrice: 100,
          directPriceToggle: false,
          quantity: 1,
        ),
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          defaultOverheadCost: 20,
          defaultProfitMarginPercent: 50,
          gstRegistered: false,
        ),
        const CategoryPricingSettings(
          name: 'Building',
          directPriceToggle: true,
          manualPrice: 999,
        ),
      );

      expect(result.wasDirectPrice, isFalse);
      expect(result.priceSource, 'Formula');
      expect(result.sellingPrice, 207);
    });

    test('zero cost direct price does not produce invalid margin', () {
      final result = PricingCalculator.resolveProductPrice(
        Product(
          name: 'Free sample',
          mrp: 25,
          purchasePrice: 0,
          directPriceToggle: true,
          manualPrice: 25,
          quantity: 1,
        ),
        const GlobalPricingSettings(gstRegistered: false),
        null,
      );

      expect(result.totalCost, 0);
      expect(result.profitAmount, 25);
      expect(result.profitMarginPercent, 0);
      expect(result.sellingPrice, 25);
    });
  });
}
