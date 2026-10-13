<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>{{ $reportTitle }}</title>
</head>
<body style="margin:0;padding:0;background:#f4faf6;font-family:Arial,Helvetica,sans-serif;color:#111827;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4faf6;padding:24px 0;">
    <tr>
        <td align="center">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0;">
                <tr>
                    <td style="background:#1e9b50;padding:24px 28px;color:#ffffff;">
                        <div style="font-size:13px;opacity:.85;">{{ $companyName }}</div>
                        <div style="font-size:22px;font-weight:bold;margin-top:4px;">{{ $reportTitle }}</div>
                        @if ($subtitle)
                            <div style="font-size:13px;opacity:.85;margin-top:4px;">{{ $subtitle }}</div>
                        @endif
                    </td>
                </tr>
                <tr>
                    <td style="padding:28px;">
                        <p style="margin:0 0 16px;font-size:15px;line-height:1.5;white-space:pre-line;">{{ $customMessage ?? 'Adjuntamos el reporte solicitado.' }}</p>
                        <p style="margin:0;font-size:14px;color:#4b5563;">Encontrará el detalle en el archivo adjunto.</p>
                        @if ($senderName)
                            <p style="margin:24px 0 0;font-size:14px;line-height:1.5;">
                                Cordialmente,<br>
                                <strong>{{ $senderName }}</strong><br>
                                {{ $companyName }}
                            </p>
                        @endif
                    </td>
                </tr>
                <tr>
                    <td style="padding:16px 28px;background:#f8fafc;font-size:12px;color:#6b7280;">
                        Este correo fue enviado desde SIGCOM.
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
