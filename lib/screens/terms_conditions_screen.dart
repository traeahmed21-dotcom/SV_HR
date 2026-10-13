import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/company_info.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageService = context.watch<LanguageService>();
    final isRTL = languageService.isArabic;
    final lang = languageService.currentLocale.languageCode;

    final title = Translations.getText('terms_conditions', lang);
    final body = isRTL ? CompanyInfo.termsAr() : CompanyInfo.termsEn();

    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CustomCard(
              padding: const EdgeInsets.all(18),
              child: Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

