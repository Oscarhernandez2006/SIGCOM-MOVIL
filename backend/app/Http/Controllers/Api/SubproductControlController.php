<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Controlador de subproductos: pedidos de subproducto en pending_control (y los failed para reintentar).
 * Lectura directa de la base; editar/aprobar/rechazar pasa por la web (stock, cartera y Siesa).
 */
class SubproductControlController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    public const PERMISSION = '/admin/controlador-subproductos';

    private const BASE = '/admin/controlador-subproductos/orders';

    public function __construct(private readonly SigcomWebClient $web) {}

    public function index(Request $request): JsonResponse
    {
        $company = $this->company($request);
        // La web lista los subproductos de todas las compañías: Agropecuaria y las virtuales sobre ella (Montería TAT).
        $companies = [$company, ...array_keys(array_filter(config('sigcom.erp_base_company'), fn ($base) => $base === $company))];

        $orders = DB::table('orders as o')
            ->join('client_records as c', 'c.id', '=', 'o.customer_id')
            ->leftJoin('users as u', 'u.id', '=', 'o.seller_id')
            ->whereIn('o.company_id', $companies)
            ->where('o.type', 'subproducto')
            ->whereIn('o.status', ['pending_control', 'failed'])
            ->orderBy('o.created_at')
            ->get([
                'o.id', 'o.company_id', 'o.order_number', 'o.second_number', 'o.status', 'o.total', 'o.created_at',
                'o.delivery_date', 'o.notes', 'o.logistics_note', 'o.sync_error',
                'c.name as customer_name', 'c.code as customer_code', 'c.branch_name', 'c.city',
                'c.price_list', 'c.payment_term', 'u.name as seller_name',
            ]);

        $items = DB::table('order_items')
            ->whereIn('order_id', $orders->pluck('id'))
            ->orderBy('product_name')
            ->get(['order_id', 'sku', 'product_name', 'unit_of_measure', 'quantity', 'unit_price', 'discount_pct', 'line_total'])
            ->groupBy('order_id');

        return response()->json($orders->map(fn ($o) => [
            'id' => $o->id,
            'company' => config('sigcom.companies')[$o->company_id]['name'] ?? $o->company_id,
            'number' => $o->order_number,
            'second_number' => $o->second_number,
            'status' => $o->status,
            'total' => (float) $o->total,
            'created_at' => $this->iso($o->created_at),
            'delivery_date' => $o->delivery_date,
            'notes' => $o->notes,
            'logistics_note' => $o->logistics_note,
            'sync_error' => $o->sync_error,
            'seller' => $o->seller_name,
            'customer' => [
                'name' => $o->customer_name,
                'code' => $o->customer_code,
                'branch' => $o->branch_name ?? $o->city,
                'price_list' => $o->price_list,
                'payment_term' => $o->payment_term,
            ],
            'items' => ($items[$o->id] ?? collect())->map(fn ($i) => [
                'sku' => $i->sku,
                'name' => $i->product_name,
                'unit' => $i->unit_of_measure,
                'quantity' => (float) $i->quantity,
                'unit_price' => (float) $i->unit_price,
                'discount_pct' => (float) $i->discount_pct,
                'total' => (float) $i->line_total,
            ])->values(),
        ])->values());
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'items' => ['required', 'array', 'min:1', 'max:200'],
            'items.*.sku' => ['required', 'string', 'max:50', 'distinct'],
            'items.*.quantity' => ['required', 'integer', 'min:1', 'max:100000'],
            'items.*.discount_pct' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'logistics_note' => ['nullable', 'string', 'max:1000'],
            'delivery_date' => ['nullable', 'date_format:Y-m-d'],
        ]);
        $company = $this->company($request);

        $order = $this->web->call($request->user(), $company, 'PATCH', self::BASE."/{$id}", array_filter([
            'items' => array_map(fn ($i) => [
                'sku' => $i['sku'],
                'quantity' => (int) $i['quantity'],
                'discountPct' => (float) ($i['discount_pct'] ?? 0),
            ], $data['items']),
            'notes' => $data['notes'] ?? null,
            'logisticsNote' => $data['logistics_note'] ?? null,
            'deliveryDate' => $data['delivery_date'] ?? null,
        ], fn ($v) => $v !== null));

        return response()->json($this->result($order));
    }

    public function approve(Request $request, string $id): JsonResponse
    {
        $order = $this->web->call($request->user(), $this->company($request), 'POST', self::BASE."/{$id}/approve");

        return response()->json($this->result($order));
    }

    public function reject(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:500']]);
        $reason = trim((string) ($data['reason'] ?? ''));
        $order = $this->web->call(
            $request->user(),
            $this->company($request),
            'POST',
            self::BASE."/{$id}/reject",
            $reason === '' ? [] : ['reason' => $reason],
        );

        return response()->json($this->result($order));
    }

    /** Igual que la web: admin o permiso del módulo global o en la compañía de subproductos. */
    public static function canControl(User $user): bool
    {
        if ($user->role === 'admin' || in_array(self::PERMISSION, $user->permissions ?? [], true)) {
            return true;
        }
        $permissions = $user->companies()
            ->where('company_id', config('sigcom.subproduct_company'))
            ->where('active', true)
            ->value('permissions');

        return in_array(self::PERMISSION, is_array($permissions) ? $permissions : (json_decode((string) $permissions, true) ?? []), true);
    }

    private function result(?array $order): array
    {
        return [
            'id' => $order['id'] ?? null,
            'status' => $order['status'] ?? null,
            'total' => (float) ($order['total'] ?? 0),
            'sync_error' => $order['syncError'] ?? null,
        ];
    }

    private function company(Request $request): string
    {
        $company = (string) $request->input('company', $request->query('company', ''));
        abort_unless(
            $company === config('sigcom.subproduct_company')
                && $request->user()->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );
        abort_unless(self::canControl($request->user()), 403, 'No tienes permiso para controlar subproductos.');

        return $company;
    }

    private function iso(?string $value): ?string
    {
        return $value ? CarbonImmutable::parse($value)->setTimezone(self::TIMEZONE)->toIso8601String() : null;
    }
}
