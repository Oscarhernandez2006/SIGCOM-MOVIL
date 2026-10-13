<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/**
 * Listas de precios (Catálogo): lectura directa de price_list_items; el PDF y la
 * sincronización con Siesa pasan por la web, igual que /admin/listas-precios.
 */
class PriceListController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    public const PERMISSION = '/admin/listas-precios';

    public function __construct(private readonly SigcomWebClient $web) {}

    public function index(Request $request): JsonResponse
    {
        $company = $this->company($request);
        $base = $this->baseCompany($company);

        $clients = DB::table('client_records')
            ->where('company_id', $base)
            ->whereNotNull('price_list')
            ->groupBy('price_list')
            ->selectRaw('price_list, count(distinct code) as count')
            ->pluck('count', 'price_list');

        $lists = DB::table('price_list_items')
            ->where('company_id', $base)
            ->groupBy('list_code')
            ->orderBy('list_code')
            ->selectRaw('list_code, max(list_name) as list_name, count(*) as items, max(updated_at) as updated_at')
            ->get()
            ->map(fn ($l) => [
                'code' => $l->list_code,
                'name' => $l->list_name,
                'items' => (int) $l->items,
                'clients' => (int) ($clients[$l->list_code] ?? 0),
                'updated_at' => $this->iso($l->updated_at),
            ]);

        return response()->json([
            'lists' => $lists,
            'can_sync' => $request->user()->role === 'admin',
        ]);
    }

    public function items(Request $request, string $code): JsonResponse
    {
        $company = $this->company($request);

        $items = DB::table('price_list_items')
            ->where('company_id', $this->baseCompany($company))
            ->where('list_code', $code)
            ->orderBy('product_name')
            ->get(['reference', 'product_name', 'unit_of_measure', 'price'])
            ->map(fn ($i) => [
                'sku' => $i->reference,
                'name' => $i->product_name,
                'unit' => $i->unit_of_measure,
                'price' => (float) $i->price,
            ]);
        abort_if($items->isEmpty(), 404, 'Lista de precios no encontrada.');

        return response()->json($items);
    }

    public function pdf(Request $request, string $code): Response
    {
        $company = $this->company($request);
        $pdf = $this->web->download($request->user(), $company, '/price-lists/'.rawurlencode($code).'/pdf');
        $date = CarbonImmutable::now(self::TIMEZONE)->toDateString();

        return response($pdf, 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="lista-precios-'.$code.'-'.$date.'.pdf"',
        ]);
    }

    /** Trae las listas de Siesa y reemplaza las de la compañía (solo administradores). */
    public function sync(Request $request): JsonResponse
    {
        $company = $this->company($request);
        abort_unless($request->user()->role === 'admin', 403, 'Solo un administrador puede sincronizar las listas.');
        $result = $this->web->call($request->user(), $company, 'POST', '/price-lists/sync') ?? [];

        return response()->json([
            'lists' => (int) ($result['lists'] ?? 0),
            'created' => (int) ($result['created'] ?? 0),
            'updated' => (int) ($result['updated'] ?? 0),
            'removed' => (int) ($result['removed'] ?? 0),
            'total' => (int) ($result['total'] ?? 0),
        ]);
    }

    /** Igual que la web: admin o permiso /admin/listas-precios en la compañía. */
    public static function canView(User $user, ?array $permissions): bool
    {
        return $user->role === 'admin' || in_array(self::PERMISSION, $permissions ?? [], true);
    }

    private function company(Request $request): string
    {
        $company = (string) $request->input('company', $request->query('company', ''));
        $access = $company === '' ? null : $request->user()->companies()
            ->where('company_id', $company)
            ->where('active', true)
            ->first();

        abort_unless($access, 403, 'No tienes acceso a esta compañía.');
        abort_unless(self::canView($request->user(), $access->permissions), 403, 'No tienes permiso para ver las listas de precios.');

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
