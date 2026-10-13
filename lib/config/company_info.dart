class CompanyInfo {
  static const String appNameAr = 'Smart Vision';
  static const String appNameEn = 'Smart Vision';

  static const String companyNameAr = 'Smart Vision';
  static const String companyNameEn = 'Smart Vision';

  static const String supportEmail = 'support@example.com';
  static const String supportPhone = '+966500000000';
  static const String websiteUrl = 'https://example.com';

  static String aboutAr() {
    return '''
$appNameAr هو نظام لإدارة الموارد البشرية يساعد الموظفين والإدارة على تنفيذ الإجراءات اليومية بسرعة ووضوح.

نلتزم بتقديم تجربة استخدام مستقرة وآمنة، مع التركيز على سهولة الوصول، وتوحيد الهوية البصرية، ودعم اللغة العربية بشكل كامل.
''';
  }

  static String aboutEn() {
    return '''
$appNameEn is a Human Resources management system that helps employees and administrators handle daily operations quickly and clearly.

We focus on a stable and secure user experience, consistent branding, and full Arabic (RTL) support.
''';
  }

  static String privacyPolicyAr() {
    return '''
نحن نحترم خصوصيتك ونلتزم بحماية بياناتك.

قد نقوم بجمع بيانات ضرورية لتشغيل التطبيق مثل بيانات الحساب والطلبات والملفات المرفوعة ومعلومات الجهاز لأغراض الأمان وتحسين الخدمة.

لا نقوم ببيع بياناتك لطرف ثالث. قد تتم مشاركة البيانات فقط عند وجود متطلبات قانونية أو لتقديم الخدمة (مثل مزودي الاستضافة) وفق ضوابط أمنية.

يمكنك التواصل معنا لأي استفسار متعلق بالخصوصية عبر البريد: $supportEmail
''';
  }

  static String privacyPolicyEn() {
    return '''
We respect your privacy and are committed to protecting your data.

We may collect data required to operate the app, such as account information, requests, uploaded files, and device information for security and service improvement.

We do not sell your data. Data may be shared only when required by law or to provide the service (e.g., hosting providers) under appropriate safeguards.

For privacy inquiries, contact us at: $supportEmail
''';
  }

  static String termsAr() {
    return '''
باستخدامك للتطبيق، أنت توافق على الالتزام بالشروط التالية:

1) استخدام التطبيق للأغراض المصرح بها داخل منشأتك فقط.
2) الحفاظ على سرية بيانات الدخول وعدم مشاركتها.
3) عدم محاولة إساءة استخدام الخدمات أو تعطيلها.

قد نقوم بتحديث هذه الشروط عند الحاجة. استمرار استخدامك للتطبيق يعني موافقتك على التحديثات.
''';
  }

  static String termsEn() {
    return '''
By using the app, you agree to the following terms:

1) Use the app only for authorized purposes within your organization.
2) Keep your login information confidential and do not share it.
3) Do not attempt to misuse or disrupt the service.

We may update these terms as needed. Continued use of the app means you accept the updates.
''';
  }
}

