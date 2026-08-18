import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import '../v14_models.dart';
import 'remote_stock_service.dart';

extension RemoteStockV14Extension on RemoteStockService {
  Future<Map<String, dynamic>> updateProductV14({
    required String pin,
    required Product product,
    required String employee,
    required ProductV14Meta meta,
    int? minimumAmount,
    int? targetAmount,
    int? varianceRecheckAmount,
    String? barcode,
  }) {
    return post(pin, {
      'action': 'product_meta',
      'employee': employee,
      'product_key': productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize),
      'minimum_amount': minimumAmount ?? product.minimumAmount,
      'target_amount': targetAmount ?? product.targetAmount,
      'variance_recheck_amount': varianceRecheckAmount ?? product.varianceRecheckAmount,
      'barcode': barcode ?? product.barcode,
      'sell_by_bottle': meta.sellByBottle,
      'bottle_sale_price': meta.bottleSalePrice,
      'portion_sale': meta.portionSale,
      'portion_prices': meta.portions.map((x) => x.toJson()).toList(growable: false),
      'image_path': meta.imagePath,
    });
  }

  Future<Map<String, dynamic>> updateProductsV14Batch({
    required String pin,
    required String employee,
    required List<({Product product, ProductV14Meta meta})> changes,
  }) {
    return post(pin, {
      'action': 'product_meta_batch',
      'employee': employee,
      'items': changes
          .map((change) => {
                'product_key': productKey(
                  name: change.product.name,
                  unit: change.product.stockUnit,
                  packageSize: change.product.packageSize,
                ),
                'minimum_amount': change.product.minimumAmount,
                'target_amount': change.product.targetAmount,
                'variance_recheck_amount': change.product.varianceRecheckAmount,
                'barcode': change.product.barcode,
                'sell_by_bottle': change.meta.sellByBottle,
                'bottle_sale_price': change.meta.bottleSalePrice,
                'portion_sale': change.meta.portionSale,
                'portion_prices': change.meta.portions.map((x) => x.toJson()).toList(growable: false),
                'image_path': change.meta.imagePath,
              })
          .toList(growable: false),
    });
  }

  Future<Map<String, dynamic>> uploadProductImage({
    required String pin,
    required Product product,
    required String employee,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) {
    return post(pin, {
      'action': 'product_image_upload',
      'employee': employee,
      'product_key': productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize),
      'file_name': fileName,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    });
  }

  Future<Map<String, dynamic>> spotStocktake({
    required String pin,
    required Product product,
    required String employee,
    required int quantityBase,
    required SpotStocktakeReason reason,
    required String device,
    String? comment,
    String? locationId,
  }) {
    return post(pin, {
      'action': 'spot_stocktake',
      'employee': employee,
      'product_key': productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize),
      'quantity_base': quantityBase,
      'reason': reason.label,
      'comment': comment,
      'device': device,
      'location_id': locationId,
      'metadata': const {'source': 'BALI STOCK V14'},
    });
  }
}
