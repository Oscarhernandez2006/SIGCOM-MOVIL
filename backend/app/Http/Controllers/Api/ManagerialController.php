<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\SigcomWebClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Panel de control gerencial (General → Dashboard de la web): comparativo por
 * compañía y venta vs. pedido por vendedor. Solo administradores.
 */
class ManagerialController extends Controller
{
    /** La web excluye Montería TAT de este panel. */
    private const EXCLUDED_COMPANIES = ['MTAT'];

    public function __construct(private readonly SigcomWebClient $web)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
        $this->authorize($request, $data['company']);

        $stats = $this->web->call($request->user(), $data['company'], 'GET', '/admin/dashboard/managerial', [
            'from' => $data['from'],
            'to' => $data['to'],
        ]) ?? [];

        $companies = collect($stats['companies'] ?? [])
            ->reject(fn ($c) => in_array($c['companyId'] ?? null, self::EXCLUDED_COMPANIES, true))
            ->map(fn ($c) => $this->company($c))
            ->values();

        return response()->json(['from' => $data['from'], 'to' => $data['to'], 'companies' => $companies]);
    }

    public function sellers(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'period' => ['required', 'regex:/^\d{6}$/'],
            'date' => ['nullable', 'date_format:Y-m-d'],
        ]);
        $this->authorize($request, $data['company']);
        $user = $request->user();
        $query = array_filter([
            'periodo' => $data['period'],
            'fecha' => $data['date'] ?? null,
            'companyId' => $data['company'],
        ]);

        $sales = $this->web->call($user, $data['company'], 'GET', '/admin/reports/vendor-product-sales/data', $query) ?? [];
        $orders = $this->web->call($user, $data['company'], 'GET', '/admin/reports/orders-by-seller/data', $query) ?? [];

        return response()->json([
            'period_label' => $sales['periodLabel'] ?? $orders['periodLabel'] ?? $data['period'],
            'sales' => [
                'total' => (float) ($sales['grandTotalNet'] ?? 0),
                'sellers' => collect($sales['sellers'] ?? [])->map(fn ($s) => [
                    'name' => $s['name'] ?? '—',
                    'total' => (float) ($s['totalNet'] ?? 0),
                ])->values(),
            ],
            'orders' => [
                'total' => (float) ($orders['grandTotal'] ?? 0),
                'count' => (int) ($orders['grandOrders'] ?? 0),
                'sellers' => collect($orders['sellers'] ?? [])->map(fn ($s) => [
                    'name' => $s['name'] ?? '—',
                    'total' => (float) ($s['total'] ?? 0),
                    'orders' => (int) ($s['orders'] ?? 0),
                ])->sortByDesc('total')->values(),
            ],
        ]);
    }

    private function company(array $c): array
    {
        $margin = $c['margin'] ?? null;
        $totals = $c['totals'] ?? [];

        return [
            'id' => $c['companyId'],
            'name' => $c['name'] ?? $c['companyId'],
            'unit' => config('sigcom.companies')[$c['companyId']]['unit'] ?? 'kg',
            'totals' => [
                'revenue' => (float) ($totals['revenue'] ?? 0),
                'orders' => (int) ($totals['orders'] ?? 0),
                'units' => (float) ($totals['units'] ?? 0),
                'avg_ticket' => (float) ($totals['avgTicket'] ?? 0),
                'customers' => (int) ($totals['customers'] ?? 0),
            ],
            // Con un solo día la web devuelve la tendencia por hora ("YYYY-MM-DDTHH:00" + label).
            'trend' => collect($c['salesTrend'] ?? [])->map(fn ($p) => [
                'date' => (string) $p['date'],
                'label' => $p['label'] ?? null,
                'revenue' => (float) ($p['revenue'] ?? 0),
            ])->values(),
            'top_products' => collect($c['topProducts'] ?? [])->map(fn ($p) => [
                'name' => $p['name'] ?? $p['sku'] ?? '—',
                'quantity' => (float) ($p['quantity'] ?? 0),
                'revenue' => (float) ($p['revenue'] ?? 0),
            ])->values(),
            'top_customers' => collect($c['topCustomers'] ?? [])->map(fn ($p) => [
                'name' => $p['name'] ?? '—',
                'code' => $p['code'] ?? null,
                'orders' => (int) ($p['orders'] ?? 0),
                'revenue' => (float) ($p['revenue'] ?? 0),
            ])->values(),
            'top_sellers' => collect($c['topSellers'] ?? [])->map(fn ($p) => [
                'name' => $p['name'] ?? '—',
                'orders' => (int) ($p['orders'] ?? 0),
                'revenue' => (float) ($p['revenue'] ?? 0),
            ])->values(),
            'margin' => $margin ? [
                'revenue' => (float) ($margin['revenue'] ?? 0),
                'cost' => (float) ($margin['cost'] ?? 0),
                'profit' => (float) ($margin['profit'] ?? 0),
                'margin_pct' => (float) ($margin['marginPct'] ?? 0),
                'kilos' => (float) ($margin['kilos'] ?? 0),
                'by_seller' => collect($margin['bySeller'] ?? [])->map(fn ($s) => [
                    'name' => $s['name'] ?? '—',
                    'revenue' => (float) ($s['revenue'] ?? 0),
                    'profit' => (float) ($s['profit'] ?? 0),
                    'margin_pct' => (float) ($s['marginPct'] ?? 0),
                    'kilos' => (float) ($s['kilos'] ?? 0),
                ])->values(),
                'by_product' => collect($margin['byProduct'] ?? [])->map(fn ($p) => [
                    'name' => $p['name'] ?? $p['ref'] ?? '—',
                    'revenue' => (float) ($p['revenue'] ?? 0),
                    'profit' => (float) ($p['profit'] ?? 0),
                    'margin_pct' => (float) ($p['marginPct'] ?? 0),
                ])->values(),
            ] : null,
        ];
    }

    private function authorize(Request $request, string $company): void
    {
        $user = $request->user();
        abort_unless($user->role === 'admin', 403, 'El panel de control es solo para administradores.');
        abort_unless(
            $user->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );
    }
}
