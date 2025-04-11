import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class BarcodeApiService {
  final String _baseUrl = 'https://world.openfoodfacts.org/api/v2/product/';

  Future<String> getProductInfo(String barcode) async {
    if (barcode.isEmpty) {
      return "Invalid barcode";
    }
    final url = Uri.parse('$_baseUrl$barcode.json?fields=product_name,brands');
    debugPrint("[BarcodeApiService] Fetching: $url");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          String productName = product['product_name'] ?? 'Unknown Product';
          String brands = product['brands'] ?? 'Unknown Brand';

          if (productName == 'Unknown Product' && brands == 'Unknown Brand') {
            debugPrint("[BarcodeApiService] Product not found for barcode: $barcode");
            return "Product not found";
          }

          String result = productName;
          if (brands != 'Unknown Brand' && brands.isNotEmpty) {
            result += " by $brands";
          }
          debugPrint("[BarcodeApiService] Found: $result for barcode: $barcode");
          return result;
        } else {
          debugPrint("[BarcodeApiService] Product not found in API response for barcode: $barcode. Status: ${data['status']}");
          return "Product not found";
        }
      } else if (response.statusCode == 404) {
           debugPrint("[BarcodeApiService] API returned 404 for barcode: $barcode");
          return "Product not found";
      }
       else {
        debugPrint("[BarcodeApiService] API Error: ${response.statusCode} for barcode: $barcode");
        return "API Error: ${response.statusCode}";
      }
    } catch (e) {
      debugPrint("[BarcodeApiService] Network or parsing error for barcode $barcode: $e");
      return "Network error";
    }
  }
}