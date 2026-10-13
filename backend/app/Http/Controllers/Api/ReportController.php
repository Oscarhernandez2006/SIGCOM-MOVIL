<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\ReportMail;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Reportes administrativos de la web (/admin/reportes). Los datos se piden a la
 * API web y se normalizan a un formato común (indicadores + filas) para que la
 * app use un solo visor; PDF y Excel son los mismos archivos de la web.
 */
class ReportController extends Controller
{
    private const XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    /** Ruta base en la web, ruta del PDF y filtros que acepta cada reporte. */
    private const REPORTS = [
        'inventory' => ['title' => 'Resumen de inventario por día', 'path' => 'inventory', 'pdf' => 'inventory', 'filter' => 'day'],
        'product-sales' => ['title' => 'Productos vendidos', 'path' => 'product-sales', 'pdf' => 'product-sales', 'filter' => 'range'],
        'sales-summary' => ['title' => 'Ventas por cliente y producto', 'path' => 'sales-summary', 'pdf' => 'sales-summary/pdf', 'filter' => 'range'],
        'seller-ranking' => ['title' => 'Ranking de vendedores', 'path' => 'seller-ranking', 'pdf' => 'seller-ranking/pdf', 'filter' => 'range'],
        'seller-product' => ['title' => 'Ventas por vendedor y producto', 'path' => 'seller-product', 'pdf' => 'seller-product/pdf', 'filter' => 'range'],
        'product-seller' => ['title' => 'Mejor vendedor por producto', 'path' => 'product-seller', 'pdf' => 'product-seller/pdf', 'filter' => 'range'],
        'seller-sales' => ['title' => 'Ventas por vendedor (mensual)', 'path' => 'seller-sales', 'pdf' => 'seller-sales/pdf', 'filter' => 'month'],
        'vendor-product-sales' => ['title' => 'Ventas acumuladas por vendedor y producto', 'path' => 'vendor-product-sales', 'pdf' => 'vendor-product-sales/pdf', 'filter' => 'period'],
    ];

    public function __construct(private readonly SigcomWebClient $web)
    {
    }

    public function show(Request $request, string $report): JsonResponse
    {
        [$config, $company, $query] = $this->resolve($request, $report);
        $data = $this->web->call($request->user(), $company, 'GET', "/admin/reports/{$config['path']}/data", $query) ?? [];

        $unit = (config('sigcom.companies')[$company]['unit'] ?? 'kg') === 'und' ? 'Unidades' : 'Kilos';

        return response()->json(['title' => $config['title']] + $this->normalize($report, $data, $unit));
    }

    public function file(Request $request, string $report): Response
    {
        [$config, $company, $query] = $this->resolve($request, $report);
        [$content, $mime, $name] = $this->download($request, $report, $config, $company, $query);

        return response($content, 200, [
            'Content-Type' => $mime,
            'Content-Disposition' => 'attachment; filename="'.$name.'"',
        ]);
    }

    public function send(Request $request, string $report): JsonResponse
    {
        [$config, $company, $query] = $this->resolve($request, $report);
        $data = $request->validate([
            'to' => ['required', 'array', 'min:1', 'max:5'],
            'to.*' => ['required', 'email:rfc', 'max:150'],
            'cc' => ['nullable', 'array', 'max:5'],
            'cc.*' => ['email:rfc', 'max:150'],
            'message' => ['nullable', 'string', 'max:2000'],
            'subtitle' => ['nullable', 'string', 'max:200'],
        ]);
        [$content, $mime, $name] = $this->download($request, $report, $config, $company, $query);
        $user = $request->user();
        $companyName = config('sigcom.quotes_mail.company_names')[$company] ?? config('app.name');

        try {
            Mail::to($data['to'])->cc($data['cc'] ?? [])->send(new ReportMail(
                $config['title'],
                $data['subtitle'] ?? null,
                $companyName,
                $user->name,
                filter_var($user->email, FILTER_VALIDATE_EMAIL) ? $user->email : null,
                trim((string) ($data['message'] ?? '')) ?: null,
                $content,
                $name,
                $mime,
            ));
        } catch (Throwable $e) {
            Log::error('No se pudo enviar el reporte por correo', ['report' => $report, 'error' => $e->getMessage()]);
            abort(502, 'No se pudo enviar el correo. Intenta de nuevo más tarde.');
        }

        Log::info('Reporte enviado por correo', ['report' => $report, 'company' => $company, 'user' => $user->id, 'to' => $data['to']]);

        return response()->json(['message' => 'Reporte enviado a '.implode(', ', $data['to']).'.']);
    }

