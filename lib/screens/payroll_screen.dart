import 'package:flutter/material.dart';
import '../models/payroll.dart';
import 'package:provider/provider.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class PayrollScreen extends StatefulWidget {
  final String employeeId;

  const PayrollScreen({super.key, required this.employeeId});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    // لا نستخدم بيانات وهمية
    final payroll = null;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('payroll', lang)),
      ),
      body: Column(
        children: [
          // Month/Year Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedMonth,
                    decoration: InputDecoration(
                      labelText: Translations.getText('month', lang),
                      border: const OutlineInputBorder(),
                    ),
                    items: List.generate(12, (index) {
                      final monthKeys = [
                        'january', 'february', 'march', 'april', 'may', 'june',
                        'july', 'august', 'september', 'october', 'november', 'december'
                      ];
                      return DropdownMenuItem(
                        value: index + 1,
                        child: Text(Translations.getText(monthKeys[index], lang)),
                      );
                    }),
                    onChanged: (value) {
                      setState(() {
                        _selectedMonth = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: InputDecoration(
                      labelText: Translations.getText('year', lang),
                      border: const OutlineInputBorder(),
                    ),
                    items: List.generate(5, (index) {
                      final year = DateTime.now().year - 2 + index;
                      return DropdownMenuItem(
                        value: year,
                        child: Text(year.toString()),
                      );
                    }),
                    onChanged: (value) {
                      setState(() {
                        _selectedYear = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Payroll Details
          Expanded(
            child: payroll == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.account_balance_wallet,
                          size: 100,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          Translations.getText('no_payroll_data', lang),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildPayrollCard(payroll),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollCard(PayrollItem payroll) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: const Color(0xFF0EA5E9),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                Translations.getText('payroll_details', lang),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: payroll.isPaid
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  payroll.isPaid ? Translations.getText('paid', lang) : Translations.getText('unpaid', lang),
                  style: TextStyle(
                    fontSize: 12,
                    color: payroll.isPaid
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildPayrollRow(
              Translations.getText('basic_salary', lang), payroll.basicSalary, Icons.attach_money, lang),
          _buildPayrollRow(Translations.getText('allowances', lang), payroll.allowances, Icons.add_circle, lang),
          _buildPayrollRow(
              Translations.getText('overtime', lang), payroll.overtime, Icons.access_time, lang),
          _buildPayrollRow(Translations.getText('bonuses', lang), payroll.bonuses, Icons.star, lang),
          const Divider(),
          _buildPayrollRow(Translations.getText('deductions', lang), -payroll.deductions, Icons.remove_circle, lang,
              isNegative: true),
          const Divider(thickness: 2),
          _buildPayrollRow(
              Translations.getText('net_salary', lang), payroll.netSalary, Icons.account_balance, lang,
              isTotal: true),
          const SizedBox(height: 24),
          if (payroll.notes != null) ...[
            Text(
              '${Translations.getText('notes', lang)}:',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              payroll.notes!,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                '${Translations.getText('payment_date', lang)}: ${payroll.paymentDate.toString().substring(0, 10)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollRow(String label, double amount, IconData icon, String lang,
      {bool isNegative = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: isTotal ? const Color(0xFF0EA5E9) : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '${isNegative ? '-' : ''}${amount.toStringAsFixed(2)} ${Translations.getText('currency_sar', lang)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? const Color(0xFF0EA5E9) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
