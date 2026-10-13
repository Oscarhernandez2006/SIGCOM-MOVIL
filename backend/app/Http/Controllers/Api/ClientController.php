<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Catálogo › Clientes (web /admin/clientes): maestro de clientes de Siesa por sucursal,
 * con su vendedor, la ubicación capturada en la toma de pedidos y su actividad reciente.
 */
class ClientController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    private const PAGE = 40;

    public const PERMISSION = '/admin/clientes';

    public function __construct(private readonly SigcomWebClient $web) {}

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'search' => ['nullable', 'string', 'max:100'],
            'seller' => ['nullable', 'string', 'max:20'],
            'page' => ['nullable', 'integer', 'min:1', 'max:1000'],
        ]);
        $company = $this->company($request);
        $page = (int) ($data['page'] ?? 1);

        $query = DB::table('client_records as c')
            ->where('c.company_id', $this->baseCompany($company))
            ->when($data['seller'] ?? null, fn ($q, $seller) => $seller === 'none'
                ? $q->where(fn ($w) => $w->whereNull('c.seller_code')->orWhere('c.seller_code', ''))
                : $q->where('c.seller_code', $seller))
            ->when(trim((string) ($data['search'] ?? '')), function ($q, string $search) {
                $like = '%'.mb_strtolower($search).'%';
                $q->where(fn ($w) => $w
                    ->whereRaw('lower(c.name) like ?', [$like])
                    ->orWhereRaw("lower(coalesce(c.branch_name, '')) like ?", [$like])
                    ->orWhere('c.code', 'like', $like));
            });

        $total = (clone $query)->count();
        $sellers = $this->sellerNames($company);
        $lists = $this->listNames($company);

        $clients = $query
            ->orderBy('c.name')
            ->orderBy('c.branch')
            ->offset(($page - 1) * self::PAGE)
            ->limit(self::PAGE)
            ->get(['c.id', 'c.code', 'c.name', 'c.branch', 'c.branch_name', 'c.city', 'c.price_list', 'c.seller_code', 'c.phone'])
            ->map(fn ($c) => [
                'id' => $c->id,
                'code' => $c->code,
                'name' => $c->name,
                'branch' => $c->branch,
                'branch_name' => $this->clean($c->branch_name),
                'city' => $c->city,
                'price_list' => $c->price_list,
                'price_list_name' => $lists[$c->price_list] ?? null,
                'seller_code' => $c->seller_code,
                'seller' => $sellers[$c->seller_code] ?? null,
                'phone' => $c->phone,
            ]);

        return response()->json([
            'clients' => $clients,
            'total' => $total,
            'page' => $page,
            'has_more' => $page * self::PAGE < $total,
            'can_sync' => $request->user()->role === 'admin',
        ]);
    }

    /** Vendedores con clientes asignados, para el filtro. */
    public function sellers(Request $request): JsonResponse
    {
        $company = $this->company($request);
        $names = $this->sellerNames($company);

        $rows = DB::table('client_records')
            ->where('company_id', $this->baseCompany($company))
            ->groupBy('seller_code')
            ->selectRaw("coalesce(nullif(trim(seller_code), ''), 'none') as code, count(*) as clients")
            ->get()
            ->map(fn ($r) => [
                'code' => $r->code,
                'name' => $r->code === 'none' ? 'Sin vendedor' : ($names[$r->code] ?? 'Vendedor '.$r->code),
                'clients' => (int) $r->clients,
            ])
            ->sortBy('name')
            ->values();

        return response()->json($rows);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $company = $this->company($request);
        $client = DB::table('client_records')->where('id', $id)->where('company_id', $this->baseCompany($company))->first();
        abort_unless($client, 404, 'Cliente no encontrado.');

        $locations = DB::table('client_seller_info as i')
            ->leftJoin('users as u', 'u.id', '=', 'i.seller_id')
            ->where('i.customer_id', $id)
            ->orderByDesc('i.updated_at')
            ->get(['i.direccion', 'i.referencia', 'i.barrio', 'i.ciudad', 'i.departamento', 'i.telefono', 'i.updated_at', 'u.name as seller'])
            ->map(fn ($l) => [
                'address' => $l->direccion,
                'reference' => $l->referencia,
                'neighborhood' => $l->barrio,
                'city' => $l->ciudad,
                'department' => $l->departamento,
                'phone' => $l->telefono,
                'seller' => $l->seller,
                'updated_at' => $this->iso($l->updated_at),
            ]);

        $orders = DB::table('orders as o')
            ->leftJoin('users as u', 'u.id', '=', 'o.seller_id')
            ->where('o.customer_id', $id)
            ->where('o.company_id', $company);
        $since = CarbonImmutable::now(self::TIMEZONE)->subDays(90)->startOfDay();
        $stats = (clone $orders)
            ->whereNotIn('o.status', ['cancelled', 'disapproved', 'expired'])
            ->where('o.created_at', '>=', $since)
            ->selectRaw('count(*) as count, coalesce(sum(o.total), 0) as total')
            ->first();
        $recent = (clone $orders)
            ->orderByDesc('o.created_at')
            ->limit(5)
            ->get(['o.id', 'o.order_number', 'o.second_number', 'o.status', 'o.total', 'o.created_at', 'u.name as seller'])
            ->map(fn ($o) => [
                'id' => $o->id,
                'number' => $o->order_number,
                'second_number' => $o->second_number,
                'status' => $o->status,
                'total' => (float) $o->total,
                'created_at' => $this->iso($o->created_at),
                'seller' => $o->seller,
            ]);

        return response()->json([
            'id' => $client->id,
            'code' => $client->code,
            'name' => $client->name,
            'branch' => $client->branch,
            'branch_name' => $this->clean($client->branch_name),
            'price_list' => $client->price_list,
            'price_list_name' => $this->listNames($company)[$client->price_list] ?? null,
            'payment_term' => $client->payment_term,
            'seller_code' => $client->seller_code,
            'seller' => $this->sellerNames($company)[$client->seller_code] ?? null,
            'address' => $client->address,
            'neighborhood' => $client->neighborhood,
            'city' => $client->city,
            'department' => $client->department,
            'phone' => $client->phone,
            'email' => $client->email,
            'delivery_schedule' => is_string($client->delivery_schedule)
                ? json_decode($client->delivery_schedule, true)
                : $client->delivery_schedule,
            'locations' => $locations,
            'orders_90d' => ['count' => (int) $stats->count, 'total' => (float) $stats->total],
            'recent_orders' => $recent,
        ]);
    }

    /** Trae los clientes de Siesa a través de la web (solo administradores). */
    public function sync(Request $request): JsonResponse
    {
        $company = $this->company($request);
        abort_unless($request->user()->role === 'admin', 403, 'Solo un administrador puede sincronizar los clientes.');
        $result = $this->web->call($request->user(), $company, 'POST', '/clients/sync') ?? [];

        return response()->json([
            'created' => (int) ($result['created'] ?? 0),
            'updated' => (int) ($result['updated'] ?? 0),
            'removed' => (int) ($result['removed'] ?? 0),
            'total' => (int) ($result['total'] ?? 0),
        ]);
    }

    /** Igual que la web: admin o permiso /admin/clientes en la compañía. */
    public static function canView(User $user, ?array $permissions): bool
    {
        return $user->role === 'admin' || in_array(self::PERMISSION, $permissions ?? [], true);
    }

    /** Código Siesa de vendedor => nombre; prioriza el código de la compañía, luego el de otras y el global. */
    private function sellerNames(string $company): Collection
    {
        $global = DB::table('users')
            ->whereRaw("nullif(trim(siesa_seller_code), '') is not null")
            ->selectRaw('trim(siesa_seller_code) as code, name')
            ->pluck('name', 'code');
        $byCompany = DB::table('user_companies as uc')
            ->join('users as u', 'u.id', '=', 'uc.user_id')
            ->whereRaw("nullif(trim(uc.siesa_seller_code), '') is not null")
            ->orderByRaw('case when uc.company_id = ? then 2 when uc.company_id = ? then 1 else 0 end', [
                $company, $this->baseCompany($company),
            ])
            ->selectRaw('trim(uc.siesa_seller_code) as code, u.name')
            ->pluck('name', 'code');

        return $global->merge($byCompany);
    }

    private function listNames(string $company): Collection
    {
        return DB::table('price_list_items')
            ->where('company_id', $this->baseCompany($company))
            ->groupBy('list_code')
            ->selectRaw('list_code, max(list_name) as name')
            ->pluck('name', 'list_code');
    }

    private function clean(?string $value): ?string
    {
        $value = $value === null ? null : trim(preg_replace('/\s+/u', ' ', str_replace("\u{00a0}", ' ', $value)));

        return $value === '' ? null : $value;
    }

    private function company(Request $request): string
    {
        $company = (string) $request->input('company', $request->query('company', ''));
        $access = $company === '' ? null : $request->user()->companies()
            ->where('company_id', $company)
            ->where('active', true)
            ->first();

        abort_unless($access, 403, 'No tienes acceso a esta compañía.');
        abort_unless(self::canView($request->user(), $access->permissions), 403, 'No tienes permiso para ver los clientes.');

        return $company;
    }

    private function baseCompany(string $company): string
    {
        return config('sigcom.erp_base_company')[$company] ?? $company;
    }

    private function iso(?string $value): ?string
    {
        return $value ? CarbonImmutable::parse($value)->setTimezone(self::TIMEZONE)->toIso8601String() : null;
    }
}