    /** @return array{0: array, 1: string, 2: array} configuración, compañía y parámetros para la web */
    private function resolve(Request $request, string $report): array
    {
        $config = self::REPORTS[$report] ?? abort(404, 'Reporte no encontrado.');
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
            'date' => ['nullable', 'date_format:Y-m-d'],
            'month' => ['nullable', 'date_format:Y-m'],
            'group_by' => ['nullable', 'in:customer,product'],
            'seller_id' => ['nullable', 'uuid'],
            'sku' => ['nullable', 'string', 'max:50'],
        ]);

        $user = $request->user();
        abort_unless($user->role === 'admin', 403, 'Los reportes son solo para administradores.');
        abort_unless(
            $user->companies()->where('company_id', $data['company'])->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );

        $today = CarbonImmutable::today('America/Bogota');
        $month = CarbonImmutable::createFromFormat('!Y-m', $data['month'] ?? $today->format('Y-m'));
        $query = match ($config['filter']) {
            'day' => ['date' => $data['date'] ?? $today->toDateString()],
            'range' => ['from' => $data['from'] ?? $today->toDateString(), 'to' => $data['to'] ?? $today->toDateString()],
            'month' => ['month' => $month->month, 'year' => $month->year],
            'period' => array_filter([
                'periodo' => isset($data['date']) ? CarbonImmutable::parse($data['date'])->format('Ym') : $month->format('Ym'),
                'fecha' => $data['date'] ?? null,
            ]),
        };
        $query['companyId'] = $data['company'];
        if ($report === 'sales-summary') {
            $query['groupBy'] = $data['group_by'] ?? 'customer';
        }
        if ($report === 'seller-product' && isset($data['seller_id'])) {
            $query['sellerId'] = $data['seller_id'];
        }
        if (in_array($report, ['seller-product', 'product-seller'], true) && isset($data['sku'])) {
            $query['sku'] = $data['sku'];
        }

        return [$config, $data['company'], $query];
    }

    /** @return array{0: string, 1: string, 2: string} contenido, tipo MIME y nombre del archivo */
    private function download(Request $request, string $report, array $config, string $company, array $query): array
    {
        $excel = $request->input('format', $request->query('format')) === 'xlsx';
        $path = $excel ? "{$config['path']}/excel" : $config['pdf'];
        $content = $this->web->download($request->user(), $company, "/admin/reports/{$path}?".http_build_query($query));
        $suffix = implode('_', array_filter([$query['from'] ?? null, $query['to'] ?? null, $query['date'] ?? null, $query['fecha'] ?? null]))
            ?: (isset($query['periodo']) ? $query['periodo'] : (isset($query['year']) ? sprintf('%d-%02d', $query['year'], $query['month']) : ''));

        return [$content, $excel ? self::XLSX : 'application/pdf', "{$report}-{$company}-{$suffix}.".($excel ? 'xlsx' : 'pdf')];
    }

    /**
     * Formato común: kpis [{label, value, format}] y rows [{title, subtitle,
     * value, format, highlight, details: [{label, value, format}], items}].
     * format: money | qty | int | pct (ratio 0-1) | text.
     */
    private function normalize(string $report, array $d, string $qtyWord = 'Kilos'): array
    {
        $qty = mb_strtolower($qtyWord);
        $per = $qtyWord === 'Kilos' ? 'kilo' : 'unidad';
        $sold = $qtyWord === 'Kilos' ? 'Kilos vendidos' : 'Unidades vendidas';
        $kpi = fn (string $label, $value, string $format = 'int') => ['label' => $label, 'value' => $value, 'format' => $format];
        $detail = fn (string $label, $value, string $format = 'qty') => ['label' => $label, 'value' => $value, 'format' => $format];
        $row = fn (string $title, ?string $subtitle, $value, string $format, array $details = [], bool $highlight = false, ?array $items = null) => array_filter([
            'title' => $title, 'subtitle' => $subtitle, 'value' => $value, 'format' => $format,
            'details' => $details, 'highlight' => $highlight, 'items' => $items,
        ], fn ($v) => $v !== null);
        $unit = fn (array $r) => isset($r['unitOfMeasure']) && $r['unitOfMeasure'] !== '' ? " {$r['unitOfMeasure']}" : '';
        $pct = fn ($v) => $v === null ? null : $v / 100;

        switch ($report) {
            case 'inventory':
                $s = $d['summary'] ?? [];

                return [
                    'kpis' => [
                        $kpi('Referencias', $s['totalRefs'] ?? 0), $kpi('Con stock', $s['refsWithStock'] ?? 0),
                        $kpi('Sin stock', $s['refsWithoutStock'] ?? 0), $kpi('Vendido', $s['totalSold'] ?? 0, 'qty'),
                        $kpi('Stock total', $s['totalStock'] ?? 0, 'qty'),
                    ],
                    'rows' => array_map(fn ($r) => $row($r['name'], "Ref. {$r['sku']}".$unit($r), $r['stock'], 'qty', [
                        $detail('Vendido', $r['sold']), $detail('Stock', $r['stock']),
                    ], ($r['stock'] ?? 0) <= 0), $d['rows'] ?? []),
                    'value_label' => 'Stock',
                ];

            case 'product-sales':
                $c = $d['companies'][0] ?? ['rows' => [], 'summary' => []];
                $s = $c['summary'] ?? [];

                return [
                    'kpis' => [
                        $kpi('Productos', $s['totalProducts'] ?? 0), $kpi('Cantidad', $s['totalQuantity'] ?? 0, 'qty'),
                        $kpi('Ingresos', $s['totalRevenue'] ?? 0, 'money'),
                    ],
                    'rows' => array_map(fn ($r) => $row($r['name'], "Ref. {$r['sku']}".$unit($r), $r['revenue'], 'money', [
                        $detail('Cantidad', $r['quantity']),
                    ]), $c['rows'] ?? []),
                ];

            case 'sales-summary':
                $s = $d['summary'] ?? [];
                $byCustomer = ($d['groupBy'] ?? 'customer') === 'customer';

                return [
                    'kpis' => [
                        $kpi($byCustomer ? 'Clientes' : 'Productos', $s['totalRows'] ?? 0), $kpi('Pedidos', $s['totalOrders'] ?? 0),
                        $kpi('Unidades', $s['totalUnits'] ?? 0, 'qty'), $kpi('Ingresos', $s['totalRevenue'] ?? 0, 'money'),
                    ],
                    'rows' => array_map(fn ($r) => $row($r['name'], ($byCustomer ? 'NIT ' : 'Ref. ').$r['reference'].$unit($r), $r['revenue'], 'money', array_values(array_filter([
                        isset($r['orders']) ? $detail('Pedidos', $r['orders'], 'int') : null,
                        $detail($byCustomer ? 'Unidades' : 'Cantidad', $r['units']),
                    ]))), $d['rows'] ?? []),
                ];

            case 'seller-ranking':
                $s = $d['summary'] ?? [];

                return [
                    'kpis' => [
                        $kpi('Vendedores', $s['totalSellers'] ?? 0), $kpi('Pedidos', $s['totalOrders'] ?? 0),
                        $kpi('Unidades', $s['totalUnits'] ?? 0, 'qty'), $kpi('Ingresos', $s['totalRevenue'] ?? 0, 'money'),
                    ],
                    'rows' => array_map(fn ($r) => $row(
                        "#{$r['position']} {$r['name']}",
                        implode(' · ', array_filter([isset($r['documentId']) ? "CC {$r['documentId']}" : null, isset($r['sellerCode']) ? "Cód. {$r['sellerCode']}" : null])) ?: null,
                        $r['revenue'], 'money',
                        [$detail('Pedidos', $r['orders'], 'int'), $detail('Unidades', $r['units'])],
                        ($r['position'] ?? 0) <= 3,
                    ), $d['rows'] ?? []),
                ];

            case 'seller-product':
                $s = $d['summary'] ?? [];

                return [
                    'kpis' => [
                        $kpi('Líneas', $s['totalRows'] ?? 0), $kpi('Unidades', $s['totalQuantity'] ?? 0, 'qty'),
                        $kpi('Ingresos', $s['totalRevenue'] ?? 0, 'money'),
                    ],
                    'rows' => array_map(fn ($r) => $row($r['productName'], "{$r['sellerName']} · Ref. {$r['sku']}", $r['revenue'], 'money', [
                        $detail('Cantidad'.$unit($r), $r['quantity']),
                    ]), $d['rows'] ?? []),
                    'options' => ['sellers' => $d['sellers'] ?? [], 'products' => $d['products'] ?? []],
                ];

            case 'product-seller':
                $s = $d['summary'] ?? [];

                return [
                    'kpis' => [
                        $kpi('Productos', $s['totalProducts'] ?? 0), $kpi('Unidades', $s['totalQuantity'] ?? 0, 'qty'),
                        $kpi('Ingresos', $s['totalRevenue'] ?? 0, 'money'),
                    ],
                    'rows' => collect($d['rows'] ?? [])->groupBy('sku')->map(fn ($sellers) => $row(
                        $sellers->first()['productName'],
                        'Ref. '.$sellers->first()['sku'].' · mejor: '.$sellers->sortBy('position')->first()['sellerName'],
                        $sellers->sum('revenue'), 'money', [],
                        false,
                        $sellers->sortBy('position')->map(fn ($r) => $row("#{$r['position']} {$r['sellerName']}", null, $r['revenue'], 'money', [
                            $detail('Cantidad'.$unit($r), $r['quantity']),
                        ], (bool) ($r['isTop'] ?? false)))->values()->all(),
                    ))->values()->all(),
                    'options' => ['products' => $d['products'] ?? []],
                ];

            case 'seller-sales':
                $t = $d['totals'] ?? [];
                $sellerRow = fn ($r, bool $total = false) => $row($total ? 'TOTAL' : $r['name'], $total ? null : ($r['sellerCode'] ?? null), $r['revenue'], 'money', [
                    $detail('Venta esperada', $r['expectedRevenue'], 'money'),
                    $detail('Cumpl. pesos', $pct($r['revenuePct']), 'pct'),
                    $detail($sold, $r['kilosSold']),
                    $detail("Ppto. {$qty}", $r['budgetKilos']),
                    $detail("Cumpl. {$qty}", $pct($r['kilosPct']), 'pct'),
                    $detail("Valor {$per} mes ant.", $r['avgKiloPrev'], 'money'),
                    $detail("Valor {$per} actual", $r['avgKiloCur'], 'money'),
                ], $total);

                return [
                    'subtitle' => isset($d['monthLabel']) ? "{$d['monthLabel']} · corte {$d['asOfDate']}" : null,
                    'kpis' => [
                        $kpi($sold, $t['kilosSold'] ?? 0, 'qty'), $kpi('Venta acumulada', $t['revenue'] ?? 0, 'money'),
                        $kpi('% Cump. pesos', $pct($t['revenuePct'] ?? null), 'pct'), $kpi('% Ideal a la fecha', $pct($d['idealPct'] ?? null), 'pct'),
                    ],
                    'rows' => array_map(fn ($r) => $sellerRow($r), $d['rows'] ?? []),
                    'total_row' => $t ? $sellerRow($t, true) : null,
                ];

            case 'vendor-product-sales':
                $sellers = $d['sellers'] ?? [];

                return [
                    'subtitle' => $d['periodLabel'] ?? null,
                    'kpis' => [
                        $kpi('Vendedores', count($sellers)), $kpi('Cantidad', $d['grandTotalQuantity'] ?? 0, 'qty'),
                        $kpi('Venta acumulada', $d['grandTotalNet'] ?? 0, 'money'),
                    ],
                    'rows' => array_map(fn ($s) => $row($s['name'], 'NIT '.$s['nit'].' · '.count($s['products'] ?? []).' productos', $s['totalNet'], 'money', [
                        $detail('Cantidad', $s['totalQuantity']),
                    ], false, array_map(fn ($p) => $row($p['descripcion'], 'Ref. '.$p['referencia'], $p['net'], 'money', [
                        $detail('Cantidad', $p['quantity']),
                    ]), $s['products'] ?? [])), $sellers),
                ];
        }

        return ['kpis' => [], 'rows' => []];
    }
}
