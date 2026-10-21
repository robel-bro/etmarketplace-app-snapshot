import 'package:flutter/cupertino.dart';

class EtCupertinoLocalizations extends DefaultCupertinoLocalizations {
  const EtCupertinoLocalizations() : super();

  static const _supportedLocales = ['en', 'am', 'om', 'ti'];

  static Future<CupertinoLocalizations> load(Locale locale) async {
    return DefaultCupertinoLocalizations();
  }

  static bool isSupported(Locale locale) =>
      _supportedLocales.contains(locale.languageCode);
}