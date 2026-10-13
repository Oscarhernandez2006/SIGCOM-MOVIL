<?php

namespace Tests\Unit;

use App\Services\ErpSalesService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class CarnesFriasSalesTest extends TestCase
{
    public function test_matches_erp_seller_names_by_words(): void
    {
        $this->assertTrue(ErpSalesService::sameSellerName('JOEL PAVA', 'PAVA CASTRO JOEL'));
        $this->assertTrue(ErpSalesService::sameSellerName('Camila Schoonewolf', 'SCHOONEWOLFF OROZCO CAMILA'));
        $this->assertTrue(ErpSalesService::sameSellerName('Linda Medrano', 'MEDRANO MARTÍNEZ LINDA'));
        $this->assertFalse(ErpSalesService::sameSellerName('JOEL PAVA', 'MEDRANO MARTINEZ LINDA'));
    }

    public function test_uses_carnes_frias_endpoint_and_groups_by_erp_category(): void
    {
        config(['sigcom.erp.base_url' => 'https://erp.test', 'sigcom.erp.cache_seconds' => 0]);
        Http::fake([
            'erp.test/ventas/vendedor-productos-carnesfrias*' => Http::response(['data' => [
                ['dia' => '2026-10-02', 'nit_vendedor' => '1', 'razon_social_vendedor' => 'A', 'categoria' => 'PRODUCTO TERMINADO ',
                    'referencia_producto' => '6100 ', 'descripcion_producto' => 'BUTI EXPRESS', 'kilos' => 25, 'total_facturas' => 1000, 'costo_total' => 400],
                ['dia' => '2026-10-02', 'nit_vendedor' => '1', 'razon_social_vendedor' => 'A', 'categoria' => 'SERVICIO',
                    'referencia_producto' => '99001', 'descripcion_producto' => 'SERVICIO TRANSPORTE', 'kilos' => 1, 'total_facturas' => 500, 'costo_total' => 0],
            ], 'has_more' => false]),
        ]);

        $summary = app(ErpSalesService::class)->summary('8', [], ['nits' => [], 'names' => []], '2026-10-01', '2026-10-05');

        $this->assertSame(1000.0, $summary['revenue']);
        $this->assertSame(25.0, $summary['kilos']);
        $this->assertSame(['Producto Terminado'], array_column($summary['categories'], 'category'));
        Http::assertNotSent(fn (Request $r) => str_contains($r->url(), 'dashboard-comercial'));
    }
}
