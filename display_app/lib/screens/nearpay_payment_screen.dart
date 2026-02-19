import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/nearpay_provider.dart';

/// Host screen that delegates the full payment UX to NearPay native SDK UI.
/// This screen intentionally renders no customer-facing payment UI.
class NearPayPaymentScreen extends StatefulWidget {
  final double amount;
  final String? customerReference;
  final Function(Map<String, dynamic>)? onPaymentComplete;
  final VoidCallback? onPaymentCancelled;
  final Function(String status, String? message)? onStatusChanged;
  final Function(String errorMessage)? onPaymentFailed;

  const NearPayPaymentScreen({
    super.key,
    required this.amount,
    this.customerReference,
    this.onPaymentComplete,
    this.onPaymentCancelled,
    this.onStatusChanged,
    this.onPaymentFailed,
  });

  @override
  State<NearPayPaymentScreen> createState() => _NearPayPaymentScreenState();
}

class _NearPayPaymentScreenState extends State<NearPayPaymentScreen> {
  late NearPayProvider _nearPayProvider;
  bool _paymentStarted = false;
  bool _completed = false;
  bool _failureNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nearPayProvider = context.read<NearPayProvider>();
      _nearPayProvider.addListener(_onStatusChanged);
      _initializeNearPay();
    });
  }

  @override
  void dispose() {
    _nearPayProvider.removeListener(_onStatusChanged);
    super.dispose();
  }

  Future<void> _initializeNearPay() async {
    await _nearPayProvider.initializeAndAuthenticate();
    _startPaymentIfReady();
  }

  void _onStatusChanged() {
    if (!mounted) return;

    final provider = _nearPayProvider;
    widget.onStatusChanged?.call(provider.status.name, provider.statusMessage);

    if (provider.status == PaymentStatus.ready) {
      _startPaymentIfReady();
      return;
    }

    if (provider.status == PaymentStatus.success && !_completed) {
      _completed = true;
      widget.onPaymentComplete?.call(provider.lastTransaction ?? {});
      return;
    }

    if (provider.status == PaymentStatus.error && !_failureNotified) {
      _failureNotified = true;
      final msg = provider.errorMessage ??
          provider.statusMessage ??
          provider.lastSdkErrorRaw ??
          'Payment failed';
      widget.onPaymentFailed?.call(msg);
    }
  }

  void _startPaymentIfReady() {
    if (_paymentStarted || !_nearPayProvider.isReady) {
      return;
    }
    _paymentStarted = true;

    final amountInHalalas = (widget.amount * 100).toInt();
    _nearPayProvider.processPurchase(
      amount: amountInHalalas,
      customerReferenceNumber: widget.customerReference,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Intentionally empty: NearPay native SDK UI should be the only UI shown.
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(),
    );
  }
}
