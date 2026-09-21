import 'package:flutter/material.dart';

IconData iconForName(String name) =>
    {
      'restaurant': Icons.restaurant,
      'directions_car': Icons.directions_car,
      'shopping_bag': Icons.shopping_bag,
      'receipt_long': Icons.receipt_long,
      'home': Icons.home,
      'movie': Icons.movie,
      'medical_services': Icons.medical_services,
      'school': Icons.school,
      'flight': Icons.flight,
      'work': Icons.work,
      'laptop': Icons.laptop,
      'storefront': Icons.storefront,
      'trending_up': Icons.trending_up,
      'card_giftcard': Icons.card_giftcard,
      'payments': Icons.payments,
      'wallet': Icons.account_balance_wallet,
    }[name] ??
    Icons.category;
