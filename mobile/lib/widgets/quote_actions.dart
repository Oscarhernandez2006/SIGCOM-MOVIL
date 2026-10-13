import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import 'email_sheet.dart';
import 'web_session.dart';

/// Descarga el PDF de la cotización y abre el menú del sistema para guardarlo
/// o compartirlo (Archivos, Drive, WhatsApp, correo personal…).
Future<void> shareQuotePdf(BuildContext context, ApiService api, {required String id, required String number}) {
  return sharePdf(
    context,
    load: () => withWebSession(context, api, () => api.quotePdf(id)),
    fileName: 'cotizacion-$number.pdf',
    subject: 'Cotización $number',
  );
}

/// Obtiene un archivo (PDF por defecto) con [load] y abre el menú del sistema para guardarlo o compartirlo.
Future<void> sharePdf(
  BuildContext context, {
  required Future<List<int>?> Function() load,
  required String fileName,
  required String subject,
  String mimeType = 'application/pdf',
}) async {
  final kind = mimeType == 'application/pdf' ? 'PDF' : 'archivo';
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text('Generando $kind…'), duration: const Duration(seconds: 2)));
  try {
    final bytes = await load();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        title: subject,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo obtener el $kind: $e')));
  }
}

/// Formulario para enviar la cotización por correo desde el buzón de la empresa.
Future<void> showSendQuoteSheet(
  BuildContext context,
  ApiService api, {
  required String id,
  required String number,
  required String customerName,
  String? customerEmail,
  String? userEmail,
}) {
  return showEmailSheet(
    context,
    title: 'Enviar cotización $number',
    customerName: customerName,
    recipients: [?customerEmail],
    userEmail: userEmail,
    defaultMessage:
        'Cordial saludo.\n\nAdjuntamos la cotización N.º $number solicitada. Quedamos atentos a sus comentarios.',
    onSend: (sheetContext, to, cc, message) =>
        withWebSession(sheetContext, api, () => api.sendQuote(id, to: to, cc: cc, message: message)),
  );
}
