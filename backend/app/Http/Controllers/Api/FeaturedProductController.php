<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\SigcomWebClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Productos estrella (Catálogo): los que se recomiendan en cada pedido de cortes.
 * Lectura directa de featured_product/products; marcar y quitar pasa por la web.
 */
class FeaturedProductController extends Controller
{
    public const PERMISSION = '/admin/productos-estrella';

    public function __construct(private readonly SigcomWebClient $web) {}

    public function index(Request $request): JsonResponse
    {
        $company = $this->company($request);

        $featured = DB::table('featured_product as f')
            ->leftJoin('products as p', fn ($j) => $j
                ->on('p.sku', '=', 'f.sku')
                ->where('p.company_id', $company)
                ->where('p.type', 'corte'))
            ->where('f.company_id', $this->baseCompany($company))
            ->orderBy('f.name')
            ->get(['f.sku', 'f.name', 'p.unit_of_measure', 'p.stock', 'p.category', 'p.active'])
            ->map(fn ($f) => [
                'sku' => $f->sku,
                'name' => $f->name,
                'unit' => $f->unit_of_measure,
                'stock' => $f->stock === null ? null : (float) $f->stock,
                'category' => $f->category,
                'in_catalog' => (bool) $f->active,
            ]);

        return response()->json($featured);
    }

    /** Productos de cortes activos para elegir, como el selector de la web. */
    public function catalog(Request $request): JsonResponse
    {
        $company = $this->company($request);

        $products = DB::table('products')
            ->where('company_id', $company)
            ->where('type', 'corte')
            ->where('active', true)
            ->orderBy('name')
            ->get(['sku', 'name', 'unit_of_measure', 'stock', 'category'])
            ->map(fn ($p) => [
                'sku' => $p->sku,
                'name' => $p->name,
                'unit' => $p->unit_of_measure,
                'stock' => (float) $p->stock,
                'category' => $p->category,
                'in_catalog' => true,
            ]);

        return response()->json($products);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'sku' => ['required', 'string', 'max:50'],
            'name' => ['nullable', 'string', 'max:200'],
        ]);
        $company = $this->company($request);
        $this->web->call($request->user(), $company, 'POST', '/featured-products', array_filter([
            'sku' => trim($data['sku']),
            'name' => trim((string) ($data['name'] ?? '')),
        ]));

        return response()->json(['message' => 'Producto marcado como estrella.'], 201);
    }

    public function destroy(Request $request, string $sku): JsonResponse
    {
        $company = $this->company($request);
        $this->web->call($request->user(), $company, 'DELETE', '/featured-products?sku='.rawurlencode($sku));

        return response()->json(['message' => 'Producto retirado de estrella.']);
    }

    /** Igual que el menú de la web: admin o permiso /admin/productos-estrella en la compañía. */
    public static function canManage(User $user, ?array $permissions): bool
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
        abort_unless(self::canManage($request->user(), $access->permissions), 403, 'No tienes permiso para gestionar productos estrella.');

        return $company;
    }

    private function baseCompany(string $company): string
    {
        return config('sigcom.erp_base_company')[$company] ?? $company;
    }
}
