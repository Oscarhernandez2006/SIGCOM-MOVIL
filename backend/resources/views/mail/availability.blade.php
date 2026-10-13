<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>Disponibilidad de productos</title>
</head>
<body style="margin:0;padding:0;background:#f4faf6;font-family:Arial,Helvetica,sans-serif;color:#111827;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4faf6;padding:24px 0;">
    <tr>
        <td align="center">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0;">
                <tr>
                    <td style="background:#1e9b50;padding:24px 28px;color:#ffffff;">
                        <div style="font-size:13px;opacity:.85;">{{ $companyName }}</div>
                        <div style="font-size:22px;font-weight:bold;margin-top:4px;">Disponibilidad de productos</div>
                        <div style="font-size:13px;opacity:.85;margin-top:4px;">{{ now('America/Bogota')->locale('es')->isoFormat('dddd D [de] MMMM [de] YYYY') }}</div>
                    </td>
                </tr>
                <tr>
                    <td style="padding:28px;">
                        <p style="margin:0 0 16px;font-size:15px;">Cordial saludo,</p>
                        @if ($customMessage)
                            <p style="margin:0 0 16px;font-size:15px;line-height:1.5;white-space:pre-line;">{{ $customMessage }}</p>
                        @else
                            <p style="margin:0 0 16px;font-size:15px;line-height:1.5;">Compartimos los productos disponibles para pedido hoy. Quedamos atentos a su solicitud.</p>
                        @endif
                        <p style="margin:0;font-size:14px;color:#4b5563;">
                            Encontrará el listado en el PDF adjunto
                            @if ($priceListName)
                                con precios de la lista <strong>{{ $priceListName }}</strong>.
                            @else
                                (sin precios).
                            @endif
                            La disponibilidad puede cambiar durante el día.
                        </p>
                        @if ($sellerName)
                            <p style="margin:24px 0 0;font-size:14px;line-height:1.5;">
                                Cordialmente,<br>
                                <strong>{{ $sellerName }}</strong><br>
                                {{ $companyName }}
                                @if ($sellerEmail)
                                    <br><a href="mailto:{{ $sellerEmail }}" style="color:#1e9b50;">{{ $sellerEmail }}</a>
                                @endif
                            </p>
                        @endif
                    </td>
                </tr>
                <tr>
                    <td style="padding:16px 28px;background:#f8fafc;font-size:12px;color:#6b7280;">
                        Este correo fue enviado desde SIGCOM.@if ($sellerEmail) Si responde, su mensaje llegará al asesor comercial.@endif
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
