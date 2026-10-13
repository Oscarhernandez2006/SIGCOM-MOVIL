<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Database\Query\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class OrderController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    private const LIMIT = 300;

    /** Agrupación de estados para los filtros de la app. */
    private const STATUS_GROUPS = [
        'in_progress' => ['draft', 'pending_approval', 'pending_control', 'confirmed', 'syncing'],
        'synced' => ['synced'],
        'issues' => ['failed', 'bounced', 'disapproved', 'expired'],
        'cancelled' => ['cancelled'],
    ];

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
            'group' => ['nullable', 'in:'.implode(',', array_keys(self::STATUS_GROUPS))],
            'status' => ['nullable', 'in:'.implode(',', array_merge(...array_values(self::STATUS_GROUPS)))],
            'type' => ['nullable', 'in:corte,subproducto'],
            'search' => ['nullable', 'string', 'max:100'],
        ]);
        $this->authorizeCompany($request, $data['company']);

        $base = DB::table('orders as o')
            ->join('client_records as c', 'c.id', '=', 'o.customer_id')
            ->where('o.company_id', $data['company'])
            ->whereRaw('(o.created_at at time zone ?)::date between ? and ?', [
                self::TIMEZONE, $data['from'], $data['to'],
            ])
            ->when($request->user()->role === 'seller', fn ($q) => $q->where('o.seller_id', $request->user()->id))
            ->when($data['type'] ?? null, fn ($q, $type) => $q->where('o.type', $type))
            ->when($data['search'] ?? null, function (Builder $q, string $search) {
                $like = '%'.mb_strtolower(trim($search)).'%';
                $q->where(fn ($w) => $w
                    ->whereRaw('lower(c.name) like ?', [$like])
                    ->orWhereRaw('lower(coalesce(c.branch_name, \'\')) like ?', [$like])
                    ->orWhere('c.code', 'like', $like)
                    ->orWhere('o.order_number', 'like', $like)
                    ->orWhere('o.second_number', 'like', $like));
            });

        $byStatus = (clone $base)
            ->groupBy('o.status')
            ->selectRaw('o.status, count(*) as count, coalesce(sum(o.total), 0) as total')
            ->get()
            ->keyBy('status');

        $summary = [];
        foreach (self::STATUS_GROUPS as $group => $statuses) {
            $rows = $byStatus->only($statuses);
            $summary[$group] = ['count' => (int) $rows->sum('count'), 'total' => (float) $rows->sum('total')];
        }

        $orders = (clone $base)
            ->leftJoin('users as u', 'u.id', '=', 'o.seller_id')
            ->when($data['group'] ?? null, fn ($q, $group) => $q->whereIn('o.status', self::STATUS_GROUPS[$group]))
            ->when($data['status'] ?? null, fn ($q, $status) => $q->where('o.status', $status))
            ->orderByDesc('o.created_at')
            ->limit(self::LIMIT)
            ->select([
                'o.id', 'o.order_number', 'o.second_number', 'o.type', 'o.status', 'o.siesa_estado',
                'o.total', 'o.created_at', 'o.delivery_date', 'o.sync_error', 'o.approval_deadline',
                'o.disapproval_reason', 'o.cancel_reason', 'o.download_count',
                'o.linked_order_number', 'o.linked_second_number',
                'c.name as customer_name', 'c.code as customer_code', 'c.branch_name', 'c.city',
                'u.name as seller_name',
            ])
            ->selectSub(DB::table('order_items')->whereColumn('order_id', 'o.id')->selectRaw('count(*)'), 'items_count')
            ->get()
            ->map(fn ($o) => [
                'id' => $o->id,
                'number' => $o->order_number,
                'second_number' => $o->second_number,
                'type' => $o->type,
                'status' => $o->status,
                'siesa_status' => $o->siesa_estado,
                'total' => (float) $o->total,
                'items_count' => (int) $o->items_count,
                'customer' => [
                    'name' => $o->customer_name,
                    'code' => $o->customer_code,
                    'branch' => $o->branch_name ?? $o->city,
                ],
                'seller' => $o->seller_name,
                'created_at' => $this->iso($o->created_at),
                'delivery_date' => $o->delivery_date,
                'approval_deadline' => $this->iso($o->approval_deadline),
                'note' => $o->sync_error ?? $o->disapproval_reason ?? $o->cancel_reason,
                'download_count' => (int) $o->download_count,
                'linked_number' => $this->numbers($o->linked_order_number, $o->linked_second_number),
            ]);

        return response()->json([
            'orders' => $orders,
            'summary' => $summary,
            'limited' => $orders->count() >= self::LIMIT,
        ]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $order = DB::table('orders as o')
            ->join('client_records as c', 'c.id', '=', 'o.customer_id')
            ->leftJoin('users as u', 'u.id', '=', 'o.seller_id')
            ->where('o.id', $id)
            ->select([
                'o.*',
                'c.name as customer_name', 'c.code as customer_code', 'c.branch_name', 'c.branch',
                'c.price_list', 'c.payment_term', 'c.address', 'c.city', 'c.phone',
                'u.name as seller_name', 'u.document_id as seller_document',
            ])
            ->selectSub(
                DB::table('user_companies as uc')
                    ->whereColumn('uc.user_id', 'o.seller_id')
                    ->whereColumn('uc.company_id', 'o.company_id')
                    ->selectRaw("coalesce(nullif(trim(uc.siesa_seller_code), ''), u.siesa_seller_code)")
                    ->limit(1),
                'seller_code'
            )
            ->first();

        abort_unless($order, 404, 'Pedido no encontrado.');
        $this->authorizeCompany($request, $order->company_id);
        abort_if(
            $request->user()->role === 'seller' && $order->seller_id !== $request->user()->id,
            403,
            'No tienes acceso a este pedido.'
        );

        $items = DB::table('order_items')
            ->where('order_id', $id)
            ->orderBy('product_name')
            ->get(['sku', 'product_name', 'unit_of_measure', 'quantity', 'unit_price', 'discount_pct', 'tax_rate', 'line_total'])
            ->map(fn ($i) => [
                'sku' => $i->sku,
                'name' => $i->product_name,
                'unit' => $i->unit_of_measure,
                'quantity' => (float) $i->quantity,
                'unit_price' => (float) $i->unit_price,
                'discount_pct' => (float) $i->discount_pct,
                'tax_rate' => (float) $i->tax_rate,
                'total' => (float) $i->line_total,
            ]);

        return response()->json([
            'id' => $order->id,
            'number' => $order->order_number,
            'second_number' => $order->second_number,
            'type' => $order->type,
            'status' => $order->status,
            'siesa_status' => $order->siesa_estado,
            'subtotal' => (float) $order->subtotal,
            'taxes' => (float) $order->taxes,
            'total' => (float) $order->total,
            'notes' => $order->notes,
            'logistics_note' => $order->logistics_note,
            'delivery_type' => $order->delivery_type,
            'delivery_date' => $order->delivery_date,
            'delivery_schedule' => $order->delivery_schedule,
            'sync_error' => $order->sync_error,
            'cancel_reason' => $order->cancel_reason,
            'disapproval_reason' => $order->disapproval_reason,
            'approval_deadline' => $this->iso($order->approval_deadline),
            'created_at' => $this->iso($order->created_at),
            'synced_at' => $this->iso($order->synced_at),
            'seller' => $order->seller_name,
            // Trazabilidad (como el detalle de Administración de pedidos en la web).
            'tracking' => [
                'seller_document' => $order->seller_document,
                'seller_code' => $order->seller_code,
                'linked_number' => $this->numbers($order->linked_order_number, $order->linked_second_number),
                'cartera_balance' => $order->cartera_balance === null ? null : (float) $order->cartera_balance,
                'approved_by' => $order->approved_by,
                'approved_at' => $this->iso($order->approved_at),
                'siesa_previous_status' => $order->siesa_estado_previo,
                'siesa_document' => $order->siesa_document_id,
                'download_count' => (int) $order->download_count,
                'downloaded_at' => $this->iso($order->downloaded_at),
                'downloaded_by' => $order->downloaded_by,
            ],
            'customer' => [
                'name' => $order->customer_name,
                'code' => $order->customer_code,
                'branch' => $order->branch_name ?? $order->branch,
                'price_list' => $order->price_list,
                'payment_term' => $order->payment_term,
                'address' => $order->address,
                'city' => $order->city,
                'phone' => $order->phone,
            ],
            'items' => $items,
        ]);
    }

    private function numbers(?string $first, ?string $second): ?string
    {
        return $first ? '#'.$first.($second ? ' / #'.$second : '') : null;
    }

    private function authorizeCompany(Request $request, string $company): void
    {
        abort_unless(
            $request->user()->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );
    }

    private function iso(?string $value): ?string
    {
        return $value ? CarbonImmutable::parse($value)->setTimezone(self::TIMEZONE)->toIso8601String() : null;
    }
}
