@php
    $money = fn ($v) => '$ '.number_format((float) $v, 0, ',', '.');
    $aging = [
        'current' => 'Corriente (sin vencer)',
        'd1_30' => 'Vencido 1 a 30 días',
        'd31_60' => 'Vencido 31 a 60 días',
        'd61_90' => 'Vencido 61 a 90 días',
        'd90_plus' => 'Vencido más de 90 días',
    ];
@endphp
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>Estado de cartera</title>
</head>
<body style="margin:0;padding:0;background:#f4faf6;font-family:Arial,Helvetica,sans-serif;color:#111827;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4faf6;padding:24px 0;">
    <tr>
        <td align="center">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0;">
                <tr>
                    <td style="background:#1e9b50;padding:24px 28px;color:#ffffff;">
                        <div style="font-size:13px;opacity:.85;">{{ $companyName }}</div>
                        <div style="font-size:22px;font-weight:bold;margin-top:4px;">Estado de cartera</div>
                        <div style="font-size:13px;margin-top:4px;">Corte al {{ \Carbon\Carbon::parse($summary['as_of'])->locale('es')->isoFormat('D [de] MMMM [de] YYYY') }}</div>
                    </td>
                </tr>
                <tr>
                    <td style="padding:28px;">
                        <p style="margin:0 0 16px;font-size:15px;">Estimado cliente <strong>{{ $client['name'] }}</strong> (NIT {{ $client['nit'] }}),</p>

                        @if ($customMessage)
                            <p style="margin:0 0 16px;font-size:15px;line-height:1.5;white-space:pre-line;">{{ $customMessage }}</p>
                        @else
                            <p style="margin:0 0 16px;font-size:15px;line-height:1.5;">Compartimos el estado de su cuenta con nosotros. En el PDF adjunto encontrará el detalle de cada documento.</p>
                        @endif

                        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;border-radius:12px;margin:8px 0 16px;">
                            <tr>
                                <td style="padding:14px 16px 6px;font-size:14px;color:#4b5563;">Saldo total</td>
                                <td style="padding:14px 16px 6px;font-size:20px;font-weight:bold;text-align:right;">{{ $money($summary['total']) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:0 16px 6px;font-size:14px;color:#4b5563;">Saldo vencido</td>
                                <td style="padding:0 16px 6px;font-size:15px;font-weight:bold;text-align:right;color:{{ $summary['overdue'] > 0 ? '#dc2626' : '#16a34a' }};">{{ $money($summary['overdue']) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:0 16px 14px;font-size:14px;color:#4b5563;">Documentos pendientes</td>
                                <td style="padding:0 16px 14px;font-size:14px;text-align:right;">{{ $summary['documents_count'] }}</td>
                            </tr>
                        </table>

                        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px;">
                            @foreach ($aging as $key => $label)
                                <tr>
                                    <td style="padding:8px 0;border-bottom:1px solid #e2e8f0;color:#4b5563;">{{ $label }}</td>
                                    <td style="padding:8px 0;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">{{ $money($summary['aging'][$key] ?? 0) }}</td>
                                </tr>
                            @endforeach
                        </table>

                        <p style="margin:20px 0 0;font-size:13px;color:#4b5563;">Si ya realizó algún pago, por favor haga caso omiso de los documentos correspondientes o envíenos el soporte.</p>

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
