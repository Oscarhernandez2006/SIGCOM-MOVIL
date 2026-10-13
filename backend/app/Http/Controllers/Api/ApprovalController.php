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
 * Aprobación de cartera: pedidos retenidos (pending_approval) por saldo del cliente.
 * La lectura va directo a la base; aprobar/desaprobar pasa por la web (sube a Siesa y libera stock).
 */
class ApprovalController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    public const PERMISSION = '/admin/cartera';

    public function __construct(private readonly SigcomWebClient $web) {}

    public function index(Request $request): JsonResponse
    {
        $company = $this->company($request);

        $orders = DB::table('orders as o')
            ->join('client_records as c', 'c.id', '=', 'o.customer_id')
            ->leftJoin('users as u', 'u.id', '=', 'o.seller_id')
            ->where('o.company_id', $company)
            ->where('o.status', 'pending_approval')
            ->orderBy('o.approval_deadline')
            ->get([
                'o.id', 'o.order_number', 'o.second_number', 'o.type', 'o.total', 'o.cartera_balance',
                'o.created_at', 'o.approval_deadline', 'o.delivery_date', 'o.notes',
                'c.name as customer_name', 'c.code as customer_code', 'c.branch_name', 'c.city',
                'c.payment_term', 'u.name as seller_name',
            ]);

        $items = DB::table('order_items')
            ->whereIn('order_id', $orders->pluck('id'))
            ->orderBy('product_name')
            ->get(['order_id', 'sku', 'product_name', 'unit_of_measure', 'quantity', 'unit_price', 'discount_pct', 'line_total'])
            ->groupBy('order_id');

        return response()->json([
            'server_time' => CarbonImmutable::now(self::TIMEZONE)->toIso8601String(),
            'orders' => $orders->map(fn ($o) => [
                'id' => $o->id,
                'number' => $o->order_number,
                'second_number' => $o->second_number,
                'type' => $o->type,
                'total' => (float) $o->total,
                'cartera_balance' => $o->cartera_balance === null ? null : (float) $o->cartera_balance,
                'created_at' => $this->iso($o->created_at),
                'approval_deadline' => $this->iso($o->approval_deadline),
                'delivery_date' => $o->delivery_date,
                'notes' => $o->notes,
                'seller' => $o->seller_name,
                'customer' => [
                    'name' => $o->customer_name,
                    'code' => $o->customer_code,
                    'branch' => $o->branch_name ?? $o->city,
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
            ])->values(),
        ]);
    }

    public function approve(Request $request, string $id): JsonResponse
    {
        $company = $this->company($request);
        $order = $this->web->call($request->user(), $company, 'POST', "/cartera/orders/{$id}/approve");

        return response()->json($this->result($order));
    }

    public function disapprove(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:500']]);
        $company = $this->company($request);
        $reason = trim((string) ($data['reason'] ?? ''));
        $order = $this->web->call(
            $request->user(),
            $company,
            'POST',
            "/cartera/orders/{$id}/disapprove",
            $reason === '' ? [] : ['reason' => $reason],
        );

        return response()->json($this->result($order));
    }

    /** Igual que la web: admin, rol cartera o permiso /admin/cartera en la compañía. */
    public static function canApprove(User $user, ?array $permissions): bool
    {
        return in_array($user->role, ['admin', 'cartera'], true)
            || in_array(self::PERMISSION, $permissions ?? [], true);
    }

    private function result(?array $order): array
    {
        return [
            'id' => $order['id'] ?? null,
            'status' => $order['status'] ?? null,
            'sync_error' => $order['syncError'] ?? null,
            'disapproval_reason' => $order['disapprovalReason'] ?? null,
        ];
    }

    private function company(Request $request): string
    {
        $company = (string) $request->input('company', $request->query('company', ''));
        $access = $company === '' ? null : $request->user()->companies()
            ->where('company_id', $company)
            ->where('active', true)
            ->first();

        abort_unless($access, 403, 'No tienes acceso a esta compañía.');
        abort_unless(self::canApprove($request->user(), $access->permissions), 403, 'No tienes permiso para aprobar cartera.');

        return $company;
    }

    private function iso(?string $value): ?string
    {
        return $value ? CarbonImmutable::parse($value)->setTimezone(self::TIMEZONE)->toIso8601String() : null;
    }
}
