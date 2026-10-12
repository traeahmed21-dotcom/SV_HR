import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import '../models/request.dart' as request_models;
import '../models/api_models.dart' as api_models;
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../utils/file_bytes.dart';

class CreateRequestScreen extends StatefulWidget {
  final api_models.EmployeeData employeeData;

  const CreateRequestScreen({
    super.key,
    required this.employeeData,
  });

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // نوع الطلب
  String? _selectedRequestType;
  List<api_models.RequestType> _availableRequestTypes = [];

  // بيانات السلفة
  String? _selectedLoanType;
  final _loanAmountController = TextEditingController();
  final _monthlyInstallmentController = TextEditingController();
  final _numberOfInstallmentsController = TextEditingController();
  DateTime? _loanStartDate;
  DateTime? _loanEndDate;
  final _loanDescriptionController = TextEditingController();

  // بيانات الإجازة
  request_models.LeaveType? _selectedLeaveType;
  DateTime? _leaveStartDate;
  DateTime? _leaveEndDate;
  final _leaveDaysController = TextEditingController();
  final _leaveReasonController = TextEditingController();

  // بيانات الطلب من نوع "أخرى"
  final _otherDescriptionController = TextEditingController();

  // بيانات طلب إضافة بصمة
  DateTime? _manualPunchDate;
  TimeOfDay? _manualPunchTime;
  String? _manualPunchType;
  final _manualPunchReasonController = TextEditingController();

  // بيانات طلب تأشيرة خروج وعودة
  DateTime? _exitReturnFromDate;
  DateTime? _exitReturnToDate;
  final _exitReturnReasonController = TextEditingController();
  final _exitReturnNotesController = TextEditingController();

  // بيانات طلب استئذان
  DateTime? _permissionDate;
  TimeOfDay? _permissionFromTime;
  TimeOfDay? _permissionToTime;
  final _permissionReasonController = TextEditingController();
  final _permissionNotesController = TextEditingController();

  // بيانات المرفق
  String? _attachmentFileName;
  Uint8List? _attachmentContent;
  bool _isPickingFile = false;

  // قوائم البيانات
  List<request_models.LoanType> _loanTypes = [];
  List<request_models.LeaveType> _leaveTypes = [];

  // بيانات المسار
  api_models.WorkflowData? _workflowData;
  bool _showWorkflowInfo = false;

  // حالة التحميل
  bool _isLoading = false;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _loanAmountController.dispose();
    _monthlyInstallmentController.dispose();
    _numberOfInstallmentsController.dispose();
    _loanDescriptionController.dispose();
    _leaveDaysController.dispose();
    _leaveReasonController.dispose();
    _otherDescriptionController.dispose();
    _manualPunchReasonController.dispose();
    _exitReturnReasonController.dispose();
    _exitReturnNotesController.dispose();
    _permissionReasonController.dispose();
    _permissionNotesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      print('🔍 ClientID المستخدم: ${widget.employeeData.clientID}');
      print('🔍 Employee Name: ${widget.employeeData.name}');
      print('🔍 Employee ID: ${widget.employeeData.employeeID}');

      // جلب أنواع الطلبات المتاحة (التي تحتوي على مسارات)
      final requestTypesFuture =
          ApiService.getRequestTypes(widget.employeeData.clientID);
      final loanTypesFuture =
          ApiService.getLoanTypes(widget.employeeData.clientID);
      final leaveTypesFuture =
          ApiService.getLeaveTypes(widget.employeeData.clientID);

      final results = await Future.wait(
          [requestTypesFuture, loanTypesFuture, leaveTypesFuture]);

      setState(() {
        _availableRequestTypes = results[0] as List<api_models.RequestType>;
        _loanTypes = results[1] as List<request_models.LoanType>;
        _leaveTypes = results[2] as List<request_models.LeaveType>;
        _isLoadingData = false;
      });

      print('تم تحميل ${_availableRequestTypes.length} نوع طلب متاح');
      print('تم تحميل ${_loanTypes.length} نوع سلفة');
      print('تم تحميل ${_leaveTypes.length} نوع إجازة');

