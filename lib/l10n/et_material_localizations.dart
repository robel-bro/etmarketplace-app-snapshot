import 'package:flutter/material.dart';

class EtMaterialLocalizations extends DefaultMaterialLocalizations {
  const EtMaterialLocalizations() : super();

  static const _supportedLocales = ['en', 'am', 'om', 'ti'];

  static Future<MaterialLocalizations> load(Locale locale) async {
    return DefaultMaterialLocalizations();
  }

  static bool isSupported(Locale locale) =>
      _supportedLocales.contains(locale.languageCode);
}