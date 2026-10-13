<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ErpSalesService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use RuntimeException;

class DashboardController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    private const EXCLUDED_ORDER_STATUSES = ['draft', 'cancelled', 'disapproved', 'expired'];

    public function __construct(private readonly ErpSalesService $erp)
    {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'seller' => ['nullable', 'uuid'],
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
            'national' => ['nullable', 'boolean'],
        ]);

        $user = $request->user();
        $company = $data['company'];

        abort_unless(
            $user->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );

        $national = (bool) ($data['national'] ?? false);
        if ($national) {
            abort_unless($user->role === 'admin', 403, 'Negocios nacionales es solo para administradores.');
            $nationalSeller = DB::table('users')
                ->where(DB::raw('trim(document_id)'), config('sigcom.national_business_seller_doc'))
                ->first(['id', 'name']);
            abort_unless($nationalSeller, 404, 'No hay un vendedor de negocios nacionales configurado.');
        }

        $sellerId = $national ? $nationalSeller->id : ($user->role === 'seller' ? $user->id : ($data['seller'] ?? null));
        $from = CarbonImmutable::parse($data['from'], self::TIMEZONE);
        $to = CarbonImmutable::parse($data['to'], self::TIMEZONE);

        $sellers = $national ? collect() : $this->sellers($company);
        $budget = $national ? $this->clientBudgetTotals($company, $sellerId, $from) : $this->budget($company, $sellerId, $from);
        $orders = $this->orders($company, $sellerId, $from, $to);
        $workingDays = $this->workingDays($company, $from, $to);

        $erp = null;
        $erpError = null;
        $salesSource = 'erp';
        if (in_array($company, config('sigcom.erp_sales_companies'), true)) {
            try {
                $erp = $this->erpSales($company, $sellerId, $from, $to);
            } catch (RuntimeException $e) {
                $erpError = $e->getMessage();
            }
        } else {
            // Montería TAT no tiene consulta de facturación propia: la web usa los pedidos de la app.
            $erp = $this->orderSales($company, $sellerId, $from, $to, $orders);
            $salesSource = 'orders';
        }
        $sales = $erp['sales'] ?? null;
        $singleDay = $from->equalTo($to);
        $buying = $national ? [] : $this->buyingCustomers($company, $sellerId, $from, $to);

        return response()->json([
            'seller' => $national ? ['id' => $nationalSeller->id, 'name' => $nationalSeller->name] : ($sellerId ? $sellers->firstWhere('id', $sellerId) : null),
            'sellers' => $user->role === 'seller' ? [] : $sellers->values(),
            'budget' => $budget,
            'sales' => $sales,
            'sales_source' => $salesSource,
            'sales_error' => $erpError,
            'compliance' => $sales ? [
                'revenue' => $this->ratio($sales['revenue'], $budget['revenue']),
                'kilos' => $this->ratio($sales['kilos'], $budget['kilos']),
            ] : null,
            'projection' => $sales && ! $singleDay && $workingDays['elapsed'] > 0 ? [
                'revenue' => $sales['revenue'] / $workingDays['elapsed'] * $workingDays['total'],
                'kilos' => $sales['kilos'] / $workingDays['elapsed'] * $workingDays['total'],
            ] : null,
            'profitability' => $erp['profitability'] ?? null,
            'growth' => $erp['growth'] ?? null,
            'trend' => $erp['trend'] ?? [],
            'categories' => $erp['categories'] ?? [],
            'orders' => $orders,
            'top_customers' => $buying,
            'customers_not_buying' => $national ? [] : $this->customersNotBuying($company, $sellerId, array_column($buying, 'code')),
            'client_budgets' => $national ? $this->clientBudgets($company, $sellerId, $from, $to) : null,
            'working_days' => $workingDays,
            'unit' => config('sigcom.companies')[$company]['unit'] ?? 'kg',
            'generated_at' => now(self::TIMEZONE)->toIso8601String(),
        ]);
    }

    private function erpSales(string $company, ?string $sellerId, CarbonImmutable $from, CarbonImmutable $to): array
    {
        $excludedDocs = config('sigcom.dashboard_excluded_seller_docs');
        if ($sellerId) {
            $nit = trim((string) DB::table('users')->where('id', $sellerId)->value('document_id'));
            $nits = $nit !== '' ? [$nit] : ['__sin_documento__'];
            $exclude = ['nits' => [], 'names' => []];
        } else {
            $nits = [];
            $names = DB::table('users')->whereIn(DB::raw('trim(document_id)'), $excludedDocs)->pluck('name');
            $exclude = [
                'nits' => $excludedDocs,
                'names' => $names->map(fn ($n) => mb_strtoupper(trim($n)))->push('INVERSIONES SERRANO MILLAN')->all(),
            ];
        }

        $days = $from->diffInDays($to) + 1;
        $prevTo = $from->subDay();
        $prevFrom = $prevTo->subDays($days - 1);

        $current = $this->erp->summary($company, $nits, $exclude, $from->toDateString(), $to->toDateString());
        $previous = $this->erp->summary($company, $nits, $exclude, $prevFrom->toDateString(), $prevTo->toDateString());
        $detailRevenue = $current['revenue'];

        // Carnes Frías: en meses completos la venta y las unidades salen de Inversiones (igual que la web).
        if ($company === '8') {
            $sellerName = $sellerId ? DB::table('users')->where('id', $sellerId)->value('name') : null;
            foreach ([[&$current, $from, $to], [&$previous, $prevFrom, $prevTo]] as [&$summary, $start, $end]) {
                $totals = $this->erp->inversionesTotals($start->toDateString(), $end->toDateString(), $sellerName, $exclude['names']);
                if ($totals) {
                    $summary['revenue'] = $totals['revenue'];
                    $summary['kilos'] = $totals['kilos'];
                }
            }
            unset($summary);
        }

        $margin = $detailRevenue - $current['cost'];

        return [
            'sales' => ['revenue' => $current['revenue'], 'kilos' => $current['kilos']],
            'profitability' => $current['cost'] > 0 ? [
                'cost' => $current['cost'],
                'margin' => $margin,
                'margin_pct' => $this->ratio($margin, $detailRevenue),
            ] : null,
            'growth' => [
                'revenue' => $this->growth($current['revenue'], $previous['revenue']),
                'kilos' => $this->growth($current['kilos'], $previous['kilos']),
            ],
            'trend' => $this->trend($current['by_day'], $from, $to),
            'categories' => $current['categories'],
        ];
    }

    /** Ventas, crecimiento y tendencia a partir de los pedidos de la app (compañías sin facturación ERP). */
    private function orderSales(string $company, ?string $sellerId, CarbonImmutable $from, CarbonImmutable $to, array $current): array
    {
        $days = $from->diffInDays($to) + 1;
        $prevTo = $from->subDay();
        $previous = $this->orders($company, $sellerId, $prevTo->subDays($days - 1), $prevTo);

        [$trendFrom, $trendTo] = $from->equalTo($to) ? [$from->startOfMonth(), $from->endOfMonth()->startOfDay()] : [$from, $to];
        $byDay = DB::table('orders as o')
            ->where('o.company_id', $company)
            ->whereNotIn('o.status', self::EXCLUDED_ORDER_STATUSES)
            ->whereRaw('(o.created_at at time zone ?)::date between ? and ?', [
                self::TIMEZONE, $trendFrom->toDateString(), $trendTo->toDateString(),
            ])
            ->when($sellerId, fn ($q) => $q->where('o.seller_id', $sellerId))
            ->groupByRaw('1')
            ->selectRaw('((o.created_at at time zone ?)::date)::text as day, coalesce(sum(o.total), 0) as revenue', [self::TIMEZONE])
            ->pluck('revenue', 'day')
            ->map(fn ($v) => (float) $v)
            ->all();

        return [
            'sales' => ['revenue' => $current['revenue'], 'kilos' => $current['kilos']],
            'profitability' => null,
            'growth' => [
                'revenue' => $this->growth($current['revenue'], $previous['revenue']),
                'kilos' => $this->growth($current['kilos'], $previous['kilos']),
            ],
            'trend' => $this->trend($byDay, $from, $to),
            'categories' => [],
        ];
    }

    /** Venta diaria; con un solo día se grafica el mes completo, igual que en la web. */
    private function trend(array $byDay, CarbonImmutable $from, CarbonImmutable $to): array
    {
        if ($from->equalTo($to)) {
            [$from, $to] = [$from->startOfMonth(), $from->endOfMonth()->startOfDay()];
        }
        $end = $to->min(CarbonImmutable::today(self::TIMEZONE));

        $trend = [];
        for ($day = $from; $day <= $end && count($trend) < 400; $day = $day->addDay()) {
            $key = $day->toDateString();
            $trend[] = ['date' => $key, 'revenue' => $byDay[$key] ?? 0];
        }

        return $trend;
    }

    private function buyingCustomers(string $company, ?string $sellerId, CarbonImmutable $from, CarbonImmutable $to): array
    {
        return DB::table('orders as o')
            ->join('client_records as c', 'c.id', '=', 'o.customer_id')
            ->where('o.company_id', $company)
            ->whereNotIn('o.status', self::EXCLUDED_ORDER_STATUSES)
            ->whereRaw('(o.created_at at time zone ?)::date between ? and ?', [
                self::TIMEZONE, $from->toDateString(), $to->toDateString(),
            ])
            ->when($sellerId, fn ($q) => $q->where('o.seller_id', $sellerId))
            ->groupBy('c.code', 'c.name')
            ->orderByDesc('revenue')
            ->limit(500)
            ->selectRaw('c.name, c.code, min(c.branch_name) as branch_name, min(c.branch) as branch, min(c.city) as city, count(*) as orders, coalesce(sum(o.total), 0) as revenue, max(o.created_at) as last_purchase')
            ->get()
            ->map(fn ($c) => $this->customerRow($c, (int) $c->orders, (float) $c->revenue))
            ->all();
    }

    /** Clientes de la cartera (por código de vendedor Siesa) sin compras en el periodo; primero los más olvidados. */
    private function customersNotBuying(string $company, ?string $sellerId, array $boughtCodes): array
    {
        $codes = DB::table('user_companies as uc')
            ->join('users as u', 'u.id', '=', 'uc.user_id')
            ->where('uc.company_id', $company)
            ->where('uc.active', true)
            ->when(
                $sellerId,
                fn ($q) => $q->where('u.id', $sellerId),
                fn ($q) => $q->where('u.active', true)
                    ->where('u.role', 'seller')
                    ->whereNotIn(DB::raw('trim(coalesce(u.document_id, \'\'))'), config('sigcom.dashboard_excluded_seller_docs')),
            )
            ->selectRaw("trim(coalesce(nullif(trim(uc.siesa_seller_code), ''), u.siesa_seller_code, '')) as code")
            ->pluck('code')
            ->filter()
            ->unique()
            ->values();

        if ($codes->isEmpty()) {
            return [];
        }

        $bought = array_flip($boughtCodes);

        return DB::table('client_records as c')
            ->leftJoin('orders as o', function ($join) {
                $join->on('o.customer_id', '=', 'c.id')->whereNotIn('o.status', self::EXCLUDED_ORDER_STATUSES);
            })
            ->where('c.company_id', config('sigcom.erp_base_company')[$company] ?? $company)
            ->whereIn('c.seller_code', $codes)
            ->groupBy('c.code', 'c.name')
            ->selectRaw('c.name, c.code, min(c.branch_name) as branch_name, min(c.branch) as branch, min(c.city) as city, max(o.created_at) as last_purchase')
            ->get()
            ->reject(fn ($c) => isset($bought[$c->code]))
            ->sortBy(fn ($c) => $c->last_purchase ?? '')
            ->take(300)
            ->map(fn ($c) => $this->customerRow($c, 0, 0))
            ->values()
            ->all();
    }

    private function customerRow(object $c, int $orders, float $revenue): array
    {
        return [
            'name' => $c->name,
            'code' => $c->code,
            'branch' => $c->branch_name ?? $c->branch,
            'city' => $c->city,
            'orders' => $orders,
            'revenue' => $revenue,
            'last_purchase' => $c->last_purchase ? CarbonImmutable::parse($c->last_purchase)->toIso8601String() : null,
        ];
    }

    private function growth(float $current, float $previous): ?float
    {
        return $previous > 0 ? ($current - $previous) / $previous : null;
    }

    private function sellers(string $company)
    {
        return DB::table('users as u')
            ->join('user_companies as uc', 'uc.user_id', '=', 'u.id')
            ->where('uc.company_id', $company)
            ->where('uc.active', true)
            ->where('u.active', true)
            ->where('u.role', 'seller')
            ->whereNotIn(DB::raw('trim(coalesce(u.document_id, \'\'))'), config('sigcom.dashboard_excluded_seller_docs'))
            ->orderBy('u.name')
            ->get(['u.id', 'u.name']);
    }

    /** Presupuesto del vendedor "por cliente": suma de las metas por tienda del mes (igual que la web). */
    private function clientBudgetTotals(string $company, string $sellerId, CarbonImmutable $from): array
    {
        $row = DB::table('client_budgets')
            ->where('company_id', $company)
            ->where('seller_id', $sellerId)
            ->where('month', $from->month)
            ->where('year', $from->year)
            ->selectRaw('coalesce(sum(expected_revenue), 0) as revenue, coalesce(sum(target_kilos), 0) as kilos')
            ->first();

        return ['revenue' => (float) $row->revenue, 'kilos' => (float) $row->kilos];
    }

    /**
     * Meta vs. venta por cliente/tienda: clientes de la cartera del vendedor (una
     * fila por NIT) con su meta del mes y la venta facturada en Siesa (cualquier canal).
     */
    private function clientBudgets(string $company, string $sellerId, CarbonImmutable $from, CarbonImmutable $to): array
    {
        $seller = DB::table('users as u')
            ->leftJoin('user_companies as uc', fn ($j) => $j->on('uc.user_id', '=', 'u.id')->where('uc.company_id', $company))
            ->where('u.id', $sellerId)
            ->selectRaw("trim(coalesce(nullif(trim(uc.siesa_seller_code), ''), u.siesa_seller_code, '')) as code, trim(u.document_id) as nit")
            ->first();
        if (! $seller || $seller->code === '') {
            return [];
        }

        $targets = DB::table('client_budgets')
            ->where('company_id', $company)
            ->where('seller_id', $sellerId)
            ->where('month', $from->month)
            ->where('year', $from->year)
            ->get(['client_code', 'expected_revenue', 'target_kilos'])
            ->keyBy(fn ($b) => trim($b->client_code));

        $baseCompany = config('sigcom.erp_base_company')[$company] ?? $company;
        try {
            $revenue = $this->erp->clientSales($baseCompany, $seller->nit, $from->toDateString(), $to->toDateString());
        } catch (RuntimeException) {
            $revenue = [];
        }

        return DB::table('client_records')
            ->where('company_id', $baseCompany)
            ->where('seller_code', $seller->code)
            ->orderBy('name')
            ->get(['code', 'name', 'branch', 'branch_name'])
            ->unique(fn ($c) => trim($c->code))
            ->map(function ($c) use ($targets, $revenue) {
                $code = trim($c->code);
                $target = (float) ($targets[$code]->expected_revenue ?? 0);
                $sold = (float) ($revenue[$code] ?? 0);

                return [
                    'code' => $code,
                    'name' => $c->name,
                    'branch' => $c->branch_name ?? $c->branch,
                    'target_revenue' => $target,
                    'target_kilos' => (float) ($targets[$code]->target_kilos ?? 0),
                    'revenue' => $sold,
                    'compliance' => $this->ratio($sold, $target),
                ];
            })
            ->values()
            ->all();
    }

    private function budget(string $company, ?string $sellerId, CarbonImmutable $from): array
    {
        $row = DB::table('budgets')
            ->where('company_id', $company)
            ->where('month', $from->month)
            ->where('year', $from->year)
            ->when($sellerId, fn ($q) => $q->where('seller_id', $sellerId))
            ->selectRaw('coalesce(sum(expected_revenue), 0) as revenue, coalesce(sum(target_kilos), 0) as kilos')
            ->first();

        return ['revenue' => (float) $row->revenue, 'kilos' => (float) $row->kilos];
    }

    private function orders(string $company, ?string $sellerId, CarbonImmutable $from, CarbonImmutable $to): array
    {
        $orders = DB::table('orders as o')
            ->where('o.company_id', $company)
            ->whereNotIn('o.status', self::EXCLUDED_ORDER_STATUSES)
            ->whereRaw('(o.created_at at time zone ?)::date between ? and ?', [
                self::TIMEZONE, $from->toDateString(), $to->toDateString(),
            ])
            ->when($sellerId, fn ($q) => $q->where('o.seller_id', $sellerId));

        $totals = (clone $orders)
            ->selectRaw('count(*) as count, coalesce(sum(o.total), 0) as revenue, count(distinct o.customer_id) as customers')
            ->first();

        $kilos = DB::table('order_items')
            ->whereIn('order_id', (clone $orders)->select('o.id'))
            ->where('unit_of_measure', 'KG')
            ->sum('quantity');

        return [
            'count' => (int) $totals->count,
            'revenue' => (float) $totals->revenue,
            'kilos' => (float) $kilos,
            'customers' => (int) $totals->customers,
            'avg_ticket' => $totals->count > 0 ? (float) $totals->revenue / $totals->count : 0,
        ];
    }

    private function workingDays(string $company, CarbonImmutable $from, CarbonImmutable $to): array
    {
        $projection = DB::table('projections')
            ->where('company_id', $company)
            ->where('month', $from->month)
            ->where('year', $from->year)
            ->orderByDesc('updated_at')
            ->first();

        $days = $projection ? json_decode($projection->working_days, true) ?? [] : [];
        $cutoff = $to->min(CarbonImmutable::today(self::TIMEZONE))->toDateString();

        return [
            'total' => count($days),
            'elapsed' => count(array_filter($days, fn (string $day) => $day <= $cutoff)),
        ];
    }

    private function ratio(float $value, float $target): ?float
    {
        return $target > 0 ? $value / $target : null;
    }
}