      if (_availableRequestTypes.isNotEmpty) {
        print(
            'أنواع الطلبات المتاحة: ${_availableRequestTypes.map((e) => '${e.value}: ${e.text}').join(', ')}');
      }
    } catch (e) {
      print(
          '❌ فشل في تحميل البيانات مع ClientID: ${widget.employeeData.clientID}');
      print('خطأ: $e');

      // محاولة ثانية مع clientID ثابت
      try {
        print('🔄 محاولة استخدام ClientID ثابت: 30');

        final requestTypesFuture = ApiService.getRequestTypes(30);
        final loanTypesFuture = ApiService.getLoanTypes(30);
        final leaveTypesFuture = ApiService.getLeaveTypes(30);

        final results = await Future.wait(
            [requestTypesFuture, loanTypesFuture, leaveTypesFuture]);

        setState(() {
          _availableRequestTypes = results[0] as List<api_models.RequestType>;
          _loanTypes = results[1] as List<request_models.LoanType>;
          _leaveTypes = results[2] as List<request_models.LeaveType>;
          _isLoadingData = false;
        });

        print('✅ تم تحميل البيانات بنجاح باستخدام ClientID: 30');
        print('تم تحميل ${_availableRequestTypes.length} نوع طلب متاح');
        print('تم تحميل ${_loanTypes.length} نوع سلفة');
        print('تم تحميل ${_leaveTypes.length} نوع إجازة');
      } catch (secondError) {
        setState(() {
          _isLoadingData = false;
        });
        print('❌ فشل في تحميل البيانات حتى مع ClientID: 30');
        print('خطأ ثاني: $secondError');

        if (mounted) {
          _showErrorSnackBar(
              'حدث خطأ في تحميل البيانات. تأكد من الاتصال بالإنترنت وحاول مرة أخرى.');
        }
      }
    }
  }

  // جلب مسار الطلب عند اختيار نوع الطلب والموظف
  Future<void> _loadWorkflow() async {
    if (_selectedRequestType == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // تحويل نوع الطلب إلى الإنجليزية
      String requestTypeEnglish;
      switch (_selectedRequestType) {
        case 'سلفة':
        case 'Loan':
          requestTypeEnglish = 'Loan';
          break;
        case 'إجازة':
        case 'Leave':
          requestTypeEnglish = 'Leave';
          break;
        case 'أخرى':
        case 'Other':
          requestTypeEnglish = 'Other';
          break;
        case 'بصمة حضور وانصراف':
        case 'ManualPunch':
          requestTypeEnglish = 'ManualPunch';
          break;
        case 'تأشيرة خروج وعودة':
        case 'ExitReturn':
          requestTypeEnglish = 'ExitReturn';
          break;
        case 'استئذان':
        case 'Permission':
          requestTypeEnglish = 'Permission';
          break;
        default:
          return;
      }

      print('🔍 جلب المسار لنوع الطلب: $requestTypeEnglish');
      print('🔍 Employee ID: ${widget.employeeData.employeeID}');

      final workflowData = await ApiService.getWorkflow(
        widget.employeeData.clientID,
        requestTypeEnglish,
        widget.employeeData.employeeID,
      );

      setState(() {
        _workflowData = workflowData;
        _showWorkflowInfo = workflowData != null;
        _isLoading = false;
      });

      if (workflowData != null) {
        print('✅ تم جلب المسار بنجاح: ${workflowData.workflowName}');
        print('عدد الخطوات: ${workflowData.steps.length}');
      } else {
        print('❌ لم يتم العثور على مسار لهذا النوع من الطلبات');
        final languageService = Provider.of<LanguageService>(context, listen: false);
        final lang = languageService.currentLocale.languageCode;
        _showErrorSnackBar(
            Translations.getText('error_no_workflow', lang));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        print('❌ خطأ في جلب المسار: $e');
        final languageService = Provider.of<LanguageService>(context, listen: false);
        final lang = languageService.currentLocale.languageCode;
        _showErrorSnackBar('${Translations.getText('error_fetching_workflow', lang)}: $e');
      }
    }
  }

  void _onRequestTypeChanged(String? value) {
    setState(() {
      _selectedRequestType = value;
      _workflowData = null;
      _showWorkflowInfo = false;

      // إعادة تعيين البيانات عند تغيير نوع الطلب
      if (value == 'سلفة' || value == 'Loan') {
        _selectedLeaveType = null;
        _leaveStartDate = null;
        _leaveEndDate = null;
        _leaveDaysController.clear();
        _leaveReasonController.clear();
        _otherDescriptionController.clear();
        _manualPunchReasonController.clear();
        _exitReturnFromDate = null;
        _exitReturnToDate = null;
        _exitReturnReasonController.clear();
        _exitReturnNotesController.clear();
        _permissionDate = null;
        _permissionFromTime = null;
        _permissionToTime = null;
        _permissionReasonController.clear();
        _permissionNotesController.clear();
      } else if (value == 'إجازة' || value == 'Leave') {
        _selectedLoanType = null;
        _loanAmountController.clear();
        _monthlyInstallmentController.clear();
        _numberOfInstallmentsController.clear();
        _loanStartDate = null;
        _loanEndDate = null;
        _loanDescriptionController.clear();
        _otherDescriptionController.clear();
        _manualPunchReasonController.clear();
        _exitReturnFromDate = null;
        _exitReturnToDate = null;
        _exitReturnReasonController.clear();
        _exitReturnNotesController.clear();
        _permissionDate = null;
        _permissionFromTime = null;
        _permissionToTime = null;
        _permissionReasonController.clear();
        _permissionNotesController.clear();
      } else if (value == 'أخرى' || value == 'Other') {
        _selectedLoanType = null;
        _loanAmountController.clear();
        _monthlyInstallmentController.clear();
        _numberOfInstallmentsController.clear();
        _loanStartDate = null;
        _loanEndDate = null;
        _loanDescriptionController.clear();
        _selectedLeaveType = null;
        _leaveStartDate = null;
        _leaveEndDate = null;
        _leaveDaysController.clear();
        _leaveReasonController.clear();
        _manualPunchReasonController.clear();
        _exitReturnFromDate = null;
        _exitReturnToDate = null;
        _exitReturnReasonController.clear();
        _exitReturnNotesController.clear();
        _permissionDate = null;
        _permissionFromTime = null;
        _permissionToTime = null;
        _permissionReasonController.clear();
        _permissionNotesController.clear();
      } else if (value == 'بصمة حضور وانصراف' || value == 'ManualPunch') {
        _selectedLoanType = null;
        _loanAmountController.clear();
        _monthlyInstallmentController.clear();
        _numberOfInstallmentsController.clear();
        _loanStartDate = null;
        _loanEndDate = null;
        _loanDescriptionController.clear();
        _selectedLeaveType = null;
        _leaveStartDate = null;
        _leaveEndDate = null;
        _leaveDaysController.clear();
        _leaveReasonController.clear();
        _otherDescriptionController.clear();
        _manualPunchDate = null;
        _manualPunchTime = null;
        _manualPunchType = null;
        _manualPunchReasonController.clear();
        _exitReturnFromDate = null;
        _exitReturnToDate = null;
        _exitReturnReasonController.clear();
        _exitReturnNotesController.clear();
        _permissionDate = null;
        _permissionFromTime = null;
        _permissionToTime = null;
        _permissionReasonController.clear();
        _permissionNotesController.clear();
      } else if (value == 'تأشيرة خروج وعودة' || value == 'ExitReturn') {
        _selectedLoanType = null;
        _loanAmountController.clear();
        _monthlyInstallmentController.clear();
        _numberOfInstallmentsController.clear();
        _loanStartDate = null;
        _loanEndDate = null;
        _loanDescriptionController.clear();
        _selectedLeaveType = null;
        _leaveStartDate = null;
        _leaveEndDate = null;
        _leaveDaysController.clear();
        _leaveReasonController.clear();
        _otherDescriptionController.clear();
        _manualPunchDate = null;
        _manualPunchTime = null;
        _manualPunchType = null;
        _manualPunchReasonController.clear();
        _permissionDate = null;
        _permissionFromTime = null;
        _permissionToTime = null;
        _permissionReasonController.clear();
        _permissionNotesController.clear();
      } else if (value == 'استئذان' || value == 'Permission') {
        _selectedLoanType = null;
        _loanAmountController.clear();
        _monthlyInstallmentController.clear();
        _numberOfInstallmentsController.clear();
        _loanStartDate = null;
        _loanEndDate = null;
        _loanDescriptionController.clear();
        _selectedLeaveType = null;
        _leaveStartDate = null;
        _leaveEndDate = null;
        _leaveDaysController.clear();
        _leaveReasonController.clear();
        _otherDescriptionController.clear();
        _manualPunchDate = null;
        _manualPunchTime = null;
        _manualPunchType = null;
        _manualPunchReasonController.clear();
        _exitReturnFromDate = null;
        _exitReturnToDate = null;
        _exitReturnReasonController.clear();
        _exitReturnNotesController.clear();
      }

      _attachmentFileName = null;
      _attachmentContent = null;
    });

    // جلب المسار تلقائياً
    if (value != null) {
      _loadWorkflow();
    }
  }

  // حساب القسط الشهري تلقائياً
  void _calculateMonthlyInstallment() {
    if (_loanAmountController.text.isNotEmpty &&
        _numberOfInstallmentsController.text.isNotEmpty) {
      try {
        final amount = double.parse(_loanAmountController.text);
        final installments = int.parse(_numberOfInstallmentsController.text);
        if (amount > 0 && installments > 0) {
          final monthlyAmount = amount / installments;
          _monthlyInstallmentController.text = monthlyAmount.toStringAsFixed(2);
        }
      } catch (e) {
        // تجاهل الأخطاء في التحويل
      }
    }
  }

  // حساب تاريخ النهاية للسلفة
  void _calculateLoanEndDate() {
    if (_loanStartDate != null &&
        _numberOfInstallmentsController.text.isNotEmpty) {
      try {
        final installments = int.parse(_numberOfInstallmentsController.text);
        if (installments > 0) {
          final endDate = DateTime(
            _loanStartDate!.year,
            _loanStartDate!.month + installments,
            _loanStartDate!.day,
          );
          setState(() {
            _loanEndDate = endDate;
          });
        }
      } catch (e) {
        // تجاهل الأخطاء في التحويل
      }
    }
  }

  // تعيين تاريخ البداية للسلفة (بداية الشهر القادم)
  void _setLoanStartDate() {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    setState(() {
      _loanStartDate = nextMonth;
    });
    _calculateLoanEndDate();
  }

  void _calculateLeaveDays() {
    if (_leaveStartDate != null && _leaveEndDate != null) {
      final difference = _leaveEndDate!.difference(_leaveStartDate!).inDays + 1;
      if (difference > 0) {
        _leaveDaysController.text = difference.toString();
      } else {
        _leaveDaysController.clear();
      }
    }
  }

  Future<void> _selectDate(
      BuildContext context, bool isStartDate, bool isLoan) async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        locale: Locale(Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme,
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          if (isLoan) {
            if (isStartDate) {
              _loanStartDate = picked;
            } else {
              _loanEndDate = picked;
            }
          } else {
            if (isStartDate) {
              _leaveStartDate = picked;
            } else {
              _leaveEndDate = picked;
            }
            _calculateLeaveDays();
          }
        });
      }
    } catch (e) {
      print('خطأ في اختيار التاريخ: $e');
      _showErrorSnackBar('حدث خطأ في اختيار التاريخ: $e');
    }
  }

  Future<void> _selectExitReturnDate(BuildContext context, bool isFrom) async {
    try {
      final initialDate = isFrom
          ? (_exitReturnFromDate ?? DateTime.now())
          : (_exitReturnToDate ?? (_exitReturnFromDate ?? DateTime.now()));
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
        locale: Locale(
          Provider.of<LanguageService>(context, listen: false)
              .currentLocale
              .languageCode,
        ),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme,
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          if (isFrom) {
            _exitReturnFromDate = picked;
            if (_exitReturnToDate != null &&
                _exitReturnToDate!.isBefore(picked)) {
              _exitReturnToDate = null;
            }
          } else {
            _exitReturnToDate = picked;
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('حدث خطأ في اختيار التاريخ: $e');
    }
  }

  Future<void> _selectPermissionDate(BuildContext context) async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _permissionDate ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        locale: Locale(
          Provider.of<LanguageService>(context, listen: false)
              .currentLocale
              .languageCode,
        ),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme,
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          _permissionDate = picked;
        });
      }
    } catch (e) {
      _showErrorSnackBar('حدث خطأ في اختيار التاريخ: $e');
    }
  }

  Future<void> _selectPermissionTime(BuildContext context, bool isFrom) async {
    try {
      final picked = await showTimePicker(
        context: context,
        initialTime: isFrom
            ? (_permissionFromTime ?? TimeOfDay.now())
            : (_permissionToTime ?? (_permissionFromTime ?? TimeOfDay.now())),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme,
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          if (isFrom) {
            _permissionFromTime = picked;
            if (_permissionToTime != null) {
              final fromMin = picked.hour * 60 + picked.minute;
              final toMin =
                  _permissionToTime!.hour * 60 + _permissionToTime!.minute;
              if (toMin <= fromMin) {
                _permissionToTime = null;
              }
            }
          } else {
            _permissionToTime = picked;
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('حدث خطأ في اختيار الوقت: $e');
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // التحقق من وجود مسار قبل الإرسال
    if (_workflowData == null) {
      final languageService = Provider.of<LanguageService>(context, listen: false);
      final lang = languageService.currentLocale.languageCode;
      _showErrorSnackBar(
          Translations.getText('error_no_workflow', lang));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('🚀 بدء إرسال الطلب...');
      print('نوع الطلب: $_selectedRequestType');
      print('ClientID: ${widget.employeeData.clientID}');
      print('EmployeeID: ${widget.employeeData.employeeID}');

      request_models.RequestCreateResponse response;

      if (_selectedRequestType == 'سلفة') {
        print('📋 إنشاء طلب سلفة...');

        final model = request_models.LoanRequestCreateModel(
          requestType: 'Loan',
          employeeID: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
          loanType: _selectedLoanType!,
          loanAmount: double.parse(_loanAmountController.text),
          monthlyInstallment: double.parse(_monthlyInstallmentController.text),
          numberOfInstallments: int.parse(_numberOfInstallmentsController.text),
          loanStartDate: _loanStartDate!,
          loanEndDate: _loanEndDate!,
          loanDescription: _loanDescriptionController.text.trim(),
          attachmentFileName: _attachmentFileName,
          attachmentContent: _attachmentContent,
          createdBy: widget.employeeData.employeeID,
        );

        print('📦 بيانات الطلب: ${model.toJson()}');
        print(
            '📎 معلومات المرفق: ${_attachmentFileName != null ? "موجود" : "غير موجود"}');
        if (_attachmentContent != null) {
          print('📏 حجم المرفق: ${_attachmentContent!.length} bytes');
        }

        response = await ApiService.createLoanRequest(
          widget.employeeData.clientID,
          model,
        );
      } else if (_selectedRequestType == 'إجازة') {
        print('📋 إنشاء طلب إجازة...');

        final model = request_models.LeaveRequestCreateModel(
          requestType: 'Leave',
          employeeID: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
          leaveTypeID: _selectedLeaveType!.value,
          leaveTypeName: _selectedLeaveType!.text,
          leaveStartDate: _leaveStartDate!,
          leaveEndDate: _leaveEndDate!,
          leaveDays: int.parse(_leaveDaysController.text),
          leaveReason: _leaveReasonController.text.trim(),
          attachmentFileName: _attachmentFileName,
          attachmentContent: _attachmentContent,
          createdBy: widget.employeeData.employeeID,
        );

        print('📦 بيانات الطلب: ${model.toJson()}');
        print(
            '📎 معلومات المرفق: ${_attachmentFileName != null ? "موجود" : "غير موجود"}');
        if (_attachmentContent != null) {
          print('📏 حجم المرفق: ${_attachmentContent!.length} bytes');
        }

        response = await ApiService.createLeaveRequest(
          widget.employeeData.clientID,
          model,
        );
      } else if (_selectedRequestType == 'أخرى') {
        print('📋 إنشاء طلب أخرى...');

        final model = request_models.OtherRequestCreateModel(
          requestType: 'Other',
          employeeID: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
          otherDescription: _otherDescriptionController.text.trim(),
          attachmentFileName: _attachmentFileName,
          attachmentContent: _attachmentContent,
          createdBy: widget.employeeData.employeeID,
        );

        print('📦 بيانات الطلب: ${model.toJson()}');
        print(
            '📎 معلومات المرفق: ${_attachmentFileName != null ? "موجود" : "غير موجود"}');
        if (_attachmentContent != null) {
          print('📏 حجم المرفق: ${_attachmentContent!.length} bytes');
        }

        response = await ApiService.createOtherRequest(
          widget.employeeData.clientID,
          model,
        );
      } else if (_selectedRequestType == 'بصمة حضور وانصراف') {
        print('📋 إنشاء طلب بصمة حضور وانصراف...');

        // التحقق المحلي من الحقول المطلوبة
        if (_manualPunchDate == null) {
          _showErrorSnackBar('الرجاء اختيار تاريخ البصمة');
          setState(() => _isLoading = false);
          return;
        }
        if (_manualPunchType == null) {
          _showErrorSnackBar('الرجاء اختيار نوع البصمة (حضور / انصراف)');
          setState(() => _isLoading = false);
          return;
        }
        if (_manualPunchTime == null) {
          _showErrorSnackBar('الرجاء اختيار وقت البصمة');
          setState(() => _isLoading = false);
          return;
        }
        final dateStr = _manualPunchDate != null
            ? '${_manualPunchDate!.year}-${_manualPunchDate!.month.toString().padLeft(2, '0')}-${_manualPunchDate!.day.toString().padLeft(2, '0')}'
            : '';
        final timeStr = _manualPunchTime != null
            ? '${_manualPunchTime!.hour.toString().padLeft(2, '0')}:${_manualPunchTime!.minute.toString().padLeft(2, '0')}'
            : '';

        final model = request_models.ManualPunchRequestCreateModel(
          requestType: 'ManualPunch',
          employeeID: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
          manualPunchDateString: dateStr,
          manualPunchTimeString: timeStr,
          manualPunchType: _manualPunchType == 'حضور' ? 'in' : 'out',
          manualPunchReason: _manualPunchReasonController.text.trim(),
          attachmentFileName: _attachmentFileName,
          attachmentContent: _attachmentContent,
          createdBy: widget.employeeData.employeeID,
        );

        print('📦 بيانات الطلب: ${model.toJson()}');

        response = await ApiService.createManualPunchRequest(
          widget.employeeData.clientID,
          model,
        );
      } else if (_selectedRequestType == 'تأشيرة خروج وعودة') {
        if (_exitReturnFromDate == null) {
          _showErrorSnackBar('الرجاء اختيار تاريخ البداية');
          setState(() => _isLoading = false);
          return;
        }
        if (_exitReturnToDate == null) {
          _showErrorSnackBar('الرجاء اختيار تاريخ النهاية');
          setState(() => _isLoading = false);
          return;
        }

        final model = request_models.ExitReturnRequestCreateModel(
          requestType: 'ExitReturn',
          employeeID: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
          fromDate: _exitReturnFromDate!,
          toDate: _exitReturnToDate!,
          reason: _exitReturnReasonController.text.trim(),
          notes: _exitReturnNotesController.text.trim(),
          attachmentFileName: _attachmentFileName,
          attachmentContent: _attachmentContent,
          createdBy: widget.employeeData.employeeID,
        );

        response = await ApiService.createExitReturnRequest(
          widget.employeeData.clientID,
          model,
        );
      } else if (_selectedRequestType == 'استئذان') {
        if (_permissionDate == null) {
          _showErrorSnackBar('الرجاء اختيار التاريخ');
          setState(() => _isLoading = false);
          return;
        }
        if (_permissionFromTime == null) {
          _showErrorSnackBar('الرجاء اختيار وقت البداية');
          setState(() => _isLoading = false);
          return;
        }
        if (_permissionToTime == null) {
          _showErrorSnackBar('الرجاء اختيار وقت النهاية');
          setState(() => _isLoading = false);
          return;
        }

        final fromStr =
            '${_permissionFromTime!.hour.toString().padLeft(2, '0')}:${_permissionFromTime!.minute.toString().padLeft(2, '0')}';
        final toStr =
            '${_permissionToTime!.hour.toString().padLeft(2, '0')}:${_permissionToTime!.minute.toString().padLeft(2, '0')}';

        final model = request_models.PermissionRequestCreateModel(
          requestType: 'Permission',
          employeeID: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
          date: _permissionDate!,
          fromTimeString: fromStr,
          toTimeString: toStr,
          reason: _permissionReasonController.text.trim(),
          notes: _permissionNotesController.text.trim(),
          attachmentFileName: _attachmentFileName,
          attachmentContent: _attachmentContent,
          createdBy: widget.employeeData.employeeID,
        );

        response = await ApiService.createPermissionRequest(
          widget.employeeData.clientID,
          model,
        );
      } else {
        _showErrorSnackBar('نوع الطلب غير مدعوم');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });

      print('📡 استجابة الخادم: ${response.success} - ${response.message}');

      if (response.success) {
        _showSuccessDialog(response.message);
      } else {
        _showErrorSnackBar(response.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        print('❌ خطأ في إرسال الطلب: $e');
        final languageService = Provider.of<LanguageService>(context, listen: false);
        final lang = languageService.currentLocale.languageCode;
        _showErrorSnackBar('${Translations.getText('operation_failed', lang)}: $e');
      }
    }
  }

  void _showSuccessDialog(String message) {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(Translations.getText('request_saved_successfully', lang)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop(true);
              },
              child: Text(Translations.getText('confirm', lang)),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // دالة اختيار المرفق
  Future<void> _pickAttachment() async {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    if (_isPickingFile) return;
    try {
      setState(() {
        _isPickingFile = true;
      });

      // محاولة أولى مع withData
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'jpg',
          'jpeg',
          'png'
        ],
        allowMultiple: false,
        withData: true,
        lockParentWindow: true, // قفل النافذة الأم
        initialDirectory: '/storage/emulated/0/Download', // مجلد التنزيلات
      );

      // إذا فشلت المحاولة الأولى، جرب بدون withData
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print('⚠️ المحاولة الأولى فشلت، جاري المحاولة الثانية...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'jpg',
            'jpeg',
            'png'
          ],
          allowMultiple: false,
          withData: false, // جرب بدون withData
          allowCompression: false, // منع الضغط
          dialogTitle: Translations.getText('select_attachment', lang), // عنوان النافذة
        );
      }

      // إذا فشلت المحاولة الثانية، جرب مع FileType.any
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثانية فشلت، جاري المحاولة الثالثة مع FileType.any...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.any, // جرب مع أي نوع ملف
          allowMultiple: false,
          withData: true,
        );
      }

      // إذا فشلت المحاولة الثالثة، جرب مع FileType.image
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثالثة فشلت، جاري المحاولة الرابعة مع FileType.image...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.image, // جرب مع الصور فقط
          allowMultiple: false,
          withData: true,
        );
      }

      // إذا فشلت المحاولة الرابعة، جرب مع FileType.media
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الرابعة فشلت، جاري المحاولة الخامسة مع FileType.media...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.media, // جرب مع الوسائط
          allowMultiple: false,
          withData: true,
        );
      }

      // إذا فشلت المحاولة الخامسة، جرب مع FileType.video
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الخامسة فشلت، جاري المحاولة السادسة مع FileType.video...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.video, // جرب مع الفيديو
          allowMultiple: false,
          withData: true,
        );
      }

      // إذا فشلت المحاولة السادسة، جرب مع FileType.audio
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة السادسة فشلت، جاري المحاولة السابعة مع FileType.audio...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.audio, // جرب مع الصوت
          allowMultiple: false,
          withData: true,
        );
      }

      // إذا فشلت المحاولة السابعة، جرب مع FileType.custom بدون allowedExtensions
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة السابعة فشلت، جاري المحاولة الثامنة مع FileType.custom بدون allowedExtensions...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع أي نوع ملف
          allowMultiple: false,
          withData: true,
        );
      }

      // إذا فشلت المحاولة الثامنة، جرب مع FileType.custom بدون withData
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثامنة فشلت، جاري المحاولة التاسعة مع FileType.custom بدون withData...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع أي نوع ملف
          allowMultiple: false,
          withData: false, // جرب بدون withData
        );
      }

      // إذا فشلت المحاولة التاسعة، جرب مع FileType.custom بدون allowMultiple
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة التاسعة فشلت، جاري المحاولة العاشرة مع FileType.custom بدون allowMultiple...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع withData
        );
      }

      // إذا فشلت المحاولة العاشرة، جرب مع FileType.custom بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة العاشرة فشلت، جاري المحاولة الحادية عشرة مع FileType.custom بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع أي نوع ملف
        );
      }

      // إذا فشلت المحاولة الحادية عشرة، جرب مع FileType.any بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الحادية عشرة فشلت، جاري المحاولة الثانية عشرة مع FileType.any بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.any, // جرب مع أي نوع ملف
        );
      }

      // إذا فشلت المحاولة الثانية عشرة، جرب مع FileType.image بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثانية عشرة فشلت، جاري المحاولة الثالثة عشرة مع FileType.image بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.image, // جرب مع الصور فقط
        );
      }

      // إذا فشلت المحاولة الثالثة عشرة، جرب مع FileType.media بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثالثة عشرة فشلت، جاري المحاولة الرابعة عشرة مع FileType.media بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.media, // جرب مع الوسائط
        );
      }

      // إذا فشلت المحاولة الرابعة عشرة، جرب مع FileType.video بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الرابعة عشرة فشلت، جاري المحاولة الخامسة عشرة مع FileType.video بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.video, // جرب مع الفيديو
        );
      }

      // إذا فشلت المحاولة الخامسة عشرة، جرب مع FileType.audio بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الخامسة عشرة فشلت، جاري المحاولة السادسة عشرة مع FileType.audio بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.audio, // جرب مع الصوت
        );
      }

      // إذا فشلت المحاولة السادسة عشرة، جرب مع FileType.custom بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة السادسة عشرة فشلت، جاري المحاولة السابعة عشرة مع FileType.custom بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع أي نوع ملف
        );
      }

      // إذا فشلت المحاولة السابعة عشرة، جرب مع FileType.any بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة السابعة عشرة فشلت، جاري المحاولة الثامنة عشرة مع FileType.any بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.any, // جرب مع أي نوع ملف
        );
      }

      // إذا فشلت المحاولة الثامنة عشرة، جرب مع FileType.image بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثامنة عشرة فشلت، جاري المحاولة التاسعة عشرة مع FileType.image بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.image, // جرب مع الصور فقط
        );
      }

      // إذا فشلت المحاولة التاسعة عشرة، جرب مع FileType.media بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة التاسعة عشرة فشلت، جاري المحاولة العشرين مع FileType.media بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.media, // جرب مع الوسائط
        );
      }

      // إذا فشلت المحاولة العشرين، جرب مع FileType.video بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة العشرين فشلت، جاري المحاولة الحادية والعشرين مع FileType.video بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.video, // جرب مع الفيديو
        );
      }

      // إذا فشلت المحاولة الحادية والعشرين، جرب مع FileType.audio بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الحادية والعشرين فشلت، جاري المحاولة الثانية والعشرين مع FileType.audio بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.audio, // جرب مع الصوت
        );
      }

      // إذا فشلت المحاولة الثانية والعشرين، جرب مع FileType.custom بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثانية والعشرين فشلت، جاري المحاولة الثالثة والعشرين مع FileType.custom بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع أي نوع ملف
        );
      }

      // إذا فشلت المحاولة الثالثة والعشرين، جرب مع FileType.any بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثالثة والعشرين فشلت، جاري المحاولة الرابعة والعشرين مع FileType.any بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.any, // جرب مع أي نوع ملف
        );
      }

      // إذا فشلت المحاولة الرابعة والعشرين، جرب مع FileType.image بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الرابعة والعشرين فشلت، جاري المحاولة الخامسة والعشرين مع FileType.image بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.image, // جرب مع الصور فقط
        );
      }

      // إذا فشلت المحاولة الخامسة والعشرين، جرب مع FileType.media بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الخامسة والعشرين فشلت، جاري المحاولة السادسة والعشرين مع FileType.media بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.media, // جرب مع الوسائط
        );
      }

      // إذا فشلت المحاولة السادسة والعشرين، جرب مع FileType.video بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة السادسة والعشرين فشلت، جاري المحاولة السابعة والعشرين مع FileType.video بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.video, // جرب مع الفيديو
        );
      }

      // إذا فشلت المحاولة السابعة والعشرين، جرب مع FileType.audio بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة السابعة والعشرين فشلت، جاري المحاولة الثامنة والعشرين مع FileType.audio بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.audio, // جرب مع الصوت
        );
      }

      // إذا فشلت المحاولة الثامنة والعشرين، جرب مع FileType.custom بدون أي خيارات
      if (result == null ||
          result.files.isEmpty ||
          (result.files.first.bytes == null ||
              result.files.first.bytes!.isEmpty)) {
        print(
            '⚠️ المحاولة الثامنة والعشرين فشلت، جاري المحاولة التاسعة والعشرين مع FileType.custom بدون أي خيارات...');

        result = await FilePicker.platform.pickFiles(
          type: FileType.custom, // جرب مع أي نوع ملف
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        print('📁 معلومات الملف:');
        print('   الاسم: ${file.name}');
        print('   الحجم: ${file.size} bytes');
        print('   Bytes موجود: ${file.bytes != null}');
        print('   Bytes فارغ: ${file.bytes?.isEmpty ?? true}');
        print('   Path موجود: ${file.path != null}');
        print('   Path: ${file.path}');

        // التحقق من حجم الملف (10 ميجابايت)
        if (file.size > 10 * 1024 * 1024) {
          _showErrorSnackBar('حجم الملف يجب أن يكون أقل من 10 ميجابايت');
          return;
        }

        // محاولة قراءة الملف بطريقة بديلة إذا لم تكن bytes متاحة
        Uint8List? fileBytes = file.bytes;

        if ((fileBytes == null || fileBytes.isEmpty) && file.path != null) {
          print('⚠️ محاولة قراءة الملف من path...');
          try {
            fileBytes = await readBytesFromPath(file.path!);
            print('✅ تم قراءة الملف من path بنجاح');
          } catch (pathError) {
            print('❌ فشل في قراءة الملف من path: $pathError');
          }
        }

        // التحقق النهائي من البيانات
        if (fileBytes == null || fileBytes.isEmpty) {
          _showErrorSnackBar(
              'لا يمكن قراءة محتوى الملف. تأكد من أن الملف صالح.');
          return;
        }

        setState(() {
          _attachmentFileName = file.name;
          _attachmentContent = fileBytes;
        });

        print('✅ تم اختيار المرفق: ${file.name}');
        print('📏 حجم الملف: ${fileBytes.length} bytes');
        _showSuccessSnackBar('تم اختيار المرفق: ${file.name}');
      }
    } catch (e) {
      print('❌ خطأ في اختيار المرفق: $e');
      _showErrorSnackBar('حدث خطأ في اختيار المرفق: $e');
    } finally {
      setState(() {
        _isPickingFile = false;
      });
    }
  }

  // دالة حذف المرفق
  void _removeAttachment() {
    setState(() {
      _attachmentFileName = null;
      _attachmentContent = null;
    });
    _showSuccessSnackBar('تم حذف المرفق');
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('create_request', lang)),
        actions: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      body: _isLoadingData
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(Translations.getText('loading', lang)),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // معلومات الموظف
                    _buildEmployeeInfoCard(lang),
                    const SizedBox(height: 16),
                    
                    // معلومات المسار (إذا وجدت)
                    _buildWorkflowInfoCard(lang),
                    const SizedBox(height: 16),

                    // اختيار نوع الطلب
                    _buildRequestTypeCard(lang),
                    const SizedBox(height: 16),

                    // حقول السلفة
                    if (_selectedRequestType == 'سلفة') _buildLoanFieldsCard(lang),

                    // حقول الإجازة
                    if (_selectedRequestType == 'إجازة')
                      _buildLeaveFieldsCard(lang),

                    // حقول الطلب من نوع "أخرى"
                    if (_selectedRequestType == 'أخرى') _buildOtherFieldsCard(lang),

                    // حقول طلب إضافة بصمة
                    if (_selectedRequestType == 'بصمة حضور وانصراف')
                      _buildManualPunchFieldsCard(lang),

                    if (_selectedRequestType == 'تأشيرة خروج وعودة')
                      _buildExitReturnFieldsCard(lang),

                    if (_selectedRequestType == 'استئذان')
                      _buildPermissionFieldsCard(lang),

                    // بطاقة المرفقات (لجميع أنواع الطلبات)
                    if (_selectedRequestType != null) _buildAttachmentCard(lang),

                    const SizedBox(height: 24),

                    // أزرار الحفظ والإلغاء
                    _buildActionButtons(lang),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmployeeInfoCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('employee_info', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRowWithIcon(
                '${Translations.getText('name', lang)}:', widget.employeeData.name, Icons.person_outline, lang),
            _buildInfoRowWithIcon(
                '${Translations.getText('employee_number_short', lang)}:',
                widget.employeeData.employeeNumber.isNotEmpty
                    ? widget.employeeData.employeeNumber
                    : '${widget.employeeData.employeeID} (${Translations.getText('temporary', lang)})',
                Icons.badge, lang),
            _buildInfoRowWithIcon(
                '${Translations.getText('email', lang)}:',
                widget.employeeData.email.isNotEmpty
                    ? widget.employeeData.email
                    : Translations.getText('not_specified', lang),
                Icons.email, lang),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value.isNotEmpty ? value : Translations.getText('not_specified', lang),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: value.isNotEmpty ? Colors.black : Colors.grey,
                fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithIcon(String label, String value, IconData icon, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value.isNotEmpty ? value : Translations.getText('not_specified', lang),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: value.isNotEmpty ? Colors.black : Colors.grey,
                fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTypeCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.category,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('request_type', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_availableRequestTypes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      Translations.getText('no_request_types_available', lang),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Translations.getText('no_workflows_defined', lang),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedRequestType,
                decoration: InputDecoration(
                  labelText: Translations.getText('select_request_type', lang),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items:
                    _availableRequestTypes.map((api_models.RequestType type) {
                  return DropdownMenuItem<String>(
                    value: type.text,
                    child: Text(type.text),
                  );
                }).toList(),
                onChanged: _onRequestTypeChanged,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return Translations.getText('error_select_request_type', lang);
                  }
                  return null;
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkflowInfoCard(String lang) {
    if (_workflowData == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      color: const Color(0xFFF0F9FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.route,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('request_workflow', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Translations.getText('workflow_name_label', lang), _workflowData!.workflowName, lang),
            const SizedBox(height: 8),
            Text(
              Translations.getText('workflow_steps_label', lang),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            ..._workflowData!.steps.map((step) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                step.stepOrder.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.stepName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${Translations.getText('approver_label', lang)} ${step.actualApproverName}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanFieldsCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('loan_details', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _isLoadingData
                      ? InputDecorator(
                          decoration: InputDecoration(
                            labelText: Translations.getText('loan_type', lang),
                            border: const OutlineInputBorder(),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(Translations.getText('loading_data', lang)),
                            ],
                          ),
                        )
                      : _loanTypes.isEmpty
                          ? Column(
                              children: [
                                 InputDecorator(
                                   decoration: InputDecoration(
                                     labelText: Translations.getText('loan_type', lang),
                                     border: const OutlineInputBorder(),
                                   ),
                                   child: Text(
                                     Translations.getText('no_loan_types_available', lang),
                                     style: const TextStyle(color: Colors.grey),
                                   ),
                                 ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _loadData,
                                        icon: const Icon(Icons.refresh),
                                        label: Text(Translations.getText('reload', lang)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF0EA5E9),
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : DropdownButtonFormField<String>(
                              value: _selectedLoanType,
                              decoration: InputDecoration(
                                labelText: Translations.getText('loan_type', lang),
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: _loanTypes
                                  .map((request_models.LoanType type) {
                                return DropdownMenuItem<String>(
                                  value: type.value,
                                  child: Text(type.text),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedLoanType = value;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return Translations.getText('error_select_loan_type', lang);
                                }
                                return null;
                              },
                            ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _loanAmountController,
                    decoration: InputDecoration(
                      labelText: Translations.getText('loan_amount_label', lang),
                      border: const OutlineInputBorder(),
                      suffixText: Translations.getText('currency_sar', lang),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      _calculateMonthlyInstallment();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return Translations.getText('error_enter_amount', lang);
                      }
                      if (double.tryParse(value) == null ||
                          double.parse(value) <= 0) {
                        return Translations.getText('error_invalid_value', lang);
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _monthlyInstallmentController,
                    decoration: InputDecoration(
                      labelText: Translations.getText('monthly_installment', lang),
                      border: const OutlineInputBorder(),
                      suffixText: Translations.getText('currency_sar', lang),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return Translations.getText('error_enter_amount', lang);
                      }
                      if (double.tryParse(value) == null ||
                          double.parse(value) <= 0) {
                        return Translations.getText('error_invalid_value', lang);
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _numberOfInstallmentsController,
                    decoration: InputDecoration(
                      labelText: Translations.getText('installments_count_label', lang),
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      _calculateMonthlyInstallment();
                      _calculateLoanEndDate();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return Translations.getText('error_enter_installments', lang);
                      }
                      if (int.tryParse(value) == null ||
                          int.parse(value) <= 0) {
                        return Translations.getText('error_invalid_value', lang);
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true, true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: Translations.getText('start_date', lang),
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        _loanStartDate != null
                            ? DateFormat('yyyy-MM-dd').format(_loanStartDate!)
                            : Translations.getText('select_date', lang),
                        style: TextStyle(
                          color: _loanStartDate != null
                              ? Colors.black
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false, true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: Translations.getText('end_date', lang),
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        _loanEndDate != null
                            ? DateFormat('yyyy-MM-dd').format(_loanEndDate!)
                            : Translations.getText('select_date', lang),
                        style: TextStyle(
                          color:
                              _loanEndDate != null ? Colors.black : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _setLoanStartDate,
                    icon: const Icon(Icons.calculate),
                    label: Text(Translations.getText('auto_set_start_date', lang)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _loanDescriptionController,
              decoration: InputDecoration(
                labelText: Translations.getText('notes', lang),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveFieldsCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.beach_access, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('leave_details', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _isLoadingData
                      ? InputDecorator(
                          decoration: InputDecoration(
                            labelText: Translations.getText('leave_type', lang),
                            border: const OutlineInputBorder(),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(Translations.getText('loading_data', lang)),
                            ],
                          ),
                        )
                      : _leaveTypes.isEmpty
                          ? Column(
                              children: [
                                 InputDecorator(
                                   decoration: InputDecoration(
                                     labelText: Translations.getText('leave_type', lang),
                                     border: const OutlineInputBorder(),
                                   ),
                                   child: Text(
                                     Translations.getText('no_leave_types_available', lang),
                                     style: const TextStyle(color: Colors.grey),
                                   ),
                                 ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _loadData,
                                        icon: const Icon(Icons.refresh),
                                        label: Text(Translations.getText('reload', lang)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF0EA5E9),
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : DropdownButtonFormField<request_models.LeaveType>(
                              value: _selectedLeaveType,
                              decoration: InputDecoration(
                                labelText: Translations.getText('leave_type', lang),
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: _leaveTypes
                                  .map((request_models.LeaveType type) {
                                return DropdownMenuItem<
                                    request_models.LeaveType>(
                                  value: type,
                                  child: Text(type.text),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedLeaveType = value;
                                });
                              },
                                validator: (value) {
                                  if (value == null) {
                                    return Translations.getText('error_select_leave_type', lang);
                                  }
                                  return null;
                                },
                            ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true, false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: Translations.getText('start_date', lang),
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        _leaveStartDate != null
                            ? DateFormat('yyyy-MM-dd').format(_leaveStartDate!)
                            : Translations.getText('select_date', lang),
                        style: TextStyle(
                          color: _leaveStartDate != null
                              ? Colors.black
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false, false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: Translations.getText('end_date', lang),
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        _leaveEndDate != null
                            ? DateFormat('yyyy-MM-dd').format(_leaveEndDate!)
                            : Translations.getText('select_date', lang),
                        style: TextStyle(
                          color: _leaveEndDate != null
                              ? Colors.black
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _leaveDaysController,
                    decoration: InputDecoration(
                      labelText: Translations.getText('number_of_days', lang),
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calculate),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    enabled: false,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'عدد الأيام مطلوب';
                      }
                      if (int.tryParse(value) == null ||
                          int.parse(value) <= 0) {
                        return 'عدد الأيام يجب أن يكون صحيحاً';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _calculateLeaveDays,
                    icon: const Icon(Icons.calculate),
                    label: Text(Translations.getText('calculate_days', lang)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _leaveReasonController,
              decoration: InputDecoration(
                labelText: Translations.getText('leave_reason', lang),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return Translations.getText('error_enter_leave_reason', lang);
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherFieldsCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('request_details', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _otherDescriptionController,
              decoration: InputDecoration(
                labelText: Translations.getText('request_description', lang),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                hintText: Translations.getText('other_description_hint', lang),
              ),
              maxLines: 5,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return Translations.getText('error_enter_description', lang);
                }
                if (value.trim().length < 10) {
                  return Translations.getText('error_description_too_short', lang);
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitReturnFieldsCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flight_takeoff, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  'تفاصيل تأشيرة خروج وعودة',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _selectExitReturnDate(context, true),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'من تاريخ',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: Text(
                  _exitReturnFromDate != null
                      ? DateFormat('yyyy-MM-dd').format(_exitReturnFromDate!)
                      : '-- اختر --',
                  style: TextStyle(
                    color:
                        _exitReturnFromDate != null ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _selectExitReturnDate(context, false),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'إلى تاريخ',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: Text(
                  _exitReturnToDate != null
                      ? DateFormat('yyyy-MM-dd').format(_exitReturnToDate!)
                      : '-- اختر --',
                  style: TextStyle(
                    color:
                        _exitReturnToDate != null ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _exitReturnReasonController,
              decoration: const InputDecoration(
                labelText: 'سبب الطلب',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 3,
              validator: (value) {
                if (_selectedRequestType != 'تأشيرة خروج وعودة') return null;
                if (_exitReturnFromDate == null) return 'الرجاء اختيار تاريخ البداية';
                if (_exitReturnToDate == null) return 'الرجاء اختيار تاريخ النهاية';
                if (value == null || value.trim().isEmpty) {
                  return 'الرجاء إدخال سبب الطلب';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _exitReturnNotesController,
              decoration: const InputDecoration(
                labelText: 'الملاحظات (اختياري)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionFieldsCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  'تفاصيل الاستئذان',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _selectPermissionDate(context),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'التاريخ',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: Text(
                  _permissionDate != null
                      ? DateFormat('yyyy-MM-dd').format(_permissionDate!)
                      : '-- اختر --',
                  style: TextStyle(
                    color: _permissionDate != null ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _selectPermissionTime(context, true),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'من وقت',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: Text(
                  _permissionFromTime != null
                      ? '${_permissionFromTime!.hour.toString().padLeft(2, '0')}:${_permissionFromTime!.minute.toString().padLeft(2, '0')}'
                      : '-- اختر --',
                  style: TextStyle(
                    color:
                        _permissionFromTime != null ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _selectPermissionTime(context, false),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'إلى وقت',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: Text(
                  _permissionToTime != null
                      ? '${_permissionToTime!.hour.toString().padLeft(2, '0')}:${_permissionToTime!.minute.toString().padLeft(2, '0')}'
                      : '-- اختر --',
                  style: TextStyle(
                    color:
                        _permissionToTime != null ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _permissionReasonController,
              decoration: const InputDecoration(
                labelText: 'سبب الطلب',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 3,
              validator: (value) {
                if (_selectedRequestType != 'استئذان') return null;
                if (_permissionDate == null) return 'الرجاء اختيار التاريخ';
                if (_permissionFromTime == null) return 'الرجاء اختيار وقت البداية';
                if (_permissionToTime == null) return 'الرجاء اختيار وقت النهاية';
                if (value == null || value.trim().isEmpty) {
                  return 'الرجاء إدخال سبب الطلب';
                }
                final fromMin = _permissionFromTime!.hour * 60 + _permissionFromTime!.minute;
                final toMin = _permissionToTime!.hour * 60 + _permissionToTime!.minute;
                if (toMin <= fromMin) return 'وقت البداية يجب أن يكون قبل وقت النهاية';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _permissionNotesController,
              decoration: const InputDecoration(
                labelText: 'الملاحظات (اختياري)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualPunchFieldsCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fingerprint, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('punch_details', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 16),
            // تاريخ البصمة
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now(),
                  locale: const Locale('ar', 'SA'),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFF0EA5E9),
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    _manualPunchDate = picked;
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '${Translations.getText('punch_date', lang)} *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  _manualPunchDate != null
                      ? DateFormat('yyyy-MM-dd').format(_manualPunchDate!)
                      : Translations.getText('select_date', lang),
                  style: TextStyle(
                    color:
                        _manualPunchDate != null ? Colors.black : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // نوع البصمة
            DropdownButtonFormField<String>(
              value: _manualPunchType,
              decoration: InputDecoration(
                labelText: '${Translations.getText('punch_type', lang)} *',
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'حضور', child: Text('${Translations.getText('check_in', lang)} (Check-In)')),
                DropdownMenuItem(
                    value: 'انصراف', child: Text('${Translations.getText('check_out', lang)} (Check-Out)')),
              ],
              onChanged: (value) {
                setState(() {
                  _manualPunchType = value;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'الرجاء اختيار نوع البصمة';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // وقت البصمة
            InkWell(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFF0EA5E9),
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: child!,
                      ),
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    _manualPunchTime = picked;
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '${Translations.getText('punch_time', lang)} *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.access_time),
                ),
                child: Text(
                  _manualPunchTime != null
                      ? '${_manualPunchTime!.hour.toString().padLeft(2, '0')}:${_manualPunchTime!.minute.toString().padLeft(2, '0')}'
                      : Translations.getText('select_time', lang),
                  style: TextStyle(
                    color:
                        _manualPunchTime != null ? Colors.black : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // سبب الطلب
            TextFormField(
              controller: _manualPunchReasonController,
              decoration: InputDecoration(
                labelText: '${Translations.getText('punch_reason', lang)} *',
                hintText: Translations.getText('punch_reason_hint', lang),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return Translations.getText('error_enter_reason', lang);
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentCard(String lang) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  Translations.getText('attachments', lang),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_attachmentFileName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0EA5E9)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.file_present, color: Color(0xFF0EA5E9)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _attachmentFileName!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${Translations.getText('file_size_label', lang)} ${(_attachmentContent?.length ?? 0) ~/ 1024} KB',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _removeAttachment,
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: Translations.getText('delete_attachment', lang),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPickingFile ? null : _pickAttachment,
                    icon: _isPickingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                    label: Text(
                        _isPickingFile ? Translations.getText('calculating', lang) : Translations.getText('add_attachment', lang)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${Translations.getText('allowed_file_types', lang)}\n${Translations.getText('max_file_size', lang)}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : Text(
                        Translations.getText('save_request', lang),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _isLoading ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  Translations.getText('cancel', lang),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        if (_isLoadingData || _availableRequestTypes.isEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: Text(Translations.getText('reload_data', lang)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
