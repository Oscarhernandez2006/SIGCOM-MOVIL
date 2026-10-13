import 'package:flutter/material.dart';

import '../theme.dart';

/// Envía y devuelve el mensaje de confirmación, o null si el usuario canceló.
typedef EmailSender = Future<String?> Function(BuildContext context, List<String> to, List<String> cc, String? message);

/// Formulario de correo desde el buzón de la empresa (cotizaciones, cartera…).
Future<void> showEmailSheet(
  BuildContext context, {
  required String title,
  required String? customerName,
  required String defaultMessage,
  required EmailSender onSend,
  List<String> recipients = const [],
  String? userEmail,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _EmailSheet(
      title: title,
      customerName: customerName,
      defaultMessage: defaultMessage,
      onSend: onSend,
      recipients: recipients,
      userEmail: userEmail,
    ),
  );
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

List<String> _emails(String text) =>
    text.split(RegExp(r'[,;\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

class _EmailSheet extends StatefulWidget {
  const _EmailSheet({
    required this.title,
    required this.customerName,
    required this.defaultMessage,
    required this.onSend,
    required this.recipients,
    this.userEmail,
  });

  final String title;
  final String? customerName;
  final String defaultMessage;
  final EmailSender onSend;
  final List<String> recipients;
  final String? userEmail;

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet> {
  final _form = GlobalKey<FormState>();
  late final _to = TextEditingController(
    text: widget.recipients.map((e) => e.trim()).where(_emailPattern.hasMatch).join(', '),
  );
  final _cc = TextEditingController();
  late final _message = TextEditingController(text: widget.defaultMessage);
  late bool _copyMe = _validUserEmail;
  bool _sending = false;
  String? _error;

  bool get _validUserEmail => widget.userEmail != null && _emailPattern.hasMatch(widget.userEmail!.trim());

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _message.dispose();
    super.dispose();
  }

  String? _validateList(String? value, {required bool required}) {
    final list = _emails(value ?? '');
    if (required && list.isEmpty) return 'Escribe al menos un correo';
    if (list.length > 5) return 'Máximo 5 correos';
    final invalid = list.where((e) => !_emailPattern.hasMatch(e)).toList();
    return invalid.isEmpty ? null : 'Correo no válido: ${invalid.first}';
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final cc = {..._emails(_cc.text), if (_copyMe) widget.userEmail!.trim()}.toList();
    try {
      final result = await widget.onSend(
        context,
        _emails(_to.text),
        cc,
        _message.text.trim().isEmpty ? null : _message.text.trim(),
      );
      if (result == null || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(result)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noRecipient = widget.recipients.every((e) => !_emailPattern.hasMatch(e.trim()));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Sale desde el correo de la empresa con el PDF adjunto.'
                '${_validUserEmail ? ' Si el cliente responde, te llega a ti.' : ''}',
                style: const TextStyle(color: AppColors.textSoft, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _to,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => _validateList(v, required: true),
                decoration: InputDecoration(
                  labelText: 'Para *',
                  helperText: noRecipient && widget.customerName != null
                      ? '${widget.customerName} no tiene correo registrado'
                      : 'Separa varios correos con coma',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _cc,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => _validateList(v, required: false),
                decoration: const InputDecoration(labelText: 'Copia (CC)', prefixIcon: Icon(Icons.group_outlined)),
              ),
              if (_validUserEmail)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _copyMe,
                  onChanged: (v) => setState(() => _copyMe = v ?? false),
                  title: Text('Enviarme una copia (${widget.userEmail})', style: const TextStyle(fontSize: 13.5)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _message,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Mensaje', alignLabelWithHint: true),
              ),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_sending ? 'Enviando…' : 'Enviar correo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
